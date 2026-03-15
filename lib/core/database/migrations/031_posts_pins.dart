import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

Future<void> runPostsPinsMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'POSTS_PINS_MIGRATION_START',
    details: {'migration': '031_posts_pins'},
  );

  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS post_pins (
        post_id TEXT PRIMARY KEY,
        event_id TEXT NOT NULL UNIQUE,
        pin_event_id TEXT NOT NULL,
        sender_peer_id TEXT NOT NULL,
        state TEXT NOT NULL,
        effective_at TEXT NOT NULL,
        pinned_at TEXT,
        removed_at TEXT,
        reason TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS post_pin_dismissals (
        post_id TEXT PRIMARY KEY,
        dismissed_at TEXT NOT NULL
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_post_pins_state_effective_at ON post_pins(state, effective_at DESC, post_id DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_post_pins_sender_peer_id ON post_pins(sender_peer_id)',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'POSTS_PINS_MIGRATION_SUCCESS',
      details: {'migration': '031_posts_pins'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'POSTS_PINS_MIGRATION_ERROR',
      details: {'migration': '031_posts_pins', 'error': e.toString()},
    );
    rethrow;
  }
}
