// ignore_for_file: file_names

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Migration 088 (finding 05 Phase 3): bounded per-group rejoin retry state.
///
/// `group_rejoin_state` is a sparse table holding one row per group that has
/// *failed* to rejoin its pubsub topic, so the retrier can:
///   * back off a persistently-failing rejoin (exponential `next_eligible_at`)
///     instead of hammering it every pass, and
///   * detect a group that exceeds its attempt budget
///     (`GROUP_REJOIN_PERMANENTLY_STUCK`).
///
/// A row is created/updated on a failed rejoin and deleted on a successful one,
/// so a healthy group has no row.
Future<void> runGroupRejoinStateMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_REJOIN_STATE_MIGRATION_START',
    details: {'migration': '088_group_rejoin_state'},
  );

  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS group_rejoin_state (
        group_id TEXT PRIMARY KEY,
        rejoin_attempt_count INTEGER NOT NULL DEFAULT 0,
        next_eligible_at INTEGER
      )
    ''');

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_REJOIN_STATE_MIGRATION_SUCCESS',
      details: {'migration': '088_group_rejoin_state'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_REJOIN_STATE_MIGRATION_ERROR',
      details: {'migration': '088_group_rejoin_state', 'error': e.toString()},
    );
    rethrow;
  }
}
