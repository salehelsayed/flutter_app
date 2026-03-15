import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

Future<void> runPostsCoreMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'POSTS_CORE_MIGRATION_START',
    details: {'migration': '027_posts_core'},
  );

  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS posts (
        post_id TEXT PRIMARY KEY,
        event_id TEXT NOT NULL UNIQUE,
        sender_peer_id TEXT NOT NULL,
        author_peer_id TEXT NOT NULL,
        author_username TEXT NOT NULL,
        text TEXT NOT NULL,
        audience_kind TEXT NOT NULL,
        selected_peer_ids TEXT,
        scope_label TEXT,
        post_created_at TEXT NOT NULL,
        visible_at TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        keep_available INTEGER NOT NULL DEFAULT 0,
        is_incoming INTEGER NOT NULL DEFAULT 1,
        is_focused INTEGER NOT NULL DEFAULT 0,
        delivery_status TEXT NOT NULL DEFAULT 'available'
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS post_recipients (
        post_id TEXT NOT NULL,
        recipient_peer_id TEXT NOT NULL,
        delivery_status TEXT NOT NULL,
        last_attempt_at TEXT NOT NULL,
        delivery_path TEXT NOT NULL,
        last_error TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (post_id, recipient_peer_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS post_feed_state (
        post_id TEXT PRIMARY KEY,
        is_hidden INTEGER NOT NULL DEFAULT 0,
        is_read INTEGER NOT NULL DEFAULT 0,
        last_focused_at TEXT,
        last_viewed_at TEXT
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_posts_visible_at ON posts(visible_at DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_posts_author_peer_id ON posts(author_peer_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_post_recipients_post_id ON post_recipients(post_id)',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'POSTS_CORE_MIGRATION_SUCCESS',
      details: {'migration': '027_posts_core'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'POSTS_CORE_MIGRATION_ERROR',
      details: {'migration': '027_posts_core', 'error': e.toString()},
    );
    rethrow;
  }
}
