import 'dart:io';

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

  group('quarantine markers', () {
    test(
      'markQuarantined sets status, increments attempt_count, records reason metadata',
      () async {
        await dbInsertInboxStagingEntry(db, makeRow());

        await dbMarkInboxStagingEntryQuarantined(
          db,
          'entry-001',
          reasonCode: 'decryption_failed',
          reasonDetail: 'message authentication failed',
        );

        final row = (await db.query(
          'inbox_staging_entries',
          where: 'entry_id = ?',
          whereArgs: ['entry-001'],
        )).single;

        expect(row['status'], 'quarantined');
        expect(row['attempt_count'], 1);
        expect(row['reject_reason_code'], 'decryption_failed');
        expect(row['reject_reason_detail'], 'message authentication failed');
        expect(row['last_attempted_at'], isNotNull);
      },
    );

    test('getRecoverableEntries excludes quarantined entries', () async {
      await dbInsertInboxStagingEntry(db, makeRow(entryId: 'entry-keep'));
      await dbInsertInboxStagingEntry(
        db,
        makeRow(entryId: 'entry-quarantined'),
      );
      await dbMarkInboxStagingEntryQuarantined(
        db,
        'entry-quarantined',
        reasonCode: 'decryption_failed',
      );

      final rows = await dbLoadRecoverableInboxStagingEntries(db, limit: 10);
      expect(rows.map((row) => row['entry_id']), ['entry-keep']);
    });

    test('countQuarantinedEntries returns quarantined total', () async {
      await dbInsertInboxStagingEntry(db, makeRow(entryId: 'entry-a'));
      await dbInsertInboxStagingEntry(db, makeRow(entryId: 'entry-b'));
      await dbInsertInboxStagingEntry(db, makeRow(entryId: 'entry-c'));
      await dbMarkInboxStagingEntryQuarantined(
        db,
        'entry-a',
        reasonCode: 'decryption_failed',
      );
      await dbMarkInboxStagingEntryQuarantined(
        db,
        'entry-b',
        reasonCode: 'decryption_failed',
      );

      expect(await dbCountQuarantinedInboxStagingEntries(db), 2);
    });

    // 172 TC-07 — the "needs attention" surface behind the couldn't-display
    // affordance (INV-2: every kept-but-undisplayed entry is user-visibly
    // surfaced). Counts quarantined rows (incl. attempt-cap-exhausted
    // recoverables) PLUS historical rejected rows whose reason codes belong
    // to the recoverable classes the pre-172 code terminally rejected
    // (unknown_sender / duplicate / edit_missing_original) — those are the
    // pre-fix casualties still sitting invisible in the table. Content-safe
    // rejections (blocked_sender / not_chat_message / ignored_edit) are
    // intentional non-displays and must NOT count.
    test('172 TC-07: needs-attention surface counts quarantined + '
        'recoverable-class rejected rows, survives reopen', () async {
      await dbInsertInboxStagingEntry(db, makeRow(entryId: 'entry-q1'));
      await dbInsertInboxStagingEntry(db, makeRow(entryId: 'entry-q2'));
      await dbInsertInboxStagingEntry(db, makeRow(entryId: 'entry-r1'));
      await dbInsertInboxStagingEntry(db, makeRow(entryId: 'entry-r2'));
      await dbInsertInboxStagingEntry(db, makeRow(entryId: 'entry-safe'));
      await dbInsertInboxStagingEntry(db, makeRow(entryId: 'entry-live'));

      await dbMarkInboxStagingEntryQuarantined(
        db,
        'entry-q1',
        reasonCode: 'decryption_failed',
      );
      await dbMarkInboxStagingEntryQuarantined(
        db,
        'entry-q2',
        reasonCode: 'attempt_cap_exceeded',
      );
      // Historical pre-172 casualties: terminally rejected recoverables.
      await dbMarkInboxStagingEntryRejected(
        db,
        'entry-r1',
        reasonCode: 'unknown_sender',
      );
      await dbMarkInboxStagingEntryRejected(
        db,
        'entry-r2',
        reasonCode: 'edit_missing_original',
      );
      // Content-safe rejection: intentional non-display, not loss.
      await dbMarkInboxStagingEntryRejected(
        db,
        'entry-safe',
        reasonCode: 'blocked_sender',
      );
      // entry-live stays pending (recoverable, still being replayed).

      expect(await dbCountNeedsAttentionInboxStagingEntries(db), 4);
    });

    test('172 TC-07 (reopen): needs-attention count reconstructs from a '
        'reopened database', () async {
      final dir = await Directory.systemTemp.createTemp(
        'inbox_staging_needs_attention',
      );
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/staging.db';

      var fileDb = await openDatabase(path, version: 1);
      await runInboxStagingEntriesMigration(fileDb);
      await dbInsertInboxStagingEntry(fileDb, makeRow(entryId: 'entry-q1'));
      await dbMarkInboxStagingEntryQuarantined(
        fileDb,
        'entry-q1',
        reasonCode: 'attempt_cap_exceeded',
      );
      await dbInsertInboxStagingEntry(fileDb, makeRow(entryId: 'entry-r1'));
      await dbMarkInboxStagingEntryRejected(
        fileDb,
        'entry-r1',
        reasonCode: 'duplicate',
      );
      await fileDb.close();

      // Process-restart model: a fresh connection must reconstruct the count.
      fileDb = await openDatabase(path, version: 1);
      addTearDown(() => fileDb.close());
      expect(await dbCountNeedsAttentionInboxStagingEntries(fileDb), 2);
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
