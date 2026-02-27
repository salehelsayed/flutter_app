import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Migration 016: Creates the `message_reactions` table for storing
/// emoji reactions on conversation messages.
///
/// Idempotent: uses CREATE TABLE IF NOT EXISTS / CREATE INDEX IF NOT EXISTS.
Future<void> runMessageReactionsMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MESSAGE_REACTIONS_MIGRATION_START',
    details: {'migration': '016_message_reactions'},
  );

  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS message_reactions (
        id TEXT PRIMARY KEY,
        message_id TEXT NOT NULL,
        emoji TEXT NOT NULL,
        sender_peer_id TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        created_at TEXT NOT NULL,
        UNIQUE(message_id, sender_peer_id)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_message_reactions_message
      ON message_reactions(message_id)
    ''');

    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGE_REACTIONS_MIGRATION_SUCCESS',
      details: {'migration': '016_message_reactions'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGE_REACTIONS_MIGRATION_ERROR',
      details: {'migration': '016_message_reactions', 'error': e.toString()},
    );
    rethrow;
  }
}
