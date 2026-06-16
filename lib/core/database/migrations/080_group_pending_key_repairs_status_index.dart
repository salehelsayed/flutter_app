import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

// The existing idx_group_pending_key_repairs_group_epoch_status index leads with
// group_id, so it cannot serve the status-only predicate used by the
// all-pending resume sweep (`WHERE status = 'pending_key' ORDER BY created_at`).
// This adds a status-leading index for that scan. Index-only, fail-open,
// IF NOT EXISTS — no data backfill.
const _createGroupPendingKeyRepairsStatusIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_group_pending_key_repairs_status_created
ON group_pending_key_repairs(status, created_at);
''';

Future<void> runGroupPendingKeyRepairsStatusIndexMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_PENDING_KEY_REPAIRS_STATUS_INDEX_MIGRATION_START',
    details: {'migration': '080_group_pending_key_repairs_status_index'},
  );

  try {
    await db.execute(_createGroupPendingKeyRepairsStatusIndexSql);

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_PENDING_KEY_REPAIRS_STATUS_INDEX_MIGRATION_SUCCESS',
      details: {'migration': '080_group_pending_key_repairs_status_index'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_PENDING_KEY_REPAIRS_STATUS_INDEX_MIGRATION_ERROR',
      details: {
        'migration': '080_group_pending_key_repairs_status_index',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
