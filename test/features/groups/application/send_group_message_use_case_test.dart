import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';

Future<List<Map<String, dynamic>>> captureFlowEvents(
  Future<void> Function() action,
) async {
  final printed = <String>[];
  final previousLogging = flowEventLoggingEnabled;
  final originalDebugPrint = debugPrint;
  flowEventLoggingEnabled = true;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) {
      printed.add(message);
    }
  };
  try {
    await action();
  } finally {
    debugPrint = originalDebugPrint;
    flowEventLoggingEnabled = previousLogging;
  }

  return printed
      .where((line) => line.startsWith('[FLOW] '))
      .map(
        (line) =>
            jsonDecode(line.substring('[FLOW] '.length))
                as Map<String, dynamic>,
      )
      .toList();
}

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

/// A bridge that blocks group:publish until [publishGate] completes.
class _GatedPublishBridge extends FakeBridge {
  final Completer<void> publishGate = Completer<void>();

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;

    if (cmd == 'group:publish') {
      await publishGate.future;
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

/// A bridge that returns ok:false on group:inboxStore.
class _InboxStoreOkFalseBridge extends FakeBridge {
  _InboxStoreOkFalseBridge() {
    responses['group:inboxStore'] = {
      'ok': false,
      'errorCode': 'INBOX_STORE_FAILED',
    };
  }
}

class _DelayedGroupRepository extends InMemoryGroupRepository {
  static const _latestKeyDelay = Duration(milliseconds: 100);
  static const _membersDelay = Duration(milliseconds: 100);

  @override
  Future<GroupKeyInfo?> getLatestKey(String groupId) async {
    await Future<void>.delayed(_latestKeyDelay);
    return super.getLatestKey(groupId);
  }

  @override
  Future<List<GroupMember>> getMembers(String groupId) async {
    await Future<void>.delayed(_membersDelay);
    return super.getMembers(groupId);
  }
}

class _SaveTrackingGroupMessageRepository
    extends InMemoryGroupMessageRepository {
  final Completer<GroupMessage> firstSave = Completer<GroupMessage>();
  final List<GroupMessage> savedMessages = [];

  @override
  Future<void> saveMessage(GroupMessage message) async {
    savedMessages.add(message);
    if (!firstSave.isCompleted) {
      firstSave.complete(message);
    }
    await super.saveMessage(message);
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

  test('emits GROUP_SEND_MSG_TIMING with group and media metadata', () async {
    final events = await captureFlowEvents(() async {
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
    });

    final timing = events.lastWhere(
      (event) => event['event'] == 'GROUP_SEND_MSG_TIMING',
    );
    expect(timing['details']['outcome'], 'success');
    expect(timing['details']['groupId'], 'group-1');
    expect(timing['details']['hasMedia'], isFalse);
    expect(timing['details']['elapsedMs'], isA<int>());
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
    // Pre-persist contract: error returns the failed message (not null)
    expect(message, isNotNull);
    expect(message!.status, 'failed');
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
    // Pre-persist contract: error returns the failed message (not null)
    expect(message, isNotNull);
    expect(message!.status, 'failed');
  });

  test('persists explicit inbox success when publish fails', () async {
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
    // Pre-persist contract: row exists with 'failed' status + retry payloads
    expect(msgRepo.count, 1);
    final page = await msgRepo.getMessagesPage('group-1');
    expect(page, hasLength(1));
    expect(page.single.id, message!.id);
    final saved = await msgRepo.getMessage(page.single.id);
    expect(saved, isNotNull);
    expect(saved!.status, 'failed');
    expect(saved.wireEnvelope, isNotNull);
    expect(saved.inboxStored, isTrue);
    expect(saved.inboxRetryPayload, isNull);
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

  test(
    'getGroup stays sequential while latest key and member lookup run in parallel',
    () async {
      final slowGroupRepo = _DelayedGroupRepository();
      await slowGroupRepo.saveGroup(testGroup);
      await slowGroupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 0,
          encryptedKey: 'encrypted-key',
          createdAt: DateTime.now().toUtc(),
        ),
      );
      await slowGroupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-1',
          username: 'Alice',
          role: MemberRole.admin,
          joinedAt: DateTime.now().toUtc(),
        ),
      );
      await slowGroupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-2',
          username: 'Bob',
          role: MemberRole.writer,
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      final stopwatch = Stopwatch()..start();
      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: slowGroupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Parallel reads',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
      );
      stopwatch.stop();

      expect(result, SendGroupMessageResult.success);
      expect(message, isNotNull);
      expect(stopwatch.elapsedMilliseconds, lessThan(180));
    },
  );

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

