import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// SQL statement to create the group_keys table.
const String _createGroupKeysTableSql = '''
CREATE TABLE IF NOT EXISTS group_keys (
  group_id TEXT NOT NULL,
  key_generation INTEGER NOT NULL,
  encrypted_key TEXT NOT NULL,
  created_at TEXT NOT NULL,
  PRIMARY KEY (group_id, key_generation)
);
''';

/// SQL statement to create the group_messages table.
const String _createGroupMessagesTableSql = '''
CREATE TABLE IF NOT EXISTS group_messages (
  id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL,
  sender_peer_id TEXT NOT NULL,
  sender_username TEXT,
  text TEXT NOT NULL,
  timestamp TEXT NOT NULL,
  key_generation INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'sent',
  is_incoming INTEGER NOT NULL DEFAULT 1,
  read_at TEXT,
  created_at TEXT NOT NULL
);
''';

/// SQL statement to create index on group_messages for fast lookups by group.
const String _createGroupMessagesGroupIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_group_messages_group ON group_messages(group_id);
''';

/// SQL statement to create index on group_messages for ordering by timestamp.
const String _createGroupMessagesTimestampIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_group_messages_ts ON group_messages(timestamp);
''';

/// Runs the group messages tables migration.
///
/// Creates the group_keys and group_messages tables. Idempotent via IF NOT EXISTS.
///
/// Emits flow events:
/// - `GROUP_MESSAGES_DB_MIGRATION_START`
/// - `GROUP_MESSAGES_DB_MIGRATION_SUCCESS`
/// - `GROUP_MESSAGES_DB_MIGRATION_ERROR`
Future<void> runGroupMessagesTablesMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_MESSAGES_DB_MIGRATION_START',
    details: {'migration': '018_group_messages_tables'},
  );

  try {
    await db.execute(_createGroupKeysTableSql);
    await db.execute(_createGroupMessagesTableSql);
    await db.execute(_createGroupMessagesGroupIndexSql);
    await db.execute(_createGroupMessagesTimestampIndexSql);

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MESSAGES_DB_MIGRATION_SUCCESS',
      details: {'migration': '018_group_messages_tables'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MESSAGES_DB_MIGRATION_ERROR',
      details: {'migration': '018_group_messages_tables', 'error': e.toString()},
    );
    rethrow;
  }
}
