// ignore_for_file: file_names

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

const _migrationName = '109_direct_reaction_inbox_custody_outbox';

/// Adds immutable sender-owned relay-inbox custody for direct reactions.
///
/// The table deliberately has no foreign key. A locally deleted target or
/// canonical reaction must not cancel an already-authored encrypted event.
/// Historical reactions are not backfilled because their exact ciphertext
/// cannot be reconstructed.
Future<void> runDirectReactionInboxCustodyOutboxMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'DIRECT_REACTION_INBOX_CUSTODY_OUTBOX_MIGRATION_START',
    details: const {'migration': _migrationName},
  );

  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS direct_reaction_inbox_custody_outbox (
        recipient_peer_id TEXT NOT NULL
          CHECK(length(trim(recipient_peer_id)) > 0),
        event_id TEXT NOT NULL CHECK(length(trim(event_id)) > 0),
        wire_envelope TEXT NOT NULL CHECK(length(trim(wire_envelope)) > 0),
        retry_count INTEGER NOT NULL DEFAULT 0 CHECK(retry_count >= 0),
        last_attempt_at TEXT
          CHECK(last_attempt_at IS NULL OR length(trim(last_attempt_at)) > 0),
        last_error_code TEXT CHECK(
          last_error_code IS NULL OR last_error_code IN (
            'store_failed',
            'store_rejected_full',
            'store_threw',
            'local_completion_failed'
          )
        ),
        created_at TEXT NOT NULL CHECK(length(trim(created_at)) > 0),
        updated_at TEXT NOT NULL CHECK(length(trim(updated_at)) > 0),
        PRIMARY KEY(recipient_peer_id, event_id)
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS
        idx_direct_reaction_inbox_custody_outbox_fair_load
      ON direct_reaction_inbox_custody_outbox(
        last_attempt_at,
        created_at,
        recipient_peer_id,
        event_id
      )
    ''');

    emitFlowEvent(
      layer: 'DB',
      event: 'DIRECT_REACTION_INBOX_CUSTODY_OUTBOX_MIGRATION_SUCCESS',
      details: const {'migration': _migrationName},
    );
  } catch (error) {
    emitFlowEvent(
      layer: 'DB',
      event: 'DIRECT_REACTION_INBOX_CUSTODY_OUTBOX_MIGRATION_ERROR',
      details: {'migration': _migrationName, 'error': error.toString()},
    );
    rethrow;
  }
}
