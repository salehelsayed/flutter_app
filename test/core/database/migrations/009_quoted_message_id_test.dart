import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/001_identity_table.dart';
import 'package:flutter_app/core/database/migrations/002_messages_table.dart';
import 'package:flutter_app/core/database/migrations/009_quoted_message_id.dart';

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

  group('Migration 009: quoted_message_id column', () {
    Future<void> runPrerequisites() async {
      await runIdentityTableMigration(db);
      await runMessagesTableMigration(db);
    }

    test('adds quoted_message_id column to messages', () async {
      await runPrerequisites();
      await runQuotedMessageIdMigration(db);

      final columns = await db.rawQuery('PRAGMA table_info(messages)');
      final columnNames =
          columns.map((col) => col['name'] as String).toList();
      expect(columnNames, contains('quoted_message_id'));
    });

    test('column is nullable (insert with null)', () async {
      await runPrerequisites();
      await runQuotedMessageIdMigration(db);

      await db.insert('messages', {
        'id': 'msg-no-quote',
        'contact_peer_id': 'peer-a',
        'sender_peer_id': 'peer-a',
        'text': 'no quote',
        'timestamp': '2026-02-01T00:00:00.000Z',
        'status': 'sent',
        'is_incoming': 1,
        'created_at': '2026-02-01T00:00:00.000Z',
        'quoted_message_id': null,
      });

      final rows = await db.query('messages',
          where: 'id = ?', whereArgs: ['msg-no-quote']);
      expect(rows[0]['quoted_message_id'], isNull);
    });

    test('can store a message ID value', () async {
      await runPrerequisites();
      await runQuotedMessageIdMigration(db);

      await db.insert('messages', {
        'id': 'msg-with-quote',
        'contact_peer_id': 'peer-a',
        'sender_peer_id': 'self',
        'text': 'replying to you',
        'timestamp': '2026-02-01T00:00:00.000Z',
        'status': 'sent',
        'is_incoming': 0,
        'created_at': '2026-02-01T00:00:00.000Z',
        'quoted_message_id': 'original-msg-uuid-123',
      });

      final rows = await db.query('messages',
          where: 'id = ?', whereArgs: ['msg-with-quote']);
      expect(rows[0]['quoted_message_id'], 'original-msg-uuid-123');
    });

    test('existing messages get null quoted_message_id', () async {
      await runPrerequisites();

      // Insert a message BEFORE running 009
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

      await runQuotedMessageIdMigration(db);

      final rows = await db.query('messages',
          where: 'id = ?', whereArgs: ['msg-existing']);
      expect(rows[0]['quoted_message_id'], isNull);
    });

    test('idempotent: running twice does not throw', () async {
      await runPrerequisites();
      await runQuotedMessageIdMigration(db);
      // Running again should not throw
      await runQuotedMessageIdMigration(db);

      // Table should still work
      final columns = await db.rawQuery('PRAGMA table_info(messages)');
      final columnNames =
          columns.map((col) => col['name'] as String).toList();
      expect(columnNames, contains('quoted_message_id'));
    });
  });
}
