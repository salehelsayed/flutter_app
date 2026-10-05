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

  group('dbHasRecoverableInboxStagingEntryExcluding', () {
    Future<bool> probe() => dbHasRecoverableInboxStagingEntryExcluding(
      db,
      messageType: 'delivery_receipt',
      rejectReasonCode: 'typed_handler_unavailable',
    );

    test('is false when only parked receipts are recoverable', () async {
      for (var i = 0; i < 3; i++) {
        await dbInsertInboxStagingEntry(
          db,
          makeRow(
            entryId: 'receipt-$i',
            messageType: 'delivery_receipt',
            status: 'retryable',
            rejectReasonCode: 'typed_handler_unavailable',
          ),
        );
      }
      expect(await probe(), isFalse);
    });

    test('is true for a pending entry behind the parked receipts', () async {
      await dbInsertInboxStagingEntry(
        db,
        makeRow(
          entryId: 'receipt',
          messageType: 'delivery_receipt',
          status: 'retryable',
          rejectReasonCode: 'typed_handler_unavailable',
        ),
      );
      await dbInsertInboxStagingEntry(
        db,
        makeRow(
          entryId: 'chat',
          relayTimestamp: '2026-04-01T00:00:09.000Z',
        ),
      );
      expect(await probe(), isTrue);
    });

    test('counts NULL message types and other reject reasons as work', () async {
      await dbInsertInboxStagingEntry(
        db,
        makeRow(entryId: 'untyped', messageType: null),
      );
      expect(await probe(), isTrue);

      await db.delete('inbox_staging_entries');
      await dbInsertInboxStagingEntry(
        db,
        makeRow(
          entryId: 'receipt-other-reason',
          messageType: 'delivery_receipt',
          status: 'retryable',
          rejectReasonCode: 'transient_failure',
        ),
      );
      expect(await probe(), isTrue);
    });

    test('ignores rows that are not recoverable', () async {
      await dbInsertInboxStagingEntry(
        db,
        makeRow(entryId: 'done', status: 'rejected'),
      );
      expect(await probe(), isFalse);
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

  group('needs-attention background clean-up', () {
    final now = DateTime.utc(2026, 10, 5, 12);
    String ago(Duration d) => now.subtract(d).toIso8601String();

    Future<({int abandoned, int deleted, int requeued})> runMaintenance() =>
        dbRunInboxStagingNeedsAttentionMaintenance(
          db,
          messageTypes: const ['chat_message'],
          now: now,
          giveUpStagedBefore: now.subtract(const Duration(days: 7)),
          deleteAbandonedBefore: now.subtract(const Duration(days: 30)),
          retryAttemptedBefore: now.subtract(const Duration(hours: 1)),
          attemptCount: 10,
        );

    Future<String?> statusOf(String entryId) async =>
        (await dbLoadInboxStagingEntry(db, entryId))?['status'] as String?;

    test('retries, gives up and deletes only the rows that are due', () async {
      Future<void> seed(
        String entryId, {
        String status = 'quarantined',
        String? messageType = 'chat_message',
        Duration stagedAgo = const Duration(days: 1),
        Duration? lastAttemptedAgo,
        String? rejectReasonCode = 'attempt_cap_exceeded',
      }) => dbInsertInboxStagingEntry(
        db,
        makeRow(
          entryId: entryId,
          status: status,
          messageType: messageType,
          stagedAt: ago(stagedAgo),
          lastAttemptedAt: lastAttemptedAgo == null
              ? null
              : ago(lastAttemptedAgo),
          rejectReasonCode: rejectReasonCode,
        ),
      );

      await seed('due', lastAttemptedAgo: const Duration(hours: 2));
      await seed(
        'never-tried',
        status: 'rejected',
        rejectReasonCode: 'duplicate',
      );
      await seed('just-tried', lastAttemptedAgo: const Duration(minutes: 10));
      await seed(
        'too-old',
        stagedAgo: const Duration(days: 8),
        lastAttemptedAgo: const Duration(hours: 2),
      );
      await seed(
        'given-up-long-ago',
        status: 'abandoned',
        lastAttemptedAgo: const Duration(days: 31),
      );
      await seed(
        'given-up-recently',
        status: 'abandoned',
        lastAttemptedAgo: const Duration(days: 29),
      );
      await seed(
        'blocked',
        status: 'rejected',
        stagedAgo: const Duration(days: 8),
        rejectReasonCode: 'blocked_sender',
      );
      await seed(
        'other-type',
        messageType: 'protected_group_content',
        stagedAgo: const Duration(days: 8),
      );
      await seed('live', status: 'pending', rejectReasonCode: null);

      final result = await runMaintenance();

      expect(result, (abandoned: 1, deleted: 1, requeued: 2));

      final due = await dbLoadInboxStagingEntry(db, 'due');
      expect(due!['status'], 'retryable');
      expect(due['attempt_count'], 10);
      expect(due['reject_reason_code'], 'background_retry');
      expect(
        due['reject_reason_detail'],
        'background retry from quarantined:attempt_cap_exceeded',
      );
      expect(await statusOf('never-tried'), 'retryable');
      expect(await statusOf('just-tried'), 'quarantined');

      final tooOld = await dbLoadInboxStagingEntry(db, 'too-old');
      expect(tooOld!['status'], 'abandoned');
      expect(tooOld['last_attempted_at'], now.toIso8601String());
      expect(
        tooOld['reject_reason_detail'],
        'gave up from quarantined:attempt_cap_exceeded',
      );

      expect(await statusOf('given-up-long-ago'), isNull);
      expect(await statusOf('given-up-recently'), 'abandoned');
      expect(await statusOf('blocked'), 'rejected');
      expect(await statusOf('other-type'), 'quarantined');
      expect(await statusOf('live'), 'pending');

      // Given-up rows are never counted or replayed.
      final recoverable = await dbLoadRecoverableInboxStagingEntries(db);
      expect(
        recoverable.map((row) => row['entry_id']).toSet(),
        {'due', 'never-tried', 'live'},
      );
      expect(await dbCountNeedsAttentionInboxStagingEntries(db), 2);
    });

    test('a second run right away changes nothing', () async {
      await dbInsertInboxStagingEntry(
        db,
        makeRow(
          entryId: 'due',
          status: 'quarantined',
          stagedAt: ago(const Duration(days: 1)),
          lastAttemptedAt: ago(const Duration(hours: 2)),
        ),
      );

      expect(await runMaintenance(), (abandoned: 0, deleted: 0, requeued: 1));
      expect(await runMaintenance(), (abandoned: 0, deleted: 0, requeued: 0));
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
