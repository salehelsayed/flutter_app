// ignore_for_file: file_names
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Plan 319: widen the reaction replay outbox for the needs-build rescue.
///
/// A stage-build throw used to abandon custody permanently (no row existed to
/// retry). The rescue stages a `needs_build` row BEFORE the throwing build
/// steps, using a SENTINEL-EMPTY payload — the column stays NOT NULL because
/// rolled-back builds read this table through non-status-filtered queries and
/// cast the payload `as String` (a NULL would crash them; '' parses and at
/// worst degrades the row to a non-crashing failed retry the new build's
/// rebuild predicate also catches). SQLite cannot alter a CHECK in place, so
/// this is a table-rebuild copy-swap; rowid is copied explicitly because two
/// production readers tiebreak on `rowid DESC`.
Future<void> runReactionOutboxNeedsBuildMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'REACTION_OUTBOX_NEEDS_BUILD_MIGRATION_START',
    details: {'migration': '105_reaction_outbox_needs_build'},
  );

  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS group_reaction_replay_outbox_v105 (
        reaction_id TEXT PRIMARY KEY,
        group_id TEXT NOT NULL,
        message_id TEXT NOT NULL,
        sender_peer_id TEXT NOT NULL,
        emoji TEXT NOT NULL,
        action TEXT NOT NULL CHECK(action IN ('add', 'remove')),
        inbox_retry_payload TEXT NOT NULL
          CHECK(inbox_retry_payload != '' OR delivery_status = 'needs_build'),
        delivery_status TEXT NOT NULL DEFAULT 'pending'
          CHECK(delivery_status IN ('pending', 'failed', 'stored', 'needs_build')),
        last_error TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      INSERT INTO group_reaction_replay_outbox_v105
        (rowid, reaction_id, group_id, message_id, sender_peer_id, emoji,
         action, inbox_retry_payload, delivery_status, last_error,
         created_at, updated_at)
      SELECT rowid, reaction_id, group_id, message_id, sender_peer_id, emoji,
             action, inbox_retry_payload, delivery_status, last_error,
             created_at, updated_at
      FROM group_reaction_replay_outbox
    ''');

    await db.execute('DROP TABLE group_reaction_replay_outbox');
    await db.execute(
      'ALTER TABLE group_reaction_replay_outbox_v105 '
      'RENAME TO group_reaction_replay_outbox',
    );

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_group_reaction_replay_outbox_retryable
      ON group_reaction_replay_outbox(delivery_status, created_at, reaction_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_group_reaction_replay_outbox_group_message
      ON group_reaction_replay_outbox(group_id, message_id, created_at)
    ''');

    emitFlowEvent(
      layer: 'DB',
      event: 'REACTION_OUTBOX_NEEDS_BUILD_MIGRATION_SUCCESS',
      details: {'migration': '105_reaction_outbox_needs_build'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'REACTION_OUTBOX_NEEDS_BUILD_MIGRATION_ERROR',
      details: {
        'migration': '105_reaction_outbox_needs_build',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
