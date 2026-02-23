import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/001_identity_table.dart';
import 'package:flutter_app/core/database/migrations/003_mlkem_keys.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    // 003 requires 001 tables to exist
    await runIdentityTableMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('Migration 003: ML-KEM key columns', () {
    test('adds ml_kem_public_key to identity', () async {
      await runMlKemKeysMigration(db);

      final columns = await db.rawQuery('PRAGMA table_info(identity)');
      final columnNames = columns.map((c) => c['name'] as String).toList();
      expect(columnNames, contains('ml_kem_public_key'));
    });

    test('adds ml_kem_secret_key to identity', () async {
      await runMlKemKeysMigration(db);

      final columns = await db.rawQuery('PRAGMA table_info(identity)');
      final columnNames = columns.map((c) => c['name'] as String).toList();
      expect(columnNames, contains('ml_kem_secret_key'));
    });

    test('adds ml_kem_public_key to contacts', () async {
      await runMlKemKeysMigration(db);

      final columns = await db.rawQuery('PRAGMA table_info(contacts)');
      final columnNames = columns.map((c) => c['name'] as String).toList();
      expect(columnNames, contains('ml_kem_public_key'));
    });

    test('adds ml_kem_public_key to contact_requests', () async {
      await runMlKemKeysMigration(db);

      final columns = await db.rawQuery('PRAGMA table_info(contact_requests)');
      final columnNames = columns.map((c) => c['name'] as String).toList();
      expect(columnNames, contains('ml_kem_public_key'));
    });

    test('new columns are nullable', () async {
      await runMlKemKeysMigration(db);

      // Insert a row into identity without specifying ML-KEM columns
      await db.rawInsert(
        'INSERT INTO identity (peer_id, public_key, private_key, mnemonic12, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        ['peer1', 'pubkey1', 'privkey1', 'mnemonic words', '2026-02-23T00:00:00Z', '2026-02-23T00:00:00Z'],
      );

      final rows = await db.query('identity');
      expect(rows.length, 1);
      expect(rows[0]['ml_kem_public_key'], isNull);
      expect(rows[0]['ml_kem_secret_key'], isNull);

      // Insert a row into contacts without specifying ML-KEM column
      await db.rawInsert(
        'INSERT INTO contacts (peer_id, public_key, rendezvous, username, signature, scanned_at) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        ['peer2', 'pubkey2', 'rdv2', 'Bob', 'sig2', '2026-02-23T00:00:00Z'],
      );

      final contactRows = await db.query('contacts');
      expect(contactRows.length, 1);
      expect(contactRows[0]['ml_kem_public_key'], isNull);

      // Insert a row into contact_requests without specifying ML-KEM column
      await db.rawInsert(
        'INSERT INTO contact_requests (peer_id, public_key, rendezvous, username, signature, received_at) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        ['peer3', 'pubkey3', 'rdv3', 'Carol', 'sig3', '2026-02-23T00:00:00Z'],
      );

      final requestRows = await db.query('contact_requests');
      expect(requestRows.length, 1);
      expect(requestRows[0]['ml_kem_public_key'], isNull);
    });

    test('NOT idempotent: running twice throws', () async {
      await runMlKemKeysMigration(db);

      // ALTER TABLE ADD COLUMN throws when column already exists
      expect(
        () => runMlKemKeysMigration(db),
        throwsA(isA<DatabaseException>()),
      );
    });
  });
}
