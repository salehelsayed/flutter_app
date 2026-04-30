import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/018_group_messages_tables.dart';
import 'package:flutter_app/core/database/migrations/026_group_quoted_message_id.dart';
import 'package:flutter_app/core/database/migrations/041_group_message_reliability_columns.dart';
import 'package:flutter_app/core/database/helpers/group_messages_db_helpers.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository_impl.dart';

import '../../../../shared/fakes/in_memory_group_message_repository.dart';

void main() {
  late Database db;
  late GroupMessageRepositoryImpl repo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runGroupMessagesTablesMigration(db);
    await runGroupQuotedMessageIdMigration(db);
    await runGroupMessageReliabilityColumnsMigration(db);

    repo = GroupMessageRepositoryImpl(
      dbInsertGroupMessage: (row) => dbInsertGroupMessage(db, row),
      dbLoadGroupMessagesPage: (groupId, {int limit = 50, int offset = 0}) =>
          dbLoadGroupMessagesPage(db, groupId, limit: limit, offset: offset),
      dbLoadGroupMessage: (id) => dbLoadGroupMessage(db, id),
      dbLoadLatestGroupMessage: (groupId) =>
          dbLoadLatestGroupMessage(db, groupId),
      dbUpdateGroupMessageStatus: (id, status) =>
          dbUpdateGroupMessageStatus(db, id, status),
      dbCountGroupMessages: (groupId) => dbCountGroupMessages(db, groupId),
      dbCountUnreadGroupMessages: (groupId) =>
          dbCountUnreadGroupMessages(db, groupId),
      dbCountTotalUnreadGroupMessages: () =>
          dbCountTotalUnreadGroupMessages(db),
      dbMarkGroupMessagesAsRead: (groupId) =>
          dbMarkGroupMessagesAsRead(db, groupId),
      dbDeleteGroupMessage: (id) => dbDeleteGroupMessage(db, id),
      dbExistsGroupMessageByContent: (groupId, senderPeerId, text, timestamp) =>
          dbExistsGroupMessageByContent(
            db,
            groupId,
            senderPeerId,
            text,
            timestamp,
          ),
      dbDeleteGroupMessagesForGroup: (groupId) =>
          dbDeleteGroupMessagesForGroup(db, groupId),
      dbLoadGroupThreadSummaries: (groupIds) =>
          dbLoadGroupThreadSummaries(db, groupIds),
      dbLoadFailedOutgoingGroupMessagesFn: () =>
          dbLoadFailedOutgoingGroupMessages(db),
      dbRecoverStuckSendingGroupMessagesFn: ({DateTime? olderThan}) =>
          dbTransitionGroupSendingToFailed(db, olderThan: olderThan),
    );
  });

  tearDown(() async {
    await db.close();
  });

  final now = DateTime.utc(2026, 1, 15, 12, 0, 0);

  GroupMessage makeMessage({
    String id = 'msg-001',
    String groupId = 'group-1',
    String senderPeerId = 'peer-sender',
    String? senderUsername = 'Alice',
    String text = 'Hello group',
    DateTime? timestamp,
    String? quotedMessageId,
    int keyGeneration = 0,
    String status = 'sent',
    bool isIncoming = true,
    DateTime? readAt,
    DateTime? createdAt,
  }) {
    return GroupMessage(
      id: id,
      groupId: groupId,
      senderPeerId: senderPeerId,
      senderUsername: senderUsername,
      text: text,
      timestamp: timestamp ?? now,
      quotedMessageId: quotedMessageId,
      keyGeneration: keyGeneration,
      status: status,
      isIncoming: isIncoming,
      readAt: readAt,
      createdAt: createdAt ?? now,
    );
  }

  group('saveMessage and getMessage', () {
    test('round-trip preserves all fields', () async {
      final msg = makeMessage();
      await repo.saveMessage(msg);

      final result = await repo.getMessage('msg-001');
      expect(result, isNotNull);
      expect(result!.id, 'msg-001');
      expect(result.groupId, 'group-1');
      expect(result.text, 'Hello group');
      expect(result.senderUsername, 'Alice');
    });

    test('round-trip preserves quotedMessageId', () async {
      final msg = makeMessage(quotedMessageId: 'msg-parent-1');
      await repo.saveMessage(msg);

      final result = await repo.getMessage('msg-001');
      expect(result, isNotNull);
      expect(result!.quotedMessageId, 'msg-parent-1');
    });

    test('returns null for non-existent', () async {
      final result = await repo.getMessage('non-existent');
      expect(result, isNull);
    });
  });

  group('pause recovery', () {
    test(
      'transitionSendingToFailed transitions outgoing sending rows',
      () async {
        final ts = DateTime.utc(2026, 1, 1, 0, 0, 0);
        await repo.saveMessage(
          makeMessage(
            id: 'sending-1',
            status: 'sending',
            isIncoming: false,
            timestamp: ts,
            createdAt: ts,
          ),
        );
        await repo.saveMessage(
          makeMessage(
            id: 'sent-1',
            status: 'sent',
            isIncoming: false,
            timestamp: ts,
            createdAt: ts,
          ),
        );

        final count = await repo.transitionSendingToFailed();

        expect(count, 1);
        expect((await repo.getMessage('sending-1'))!.status, 'failed');
        expect((await repo.getMessage('sent-1'))!.status, 'sent');
      },
    );
  });

  group('getMessagesPage', () {
    test('returns messages in chronological order', () async {
      await repo.saveMessage(
        makeMessage(id: 'msg-1', timestamp: DateTime.utc(2026, 1, 1)),
      );
      await repo.saveMessage(
        makeMessage(id: 'msg-2', timestamp: DateTime.utc(2026, 1, 2)),
      );
      await repo.saveMessage(
        makeMessage(id: 'msg-3', timestamp: DateTime.utc(2026, 1, 3)),
      );

      final page = await repo.getMessagesPage('group-1');
      expect(page.length, 3);
      expect(page[0].id, 'msg-1');
      expect(page[1].id, 'msg-2');
      expect(page[2].id, 'msg-3');
    });

    test('respects limit parameter', () async {
      for (var i = 1; i <= 5; i++) {
        await repo.saveMessage(
          makeMessage(id: 'msg-$i', timestamp: DateTime.utc(2026, 1, i)),
        );
      }

      final page = await repo.getMessagesPage('group-1', limit: 3);
      expect(page.length, 3);
    });

    test('orders equal-timestamp messages by id', () async {
      final sharedTimestamp = DateTime.utc(2026, 1, 2);
      await repo.saveMessage(
        makeMessage(
          id: 'msg-c',
          timestamp: sharedTimestamp,
          createdAt: sharedTimestamp.add(const Duration(seconds: 3)),
        ),
      );
      await repo.saveMessage(
        makeMessage(
          id: 'msg-a',
          timestamp: sharedTimestamp,
          createdAt: sharedTimestamp.add(const Duration(seconds: 1)),
        ),
      );
      await repo.saveMessage(
        makeMessage(
          id: 'msg-b',
          timestamp: sharedTimestamp,
          createdAt: sharedTimestamp.add(const Duration(seconds: 2)),
        ),
      );

      final page = await repo.getMessagesPage('group-1');
      expect(page.map((message) => message.id).toList(), [
        'msg-a',
        'msg-b',
        'msg-c',
      ]);

      final latestPage = await repo.getMessagesPage('group-1', limit: 2);
      expect(latestPage.map((message) => message.id).toList(), [
        'msg-b',
        'msg-c',
      ]);
    });
  });

  group('getLatestMessage', () {
    test('returns null when no messages', () async {
      final result = await repo.getLatestMessage('group-1');
      expect(result, isNull);
    });

    test('returns the most recent message', () async {
      await repo.saveMessage(
        makeMessage(id: 'msg-old', timestamp: DateTime.utc(2026, 1, 1)),
      );
      await repo.saveMessage(
        makeMessage(id: 'msg-new', timestamp: DateTime.utc(2026, 1, 2)),
      );

      final result = await repo.getLatestMessage('group-1');
      expect(result!.id, 'msg-new');
    });

    test(
      'uses message id as latest tie-breaker for equal timestamps',
      () async {
        final sharedTimestamp = DateTime.utc(2026, 1, 2);
        await repo.saveMessage(
          makeMessage(
            id: 'msg-c',
            timestamp: sharedTimestamp,
            quotedMessageId: 'msg-parent',
            createdAt: sharedTimestamp.add(const Duration(seconds: 1)),
          ),
        );
        await repo.saveMessage(
          makeMessage(
            id: 'msg-a',
            timestamp: sharedTimestamp,
            createdAt: sharedTimestamp.add(const Duration(seconds: 3)),
          ),
        );

        final latest = await repo.getLatestMessage('group-1');
        expect(latest!.id, 'msg-c');
        expect(latest.quotedMessageId, 'msg-parent');

        final summaries = await repo.getGroupThreadSummaries(['group-1']);
        expect(summaries['group-1']!.latestMessage!.id, 'msg-c');
        expect(
          summaries['group-1']!.latestMessage!.quotedMessageId,
          'msg-parent',
        );
      },
    );

    test(
      'getGroupThreadSummaries returns latest rows and zero defaults',
      () async {
        await repo.saveMessage(
          makeMessage(
            id: 'msg-old',
            groupId: 'group-1',
            timestamp: DateTime.utc(2026, 1, 1),
          ),
        );
        await repo.saveMessage(
          makeMessage(
            id: 'msg-new',
            groupId: 'group-1',
            timestamp: DateTime.utc(2026, 1, 2),
          ),
        );

        final summaries = await repo.getGroupThreadSummaries([
          'group-1',
          'group-2',
        ]);

        expect(summaries['group-1']!.latestMessage!.id, 'msg-new');
        expect(summaries['group-1']!.latestMessage!.quotedMessageId, isNull);
        expect(summaries['group-1']!.unreadCount, 2);
        expect(summaries['group-2']!.latestMessage, isNull);
        expect(summaries['group-2']!.unreadCount, 0);
      },
    );

    test('getGroupThreadSummaries preserves latest quotedMessageId', () async {
      await repo.saveMessage(
        makeMessage(
          id: 'msg-parent',
          groupId: 'group-1',
          timestamp: DateTime.utc(2026, 1, 1),
        ),
      );
      await repo.saveMessage(
        makeMessage(
          id: 'msg-reply',
          groupId: 'group-1',
          timestamp: DateTime.utc(2026, 1, 2),
          quotedMessageId: 'msg-parent',
        ),
      );

      final summaries = await repo.getGroupThreadSummaries(['group-1']);
      expect(summaries['group-1']!.latestMessage!.id, 'msg-reply');
      expect(
        summaries['group-1']!.latestMessage!.quotedMessageId,
        'msg-parent',
      );
    });
  });

  group('InMemoryGroupMessageRepository ordering parity', () {
    test('orders equal-timestamp pages and latest selection by id', () async {
      final fakeRepo = InMemoryGroupMessageRepository();
      final sharedTimestamp = DateTime.utc(2026, 1, 2);
      await fakeRepo.saveMessage(
        makeMessage(
          id: 'msg-c',
          timestamp: sharedTimestamp,
          quotedMessageId: 'msg-parent',
          createdAt: sharedTimestamp.add(const Duration(seconds: 3)),
        ),
      );
      await fakeRepo.saveMessage(
        makeMessage(
          id: 'msg-a',
          timestamp: sharedTimestamp,
          createdAt: sharedTimestamp.add(const Duration(seconds: 1)),
        ),
      );
      await fakeRepo.saveMessage(
        makeMessage(
          id: 'msg-b',
          timestamp: sharedTimestamp,
          createdAt: sharedTimestamp.add(const Duration(seconds: 2)),
        ),
      );

      final page = await fakeRepo.getMessagesPage('group-1');
      expect(page.map((message) => message.id).toList(), [
        'msg-a',
        'msg-b',
        'msg-c',
      ]);

      final latestPage = await fakeRepo.getMessagesPage('group-1', limit: 2);
      expect(latestPage.map((message) => message.id).toList(), [
        'msg-b',
        'msg-c',
      ]);

      final latest = await fakeRepo.getLatestMessage('group-1');
      expect(latest!.id, 'msg-c');
      expect(latest.quotedMessageId, 'msg-parent');

      final summary = await fakeRepo.getGroupThreadSummary('group-1');
      expect(summary.latestMessage!.id, 'msg-c');
      expect(summary.latestMessage!.quotedMessageId, 'msg-parent');
    });
  });

  group('updateMessageStatus', () {
    test('updates the status field', () async {
      await repo.saveMessage(makeMessage(status: 'sent'));

      await repo.updateMessageStatus('msg-001', 'delivered');

      final result = await repo.getMessage('msg-001');
      expect(result!.status, 'delivered');
    });
  });

  group('Section 1 recovery methods', () {
    test('loads failed outgoing group messages', () async {
      await repo.saveMessage(
        makeMessage(id: 'failed-outgoing', status: 'failed', isIncoming: false),
      );
      await repo.saveMessage(
        makeMessage(id: 'failed-incoming', status: 'failed', isIncoming: true),
      );

      final failed = await repo.getFailedOutgoingMessages();

      expect(failed, hasLength(1));
      expect(failed.single.id, 'failed-outgoing');
    });

    test('recovers stuck sending messages older than threshold', () async {
      final now = DateTime.now().toUtc();
      final oldTs = now.subtract(const Duration(minutes: 5));
      final recentTs = now.subtract(const Duration(seconds: 10));
      await repo.saveMessage(
        makeMessage(
          id: 'old-sending',
          status: 'sending',
          isIncoming: false,
          timestamp: oldTs,
          createdAt: oldTs,
        ),
      );
      await repo.saveMessage(
        makeMessage(
          id: 'recent-sending',
          status: 'sending',
          isIncoming: false,
          timestamp: recentTs,
          createdAt: recentTs,
        ),
      );

      final recovered = await repo.recoverStuckSendingMessages(
        olderThan: const Duration(seconds: 30),
      );

      expect(recovered, 1);
    });
  });

  group('getMessageCount', () {
    test('returns correct count', () async {
      await repo.saveMessage(makeMessage(id: 'msg-1'));
      await repo.saveMessage(makeMessage(id: 'msg-2'));

      final count = await repo.getMessageCount('group-1');
      expect(count, 2);
    });
  });

  group('getUnreadCount', () {
    test('counts only unread incoming messages', () async {
      await repo.saveMessage(
        makeMessage(id: 'msg-unread', isIncoming: true, readAt: null),
      );
      await repo.saveMessage(
        makeMessage(
          id: 'msg-read',
          isIncoming: true,
          readAt: DateTime.utc(2026, 1, 15, 13),
        ),
      );
      await repo.saveMessage(
        makeMessage(id: 'msg-out', isIncoming: false, readAt: null),
      );

      final count = await repo.getUnreadCount('group-1');
      expect(count, 1);
    });
  });

  group('getTotalUnreadCount', () {
    test('counts across all groups', () async {
      await repo.saveMessage(
        makeMessage(
          id: 'msg-g1',
          groupId: 'group-1',
          isIncoming: true,
          readAt: null,
        ),
      );
      await repo.saveMessage(
        makeMessage(
          id: 'msg-g2',
          groupId: 'group-2',
          isIncoming: true,
          readAt: null,
        ),
      );

      final count = await repo.getTotalUnreadCount();
      expect(count, 2);
    });
  });

  group('markAsRead', () {
    test('marks unread incoming messages as read', () async {
      await repo.saveMessage(
        makeMessage(id: 'msg-unread', isIncoming: true, readAt: null),
      );

      await repo.markAsRead('group-1');

      final result = await repo.getMessage('msg-unread');
      expect(result!.readAt, isNotNull);
    });

    test('does not mark outgoing messages', () async {
      await repo.saveMessage(
        makeMessage(id: 'msg-out', isIncoming: false, readAt: null),
      );

      await repo.markAsRead('group-1');

      final result = await repo.getMessage('msg-out');
      expect(result!.readAt, isNull);
    });
  });

  group('deleteMessage', () {
    test('removes the message', () async {
      await repo.saveMessage(makeMessage());
      await repo.deleteMessage('msg-001');

      final result = await repo.getMessage('msg-001');
      expect(result, isNull);
    });

    test('does not affect other messages', () async {
      await repo.saveMessage(makeMessage(id: 'msg-1'));
      await repo.saveMessage(makeMessage(id: 'msg-2'));

      await repo.deleteMessage('msg-1');

      expect(await repo.getMessage('msg-1'), isNull);
      expect(await repo.getMessage('msg-2'), isNotNull);
    });
  });

  group('existsByContent', () {
    test('returns true for exact match', () async {
      await repo.saveMessage(
        makeMessage(
          groupId: 'group-1',
          senderPeerId: 'peer-sender',
          text: 'Hello group',
          timestamp: now,
        ),
      );

      final result = await repo.existsByContent(
        'group-1',
        'peer-sender',
        'Hello group',
        now,
      );
      expect(result, isTrue);
    });

    test('returns false when no match exists', () async {
      final result = await repo.existsByContent(
        'group-1',
        'peer-sender',
        'Hello group',
        now,
      );
      expect(result, isFalse);
    });

    test('returns false for different sender', () async {
      await repo.saveMessage(
        makeMessage(
          groupId: 'group-1',
          senderPeerId: 'peer-sender',
          text: 'Hello group',
          timestamp: now,
        ),
      );

      final result = await repo.existsByContent(
        'group-1',
        'peer-other',
        'Hello group',
        now,
      );
      expect(result, isFalse);
    });

    test('returns false for different text', () async {
      await repo.saveMessage(
        makeMessage(
          groupId: 'group-1',
          senderPeerId: 'peer-sender',
          text: 'Hello group',
          timestamp: now,
        ),
      );

      final result = await repo.existsByContent(
        'group-1',
        'peer-sender',
        'Different text',
        now,
      );
      expect(result, isFalse);
    });

    test('returns false for different timestamp', () async {
      await repo.saveMessage(
        makeMessage(
          groupId: 'group-1',
          senderPeerId: 'peer-sender',
          text: 'Hello group',
          timestamp: now,
        ),
      );

      final result = await repo.existsByContent(
        'group-1',
        'peer-sender',
        'Hello group',
        now.add(const Duration(seconds: 1)),
      );
      expect(result, isFalse);
    });

    test('does not match across groups', () async {
      await repo.saveMessage(
        makeMessage(
          groupId: 'group-1',
          senderPeerId: 'peer-sender',
          text: 'Hello group',
          timestamp: now,
        ),
      );

      final result = await repo.existsByContent(
        'group-2',
        'peer-sender',
        'Hello group',
        now,
      );
      expect(result, isFalse);
    });
  });
}
