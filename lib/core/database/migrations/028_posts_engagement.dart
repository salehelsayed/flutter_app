import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

Future<void> runPostsEngagementMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'POSTS_ENGAGEMENT_MIGRATION_START',
    details: {'migration': '028_posts_engagement'},
  );

  try {
    final postsColumns = await db.rawQuery("PRAGMA table_info(posts)");
    final hasMediaKind = postsColumns.any(
      (column) => column['name'] == 'media_kind',
    );
    final hasLastEngagementAt = postsColumns.any(
      (column) => column['name'] == 'last_engagement_at',
    );
    if (!hasMediaKind) {
      await db.execute(
        "ALTER TABLE posts ADD COLUMN media_kind TEXT NOT NULL DEFAULT 'none'",
      );
    }
    if (!hasLastEngagementAt) {
      await db.execute("ALTER TABLE posts ADD COLUMN last_engagement_at TEXT");
    }

    await db.execute('''
      CREATE TABLE IF NOT EXISTS post_comments (
        comment_id TEXT PRIMARY KEY,
        event_id TEXT NOT NULL UNIQUE,
        post_id TEXT NOT NULL,
        sender_peer_id TEXT NOT NULL,
        author_username TEXT NOT NULL DEFAULT '',
        body TEXT NOT NULL,
        commented_at TEXT NOT NULL,
        created_at TEXT NOT NULL,
        is_incoming INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS post_reactions (
        reaction_id TEXT PRIMARY KEY,
        event_id TEXT NOT NULL UNIQUE,
        post_id TEXT NOT NULL,
        sender_peer_id TEXT NOT NULL,
        kind TEXT NOT NULL,
        is_active INTEGER NOT NULL,
        reacted_at TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS post_comment_reactions (
        reaction_id TEXT PRIMARY KEY,
        event_id TEXT NOT NULL UNIQUE,
        post_id TEXT NOT NULL,
        comment_id TEXT NOT NULL,
        sender_peer_id TEXT NOT NULL,
        kind TEXT NOT NULL,
        is_active INTEGER NOT NULL,
        reacted_at TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS post_pending_child_events (
        event_id TEXT PRIMARY KEY,
        post_id TEXT NOT NULL,
        event_type TEXT NOT NULL,
        sender_peer_id TEXT NOT NULL,
        created_at TEXT NOT NULL,
        raw_envelope TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS post_media_attachments (
        media_id TEXT PRIMARY KEY,
        post_id TEXT NOT NULL,
        blob_id TEXT NOT NULL,
        kind TEXT NOT NULL,
        mime TEXT NOT NULL,
        size_bytes INTEGER NOT NULL DEFAULT 0,
        position INTEGER NOT NULL DEFAULT 0,
        width INTEGER,
        height INTEGER,
        duration_ms INTEGER,
        local_path TEXT,
        download_status TEXT NOT NULL DEFAULT 'pending',
        created_at TEXT NOT NULL,
        waveform TEXT,
        thumbnail_blob_id TEXT
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_post_comments_post_id ON post_comments(post_id, commented_at ASC, comment_id ASC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_post_reactions_post_id ON post_reactions(post_id, reacted_at ASC, reaction_id ASC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_post_comment_reactions_comment_id ON post_comment_reactions(comment_id, reacted_at ASC, reaction_id ASC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_post_pending_child_events_post_id ON post_pending_child_events(post_id, created_at ASC, event_id ASC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_post_media_attachments_post_id ON post_media_attachments(post_id, position ASC, created_at ASC, media_id ASC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_posts_expires_at ON posts(expires_at)',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'POSTS_ENGAGEMENT_MIGRATION_SUCCESS',
      details: {'migration': '028_posts_engagement'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'POSTS_ENGAGEMENT_MIGRATION_ERROR',
      details: {'migration': '028_posts_engagement', 'error': e.toString()},
    );
    rethrow;
  }
}
