import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/migrations/054_group_reaction_replay_outbox.dart';

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

  group('Migration 054: group reaction replay outbox', () {
    test('creates the outbox table and expected columns', () async {
      await runGroupReactionReplayOutboxMigration(db);

      final columns = await db.rawQuery(
        'PRAGMA table_info(group_reaction_replay_outbox)',
      );
      final columnNames = columns.map((col) => col['name'] as String).toList();

      expect(columnNames, contains('reaction_id'));
      expect(columnNames, contains('group_id'));
      expect(columnNames, contains('message_id'));
      expect(columnNames, contains('sender_peer_id'));
      expect(columnNames, contains('emoji'));
      expect(columnNames, contains('action'));
      expect(columnNames, contains('inbox_retry_payload'));
      expect(columnNames, contains('delivery_status'));
      expect(columnNames, contains('last_error'));
      expect(columnNames, contains('created_at'));
      expect(columnNames, contains('updated_at'));
    });

    test('supports persisted retry rows with pending status', () async {
      await runGroupReactionReplayOutboxMigration(db);

      await db.insert('group_reaction_replay_outbox', {
        'reaction_id': 'reaction-1',
        'group_id': 'group-1',
        'message_id': 'message-1',
        'sender_peer_id': 'peer-1',
        'emoji': '🔥',
        'action': 'add',
        'inbox_retry_payload': '{"groupId":"group-1","message":"payload"}',
        'delivery_status': 'pending',
        'last_error': null,
        'created_at': '2026-04-13T08:00:00.000Z',
        'updated_at': '2026-04-13T08:00:00.000Z',
      });

      final rows = await db.query(
        'group_reaction_replay_outbox',
        where: 'reaction_id = ?',
        whereArgs: ['reaction-1'],
      );

      expect(rows, hasLength(1));
      expect(rows.first['delivery_status'], 'pending');
      expect(
        rows.first['inbox_retry_payload'],
        '{"groupId":"group-1","message":"payload"}',
      );
    });

    test('is idempotent', () async {
      await runGroupReactionReplayOutboxMigration(db);
      await runGroupReactionReplayOutboxMigration(db);

      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' "
        "AND tbl_name='group_reaction_replay_outbox'",
      );
      final indexNames = indexes.map((row) => row['name'] as String).toList();

      expect(
        indexNames,
        contains('idx_group_reaction_replay_outbox_retryable'),
      );
      expect(
        indexNames,
        contains('idx_group_reaction_replay_outbox_group_message'),
      );
    });
  });
}
