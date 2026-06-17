// ignore_for_file: file_names

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Migration 089: Add download attempt tracking to `media_attachments`.
///
/// Adds `download_retry_count INTEGER NOT NULL DEFAULT 0` so incoming media
/// downloads can be bounded: a transient `failed` row is retryable only while
/// the counter stays below `kMaxDownloadRetries`, then flips to the terminal
/// `download_failed` status. Existing rows default to 0 and simply re-enter the
/// bounded budget (INV-DL-5).
Future<void> runMediaAttachmentDownloadRetryColumnMigration(Database db) async {
  final columns = await db.rawQuery('PRAGMA table_info(media_attachments)');
  final columnNames = columns.map((col) => col['name'] as String).toSet();

  if (columnNames.contains('download_retry_count')) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_ATTACHMENT_DOWNLOAD_RETRY_MIGRATION_ALREADY_DONE',
      details: {'migration': '089_media_attachment_download_retry_column'},
    );
    return;
  }

  emitFlowEvent(
    layer: 'DB',
    event: 'MEDIA_ATTACHMENT_DOWNLOAD_RETRY_MIGRATION_START',
    details: {'migration': '089_media_attachment_download_retry_column'},
  );

  try {
    await db.execute(
      'ALTER TABLE media_attachments ADD COLUMN download_retry_count INTEGER NOT NULL DEFAULT 0',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_ATTACHMENT_DOWNLOAD_RETRY_MIGRATION_SUCCESS',
      details: {'migration': '089_media_attachment_download_retry_column'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_ATTACHMENT_DOWNLOAD_RETRY_MIGRATION_ERROR',
      details: {
        'migration': '089_media_attachment_download_retry_column',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
