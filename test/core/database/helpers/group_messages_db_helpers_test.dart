import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/018_group_messages_tables.dart';
import 'package:flutter_app/core/database/migrations/026_group_quoted_message_id.dart';
import 'package:flutter_app/core/database/helpers/group_messages_db_helpers.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runGroupMessagesTablesMigration(db);
    await runGroupQuotedMessageIdMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  Map<String, Object?> makeMessageRow({
    String id = 'msg-001',
    String groupId = 'group-1',
    String senderPeerId = 'peer-sender',
    String? senderUsername = 'Alice',
    String text = 'Hello group',
    String timestamp = '2026-01-15T12:00:00.000Z',
    String? quotedMessageId,
    int keyGeneration = 0,
    String status = 'sent',
    int isIncoming = 1,
    String? readAt,
    String createdAt = '2026-01-15T12:00:00.000Z',
  }) {
    return {
      'id': id,
      'group_id': groupId,
      'sender_peer_id': senderPeerId,
      'sender_username': senderUsername,
      'text': text,
      'timestamp': timestamp,
      'quoted_message_id': quotedMessageId,
      'key_generation': keyGeneration,
      'status': status,
      'is_incoming': isIncoming,
      'read_at': readAt,
      'created_at': createdAt,
    };
  }

  group('dbInsertGroupMessage', () {
    test('inserts a new message', () async {
      await dbInsertGroupMessage(db, makeMessageRow());

      final rows = await db.query('group_messages');
      expect(rows.length, 1);
      expect(rows[0]['id'], 'msg-001');
      expect(rows[0]['text'], 'Hello group');
    });
  });

  group('dbLoadGroupMessagesPage', () {
    test('returns empty list for no messages', () async {
      final results = await dbLoadGroupMessagesPage(db, 'group-1');
      expect(results, isEmpty);
    });

    test('returns messages in chronological (ASC) order', () async {
      await dbInsertGroupMessage(
        db,
        makeMessageRow(id: 'msg-1', timestamp: '2026-01-01T00:00:00.000Z'),
      );
      await dbInsertGroupMessage(
        db,
        makeMessageRow(id: 'msg-2', timestamp: '2026-01-02T00:00:00.000Z'),
      );
      await dbInsertGroupMessage(
        db,
        makeMessageRow(id: 'msg-3', timestamp: '2026-01-03T00:00:00.000Z'),
      );

      final results = await dbLoadGroupMessagesPage(db, 'group-1');
      expect(results.length, 3);
      expect(results[0]['id'], 'msg-1');
      expect(results[1]['id'], 'msg-2');
      expect(results[2]['id'], 'msg-3');
    });

    test('respects limit parameter', () async {
      await dbInsertGroupMessage(
        db,
        makeMessageRow(id: 'msg-1', timestamp: '2026-01-01T00:00:00.000Z'),
      );
      await dbInsertGroupMessage(
        db,
        makeMessageRow(id: 'msg-2', timestamp: '2026-01-02T00:00:00.000Z'),
      );
      await dbInsertGroupMessage(
        db,
        makeMessageRow(id: 'msg-3', timestamp: '2026-01-03T00:00:00.000Z'),
      );

      final results = await dbLoadGroupMessagesPage(db, 'group-1', limit: 2);
      expect(results.length, 2);
      // Most recent 2 (DESC) then reversed to ASC
      expect(results[0]['id'], 'msg-2');
      expect(results[1]['id'], 'msg-3');
    });

    test('orders equal-timestamp pages by message id', () async {
      const sharedTimestamp = '2026-01-02T00:00:00.000Z';
      await dbInsertGroupMessage(
        db,
        makeMessageRow(
          id: 'msg-c',
          timestamp: sharedTimestamp,
          createdAt: '2026-01-02T00:00:03.000Z',
        ),
      );
      await dbInsertGroupMessage(
        db,
        makeMessageRow(
          id: 'msg-a',
          timestamp: sharedTimestamp,
          createdAt: '2026-01-02T00:00:01.000Z',
        ),
      );
      await dbInsertGroupMessage(
        db,
        makeMessageRow(
          id: 'msg-b',
          timestamp: sharedTimestamp,
          createdAt: '2026-01-02T00:00:02.000Z',
        ),
      );

      final results = await dbLoadGroupMessagesPage(db, 'group-1');
      expect(results.map((row) => row['id']).toList(), [
        'msg-a',
        'msg-b',
        'msg-c',
      ]);

      final latestPage = await dbLoadGroupMessagesPage(db, 'group-1', limit: 2);
      expect(latestPage.map((row) => row['id']).toList(), ['msg-b', 'msg-c']);
    });
  });

  group('dbLoadAllGroupMessages', () {
    test('returns only messages for the given group', () async {
      await dbInsertGroupMessage(
        db,
        makeMessageRow(id: 'msg-g1', groupId: 'group-1'),
      );
      await dbInsertGroupMessage(
        db,
        makeMessageRow(id: 'msg-g2', groupId: 'group-2'),
      );

      final results = await dbLoadAllGroupMessages(db, 'group-1');
      expect(results.length, 1);
      expect(results[0]['id'], 'msg-g1');
    });

    test('orders equal-timestamp messages by message id', () async {
      const sharedTimestamp = '2026-01-02T00:00:00.000Z';
      await dbInsertGroupMessage(
        db,
        makeMessageRow(id: 'msg-c', timestamp: sharedTimestamp),
      );
      await dbInsertGroupMessage(
        db,
        makeMessageRow(id: 'msg-a', timestamp: sharedTimestamp),
      );
      await dbInsertGroupMessage(
        db,
        makeMessageRow(id: 'msg-b', timestamp: sharedTimestamp),
      );

      final results = await dbLoadAllGroupMessages(db, 'group-1');
      expect(results.map((row) => row['id']).toList(), [
        'msg-a',
        'msg-b',
        'msg-c',
      ]);
    });
  });

  group('dbLoadLatestGroupMessage', () {
    test('returns null when no messages', () async {
      final result = await dbLoadLatestGroupMessage(db, 'group-1');
      expect(result, isNull);
    });

    test('returns the most recent message', () async {
      await dbInsertGroupMessage(
        db,
        makeMessageRow(id: 'msg-old', timestamp: '2026-01-01T00:00:00.000Z'),
      );
      await dbInsertGroupMessage(
        db,
        makeMessageRow(id: 'msg-new', timestamp: '2026-01-02T00:00:00.000Z'),
      );

      final result = await dbLoadLatestGroupMessage(db, 'group-1');
      expect(result, isNotNull);
      expect(result!['id'], 'msg-new');
    });

    test(
      'uses message id as latest tie-breaker for equal timestamps',
      () async {
        const sharedTimestamp = '2026-01-02T00:00:00.000Z';
        await dbInsertGroupMessage(
          db,
          makeMessageRow(
            id: 'msg-c',
            timestamp: sharedTimestamp,
            createdAt: '2026-01-02T00:00:01.000Z',
          ),
        );
        await dbInsertGroupMessage(
          db,
          makeMessageRow(
            id: 'msg-a',
            timestamp: sharedTimestamp,
            createdAt: '2026-01-02T00:00:03.000Z',
          ),
        );

        final result = await dbLoadLatestGroupMessage(db, 'group-1');
        expect(result, isNotNull);
        expect(result!['id'], 'msg-c');
      },
    );
  });

  group('dbLoadGroupThreadSummaries', () {
    test(
      'uses message id as latest tie-breaker for equal timestamps',
      () async {
        const sharedTimestamp = '2026-01-02T00:00:00.000Z';
        await dbInsertGroupMessage(
          db,
          makeMessageRow(
            id: 'msg-c',
            timestamp: sharedTimestamp,
            quotedMessageId: 'msg-parent',
            createdAt: '2026-01-02T00:00:01.000Z',
          ),
        );
        await dbInsertGroupMessage(
          db,
          makeMessageRow(
            id: 'msg-a',
            timestamp: sharedTimestamp,
            createdAt: '2026-01-02T00:00:03.000Z',
          ),
        );

        final rows = await dbLoadGroupThreadSummaries(db, ['group-1']);
        expect(rows, hasLength(1));
        expect(rows.single['latest_id'], 'msg-c');
        expect(rows.single['latest_quoted_message_id'], 'msg-parent');
      },
    );
  });

  group('dbLoadGroupMessage', () {
    test('returns null for non-existent message', () async {
      final result = await dbLoadGroupMessage(db, 'non-existent');
      expect(result, isNull);
    });

    test('returns message when it exists', () async {
      await dbInsertGroupMessage(db, makeMessageRow());

      final result = await dbLoadGroupMessage(db, 'msg-001');
      expect(result, isNotNull);
      expect(result!['text'], 'Hello group');
    });

    test('round-trips quoted_message_id', () async {
      await dbInsertGroupMessage(
        db,
        makeMessageRow(id: 'msg-quoted', quotedMessageId: 'msg-parent-1'),
      );

      final result = await dbLoadGroupMessage(db, 'msg-quoted');
      expect(result, isNotNull);
      expect(result!['quoted_message_id'], 'msg-parent-1');
    });
  });

  group('dbUpdateGroupMessageStatus', () {
    test('updates status field', () async {
      await dbInsertGroupMessage(db, makeMessageRow(status: 'sent'));

      await dbUpdateGroupMessageStatus(db, 'msg-001', 'delivered');

      final row = await dbLoadGroupMessage(db, 'msg-001');
      expect(row!['status'], 'delivered');
    });
  });

  group('dbCountGroupMessages', () {
    test('returns correct count for a group', () async {
      await dbInsertGroupMessage(db, makeMessageRow(id: 'msg-1'));
      await dbInsertGroupMessage(db, makeMessageRow(id: 'msg-2'));
      await dbInsertGroupMessage(
        db,
        makeMessageRow(id: 'msg-other', groupId: 'group-2'),
      );

      expect(await dbCountGroupMessages(db, 'group-1'), 2);
      expect(await dbCountGroupMessages(db, 'group-2'), 1);
    });
  });

  group('dbCountUnreadGroupMessages', () {
    test('counts only unread incoming messages for a group', () async {
      await dbInsertGroupMessage(
        db,
        makeMessageRow(id: 'msg-unread', isIncoming: 1, readAt: null),
      );
      await dbInsertGroupMessage(
        db,
        makeMessageRow(
          id: 'msg-read',
          isIncoming: 1,
          readAt: '2026-01-15T13:00:00.000Z',
        ),
      );
      await dbInsertGroupMessage(
        db,
        makeMessageRow(id: 'msg-outgoing', isIncoming: 0, readAt: null),
      );

      final count = await dbCountUnreadGroupMessages(db, 'group-1');
      expect(count, 1);
    });
  });

  group('dbCountTotalUnreadGroupMessages', () {
    test('counts across all groups', () async {
      await dbInsertGroupMessage(
        db,
        makeMessageRow(
          id: 'msg-g1',
          groupId: 'group-1',
          isIncoming: 1,
          readAt: null,
        ),
      );
      await dbInsertGroupMessage(
        db,
        makeMessageRow(
          id: 'msg-g2',
          groupId: 'group-2',
          isIncoming: 1,
          readAt: null,
        ),
      );

      final count = await dbCountTotalUnreadGroupMessages(db);
      expect(count, 2);
    });
  });

  group('dbMarkGroupMessagesAsRead', () {
    test('marks unread incoming messages as read', () async {
      await dbInsertGroupMessage(
        db,
        makeMessageRow(id: 'msg-unread', isIncoming: 1, readAt: null),
      );
      await dbInsertGroupMessage(
        db,
        makeMessageRow(id: 'msg-out', isIncoming: 0, readAt: null),
      );

      final count = await dbMarkGroupMessagesAsRead(db, 'group-1');
      expect(count, 1);

      final unread = await dbLoadGroupMessage(db, 'msg-unread');
      expect(unread!['read_at'], isNotNull);

      final outgoing = await dbLoadGroupMessage(db, 'msg-out');
      expect(outgoing!['read_at'], isNull);
    });
  });

  group('dbDeleteGroupMessage', () {
    test('deletes a single message', () async {
      await dbInsertGroupMessage(db, makeMessageRow(id: 'msg-1'));
      await dbInsertGroupMessage(db, makeMessageRow(id: 'msg-2'));

      await dbDeleteGroupMessage(db, 'msg-1');

      expect(await dbLoadGroupMessage(db, 'msg-1'), isNull);
      expect(await dbLoadGroupMessage(db, 'msg-2'), isNotNull);
    });
  });
}
