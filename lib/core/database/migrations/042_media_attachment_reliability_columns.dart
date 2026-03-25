import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Migration 042: Add attachment retry tracking to `media_attachments`.
///
/// Adds `upload_retry_count INTEGER NOT NULL DEFAULT 0` so outgoing media
/// uploads can retry in place without creating new attachment rows.
Future<void> runMediaAttachmentReliabilityColumnsMigration(Database db) async {
  final columns = await db.rawQuery('PRAGMA table_info(media_attachments)');
  final columnNames = columns.map((col) => col['name'] as String).toSet();

  if (columnNames.contains('upload_retry_count')) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_ATTACHMENT_RELIABILITY_MIGRATION_ALREADY_DONE',
      details: {'migration': '042_media_attachment_reliability_columns'},
    );
    return;
  }

  emitFlowEvent(
    layer: 'DB',
    event: 'MEDIA_ATTACHMENT_RELIABILITY_MIGRATION_START',
    details: {'migration': '042_media_attachment_reliability_columns'},
  );

  try {
    await db.execute(
      'ALTER TABLE media_attachments ADD COLUMN upload_retry_count INTEGER NOT NULL DEFAULT 0',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_ATTACHMENT_RELIABILITY_MIGRATION_SUCCESS',
      details: {'migration': '042_media_attachment_reliability_columns'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_ATTACHMENT_RELIABILITY_MIGRATION_ERROR',
      details: {
        'migration': '042_media_attachment_reliability_columns',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
