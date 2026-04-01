import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Migration 045: durable local staging for fetched relay inbox entries.
Future<void> runInboxStagingEntriesMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'INBOX_STAGING_ENTRIES_MIGRATION_START',
    details: {'migration': '045_inbox_staging_entries'},
  );

  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS inbox_staging_entries (
        entry_id TEXT PRIMARY KEY,
        owner_peer_id TEXT NOT NULL,
        sender_peer_id TEXT NOT NULL,
        message_type TEXT,
        relay_timestamp TEXT NOT NULL,
        envelope TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        attempt_count INTEGER NOT NULL DEFAULT 0,
        staged_at TEXT NOT NULL,
        last_attempted_at TEXT,
        reject_reason_code TEXT,
        reject_reason_detail TEXT
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_inbox_staging_entries_recoverable
      ON inbox_staging_entries(status, relay_timestamp, staged_at, entry_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_inbox_staging_entries_owner_status
      ON inbox_staging_entries(owner_peer_id, status, relay_timestamp, staged_at, entry_id)
    ''');

    emitFlowEvent(
      layer: 'DB',
      event: 'INBOX_STAGING_ENTRIES_MIGRATION_SUCCESS',
      details: {'migration': '045_inbox_staging_entries'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'INBOX_STAGING_ENTRIES_MIGRATION_ERROR',
      details: {
        'migration': '045_inbox_staging_entries',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
