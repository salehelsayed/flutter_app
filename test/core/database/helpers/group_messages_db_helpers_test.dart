import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/018_group_messages_tables.dart';
import 'package:flutter_app/core/database/migrations/026_group_quoted_message_id.dart';
import 'package:flutter_app/core/database/migrations/061_group_message_transport_peer_id.dart';
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
    await runGroupMessageTransportPeerIdMigration(db);
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
    String? transportPeerId,
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
      'transport_peer_id': transportPeerId,
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
            transportPeerId: 'peer-sender-device',
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
        expect(rows.single['latest_transport_peer_id'], 'peer-sender-device');
      },
    );
  });

  // 161 db-persistence-5 (QUERY half): the batched preview aggregate that
  // replaces the per-group `getMessagesPage(limit:200)` loop on feed mount. The
  // windowed message slice itself is loaded separately (per pending group, in
  // load_feed_use_case) — these locks cover the AGGREGATE against the real
  // engine (counts + last_outgoing_at + latest row + cutoff exclusion).
  group('dbLoadGroupThreadPreviews (161)', () {
    test(
      'TC-161-01: returns message_count + unread_count + last_outgoing_at + '
      'latest row, with sys-member_removed_cutoff EXCLUDED',
      () async {
        const base = '2026-01-15T12:0';
        // 6 read incoming (12:00..12:05)
        for (var i = 0; i < 6; i++) {
          await dbInsertGroupMessage(
            db,
            makeMessageRow(
              id: 'm0$i',
              timestamp: '$base$i:00.000Z',
              isIncoming: 1,
              readAt: '$base$i:30.000Z',
            ),
          );
        }
        // 2 outgoing (12:06, 12:07) — 12:07 is the latest outgoing
        await dbInsertGroupMessage(
          db,
          makeMessageRow(
            id: 'm06',
            timestamp: '${base}6:00.000Z',
            isIncoming: 0,
            status: 'sent',
          ),
        );
        await dbInsertGroupMessage(
          db,
          makeMessageRow(
            id: 'm07',
            timestamp: '${base}7:00.000Z',
            isIncoming: 0,
            status: 'sent',
          ),
        );
        // 4 unread incoming (12:08..12:11) — m11 is the newest non-cutoff row
        for (var i = 8; i <= 11; i++) {
          await dbInsertGroupMessage(
            db,
            makeMessageRow(
              id: 'm$i',
              timestamp: i < 10 ? '$base$i:00.000Z' : '2026-01-15T12:$i:00.000Z',
              isIncoming: 1,
            ),
          );
        }
        // Removal-cutoff sentinel (newest overall, but MUST be excluded)
        await dbInsertGroupMessage(
          db,
          makeMessageRow(
            id: 'sys-member_removed_cutoff:group-1:peerX:1',
            timestamp: '2026-01-15T12:20:00.000Z',
            isIncoming: 1,
          ),
        );

        final rows = await dbLoadGroupThreadPreviews(db, ['group-1']);
        expect(rows, hasLength(1));
        final row = rows.single;
        expect(row['group_id'], 'group-1');
        expect(row['message_count'], 12, reason: 'cutoff row excluded from total');
        expect(row['unread_count'], 4);
        expect(row['last_outgoing_at'], '${base}7:00.000Z');
        // latest = newest non-cutoff row (m11), NEVER the cutoff sentinel.
        expect(row['latest_id'], 'm11');
        expect(row['latest_is_incoming'], 1);
      },
    );

    test(
      'TC-161-02: ONE batched query returns a preview row per group '
      '(no per-group round-trip)',
      () async {
        for (final groupId in ['group-1', 'group-2', 'group-3']) {
          await dbInsertGroupMessage(
            db,
            makeMessageRow(
              id: '$groupId-a',
              groupId: groupId,
              timestamp: '2026-01-15T12:00:00.000Z',
              isIncoming: 1,
            ),
          );
          await dbInsertGroupMessage(
            db,
            makeMessageRow(
              id: '$groupId-b',
              groupId: groupId,
              timestamp: '2026-01-15T12:01:00.000Z',
              isIncoming: 0,
            ),
          );
        }

        final counter = _QueryCountingExecutor(db);
        final rows = await dbLoadGroupThreadPreviews(counter, [
          'group-1',
          'group-2',
          'group-3',
        ]);

        expect(rows, hasLength(3));
        expect(
          rows.map((r) => r['group_id']).toSet(),
          {'group-1', 'group-2', 'group-3'},
        );
        for (final r in rows) {
          expect(r['message_count'], 2);
          expect(r['unread_count'], 1);
        }
        // Batched aggregate: a single rawQuery for all 3 groups (a per-group
        // loop would scale the count with group count).
        expect(counter.rawQueryCount, 1);
      },
    );

    test(
      'TC-161-12: last_outgoing_at is the newest outgoing timestamp even when '
      'many newer incoming rows follow it (answered-by-old-outgoing)',
      () async {
        // Outgoing first, then a run of newer incoming (all read).
        await dbInsertGroupMessage(
          db,
          makeMessageRow(
            id: 'out-1',
            timestamp: '2026-01-15T12:00:00.000Z',
            isIncoming: 0,
            status: 'sent',
          ),
        );
        for (var i = 1; i <= 5; i++) {
          await dbInsertGroupMessage(
            db,
            makeMessageRow(
              id: 'in-$i',
              timestamp: '2026-01-15T12:0$i:00.000Z',
              isIncoming: 1,
              readAt: '2026-01-15T13:00:00.000Z',
            ),
          );
        }

        final rows = await dbLoadGroupThreadPreviews(db, ['group-1']);
        expect(rows.single['last_outgoing_at'], '2026-01-15T12:00:00.000Z');
        expect(rows.single['unread_count'], 0);
      },
    );

    test('TC-161-01b: latest tie-breaker uses id DESC for equal timestamps',
        () async {
      const sharedTimestamp = '2026-01-02T00:00:00.000Z';
      await dbInsertGroupMessage(
        db,
        makeMessageRow(id: 'tie-c', timestamp: sharedTimestamp),
      );
      await dbInsertGroupMessage(
        db,
        makeMessageRow(id: 'tie-a', timestamp: sharedTimestamp),
      );

      final rows = await dbLoadGroupThreadPreviews(db, ['group-1']);
      expect(rows.single['latest_id'], 'tie-c');
    });
  });

  group('dbLoadGroupMessage', () {
    test('returns null for non-existent message', () async {
      final result = await dbLoadGroupMessage(db, 'non-existent');
      expect(result, isNull);
    });

    test('PGC-005 dbLoadGroupMessage rethrows database errors', () async {
      final closedDb = await openDatabase(inMemoryDatabasePath, version: 1);
      await runGroupMessagesTablesMigration(closedDb);
      await runGroupQuotedMessageIdMigration(closedDb);
      await runGroupMessageTransportPeerIdMigration(closedDb);
      await closedDb.close();

      await expectLater(
        dbLoadGroupMessage(closedDb, 'msg-001'),
        throwsA(anything),
      );
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

  group('dbDeleteGroupMessagesForGroup', () {
    test('deletes only messages for the requested group', () async {
      await dbInsertGroupMessage(
        db,
        makeMessageRow(id: 'msg-target-1', groupId: 'group-1'),
      );
      await dbInsertGroupMessage(
        db,
        makeMessageRow(id: 'msg-target-2', groupId: 'group-1'),
      );
      await dbInsertGroupMessage(
        db,
        makeMessageRow(id: 'msg-other', groupId: 'group-2'),
      );

      final count = await dbDeleteGroupMessagesForGroup(db, 'group-1');

      expect(count, 2);
      expect(await dbLoadAllGroupMessages(db, 'group-1'), isEmpty);
      final remaining = await dbLoadAllGroupMessages(db, 'group-2');
      expect(remaining.map((row) => row['id']), ['msg-other']);
    });
  });
}

/// Counts `rawQuery` calls and forwards everything else to a real executor, so
/// TC-161-02 can prove the batched preview aggregate is ONE query for N groups
/// (a per-group internal loop would scale the count).
class _QueryCountingExecutor implements DatabaseExecutor {
  _QueryCountingExecutor(this._inner);

  final DatabaseExecutor _inner;
  int rawQueryCount = 0;

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) {
    rawQueryCount++;
    return _inner.rawQuery(sql, arguments);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(
        'unexpected ${invocation.memberName} on counting executor',
      );
}
