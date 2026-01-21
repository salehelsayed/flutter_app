import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/migrations/001_identity_table.dart';
import 'package:flutter_app/core/database/helpers/identity_db_helpers.dart';

void main() {
  // Initialize FFI for desktop testing
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;

  setUp(() async {
    // Create in-memory database for each test
    db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
    );
    // Run migration
    await runIdentityTableMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('DB_XS_01 - Migration', () {
    test('creates identity table', () async {
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='identity'",
      );
      expect(tables.length, 1);
      expect(tables.first['name'], 'identity');
    });

    test('migration is idempotent', () async {
      // Running twice should not throw
      await runIdentityTableMigration(db);
      await runIdentityTableMigration(db);
    });
  });

  group('DB_XS_02 - Load Identity', () {
    test('returns null when no identity exists', () async {
      final result = await dbLoadIdentityRow(db);
      expect(result, isNull);
    });

    test('returns row when identity exists', () async {
      // Insert test data directly
      await db.insert('identity', {
        'id': 1,
        'peer_id': '12D3KooWTest',
        'public_key': 'dGVzdC1wdWJsaWMta2V5',
        'private_key': 'dGVzdC1wcml2YXRlLWtleQ==',
        'mnemonic12': 'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
        'created_at': '2025-01-01T00:00:00.000Z',
        'updated_at': '2025-01-01T00:00:00.000Z',
      });

      final result = await dbLoadIdentityRow(db);
      
      expect(result, isNotNull);
      expect(result!['peer_id'], '12D3KooWTest');
      expect(result['public_key'], 'dGVzdC1wdWJsaWMta2V5');
    });
  });

  group('DB_XS_03 - Upsert Identity', () {
    test('inserts new identity', () async {
      await dbUpsertIdentityRow(db, {
        'peer_id': '12D3KooWNew',
        'public_key': 'bmV3LXB1YmxpYy1rZXk=',
        'private_key': 'bmV3LXByaXZhdGUta2V5',
        'mnemonic12': 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
        'created_at': '2025-01-01T00:00:00.000Z',
        'updated_at': '2025-01-01T00:00:00.000Z',
      });

      final result = await dbLoadIdentityRow(db);
      expect(result, isNotNull);
      expect(result!['peer_id'], '12D3KooWNew');
    });

    test('replaces existing identity', () async {
      // Insert first
      await dbUpsertIdentityRow(db, {
        'peer_id': '12D3KooWFirst',
        'public_key': 'Zmlyc3Q=',
        'private_key': 'Zmlyc3Q=',
        'mnemonic12': 'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
        'created_at': '2025-01-01T00:00:00.000Z',
        'updated_at': '2025-01-01T00:00:00.000Z',
      });

      // Replace with second
      await dbUpsertIdentityRow(db, {
        'peer_id': '12D3KooWSecond',
        'public_key': 'c2Vjb25k',
        'private_key': 'c2Vjb25k',
        'mnemonic12': 'zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong',
        'created_at': '2025-01-01T00:00:00.000Z',
        'updated_at': '2025-01-02T00:00:00.000Z',
      });

      final result = await dbLoadIdentityRow(db);
      expect(result, isNotNull);
      expect(result!['peer_id'], '12D3KooWSecond');

      // Verify only one row exists
      final count = await db.rawQuery('SELECT COUNT(*) as cnt FROM identity');
      expect(count.first['cnt'], 1);
    });
  });
}
