import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

Future<void> runPostsNearbyMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'POSTS_NEARBY_MIGRATION_START',
    details: {'migration': '029_posts_nearby'},
  );

  try {
    final postColumns = await db.rawQuery("PRAGMA table_info(posts)");
    final postColumnNames = postColumns
        .map((column) => column['name'] as String? ?? '')
        .toSet();
    if (!postColumnNames.contains('audience_radius_m')) {
      await db.execute(
        'ALTER TABLE posts ADD COLUMN audience_radius_m INTEGER',
      );
    }
    if (!postColumnNames.contains('nearby_distance_m')) {
      await db.execute(
        'ALTER TABLE posts ADD COLUMN nearby_distance_m INTEGER',
      );
    }
    if (!postColumnNames.contains('nearby_sender_lat_e3')) {
      await db.execute(
        'ALTER TABLE posts ADD COLUMN nearby_sender_lat_e3 INTEGER',
      );
    }
    if (!postColumnNames.contains('nearby_sender_lng_e3')) {
      await db.execute(
        'ALTER TABLE posts ADD COLUMN nearby_sender_lng_e3 INTEGER',
      );
    }
    if (!postColumnNames.contains('nearby_sender_captured_at')) {
      await db.execute(
        'ALTER TABLE posts ADD COLUMN nearby_sender_captured_at TEXT',
      );
    }
    if (!postColumnNames.contains('nearby_sender_accuracy_m')) {
      await db.execute(
        'ALTER TABLE posts ADD COLUMN nearby_sender_accuracy_m REAL',
      );
    }

    await db.execute('''
      CREATE TABLE IF NOT EXISTS post_privacy_state (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        sharing_enabled INTEGER NOT NULL DEFAULT 0,
        permission_state TEXT NOT NULL DEFAULT 'unknown',
        last_local_lat_e3 INTEGER,
        last_local_lng_e3 INTEGER,
        last_local_captured_at TEXT,
        last_local_accuracy_m REAL,
        last_refresh_attempt_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS post_location_presence (
        peer_id TEXT PRIMARY KEY,
        lat_e3 INTEGER,
        lng_e3 INTEGER,
        captured_at TEXT NOT NULL,
        accuracy_m REAL,
        updated_at TEXT NOT NULL,
        status TEXT NOT NULL
      )
    ''');

    await db.insert('post_privacy_state', <String, Object?>{
      'id': 1,
      'sharing_enabled': 0,
      'permission_state': 'unknown',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_post_location_presence_updated_at ON post_location_presence(updated_at DESC)',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'POSTS_NEARBY_MIGRATION_SUCCESS',
      details: {'migration': '029_posts_nearby'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'POSTS_NEARBY_MIGRATION_ERROR',
      details: {'migration': '029_posts_nearby', 'error': e.toString()},
    );
    rethrow;
  }
}
