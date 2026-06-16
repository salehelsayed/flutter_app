// ignore_for_file: file_names

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Finding 10 (Gap 3c): adds a nullable `removed_at` tombstone column to the
/// shared `message_reactions` table (1:1 + group). A remove sets `removed_at`
/// to the remove's sender-authored timestamp instead of hard-deleting the row,
/// so a later *older* add can be recognised as stale and dropped (full
/// remove-then-stale-add convergence / INV-T2). Additive and idempotent —
/// `ALTER TABLE ADD COLUMN` has no `IF NOT EXISTS`, so re-runs are guarded by a
/// PRAGMA check.
Future<void> runMessageReactionTombstoneMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MESSAGE_REACTION_TOMBSTONE_MIGRATION_START',
    details: {'migration': '082_message_reaction_tombstone'},
  );

  try {
    final columns = await db.rawQuery('PRAGMA table_info(message_reactions)');
    final hasRemovedAt = columns.any((c) => c['name'] == 'removed_at');
    if (!hasRemovedAt) {
      await db.execute(
        'ALTER TABLE message_reactions ADD COLUMN removed_at TEXT',
      );
    }

    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGE_REACTION_TOMBSTONE_MIGRATION_SUCCESS',
      details: {'migration': '082_message_reaction_tombstone'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGE_REACTION_TOMBSTONE_MIGRATION_ERROR',
      details: {
        'migration': '082_message_reaction_tombstone',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
