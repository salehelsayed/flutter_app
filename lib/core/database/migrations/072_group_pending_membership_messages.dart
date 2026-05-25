// ignore_for_file: file_names

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

const _createGroupPendingMembershipMessagesTableSql = '''
CREATE TABLE IF NOT EXISTS group_pending_membership_messages (
  id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL,
  sender_peer_id TEXT NOT NULL,
  message_id TEXT,
  payload_json TEXT NOT NULL,
  received_at TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
''';

const _createGroupPendingMembershipMessagesSenderIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_group_pending_membership_messages_group_sender_received
ON group_pending_membership_messages(group_id, sender_peer_id, received_at);
''';

const _createGroupPendingMembershipMessagesGroupIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_group_pending_membership_messages_group_received
ON group_pending_membership_messages(group_id, received_at);
''';

const _createGroupPendingMembershipMessagesMessageIndexSql = '''
CREATE UNIQUE INDEX IF NOT EXISTS idx_group_pending_membership_messages_group_message
ON group_pending_membership_messages(group_id, message_id)
WHERE message_id IS NOT NULL AND message_id <> '';
''';

Future<void> runGroupPendingMembershipMessagesMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_PENDING_MEMBERSHIP_MESSAGES_MIGRATION_START',
    details: {'migration': '072_group_pending_membership_messages'},
  );

  try {
    await db.execute(_createGroupPendingMembershipMessagesTableSql);
    await db.execute(_createGroupPendingMembershipMessagesSenderIndexSql);
    await db.execute(_createGroupPendingMembershipMessagesGroupIndexSql);
    await db.execute(_createGroupPendingMembershipMessagesMessageIndexSql);

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_PENDING_MEMBERSHIP_MESSAGES_MIGRATION_SUCCESS',
      details: {'migration': '072_group_pending_membership_messages'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_PENDING_MEMBERSHIP_MESSAGES_MIGRATION_ERROR',
      details: {
        'migration': '072_group_pending_membership_messages',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
