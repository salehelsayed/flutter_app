// ignore_for_file: file_names

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

const _migrationName = '110_direct_media_custody_intent';

/// Adds the local-only manifest authority for newly prepared direct media.
///
/// Historical rows remain null: without the complete authored attachment-ID
/// set, an earlier row cannot safely be promoted into initial-envelope
/// custody. The column intentionally has no index because it is consumed only
/// while loading a message by its existing primary key.
Future<void> runDirectMediaCustodyIntentMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'DIRECT_MEDIA_CUSTODY_INTENT_MIGRATION_START',
    details: const {'migration': _migrationName},
  );

  try {
    final columns = await db.rawQuery('PRAGMA table_info(messages)');
    final alreadyInstalled = columns.any(
      (column) => column['name'] == 'direct_media_custody_intent_id',
    );
    if (!alreadyInstalled) {
      await db.execute('''
        ALTER TABLE messages
        ADD COLUMN direct_media_custody_intent_id TEXT CHECK (
          direct_media_custody_intent_id IS NULL OR (
            typeof(direct_media_custody_intent_id) = 'text' AND
            length(direct_media_custody_intent_id) = 32 AND
            length(CAST(direct_media_custody_intent_id AS BLOB)) = 32 AND
            direct_media_custody_intent_id NOT GLOB '*[^0-9a-f]*'
          )
        )
      ''');
    }

    emitFlowEvent(
      layer: 'DB',
      event: 'DIRECT_MEDIA_CUSTODY_INTENT_MIGRATION_SUCCESS',
      details: const {'migration': _migrationName},
    );
  } catch (error) {
    emitFlowEvent(
      layer: 'DB',
      event: 'DIRECT_MEDIA_CUSTODY_INTENT_MIGRATION_ERROR',
      details: {'migration': _migrationName, 'error': error.toString()},
    );
    rethrow;
  }
}
