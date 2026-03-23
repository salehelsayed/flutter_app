import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';

/// A bridge that delays group:publish by [delay] to test concurrency.
class _SlowPublishBridge extends FakeBridge {
  final Duration delay;
  _SlowPublishBridge({this.delay = const Duration(milliseconds: 200)});

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;

    if (cmd == 'group:publish') {
      await Future<void>.delayed(delay);
    }

    return super.send(message);
  }
}

/// A bridge that returns ok: false for group:publish but tracks all commands.
class _FailPublishBridge extends FakeBridge {
  _FailPublishBridge() {
    responses['group:publish'] = {'ok': false, 'errorCode': 'PUBLISH_FAILED'};
  }
}

/// A bridge that throws on group:inboxStore commands.
class _InboxStoreFailBridge extends FakeBridge {
  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;

    if (cmd == 'group:inboxStore') {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);
      throw Exception('Relay inbox store failed');
    }

    return super.send(message);
  }
}

Map<String, dynamic> _lastGroupInboxStorePayload(FakeBridge bridge) {
  final inboxMsg = bridge.sentMessages.lastWhere(
    (m) => (jsonDecode(m) as Map)['cmd'] == 'group:inboxStore',
  );
  return (jsonDecode(inboxMsg) as Map)['payload'] as Map<String, dynamic>;
}

