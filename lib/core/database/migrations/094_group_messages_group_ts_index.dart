// ignore_for_file: file_names

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

// QW-6 (db-persistence-5): the hot group page query is
//   SELECT * FROM group_messages WHERE group_id = ? AND id NOT LIKE ?
//   ORDER BY timestamp DESC, id DESC LIMIT ?
// The 018 indices are single-column (idx_group_messages_group on group_id,
// idx_group_messages_ts on timestamp), so the planner sorts via a temp b-tree.
//
// CRITICAL (Finding-1 HIGH): the ORDER BY has TWO terms (timestamp DESC, id DESC).
// A 2-col (group_id, timestamp) index satisfies only the leading term and leaves
// `USE TEMP B-TREE FOR LAST TERM OF ORDER BY`. The index MUST be the 3-col
// (group_id, timestamp, id) — all-ASC, which SQLite scans in reverse to satisfy
// `timestamp DESC, id DESC` with no temp b-tree (the sort direction is
// consistent across both terms, and `id` is TEXT/BINARY matching the index
// collation). The `id NOT LIKE ?` predicate is a residual filter that does not
// affect ordering. Index-only, fail-open, IF NOT EXISTS — no data backfill.
const _createGroupMessagesGroupTsIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_group_messages_group_ts
ON group_messages(group_id, timestamp, id);
''';

Future<void> runGroupMessagesGroupTsIndexMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_MESSAGES_GROUP_TS_INDEX_MIGRATION_START',
    details: {'migration': '094_group_messages_group_ts_index'},
  );

  try {
    await db.execute(_createGroupMessagesGroupTsIndexSql);

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MESSAGES_GROUP_TS_INDEX_MIGRATION_SUCCESS',
      details: {'migration': '094_group_messages_group_ts_index'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MESSAGES_GROUP_TS_INDEX_MIGRATION_ERROR',
      details: {
        'migration': '094_group_messages_group_ts_index',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
