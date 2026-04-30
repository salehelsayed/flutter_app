import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/migrations/055_group_invite_revocations.dart';

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

  group('Migration 055: group invite revocations', () {
    test('creates revocation table and indexes', () async {
      await runGroupInviteRevocationsMigration(db);

      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );
      expect(
        tables.map((row) => row['name']),
        contains('group_invite_revocations'),
      );

      final columns = await db.rawQuery(
        'PRAGMA table_info(group_invite_revocations)',
      );
      final columnNames = columns.map((col) => col['name'] as String).toList();
      expect(
        columnNames,
        containsAll([
          'invite_id',
          'group_id',
          'revoked_at',
          'expires_at',
          'revoked_by',
        ]),
      );

      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index'",
      );
      expect(
        indexes.map((row) => row['name']),
        containsAll([
          'idx_group_invite_revocations_group_id',
          'idx_group_invite_revocations_expires_at',
        ]),
      );
    });

    test('can store a revoked invite row after migration', () async {
      await runGroupInviteRevocationsMigration(db);

      await db.insert('group_invite_revocations', {
        'invite_id': 'invite-1',
        'group_id': 'group-1',
        'revoked_at': '2026-04-29T12:00:00.000Z',
        'expires_at': '2026-05-06T12:00:00.000Z',
        'revoked_by': 'peer-admin',
      });

      final rows = await db.query(
        'group_invite_revocations',
        where: 'invite_id = ?',
        whereArgs: ['invite-1'],
      );
      expect(rows.single['group_id'], 'group-1');
      expect(rows.single['revoked_by'], 'peer-admin');
    });

    test('is idempotent', () async {
      await runGroupInviteRevocationsMigration(db);
      await runGroupInviteRevocationsMigration(db);

      final columns = await db.rawQuery(
        'PRAGMA table_info(group_invite_revocations)',
      );
      final columnNames = columns.map((col) => col['name'] as String).toList();
      expect(columnNames, contains('invite_id'));
    });
  });
}
