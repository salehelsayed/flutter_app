import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/001_identity_table.dart';
import 'package:flutter_app/core/database/migrations/003_mlkem_keys.dart';
import 'package:flutter_app/core/database/migrations/004_nullify_secret_columns.dart';
import 'package:flutter_app/core/database/migrations/005_secret_null_checks.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    // 005 requires 001 + 003 + 004
    await runIdentityTableMigration(db);
    await runMlKemKeysMigration(db);
    await runNullifySecretColumnsMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('Migration 005: secret null CHECK constraints', () {
    test('CHECK constraint rejects non-null private_key', () async {
      await runSecretNullChecksMigration(db);

      expect(
        () => db.rawInsert(
          'INSERT INTO identity (peer_id, public_key, private_key, mnemonic12, created_at, updated_at) '
          'VALUES (?, ?, ?, ?, ?, ?)',
          ['peer1', 'pubkey1', 'should_be_rejected', null, '2026-02-23T00:00:00Z', '2026-02-23T00:00:00Z'],
        ),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('CHECK constraint rejects non-null mnemonic12', () async {
      await runSecretNullChecksMigration(db);

      expect(
        () => db.rawInsert(
          'INSERT INTO identity (peer_id, public_key, private_key, mnemonic12, created_at, updated_at) '
          'VALUES (?, ?, ?, ?, ?, ?)',
          ['peer1', 'pubkey1', null, 'should_be_rejected', '2026-02-23T00:00:00Z', '2026-02-23T00:00:00Z'],
        ),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('CHECK constraint rejects non-null ml_kem_secret_key', () async {
      await runSecretNullChecksMigration(db);

      expect(
        () => db.rawInsert(
          'INSERT INTO identity (peer_id, public_key, private_key, mnemonic12, ml_kem_secret_key, created_at, updated_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?)',
          ['peer1', 'pubkey1', null, null, 'should_be_rejected', '2026-02-23T00:00:00Z', '2026-02-23T00:00:00Z'],
        ),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('allows null secret columns', () async {
      await runSecretNullChecksMigration(db);

      await db.rawInsert(
        'INSERT INTO identity (peer_id, public_key, private_key, mnemonic12, ml_kem_secret_key, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        ['peer1', 'pubkey1', null, null, null, '2026-02-23T00:00:00Z', '2026-02-23T00:00:00Z'],
      );

      final rows = await db.query('identity');
      expect(rows.length, 1);
      expect(rows[0]['private_key'], isNull);
      expect(rows[0]['mnemonic12'], isNull);
      expect(rows[0]['ml_kem_secret_key'], isNull);
    });

    test('adds avatar_blob column', () async {
      await runSecretNullChecksMigration(db);

      final columns = await db.rawQuery('PRAGMA table_info(identity)');
      final columnNames = columns.map((c) => c['name'] as String).toList();
      expect(columnNames, contains('avatar_blob'));

      // Verify the column type is BLOB
      final avatarBlobColumn = columns.firstWhere(
        (c) => c['name'] == 'avatar_blob',
      );
      expect(avatarBlobColumn['type'], 'BLOB');
    });

    test('preserves existing data', () async {
      // Insert data before migration (with null secrets, as 004 made them nullable)
      await db.rawInsert(
        'INSERT INTO identity (peer_id, public_key, private_key, mnemonic12, ml_kem_public_key, username, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        ['peer1', 'pubkey1', null, null, 'mlkem_pub', 'Alice', '2026-02-23T00:00:00Z', '2026-02-23T00:00:00Z'],
      );

      await runSecretNullChecksMigration(db);

      final rows = await db.query('identity');
      expect(rows.length, 1);
      expect(rows[0]['peer_id'], 'peer1');
      expect(rows[0]['public_key'], 'pubkey1');
      expect(rows[0]['ml_kem_public_key'], 'mlkem_pub');
      expect(rows[0]['username'], 'Alice');
      expect(rows[0]['created_at'], '2026-02-23T00:00:00Z');
      expect(rows[0]['updated_at'], '2026-02-23T00:00:00Z');
      expect(rows[0]['avatar_blob'], isNull);
    });

    test('schema contains CHECK constraints', () async {
      await runSecretNullChecksMigration(db);

      final schema = await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name='identity'",
      );
      expect(schema.isNotEmpty, isTrue);

      final sql = schema.first['sql'] as String;
      expect(sql, contains('CHECK'));
      expect(sql, contains('private_key IS NULL'));
      expect(sql, contains('mnemonic12 IS NULL'));
      expect(sql, contains('ml_kem_secret_key IS NULL'));
    });

    test('idempotent: running twice does not throw', () async {
      await runSecretNullChecksMigration(db);
      await runSecretNullChecksMigration(db);

      // Table should still work
      final rows = await db.query('identity');
      expect(rows, isEmpty);
    });
  });
}
