import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/migrations/056_group_invite_consumptions.dart';

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

  group('Migration 056: group invite consumptions', () {
    test('creates consumption table and indexes', () async {
      await runGroupInviteConsumptionsMigration(db);

      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );
      expect(
        tables.map((row) => row['name']),
        contains('group_invite_consumptions'),
      );

      final columns = await db.rawQuery(
        'PRAGMA table_info(group_invite_consumptions)',
      );
      final columnNames = columns.map((col) => col['name'] as String).toList();
      expect(
        columnNames,
        containsAll(['invite_id', 'group_id', 'consumed_at', 'expires_at']),
      );

      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index'",
      );
      expect(
        indexes.map((row) => row['name']),
        containsAll([
          'idx_group_invite_consumptions_group_id',
          'idx_group_invite_consumptions_expires_at',
        ]),
      );
    });

    test('can store a consumed invite row after migration', () async {
      await runGroupInviteConsumptionsMigration(db);

      await db.insert('group_invite_consumptions', {
        'invite_id': 'invite-1',
        'group_id': 'group-1',
        'consumed_at': '2026-04-29T12:00:00.000Z',
        'expires_at': '2026-05-06T12:00:00.000Z',
      });

      final rows = await db.query(
        'group_invite_consumptions',
        where: 'invite_id = ?',
        whereArgs: ['invite-1'],
      );
      expect(rows.single['group_id'], 'group-1');
    });

    test('is idempotent', () async {
      await runGroupInviteConsumptionsMigration(db);
      await runGroupInviteConsumptionsMigration(db);

      final columns = await db.rawQuery(
        'PRAGMA table_info(group_invite_consumptions)',
      );
      final columnNames = columns.map((col) => col['name'] as String).toList();
      expect(columnNames, contains('invite_id'));
    });
  });
}
