import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/001_identity_table.dart';
import 'package:flutter_app/core/database/migrations/003_mlkem_keys.dart';
import 'package:flutter_app/core/database/migrations/004_nullify_secret_columns.dart';
import 'package:flutter_app/core/secure_storage/migrate_secrets_to_secure_storage.dart';
import 'fake_secure_key_store.dart';

void main() {
  late Database db;
  late FakeSecureKeyStore secureKeyStore;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runIdentityTableMigration(db);
    await runMlKemKeysMigration(db);
    await runNullifySecretColumnsMigration(db);
    secureKeyStore = FakeSecureKeyStore();
  });

  tearDown(() async {
    await db.close();
  });

  test('Fresh install (no identity) — marks migrated', () async {
    await migrateSecretsToSecureStorage(db: db, secureKeyStore: secureKeyStore);

    expect(await secureKeyStore.containsKey('secrets_migrated'), isTrue);
    expect(await secureKeyStore.read('identity_private_key'), isNull);
    expect(await secureKeyStore.read('identity_mnemonic12'), isNull);
    expect(await secureKeyStore.read('identity_ml_kem_secret_key'), isNull);
  });

  test('Existing identity — copies secrets and nulls columns', () async {
    // Insert an identity with secrets in DB
    await db.insert('identity', {
      'id': 1,
      'peer_id': '12D3KooWTestPeer',
      'public_key': 'pub-key',
      'private_key': 'secret-private-key',
      'mnemonic12': 'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
      'ml_kem_public_key': 'mlkem-pub',
      'ml_kem_secret_key': 'mlkem-secret-key',
      'username': 'TestUser',
      'created_at': '2025-01-01T00:00:00Z',
      'updated_at': '2025-01-01T00:00:00Z',
    });

    await migrateSecretsToSecureStorage(db: db, secureKeyStore: secureKeyStore);

    // Secrets should be in secure storage
    expect(await secureKeyStore.read('identity_private_key'), 'secret-private-key');
    expect(
      await secureKeyStore.read('identity_mnemonic12'),
      'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
    );
    expect(await secureKeyStore.read('identity_ml_kem_secret_key'), 'mlkem-secret-key');
    expect(await secureKeyStore.containsKey('secrets_migrated'), isTrue);

    // DB columns should be null
    final row = (await db.query('identity', where: 'id = ?', whereArgs: [1])).first;
    expect(row['private_key'], isNull);
    expect(row['mnemonic12'], isNull);
    expect(row['ml_kem_secret_key'], isNull);
    // Non-secret columns preserved
    expect(row['peer_id'], '12D3KooWTestPeer');
    expect(row['public_key'], 'pub-key');
    expect(row['ml_kem_public_key'], 'mlkem-pub');
  });

  test('Already migrated — skips immediately', () async {
    await secureKeyStore.write('secrets_migrated', 'true');

    // Insert identity with secrets still in DB (shouldn't be touched)
    await db.insert('identity', {
      'id': 1,
      'peer_id': '12D3KooWTestPeer',
      'public_key': 'pub-key',
      'private_key': 'should-not-be-copied',
      'mnemonic12': 'should not be copied either at all',
      'username': 'TestUser',
      'created_at': '2025-01-01T00:00:00Z',
      'updated_at': '2025-01-01T00:00:00Z',
    });

    await migrateSecretsToSecureStorage(db: db, secureKeyStore: secureKeyStore);

    // Secrets should NOT be in secure storage (skipped)
    expect(await secureKeyStore.read('identity_private_key'), isNull);
    expect(await secureKeyStore.read('identity_mnemonic12'), isNull);

    // DB columns should still have values (not touched)
    final row = (await db.query('identity', where: 'id = ?', whereArgs: [1])).first;
    expect(row['private_key'], 'should-not-be-copied');
  });

  test('Partial migration — re-runs safely', () async {
    // Simulate partial migration: secrets in secure storage but no sentinel
    await secureKeyStore.write('identity_private_key', 'already-migrated-key');

    await db.insert('identity', {
      'id': 1,
      'peer_id': '12D3KooWTestPeer',
      'public_key': 'pub-key',
      'private_key': 'db-private-key',
      'mnemonic12': 'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
      'username': 'TestUser',
      'created_at': '2025-01-01T00:00:00Z',
      'updated_at': '2025-01-01T00:00:00Z',
    });

    await migrateSecretsToSecureStorage(db: db, secureKeyStore: secureKeyStore);

    // Should overwrite with DB values (idempotent)
    expect(await secureKeyStore.read('identity_private_key'), 'db-private-key');
    expect(await secureKeyStore.containsKey('secrets_migrated'), isTrue);

    // DB columns should be nulled
    final row = (await db.query('identity', where: 'id = ?', whereArgs: [1])).first;
    expect(row['private_key'], isNull);
    expect(row['mnemonic12'], isNull);
  });
}
