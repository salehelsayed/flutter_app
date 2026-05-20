// ignore_for_file: file_names

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

const _createGroupMessageLocalDeletionsSql = '''
CREATE TABLE IF NOT EXISTS group_message_local_deletions (
  message_id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL,
  deleted_at TEXT NOT NULL,
  created_at TEXT NOT NULL
);
''';

const _createGroupMessageLocalDeletionsGroupIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_group_message_local_deletions_group
ON group_message_local_deletions(group_id, deleted_at);
''';

Future<void> runGroupMessageLocalDeletionsMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_MESSAGE_LOCAL_DELETIONS_MIGRATION_START',
    details: {'migration': '069_group_message_local_deletions'},
  );

  try {
    await db.execute(_createGroupMessageLocalDeletionsSql);
    await db.execute(_createGroupMessageLocalDeletionsGroupIndexSql);

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MESSAGE_LOCAL_DELETIONS_MIGRATION_SUCCESS',
      details: {'migration': '069_group_message_local_deletions'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MESSAGE_LOCAL_DELETIONS_MIGRATION_ERROR',
      details: {
        'migration': '069_group_message_local_deletions',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
