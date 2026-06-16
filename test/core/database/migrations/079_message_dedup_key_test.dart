import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/migrations/002_messages_table.dart';
import 'package:flutter_app/core/database/migrations/079_message_dedup_key.dart';

/// F8 tier-2 — migration 079: the `dedup_key` column on `messages`.
///
/// Wire-stamped propagated source-id (survives a forward's id+timestamp
/// re-mint). Nullable: legacy rows carry NULL and fall back to tier-1.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await runMessagesTableMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<List<String>> messageColumns() async {
    final columns = await db.rawQuery('PRAGMA table_info(messages)');
    return columns.map((column) => column['name'] as String).toList();
  }

  Future<List<String>> messageIndexes() async {
    final rows = await db.rawQuery('PRAGMA index_list(messages)');
    return rows.map((row) => row['name'] as String).toList();
  }

  test(
    'migration 079 adds the nullable dedup_key column + a non-unique index',
    () async {
      expect(await messageColumns(), isNot(contains('dedup_key')));

      await runMessageDedupKeyMigration(db);

      expect(await messageColumns(), contains('dedup_key'));
      expect(await messageIndexes(), contains('idx_messages_dedup_key'));

      // Index is deliberately NON-unique (legitimate repeated forwards share a
      // key). PRAGMA index_list reports unique=0 for a non-unique index.
      final indexInfo = await db.rawQuery('PRAGMA index_list(messages)');
      final dedupIdx = indexInfo.firstWhere(
        (row) => row['name'] == 'idx_messages_dedup_key',
      );
      expect(dedupIdx['unique'], 0);
    },
  );

  test('preserves existing rows with a NULL dedup_key', () async {
    await db.insert('messages', {
      'id': 'legacy-msg-1',
      'contact_peer_id': 'peer-a',
      'sender_peer_id': 'peer-a',
      'text': 'pre-079 row',
      'timestamp': '2026-06-01T10:00:00.000Z',
      'status': 'delivered',
      'is_incoming': 1,
      'created_at': '2026-06-01T10:00:00.000Z',
    });

    await runMessageDedupKeyMigration(db);

    final row = (await db.query(
      'messages',
      where: 'id = ?',
      whereArgs: ['legacy-msg-1'],
    )).single;
    expect(row['text'], 'pre-079 row');
    expect(row['dedup_key'], isNull);
  });

  test('is idempotent (column + index guards)', () async {
    await runMessageDedupKeyMigration(db);
    await runMessageDedupKeyMigration(db);

    final dedupColumns = (await messageColumns())
        .where((name) => name == 'dedup_key')
        .toList();
    expect(dedupColumns, hasLength(1));
    final dedupIndexes = (await messageIndexes())
        .where((name) => name == 'idx_messages_dedup_key')
        .toList();
    expect(dedupIndexes, hasLength(1));
  });
}
