import 'package:flutter_app/core/database/migrations/064_group_welcome_key_package_tombstones.dart';
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
    'creates package tombstone table and expiry index idempotently',
    () async {
      await runGroupWelcomeKeyPackageTombstonesMigration(db);
      await runGroupWelcomeKeyPackageTombstonesMigration(db);

      final columns = await db.rawQuery(
        "PRAGMA table_info('group_welcome_key_package_tombstones')",
      );
      final columnNames = columns.map((row) => row['name']).toSet();
      expect(columnNames, contains('package_id'));
      expect(columnNames, contains('recipient_device_id'));
      expect(columnNames, contains('group_id'));
      expect(columnNames, contains('invite_id'));
      expect(columnNames, contains('public_material_hash'));
      expect(columnNames, contains('consumed_at'));
      expect(columnNames, contains('expires_at'));

      final indexes = await db.rawQuery(
        "PRAGMA index_list('group_welcome_key_package_tombstones')",
      );
      expect(
        indexes.map((row) => row['name']),
        contains('idx_group_welcome_key_package_tombstones_expires_at'),
      );
    },
  );
}
