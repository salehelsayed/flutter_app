import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/group_invite_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../shared/fakes/in_memory_pending_group_invite_repository.dart';

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
  Map<String, dynamic>? groupConfig,
}) {
  final payload = GroupInvitePayload(
    id: 'invite-uuid-001',
    groupId: groupId,
    groupKey: 'base64GroupKey==',
    keyEpoch: 1,
    groupConfig: groupConfig ?? _testGroupConfig,
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
  late InMemoryMediaAttachmentRepository mediaRepo;
  late InMemoryPendingGroupInviteRepository pendingInviteRepo;
  late FakeContactRepository contactRepo;
  late FakeBridge bridge;
  late GroupInviteListener listener;

  setUp(() {
    incomingController = StreamController<ChatMessage>.broadcast();
    groupRepo = InMemoryGroupRepository();
    msgRepo = InMemoryGroupMessageRepository();
    mediaRepo = InMemoryMediaAttachmentRepository();
    pendingInviteRepo = InMemoryPendingGroupInviteRepository();
    contactRepo = FakeContactRepository();
    bridge = PassthroughCryptoBridge();
    contactRepo.seed([_aliceContact()]);

    listener = GroupInviteListener(
      groupInviteStream: incomingController.stream,
      groupRepo: groupRepo,
      pendingInviteRepo: pendingInviteRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      msgRepo: msgRepo,
      mediaAttachmentRepo: mediaRepo,
      getOwnMlKemSecretKey: () async => 'mySecretKey',
    );
  });

  tearDown(() async {
    listener.dispose();
    await incomingController.close();
  });

  group('GroupInviteListener', () {
    test(
      'stores a valid v2 invite as pending and does not join immediately',
      () async {
        listener.start();

        final invites = <PendingGroupInvite>[];
        listener.pendingInviteStream.listen(invites.add);

        incomingController.add(_makeV2InviteMessage());
        await Future.delayed(const Duration(milliseconds: 100));

        expect(invites, hasLength(1));
        expect(invites.first.groupId, 'grp-abc123');
        expect(invites.first.groupName, 'Book Club');
        expect(invites.first.groupDescription, 'A group for book lovers');
        expect(
          await pendingInviteRepo.getPendingInvite('grp-abc123'),
          isNotNull,
        );
        expect(await groupRepo.getGroup('grp-abc123'), isNull);
        expect(bridge.commandLog, isNot(contains('group:join')));
      },
    );

    test('does not store pending invite from unknown sender', () async {
      contactRepo.seed([]);
      listener.start();

      final invites = <PendingGroupInvite>[];
      listener.pendingInviteStream.listen(invites.add);

      incomingController.add(_makeV1InviteMessage());
      await Future.delayed(const Duration(milliseconds: 100));

      expect(invites, isEmpty);
      expect(pendingInviteRepo.count, 0);
      expect(groupRepo.groupCount, 0);
    });

    test('does not store pending invite for an already joined group', () async {
      await groupRepo.saveGroup(
        GroupModel(
          id: 'grp-abc123',
          name: 'Already Joined',
          type: GroupType.chat,
          topicName: '/mknoon/group/grp-abc123',
          createdAt: DateTime.utc(2026, 1, 1),
          createdBy: '12D3KooWAlice',
          myRole: GroupRole.admin,
        ),
      );

      listener.start();
      final invites = <PendingGroupInvite>[];
      listener.pendingInviteStream.listen(invites.add);

      incomingController.add(_makeV1InviteMessage());
      await Future.delayed(const Duration(milliseconds: 100));

      expect(invites, isEmpty);
      expect(pendingInviteRepo.count, 0);
      expect((await groupRepo.getGroup('grp-abc123'))!.name, 'Already Joined');
    });

    test('does not crash on decryption failure', () async {
      final failListener = GroupInviteListener(
        groupInviteStream: incomingController.stream,
        groupRepo: groupRepo,
        pendingInviteRepo: pendingInviteRepo,
        contactRepo: contactRepo,
        bridge: _FailDecryptBridge(),
        getOwnMlKemSecretKey: () async => 'mySecretKey',
      );
      addTearDown(failListener.dispose);
      failListener.start();

      final invites = <PendingGroupInvite>[];
      failListener.pendingInviteStream.listen(invites.add);

      incomingController.add(_makeV2InviteMessage());
      await Future.delayed(const Duration(milliseconds: 100));

      expect(invites, isEmpty);
      expect(pendingInviteRepo.count, 0);
    });

    test(
      'calling start twice does not create duplicate subscriptions',
      () async {
        listener.start();
        listener.start();

        final invites = <PendingGroupInvite>[];
        listener.pendingInviteStream.listen(invites.add);

        incomingController.add(_makeV1InviteMessage());
        await Future.delayed(const Duration(milliseconds: 100));

        expect(invites, hasLength(1));
        expect(pendingInviteRepo.count, 1);
      },
    );

    test('stop prevents further processing', () async {
      listener.start();
      listener.stop();

      incomingController.add(_makeV1InviteMessage());
      await Future.delayed(const Duration(milliseconds: 100));

      expect(pendingInviteRepo.count, 0);
    });

    test('dispose is safe after start', () {
      listener.start();
      listener.dispose();
    });

    test('does not process invite from blocked contact', () async {
      contactRepo.seed([_aliceContact(isBlocked: true)]);
      listener.start();

      incomingController.add(_makeV1InviteMessage());
      await Future.delayed(const Duration(milliseconds: 100));

      expect(pendingInviteRepo.count, 0);
      expect(groupRepo.groupCount, 0);
    });

    test(
      'duplicate pending invite replaces the existing preview row',
      () async {
        listener.start();

        incomingController.add(_makeV1InviteMessage());
        await Future.delayed(const Duration(milliseconds: 100));

        final refreshedConfig = {
          ..._testGroupConfig,
          'name': 'Renamed Book Club',
          'description': 'Updated invite preview',
        };
        incomingController.add(
          _makeV1InviteMessage(groupConfig: refreshedConfig),
        );
        await Future.delayed(const Duration(milliseconds: 100));

        expect(pendingInviteRepo.count, 1);
        final stored = await pendingInviteRepo.getPendingInvite('grp-abc123');
        expect(stored, isNotNull);
        expect(stored!.groupName, 'Renamed Book Club');
        expect(stored.groupDescription, 'Updated invite preview');
      },
    );
  });
}
