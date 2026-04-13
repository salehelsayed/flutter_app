import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

Future<void> runGroupReactionReplayOutboxMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_REACTION_REPLAY_OUTBOX_MIGRATION_START',
    details: {'migration': '054_group_reaction_replay_outbox'},
  );

  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS group_reaction_replay_outbox (
        reaction_id TEXT PRIMARY KEY,
        group_id TEXT NOT NULL,
        message_id TEXT NOT NULL,
        sender_peer_id TEXT NOT NULL,
        emoji TEXT NOT NULL,
        action TEXT NOT NULL CHECK(action IN ('add', 'remove')),
        inbox_retry_payload TEXT NOT NULL,
        delivery_status TEXT NOT NULL DEFAULT 'pending'
          CHECK(delivery_status IN ('pending', 'failed', 'stored')),
        last_error TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

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
      event: 'GROUP_REACTION_REPLAY_OUTBOX_MIGRATION_SUCCESS',
      details: {'migration': '054_group_reaction_replay_outbox'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_REACTION_REPLAY_OUTBOX_MIGRATION_ERROR',
      details: {
        'migration': '054_group_reaction_replay_outbox',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
