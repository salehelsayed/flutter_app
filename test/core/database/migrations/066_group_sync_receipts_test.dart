import 'package:flutter_app/core/database/migrations/066_group_sync_receipts.dart';
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

  test(
    'PREREQ-GROUP-SYNC-RECEIPTS creates cursor and receipt tables idempotently',
    () async {
      await runGroupSyncReceiptsMigration(db);
      await runGroupSyncReceiptsMigration(db);

      final cursorColumns = await db.rawQuery(
        "PRAGMA table_info('group_inbox_cursors')",
      );
      expect(
        cursorColumns.map((row) => row['name']).toSet(),
        containsAll(['group_id', 'cursor', 'created_at', 'updated_at']),
      );

      final receiptColumns = await db.rawQuery(
        "PRAGMA table_info('group_message_receipts')",
      );
      expect(
        receiptColumns.map((row) => row['name']).toSet(),
        containsAll([
          'group_id',
          'message_id',
          'receipt_type',
          'member_peer_id',
          'sender_device_id',
          'receipt_at',
          'source_event_id',
          'created_at',
          'updated_at',
        ]),
      );

      final indexes = await db.rawQuery(
        "PRAGMA index_list('group_message_receipts')",
      );
      final indexNames = indexes.map((row) => row['name']).toSet();
      expect(indexNames, contains('idx_group_message_receipts_message'));
      expect(indexNames, contains('idx_group_message_receipts_member'));
    },
  );
}
