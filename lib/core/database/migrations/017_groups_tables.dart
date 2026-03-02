import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// SQL statement to create the groups table.
const String _createGroupsTableSql = '''
CREATE TABLE IF NOT EXISTS groups (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  type TEXT NOT NULL CHECK(type IN ('chat','announcement','qa')),
  topic_name TEXT NOT NULL UNIQUE,
  description TEXT,
  created_at TEXT NOT NULL,
  created_by TEXT NOT NULL,
  my_role TEXT NOT NULL CHECK(my_role IN ('admin','member')),
  is_archived INTEGER NOT NULL DEFAULT 0,
  archived_at TEXT
);
''';

/// SQL statement to create the group_members table.
const String _createGroupMembersTableSql = '''
CREATE TABLE IF NOT EXISTS group_members (
  group_id TEXT NOT NULL,
  peer_id TEXT NOT NULL,
  username TEXT,
  role TEXT NOT NULL CHECK(role IN ('admin','writer','reader')),
  public_key TEXT,
  ml_kem_public_key TEXT,
  joined_at TEXT NOT NULL,
  PRIMARY KEY (group_id, peer_id)
);
''';

/// SQL statement to create index on group_members for fast lookups by group.
const String _createGroupMembersIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_group_members_group ON group_members(group_id);
''';

/// Runs the groups tables migration.
///
/// Creates the groups and group_members tables. Idempotent via IF NOT EXISTS.
///
/// Emits flow events:
/// - `GROUPS_DB_MIGRATION_START`
/// - `GROUPS_DB_MIGRATION_SUCCESS`
/// - `GROUPS_DB_MIGRATION_ERROR`
Future<void> runGroupsTablesMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUPS_DB_MIGRATION_START',
    details: {'migration': '017_groups_tables'},
  );

  try {
    await db.execute(_createGroupsTableSql);
    await db.execute(_createGroupMembersTableSql);
    await db.execute(_createGroupMembersIndexSql);

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_DB_MIGRATION_SUCCESS',
      details: {'migration': '017_groups_tables'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_DB_MIGRATION_ERROR',
      details: {'migration': '017_groups_tables', 'error': e.toString()},
    );
    rethrow;
  }
}
