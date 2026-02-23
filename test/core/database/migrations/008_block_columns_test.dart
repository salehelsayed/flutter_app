import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/001_identity_table.dart';
import 'package:flutter_app/core/database/migrations/003_mlkem_keys.dart';
import 'package:flutter_app/core/database/migrations/007_archive_columns.dart';
import 'package:flutter_app/core/database/migrations/008_block_columns.dart';

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

  group('Migration 008: block columns', () {
    Future<void> runPrerequisites() async {
      await runIdentityTableMigration(db);
      await runMlKemKeysMigration(db);
      await runArchiveColumnsMigration(db);
    }

    test('adds is_blocked column to contacts', () async {
      await runPrerequisites();
      await runBlockColumnsMigration(db);

      final columns = await db.rawQuery('PRAGMA table_info(contacts)');
      final columnNames =
          columns.map((col) => col['name'] as String).toList();
      expect(columnNames, contains('is_blocked'));
    });

    test('adds blocked_at column to contacts', () async {
      await runPrerequisites();
      await runBlockColumnsMigration(db);

      final columns = await db.rawQuery('PRAGMA table_info(contacts)');
      final columnNames =
          columns.map((col) => col['name'] as String).toList();
      expect(columnNames, contains('blocked_at'));
    });

    test('is_blocked defaults to 0', () async {
      await runPrerequisites();
      await runBlockColumnsMigration(db);

      await db.insert('contacts', {
        'peer_id': 'peer-new',
        'public_key': 'pk-new',
        'rendezvous': 'rv-new',
        'username': 'New User',
        'signature': 'sig-new',
        'scanned_at': '2026-02-01T00:00:00.000Z',
      });

      final rows = await db.query('contacts',
          where: 'peer_id = ?', whereArgs: ['peer-new']);
      expect(rows[0]['is_blocked'], 0);
    });

    test('blocked_at defaults to NULL', () async {
      await runPrerequisites();
      await runBlockColumnsMigration(db);

      await db.insert('contacts', {
        'peer_id': 'peer-null-check',
        'public_key': 'pk-null',
        'rendezvous': 'rv-null',
        'username': 'Null User',
        'signature': 'sig-null',
        'scanned_at': '2026-02-01T00:00:00.000Z',
      });

      final rows = await db.query('contacts',
          where: 'peer_id = ?', whereArgs: ['peer-null-check']);
      expect(rows[0]['blocked_at'], isNull);
    });

    test('existing contacts get is_blocked=0 after migration', () async {
      await runPrerequisites();

      // Insert a contact BEFORE running 008
      await db.insert('contacts', {
        'peer_id': 'peer-existing',
        'public_key': 'pk-existing',
        'rendezvous': 'rv-existing',
        'username': 'Existing User',
        'signature': 'sig-existing',
        'scanned_at': '2026-01-01T00:00:00.000Z',
      });

      await runBlockColumnsMigration(db);

      final rows = await db.query('contacts',
          where: 'peer_id = ?', whereArgs: ['peer-existing']);
      expect(rows[0]['is_blocked'], 0);
      expect(rows[0]['blocked_at'], isNull);
    });

    test('idempotent: running twice does not throw', () async {
      await runPrerequisites();
      await runBlockColumnsMigration(db);
      // Running again should not throw
      await runBlockColumnsMigration(db);

      // Table should still work
      final columns = await db.rawQuery('PRAGMA table_info(contacts)');
      final columnNames =
          columns.map((col) => col['name'] as String).toList();
      expect(columnNames, contains('is_blocked'));
      expect(columnNames, contains('blocked_at'));
    });
  });
}
