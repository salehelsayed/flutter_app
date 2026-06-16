import 'package:flutter_app/core/database/helpers/inbox_staging_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/045_inbox_staging_entries.dart';
import 'package:flutter_app/core/inbox/inbox_staging_entry.dart';
import 'package:flutter_app/core/inbox/inbox_staging_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// F3 step 1: `InboxStagingRepositoryImpl.stageEntries` must report an entry as
/// ackable ONLY when the underlying `dbInsertInboxStagingEntry` actually
/// inserted a fresh row. On HEAD it unconditionally reports every entryId
/// ackable even when the `ConflictAlgorithm.ignore` insert was a no-op, so two
/// concurrent drains fetching the same not-yet-acked relay page both ack and
/// both replay the same entries (double notification / double receipt re-mint).
///
/// These tests exercise the REAL `dbInsertInboxStagingEntry` helper over an
/// in-memory sqflite DB (the fake mirrors the bug, so a fake-based unit would
/// pass-by-bug).
void main() {
  late Database db;
  late InboxStagingRepositoryImpl repo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runInboxStagingEntriesMigration(db);
    repo = InboxStagingRepositoryImpl(
      dbInsertInboxStagingEntry: (row) => dbInsertInboxStagingEntry(db, row),
      dbLoadRecoverableInboxStagingEntries: ({limit = 50, entryIds}) =>
          dbLoadRecoverableInboxStagingEntries(
            db,
            limit: limit,
            entryIds: entryIds,
          ),
      dbLoadInboxStagingEntry: (entryId) => dbLoadInboxStagingEntry(db, entryId),
      dbDeleteInboxStagingEntry: (entryId) =>
          dbDeleteInboxStagingEntry(db, entryId),
      dbMarkInboxStagingEntryRetryable:
          (entryId, {required reasonCode, reasonDetail}) =>
              dbMarkInboxStagingEntryRetryable(
                db,
                entryId,
                reasonCode: reasonCode,
                reasonDetail: reasonDetail,
              ),
      dbMarkInboxStagingEntryRejected:
          (entryId, {required reasonCode, reasonDetail}) =>
              dbMarkInboxStagingEntryRejected(
                db,
                entryId,
                reasonCode: reasonCode,
                reasonDetail: reasonDetail,
              ),
      dbMarkInboxStagingEntryQuarantined:
          (entryId, {required reasonCode, reasonDetail}) =>
              dbMarkInboxStagingEntryQuarantined(
                db,
                entryId,
                reasonCode: reasonCode,
                reasonDetail: reasonDetail,
              ),
      dbCountQuarantinedInboxStagingEntries: () =>
          dbCountQuarantinedInboxStagingEntries(db),
    );
  });

  tearDown(() async {
    await db.close();
  });

  InboxStagingEntry makeEntry({
    String entryId = 'entry-A',
    String envelope = '{"type":"chat_message"}',
    String status = 'pending',
  }) {
    return InboxStagingEntry(
      entryId: entryId,
      ownerPeerId: 'self-peer',
      senderPeerId: 'remote-peer',
      messageType: 'chat_message',
      relayTimestamp: '2026-04-01T00:00:00.000Z',
      envelope: envelope,
      status: status,
      stagedAt: '2026-04-01T00:00:01.000Z',
    );
  }

  group('stageEntries insert-result idempotency (F3 step 1)', () {
    test('first stage of a fresh entry reports it ackable', () async {
      final ackable = await repo.stageEntries([makeEntry()]);
      expect(ackable, ['entry-A']);
    });

    test('re-staging an already-staged entry reports it NOT ackable', () async {
      await repo.stageEntries([makeEntry(envelope: 'first')]);

      final secondAckable = await repo.stageEntries([
        makeEntry(envelope: 'second'),
      ]);

      // The conflict-ignored re-insert did not insert a fresh row, so the entry
      // must NOT be re-reported as ackable — otherwise a second concurrent
      // drain re-acks + re-replays an entry the first drain already owns.
      expect(secondAckable, isEmpty);

      // The original row is untouched (ignore semantics preserved).
      final rows = await db.query('inbox_staging_entries');
      expect(rows, hasLength(1));
      expect(rows.single['envelope'], 'first');
    });

    test('mixed batch reports only the newly-inserted ids as ackable', () async {
      await repo.stageEntries([makeEntry(entryId: 'entry-A')]);

      final ackable = await repo.stageEntries([
        makeEntry(entryId: 'entry-A'), // already staged → not ackable
        makeEntry(entryId: 'entry-B'), // fresh → ackable
      ]);

      expect(ackable, ['entry-B']);
    });

    test(
      'a re-staged still-pending entry remains recoverable by id (safety net intact)',
      () async {
        await repo.stageEntries([makeEntry(entryId: 'entry-A')]);

        final secondAckable = await repo.stageEntries([
          makeEntry(entryId: 'entry-A'),
        ]);
        expect(secondAckable, isEmpty);

        // Even though it is no longer reported ackable, an entry staged-then-
        // interrupted before durable commit must still be picked up by the
        // recoverable-by-ids sweep so a later drain never drops it.
        final recoverable = await repo.getRecoverableEntriesByIds(['entry-A']);
        expect(recoverable.map((e) => e.entryId), ['entry-A']);
      },
    );
  });
}
