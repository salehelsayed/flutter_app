import 'package:flutter_app/core/database/migrations/065_group_history_gap_repairs.dart';
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
    'PREREQ-HISTORY-GAP-REPAIR creates gap lifecycle table and indexes idempotently',
    () async {
      await runGroupHistoryGapRepairsMigration(db);
      await runGroupHistoryGapRepairsMigration(db);

      final columns = await db.rawQuery(
        "PRAGMA table_info('group_history_gap_repairs')",
      );
      final columnNames = columns.map((row) => row['name']).toSet();
      expect(columnNames, contains('group_id'));
      expect(columnNames, contains('gap_id'));
      expect(columnNames, contains('missing_after_message_id'));
      expect(columnNames, contains('missing_before_message_id'));
      expect(columnNames, contains('expected_range_hash'));
      expect(columnNames, contains('expected_head_message_id'));
      expect(columnNames, contains('candidate_source_peer_ids_json'));
      expect(columnNames, contains('attempted_source_peer_ids_json'));
      expect(columnNames, contains('repaired_message_ids_json'));
      expect(columnNames, contains('status'));
      expect(columnNames, contains('failure_reason'));
      expect(columnNames, contains('created_at'));
      expect(columnNames, contains('updated_at'));
      expect(columnNames, contains('repaired_at'));
      expect(columnNames, contains('failed_at'));

      final indexes = await db.rawQuery(
        "PRAGMA index_list('group_history_gap_repairs')",
      );
      final indexNames = indexes.map((row) => row['name']).toSet();
      expect(
        indexNames,
        contains('idx_group_history_gap_repairs_group_status_updated'),
      );
      expect(indexNames, contains('idx_group_history_gap_repairs_group_range'));
    },
  );
}
