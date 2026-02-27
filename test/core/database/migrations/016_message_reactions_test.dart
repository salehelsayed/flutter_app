import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/001_identity_table.dart';
import 'package:flutter_app/core/database/migrations/002_messages_table.dart';
import 'package:flutter_app/core/database/migrations/016_message_reactions.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    // 016 is a standalone table (no FK enforced), but we need messages table
    // for integration scenarios
    await runIdentityTableMigration(db);
    await runMessagesTableMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('Migration 016: message_reactions table', () {
    test('creates message_reactions table with correct columns', () async {
      await runMessageReactionsMigration(db);

      final columns = await db.rawQuery('PRAGMA table_info(message_reactions)');
      final columnNames = columns.map((c) => c['name'] as String).toList();

      expect(columnNames, containsAll([
        'id',
        'message_id',
        'emoji',
        'sender_peer_id',
        'timestamp',
        'created_at',
      ]));
    });

    test('id is primary key', () async {
      await runMessageReactionsMigration(db);

      final columns = await db.rawQuery('PRAGMA table_info(message_reactions)');
      final idColumn = columns.firstWhere((c) => c['name'] == 'id');
      expect(idColumn['pk'], 1);
    });

    test('UNIQUE constraint on (message_id, sender_peer_id)', () async {
      await runMessageReactionsMigration(db);

      // First insert succeeds
      await db.insert('message_reactions', {
        'id': 'r1',
        'message_id': 'msg-1',
        'emoji': '👍',
        'sender_peer_id': 'sender-1',
        'timestamp': '2026-02-27T10:00:00.000Z',
        'created_at': '2026-02-27T10:00:01.000Z',
      });

      // Second insert with same message_id + sender_peer_id fails
      expect(
        () async => await db.insert('message_reactions', {
          'id': 'r2',
          'message_id': 'msg-1',
          'emoji': '❤️',
          'sender_peer_id': 'sender-1',
          'timestamp': '2026-02-27T10:01:00.000Z',
          'created_at': '2026-02-27T10:01:01.000Z',
        }),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('allows different senders on same message', () async {
      await runMessageReactionsMigration(db);

      await db.insert('message_reactions', {
        'id': 'r1',
        'message_id': 'msg-1',
        'emoji': '👍',
        'sender_peer_id': 'sender-1',
        'timestamp': '2026-02-27T10:00:00.000Z',
        'created_at': '2026-02-27T10:00:01.000Z',
      });

      await db.insert('message_reactions', {
        'id': 'r2',
        'message_id': 'msg-1',
        'emoji': '❤️',
        'sender_peer_id': 'sender-2',
        'timestamp': '2026-02-27T10:00:00.000Z',
        'created_at': '2026-02-27T10:00:01.000Z',
      });

      final rows = await db.query('message_reactions');
      expect(rows.length, 2);
    });

    test('allows same sender on different messages', () async {
      await runMessageReactionsMigration(db);

      await db.insert('message_reactions', {
        'id': 'r1',
        'message_id': 'msg-1',
        'emoji': '👍',
        'sender_peer_id': 'sender-1',
        'timestamp': '2026-02-27T10:00:00.000Z',
        'created_at': '2026-02-27T10:00:01.000Z',
      });

      await db.insert('message_reactions', {
        'id': 'r2',
        'message_id': 'msg-2',
        'emoji': '👍',
        'sender_peer_id': 'sender-1',
        'timestamp': '2026-02-27T10:00:00.000Z',
        'created_at': '2026-02-27T10:00:01.000Z',
      });

      final rows = await db.query('message_reactions');
      expect(rows.length, 2);
    });

    test('index on message_id exists', () async {
      await runMessageReactionsMigration(db);

      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='message_reactions'",
      );
      expect(
        indexes.map((r) => r['name'] as String),
        contains('idx_message_reactions_message'),
      );
    });

    test('idempotent — running twice does not throw and preserves data',
        () async {
      await runMessageReactionsMigration(db);

      await db.insert('message_reactions', {
        'id': 'r1',
        'message_id': 'msg-1',
        'emoji': '👍',
        'sender_peer_id': 'sender-1',
        'timestamp': '2026-02-27T10:00:00.000Z',
        'created_at': '2026-02-27T10:00:01.000Z',
      });

      // Run again — IF NOT EXISTS should make this a no-op
      await runMessageReactionsMigration(db);

      final rows = await db.query('message_reactions');
      expect(rows.length, 1);
      expect(rows[0]['emoji'], '👍');
    });

    test('UTF-8 emoji stored correctly', () async {
      await runMessageReactionsMigration(db);

      // Multi-codepoint emoji (family with ZWJ)
      await db.insert('message_reactions', {
        'id': 'r1',
        'message_id': 'msg-1',
        'emoji': '👨‍👩‍👧‍👦',
        'sender_peer_id': 'sender-1',
        'timestamp': '2026-02-27T10:00:00.000Z',
        'created_at': '2026-02-27T10:00:01.000Z',
      });

      final rows = await db.query('message_reactions',
          where: 'id = ?', whereArgs: ['r1']);
      expect(rows[0]['emoji'], '👨‍👩‍👧‍👦');
    });
  });
}
