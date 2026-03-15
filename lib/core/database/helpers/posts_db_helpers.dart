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
    final insertRow = Map<String, Object?>.from(row);
    final columns = await db.rawQuery("PRAGMA table_info(posts)");
    final hasMediaKind = columns.any(
      (column) => column['name'] == 'media_kind',
    );
    final hasLastEngagementAt = columns.any(
      (column) => column['name'] == 'last_engagement_at',
    );
    if (!hasMediaKind) {
      insertRow.remove('media_kind');
    }
    if (!hasLastEngagementAt) {
      insertRow.remove('last_engagement_at');
    }
    await db.insert(
      'posts',
      insertRow,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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

Future<List<Map<String, Object?>>> dbLoadExpiredPosts(
  Database db,
  String nowIso,
) async {
  return db.rawQuery(
    '''
      SELECT
        p.*,
        COALESCE(fs.is_hidden, 0) AS is_hidden,
        COALESCE(fs.is_read, 0) AS is_read,
        COALESCE(fs.last_focused_at, '') AS last_focused_at
      FROM posts p
      LEFT JOIN post_feed_state fs ON fs.post_id = p.post_id
      WHERE p.keep_available = 0
        AND p.expires_at <= ?
    ''',
    <Object?>[nowIso],
  );
}

Future<void> dbDeletePostCascade(Database db, String postId) async {
  await db.transaction((txn) async {
    await txn.delete(
      'post_comment_reactions',
      where: 'post_id = ?',
      whereArgs: <Object?>[postId],
    );
    await txn.delete(
      'post_reactions',
      where: 'post_id = ?',
      whereArgs: <Object?>[postId],
    );
    await txn.delete(
      'post_comments',
      where: 'post_id = ?',
      whereArgs: <Object?>[postId],
    );
    await txn.delete(
      'post_media_attachments',
      where: 'post_id = ?',
      whereArgs: <Object?>[postId],
    );
    await txn.delete(
      'post_pending_child_events',
      where: 'post_id = ?',
      whereArgs: <Object?>[postId],
    );
    await txn.delete(
      'post_recipients',
      where: 'post_id = ?',
      whereArgs: <Object?>[postId],
    );
    await txn.delete(
      'post_feed_state',
      where: 'post_id = ?',
      whereArgs: <Object?>[postId],
    );
    await txn.delete('posts', where: 'post_id = ?', whereArgs: <Object?>[postId]);
  });
}
