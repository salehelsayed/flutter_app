import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Migration 079: adds the F8 tier-2 `dedup_key` column to `messages`.
///
/// `dedup_key` (TEXT, nullable) is a wire-stamped, propagated source-message
/// identifier — a normal send stamps its own id; a forward/share copies the
/// source's key onto a freshly-minted id+timestamp. The receiver dedups on
/// `(contact_peer_id, sender_peer_id, dedup_key)` for incoming rows so a
/// forward (which re-mints BOTH id and timestamp) does not double-card —
/// the forward/share-to-contact prerequisite that timestamp-exact tier-1
/// (`existsByContent`) structurally cannot catch.
///
/// Nullable: legacy / pre-rollout rows carry NULL and fall back to the
/// timestamp-exact tier-1 path. The index is deliberately NON-UNIQUE — a
/// UNIQUE constraint would reject legitimate repeated forwards and be
/// ambiguous across the many NULL keys; dedup is query-time, pre-persist only.
///
/// NOTE (sequencing): migration 078 (`078_group_pending_key_distributions`) is
/// owned by the concurrent undecryptable-self-heal effort. Both use additive
/// `if (oldVersion < N)` guards, so land order does not matter; the version
/// constant resolves to the max (79) on merge.
Future<void> runMessageDedupKeyMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MESSAGES_DEDUP_KEY_MIGRATION_START',
    details: {'migration': '079_message_dedup_key'},
  );

  try {
    final columns = await db.rawQuery('PRAGMA table_info(messages)');
    final columnNames = columns.map((column) => column['name']).toSet();

    if (!columnNames.contains('dedup_key')) {
      await db.execute('ALTER TABLE messages ADD COLUMN dedup_key TEXT');
    }

    await db.execute('''
CREATE INDEX IF NOT EXISTS idx_messages_dedup_key
  ON messages(contact_peer_id, sender_peer_id, dedup_key)''');

    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DEDUP_KEY_MIGRATION_SUCCESS',
      details: {'migration': '079_message_dedup_key'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DEDUP_KEY_MIGRATION_ERROR',
      details: {'migration': '079_message_dedup_key', 'error': e.toString()},
    );
    rethrow;
  }
}
