import 'package:sqflite/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// SQL statement to create the messages table.
const String _createMessagesTableSql = '''
CREATE TABLE IF NOT EXISTS messages (
  id TEXT PRIMARY KEY,
  contact_peer_id TEXT NOT NULL,
  sender_peer_id TEXT NOT NULL,
  text TEXT NOT NULL,
  timestamp TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'sent',
  is_incoming INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
);
''';

/// SQL statement to create index on contact_peer_id for fast lookups.
const String _createContactIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_messages_contact ON messages(contact_peer_id);
''';

/// SQL statement to create index on timestamp for ordering.
const String _createTimestampIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_messages_ts ON messages(timestamp);
''';

/// Runs the messages table migration.
///
/// Creates the messages table and its indexes. Idempotent via IF NOT EXISTS.
///
/// Emits flow events:
/// - `MESSAGES_DB_MIGRATION_START`
/// - `MESSAGES_DB_MIGRATION_SUCCESS`
/// - `MESSAGES_DB_MIGRATION_ERROR`
Future<void> runMessagesTableMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MESSAGES_DB_MIGRATION_START',
    details: {'table': 'messages'},
  );

  try {
    await db.execute(_createMessagesTableSql);
    await db.execute(_createContactIndexSql);
    await db.execute(_createTimestampIndexSql);

    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_MIGRATION_SUCCESS',
      details: {'table': 'messages'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_MIGRATION_ERROR',
      details: {'table': 'messages', 'error': e.toString()},
    );
    rethrow;
  }
}

/// Migration class for creating the messages table.
class MessagesTableMigration {
  static const String migrationName = '002_messages_table';
  static const String tableName = 'messages';

  static Future<void> run(Database db) async {
    await runMessagesTableMigration(db);
  }
}
