import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Migration 059: Add per-object encryption metadata to `media_attachments`.
Future<void> runMediaAttachmentEncryptionColumnsMigration(Database db) async {
  final columns = await db.rawQuery('PRAGMA table_info(media_attachments)');
  final columnNames = columns.map((col) => col['name'] as String).toSet();
  final missingColumns = <String, String>{
    if (!columnNames.contains('encryption_key_base64'))
      'encryption_key_base64': 'TEXT',
    if (!columnNames.contains('encryption_nonce')) 'encryption_nonce': 'TEXT',
    if (!columnNames.contains('encryption_scheme')) 'encryption_scheme': 'TEXT',
  };

  if (missingColumns.isEmpty) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_ATTACHMENT_ENCRYPTION_MIGRATION_ALREADY_DONE',
      details: {'migration': '059_media_attachment_encryption_columns'},
    );
    return;
  }

  emitFlowEvent(
    layer: 'DB',
    event: 'MEDIA_ATTACHMENT_ENCRYPTION_MIGRATION_START',
    details: {'migration': '059_media_attachment_encryption_columns'},
  );

  try {
    for (final entry in missingColumns.entries) {
      await db.execute(
        'ALTER TABLE media_attachments ADD COLUMN ${entry.key} ${entry.value}',
      );
    }

    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_ATTACHMENT_ENCRYPTION_MIGRATION_SUCCESS',
      details: {'migration': '059_media_attachment_encryption_columns'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_ATTACHMENT_ENCRYPTION_MIGRATION_ERROR',
      details: {
        'migration': '059_media_attachment_encryption_columns',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
