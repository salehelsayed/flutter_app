import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/group_invite_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

const _testGroupConfig = {
  'name': 'Book Club',
  'groupType': 'chat',
  'description': 'A group for book lovers',
  'members': [
    {
      'peerId': '12D3KooWAlice',
      'username': 'Alice',
      'role': 'admin',
      'publicKey': 'alicePubKey64',
      'mlKemPublicKey': 'aliceMlKem64',
    },
    {
      'peerId': '12D3KooWBob',
      'username': 'Bob',
      'role': 'writer',
      'publicKey': 'bobPubKey64',
      'mlKemPublicKey': 'bobMlKem64',
    },
  ],
  'createdBy': '12D3KooWAlice',
  'createdAt': '2026-03-02T00:00:00.000Z',
};

ContactModel _aliceContact({bool isBlocked = false}) {
  return ContactModel(
    peerId: '12D3KooWAlice',
    publicKey: 'alicePubKey64',
    rendezvous: '/ip4/0.0.0.0',
    username: 'Alice',
    signature: 'sig',
    scannedAt: '2026-01-01T00:00:00Z',
    mlKemPublicKey: 'aliceMlKem64',
    isBlocked: isBlocked,
    blockedAt: isBlocked ? '2026-01-01T00:00:00Z' : null,
  );
}

ChatMessage _makeV1InviteMessage({
  String groupId = 'grp-abc123',
  String senderPeerId = '12D3KooWAlice',
}) {
  final payload = GroupInvitePayload(
    id: 'invite-uuid-001',
    groupId: groupId,
    groupKey: 'base64GroupKey==',
    keyEpoch: 1,
    groupConfig: _testGroupConfig,
    senderPeerId: senderPeerId,
    senderUsername: 'Alice',
    timestamp: '2026-03-02T12:00:00.000Z',
  );
  return ChatMessage(
    from: senderPeerId,
    to: 'myPeerId',
    content: payload.toJson(),
    timestamp: DateTime.now().toUtc().toIso8601String(),
    isIncoming: true,
  );
}

ChatMessage _makeV2InviteMessage({
  String groupId = 'grp-abc123',
  String senderPeerId = '12D3KooWAlice',
}) {
  final payload = GroupInvitePayload(
    id: 'invite-uuid-001',
    groupId: groupId,
    groupKey: 'base64GroupKey==',
    keyEpoch: 1,
    groupConfig: _testGroupConfig,
    senderPeerId: senderPeerId,
    senderUsername: 'Alice',
    timestamp: '2026-03-02T12:00:00.000Z',
  );
  final innerJson = payload.toInnerJson();
  final envelope = GroupInvitePayload.buildEncryptedEnvelope(
    senderPeerId: senderPeerId,
    kem: 'fake-kem',
    ciphertext: innerJson,
    nonce: 'fake-nonce',
  );
  return ChatMessage(
    from: senderPeerId,
    to: 'myPeerId',
    content: envelope,
    timestamp: DateTime.now().toUtc().toIso8601String(),
    isIncoming: true,
  );
}

/// A bridge that returns ok=false for message.decrypt
class _FailDecryptBridge extends FakeBridge {
  @override
  Future<String> send(String message) async {
    sendCallCount++;
    lastSentMessage = message;

    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    lastCommand = cmd;

    if (cmd == 'message.decrypt') {
      return jsonEncode({
        'ok': false,
        'errorCode': 'DECRYPT_FAILED',
        'errorMessage': 'Cannot decrypt',
      });
    }

    return super.send(message);
  }
}

