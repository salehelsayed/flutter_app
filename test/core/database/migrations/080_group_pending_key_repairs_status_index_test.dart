// ignore_for_file: file_names
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/migrations/063_group_pending_key_repairs.dart';
import 'package:flutter_app/core/database/migrations/080_group_pending_key_repairs_status_index.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    // 080 indexes the table created by 063; run the prerequisite first.
    await runGroupPendingKeyRepairsMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<bool> indexExists(String name) async {
    final rows = await db.query(
      'sqlite_master',
      where: "type = 'index' AND name = ?",
      whereArgs: [name],
    );
    return rows.isNotEmpty;
  }

  test('080 creates the status-leading idx_..._status_created index', () async {
    expect(
      await indexExists('idx_group_pending_key_repairs_status_created'),
      isFalse,
    );

    await runGroupPendingKeyRepairsStatusIndexMigration(db);

    expect(
      await indexExists('idx_group_pending_key_repairs_status_created'),
      isTrue,
    );
  });

  test('080 is idempotent on re-run', () async {
    await runGroupPendingKeyRepairsStatusIndexMigration(db);
    await runGroupPendingKeyRepairsStatusIndexMigration(db);

    expect(
      await indexExists('idx_group_pending_key_repairs_status_created'),
      isTrue,
    );
  });
}
