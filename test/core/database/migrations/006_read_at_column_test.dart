import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/001_identity_table.dart';
import 'package:flutter_app/core/database/migrations/002_messages_table.dart';
import 'package:flutter_app/core/database/migrations/006_read_at_column.dart';

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

  group('Migration 006: read_at column', () {
    Future<void> runPrerequisites() async {
      await runIdentityTableMigration(db);
      await runMessagesTableMigration(db);
    }

    test('adds read_at column to messages', () async {
      await runPrerequisites();
      await runReadAtColumnMigration(db);

      final columns = await db.rawQuery('PRAGMA table_info(messages)');
      final columnNames =
          columns.map((col) => col['name'] as String).toList();
      expect(columnNames, contains('read_at'));
    });

    test('marks existing incoming messages as read', () async {
      await runPrerequisites();

      // Insert incoming messages BEFORE running 006
      await db.insert('messages', {
        'id': 'msg-1',
        'contact_peer_id': 'peer-a',
        'sender_peer_id': 'peer-a',
        'text': 'hello',
        'timestamp': '2026-01-01T00:00:00.000Z',
        'status': 'sent',
        'is_incoming': 1,
        'created_at': '2026-01-01T00:00:00.000Z',
      });
      await db.insert('messages', {
        'id': 'msg-2',
        'contact_peer_id': 'peer-b',
        'sender_peer_id': 'peer-b',
        'text': 'world',
        'timestamp': '2026-01-02T00:00:00.000Z',
        'status': 'sent',
        'is_incoming': 1,
        'created_at': '2026-01-02T00:00:00.000Z',
      });

      await runReadAtColumnMigration(db);

      final rows = await db.query('messages', orderBy: 'id');
      expect(rows[0]['read_at'], isNotNull);
      expect(rows[1]['read_at'], isNotNull);
    });

    test('does NOT mark outgoing messages as read', () async {
      await runPrerequisites();

      // Insert an outgoing message BEFORE running 006
      await db.insert('messages', {
        'id': 'msg-out-1',
        'contact_peer_id': 'peer-a',
        'sender_peer_id': 'self',
        'text': 'outgoing hello',
        'timestamp': '2026-01-01T00:00:00.000Z',
        'status': 'sent',
        'is_incoming': 0,
        'created_at': '2026-01-01T00:00:00.000Z',
      });

      await runReadAtColumnMigration(db);

      final rows = await db.query('messages',
          where: 'id = ?', whereArgs: ['msg-out-1']);
      expect(rows[0]['read_at'], isNull);
    });

    test('creates idx_messages_unread index', () async {
      await runPrerequisites();
      await runReadAtColumnMigration(db);

      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='messages'",
      );
      final indexNames =
          indexes.map((r) => r['name'] as String).toList();
      expect(indexNames, contains('idx_messages_unread'));
    });

    test('new messages default read_at to NULL', () async {
      await runPrerequisites();
      await runReadAtColumnMigration(db);

      // Insert a new message after migration
      await db.insert('messages', {
        'id': 'msg-new',
        'contact_peer_id': 'peer-c',
        'sender_peer_id': 'peer-c',
        'text': 'new message',
        'timestamp': '2026-02-01T00:00:00.000Z',
        'status': 'sent',
        'is_incoming': 1,
        'created_at': '2026-02-01T00:00:00.000Z',
      });

      final rows = await db.query('messages',
          where: 'id = ?', whereArgs: ['msg-new']);
      expect(rows[0]['read_at'], isNull);
    });

    test('preserves existing message data', () async {
      await runPrerequisites();

      await db.insert('messages', {
        'id': 'msg-preserve',
        'contact_peer_id': 'peer-x',
        'sender_peer_id': 'peer-x',
        'text': 'preserve me',
        'timestamp': '2026-01-15T12:30:00.000Z',
        'status': 'delivered',
        'is_incoming': 1,
        'created_at': '2026-01-15T12:30:00.000Z',
      });

      await runReadAtColumnMigration(db);

      final rows = await db.query('messages',
          where: 'id = ?', whereArgs: ['msg-preserve']);
      expect(rows.length, 1);
      expect(rows[0]['id'], 'msg-preserve');
      expect(rows[0]['contact_peer_id'], 'peer-x');
      expect(rows[0]['sender_peer_id'], 'peer-x');
      expect(rows[0]['text'], 'preserve me');
      expect(rows[0]['timestamp'], '2026-01-15T12:30:00.000Z');
      expect(rows[0]['status'], 'delivered');
      expect(rows[0]['is_incoming'], 1);
      expect(rows[0]['created_at'], '2026-01-15T12:30:00.000Z');
    });

    test('composite index is on correct columns', () async {
      await runPrerequisites();
      await runReadAtColumnMigration(db);

      final indexInfo = await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type='index' AND name='idx_messages_unread'",
      );
      expect(indexInfo.length, 1);
      final sql = indexInfo[0]['sql'] as String;
      expect(sql, contains('contact_peer_id'));
      expect(sql, contains('is_incoming'));
      expect(sql, contains('read_at'));
    });

    test('idempotent: running twice does not throw', () async {
      await runPrerequisites();
      await runReadAtColumnMigration(db);
      // Running again should not throw
      await runReadAtColumnMigration(db);

      // Table should still work
      final columns = await db.rawQuery('PRAGMA table_info(messages)');
      final columnNames =
          columns.map((col) => col['name'] as String).toList();
      expect(columnNames, contains('read_at'));
    });
  });
}
