import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

Future<void> runPostsMediaUploadRecoveryMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'POSTS_MEDIA_UPLOAD_RECOVERY_MIGRATION_START',
    details: {'migration': '034_posts_media_upload_recovery'},
  );

  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS post_media_upload_recovery (
        post_id TEXT NOT NULL,
        position INTEGER NOT NULL,
        local_file_path TEXT NOT NULL,
        mime TEXT NOT NULL,
        kind TEXT NOT NULL,
        width INTEGER,
        height INTEGER,
        duration_ms INTEGER,
        waveform TEXT,
        created_at TEXT NOT NULL,
        PRIMARY KEY (post_id, position)
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_post_media_upload_recovery_post_id ON post_media_upload_recovery(post_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_post_media_upload_recovery_created_at ON post_media_upload_recovery(created_at ASC, post_id ASC, position ASC)',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'POSTS_MEDIA_UPLOAD_RECOVERY_MIGRATION_SUCCESS',
      details: {'migration': '034_posts_media_upload_recovery'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'POSTS_MEDIA_UPLOAD_RECOVERY_MIGRATION_ERROR',
      details: {
        'migration': '034_posts_media_upload_recovery',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
