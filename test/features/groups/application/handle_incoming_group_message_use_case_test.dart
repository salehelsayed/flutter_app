import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';
import 'package:flutter_app/core/media/group_media_size_policy.dart';

import 'package:flutter_app/features/groups/application/handle_incoming_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';

const _validContentHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

class _CountingGroupRepository extends InMemoryGroupRepository {
  var getGroupCalls = 0;
  var getMemberCalls = 0;

  @override
  Future<GroupModel?> getGroup(String id) async {
    getGroupCalls++;
    return super.getGroup(id);
  }

  @override
  Future<GroupMember?> getMember(String groupId, String peerId) async {
    getMemberCalls++;
    return super.getMember(groupId, peerId);
  }
}

class _FakeEventLog {
  final entries = <Map<String, Object?>>[];
  final _payloadBySourceEventId = <String, String>{};

  Future<Map<String, Object?>> append({
    required String groupId,
    required String eventType,
    required String sourcePeerId,
    required String sourceEventId,
    required String sourceTimestamp,
    required Map<String, Object?> payload,
    DateTime? createdAt,
  }) async {
    final canonical = canonicalizeGroupEventLogPayload(payload);
    final existing = _payloadBySourceEventId[sourceEventId];
    if (existing != null && existing != canonical) {
      throw GroupEventLogTamperException('conflicting replay');
    }
    _payloadBySourceEventId[sourceEventId] = canonical;
    final entry = {
      'groupId': groupId,
      'eventType': eventType,
      'sourcePeerId': sourcePeerId,
      'sourceEventId': sourceEventId,
      'sourceTimestamp': sourceTimestamp,
      'payload': payload,
    };
    if (existing == null) {
      entries.add(entry);
    }
    return entry;
  }
}

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

  test('records incoming message in tamper-evident event log', () async {
    final eventLog = _FakeEventLog();
    final timestamp = DateTime.utc(2026, 4, 30, 12).toIso8601String();

    final result = await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 3,
      text: 'Logged message',
      timestamp: timestamp,
      messageId: 'msg-log-1',
      quotedMessageId: 'msg-parent-1',
      appendGroupEventLogEntry: eventLog.append,
    );

    expect(result, isNotNull);
    expect(eventLog.entries, hasLength(1));
    expect(eventLog.entries.single['eventType'], 'message');
    expect(eventLog.entries.single['sourceEventId'], 'msg-log-1');
    final payload = eventLog.entries.single['payload'] as Map<String, Object?>;
    expect(payload['text'], 'Logged message');
    expect(payload['keyEpoch'], 3);
    expect(payload['quotedMessageId'], 'msg-parent-1');
  });

  test(
    'event log rejects tampered duplicate before stored message changes',
    () async {
      final eventLog = _FakeEventLog();
      final timestamp = DateTime.utc(2026, 4, 30, 12).toIso8601String();

      await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Original',
        timestamp: timestamp,
        messageId: 'msg-replay-1',
        appendGroupEventLogEntry: eventLog.append,
      );

      expect(
        () => handleIncomingGroupMessage(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          senderId: 'peer-sender',
          senderUsername: 'Sender',
          keyEpoch: 0,
          text: 'Tampered',
          timestamp: timestamp,
          messageId: 'msg-replay-1',
          appendGroupEventLogEntry: eventLog.append,
        ),
        throwsA(isA<GroupEventLogTamperException>()),
      );

      final stored = await msgRepo.getMessage('msg-replay-1');
      expect(stored, isNotNull);
      expect(stored!.text, 'Original');
      expect(msgRepo.count, 1);
    },
  );

  test('persists same-self delivery as local sent history', () async {
    final result = await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 0,
      text: 'Synced from another device',
      timestamp: DateTime.now().toUtc().toIso8601String(),
      selfPeerId: 'peer-sender',
    );

    expect(result, isNotNull);
    expect(result!.isIncoming, isFalse);
    expect(result.status, 'sent');
    expect(await msgRepo.getUnreadCount('group-1'), 0);
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

  test(
    'duplicate by messageId skips repeated group and member lookups',
    () async {
      final countingRepo = _CountingGroupRepository();
      await countingRepo.saveGroup(testGroup);
      await countingRepo.saveMember(testMember);
      await msgRepo.saveMessage(
        GroupMessage(
          id: 'msg-duplicate-fast-path',
          groupId: 'group-1',
          senderPeerId: 'peer-sender',
          senderUsername: 'Sender',
          text: 'Existing message',
          timestamp: DateTime.now().toUtc(),
          status: 'delivered',
          isIncoming: true,
          createdAt: DateTime.now().toUtc(),
        ),
      );

      final result = await handleIncomingGroupMessage(
        groupRepo: countingRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Existing message',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        messageId: 'msg-duplicate-fast-path',
      );

      expect(result, isNull);
      expect(countingRepo.getGroupCalls, 0);
      expect(countingRepo.getMemberCalls, 0);
    },
  );

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
    'refreshes stored member username from later incoming group traffic',
    () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-sender',
          username: 'Old Name',
          role: MemberRole.writer,
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      final result = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Fresh Name',
        keyEpoch: 0,
        text: 'Name refresh',
        timestamp: DateTime.now().toUtc().toIso8601String(),
      );

      expect(result, isNotNull);
      final refreshedMember = await groupRepo.getMember(
        'group-1',
        'peer-sender',
      );
      expect(refreshedMember, isNotNull);
      expect(refreshedMember!.username, 'Fresh Name');
      expect(result!.senderUsername, 'Fresh Name');
    },
  );

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

  test(
    'accepts a message that predates the persisted dissolve cutoff',
    () async {
      await groupRepo.updateGroup(
        testGroup.copyWith(
          isDissolved: true,
          dissolvedAt: DateTime.utc(2026, 4, 5, 12, 0, 0),
          dissolvedBy: 'peer-admin',
        ),
      );

      final result = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Sent before dissolve',
        timestamp: DateTime.utc(2026, 4, 5, 11, 59, 59).toIso8601String(),
        messageId: 'msg-before-dissolve',
      );

      expect(result, isNotNull);
      expect(result!.id, 'msg-before-dissolve');
    },
  );

  test('rejects a message at or after the persisted dissolve cutoff', () async {
    final dissolvedAt = DateTime.utc(2026, 4, 5, 12, 0, 0);
    await groupRepo.updateGroup(
      testGroup.copyWith(
        isDissolved: true,
        dissolvedAt: dissolvedAt,
        dissolvedBy: 'peer-admin',
      ),
    );

    final result = await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 0,
      text: 'Too late',
      timestamp: dissolvedAt.toIso8601String(),
      messageId: 'msg-after-dissolve',
    );

    expect(result, isNull);
    expect(await msgRepo.getMessage('msg-after-dissolve'), isNull);
  });

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

  test('far future incoming timestamp is clamped to receive time', () async {
    final beforeReceive = DateTime.now().toUtc();
    final farFuture = beforeReceive.add(const Duration(days: 2));

    final result = await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 0,
      text: 'Future-skewed message',
      timestamp: farFuture.toIso8601String(),
      messageId: 'msg-future-skew',
    );
    final afterReceive = DateTime.now().toUtc();

    expect(result, isNotNull);
    expect(result!.timestamp.isBefore(farFuture), isTrue);
    expect(
      result.timestamp.isAfter(
        beforeReceive.subtract(const Duration(seconds: 1)),
      ),
      isTrue,
    );
    expect(
      result.timestamp.isBefore(afterReceive.add(const Duration(seconds: 1))),
      isTrue,
    );

    final saved = await msgRepo.getMessage('msg-future-skew');
    expect(saved, isNotNull);
    expect(saved!.timestamp, result.timestamp);
  });

  test(
    'past current and near future timestamps retain chronological order',
    () async {
      final base = DateTime.now().toUtc();
      final past = base.subtract(const Duration(minutes: 3));
      final nearFuture = base.add(const Duration(minutes: 3));

      await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Current clock',
        timestamp: base.toIso8601String(),
        messageId: 'msg-clock-current',
      );
      await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Past clock',
        timestamp: past.toIso8601String(),
        messageId: 'msg-clock-past',
      );
      await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Near future clock',
        timestamp: nearFuture.toIso8601String(),
        messageId: 'msg-clock-near-future',
      );

      final page = await msgRepo.getMessagesPage('group-1');
      expect(page.map((message) => message.id), [
        'msg-clock-past',
        'msg-clock-current',
        'msg-clock-near-future',
      ]);
      expect(
        (await msgRepo.getLatestMessage('group-1'))!.id,
        'msg-clock-near-future',
      );
    },
  );

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

  test(
    'duplicate replay with the same messageId ignores a tampered timestamp',
    () async {
      const sharedMessageId = 'msg-replay-timestamp-tampered';
      final originalTimestamp = DateTime.utc(2026, 4, 5, 11, 59, 59);
      final tamperedTimestamp = originalTimestamp.add(
        const Duration(minutes: 5),
      );

      final first = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Replay-resistant message',
        timestamp: originalTimestamp.toIso8601String(),
        messageId: sharedMessageId,
      );
      expect(first, isNotNull);

      final replay = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Replay-resistant message',
        timestamp: tamperedTimestamp.toIso8601String(),
        messageId: sharedMessageId,
      );

      expect(
        replay,
        isNull,
        reason: 'Replayed messageId must still deduplicate',
      );

      final saved = await msgRepo.getMessage(sharedMessageId);
      expect(saved, isNotNull);
      expect(saved!.timestamp, originalTimestamp);
      expect(saved.text, 'Replay-resistant message');
      expect(msgRepo.count, 1);
    },
  );

  test(
    'duplicate replay with the same messageId ignores conflicting content',
    () async {
      const sharedMessageId = 'msg-replay-content-tampered';
      final originalTimestamp = DateTime.utc(2026, 4, 5, 12, 30, 0);

      final first = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Trusted live content',
        timestamp: originalTimestamp.toIso8601String(),
        messageId: sharedMessageId,
      );
      expect(first, isNotNull);

      final replay = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Tampered inbox content',
        timestamp: originalTimestamp
            .add(const Duration(minutes: 1))
            .toIso8601String(),
        messageId: sharedMessageId,
      );

      expect(replay, isNull);

      final saved = await msgRepo.getMessage(sharedMessageId);
      expect(saved, isNotNull);
      expect(saved!.text, 'Trusted live content');
      expect(saved.timestamp, originalTimestamp);
      expect(msgRepo.count, 1);
    },
  );

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
        'contentHash': _validContentHash,
        'encryptionKeyBase64': 'key-fixture',
        'encryptionNonce': 'nonce-fixture',
        'encryptionScheme': 'blob_aes_256_gcm_v1',
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
        'contentHash': _validContentHash,
        'encryptionKeyBase64': 'key-fixture',
        'encryptionNonce': 'nonce-fixture',
        'encryptionScheme': 'blob_aes_256_gcm_v1',
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

  test(
    'replayed removed-sender message after cutoff does not overwrite the accepted pre-cutoff row',
    () async {
      const sharedMessageId = 'msg-removed-replay-cutoff';
      final removedAt = DateTime.utc(2026, 4, 5, 12, 0, 0);
      final originalTimestamp = removedAt.subtract(
        const Duration(milliseconds: 1),
      );

      final first = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-removed',
        senderUsername: 'Removed',
        keyEpoch: 0,
        text: 'Sent before cutoff',
        timestamp: originalTimestamp.toIso8601String(),
        messageId: sharedMessageId,
      );
      expect(first, isNotNull);

      await saveRemovalCutoff(
        removedPeerId: 'peer-removed',
        removedAt: removedAt,
      );

      final replay = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-removed',
        senderUsername: 'Removed',
        keyEpoch: 0,
        text: 'Sent before cutoff',
        timestamp: removedAt.add(const Duration(seconds: 1)).toIso8601String(),
        messageId: sharedMessageId,
      );

      expect(replay, isNull);

      final saved = await msgRepo.getMessage(sharedMessageId);
      expect(saved, isNotNull);
      expect(saved!.timestamp, originalTimestamp);
      expect(
        (await msgRepo.getMessagesPage(
          'group-1',
        )).where((message) => message.id == sharedMessageId),
        hasLength(1),
      );
    },
  );

  test(
    'replayed message after dissolve cutoff does not overwrite the accepted pre-dissolve row',
    () async {
      const sharedMessageId = 'msg-dissolve-replay-cutoff';
      final dissolvedAt = DateTime.utc(2026, 4, 5, 12, 0, 0);
      final originalTimestamp = dissolvedAt.subtract(
        const Duration(seconds: 1),
      );

      await groupRepo.updateGroup(
        testGroup.copyWith(
          isDissolved: true,
          dissolvedAt: dissolvedAt,
          dissolvedBy: 'peer-admin',
        ),
      );

      final first = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Sent before dissolve',
        timestamp: originalTimestamp.toIso8601String(),
        messageId: sharedMessageId,
      );
      expect(first, isNotNull);

      final replay = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Sent before dissolve',
        timestamp: dissolvedAt
            .add(const Duration(seconds: 1))
            .toIso8601String(),
        messageId: sharedMessageId,
      );

      expect(replay, isNull);

      final saved = await msgRepo.getMessage(sharedMessageId);
      expect(saved, isNotNull);
      expect(saved!.timestamp, originalTimestamp);
      expect(
        (await msgRepo.getMessagesPage(
          'group-1',
        )).where((message) => message.id == sharedMessageId),
        hasLength(1),
      );
    },
  );

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
          'contentHash': _validContentHash,
          'encryptionKeyBase64': 'key-fixture',
          'encryptionNonce': 'nonce-fixture',
          'encryptionScheme': 'blob_aes_256_gcm_v1',
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
          'contentHash': _validContentHash,
          'encryptionKeyBase64': 'key-fixture',
          'encryptionNonce': 'nonce-fixture',
          'encryptionScheme': 'blob_aes_256_gcm_v1',
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

    test(
      'rejects invalid live media before saving message or attachment',
      () async {
        final media = [
          {
            'id': 'blob-dangerous',
            'mime': 'text/html',
            'size': 5000,
            'mediaType': 'file',
            'contentHash': _validContentHash,
            'encryptionKeyBase64': 'key-fixture',
            'encryptionNonce': 'nonce-fixture',
            'encryptionScheme': 'blob_aes_256_gcm_v1',
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
          text: 'Dangerous media',
          timestamp: DateTime.now().toUtc().toIso8601String(),
          messageId: 'msg-dangerous-media',
          media: media,
          mediaAttachmentRepo: mediaRepo,
        );

        expect(result, isNull);
        expect(await msgRepo.getMessage('msg-dangerous-media'), isNull);
        expect(msgRepo.count, 0);
        expect(mediaRepo.count, 0);
      },
    );

    test('rejects incoming mediaType mismatches before storage', () async {
      final media = [
        {
          'id': 'blob-mismatch',
          'mime': 'image/jpeg',
          'size': 5000,
          'mediaType': 'video',
          'contentHash': _validContentHash,
          'encryptionKeyBase64': 'key-fixture',
          'encryptionNonce': 'nonce-fixture',
          'encryptionScheme': 'blob_aes_256_gcm_v1',
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
        text: 'Mismatch media',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        messageId: 'msg-mismatch-media',
        media: media,
        mediaAttachmentRepo: mediaRepo,
      );

      expect(result, isNull);
      expect(await msgRepo.getMessage('msg-mismatch-media'), isNull);
      expect(mediaRepo.count, 0);
    });

    test(
      'rejects oversized live media before saving message or attachment',
      () async {
        final media = [
          {
            'id': 'blob-oversized-live',
            'mime': 'image/jpeg',
            'size': kGroupMediaPerAttachmentLimitBytes + 1,
            'mediaType': 'image',
            'contentHash': _validContentHash,
            'encryptionKeyBase64': 'key-fixture',
            'encryptionNonce': 'nonce-fixture',
            'encryptionScheme': 'blob_aes_256_gcm_v1',
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
          text: 'Oversized media',
          timestamp: DateTime.now().toUtc().toIso8601String(),
          messageId: 'msg-oversized-live',
          media: media,
          mediaAttachmentRepo: mediaRepo,
        );

        expect(result, isNull);
        expect(await msgRepo.getMessage('msg-oversized-live'), isNull);
        expect(msgRepo.count, 0);
        expect(mediaRepo.count, 0);
      },
    );

    test('rejects total-over-limit live media before storage', () async {
      final media = [
        {
          'id': 'blob-total-1',
          'mime': 'image/jpeg',
          'size': kGroupMediaTotalMessageLimitBytes,
          'mediaType': 'image',
          'contentHash': _validContentHash,
          'encryptionKeyBase64': 'key-fixture',
          'encryptionNonce': 'nonce-fixture',
          'encryptionScheme': 'blob_aes_256_gcm_v1',
          'downloadStatus': 'pending',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
        {
          'id': 'blob-total-2',
          'mime': 'image/png',
          'size': 1,
          'mediaType': 'image',
          'contentHash': _validContentHash,
          'encryptionKeyBase64': 'key-fixture',
          'encryptionNonce': 'nonce-fixture',
          'encryptionScheme': 'blob_aes_256_gcm_v1',
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
        text: 'Too much media',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        messageId: 'msg-total-oversized-live',
        media: media,
        mediaAttachmentRepo: mediaRepo,
      );

      expect(result, isNull);
      expect(await msgRepo.getMessage('msg-total-oversized-live'), isNull);
      expect(mediaRepo.count, 0);
    });

    test('rejects malformed media descriptors before storage', () async {
      final media = [
        {
          'id': 'blob-malformed',
          'mime': 42,
          'size': 5000,
          'mediaType': 'image',
          'contentHash': _validContentHash,
          'encryptionKeyBase64': 'key-fixture',
          'encryptionNonce': 'nonce-fixture',
          'encryptionScheme': 'blob_aes_256_gcm_v1',
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
        text: 'Malformed media',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        messageId: 'msg-malformed-media',
        media: media,
        mediaAttachmentRepo: mediaRepo,
      );

      expect(result, isNull);
      expect(await msgRepo.getMessage('msg-malformed-media'), isNull);
      expect(mediaRepo.count, 0);
    });

    test('rejects malformed media size before storage', () async {
      final media = [
        {
          'id': 'blob-bad-size',
          'mime': 'image/png',
          'size': '5000',
          'mediaType': 'image',
          'contentHash': _validContentHash,
          'encryptionKeyBase64': 'key-fixture',
          'encryptionNonce': 'nonce-fixture',
          'encryptionScheme': 'blob_aes_256_gcm_v1',
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
        text: 'Malformed media size',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        messageId: 'msg-malformed-media-size',
        media: media,
        mediaAttachmentRepo: mediaRepo,
      );

      expect(result, isNull);
      expect(await msgRepo.getMessage('msg-malformed-media-size'), isNull);
      expect(mediaRepo.count, 0);
    });

    test('rejects missing content hash before storage', () async {
      final media = [
        {
          'id': 'blob-missing-hash',
          'mime': 'image/png',
          'size': 5000,
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
        text: 'Missing hash',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        messageId: 'msg-missing-content-hash',
        media: media,
        mediaAttachmentRepo: mediaRepo,
      );

      expect(result, isNull);
      expect(await msgRepo.getMessage('msg-missing-content-hash'), isNull);
      expect(mediaRepo.count, 0);
    });

    test('rejects malformed content hash before storage', () async {
      final media = [
        {
          'id': 'blob-bad-hash',
          'mime': 'image/png',
          'size': 5000,
          'mediaType': 'image',
          'contentHash': 'not-a-sha256',
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
        text: 'Bad hash',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        messageId: 'msg-bad-content-hash',
        media: media,
        mediaAttachmentRepo: mediaRepo,
      );

      expect(result, isNull);
      expect(await msgRepo.getMessage('msg-bad-content-hash'), isNull);
      expect(mediaRepo.count, 0);
    });

    test('rejects missing media encryption metadata before storage', () async {
      final media = [
        {
          'id': 'blob-missing-encryption',
          'mime': 'image/png',
          'size': 5000,
          'mediaType': 'image',
          'contentHash': _validContentHash,
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
        text: 'Missing encryption',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        messageId: 'msg-missing-media-encryption',
        media: media,
        mediaAttachmentRepo: mediaRepo,
      );

      expect(result, isNull);
      expect(await msgRepo.getMessage('msg-missing-media-encryption'), isNull);
      expect(mediaRepo.count, 0);
    });

    test(
      'duplicate replay with oversized media does not enrich existing sparse message',
      () async {
        await msgRepo.saveMessage(
          GroupMessage(
            id: 'msg-duplicate-oversized',
            groupId: 'group-1',
            senderPeerId: 'peer-sender',
            senderUsername: 'Sender',
            text: 'Existing message',
            timestamp: DateTime.now().toUtc(),
            status: 'delivered',
            isIncoming: true,
            createdAt: DateTime.now().toUtc(),
          ),
        );

        final result = await handleIncomingGroupMessage(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          senderId: 'peer-sender',
          senderUsername: 'Sender',
          keyEpoch: 0,
          text: 'Existing message',
          timestamp: DateTime.now().toUtc().toIso8601String(),
          messageId: 'msg-duplicate-oversized',
          media: [
            {
              'id': 'blob-duplicate-oversized',
              'mime': 'image/jpeg',
              'size': kGroupMediaPerAttachmentLimitBytes + 1,
              'mediaType': 'image',
              'contentHash': _validContentHash,
              'encryptionKeyBase64': 'key-fixture',
              'encryptionNonce': 'nonce-fixture',
              'encryptionScheme': 'blob_aes_256_gcm_v1',
              'downloadStatus': 'pending',
              'createdAt': DateTime.now().toUtc().toIso8601String(),
            },
          ],
          mediaAttachmentRepo: mediaRepo,
        );

        expect(result, isNull);
        expect(mediaRepo.count, 0);
      },
    );

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
          'contentHash': _validContentHash,
          'encryptionKeyBase64': 'key-fixture',
          'encryptionNonce': 'nonce-fixture',
          'encryptionScheme': 'blob_aes_256_gcm_v1',
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
