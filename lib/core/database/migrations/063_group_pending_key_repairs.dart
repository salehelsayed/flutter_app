import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

const _createGroupPendingKeyRepairsTableSql = '''
CREATE TABLE IF NOT EXISTS group_pending_key_repairs (
  id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL,
  message_id TEXT NOT NULL,
  sender_peer_id TEXT,
  transport_peer_id TEXT,
  payload_type TEXT NOT NULL,
  key_epoch INTEGER NOT NULL,
  replay_envelope_json TEXT,
  status TEXT NOT NULL DEFAULT 'pending_key',
  trigger_count INTEGER NOT NULL DEFAULT 0,
  attempts INTEGER NOT NULL DEFAULT 0,
  last_error TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  finalized_at TEXT,
  UNIQUE(group_id, message_id)
);
''';

const _createGroupPendingKeyRepairsEpochIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_group_pending_key_repairs_group_epoch_status
ON group_pending_key_repairs(group_id, key_epoch, status, created_at);
''';

const _createGroupPendingKeyRepairsMessageIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_group_pending_key_repairs_group_message
ON group_pending_key_repairs(group_id, message_id);
''';

Future<void> runGroupPendingKeyRepairsMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_PENDING_KEY_REPAIRS_MIGRATION_START',
    details: {'migration': '063_group_pending_key_repairs'},
  );

  try {
    await db.execute(_createGroupPendingKeyRepairsTableSql);
    await db.execute(_createGroupPendingKeyRepairsEpochIndexSql);
    await db.execute(_createGroupPendingKeyRepairsMessageIndexSql);

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_PENDING_KEY_REPAIRS_MIGRATION_SUCCESS',
      details: {'migration': '063_group_pending_key_repairs'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_PENDING_KEY_REPAIRS_MIGRATION_ERROR',
      details: {
        'migration': '063_group_pending_key_repairs',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
