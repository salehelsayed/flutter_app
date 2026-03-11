import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
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
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';

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

class _InviteInboxPage {
  final List<Map<String, dynamic>> messages;
  final String nextCursor;

  const _InviteInboxPage(this.messages, this.nextCursor);
}

class _CursorInboxInviteBridge extends PassthroughCryptoBridge {
  final Map<String, _InviteInboxPage> pages = {};

  void addPage(
    String groupId,
    String cursor,
    List<Map<String, dynamic>> messages,
    String nextCursor,
  ) {
    pages['$groupId:$cursor'] = _InviteInboxPage(messages, nextCursor);
  }

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;

    if (cmd == 'group:inboxRetrieveCursor') {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);

      if (responses.containsKey(cmd)) {
        return jsonEncode(responses[cmd]!);
      }

      final payload = parsed['payload'] as Map<String, dynamic>;
      final groupId = payload['groupId'] as String;
      final cursor = payload['cursor'] as String? ?? '';
      final page = pages['$groupId:$cursor'];
      return jsonEncode({
        'ok': true,
        'messages': page?.messages ?? const <Map<String, dynamic>>[],
        'cursor': page?.nextCursor ?? '',
      });
    }

    return super.send(message);
  }
}

class _TimeoutInboxRetrieveBridge extends _CursorInboxInviteBridge {
  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == 'group:inboxRetrieveCursor') {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);
      throw TimeoutException('Simulated inbox timeout');
    }
    return super.send(message);
  }
}

