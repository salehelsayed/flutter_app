import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/001_identity_table.dart';

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

  group('Migration 001: identity, contacts, contact_requests tables', () {
    test('creates identity table', () async {
      await runIdentityTableMigration(db);

      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='identity'",
      );
      expect(tables.length, 1);
      expect(tables.first['name'], 'identity');
    });

    test('creates contacts table', () async {
      await runIdentityTableMigration(db);

      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='contacts'",
      );
      expect(tables.length, 1);
      expect(tables.first['name'], 'contacts');
    });

    test('creates contact_requests table', () async {
      await runIdentityTableMigration(db);

      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='contact_requests'",
      );
      expect(tables.length, 1);
      expect(tables.first['name'], 'contact_requests');
    });

    test('identity table has correct columns', () async {
      await runIdentityTableMigration(db);

      final columns = await db.rawQuery('PRAGMA table_info(identity)');
      final columnNames = columns.map((c) => c['name'] as String).toList();

      expect(columnNames, containsAll([
        'id',
        'peer_id',
        'public_key',
        'private_key',
        'mnemonic12',
        'username',
        'avatar_path',
        'created_at',
        'updated_at',
      ]));
      expect(columnNames.length, 9);
    });

    test('contacts table has correct columns', () async {
      await runIdentityTableMigration(db);

      final columns = await db.rawQuery('PRAGMA table_info(contacts)');
      final columnNames = columns.map((c) => c['name'] as String).toList();

      expect(columnNames, containsAll([
        'peer_id',
        'public_key',
        'rendezvous',
        'username',
        'signature',
        'scanned_at',
        'avatar_path',
      ]));
      expect(columnNames.length, 7);
    });

    test('contact_requests table has correct columns', () async {
      await runIdentityTableMigration(db);

      final columns = await db.rawQuery('PRAGMA table_info(contact_requests)');
      final columnNames = columns.map((c) => c['name'] as String).toList();

      expect(columnNames, containsAll([
        'peer_id',
        'public_key',
        'rendezvous',
        'username',
        'signature',
        'received_at',
        'status',
      ]));
      expect(columnNames.length, 7);
    });

    test('username default is Username on identity table', () async {
      await runIdentityTableMigration(db);

      // Insert a row without specifying username to test the default
      await db.rawInsert(
        'INSERT INTO identity (peer_id, public_key, private_key, mnemonic12, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        ['peer1', 'pubkey1', 'privkey1', 'mnemonic words', '2026-02-23T00:00:00Z', '2026-02-23T00:00:00Z'],
      );

      final rows = await db.query('identity');
      expect(rows.length, 1);
      expect(rows[0]['username'], 'Username');
    });

    test('status default is pending on contact_requests table', () async {
      await runIdentityTableMigration(db);

      // Insert a row without specifying status to test the default
      await db.rawInsert(
        'INSERT INTO contact_requests (peer_id, public_key, rendezvous, username, signature, received_at) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        ['peer1', 'pubkey1', 'rdv1', 'Alice', 'sig1', '2026-02-23T00:00:00Z'],
      );

      final rows = await db.query('contact_requests');
      expect(rows.length, 1);
      expect(rows[0]['status'], 'pending');
    });

    test('idempotent: running twice does not throw', () async {
      await runIdentityTableMigration(db);
      await runIdentityTableMigration(db);

      // Tables should still exist and be queryable
      final identityRows = await db.query('identity');
      expect(identityRows, isEmpty);

      final contactsRows = await db.query('contacts');
      expect(contactsRows, isEmpty);

      final requestsRows = await db.query('contact_requests');
      expect(requestsRows, isEmpty);
    });
  });
}
