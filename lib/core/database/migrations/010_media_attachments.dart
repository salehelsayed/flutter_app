import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Migration 010: Creates the `media_attachments` table for storing
/// media metadata associated with conversation messages.
///
/// Idempotent: uses CREATE TABLE IF NOT EXISTS / CREATE INDEX IF NOT EXISTS.
Future<void> runMediaAttachmentsMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MEDIA_ATTACHMENTS_MIGRATION_START',
    details: {'migration': '010_media_attachments'},
  );

  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS media_attachments (
        id TEXT PRIMARY KEY,
        message_id TEXT NOT NULL,
        mime TEXT NOT NULL,
        size INTEGER NOT NULL DEFAULT 0,
        media_type TEXT NOT NULL,
        width INTEGER,
        height INTEGER,
        duration_ms INTEGER,
        local_path TEXT,
        download_status TEXT NOT NULL DEFAULT 'pending',
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_media_attachments_message
      ON media_attachments(message_id)
    ''');

    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_ATTACHMENTS_MIGRATION_SUCCESS',
      details: {'migration': '010_media_attachments'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_ATTACHMENTS_MIGRATION_ERROR',
      details: {'migration': '010_media_attachments', 'error': e.toString()},
    );
    rethrow;
  }
}
