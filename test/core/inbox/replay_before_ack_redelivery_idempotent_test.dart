import 'package:flutter_app/core/inbox/inbox_staging_entry.dart';
import 'package:flutter_app/core/inbox/inbox_staging_repository_impl.dart';
import 'package:flutter_app/core/database/helpers/inbox_staging_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/045_inbox_staging_entries.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
      dbLoadInboxStagingEntry: (entryId) =>
          dbLoadInboxStagingEntry(db, entryId),
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

  InboxStagingEntry entry({
    String entryId = 'entry-redeliver',
    String messageId = 'msg-redeliver',
  }) {
    return InboxStagingEntry(
      entryId: entryId,
      ownerPeerId: 'self-peer',
      senderPeerId: 'remote-peer',
      messageType: 'chat_message',
      relayTimestamp: '2026-04-01T00:00:00.000Z',
      envelope: '{"type":"chat_message","payload":{"id":"$messageId"}}',
      stagedAt: '2026-04-01T00:00:01.000Z',
    );
  }

  test(
    're-staged same entryIds before ack do not duplicate recoverable rows',
    () async {
      final firstAckable = await repo.stageEntries([entry()]);
      final secondAckable = await repo.stageEntries([entry()]);

      expect(firstAckable, ['entry-redeliver']);
      expect(secondAckable, isEmpty);
      final recoverable = await repo.getRecoverableEntriesByIds([
        'entry-redeliver',
      ]);
      expect(recoverable, hasLength(1));
      expect(recoverable.single.entryId, 'entry-redeliver');
    },
  );
}
