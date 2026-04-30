import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

Future<void> runGroupEventLogMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_EVENT_LOG_MIGRATION_START',
    details: {'migration': '060_group_event_log'},
  );

  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS group_event_log (
        id TEXT PRIMARY KEY,
        group_id TEXT NOT NULL,
        sequence INTEGER NOT NULL CHECK(sequence > 0),
        event_type TEXT NOT NULL,
        source_peer_id TEXT NOT NULL,
        source_event_id TEXT NOT NULL,
        source_timestamp TEXT NOT NULL,
        canonical_payload TEXT NOT NULL,
        previous_entry_hash TEXT,
        entry_hash TEXT NOT NULL,
        created_at TEXT NOT NULL,
        UNIQUE(group_id, sequence),
        UNIQUE(group_id, source_event_id)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_group_event_log_group_sequence
      ON group_event_log(group_id, sequence)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_group_event_log_event_type
      ON group_event_log(group_id, event_type, source_timestamp)
    ''');

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_EVENT_LOG_MIGRATION_SUCCESS',
      details: {'migration': '060_group_event_log'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_EVENT_LOG_MIGRATION_ERROR',
      details: {'migration': '060_group_event_log', 'error': e.toString()},
    );
    rethrow;
  }
}
