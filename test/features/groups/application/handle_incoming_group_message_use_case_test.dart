import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/handle_incoming_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';

void main() {
  late InMemoryGroupRepository groupRepo;
  late InMemoryGroupMessageRepository msgRepo;

  final testGroup = GroupModel(
    id: 'group-1',
    name: 'Test Group',
    type: GroupType.chat,
    topicName: 'group-topic-1',
    createdAt: DateTime.now().toUtc(),
    createdBy: 'peer-admin',
    myRole: GroupRole.admin,
  );

  final testMember = GroupMember(
    groupId: 'group-1',
    peerId: 'peer-sender',
    username: 'Sender',
    role: MemberRole.writer,
    joinedAt: DateTime.now().toUtc(),
  );

  setUp(() async {
    groupRepo = InMemoryGroupRepository();
    msgRepo = InMemoryGroupMessageRepository();

    await groupRepo.saveGroup(testGroup);
    await groupRepo.saveMember(testMember);
  });

  Future<void> saveRemovalCutoff({
    required String removedPeerId,
    required DateTime removedAt,
  }) {
    return msgRepo.saveMessage(
      GroupMessage(
        id:
            'sys-member_removed:group-1:$removedPeerId:peer-admin:'
            '${removedAt.microsecondsSinceEpoch}',
        groupId: 'group-1',
        senderPeerId: 'peer-admin',
        senderUsername: 'Admin',
        text: 'Admin removed $removedPeerId',
        timestamp: removedAt,
        status: 'delivered',
        isIncoming: true,
        createdAt: removedAt,
      ),
    );
  }

  test('handles incoming message successfully', () async {
    final result = await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 0,
      text: 'Hello from sender!',
      timestamp: DateTime.now().toUtc().toIso8601String(),
    );

    expect(result, isNotNull);
    expect(result!.text, 'Hello from sender!');
    expect(result.isIncoming, true);
    expect(result.senderPeerId, 'peer-sender');
  });

  test(
    'strips dangerous bidi controls and preserves safe markers on incoming save',
    () async {
      const rawText = 'Hello\u202E\u200E world';
      const sanitizedText = 'Hello\u200E world';

      final result = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: rawText,
        timestamp: DateTime.now().toUtc().toIso8601String(),
      );

      expect(result, isNotNull);
      expect(result!.text, sanitizedText);

      final saved = await msgRepo.getMessage(result.id);
      expect(saved, isNotNull);
      expect(saved!.text, sanitizedText);
      expect(saved.text, isNot(contains('\u202E')));
    },
  );

  test('ignores message for unknown group', () async {
    final result = await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'nonexistent-group',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 0,
      text: 'Hello',
      timestamp: DateTime.now().toUtc().toIso8601String(),
    );

    expect(result, isNull);
  });

  test('saves message to repo', () async {
    await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 0,
      text: 'Test message',
      timestamp: DateTime.now().toUtc().toIso8601String(),
    );

    expect(msgRepo.count, 1);
    final latest = await msgRepo.getLatestMessage('group-1');
    expect(latest, isNotNull);
    expect(latest!.text, 'Test message');
  });

  test('persists quotedMessageId from incoming payload', () async {
    final result = await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 0,
      text: 'Reply in group',
      timestamp: DateTime.now().toUtc().toIso8601String(),
      quotedMessageId: 'msg-parent-1',
    );

    expect(result, isNotNull);
    expect(result!.quotedMessageId, 'msg-parent-1');

    final saved = await msgRepo.getMessage(result.id);
    expect(saved, isNotNull);
    expect(saved!.quotedMessageId, 'msg-parent-1');
  });

  test('still processes messages from unknown members', () async {
    // Message from non-member (stale member list)
    final result = await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      senderId: 'unknown-peer',
      senderUsername: 'Unknown',
      keyEpoch: 0,
      text: 'Hello from unknown',
      timestamp: DateTime.now().toUtc().toIso8601String(),
    );

    expect(result, isNotNull);
    expect(result!.text, 'Hello from unknown');
    expect(msgRepo.count, 1);
  });

  test(
    'accepts removed-sender message when it predates the persisted removal cutoff',
    () async {
      final removedAt = DateTime.utc(2026, 4, 5, 12, 0, 0);
      await saveRemovalCutoff(
        removedPeerId: 'peer-removed',
        removedAt: removedAt,
      );

      final result = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-removed',
        senderUsername: 'Removed',
        keyEpoch: 0,
        text: 'Sent before cutoff',
        timestamp: removedAt
            .subtract(const Duration(milliseconds: 1))
            .toIso8601String(),
        messageId: 'msg-before-cutoff',
      );

      expect(result, isNotNull);
      expect(result!.text, 'Sent before cutoff');
      expect(result.id, 'msg-before-cutoff');
    },
  );

  test(
    'rejects removed-sender message when it is at the persisted removal cutoff',
    () async {
      final removedAt = DateTime.utc(2026, 4, 5, 12, 0, 0);
      await saveRemovalCutoff(
        removedPeerId: 'peer-removed',
        removedAt: removedAt,
      );

      final result = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-removed',
        senderUsername: 'Removed',
        keyEpoch: 0,
        text: 'Sent at cutoff',
        timestamp: removedAt.toIso8601String(),
        messageId: 'msg-at-cutoff',
      );

      expect(result, isNull);
      expect(await msgRepo.getMessage('msg-at-cutoff'), isNull);
    },
  );

  test(
    'still processes unknown sender when persisted removal cutoff belongs to another peer',
    () async {
      await saveRemovalCutoff(
        removedPeerId: 'peer-other',
        removedAt: DateTime.utc(2026, 4, 5, 12, 0, 0),
      );

      final result = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-new',
        senderUsername: 'New sender',
        keyEpoch: 0,
        text: 'Hello from future member',
        timestamp: DateTime.utc(2026, 4, 5, 12, 0, 1).toIso8601String(),
        messageId: 'msg-new-sender',
      );

      expect(result, isNotNull);
      expect(result!.id, 'msg-new-sender');
    },
  );

  test('deduplicates identical incoming messages', () async {
    final ts = DateTime.now().toUtc().toIso8601String();

    final result1 = await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 0,
      text: 'Hello!',
      timestamp: ts,
    );
    expect(result1, isNotNull);

    // Second call with same fields
    final result2 = await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 0,
      text: 'Hello!',
      timestamp: ts,
    );
    expect(result2, isNull); // duplicate → skipped
    expect(msgRepo.count, 1); // still only 1 message
  });

  test(
    'deduplicates messages after sanitizing invisible bidi controls',
    () async {
      final ts = DateTime.now().toUtc().toIso8601String();

      final result1 = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Hello world',
        timestamp: ts,
      );
      expect(result1, isNotNull);

      final result2 = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Hello\u200B world',
        timestamp: ts,
      );

      expect(result2, isNull);
      expect(msgRepo.count, 1);
    },
  );

  test('allows messages with different text or timestamp', () async {
    final ts1 = DateTime(2026, 1, 1).toUtc().toIso8601String();
    final ts2 = DateTime(2026, 1, 2).toUtc().toIso8601String();

    await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 0,
      text: 'A',
      timestamp: ts1,
    );
    await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 0,
      text: 'B',
      timestamp: ts1,
    ); // different text
    await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 0,
      text: 'A',
      timestamp: ts2,
    ); // different time

    expect(msgRepo.count, 3); // all unique
  });

  // ---------------------------------------------------------------------------
  // Phase 6: messageId-based dedupe tests
  // ---------------------------------------------------------------------------
  test(
    'deduplicates by messageId when pubsub and group inbox deliver same message',
    () async {
      final ts = DateTime.now().toUtc().toIso8601String();
      const sharedMessageId = 'msg-shared-123';

      // First delivery (e.g. from pubsub).
      final result1 = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Hello!',
        timestamp: ts,
        messageId: sharedMessageId,
      );
      expect(result1, isNotNull);
      expect(result1!.id, sharedMessageId);

      // Second delivery (e.g. from group inbox drain) with the same messageId.
      final result2 = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Hello!',
        timestamp: ts,
        messageId: sharedMessageId,
      );
      expect(
        result2,
        isNull,
        reason: 'Duplicate by messageId should be skipped',
      );
      expect(msgRepo.count, 1, reason: 'Only one message should be saved');
    },
  );

  test('duplicate replay enriches a missing quotedMessageId', () async {
    const sharedMessageId = 'msg-quote-repair';
    final ts = DateTime.now().toUtc().toIso8601String();

    await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 0,
      text: 'Sparse live copy',
      timestamp: ts,
      messageId: sharedMessageId,
    );

    final result = await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 0,
      text: 'Sparse live copy',
      timestamp: ts,
      messageId: sharedMessageId,
      quotedMessageId: 'msg-parent-1',
    );

    expect(result, isNull, reason: 'Replay is still a duplicate delivery');

    final saved = await msgRepo.getMessage(sharedMessageId);
    expect(saved, isNotNull);
    expect(saved!.quotedMessageId, 'msg-parent-1');
  });

  test('duplicate replay saves missing media attachments', () async {
    final mediaRepo = InMemoryMediaAttachmentRepository();
    const sharedMessageId = 'msg-media-repair';
    final ts = DateTime.now().toUtc().toIso8601String();
    final media = [
      {
        'id': 'blob-repair-1',
        'mime': 'image/png',
        'size': 2048,
        'mediaType': 'image',
        'downloadStatus': 'pending',
        'createdAt': ts,
      },
    ];

    await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 0,
      text: '',
      timestamp: ts,
      messageId: sharedMessageId,
      mediaAttachmentRepo: mediaRepo,
    );

    expect(mediaRepo.count, 0);

    final result = await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 0,
      text: '',
      timestamp: ts,
      messageId: sharedMessageId,
      media: media,
      mediaAttachmentRepo: mediaRepo,
    );

    expect(result, isNull, reason: 'Replay is still a duplicate delivery');
    expect(mediaRepo.count, 1);

    final attachments = await mediaRepo.getAttachmentsForMessage(
      sharedMessageId,
    );
    expect(attachments, hasLength(1));
    expect(attachments.first.id, 'blob-repair-1');
  });

  test('duplicate group inbox replay does not resave media', () async {
    final mediaRepo = InMemoryMediaAttachmentRepository();
    final ts = DateTime.now().toUtc().toIso8601String();
    const sharedMessageId = 'msg-media-dup';

    final media = [
      {
        'id': 'blob-dup-test',
        'mime': 'image/png',
        'size': 1000,
        'mediaType': 'image',
        'downloadStatus': 'pending',
        'createdAt': ts,
      },
    ];

    // First delivery — message and media saved.
    await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 0,
      text: 'With media',
      timestamp: ts,
      messageId: sharedMessageId,
      media: media,
      mediaAttachmentRepo: mediaRepo,
    );
    expect(msgRepo.count, 1);
    expect(mediaRepo.count, 1);

    // Second delivery — same messageId, should be deduplicated.
    final result2 = await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 0,
      text: 'With media',
      timestamp: ts,
      messageId: sharedMessageId,
      media: media,
      mediaAttachmentRepo: mediaRepo,
    );
    expect(result2, isNull);
    expect(mediaRepo.count, 1, reason: 'Media should not be saved again');
  });

  // ---------------------------------------------------------------------------
  // Media attachment tests
  // ---------------------------------------------------------------------------
  group('media attachments', () {
    late InMemoryMediaAttachmentRepository mediaRepo;

    setUp(() {
      mediaRepo = InMemoryMediaAttachmentRepository();
    });

    test('saves media attachments when media list provided', () async {
      final media = [
        {
          'id': 'blob-1',
          'mime': 'image/jpeg',
          'size': 12345,
          'mediaType': 'image',
          'downloadStatus': 'pending',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      ];

      final result = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Check this out',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        media: media,
        mediaAttachmentRepo: mediaRepo,
      );

      expect(result, isNotNull);
      expect(mediaRepo.count, 1);

      // Verify attachment has the message's ID
      final attachments = await mediaRepo.getAttachmentsForMessage(result!.id);
      expect(attachments.length, 1);
      expect(attachments.first.mime, 'image/jpeg');
    });

    test('creates MediaAttachment with downloadStatus pending', () async {
      final media = [
        {
          'id': 'blob-2',
          'mime': 'audio/mp4',
          'size': 5000,
          'mediaType': 'audio',
          'downloadStatus': 'pending',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      ];

      final result = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Voice note',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        media: media,
        mediaAttachmentRepo: mediaRepo,
      );

      expect(result, isNotNull);
      final pending = await mediaRepo.getPendingDownloads();
      expect(pending.length, 1);
      expect(pending.first.downloadStatus, 'pending');
    });

    test('handles message without media (backward compat)', () async {
      final result = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Plain text',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        mediaAttachmentRepo: mediaRepo,
      );

      expect(result, isNotNull);
      expect(mediaRepo.count, 0);
    });

    test('ignores duplicate messages — does not re-save media', () async {
      final ts = DateTime.now().toUtc().toIso8601String();
      final media = [
        {
          'id': 'blob-dup',
          'mime': 'image/png',
          'size': 1000,
          'mediaType': 'image',
          'downloadStatus': 'pending',
          'createdAt': ts,
        },
      ];

      await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Duplicate test',
        timestamp: ts,
        media: media,
        mediaAttachmentRepo: mediaRepo,
      );

      // Second call with same content — should be duplicate
      final result2 = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Duplicate test',
        timestamp: ts,
        media: media,
        mediaAttachmentRepo: mediaRepo,
      );

      expect(result2, isNull); // duplicate
      expect(mediaRepo.count, 1); // only saved once
    });
  });
}