    test(
      'removes stale upload_pending placeholders before saving final attachments',
      () async {
        const messageId = 'group-media-stable-id';
        await mediaRepo.saveAttachment(
          MediaAttachment(
            id: 'pending-placeholder',
            messageId: messageId,
            mime: 'image/jpeg',
            size: 0,
            mediaType: 'image',
            localPath: 'pending_uploads/$messageId/pending-placeholder.jpg',
            downloadStatus: 'upload_pending',
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );

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
          messageId: messageId,
          mediaAttachments: [
            testAttachment.copyWith(
              id: 'final-attachment',
              messageId: messageId,
            ),
          ],
          mediaAttachmentRepo: mediaRepo,
        );

        expect(result, SendGroupMessageResult.success);

        final savedAttachments = await mediaRepo.getAttachmentsForMessage(
          messageId,
        );
        expect(savedAttachments, hasLength(1));
        expect(savedAttachments.single.id, 'final-attachment');
        expect(savedAttachments.single.downloadStatus, 'done');
      },
    );

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

    test(
      'announcement voice-only send accepts empty text and writes exact voice push body',
      () async {
        final announcementGroup = GroupModel(
          id: 'group-announce-voice',
          name: 'Voice Announces',
          type: GroupType.announcement,
          topicName: 'group-topic-announce-voice',
          createdAt: DateTime.now().toUtc(),
          createdBy: 'peer-1',
          myRole: GroupRole.admin,
        );
        await groupRepo.saveGroup(announcementGroup);
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: 'group-announce-voice',
            keyGeneration: 5,
            encryptedKey: 'voice-key',
            createdAt: DateTime.now().toUtc(),
          ),
        );

