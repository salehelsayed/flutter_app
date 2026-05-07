import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

const _createGroupInviteDeliveryAttemptsSql = '''
CREATE TABLE IF NOT EXISTS group_invite_delivery_attempts (
  group_id TEXT NOT NULL,
  peer_id TEXT NOT NULL,
  username TEXT,
  status TEXT NOT NULL CHECK(status IN (
    'sent',
    'queued',
    'needs_resend',
    'cannot_send',
    'joined'
  )),
  attempted_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  last_error TEXT,
  PRIMARY KEY(group_id, peer_id)
);
''';

const _createGroupInviteDeliveryAttemptsGroupStatusIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_group_invite_delivery_attempts_group_status
ON group_invite_delivery_attempts(group_id, status);
''';

const _createGroupInviteDeliveryAttemptsPeerIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_group_invite_delivery_attempts_peer
ON group_invite_delivery_attempts(peer_id);
''';

Future<void> runGroupInviteDeliveryAttemptsMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_INVITE_DELIVERY_ATTEMPTS_MIGRATION_START',
    details: {'migration': '067_group_invite_delivery_attempts'},
  );

  try {
    await db.execute(_createGroupInviteDeliveryAttemptsSql);
    await db.execute(_createGroupInviteDeliveryAttemptsGroupStatusIndexSql);
    await db.execute(_createGroupInviteDeliveryAttemptsPeerIndexSql);

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_INVITE_DELIVERY_ATTEMPTS_MIGRATION_SUCCESS',
      details: {'migration': '067_group_invite_delivery_attempts'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_INVITE_DELIVERY_ATTEMPTS_MIGRATION_ERROR',
      details: {
        'migration': '067_group_invite_delivery_attempts',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
