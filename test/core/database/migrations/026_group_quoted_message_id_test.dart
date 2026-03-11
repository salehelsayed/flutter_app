import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/017_groups_tables.dart';
import 'package:flutter_app/core/database/migrations/018_group_messages_tables.dart';
import 'package:flutter_app/core/database/migrations/026_group_quoted_message_id.dart';

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

  group('Migration 026: group_messages.quoted_message_id', () {
    Future<void> runPrerequisites() async {
      await runGroupsTablesMigration(db);
      await runGroupMessagesTablesMigration(db);
    }

    test('adds quoted_message_id column to group_messages', () async {
      await runPrerequisites();
      await runGroupQuotedMessageIdMigration(db);

      final columns = await db.rawQuery('PRAGMA table_info(group_messages)');
      final columnNames = columns.map((col) => col['name'] as String).toList();
      expect(columnNames, contains('quoted_message_id'));
    });

    test('existing rows get null quoted_message_id on upgrade', () async {
      await runPrerequisites();
      await db.insert('group_messages', {
        'id': 'msg-existing',
        'group_id': 'group-1',
        'sender_peer_id': 'peer-a',
        'sender_username': 'Alice',
        'text': 'existing message',
        'timestamp': '2026-01-15T00:00:00.000Z',
        'key_generation': 0,
        'status': 'sent',
        'is_incoming': 1,
        'created_at': '2026-01-15T00:00:00.000Z',
      });

      await runGroupQuotedMessageIdMigration(db);

      final rows = await db.query(
        'group_messages',
        where: 'id = ?',
        whereArgs: ['msg-existing'],
      );
      expect(rows.first['quoted_message_id'], isNull);
    });

    test('can store a quoted parent id after migration', () async {
      await runPrerequisites();
      await runGroupQuotedMessageIdMigration(db);

      await db.insert('group_messages', {
        'id': 'msg-reply',
        'group_id': 'group-1',
        'sender_peer_id': 'peer-a',
        'sender_username': 'Alice',
        'text': 'reply',
        'timestamp': '2026-01-15T00:00:00.000Z',
        'quoted_message_id': 'msg-parent',
        'key_generation': 0,
        'status': 'sent',
        'is_incoming': 1,
        'created_at': '2026-01-15T00:00:00.000Z',
      });

      final rows = await db.query(
        'group_messages',
        where: 'id = ?',
        whereArgs: ['msg-reply'],
      );
      expect(rows.first['quoted_message_id'], 'msg-parent');
    });

    test('is idempotent', () async {
      await runPrerequisites();
      await runGroupQuotedMessageIdMigration(db);
      await runGroupQuotedMessageIdMigration(db);

      final columns = await db.rawQuery('PRAGMA table_info(group_messages)');
      final columnNames = columns.map((col) => col['name'] as String).toList();
      expect(columnNames, contains('quoted_message_id'));
    });
  });
}
