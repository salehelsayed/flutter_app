// ignore_for_file: file_names

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

const _createPendingGroupBroadcastsTableSql = '''
CREATE TABLE IF NOT EXISTS pending_group_broadcasts (
  id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  sys_text TEXT NOT NULL,
  recipient_peer_ids TEXT,
  event_at TEXT NOT NULL,
  source_message_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
''';

const _createPendingGroupBroadcastsGroupIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_pending_group_broadcasts_group_created
ON pending_group_broadcasts(group_id, created_at);
''';

const _createPendingGroupBroadcastsDedupIndexSql = '''
CREATE UNIQUE INDEX IF NOT EXISTS idx_pending_group_broadcasts_group_source
ON pending_group_broadcasts(group_id, source_message_id)
WHERE source_message_id IS NOT NULL AND source_message_id <> '';
''';

/// Migration 086: durable queue for group system broadcasts (e.g. a metadata
/// edit) that were persisted locally but failed to leave the device, so they
/// can be re-pushed on the next rejoin/foreground instead of being lost or
/// silently reported as sent.
Future<void> runPendingGroupBroadcastsMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'PENDING_GROUP_BROADCASTS_MIGRATION_START',
    details: {'migration': '086_pending_group_broadcasts'},
  );

  try {
    await db.execute(_createPendingGroupBroadcastsTableSql);
    await db.execute(_createPendingGroupBroadcastsGroupIndexSql);
    await db.execute(_createPendingGroupBroadcastsDedupIndexSql);

    emitFlowEvent(
      layer: 'DB',
      event: 'PENDING_GROUP_BROADCASTS_MIGRATION_SUCCESS',
      details: {'migration': '086_pending_group_broadcasts'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'PENDING_GROUP_BROADCASTS_MIGRATION_ERROR',
      details: {
        'migration': '086_pending_group_broadcasts',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
