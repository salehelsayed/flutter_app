import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

const _createGroupInboxCursorsSql = '''
CREATE TABLE IF NOT EXISTS group_inbox_cursors (
  group_id TEXT PRIMARY KEY,
  cursor TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
''';

const _createGroupMessageReceiptsSql = '''
CREATE TABLE IF NOT EXISTS group_message_receipts (
  group_id TEXT NOT NULL,
  message_id TEXT NOT NULL,
  receipt_type TEXT NOT NULL,
  member_peer_id TEXT NOT NULL,
  sender_device_id TEXT,
  receipt_at TEXT NOT NULL,
  source_event_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY(group_id, message_id, receipt_type, member_peer_id)
);
''';

const _createGroupMessageReceiptsMessageIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_group_message_receipts_message
ON group_message_receipts(group_id, message_id, receipt_type);
''';

const _createGroupMessageReceiptsMemberIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_group_message_receipts_member
ON group_message_receipts(group_id, member_peer_id, updated_at);
''';

Future<void> runGroupSyncReceiptsMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_SYNC_RECEIPTS_MIGRATION_START',
    details: {'migration': '066_group_sync_receipts'},
  );

  try {
    await db.execute(_createGroupInboxCursorsSql);
    await db.execute(_createGroupMessageReceiptsSql);
    await db.execute(_createGroupMessageReceiptsMessageIndexSql);
    await db.execute(_createGroupMessageReceiptsMemberIndexSql);

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_SYNC_RECEIPTS_MIGRATION_SUCCESS',
      details: {'migration': '066_group_sync_receipts'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_SYNC_RECEIPTS_MIGRATION_ERROR',
      details: {'migration': '066_group_sync_receipts', 'error': e.toString()},
    );
    rethrow;
  }
}
