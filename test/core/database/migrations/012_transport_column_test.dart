import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/001_identity_table.dart';
import 'package:flutter_app/core/database/migrations/002_messages_table.dart';
import 'package:flutter_app/core/database/migrations/012_transport_column.dart';

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

  group('Migration 012: transport column', () {
    Future<void> runPrerequisites() async {
      await runIdentityTableMigration(db);
      await runMessagesTableMigration(db);
    }

    test('adds transport column to messages', () async {
      await runPrerequisites();
      await runTransportColumnMigration(db);

      final columns = await db.rawQuery('PRAGMA table_info(messages)');
      final columnNames =
          columns.map((col) => col['name'] as String).toList();
      expect(columnNames, contains('transport'));
    });

    test('column is nullable (insert with null)', () async {
      await runPrerequisites();
      await runTransportColumnMigration(db);

      await db.insert('messages', {
        'id': 'msg-null-transport',
        'contact_peer_id': 'peer-a',
        'sender_peer_id': 'peer-a',
        'text': 'no transport',
        'timestamp': '2026-02-01T00:00:00.000Z',
        'status': 'sent',
        'is_incoming': 1,
        'created_at': '2026-02-01T00:00:00.000Z',
        'transport': null,
      });

      final rows = await db.query('messages',
          where: 'id = ?', whereArgs: ['msg-null-transport']);
      expect(rows[0]['transport'], isNull);
    });

    test('can store wifi value', () async {
      await runPrerequisites();
      await runTransportColumnMigration(db);

      await db.insert('messages', {
        'id': 'msg-wifi',
        'contact_peer_id': 'peer-a',
        'sender_peer_id': 'peer-a',
        'text': 'wifi message',
        'timestamp': '2026-02-01T00:00:00.000Z',
        'status': 'sent',
        'is_incoming': 1,
        'created_at': '2026-02-01T00:00:00.000Z',
        'transport': 'wifi',
      });

      final rows = await db.query('messages',
          where: 'id = ?', whereArgs: ['msg-wifi']);
      expect(rows[0]['transport'], 'wifi');
    });

    test('can store relay value', () async {
      await runPrerequisites();
      await runTransportColumnMigration(db);

      await db.insert('messages', {
        'id': 'msg-relay',
        'contact_peer_id': 'peer-a',
        'sender_peer_id': 'peer-a',
        'text': 'relay message',
        'timestamp': '2026-02-01T00:00:00.000Z',
        'status': 'sent',
        'is_incoming': 1,
        'created_at': '2026-02-01T00:00:00.000Z',
        'transport': 'relay',
      });

      final rows = await db.query('messages',
          where: 'id = ?', whereArgs: ['msg-relay']);
      expect(rows[0]['transport'], 'relay');
    });

    test('can store inbox value', () async {
      await runPrerequisites();
      await runTransportColumnMigration(db);

      await db.insert('messages', {
        'id': 'msg-inbox',
        'contact_peer_id': 'peer-a',
        'sender_peer_id': 'peer-a',
        'text': 'inbox message',
        'timestamp': '2026-02-01T00:00:00.000Z',
        'status': 'sent',
        'is_incoming': 1,
        'created_at': '2026-02-01T00:00:00.000Z',
        'transport': 'inbox',
      });

      final rows = await db.query('messages',
          where: 'id = ?', whereArgs: ['msg-inbox']);
      expect(rows[0]['transport'], 'inbox');
    });

    test('existing messages get null transport', () async {
      await runPrerequisites();

      // Insert a message BEFORE running 012
      await db.insert('messages', {
        'id': 'msg-existing',
        'contact_peer_id': 'peer-b',
        'sender_peer_id': 'peer-b',
        'text': 'existing message',
        'timestamp': '2026-01-15T00:00:00.000Z',
        'status': 'sent',
        'is_incoming': 1,
        'created_at': '2026-01-15T00:00:00.000Z',
      });

      await runTransportColumnMigration(db);

      final rows = await db.query('messages',
          where: 'id = ?', whereArgs: ['msg-existing']);
      expect(rows[0]['transport'], isNull);
    });

    test('idempotent: running twice does not throw', () async {
      await runPrerequisites();
      await runTransportColumnMigration(db);
      // Running again should not throw
      await runTransportColumnMigration(db);

      // Table should still work
      final columns = await db.rawQuery('PRAGMA table_info(messages)');
      final columnNames =
          columns.map((col) => col['name'] as String).toList();
      expect(columnNames, contains('transport'));
    });

    test('migration handles missing messages table gracefully', () async {
      // Do NOT run prerequisites so the messages table does not exist.
      // The PRAGMA table_info on a non-existent table returns empty list,
      // so hasColumn is false, and ALTER TABLE will throw because the table
      // does not exist. The migration rethrows this error.
      expect(
        () => runTransportColumnMigration(db),
        throwsA(isA<DatabaseException>()),
      );
    });
  });
}