void main() {
  late FakeBridge bridge;
  late InMemoryGroupRepository groupRepo;
  late InMemoryGroupMessageRepository msgRepo;

  final testGroup = GroupModel(
    id: 'group-1',
    name: 'Test Group',
    type: GroupType.chat,
    topicName: 'group-topic-1',
    createdAt: DateTime.now().toUtc(),
    createdBy: 'peer-1',
    myRole: GroupRole.admin,
  );

  setUp(() async {
    bridge = FakeBridge();
    groupRepo = InMemoryGroupRepository();
    msgRepo = InMemoryGroupMessageRepository();

    await groupRepo.saveGroup(testGroup);

    bridge.responses['group:publish'] = {'ok': true, 'messageId': 'msg-123'};
  });

  test('sends message successfully', () async {
    final (result, message) = await sendGroupMessage(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      text: 'Hello group!',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Alice',
    );

    expect(result, SendGroupMessageResult.success);
    expect(message, isNotNull);
    expect(message!.text, 'Hello group!');
    expect(message.isIncoming, false);
    expect(message.status, 'sent');
  });

  test('returns groupNotFound for unknown group', () async {
    final (result, message) = await sendGroupMessage(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'nonexistent',
      text: 'Hello',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Alice',
    );

    expect(result, SendGroupMessageResult.groupNotFound);
    expect(message, isNull);
  });

  test('returns unauthorized for non-admin in announcement group', () async {
    final announcementGroup = GroupModel(
      id: 'group-announce',
      name: 'Announcements',
      type: GroupType.announcement,
      topicName: 'group-topic-announce',
      createdAt: DateTime.now().toUtc(),
      createdBy: 'peer-admin',
      myRole: GroupRole.member,
    );
    await groupRepo.saveGroup(announcementGroup);

    final (result, message) = await sendGroupMessage(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-announce',
      text: 'Hello',
      senderPeerId: 'peer-2',
      senderPublicKey: 'pk-2',
      senderPrivateKey: 'sk-2',
      senderUsername: 'Bob',
    );

    expect(result, SendGroupMessageResult.unauthorized);
    expect(message, isNull);
  });

  test('saves message to repo on success', () async {
    await sendGroupMessage(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      text: 'Hello group!',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Alice',
    );

    expect(msgRepo.count, 1);
    final latest = await msgRepo.getLatestMessage('group-1');
    expect(latest, isNotNull);
    expect(latest!.text, 'Hello group!');
  });

  test(
    'propagates quotedMessageId through publish, inbox, and saved message',
    () async {
      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Replying in group',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        quotedMessageId: 'msg-parent-1',
      );

      expect(result, SendGroupMessageResult.success);
      expect(message, isNotNull);
      expect(message!.quotedMessageId, 'msg-parent-1');

      final publishMsg = bridge.sentMessages.firstWhere(
        (m) => (jsonDecode(m) as Map)['cmd'] == 'group:publish',
      );
      final publishPayload =
          (jsonDecode(publishMsg) as Map)['payload'] as Map<String, dynamic>;
      expect(publishPayload['quotedMessageId'], 'msg-parent-1');

      final inboxMsg = bridge.sentMessages.firstWhere(
        (m) => (jsonDecode(m) as Map)['cmd'] == 'group:inboxStore',
      );
      final inboxPayload =
          (jsonDecode(inboxMsg) as Map)['payload'] as Map<String, dynamic>;
      final innerPayload =
          jsonDecode(inboxPayload['message'] as String) as Map<String, dynamic>;
      expect(innerPayload['quotedMessageId'], 'msg-parent-1');

      final saved = await msgRepo.getMessage(message.id);
      expect(saved, isNotNull);
      expect(saved!.quotedMessageId, 'msg-parent-1');
    },
  );

  test(
    'strips dangerous bidi controls and preserves safe markers across publish, inbox, save, and push body',
    () async {
      const rawText = 'Hello\u202E\u200E group\u200F!';
      const sanitizedText = 'Hello\u200E group\u200F!';

      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: rawText,
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
      );

      expect(result, SendGroupMessageResult.success);
      expect(message, isNotNull);
      expect(message!.text, sanitizedText);

      final saved = await msgRepo.getMessage(message.id);
      expect(saved, isNotNull);
      expect(saved!.text, sanitizedText);

      final publishMsg = bridge.sentMessages.firstWhere(
        (m) => (jsonDecode(m) as Map)['cmd'] == 'group:publish',
      );
      final publishPayload =
          (jsonDecode(publishMsg) as Map)['payload'] as Map<String, dynamic>;
      expect(publishPayload['text'], sanitizedText);
      expect(publishPayload['text'], isNot(contains('\u202E')));

      final inboxPayload = _lastGroupInboxStorePayload(bridge);
      expect(inboxPayload['pushBody'], equals('Alice: $sanitizedText'));
      expect(inboxPayload['pushBody'], isNot(contains('\u202E')));

      final innerPayload =
          jsonDecode(inboxPayload['message'] as String) as Map<String, dynamic>;
      expect(innerPayload['text'], sanitizedText);
    },
  );

  test('stores message in relay inbox on publish', () async {
    await sendGroupMessage(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      text: 'Hello group!',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Alice',
    );

    // Both operations should run (order is non-deterministic due to parallelism)
    expect(bridge.commandLog, contains('group:publish'));
    expect(bridge.commandLog, contains('group:inboxStore'));
  });

  test(
    'group send loads members and excludes sender from push recipients',
    () async {
      final joinedAt = DateTime.utc(2026, 1, 1);
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-1',
          username: 'Alice',
          role: MemberRole.admin,
          joinedAt: joinedAt,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-2',
          username: 'Bob',
          role: MemberRole.writer,
          joinedAt: joinedAt.add(const Duration(seconds: 1)),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-3',
          username: 'Cara',
          role: MemberRole.reader,
          joinedAt: joinedAt.add(const Duration(seconds: 2)),
        ),
      );

      await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Hello group!',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
      );

      final inboxPayload = _lastGroupInboxStorePayload(bridge);
      expect(
        inboxPayload['recipientPeerIds'],
        unorderedEquals(['peer-2', 'peer-3']),
      );
      expect(inboxPayload['pushTitle'], equals('Test Group'));
      expect(inboxPayload['pushBody'], equals('Alice: Hello group!'));
    },
  );

  test('text group message builds preview body like Sender: hello', () async {
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-2',
        username: 'Bob',
        role: MemberRole.writer,
        joinedAt: DateTime.utc(2026, 1, 2),
      ),
    );

    await sendGroupMessage(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      text: 'hello',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Sender',
    );

    final inboxPayload = _lastGroupInboxStorePayload(bridge);
    expect(inboxPayload['pushBody'], equals('Sender: hello'));
  });

  test(
    'media-only group message builds a non-empty fallback preview body',
    () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-2',
          username: 'Bob',
          role: MemberRole.writer,
          joinedAt: DateTime.utc(2026, 1, 2),
        ),
      );

      final voiceAttachment = MediaAttachment(
        id: 'att-voice',
        messageId: '',
        mime: 'audio/mp4',
        size: 48000,
        mediaType: 'audio',
        downloadStatus: 'done',
        createdAt: DateTime.now().toUtc().toIso8601String(),
        localPath: '/tmp/voice.m4a',
        durationMs: 3000,
        waveform: [0.1, 0.5, 0.8, 0.3],
      );

      await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: '',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        mediaAttachments: [voiceAttachment],
      );

      final inboxPayload = _lastGroupInboxStorePayload(bridge);
      expect((inboxPayload['pushBody'] as String), isNotEmpty);
      expect(inboxPayload['pushBody'], contains('Alice'));
    },
  );

  test(
    'empty recipient list does not crash and still stores group inbox',
    () async {
      final (result, _) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Only me here',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
      );

      expect(result, SendGroupMessageResult.success);
      expect(bridge.commandLog, contains('group:inboxStore'));

      final inboxPayload = _lastGroupInboxStorePayload(bridge);
      expect(inboxPayload.containsKey('recipientPeerIds'), isFalse);
    },
  );

  test('send succeeds even if inbox store throws', () async {
    final failBridge = _InboxStoreFailBridge();
    failBridge.responses['group:publish'] = {
      'ok': true,
      'messageId': 'msg-123',
    };

    final (result, message) = await sendGroupMessage(
      bridge: failBridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      text: 'Hello!',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Alice',
    );

    // Send should still succeed despite inbox store failure
    expect(result, SendGroupMessageResult.success);
    expect(message, isNotNull);
    expect(failBridge.commandLog, contains('group:publish'));
    expect(failBridge.commandLog, contains('group:inboxStore'));
  });

  test('returns error when publish returns ok: false', () async {
    bridge.responses['group:publish'] = {
      'ok': false,
      'errorCode': 'PUBLISH_FAILED',
    };

    final (result, message) = await sendGroupMessage(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      text: 'Hello!',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Alice',
    );

    expect(result, SendGroupMessageResult.error);
    expect(message, isNull);
  });

  test('returns error when publish throws exception', () async {
    bridge.throwOnSend = true;

    final (result, message) = await sendGroupMessage(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      text: 'Hello!',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Alice',
    );

    expect(result, SendGroupMessageResult.error);
    expect(message, isNull);
  });

  test('does not persist message when publish fails', () async {
    bridge.responses['group:publish'] = {
      'ok': false,
      'errorCode': 'PUBLISH_FAILED',
    };

    final (result, message) = await sendGroupMessage(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      text: 'Hello!',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Alice',
    );

    expect(result, SendGroupMessageResult.error);
    expect(msgRepo.count, 0);
  });

  test('publish and inbox store run concurrently', () async {
    final slowBridge = _SlowPublishBridge(
      delay: const Duration(milliseconds: 200),
    );
    slowBridge.responses['group:publish'] = {
      'ok': true,
      'messageId': 'msg-123',
    };

    final stopwatch = Stopwatch()..start();
    await sendGroupMessage(
      bridge: slowBridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      text: 'Hello!',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Alice',
    );
    stopwatch.stop();

    // If sequential: publish(200ms) + inboxStore(~0ms) > 200ms (plus overhead)
    // If parallel: max(publish(200ms), inboxStore(~0ms)) ≈ 200ms
    // Both should be present
    expect(slowBridge.commandLog, contains('group:publish'));
    expect(slowBridge.commandLog, contains('group:inboxStore'));

    // Wall-clock should be under 400ms (sequential would be ~400ms+ with overhead)
    expect(stopwatch.elapsedMilliseconds, lessThan(400));
  });

  test('inbox store runs even when publish fails', () async {
    final failBridge = _FailPublishBridge();

    final (result, _) = await sendGroupMessage(
      bridge: failBridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      text: 'Hello!',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Alice',
    );

    expect(result, SendGroupMessageResult.error);
    // inbox store should still have run despite publish failure
    expect(failBridge.commandLog, contains('group:publish'));
    expect(failBridge.commandLog, contains('group:inboxStore'));
  });

  // ---------------------------------------------------------------------------
  // Media attachment tests
  // ---------------------------------------------------------------------------
  group('media attachments', () {
    late InMemoryMediaAttachmentRepository mediaRepo;

    final testAttachment = MediaAttachment(
      id: 'att-1',
      messageId: '',
      mime: 'image/jpeg',
      size: 12345,
      mediaType: 'image',
      downloadStatus: 'done',
      createdAt: DateTime.now().toUtc().toIso8601String(),
      localPath: '/tmp/photo.jpg',
    );

    setUp(() {
      mediaRepo = InMemoryMediaAttachmentRepository();
    });

    test('includes media in publish payload', () async {
      final (result, _) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Check this out',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        mediaAttachments: [testAttachment],
        mediaAttachmentRepo: mediaRepo,
      );

      expect(result, SendGroupMessageResult.success);

      // Verify bridge received media in publish payload
      final publishMsg = bridge.sentMessages.firstWhere(
        (m) => (jsonDecode(m) as Map)['cmd'] == 'group:publish',
      );
      final payload =
          (jsonDecode(publishMsg) as Map)['payload'] as Map<String, dynamic>;
      expect(payload['media'], isNotNull);
      expect((payload['media'] as List).length, 1);
    });

    test('includes media in inbox payload', () async {
      await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Check this out',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        mediaAttachments: [testAttachment],
        mediaAttachmentRepo: mediaRepo,
      );

      // Verify inbox store received media in payload
      final inboxMsg = bridge.sentMessages.firstWhere(
        (m) => (jsonDecode(m) as Map)['cmd'] == 'group:inboxStore',
      );
      final inboxPayload =
          (jsonDecode(inboxMsg) as Map)['payload'] as Map<String, dynamic>;
      final innerPayload =
          jsonDecode(inboxPayload['message'] as String) as Map<String, dynamic>;
      expect(innerPayload['media'], isNotNull);
      expect((innerPayload['media'] as List).length, 1);
    });

    test('saves attachments to MediaAttachmentRepository', () async {
      await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Check this out',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        mediaAttachments: [testAttachment],
        mediaAttachmentRepo: mediaRepo,
      );

      expect(mediaRepo.count, 1);
      // The saved attachment should have a non-empty messageId
      final saved = (await mediaRepo.getPendingDownloads()).isEmpty;
      // Since testAttachment has downloadStatus: 'done', getPendingDownloads returns empty
      expect(saved, isTrue);
    });

    test('uses provided messageId when given', () async {
      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Hello!',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        messageId: 'pre-created-id',
      );

      expect(result, SendGroupMessageResult.success);
      expect(message!.id, 'pre-created-id');
      final saved = await msgRepo.getMessage('pre-created-id');
      expect(saved, isNotNull);
    });

    test('uses provided timestamp when given', () async {
      final fixedTime = DateTime.utc(2026, 1, 15, 12, 0, 0);

      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Hello!',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        timestamp: fixedTime,
      );

      expect(result, SendGroupMessageResult.success);
      expect(message!.timestamp, fixedTime);
    });

    test('generates messageId when not provided', () async {
      final (_, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Hello!',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
      );

      expect(message!.id, isNotEmpty);
      expect(message.id, isNot('pre-created-id'));
    });

    test('sends message with empty text and media (voice note)', () async {
      final voiceAttachment = MediaAttachment(
        id: 'att-voice',
        messageId: '',
        mime: 'audio/mp4',
        size: 48000,
        mediaType: 'audio',
        downloadStatus: 'done',
        createdAt: DateTime.now().toUtc().toIso8601String(),
        localPath: '/tmp/voice.m4a',
        durationMs: 3000,
        waveform: [0.1, 0.5, 0.8, 0.3],
      );

      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: '',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        mediaAttachments: [voiceAttachment],
        mediaAttachmentRepo: mediaRepo,
      );

      expect(result, SendGroupMessageResult.success);
      expect(message, isNotNull);
      expect(message!.text, '');
      expect(message.status, 'sent');

      // Verify bridge received media in publish payload
      final publishMsg = bridge.sentMessages.firstWhere(
        (m) => (jsonDecode(m) as Map)['cmd'] == 'group:publish',
      );
      final payload =
          (jsonDecode(publishMsg) as Map)['payload'] as Map<String, dynamic>;
      expect(payload['media'], isNotNull);
      expect((payload['media'] as List).length, 1);

      // Verify attachment saved with resolved messageId
      expect(mediaRepo.count, 1);
    });

    test('rejects message with empty text and no media', () async {
      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: '',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
      );

      expect(result, SendGroupMessageResult.error);
      expect(message, isNull);
      // Should not have called bridge at all
      expect(bridge.commandLog, isEmpty);
    });

    test('rejects message with whitespace-only text and no media', () async {
      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: '   ',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
      );

      expect(result, SendGroupMessageResult.error);
      expect(message, isNull);
    });

    test(
      'topicPeers zero does not fail group send when durable inbox store succeeds',
      () async {
        // When the Go pubsub topic has zero peers, publish still returns ok:true
        // because the durable inbox store is the fallback path. The send should
        // succeed as long as the inbox store completes successfully.
        bridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'msg-zero-peers',
          'topicPeers': 0,
        };

        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'No peers online',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
        );

        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);
        expect(message!.text, 'No peers online');
        // Both publish and inbox store should have been called
        expect(bridge.commandLog, contains('group:publish'));
        expect(bridge.commandLog, contains('group:inboxStore'));
      },
    );

    test(
      'announcement admin send keeps success semantics when live fanout is zero',
      () async {
        // Admin in an announcement group should still succeed even when
        // no peers are online (zero live fanout), because the durable
        // inbox store ensures offline readers will catch up.
        final announcementGroup = GroupModel(
          id: 'group-announce-zero',
          name: 'Announces',
          type: GroupType.announcement,
          topicName: 'group-topic-announce-zero',
          createdAt: DateTime.now().toUtc(),
          createdBy: 'peer-1',
          myRole: GroupRole.admin,
        );
        await groupRepo.saveGroup(announcementGroup);

        bridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'msg-announce-zero',
          'topicPeers': 0,
        };

        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-announce-zero',
          text: 'Announcement to empty room',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
        );

        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);
      },
    );

    test(
      'announcement non-admin remains blocked before any network send starts',
      () async {
        // Non-admin in an announcement group must be rejected before
        // any bridge calls are made (no publish, no inbox store).
        final announcementGroup = GroupModel(
          id: 'group-announce-blocked',
          name: 'Announces Blocked',
          type: GroupType.announcement,
          topicName: 'group-topic-announce-blocked',
          createdAt: DateTime.now().toUtc(),
          createdBy: 'peer-admin',
          myRole: GroupRole.member,
        );
        await groupRepo.saveGroup(announcementGroup);

        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-announce-blocked',
          text: 'Trying to announce',
          senderPeerId: 'peer-2',
          senderPublicKey: 'pk-2',
          senderPrivateKey: 'sk-2',
          senderUsername: 'Bob',
        );

        expect(result, SendGroupMessageResult.unauthorized);
        expect(message, isNull);
        // No bridge calls should have been made at all
        expect(bridge.commandLog, isEmpty);
      },
    );

    test('text-only message without media — no media in payload', () async {
      await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Hello!',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
      );

      final publishMsg = bridge.sentMessages.firstWhere(
        (m) => (jsonDecode(m) as Map)['cmd'] == 'group:publish',
      );
      final payload =
          (jsonDecode(publishMsg) as Map)['payload'] as Map<String, dynamic>;
      expect(payload.containsKey('media'), isFalse);
    });
  });
}
