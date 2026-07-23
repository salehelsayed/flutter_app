import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/helpers/group_messages_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/018_group_messages_tables.dart';
import 'package:flutter_app/core/database/migrations/026_group_quoted_message_id.dart';
import 'package:flutter_app/core/database/migrations/041_group_message_reliability_columns.dart';
import 'package:flutter_app/core/database/migrations/073_group_message_last_send_attempt_at.dart';

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
    await runGroupMessageReliabilityColumnsMigration(db);
    await runGroupMessageLastSendAttemptAtMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  Map<String, Object?> makeRow({
    required String id,
    required String status,
    required int isIncoming,
    required String timestamp,
    String? lastSendAttemptAt,
  }) {
    return {
      'id': id,
      'group_id': 'group-1',
      'sender_peer_id': 'peer-me',
      'sender_username': 'Alice',
      'text': 'Hello group',
      'timestamp': timestamp,
      'quoted_message_id': null,
      'key_generation': 0,
      'status': status,
      'is_incoming': isIncoming,
      'read_at': null,
      'created_at': timestamp,
      'wire_envelope': null,
      'inbox_stored': 0,
      'inbox_retry_payload': null,
      'last_send_attempt_at': lastSendAttemptAt,
    };
  }

  test(
    'dbTransitionGroupSendingToFailed bulk transitions outgoing rows',
    () async {
      final oldTs = '2026-01-01T00:00:00.000Z';
      await dbInsertGroupMessage(
        db,
        makeRow(
          id: 'sending-1',
          status: 'sending',
          isIncoming: 0,
          timestamp: oldTs,
        ),
      );
      await dbInsertGroupMessage(
        db,
        makeRow(
          id: 'sending-2',
          status: 'sending',
          isIncoming: 0,
          timestamp: oldTs,
        ),
      );
      await dbInsertGroupMessage(
        db,
        makeRow(
          id: 'sending-3',
          status: 'sending',
          isIncoming: 0,
          timestamp: oldTs,
        ),
      );
      await dbInsertGroupMessage(
        db,
        makeRow(id: 'sent-1', status: 'sent', isIncoming: 0, timestamp: oldTs),
      );
      await dbInsertGroupMessage(
        db,
        makeRow(id: 'sent-2', status: 'sent', isIncoming: 0, timestamp: oldTs),
      );
      await dbInsertGroupMessage(
        db,
        makeRow(
          id: 'incoming-sending',
          status: 'sending',
          isIncoming: 1,
          timestamp: oldTs,
        ),
      );

      final count = await dbTransitionGroupSendingToFailed(db);

      expect(count, 3);
      final rows = await db.query(
        'group_messages',
        where: 'id IN (?, ?, ?, ?, ?, ?)',
        whereArgs: [
          'sending-1',
          'sending-2',
          'sending-3',
          'sent-1',
          'sent-2',
          'incoming-sending',
        ],
        orderBy: 'id ASC',
      );
      final statusesById = {
        for (final row in rows) row['id'] as String: row['status'] as String,
      };
      expect(statusesById['sending-1'], 'failed');
      expect(statusesById['sending-2'], 'failed');
      expect(statusesById['sending-3'], 'failed');
      expect(statusesById['sent-1'], 'sent');
      expect(statusesById['sent-2'], 'sent');
      expect(statusesById['incoming-sending'], 'sending');
    },
  );

  test(
    'dbTransitionGroupSendingToFailed uses fresh last_send_attempt_at over old timestamp',
    () async {
      final oldLogicalTs = DateTime.utc(2026, 1, 1).toIso8601String();
      final freshAttemptTs = DateTime.utc(2026, 6, 1).toIso8601String();
      await dbInsertGroupMessage(
        db,
        makeRow(
          id: 'fresh-retry-attempt',
          status: 'sending',
          isIncoming: 0,
          timestamp: oldLogicalTs,
          lastSendAttemptAt: freshAttemptTs,
        ),
      );

      final count = await dbTransitionGroupSendingToFailed(
        db,
        olderThan: DateTime.utc(2026, 3, 1),
      );

      expect(count, 0);
      final row = (await db.query(
        'group_messages',
        where: 'id = ?',
        whereArgs: ['fresh-retry-attempt'],
      )).single;
      expect(row['status'], 'sending');
    },
  );

  test(
    'dbTransitionGroupSendingToFailed fails stale last_send_attempt_at even with recent timestamp',
    () async {
      final recentLogicalTs = DateTime.utc(2026, 6, 1).toIso8601String();
      final staleAttemptTs = DateTime.utc(2026, 1, 1).toIso8601String();
      await dbInsertGroupMessage(
        db,
        makeRow(
          id: 'stale-send-attempt',
          status: 'sending',
          isIncoming: 0,
          timestamp: recentLogicalTs,
          lastSendAttemptAt: staleAttemptTs,
        ),
      );

      final count = await dbTransitionGroupSendingToFailed(
        db,
        olderThan: DateTime.utc(2026, 3, 1),
      );

      expect(count, 1);
      final row = (await db.query(
        'group_messages',
        where: 'id = ?',
        whereArgs: ['stale-send-attempt'],
      )).single;
      expect(row['status'], 'failed');
    },
  );

  test(
    'dbTransitionGroupSendingToFailed falls back to timestamp for legacy null attempts',
    () async {
      final oldLogicalTs = DateTime.utc(2026, 1, 1).toIso8601String();
      await dbInsertGroupMessage(
        db,
        makeRow(
          id: 'legacy-null-attempt',
          status: 'sending',
          isIncoming: 0,
          timestamp: oldLogicalTs,
          lastSendAttemptAt: null,
        ),
      );

      final count = await dbTransitionGroupSendingToFailed(
        db,
        olderThan: DateTime.utc(2026, 3, 1),
      );

      expect(count, 1);
      final row = (await db.query(
        'group_messages',
        where: 'id = ?',
        whereArgs: ['legacy-null-attempt'],
      )).single;
      expect(row['status'], 'failed');
    },
  );

  test(
    'P269 sending sweeper preserves parents with pending group uploads in both age modes',
    () async {
      await db.execute('''
        CREATE TABLE media_attachments (
          id TEXT PRIMARY KEY,
          message_id TEXT NOT NULL,
          owner_lane TEXT NOT NULL,
          download_status TEXT NOT NULL
        )
      ''');
      final oldTimestamp = DateTime.utc(2026, 1, 1).toIso8601String();
      for (final id in const <String>[
        'pending-upload-unbounded',
        'pending-upload-aged',
        'control-aged',
      ]) {
        await dbInsertGroupMessage(
          db,
          makeRow(
            id: id,
            status: 'sending',
            isIncoming: 0,
            timestamp: oldTimestamp,
          ),
        );
      }
      for (final messageId in const <String>[
        'pending-upload-unbounded',
        'pending-upload-aged',
      ]) {
        await db.insert('media_attachments', <String, Object?>{
          'id': 'blob-$messageId',
          'message_id': messageId,
          'owner_lane': 'group',
          'download_status': 'upload_pending',
        });
      }

      final unboundedCount = await dbTransitionGroupSendingToFailed(db);
      expect(unboundedCount, 1);
      expect(
        (await db.query(
          'group_messages',
          where: 'id = ?',
          whereArgs: const ['pending-upload-unbounded'],
        )).single['status'],
        'sending',
      );

      await db.update(
        'group_messages',
        const <String, Object?>{'status': 'sending'},
        where: 'id = ?',
        whereArgs: const ['control-aged'],
      );
      final agedCount = await dbTransitionGroupSendingToFailed(
        db,
        olderThan: DateTime.utc(2026, 3, 1),
      );
      expect(agedCount, 1);
      expect(
        (await db.query(
          'group_messages',
          where: 'id = ?',
          whereArgs: const ['pending-upload-aged'],
        )).single['status'],
        'sending',
      );
    },
  );
}
