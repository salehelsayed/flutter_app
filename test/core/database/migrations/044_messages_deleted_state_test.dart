import 'package:flutter_app/core/database/migrations/001_identity_table.dart';
import 'package:flutter_app/core/database/migrations/002_messages_table.dart';
import 'package:flutter_app/core/database/migrations/044_messages_deleted_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

  group('Migration 044: deleted message state columns', () {
    Future<void> runPrerequisites() async {
      await runIdentityTableMigration(db);
      await runMessagesTableMigration(db);
    }

    test('adds deleted state columns to messages', () async {
      await runPrerequisites();
      await runMessagesDeletedStateMigration(db);

      final columns = await db.rawQuery('PRAGMA table_info(messages)');
      final columnNames = columns.map((col) => col['name'] as String).toList();

      expect(columnNames, contains('deleted_at'));
      expect(columnNames, contains('deleted_by_peer_id'));
      expect(columnNames, contains('hidden_at'));
    });

    test('existing rows get null deleted state values after upgrade', () async {
      await runPrerequisites();
      await db.insert('messages', {
        'id': 'msg-existing',
        'contact_peer_id': 'peer-a',
        'sender_peer_id': 'peer-a',
        'text': 'hello',
        'timestamp': '2026-03-31T00:00:00.000Z',
        'status': 'sent',
        'is_incoming': 1,
        'created_at': '2026-03-31T00:00:00.000Z',
      });

      await runMessagesDeletedStateMigration(db);

      final row = (await db.query(
        'messages',
        where: 'id = ?',
        whereArgs: ['msg-existing'],
      )).single;

      expect(row['deleted_at'], isNull);
      expect(row['deleted_by_peer_id'], isNull);
      expect(row['hidden_at'], isNull);
    });

    test('is idempotent when run twice', () async {
      await runPrerequisites();
      await runMessagesDeletedStateMigration(db);
      await runMessagesDeletedStateMigration(db);

      final columns = await db.rawQuery('PRAGMA table_info(messages)');
      final columnNames = columns.map((col) => col['name'] as String).toList();

      expect(columnNames.where((name) => name == 'deleted_at'), hasLength(1));
      expect(
        columnNames.where((name) => name == 'deleted_by_peer_id'),
        hasLength(1),
      );
      expect(columnNames.where((name) => name == 'hidden_at'), hasLength(1));
    });
  });
}
