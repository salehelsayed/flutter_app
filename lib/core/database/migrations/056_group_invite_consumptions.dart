import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

const String _createGroupInviteConsumptionsTableSql = '''
CREATE TABLE IF NOT EXISTS group_invite_consumptions (
  invite_id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL,
  consumed_at TEXT NOT NULL,
  expires_at TEXT NOT NULL
);
''';

const String _createGroupInviteConsumptionsGroupIdIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_group_invite_consumptions_group_id
ON group_invite_consumptions(group_id);
''';

const String _createGroupInviteConsumptionsExpiresAtIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_group_invite_consumptions_expires_at
ON group_invite_consumptions(expires_at);
''';

Future<void> runGroupInviteConsumptionsMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_INVITE_CONSUMPTIONS_MIGRATION_START',
    details: {'migration': '056_group_invite_consumptions'},
  );

  try {
    await db.execute(_createGroupInviteConsumptionsTableSql);
    await db.execute(_createGroupInviteConsumptionsGroupIdIndexSql);
    await db.execute(_createGroupInviteConsumptionsExpiresAtIndexSql);

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_INVITE_CONSUMPTIONS_MIGRATION_SUCCESS',
      details: {'migration': '056_group_invite_consumptions'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_INVITE_CONSUMPTIONS_MIGRATION_ERROR',
      details: {
        'migration': '056_group_invite_consumptions',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
