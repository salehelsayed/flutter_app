// ignore_for_file: file_names

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

const _createGroupPendingReactionsTableSql = '''
CREATE TABLE IF NOT EXISTS group_pending_reactions (
  id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL,
  message_id TEXT NOT NULL,
  sender_peer_id TEXT NOT NULL,
  transport_peer_id TEXT,
  sender_device_id TEXT,
  sender_public_key TEXT,
  reaction_json TEXT NOT NULL,
  received_at TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
''';

const _createGroupPendingReactionsGroupMessageIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_group_pending_reactions_group_message
ON group_pending_reactions(group_id, message_id);
''';

const _createGroupPendingReactionsGroupReceivedIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_group_pending_reactions_group_received
ON group_pending_reactions(group_id, received_at);
''';

/// Finding 10 (Gap 2): a durable, per-group-capped buffer of fully-validated
/// group reactions whose target message has not yet arrived. The PRIMARY KEY is
/// the deterministic reaction id, so a re-delivered reaction dedups by upsert
/// (INV-R5). The (group_id, message_id) index serves the message-arrival flush;
/// the (group_id, received_at) index serves oldest-first cap eviction.
Future<void> runGroupPendingReactionsMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_PENDING_REACTIONS_MIGRATION_START',
    details: {'migration': '081_group_pending_reactions'},
  );

  try {
    await db.execute(_createGroupPendingReactionsTableSql);
    await db.execute(_createGroupPendingReactionsGroupMessageIndexSql);
    await db.execute(_createGroupPendingReactionsGroupReceivedIndexSql);

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_PENDING_REACTIONS_MIGRATION_SUCCESS',
      details: {'migration': '081_group_pending_reactions'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_PENDING_REACTIONS_MIGRATION_ERROR',
      details: {
        'migration': '081_group_pending_reactions',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
