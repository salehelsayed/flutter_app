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
  });

  tearDown(() async {
    await db.close();
  });

  group('Migration 045: inbox staging entries', () {
    test('creates the inbox staging table and indexes', () async {
      await runInboxStagingEntriesMigration(db);

      final columns = await db.rawQuery(
        'PRAGMA table_info(inbox_staging_entries)',
      );
      final columnNames = columns
          .map((column) => column['name'] as String)
          .toList();

      expect(
        columnNames,
        containsAll([
          'entry_id',
          'owner_peer_id',
          'sender_peer_id',
          'message_type',
          'relay_timestamp',
          'envelope',
          'status',
          'attempt_count',
          'staged_at',
          'last_attempted_at',
          'reject_reason_code',
          'reject_reason_detail',
        ]),
      );

      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='inbox_staging_entries'",
      );
      final indexNames = indexes.map((row) => row['name'] as String).toList();
      expect(indexNames, contains('idx_inbox_staging_entries_recoverable'));
      expect(indexNames, contains('idx_inbox_staging_entries_owner_status'));
    });

    test('is idempotent when run twice', () async {
      await runInboxStagingEntriesMigration(db);
      await runInboxStagingEntriesMigration(db);

      final columns = await db.rawQuery(
        'PRAGMA table_info(inbox_staging_entries)',
      );
      expect(
        columns.where((column) => column['name'] == 'entry_id'),
        hasLength(1),
      );
    });
  });
}
