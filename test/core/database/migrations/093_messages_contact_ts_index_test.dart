// ignore_for_file: file_names

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/migrations/002_messages_table.dart';
import 'package:flutter_app/core/database/migrations/044_messages_deleted_state.dart';
import 'package:flutter_app/core/database/migrations/093_messages_contact_ts_index.dart';

void main() {
  // QW-5 (db-persistence-2): composite (contact_peer_id, timestamp) index for
  // the hot 1:1 page query. Plain sqflite FFI in-memory — the migration SQL is
  // cipher-agnostic (mirrors the 080/092 harness).
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    // 093 indexes the `messages` table (002) and the production query it
    // accelerates references `hidden_at IS NULL` (added by 044), so both
    // prerequisites must run for the EXPLAIN QUERY PLAN assertion to parse.
    await runMessagesTableMigration(db);
    await runMessagesDeletedStateMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<bool> indexExists(String name) async {
    final rows = await db.query(
      'sqlite_master',
      where: "type = 'index' AND name = ?",
      whereArgs: [name],
    );
    return rows.isNotEmpty;
  }

  Future<String> queryPlan(String sql, List<Object?> args) async {
    final rows = await db.rawQuery('EXPLAIN QUERY PLAN $sql', args);
    return rows.map((r) => r['detail']).join('\n').toUpperCase();
  }

  Future<void> seedMessages() async {
    final batch = db.batch();
    // 60 rows for the target contact ...
    for (var i = 0; i < 60; i++) {
      final mm = (i % 60).toString().padLeft(2, '0');
      batch.insert('messages', <String, Object?>{
        'id': 'm$i',
        'contact_peer_id': 'peerX',
        'sender_peer_id': 'peerX',
        'text': 'hello $i',
        'timestamp': '2026-06-24T10:$mm:00.000Z',
        'created_at': '2026-06-24T10:00:00.000Z',
      });
    }
    // ... plus a few decoys for other contacts (planner must still prefer the
    // composite index keyed on the equality predicate).
    for (var i = 0; i < 10; i++) {
      batch.insert('messages', <String, Object?>{
        'id': 'd$i',
        'contact_peer_id': 'peerY',
        'sender_peer_id': 'peerY',
        'text': 'decoy $i',
        'timestamp': '2026-06-24T09:00:00.000Z',
        'created_at': '2026-06-24T09:00:00.000Z',
      });
    }
    await batch.commit(noResult: true);
  }

  test('093 creates idx_messages_contact_ts', () async {
    expect(await indexExists('idx_messages_contact_ts'), isFalse);

    await runMessagesContactTsIndexMigration(db);

    expect(await indexExists('idx_messages_contact_ts'), isTrue);
  });

  test('093 is idempotent on re-run', () async {
    await runMessagesContactTsIndexMigration(db);
    await runMessagesContactTsIndexMigration(db);

    expect(await indexExists('idx_messages_contact_ts'), isTrue);
  });

  test('093 query plan uses the index with NO temp b-tree', () async {
    await runMessagesContactTsIndexMigration(db);
    await seedMessages();

    final plan = await queryPlan(
      'SELECT * FROM messages WHERE contact_peer_id = ? AND hidden_at IS NULL '
      'ORDER BY timestamp DESC LIMIT ?',
      ['peerX', 50],
    );

    // Single-term ORDER BY → the 2-col (contact_peer_id, timestamp) index fully
    // satisfies filter + order (reverse scan for DESC); no sort step.
    expect(plan, contains('IDX_MESSAGES_CONTACT_TS'));
    expect(plan, isNot(contains('USE TEMP B-TREE')));
  });
}