void main() {
  late StreamController<ChatMessage> incomingController;
  late InMemoryGroupRepository groupRepo;
  late InMemoryGroupMessageRepository msgRepo;
  late InMemoryMediaAttachmentRepository mediaRepo;
  late FakeContactRepository contactRepo;
  late _CursorInboxInviteBridge bridge;
  late GroupInviteListener listener;

  setUp(() {
    incomingController = StreamController<ChatMessage>.broadcast();
    groupRepo = InMemoryGroupRepository();
    msgRepo = InMemoryGroupMessageRepository();
    mediaRepo = InMemoryMediaAttachmentRepository();
    contactRepo = FakeContactRepository();
    bridge = _CursorInboxInviteBridge();
    contactRepo.seed([_aliceContact()]);

    listener = GroupInviteListener(
      groupInviteStream: incomingController.stream,
      groupRepo: groupRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      msgRepo: msgRepo,
      mediaAttachmentRepo: mediaRepo,
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
    test(
      'calling start twice does not create duplicate subscriptions',
      () async {
        listener.start();
        listener.start(); // Second call should be no-op

        final groups = <GroupModel>[];
        listener.groupJoinedStream.listen(groups.add);

        incomingController.add(_makeV1InviteMessage());

        await Future.delayed(const Duration(milliseconds: 100));

        // Should only get one emission, not two
        expect(groups, hasLength(1));
      },
    );

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
      bridge.addPage('grp-abc123', '', [
        {
          'from': '12D3KooWAlice',
          'message': jsonEncode({
            'groupId': 'grp-abc123',
            'messageId': 'offline-msg-1',
            'senderId': '12D3KooWAlice',
            'senderUsername': 'Alice',
            'keyEpoch': 1,
            'text': '',
            'media': [
              {
                'id': 'blob-offline-1',
                'mime': 'image/jpeg',
                'size': 4096,
                'mediaType': 'image',
                'downloadStatus': 'pending',
                'createdAt': '2026-03-02T13:00:00.000Z',
              },
            ],
            'timestamp': '2026-03-02T13:00:00.000Z',
          }),
          'timestamp': 1709384400000,
        },
        {
          'from': '12D3KooWAlice',
          'message': jsonEncode({
            'groupId': 'grp-abc123',
            'messageId': 'offline-msg-2',
            'senderId': '12D3KooWAlice',
            'senderUsername': 'Alice',
            'keyEpoch': 1,
            'text': 'Reply to the missed photo',
            'quotedMessageId': 'offline-msg-1',
            'timestamp': '2026-03-02T13:01:00.000Z',
          }),
          'timestamp': 1709384460000,
        },
      ], '');

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
      expect(messages.map((m) => m.id).toSet(), {
        'offline-msg-1',
        'offline-msg-2',
      });
      expect(messages.every((m) => m.isIncoming), isTrue);
      final quotedReply = messages.firstWhere(
        (m) => m.text == 'Reply to the missed photo',
      );
      expect(quotedReply.quotedMessageId, 'offline-msg-1');

      final attachments = await mediaRepo.getAttachmentsForMessage(
        'offline-msg-1',
      );
      expect(attachments, hasLength(1));
      expect(attachments.first.id, 'blob-offline-1');
      expect(bridge.commandLog, contains('group:inboxRetrieveCursor'));
    });

    test(
      'drains all invite inbox cursor pages when backlog exceeds one page',
      () async {
        final firstPage = List<Map<String, dynamic>>.generate(50, (index) {
          final messageNumber = index + 1;
          return {
            'from': '12D3KooWAlice',
            'message': jsonEncode({
              'groupId': 'grp-abc123',
              'messageId': 'offline-msg-$messageNumber',
              'senderId': '12D3KooWAlice',
              'senderUsername': 'Alice',
              'keyEpoch': 1,
              'text': 'Offline backlog $messageNumber',
              'timestamp': DateTime.utc(
                2026,
                3,
                2,
                13,
                messageNumber,
              ).toIso8601String(),
            }),
            'timestamp': 1709384400000 + (messageNumber * 60000),
          };
        });
        bridge.addPage('grp-abc123', '', firstPage, 'cursor-page-2');
        bridge.addPage('grp-abc123', 'cursor-page-2', [
          {
            'from': '12D3KooWAlice',
            'message': jsonEncode({
              'groupId': 'grp-abc123',
              'messageId': 'offline-msg-51',
              'senderId': '12D3KooWAlice',
              'senderUsername': 'Alice',
              'keyEpoch': 1,
              'text': 'Quoted backlog reply from page two',
              'quotedMessageId': 'offline-msg-1',
              'timestamp': '2026-03-02T14:00:00.000Z',
            }),
            'timestamp': 1709388000000,
          },
        ], '');

        listener.start();

        final groups = <GroupModel>[];
        listener.groupJoinedStream.listen(groups.add);

        incomingController.add(_makeV1InviteMessage());

        await Future.delayed(const Duration(milliseconds: 250));

        final retrieveCmds = bridge.sentMessages
            .map((message) => jsonDecode(message) as Map<String, dynamic>)
            .where((message) => message['cmd'] == 'group:inboxRetrieveCursor')
            .toList();
        final pagedReply = await msgRepo.getMessage('offline-msg-51');

        expect(groups, hasLength(1));
        expect(msgRepo.count, 51);
        expect(pagedReply, isNotNull);
        expect(pagedReply!.quotedMessageId, 'offline-msg-1');
        expect(retrieveCmds, hasLength(2));
        expect(retrieveCmds[0]['payload']['cursor'], '');
        expect(retrieveCmds[1]['payload']['cursor'], 'cursor-page-2');
      },
    );

    // --- Cycle 6.10 ---
    test('drain error does not prevent group from being broadcast', () async {
      // Make inboxRetrieve fail
      bridge.responses['group:inboxRetrieveCursor'] = {
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

    test(
      'timeout during offline inbox drain logs an error instead of a done event',
      () async {
        final output = <String>[];
        final originalDebugPrint = debugPrint;
        flowEventLoggingEnabled = true;
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message != null) output.add(message);
        };
        addTearDown(() {
          debugPrint = originalDebugPrint;
          flowEventLoggingEnabled = kDebugMode;
        });

        final timeoutBridge = _TimeoutInboxRetrieveBridge();
        final timeoutListener = GroupInviteListener(
          groupInviteStream: incomingController.stream,
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          bridge: timeoutBridge,
          msgRepo: msgRepo,
          mediaAttachmentRepo: mediaRepo,
          getOwnMlKemSecretKey: () async => 'mySecretKey',
        );
        addTearDown(timeoutListener.dispose);

        timeoutListener.start();

        final groups = <GroupModel>[];
        timeoutListener.groupJoinedStream.listen(groups.add);

        incomingController.add(_makeV1InviteMessage());

        await Future.delayed(const Duration(milliseconds: 200));

        final events = output
            .where((line) => line.startsWith('[FLOW] '))
            .map(
              (line) =>
                  jsonDecode(line.substring('[FLOW] '.length))
                      as Map<String, dynamic>,
            )
            .toList();

        expect(groups, hasLength(1));
        expect(msgRepo.count, 0);
        expect(timeoutBridge.commandLog, contains('group:inboxRetrieveCursor'));
        expect(
          events.any(
            (event) => event['event'] == 'GROUP_INVITE_DRAIN_INBOX_ERROR',
          ),
          isTrue,
        );
        expect(
          events.any(
            (event) => event['event'] == 'GROUP_INVITE_DRAIN_INBOX_DONE',
          ),
          isFalse,
        );
      },
    );
  });
}
