import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

const String _createPendingGroupInvitesTableSql = '''
CREATE TABLE IF NOT EXISTS pending_group_invites (
  group_id TEXT PRIMARY KEY,
  invite_id TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  group_name TEXT NOT NULL,
  group_type TEXT NOT NULL CHECK(group_type IN ('chat','announcement','qa')),
  group_description TEXT,
  avatar_blob_id TEXT,
  avatar_mime TEXT,
  sender_peer_id TEXT NOT NULL,
  sender_username TEXT NOT NULL,
  created_by TEXT NOT NULL,
  created_at TEXT NOT NULL,
  metadata_updated_at TEXT,
  received_at TEXT NOT NULL,
  expires_at TEXT NOT NULL
);
''';

const String _createPendingGroupInvitesExpiresAtIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_pending_group_invites_expires_at
ON pending_group_invites(expires_at);
''';

Future<void> runPendingGroupInvitesMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'PENDING_GROUP_INVITES_MIGRATION_START',
    details: {'migration': '051_pending_group_invites'},
  );

  try {
    await db.execute(_createPendingGroupInvitesTableSql);
    await db.execute(_createPendingGroupInvitesExpiresAtIndexSql);

    emitFlowEvent(
      layer: 'DB',
      event: 'PENDING_GROUP_INVITES_MIGRATION_SUCCESS',
      details: {'migration': '051_pending_group_invites'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'PENDING_GROUP_INVITES_MIGRATION_ERROR',
      details: {
        'migration': '051_pending_group_invites',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
