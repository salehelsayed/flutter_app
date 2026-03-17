import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

Future<void> runPostsRepostMediaCryptoMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'POSTS_REPOST_MEDIA_CRYPTO_MIGRATION_START',
    details: {'migration': '038_posts_repost_media_crypto'},
  );

  try {
    final columns = await db.rawQuery(
      'PRAGMA table_info(post_media_attachments)',
    );
    final columnNames = columns.map((c) => c['name'] as String).toSet();

    if (!columnNames.contains('encryption_key_base64')) {
      await db.execute(
        'ALTER TABLE post_media_attachments ADD COLUMN encryption_key_base64 TEXT',
      );
    }
    if (!columnNames.contains('encryption_nonce')) {
      await db.execute(
        'ALTER TABLE post_media_attachments ADD COLUMN encryption_nonce TEXT',
      );
    }
    if (!columnNames.contains('is_encrypted')) {
      await db.execute(
        'ALTER TABLE post_media_attachments ADD COLUMN is_encrypted INTEGER NOT NULL DEFAULT 0',
      );
    }

    emitFlowEvent(
      layer: 'DB',
      event: 'POSTS_REPOST_MEDIA_CRYPTO_MIGRATION_SUCCESS',
      details: {'migration': '038_posts_repost_media_crypto'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'POSTS_REPOST_MEDIA_CRYPTO_MIGRATION_ERROR',
      details: {
        'migration': '038_posts_repost_media_crypto',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
