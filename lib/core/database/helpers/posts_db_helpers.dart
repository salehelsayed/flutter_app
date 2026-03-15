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
    final hasAudienceRadiusM = columns.any(
      (column) => column['name'] == 'audience_radius_m',
    );
    final hasNearbyDistanceM = columns.any(
      (column) => column['name'] == 'nearby_distance_m',
    );
    final hasNearbySenderLatE3 = columns.any(
      (column) => column['name'] == 'nearby_sender_lat_e3',
    );
    final hasNearbySenderLngE3 = columns.any(
      (column) => column['name'] == 'nearby_sender_lng_e3',
    );
    final hasNearbySenderCapturedAt = columns.any(
      (column) => column['name'] == 'nearby_sender_captured_at',
    );
    final hasNearbySenderAccuracyM = columns.any(
      (column) => column['name'] == 'nearby_sender_accuracy_m',
    );
    if (!hasMediaKind) {
      insertRow.remove('media_kind');
    }
    if (!hasLastEngagementAt) {
      insertRow.remove('last_engagement_at');
    }
    if (!hasAudienceRadiusM) {
      insertRow.remove('audience_radius_m');
    }
    if (!hasNearbyDistanceM) {
      insertRow.remove('nearby_distance_m');
    }
    if (!hasNearbySenderLatE3) {
      insertRow.remove('nearby_sender_lat_e3');
    }
    if (!hasNearbySenderLngE3) {
      insertRow.remove('nearby_sender_lng_e3');
    }
    if (!hasNearbySenderCapturedAt) {
      insertRow.remove('nearby_sender_captured_at');
    }
    if (!hasNearbySenderAccuracyM) {
      insertRow.remove('nearby_sender_accuracy_m');
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
        po.origin_kind,
        po.pass_id,
        po.passer_peer_id,
        po.passer_username,
        po.pass_created_at,
        COALESCE(pc.share_count, 0) AS share_count,
        COALESCE(fs.is_hidden, 0) AS is_hidden,
        COALESCE(fs.is_read, 0) AS is_read,
        COALESCE(fs.last_focused_at, '') AS last_focused_at
      FROM posts p
      LEFT JOIN post_feed_state fs ON fs.post_id = p.post_id
      LEFT JOIN post_origin po ON po.post_id = p.post_id
      LEFT JOIN (
        SELECT post_id, COUNT(*) AS share_count
        FROM post_passes
        GROUP BY post_id
      ) pc ON pc.post_id = p.post_id
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
      po.origin_kind,
      po.pass_id,
      po.passer_peer_id,
      po.passer_username,
      po.pass_created_at,
      COALESCE(pc.share_count, 0) AS share_count,
      COALESCE(fs.is_hidden, 0) AS is_hidden,
      COALESCE(fs.is_read, 0) AS is_read,
      COALESCE(fs.last_focused_at, '') AS last_focused_at
    FROM posts p
    LEFT JOIN post_feed_state fs ON fs.post_id = p.post_id
    LEFT JOIN post_origin po ON po.post_id = p.post_id
    LEFT JOIN (
      SELECT post_id, COUNT(*) AS share_count
      FROM post_passes
      GROUP BY post_id
    ) pc ON pc.post_id = p.post_id
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
        po.origin_kind,
        po.pass_id,
        po.passer_peer_id,
        po.passer_username,
        po.pass_created_at,
        COALESCE(pc.share_count, 0) AS share_count,
        COALESCE(fs.is_hidden, 0) AS is_hidden,
        COALESCE(fs.is_read, 0) AS is_read,
        COALESCE(fs.last_focused_at, '') AS last_focused_at
      FROM posts p
      LEFT JOIN post_feed_state fs ON fs.post_id = p.post_id
      LEFT JOIN post_origin po ON po.post_id = p.post_id
      LEFT JOIN (
        SELECT post_id, COUNT(*) AS share_count
        FROM post_passes
        GROUP BY post_id
      ) pc ON pc.post_id = p.post_id
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
      'post_passes',
      where: 'post_id = ?',
      whereArgs: <Object?>[postId],
    );
    await txn.delete(
      'post_origin',
      where: 'post_id = ?',
      whereArgs: <Object?>[postId],
    );
    await txn.delete(
      'post_pins',
      where: 'post_id = ?',
      whereArgs: <Object?>[postId],
    );
    await txn.delete(
      'post_pin_dismissals',
      where: 'post_id = ?',
      whereArgs: <Object?>[postId],
    );
    await txn.delete(
      'post_feed_state',
      where: 'post_id = ?',
      whereArgs: <Object?>[postId],
    );
    await txn.delete(
      'posts',
      where: 'post_id = ?',
      whereArgs: <Object?>[postId],
    );
  });
}