void main() {
  late StreamController<ChatMessage> incomingController;
  late InMemoryGroupRepository groupRepo;
  late InMemoryGroupMessageRepository msgRepo;
  late FakeContactRepository contactRepo;
  late PassthroughCryptoBridge bridge;
  late GroupInviteListener listener;

  setUp(() {
    incomingController = StreamController<ChatMessage>.broadcast();
    groupRepo = InMemoryGroupRepository();
    msgRepo = InMemoryGroupMessageRepository();
    contactRepo = FakeContactRepository();
    bridge = PassthroughCryptoBridge();
    contactRepo.seed([_aliceContact()]);

    listener = GroupInviteListener(
      groupInviteStream: incomingController.stream,
      groupRepo: groupRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      msgRepo: msgRepo,
      getOwnMlKemSecretKey: () async => 'mySecretKey',
    );
  });

  tearDown(() {
    listener.dispose();
    incomingController.close();
  });

  group('GroupInviteListener', () {
    // --- Cycle 6.1 ---
    test('processes v2 invite and broadcasts joined GroupModel', () async {
      listener.start();

      final groups = <GroupModel>[];
      listener.groupJoinedStream.listen(groups.add);

      incomingController.add(_makeV2InviteMessage());

      // Wait for async processing
      await Future.delayed(const Duration(milliseconds: 100));

      expect(groups, hasLength(1));
      expect(groups.first.id, equals('grp-abc123'));
      expect(groups.first.name, equals('Book Club'));

      // Group is persisted
      final storedGroup = await groupRepo.getGroup('grp-abc123');
      expect(storedGroup, isNotNull);

      // Bridge group:join was called
      expect(bridge.commandLog, contains('group:join'));
    });

    // --- Cycle 6.2 ---
    test('does not broadcast for invite from unknown sender', () async {
      contactRepo.seed([]); // No contacts

      listener.start();

      final groups = <GroupModel>[];
      listener.groupJoinedStream.listen(groups.add);

      incomingController.add(_makeV1InviteMessage());

      await Future.delayed(const Duration(milliseconds: 100));

      expect(groups, isEmpty);
      expect(groupRepo.groupCount, equals(0));
    });

    // --- Cycle 6.3 ---
    test('does not broadcast for invite to a group already joined', () async {
      // Pre-populate the group
      final existingGroup = GroupModel(
        id: 'grp-abc123',
        name: 'Already Joined',
        type: GroupType.chat,
        topicName: '/mknoon/group/grp-abc123',
        createdAt: DateTime.utc(2026, 1, 1),
        createdBy: '12D3KooWAlice',
        myRole: GroupRole.admin,
      );
      await groupRepo.saveGroup(existingGroup);

      listener.start();

      final groups = <GroupModel>[];
      listener.groupJoinedStream.listen(groups.add);

      incomingController.add(_makeV1InviteMessage());

      await Future.delayed(const Duration(milliseconds: 100));

      expect(groups, isEmpty);

      // Original group still intact
      final stored = await groupRepo.getGroup('grp-abc123');
      expect(stored!.name, equals('Already Joined'));
    });

    // --- Cycle 6.4 ---
    test('does not crash on decryption failure', () async {
      final failBridge = _FailDecryptBridge();
      final failListener = GroupInviteListener(
        groupInviteStream: incomingController.stream,
        groupRepo: groupRepo,
        contactRepo: contactRepo,
        bridge: failBridge,
        getOwnMlKemSecretKey: () async => 'mySecretKey',
      );
      failListener.start();

      final groups = <GroupModel>[];
      failListener.groupJoinedStream.listen(groups.add);

      incomingController.add(_makeV2InviteMessage());

      await Future.delayed(const Duration(milliseconds: 100));

      // Should not crash — just silently ignore
      expect(groups, isEmpty);

      failListener.dispose();
    });

    // --- Cycle 6.5 ---
    test('calling start twice does not create duplicate subscriptions',
        () async {
      listener.start();
      listener.start(); // Second call should be no-op

      final groups = <GroupModel>[];
      listener.groupJoinedStream.listen(groups.add);

      incomingController.add(_makeV1InviteMessage());

      await Future.delayed(const Duration(milliseconds: 100));

      // Should only get one emission, not two
      expect(groups, hasLength(1));
    });

    // --- Cycle 6.6 ---
    test('stop prevents further processing', () async {
      listener.start();
      listener.stop();

      final groups = <GroupModel>[];
      listener.groupJoinedStream.listen(groups.add);

      incomingController.add(_makeV1InviteMessage());

      await Future.delayed(const Duration(milliseconds: 100));

      expect(groups, isEmpty);
    });

    // --- Cycle 6.7 ---
    test('dispose closes groupJoinedStream', () async {
      // Should not throw
      listener.dispose();
    });

    // --- Cycle 6.8 ---
    test('does not process invite from blocked contact', () async {
      contactRepo.seed([_aliceContact(isBlocked: true)]);

      listener.start();

      final groups = <GroupModel>[];
      listener.groupJoinedStream.listen(groups.add);

      incomingController.add(_makeV1InviteMessage());

      await Future.delayed(const Duration(milliseconds: 100));

      expect(groups, isEmpty);
      expect(groupRepo.groupCount, equals(0));
    });

    // --- Cycle 6.9 ---
    test('drains offline inbox after successful invite', () async {
      // Pre-configure bridge to return stored messages in relay format:
      // {from, message (JSON string), timestamp}
      bridge.responses['group:inboxRetrieve'] = {
        'ok': true,
        'messages': [
          {
            'from': '12D3KooWAlice',
            'message': jsonEncode({
              'groupId': 'grp-abc123',
              'senderId': '12D3KooWAlice',
              'senderUsername': 'Alice',
              'keyEpoch': 1,
              'text': 'Missed while offline',
              'timestamp': '2026-03-02T13:00:00.000Z',
            }),
            'timestamp': 1709384400000,
          },
          {
            'from': '12D3KooWAlice',
            'message': jsonEncode({
              'groupId': 'grp-abc123',
              'senderId': '12D3KooWAlice',
              'senderUsername': 'Alice',
              'keyEpoch': 1,
              'text': 'Another offline message',
              'timestamp': '2026-03-02T13:01:00.000Z',
            }),
            'timestamp': 1709384460000,
          },
        ],
      };

      listener.start();

      final groups = <GroupModel>[];
      listener.groupJoinedStream.listen(groups.add);

      incomingController.add(_makeV1InviteMessage());

      await Future.delayed(const Duration(milliseconds: 200));

      // Group was joined
      expect(groups, hasLength(1));

      // Offline inbox messages were drained and saved
      expect(msgRepo.count, 2);
      final messages = await msgRepo.getMessagesPage('grp-abc123');
      expect(messages.map((m) => m.text).toSet(),
          {'Missed while offline', 'Another offline message'});
      expect(messages.every((m) => m.isIncoming), isTrue);
    });

    // --- Cycle 6.10 ---
    test('drain error does not prevent group from being broadcast', () async {
      // Make inboxRetrieve fail
      bridge.responses['group:inboxRetrieve'] = {
        'ok': false,
        'errorCode': 'RELAY_UNREACHABLE',
        'errorMessage': 'Cannot reach relay',
      };

      listener.start();

      final groups = <GroupModel>[];
      listener.groupJoinedStream.listen(groups.add);

      incomingController.add(_makeV1InviteMessage());

      await Future.delayed(const Duration(milliseconds: 200));

      // Group should still be broadcast despite drain error
      expect(groups, hasLength(1));
      expect(groups.first.id, 'grp-abc123');

      // No messages saved (drain failed)
      expect(msgRepo.count, 0);
    });
  });
}
