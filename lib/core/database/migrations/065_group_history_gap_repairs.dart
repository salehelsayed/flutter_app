import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

const _createGroupHistoryGapRepairsTableSql = '''
CREATE TABLE IF NOT EXISTS group_history_gap_repairs (
  group_id TEXT NOT NULL,
  gap_id TEXT NOT NULL,
  missing_after_message_id TEXT NOT NULL,
  missing_before_message_id TEXT NOT NULL,
  expected_range_hash TEXT NOT NULL,
  expected_head_message_id TEXT NOT NULL,
  candidate_source_peer_ids_json TEXT NOT NULL DEFAULT '[]',
  attempted_source_peer_ids_json TEXT NOT NULL DEFAULT '[]',
  repaired_message_ids_json TEXT NOT NULL DEFAULT '[]',
  status TEXT NOT NULL DEFAULT 'detected',
  failure_reason TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  repaired_at TEXT,
  failed_at TEXT,
  PRIMARY KEY(group_id, gap_id)
);
''';

const _createGroupHistoryGapRepairsStatusIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_group_history_gap_repairs_group_status_updated
ON group_history_gap_repairs(group_id, status, updated_at);
''';

const _createGroupHistoryGapRepairsRangeIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_group_history_gap_repairs_group_range
ON group_history_gap_repairs(group_id, missing_after_message_id, missing_before_message_id);
''';

Future<void> runGroupHistoryGapRepairsMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_HISTORY_GAP_REPAIRS_MIGRATION_START',
    details: {'migration': '065_group_history_gap_repairs'},
  );

  try {
    await db.execute(_createGroupHistoryGapRepairsTableSql);
    await db.execute(_createGroupHistoryGapRepairsStatusIndexSql);
    await db.execute(_createGroupHistoryGapRepairsRangeIndexSql);

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_HISTORY_GAP_REPAIRS_MIGRATION_SUCCESS',
      details: {'migration': '065_group_history_gap_repairs'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_HISTORY_GAP_REPAIRS_MIGRATION_ERROR',
      details: {
        'migration': '065_group_history_gap_repairs',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
