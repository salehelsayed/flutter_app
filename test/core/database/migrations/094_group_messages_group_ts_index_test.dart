// ignore_for_file: file_names

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/migrations/018_group_messages_tables.dart';
import 'package:flutter_app/core/database/migrations/094_group_messages_group_ts_index.dart';

void main() {
  // QW-6 (db-persistence-5): the hot group page query orders by a TWO-term
  // `timestamp DESC, id DESC`, so the index MUST be 3-col
  // (group_id, timestamp, id) — a 2-col index leaves
  // `USE TEMP B-TREE FOR LAST TERM OF ORDER BY` (Finding-1 HIGH). Plain sqflite
  // FFI in-memory (cipher-agnostic SQL).
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // The exact residual-filter literal the production helper passes.
  const removalCutoffLike = 'sys-member_removed_cutoff:%';

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await runGroupMessagesTablesMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<bool> indexExists(Database d, String name) async {
    final rows = await d.query(
      'sqlite_master',
      where: "type = 'index' AND name = ?",
      whereArgs: [name],
    );
    return rows.isNotEmpty;
  }

  Future<String> queryPlan(
    Database d,
    String sql,
    List<Object?> args,
  ) async {
    final rows = await d.rawQuery('EXPLAIN QUERY PLAN $sql', args);
    return rows.map((r) => r['detail']).join('\n').toUpperCase();
  }

  Future<void> seedGroupMessages(Database d) async {
    final batch = d.batch();
    for (var i = 0; i < 60; i++) {
      final mm = (i % 60).toString().padLeft(2, '0');
      batch.insert('group_messages', <String, Object?>{
        'id': 'gm$i',
        'group_id': 'groupX',
        'sender_peer_id': 'peerX',
        'text': 'hello $i',
        'timestamp': '2026-06-24T10:$mm:00.000Z',
        'created_at': '2026-06-24T10:00:00.000Z',
      });
    }
    for (var i = 0; i < 10; i++) {
      batch.insert('group_messages', <String, Object?>{
        'id': 'dx$i',
        'group_id': 'groupY',
        'sender_peer_id': 'peerY',
        'text': 'decoy $i',
        'timestamp': '2026-06-24T09:00:00.000Z',
        'created_at': '2026-06-24T09:00:00.000Z',
      });
    }
    await batch.commit(noResult: true);
  }

  const productionQuery =
      'SELECT * FROM group_messages WHERE group_id = ? AND id NOT LIKE ? '
      'ORDER BY timestamp DESC, id DESC LIMIT ?';

  test('094 creates idx_group_messages_group_ts', () async {
    expect(await indexExists(db, 'idx_group_messages_group_ts'), isFalse);

    await runGroupMessagesGroupTsIndexMigration(db);

    expect(await indexExists(db, 'idx_group_messages_group_ts'), isTrue);
  });

  test('094 is idempotent on re-run', () async {
    await runGroupMessagesGroupTsIndexMigration(db);
    await runGroupMessagesGroupTsIndexMigration(db);

    expect(await indexExists(db, 'idx_group_messages_group_ts'), isTrue);
  });

  test('094 query plan uses the 3-col index with NO temp b-tree', () async {
    await runGroupMessagesGroupTsIndexMigration(db);
    await seedGroupMessages(db);

    final plan = await queryPlan(
      db,
      productionQuery,
      ['groupX', removalCutoffLike, 50],
    );

    expect(plan, contains('IDX_GROUP_MESSAGES_GROUP_TS'));
    expect(plan, isNot(contains('USE TEMP B-TREE')));
  });

  test(
    '094 negative control: a 2-col (group_id, timestamp) index STILL leaves a '
    'temp b-tree for the second ORDER BY term',
    () async {
      // Fresh db with ONLY a 2-col index — proves the third `id` column is what
      // removes the sort, not just "any composite index".
      final db2 =
          await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(() async => db2.close());
      await runGroupMessagesTablesMigration(db2);
      await db2.execute(
        'CREATE INDEX idx_group_messages_group_ts_2col '
        'ON group_messages(group_id, timestamp)',
      );
      await seedGroupMessages(db2);

      final plan = await queryPlan(
        db2,
        productionQuery,
        ['groupX', removalCutoffLike, 50],
      );

      expect(plan, contains('USE TEMP B-TREE'));
    },
  );
}
