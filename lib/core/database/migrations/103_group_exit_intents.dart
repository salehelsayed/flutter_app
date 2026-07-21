// ignore_for_file: file_names

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

const _migrationName = '103_group_exit_intents';

const _createGroupExitIntentsTableSql = '''
CREATE TABLE IF NOT EXISTS group_exit_intents (
  group_id TEXT PRIMARY KEY,
  intent_id TEXT NOT NULL UNIQUE,
  self_peer_id TEXT NOT NULL,
  self_joined_at TEXT NOT NULL,
  state TEXT NOT NULL CHECK(state IN (
    'queued',
    'leave_notice_pending',
    'leave_notice_attempted',
    'rotation_claimed',
    'native_leave_pending',
    'cleanup_pending'
  )),
  pending_broadcast_id TEXT NOT NULL UNIQUE,
  source_event_id TEXT UNIQUE,
  event_at TEXT,
  revision INTEGER NOT NULL DEFAULT 0 CHECK(revision >= 0),
  last_error_code TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  CHECK(TRIM(group_id) <> ''),
  CHECK(TRIM(intent_id) <> ''),
  CHECK(TRIM(self_peer_id) <> ''),
  CHECK(TRIM(self_joined_at) <> ''),
  CHECK(TRIM(pending_broadcast_id) <> ''),
  CHECK(
    last_error_code IS NULL
    OR (
      length(last_error_code) BETWEEN 1 AND 64
      AND last_error_code = TRIM(last_error_code)
      AND last_error_code NOT GLOB '*[^-a-z0-9_:]*'
    )
  ),
  CHECK(
    (state = 'queued' AND source_event_id IS NULL AND event_at IS NULL)
    OR
    (state <> 'queued' AND source_event_id IS NOT NULL
      AND TRIM(source_event_id) <> '' AND event_at IS NOT NULL)
  )
);
''';

const _createGroupExitIntentsStateUpdatedIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_group_exit_intents_state_updated
ON group_exit_intents(state, updated_at);
''';

/// Adds the restart-safe voluntary group-exit state machine.
///
/// The table intentionally has no foreign key or cascade: after a confirmed
/// native leave, its cleanup authority must survive deletion of `groups`.
/// Legacy rows are never inferred or backfilled from pending role work.
Future<void> runGroupExitIntentsMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_EXIT_INTENTS_MIGRATION_START',
    details: const {'migration': _migrationName},
  );

  try {
    await db.execute(_createGroupExitIntentsTableSql);
    await db.execute(_createGroupExitIntentsStateUpdatedIndexSql);
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_EXIT_INTENTS_MIGRATION_SUCCESS',
      details: const {'migration': _migrationName},
    );
  } catch (error) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_EXIT_INTENTS_MIGRATION_ERROR',
      details: {'migration': _migrationName, 'error': error.toString()},
    );
    rethrow;
  }
}
