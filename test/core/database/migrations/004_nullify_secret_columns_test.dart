import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/001_identity_table.dart';
import 'package:flutter_app/core/database/migrations/003_mlkem_keys.dart';
import 'package:flutter_app/core/database/migrations/004_nullify_secret_columns.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    // 004 requires 001 + 003
    await runIdentityTableMigration(db);
    await runMlKemKeysMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('Migration 004: nullify secret columns', () {
    test('private_key is nullable after migration', () async {
      await runNullifySecretColumnsMigration(db);

      // Insert a row with null private_key — should succeed
      await db.rawInsert(
        'INSERT INTO identity (peer_id, public_key, private_key, mnemonic12, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        ['peer1', 'pubkey1', null, 'mnemonic words', '2026-02-23T00:00:00Z', '2026-02-23T00:00:00Z'],
      );

      final rows = await db.query('identity');
      expect(rows.length, 1);
      expect(rows[0]['private_key'], isNull);
    });

    test('mnemonic12 is nullable after migration', () async {
      await runNullifySecretColumnsMigration(db);

      // Insert a row with null mnemonic12 — should succeed
      await db.rawInsert(
        'INSERT INTO identity (peer_id, public_key, private_key, mnemonic12, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        ['peer1', 'pubkey1', 'privkey1', null, '2026-02-23T00:00:00Z', '2026-02-23T00:00:00Z'],
      );

      final rows = await db.query('identity');
      expect(rows.length, 1);
      expect(rows[0]['mnemonic12'], isNull);
    });

    test('preserves existing data during migration', () async {
      // Insert data before migration
      await db.rawInsert(
        'INSERT INTO identity (peer_id, public_key, private_key, mnemonic12, username, ml_kem_public_key, ml_kem_secret_key, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        ['peer1', 'pubkey1', 'privkey1', 'word1 word2 word3', 'Alice', 'mlkem_pub', 'mlkem_sec', '2026-02-23T00:00:00Z', '2026-02-23T00:00:00Z'],
      );

      await runNullifySecretColumnsMigration(db);

      final rows = await db.query('identity');
      expect(rows.length, 1);
      expect(rows[0]['peer_id'], 'peer1');
      expect(rows[0]['public_key'], 'pubkey1');
      expect(rows[0]['private_key'], 'privkey1');
      expect(rows[0]['mnemonic12'], 'word1 word2 word3');
      expect(rows[0]['username'], 'Alice');
      expect(rows[0]['created_at'], '2026-02-23T00:00:00Z');
      expect(rows[0]['updated_at'], '2026-02-23T00:00:00Z');
    });

    test('table still has all expected columns', () async {
      await runNullifySecretColumnsMigration(db);

      final columns = await db.rawQuery('PRAGMA table_info(identity)');
      final columnNames = columns.map((c) => c['name'] as String).toList();

      expect(columnNames, containsAll([
        'id',
        'peer_id',
        'public_key',
        'private_key',
        'mnemonic12',
        'ml_kem_public_key',
        'ml_kem_secret_key',
        'username',
        'avatar_path',
        'created_at',
        'updated_at',
      ]));
      expect(columnNames.length, 11);
    });

    test('ml_kem columns preserved', () async {
      // Insert data with ML-KEM keys before migration
      await db.rawInsert(
        'INSERT INTO identity (peer_id, public_key, private_key, mnemonic12, ml_kem_public_key, ml_kem_secret_key, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        ['peer1', 'pubkey1', 'privkey1', 'mnemonic', 'mlkem_pub_key', 'mlkem_sec_key', '2026-02-23T00:00:00Z', '2026-02-23T00:00:00Z'],
      );

      await runNullifySecretColumnsMigration(db);

      final rows = await db.query('identity');
      expect(rows.length, 1);
      expect(rows[0]['ml_kem_public_key'], 'mlkem_pub_key');
      expect(rows[0]['ml_kem_secret_key'], 'mlkem_sec_key');
    });

    test('can insert row with null private_key and mnemonic12', () async {
      await runNullifySecretColumnsMigration(db);

      await db.rawInsert(
        'INSERT INTO identity (peer_id, public_key, private_key, mnemonic12, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        ['peer1', 'pubkey1', null, null, '2026-02-23T00:00:00Z', '2026-02-23T00:00:00Z'],
      );

      final rows = await db.query('identity');
      expect(rows.length, 1);
      expect(rows[0]['private_key'], isNull);
      expect(rows[0]['mnemonic12'], isNull);
    });

    test('running twice does not throw but recreates table', () async {
      await runNullifySecretColumnsMigration(db);

      // Insert data after first run
      await db.rawInsert(
        'INSERT INTO identity (peer_id, public_key, private_key, mnemonic12, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        ['peer1', 'pubkey1', null, null, '2026-02-23T00:00:00Z', '2026-02-23T00:00:00Z'],
      );

      // Running again succeeds (rename→create→copy→drop completes cleanly)
      await runNullifySecretColumnsMigration(db);

      // Data is preserved through the second run
      final rows = await db.query('identity');
      expect(rows.length, 1);
      expect(rows[0]['peer_id'], 'peer1');
    });
  });
}
