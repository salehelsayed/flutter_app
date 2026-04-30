import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

const String _createGroupInviteRevocationsTableSql = '''
CREATE TABLE IF NOT EXISTS group_invite_revocations (
  invite_id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL,
  revoked_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  revoked_by TEXT
);
''';

const String _createGroupInviteRevocationsGroupIdIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_group_invite_revocations_group_id
ON group_invite_revocations(group_id);
''';

const String _createGroupInviteRevocationsExpiresAtIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_group_invite_revocations_expires_at
ON group_invite_revocations(expires_at);
''';

Future<void> runGroupInviteRevocationsMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_INVITE_REVOCATIONS_MIGRATION_START',
    details: {'migration': '055_group_invite_revocations'},
  );

  try {
    await db.execute(_createGroupInviteRevocationsTableSql);
    await db.execute(_createGroupInviteRevocationsGroupIdIndexSql);
    await db.execute(_createGroupInviteRevocationsExpiresAtIndexSql);

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_INVITE_REVOCATIONS_MIGRATION_SUCCESS',
      details: {'migration': '055_group_invite_revocations'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_INVITE_REVOCATIONS_MIGRATION_ERROR',
      details: {
        'migration': '055_group_invite_revocations',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
