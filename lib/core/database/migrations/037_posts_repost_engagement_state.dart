import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

Future<void> runPostsRepostEngagementStateMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'POSTS_REPOST_ENGAGEMENT_STATE_MIGRATION_START',
    details: {'migration': '037_posts_repost_engagement_state'},
  );

  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS post_repost_engagement_participants (
        post_id TEXT NOT NULL,
        participant_peer_id TEXT NOT NULL,
        created_at TEXT NOT NULL,
        PRIMARY KEY (post_id, participant_peer_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS post_repost_heart_baseline_peers (
        post_id TEXT NOT NULL,
        sender_peer_id TEXT NOT NULL,
        created_at TEXT NOT NULL,
        PRIMARY KEY (post_id, sender_peer_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS post_repost_projection_state (
        post_id TEXT PRIMARY KEY,
        repost_total_baseline INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    emitFlowEvent(
      layer: 'DB',
      event: 'POSTS_REPOST_ENGAGEMENT_STATE_MIGRATION_SUCCESS',
      details: {'migration': '037_posts_repost_engagement_state'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'POSTS_REPOST_ENGAGEMENT_STATE_MIGRATION_ERROR',
      details: {
        'migration': '037_posts_repost_engagement_state',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
