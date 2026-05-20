// ignore_for_file: file_names

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

const _createGroupKeyRotationDraftsSql = '''
CREATE TABLE IF NOT EXISTS group_key_rotation_drafts (
  group_id TEXT PRIMARY KEY,
  key_generation INTEGER NOT NULL,
  encrypted_key TEXT NOT NULL,
  created_at TEXT NOT NULL
);
''';

const _createGroupKeyRotationDraftsEpochIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_group_key_rotation_drafts_group_epoch
ON group_key_rotation_drafts(group_id, key_generation);
''';

Future<void> runGroupKeyRotationDraftsMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_KEY_ROTATION_DRAFTS_MIGRATION_START',
    details: {'migration': '070_group_key_rotation_drafts'},
  );

  try {
    await db.execute(_createGroupKeyRotationDraftsSql);
    await db.execute(_createGroupKeyRotationDraftsEpochIndexSql);

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_KEY_ROTATION_DRAFTS_MIGRATION_SUCCESS',
      details: {'migration': '070_group_key_rotation_drafts'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_KEY_ROTATION_DRAFTS_MIGRATION_ERROR',
      details: {
        'migration': '070_group_key_rotation_drafts',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
