import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/001_identity_table.dart';
import 'package:flutter_app/core/database/migrations/003_mlkem_keys.dart';
import 'package:flutter_app/core/database/migrations/004_nullify_secret_columns.dart';
import 'package:flutter_app/core/database/migrations/005_secret_null_checks.dart';
import 'package:flutter_app/core/database/migrations/011_avatar_version.dart';

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

  group('Migration 011: avatar_version column', () {
    Future<void> runPrerequisites() async {
      await runIdentityTableMigration(db);
      await runMlKemKeysMigration(db);
      await runNullifySecretColumnsMigration(db);
      await runSecretNullChecksMigration(db);
    }

    test('adds avatar_version to identity', () async {
      await runPrerequisites();
      await runAvatarVersionMigration(db);

      final columns = await db.rawQuery('PRAGMA table_info(identity)');
      final columnNames =
          columns.map((col) => col['name'] as String).toList();
      expect(columnNames, contains('avatar_version'));
    });

    test('adds avatar_version to contacts', () async {
      await runPrerequisites();
      await runAvatarVersionMigration(db);

      final columns = await db.rawQuery('PRAGMA table_info(contacts)');
      final columnNames =
          columns.map((col) => col['name'] as String).toList();
      expect(columnNames, contains('avatar_version'));
    });

    test('column is nullable', () async {
      await runPrerequisites();
      await runAvatarVersionMigration(db);

      // Insert a contact with null avatar_version
      await db.insert('contacts', {
        'peer_id': 'peer-nullable',
        'public_key': 'pk-nullable',
        'rendezvous': 'rv-nullable',
        'username': 'Nullable User',
        'signature': 'sig-nullable',
        'scanned_at': '2026-02-01T00:00:00.000Z',
        'avatar_version': null,
      });

      final rows = await db.query('contacts',
          where: 'peer_id = ?', whereArgs: ['peer-nullable']);
      expect(rows[0]['avatar_version'], isNull);
    });

    test('existing rows get null avatar_version', () async {
      await runPrerequisites();

      // Insert identity and contact BEFORE running 011
      await db.insert('identity', {
        'id': 1,
        'peer_id': 'my-peer-id',
        'public_key': 'my-public-key',
        'username': 'TestUser',
        'created_at': '2026-01-01T00:00:00.000Z',
        'updated_at': '2026-01-01T00:00:00.000Z',
      });
      await db.insert('contacts', {
        'peer_id': 'peer-existing',
        'public_key': 'pk-existing',
        'rendezvous': 'rv-existing',
        'username': 'Existing User',
        'signature': 'sig-existing',
        'scanned_at': '2026-01-01T00:00:00.000Z',
      });

      await runAvatarVersionMigration(db);

      final identityRows = await db.query('identity');
      expect(identityRows[0]['avatar_version'], isNull);

      final contactRows = await db.query('contacts',
          where: 'peer_id = ?', whereArgs: ['peer-existing']);
      expect(contactRows[0]['avatar_version'], isNull);
    });

    test('idempotent: running twice does not throw', () async {
      await runPrerequisites();
      await runAvatarVersionMigration(db);
      // Running again should not throw (catches duplicate column error)
      await runAvatarVersionMigration(db);

      // Columns should still exist
      final identityCols =
          await db.rawQuery('PRAGMA table_info(identity)');
      final identityColNames =
          identityCols.map((col) => col['name'] as String).toList();
      expect(identityColNames, contains('avatar_version'));

      final contactCols =
          await db.rawQuery('PRAGMA table_info(contacts)');
      final contactColNames =
          contactCols.map((col) => col['name'] as String).toList();
      expect(contactColNames, contains('avatar_version'));
    });

    test('rethrows non-duplicate-column errors', () async {
      // Do NOT run prerequisites so the tables don't exist.
      // This should cause a non-"duplicate column" error that gets rethrown.
      expect(
        () => runAvatarVersionMigration(db),
        throwsA(isA<DatabaseException>()),
      );
    });
  });
}