        final voiceAttachment = MediaAttachment(
          id: 'att-announce-voice',
          messageId: '',
          mime: 'audio/mp4',
          size: 64000,
          mediaType: 'audio',
          downloadStatus: 'done',
          createdAt: DateTime.now().toUtc().toIso8601String(),
          localPath: '/tmp/announce-voice.m4a',
          durationMs: 1800,
          waveform: [0.2, 0.4, 0.8],
        );

        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-announce-voice',
          text: '',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          mediaAttachments: [voiceAttachment],
          mediaAttachmentRepo: mediaRepo,
          messageId: 'msg-announce-voice',
        );

        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);
        expect(message!.id, 'msg-announce-voice');
        expect(message.text, '');
        expect(message.keyGeneration, 5);
        expect(message.status, 'sent');

        final inboxPayload = _lastGroupInboxStorePayload(bridge);
        expect(inboxPayload['pushBody'], equals('Alice sent a voice message'));
        final inboxEnvelope =
            jsonDecode(inboxPayload['message'] as String)
                as Map<String, dynamic>;
        expect(inboxEnvelope['keyEpoch'], 5);
        expect(inboxEnvelope['messageId'], 'msg-announce-voice');
      },
    );

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
      'topicPeers zero returns successNoPeers when durable inbox store succeeds',
      () async {
        // When the Go pubsub topic has zero peers, publish still returns ok:true
        // because the durable inbox store is the fallback path. The send should
        // return successNoPeers while persisting the row as a successful send.
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

        expect(result, SendGroupMessageResult.successNoPeers);
        expect(message, isNotNull);
        expect(message!.text, 'No peers online');
        expect(message.status, 'sent');
        // Both publish and inbox store should have been called
        expect(bridge.commandLog, contains('group:publish'));
        expect(bridge.commandLog, contains('group:inboxStore'));
      },
    );

    test(
      'announcement admin send returns successNoPeers when live fanout is zero',
      () async {
        // Admin in an announcement group should return successNoPeers when
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

        expect(result, SendGroupMessageResult.successNoPeers);
        expect(message, isNotNull);
        expect(message!.status, 'sent');
      },
    );

    test(
      'announcement admin send after key rotation uses the new epoch and remains authorized',
      () async {
        final announcementGroup = GroupModel(
          id: 'group-announce-rotated',
          name: 'Announces Rotated',
          type: GroupType.announcement,
          topicName: 'group-topic-announce-rotated',
          createdAt: DateTime.now().toUtc(),
          createdBy: 'peer-1',
          myRole: GroupRole.admin,
        );
        await groupRepo.saveGroup(announcementGroup);
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: 'group-announce-rotated',
            keyGeneration: 1,
            encryptedKey: 'old-key',
            createdAt: DateTime.now().toUtc(),
          ),
        );
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: 'group-announce-rotated',
            keyGeneration: 2,
            encryptedKey: 'new-key',
            createdAt: DateTime.now().toUtc(),
          ),
        );

        bridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'msg-announce-rotated',
          'topicPeers': 1,
        };

        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-announce-rotated',
          text: 'Post-rotation announcement',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'msg-announce-rotated',
        );

        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);
        expect(message!.keyGeneration, 2);
        expect(message.status, 'sent');
        expect(bridge.commandLog, contains('group:publish'));
        expect(bridge.commandLog, contains('group:inboxStore'));

        final inboxPayload = _lastGroupInboxStorePayload(bridge);
        final inboxEnvelope =
            jsonDecode(inboxPayload['message'] as String)
                as Map<String, dynamic>;
        expect(inboxEnvelope['keyEpoch'], 2);
        expect(inboxEnvelope['messageId'], 'msg-announce-rotated');
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

  // ---------------------------------------------------------------------------
  // WU-3: Pre-persist, _tryInboxStore, topicPeers, 4-way result matrix
  // ---------------------------------------------------------------------------
  group('WU-3: pre-persist and send contract', () {
    test(
      'pre-persist: message saved with sending status + wireEnvelope + inboxRetryPayload BEFORE bridge call',
      () async {
        final gatedBridge = _GatedPublishBridge();
        gatedBridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'msg-123',
          'topicPeers': 2,
        };
        final trackingRepo = _SaveTrackingGroupMessageRepository();

        final fixedTime = DateTime.utc(2026, 1, 15, 12, 0, 0);
        var completed = false;

        final sendFuture =
            sendGroupMessage(
              bridge: gatedBridge,
              groupRepo: groupRepo,
              msgRepo: trackingRepo,
              groupId: 'group-1',
              text: 'Pre-persist test',
              senderPeerId: 'peer-1',
              senderPublicKey: 'pk-1',
              senderPrivateKey: 'sk-1',
              senderUsername: 'Alice',
              messageId: 'pre-persist-id',
              timestamp: fixedTime,
            ).then((value) {
              completed = true;
              return value;
            });

        final firstSaved = await trackingRepo.firstSave.future;
        expect(firstSaved.id, 'pre-persist-id');
        expect(firstSaved.status, 'sending');
        expect(firstSaved.wireEnvelope, isNotNull);
        expect(firstSaved.inboxRetryPayload, isNotNull);

        final savedWhilePublishBlocked = await trackingRepo.getMessage(
          'pre-persist-id',
        );
        expect(savedWhilePublishBlocked, isNotNull);
        expect(savedWhilePublishBlocked!.status, 'sending');
        expect(savedWhilePublishBlocked.wireEnvelope, isNotNull);
        expect(savedWhilePublishBlocked.inboxRetryPayload, isNotNull);
        expect(completed, isFalse);

        gatedBridge.publishGate.complete();
        final (result, message) = await sendFuture;

        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);

        final saved = await trackingRepo.getMessage('pre-persist-id');
        expect(saved, isNotNull);
        expect(saved!.status, 'sent');
      },
    );

    test('pre-persist: unauthorized caller does NOT persist a row', () async {
      final announcementGroup = GroupModel(
        id: 'group-no-persist',
        name: 'Announcements',
        type: GroupType.announcement,
        topicName: 'group-topic-announce',
        createdAt: DateTime.now().toUtc(),
        createdBy: 'peer-admin',
        myRole: GroupRole.member,
      );
      await groupRepo.saveGroup(announcementGroup);

      final (result, _) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-no-persist',
        text: 'Trying to send',
        senderPeerId: 'peer-2',
        senderPublicKey: 'pk-2',
        senderPrivateKey: 'sk-2',
        senderUsername: 'Bob',
      );

      expect(result, SendGroupMessageResult.unauthorized);
      expect(msgRepo.count, 0);
    });

    test('pre-persist: group-not-found does NOT persist a row', () async {
      final (result, _) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'nonexistent-group',
        text: 'No group',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
      );

      expect(result, SendGroupMessageResult.groupNotFound);
      expect(msgRepo.count, 0);
    });
  });

  group('WU-3: 0-peer publish detection and 4-way matrix', () {
    test('0-peer + inbox OK → successNoPeers, status sent', () async {
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
        messageId: 'msg-zero-peers',
      );

      expect(result, SendGroupMessageResult.successNoPeers);
      expect(message, isNotNull);
      expect(message!.status, 'sent');

      final saved = await msgRepo.getMessage('msg-zero-peers');
      expect(saved, isNotNull);
      expect(saved!.status, 'sent');
      expect(saved.inboxStored, isTrue);
    });

    test('0-peer + inbox fail → error', () async {
      final failBridge = _InboxStoreFailBridge();
      failBridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'msg-zero-fail',
        'topicPeers': 0,
      };

      final (result, message) = await sendGroupMessage(
        bridge: failBridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Zero peers, inbox fail',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        messageId: 'msg-zero-fail',
      );

      expect(result, SendGroupMessageResult.error);
      // The pre-persisted row should exist with 'failed' status
      final saved = await msgRepo.getMessage('msg-zero-fail');
      expect(saved, isNotNull);
      expect(saved!.status, 'failed');
    });

    test('peers > 0 + inbox OK → success, both payloads cleared', () async {
      bridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'msg-peers-ok',
        'topicPeers': 3,
      };

      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Normal send',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        messageId: 'msg-peers-ok',
      );

      expect(result, SendGroupMessageResult.success);
      expect(message, isNotNull);
      expect(message!.status, 'sent');
      expect(message.inboxStored, isTrue);

      final saved = await msgRepo.getMessage('msg-peers-ok');
      expect(saved, isNotNull);
      expect(saved!.wireEnvelope, isNull);
      expect(saved.inboxRetryPayload, isNull);
    });

    test(
      'peers > 0 + inbox fail → success, wireEnvelope cleared, inboxRetryPayload kept',
      () async {
        final failBridge = _InboxStoreFailBridge();
        failBridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'msg-peers-inbox-fail',
          'topicPeers': 3,
        };

        final (result, message) = await sendGroupMessage(
          bridge: failBridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'Inbox fails but peers OK',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'msg-peers-inbox-fail',
        );

        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);
        expect(message!.status, 'sent');
        expect(message.inboxStored, isFalse);

        final saved = await msgRepo.getMessage('msg-peers-inbox-fail');
        expect(saved, isNotNull);
        expect(saved!.wireEnvelope, isNull);
        expect(saved.inboxRetryPayload, isNotNull);
      },
    );

    test('missing topicPeers → legacy success', () async {
      // Old bridge response without topicPeers key
      bridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'msg-legacy',
      };

      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Legacy bridge',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        messageId: 'msg-legacy',
      );

      expect(result, SendGroupMessageResult.success);
      expect(message, isNotNull);
      expect(message!.status, 'sent');
    });

    test(
      'publish fail + inbox fail → status failed, both payloads retained',
      () async {
        final failBridge = _InboxStoreFailBridge();
        failBridge.responses['group:publish'] = {
          'ok': false,
          'errorCode': 'PUBLISH_FAILED',
        };

        final (result, message) = await sendGroupMessage(
          bridge: failBridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'Will fail',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'msg-publish-fail',
        );

        expect(result, SendGroupMessageResult.error);
        // Pre-persisted row should exist with 'failed' status
        final page = await msgRepo.getMessagesPage('group-1');
        expect(page, hasLength(1));
        expect(page.single.id, 'msg-publish-fail');
        final saved = await msgRepo.getMessage(page.single.id);
        expect(saved, isNotNull);
        expect(saved!.status, 'failed');
        expect(saved.wireEnvelope, isNotNull);
        expect(saved.inboxStored, isFalse);
        expect(saved.inboxRetryPayload, isNotNull);
      },
    );

    test(
      'publish fail + inbox OK keeps failed status but persists inbox success explicitly',
      () async {
        final failPublishBridge = _FailPublishBridge();

        final (result, message) = await sendGroupMessage(
          bridge: failPublishBridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'Publish fails, inbox stores',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'msg-publish-fail-inbox-ok',
        );

        expect(result, SendGroupMessageResult.error);
        expect(message, isNotNull);
        expect(message!.status, 'failed');
        expect(message.inboxStored, isTrue);
        expect(message.inboxRetryPayload, isNull);

        final saved = await msgRepo.getMessage('msg-publish-fail-inbox-ok');
        expect(saved, isNotNull);
        expect(saved!.status, 'failed');
        expect(saved.wireEnvelope, isNotNull);
        expect(saved.inboxStored, isTrue);
        expect(saved.inboxRetryPayload, isNull);
      },
    );

    test('inbox store ok:false is treated as inbox failure', () async {
      final okFalseBridge = _InboxStoreOkFalseBridge();
      okFalseBridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'msg-inbox-ok-false',
        'topicPeers': 3,
      };

      final (result, message) = await sendGroupMessage(
        bridge: okFalseBridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Inbox bridge says ok false',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        messageId: 'msg-inbox-ok-false',
      );

      expect(result, SendGroupMessageResult.success);
      expect(message, isNotNull);
      expect(message!.status, 'sent');
      expect(message.inboxStored, isFalse);
      expect(message.inboxRetryPayload, isNotNull);

      final saved = await msgRepo.getMessage('msg-inbox-ok-false');
      expect(saved, isNotNull);
      expect(saved!.status, 'sent');
      expect(saved.inboxStored, isFalse);
      expect(saved.inboxRetryPayload, isNotNull);
    });

    test(
      'inbox store uses exactly one group:inboxStore call on success',
      () async {
        bridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'msg-single-inbox',
          'topicPeers': 2,
        };

        await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'Single inbox call',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
        );

        final inboxCalls = bridge.commandLog
            .where((c) => c == 'group:inboxStore')
            .length;
        expect(inboxCalls, 1);
      },
    );
  });
}
