// ignore_for_file: file_names
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Migration 076: Adds the doc-113 posts media crypto contract columns.
///
/// `post_media_attachments` got key/nonce/is_encrypted in 038 (pass-along
/// path); the author-attach encryption flip additionally requires the
/// explicit scheme discriminator and the ciphertext content hash (doc-112
/// parity — 1:1 got these in 058/059). Both nullable: legacy pass rows never
/// carry them and stay valid forever.
Future<void> runPostMediaAttachmentCryptoColumnsMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'POST_MEDIA_ATTACHMENT_CRYPTO_COLUMNS_MIGRATION_START',
    details: {'migration': '076_post_media_attachment_crypto_columns'},
  );

  try {
    final columns = await db.rawQuery(
      'PRAGMA table_info(post_media_attachments)',
    );
    final columnNames = columns.map((column) => column['name']).toSet();

    if (!columnNames.contains('encryption_scheme')) {
      await db.execute(
        'ALTER TABLE post_media_attachments ADD COLUMN encryption_scheme TEXT',
      );
    }
    if (!columnNames.contains('content_hash')) {
      await db.execute(
        'ALTER TABLE post_media_attachments ADD COLUMN content_hash TEXT',
      );
    }

    emitFlowEvent(
      layer: 'DB',
      event: 'POST_MEDIA_ATTACHMENT_CRYPTO_COLUMNS_MIGRATION_SUCCESS',
      details: {'migration': '076_post_media_attachment_crypto_columns'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'POST_MEDIA_ATTACHMENT_CRYPTO_COLUMNS_MIGRATION_ERROR',
      details: {
        'migration': '076_post_media_attachment_crypto_columns',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
