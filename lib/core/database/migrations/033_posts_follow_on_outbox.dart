import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

Future<void> runPostsFollowOnOutboxMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'POSTS_FOLLOW_ON_OUTBOX_MIGRATION_START',
    details: {'migration': '033_posts_follow_on_outbox'},
  );

  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS post_follow_on_outbox_events (
        event_id TEXT PRIMARY KEY,
        event_type TEXT NOT NULL,
        post_id TEXT NOT NULL,
        comment_id TEXT,
        sender_peer_id TEXT NOT NULL,
        raw_envelope TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS post_follow_on_outbox_recipient_deliveries (
        event_id TEXT NOT NULL,
        recipient_peer_id TEXT NOT NULL,
        delivery_status TEXT NOT NULL,
        delivery_path TEXT NOT NULL,
        last_error TEXT,
        last_attempt_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (event_id, recipient_peer_id)
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_post_follow_on_outbox_events_created_at ON post_follow_on_outbox_events(created_at ASC, event_id ASC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_post_follow_on_outbox_events_post_id ON post_follow_on_outbox_events(post_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_post_follow_on_outbox_events_comment_id ON post_follow_on_outbox_events(comment_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_post_follow_on_outbox_recipient_deliveries_status ON post_follow_on_outbox_recipient_deliveries(delivery_status, updated_at ASC, event_id ASC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_post_follow_on_outbox_recipient_deliveries_recipient ON post_follow_on_outbox_recipient_deliveries(recipient_peer_id)',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'POSTS_FOLLOW_ON_OUTBOX_MIGRATION_SUCCESS',
      details: {'migration': '033_posts_follow_on_outbox'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'POSTS_FOLLOW_ON_OUTBOX_MIGRATION_ERROR',
      details: {
        'migration': '033_posts_follow_on_outbox',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
