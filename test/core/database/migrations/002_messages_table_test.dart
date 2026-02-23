import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/002_messages_table.dart';

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

  group('Migration 002: messages table', () {
    test('creates messages table', () async {
      await runMessagesTableMigration(db);

      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='messages'",
      );
      expect(tables.length, 1);
      expect(tables.first['name'], 'messages');
    });

    test('table has correct columns', () async {
      await runMessagesTableMigration(db);

      final columns = await db.rawQuery('PRAGMA table_info(messages)');
      final columnNames = columns.map((c) => c['name'] as String).toList();

      expect(columnNames, containsAll([
        'id',
        'contact_peer_id',
        'sender_peer_id',
        'text',
        'timestamp',
        'status',
        'is_incoming',
        'created_at',
      ]));
      expect(columnNames.length, 8);
    });

    test('status defaults to sent', () async {
      await runMessagesTableMigration(db);

      await db.rawInsert(
        'INSERT INTO messages (id, contact_peer_id, sender_peer_id, text, timestamp, is_incoming, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        ['msg-1', 'contact1', 'sender1', 'Hello', '2026-02-23T00:00:00Z', 0, '2026-02-23T00:00:00Z'],
      );

      final rows = await db.query('messages');
      expect(rows.length, 1);
      expect(rows[0]['status'], 'sent');
    });

    test('is_incoming defaults to 0', () async {
      await runMessagesTableMigration(db);

      await db.rawInsert(
        'INSERT INTO messages (id, contact_peer_id, sender_peer_id, text, timestamp, status, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        ['msg-2', 'contact1', 'sender1', 'Hello', '2026-02-23T00:00:00Z', 'sent', '2026-02-23T00:00:00Z'],
      );

      final rows = await db.query('messages');
      expect(rows.length, 1);
      expect(rows[0]['is_incoming'], 0);
    });

    test('creates idx_messages_contact index', () async {
      await runMessagesTableMigration(db);

      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='messages'",
      );
      final indexNames = indexes.map((r) => r['name'] as String).toList();
      expect(indexNames, contains('idx_messages_contact'));
    });

    test('creates idx_messages_ts index', () async {
      await runMessagesTableMigration(db);

      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='messages'",
      );
      final indexNames = indexes.map((r) => r['name'] as String).toList();
      expect(indexNames, contains('idx_messages_ts'));
    });

    test('can insert and query a row', () async {
      await runMessagesTableMigration(db);

      await db.insert('messages', {
        'id': 'msg-full',
        'contact_peer_id': 'contact1',
        'sender_peer_id': 'sender1',
        'text': 'Hello world',
        'timestamp': '2026-02-23T12:00:00Z',
        'status': 'delivered',
        'is_incoming': 1,
        'created_at': '2026-02-23T12:00:00Z',
      });

      final rows = await db.query('messages', where: 'id = ?', whereArgs: ['msg-full']);
      expect(rows.length, 1);
      expect(rows[0]['id'], 'msg-full');
      expect(rows[0]['contact_peer_id'], 'contact1');
      expect(rows[0]['sender_peer_id'], 'sender1');
      expect(rows[0]['text'], 'Hello world');
      expect(rows[0]['timestamp'], '2026-02-23T12:00:00Z');
      expect(rows[0]['status'], 'delivered');
      expect(rows[0]['is_incoming'], 1);
      expect(rows[0]['created_at'], '2026-02-23T12:00:00Z');
    });

    test('idempotent: running twice does not throw', () async {
      await runMessagesTableMigration(db);
      await runMessagesTableMigration(db);

      // Table should still work
      final rows = await db.query('messages');
      expect(rows, isEmpty);
    });
  });
}
