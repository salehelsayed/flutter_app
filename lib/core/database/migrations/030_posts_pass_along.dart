import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

Future<void> runPostsPassAlongMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'POSTS_PASS_ALONG_MIGRATION_START',
    details: {'migration': '030_posts_pass_along'},
  );

  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS post_passes (
        pass_id TEXT PRIMARY KEY,
        event_id TEXT NOT NULL UNIQUE,
        post_id TEXT NOT NULL,
        sender_peer_id TEXT NOT NULL,
        passer_peer_id TEXT NOT NULL,
        passer_username TEXT NOT NULL,
        passed_at TEXT NOT NULL,
        created_at TEXT NOT NULL,
        is_incoming INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS post_origin (
        post_id TEXT PRIMARY KEY,
        origin_kind TEXT NOT NULL,
        pass_id TEXT,
        passer_peer_id TEXT,
        passer_username TEXT,
        pass_created_at TEXT
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_post_passes_post_id ON post_passes(post_id, passed_at DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_post_passes_sender_peer_id ON post_passes(sender_peer_id)',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'POSTS_PASS_ALONG_MIGRATION_SUCCESS',
      details: {'migration': '030_posts_pass_along'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'POSTS_PASS_ALONG_MIGRATION_ERROR',
      details: {'migration': '030_posts_pass_along', 'error': e.toString()},
    );
    rethrow;
  }
}
