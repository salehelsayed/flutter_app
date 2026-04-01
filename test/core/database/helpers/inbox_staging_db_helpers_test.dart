import 'package:flutter_app/core/database/helpers/inbox_staging_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/045_inbox_staging_entries.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runInboxStagingEntriesMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  Map<String, Object?> makeRow({
    String entryId = 'entry-001',
    String ownerPeerId = 'self-peer',
    String senderPeerId = 'remote-peer',
    String? messageType = 'chat_message',
    String relayTimestamp = '2026-04-01T00:00:00.000Z',
    String envelope = '{"type":"chat_message"}',
    String status = 'pending',
    int attemptCount = 0,
    String stagedAt = '2026-04-01T00:00:01.000Z',
    String? lastAttemptedAt,
    String? rejectReasonCode,
    String? rejectReasonDetail,
  }) {
    return {
      'entry_id': entryId,
      'owner_peer_id': ownerPeerId,
      'sender_peer_id': senderPeerId,
      'message_type': messageType,
      'relay_timestamp': relayTimestamp,
      'envelope': envelope,
      'status': status,
      'attempt_count': attemptCount,
      'staged_at': stagedAt,
      'last_attempted_at': lastAttemptedAt,
      'reject_reason_code': rejectReasonCode,
      'reject_reason_detail': rejectReasonDetail,
    };
  }

  group('dbInsertInboxStagingEntry', () {
    test('inserts a new staged inbox row', () async {
      await dbInsertInboxStagingEntry(db, makeRow());

      final rows = await db.query('inbox_staging_entries');
      expect(rows, hasLength(1));
      expect(rows.single['entry_id'], 'entry-001');
    });

    test('ignores duplicate entry ids', () async {
      await dbInsertInboxStagingEntry(db, makeRow(envelope: 'first'));
      await dbInsertInboxStagingEntry(db, makeRow(envelope: 'second'));

      final rows = await db.query('inbox_staging_entries');
      expect(rows, hasLength(1));
      expect(rows.single['envelope'], 'first');
    });
  });

  group('dbLoadRecoverableInboxStagingEntries', () {
    test('returns pending and retryable rows in relay order', () async {
      await dbInsertInboxStagingEntry(
        db,
        makeRow(
          entryId: 'entry-002',
          relayTimestamp: '2026-04-01T00:00:02.000Z',
        ),
      );
      await dbInsertInboxStagingEntry(
        db,
        makeRow(
          entryId: 'entry-001',
          relayTimestamp: '2026-04-01T00:00:01.000Z',
          status: 'retryable',
        ),
      );
      await dbInsertInboxStagingEntry(
        db,
        makeRow(
          entryId: 'entry-003',
          relayTimestamp: '2026-04-01T00:00:03.000Z',
          status: 'rejected',
        ),
      );

      final rows = await dbLoadRecoverableInboxStagingEntries(db, limit: 10);
      expect(rows.map((row) => row['entry_id']), ['entry-001', 'entry-002']);
    });

    test('filters by entry ids when requested', () async {
      await dbInsertInboxStagingEntry(db, makeRow(entryId: 'entry-001'));
      await dbInsertInboxStagingEntry(db, makeRow(entryId: 'entry-002'));

      final rows = await dbLoadRecoverableInboxStagingEntries(
        db,
        limit: 10,
        entryIds: const ['entry-002'],
      );

      expect(rows.map((row) => row['entry_id']), ['entry-002']);
    });
  });

  group('retry and reject markers', () {
    test('marks a row retryable with exact reason metadata', () async {
      await dbInsertInboxStagingEntry(db, makeRow());

      await dbMarkInboxStagingEntryRetryable(
        db,
        'entry-001',
        reasonCode: 'missing_mlkem_secret',
        reasonDetail: 'secret unavailable',
      );

      final row = (await db.query(
        'inbox_staging_entries',
        where: 'entry_id = ?',
        whereArgs: ['entry-001'],
      )).single;

      expect(row['status'], 'retryable');
      expect(row['attempt_count'], 1);
      expect(row['reject_reason_code'], 'missing_mlkem_secret');
      expect(row['reject_reason_detail'], 'secret unavailable');
      expect(row['last_attempted_at'], isNotNull);
    });

    test('marks a row rejected with exact reason metadata', () async {
      await dbInsertInboxStagingEntry(db, makeRow());

      await dbMarkInboxStagingEntryRejected(
        db,
        'entry-001',
        reasonCode: 'unknown_sender',
        reasonDetail: 'sender missing from contacts',
      );

      final row = (await db.query(
        'inbox_staging_entries',
        where: 'entry_id = ?',
        whereArgs: ['entry-001'],
      )).single;

      expect(row['status'], 'rejected');
      expect(row['attempt_count'], 1);
      expect(row['reject_reason_code'], 'unknown_sender');
      expect(row['reject_reason_detail'], 'sender missing from contacts');
    });
  });

  group('dbDeleteInboxStagingEntry', () {
    test('deletes staged rows after successful replay', () async {
      await dbInsertInboxStagingEntry(db, makeRow());

      final deleted = await dbDeleteInboxStagingEntry(db, 'entry-001');

      expect(deleted, 1);
      expect(await db.query('inbox_staging_entries'), isEmpty);
    });
  });
}
