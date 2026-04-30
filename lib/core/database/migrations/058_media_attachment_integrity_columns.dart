import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Migration 058: Add integrity metadata to `media_attachments`.
///
/// `content_hash` stores the canonical SHA-256 digest for group media relay
/// blob bytes. `thumbnail_hash` is reserved for future first-class remote
/// thumbnail blobs; current group thumbnails are generated locally.
Future<void> runMediaAttachmentIntegrityColumnsMigration(Database db) async {
  final columns = await db.rawQuery('PRAGMA table_info(media_attachments)');
  final columnNames = columns.map((col) => col['name'] as String).toSet();
  final needsContentHash = !columnNames.contains('content_hash');
  final needsThumbnailHash = !columnNames.contains('thumbnail_hash');

  if (!needsContentHash && !needsThumbnailHash) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_ATTACHMENT_INTEGRITY_MIGRATION_ALREADY_DONE',
      details: {'migration': '058_media_attachment_integrity_columns'},
    );
    return;
  }

  emitFlowEvent(
    layer: 'DB',
    event: 'MEDIA_ATTACHMENT_INTEGRITY_MIGRATION_START',
    details: {'migration': '058_media_attachment_integrity_columns'},
  );

  try {
    if (needsContentHash) {
      await db.execute(
        'ALTER TABLE media_attachments ADD COLUMN content_hash TEXT',
      );
    }
    if (needsThumbnailHash) {
      await db.execute(
        'ALTER TABLE media_attachments ADD COLUMN thumbnail_hash TEXT',
      );
    }

    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_ATTACHMENT_INTEGRITY_MIGRATION_SUCCESS',
      details: {'migration': '058_media_attachment_integrity_columns'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_ATTACHMENT_INTEGRITY_MIGRATION_ERROR',
      details: {
        'migration': '058_media_attachment_integrity_columns',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
