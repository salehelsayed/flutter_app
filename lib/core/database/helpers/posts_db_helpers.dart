import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

Future<void> dbInsertPost(Database db, Map<String, Object?> row) async {
  final postId = row['post_id'] as String? ?? '';
  emitFlowEvent(
    layer: 'DB',
    event: 'POSTS_DB_INSERT_START',
    details: {'postId': postId},
  );
  try {
    await db.insert('posts', row, conflictAlgorithm: ConflictAlgorithm.replace);
    await db.insert('post_feed_state', <String, Object?>{
      'post_id': postId,
      'is_hidden': 0,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    emitFlowEvent(
      layer: 'DB',
      event: 'POSTS_DB_INSERT_SUCCESS',
      details: {'postId': postId},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'POSTS_DB_INSERT_ERROR',
      details: {'postId': postId, 'error': e.toString()},
    );
    rethrow;
  }
}

Future<Map<String, Object?>?> dbLoadPost(Database db, String postId) async {
  final rows = await db.rawQuery(
    '''
      SELECT
        p.*,
        COALESCE(fs.is_hidden, 0) AS is_hidden,
        COALESCE(fs.is_read, 0) AS is_read,
        COALESCE(fs.last_focused_at, '') AS last_focused_at
      FROM posts p
      LEFT JOIN post_feed_state fs ON fs.post_id = p.post_id
      WHERE p.post_id = ?
      LIMIT 1
    ''',
    <Object?>[postId],
  );
  if (rows.isEmpty) {
    return null;
  }
  return rows.first;
}

Future<List<Map<String, Object?>>> dbLoadPostsFeed(Database db) async {
  return db.rawQuery('''
    SELECT
      p.*,
      COALESCE(fs.is_hidden, 0) AS is_hidden,
      COALESCE(fs.is_read, 0) AS is_read,
      COALESCE(fs.last_focused_at, '') AS last_focused_at
    FROM posts p
    LEFT JOIN post_feed_state fs ON fs.post_id = p.post_id
    WHERE COALESCE(fs.is_hidden, 0) = 0
    ORDER BY p.visible_at DESC, p.post_created_at DESC, p.post_id DESC
  ''');
}
