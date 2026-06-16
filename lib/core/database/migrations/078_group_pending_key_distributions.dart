import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

const _createGroupPendingKeyDistributionsTableSql = '''
CREATE TABLE IF NOT EXISTS group_pending_key_distributions (
  id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL,
  peer_id TEXT NOT NULL,
  transport_peer_id TEXT,
  device_id TEXT,
  key_epoch INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  attempts INTEGER NOT NULL DEFAULT 0,
  last_error TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  finalized_at TEXT,
  UNIQUE(group_id, peer_id)
);
''';

const _createGroupPendingKeyDistributionsGroupStatusIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_group_pending_key_distributions_group_status
ON group_pending_key_distributions(group_id, status, created_at);
''';

const _createGroupPendingKeyDistributionsPeerStatusIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_group_pending_key_distributions_peer_status
ON group_pending_key_distributions(peer_id, status);
''';

/// Slice 2 of Finding 03 (removal-rotation fails-closed): a durable sender-side
/// queue of group members that were keyless / undelivered when the group key
/// rotated. The drainer re-distributes the CURRENT group key to each row's
/// target once that target gains a usable ML-KEM key. `key_epoch` is provenance
/// only — the drain always re-reads the latest persisted key (INV-D2).
Future<void> runGroupPendingKeyDistributionsMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_PENDING_KEY_DISTRIBUTIONS_MIGRATION_START',
    details: {'migration': '078_group_pending_key_distributions'},
  );

  try {
    await db.execute(_createGroupPendingKeyDistributionsTableSql);
    await db.execute(_createGroupPendingKeyDistributionsGroupStatusIndexSql);
    await db.execute(_createGroupPendingKeyDistributionsPeerStatusIndexSql);

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_PENDING_KEY_DISTRIBUTIONS_MIGRATION_SUCCESS',
      details: {'migration': '078_group_pending_key_distributions'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_PENDING_KEY_DISTRIBUTIONS_MIGRATION_ERROR',
      details: {
        'migration': '078_group_pending_key_distributions',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
