import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

void _emitPostsDbTiming({
  required String event,
  required Stopwatch stopwatch,
  required Map<String, dynamic> details,
}) {
  emitFlowEvent(
    layer: 'DB',
    event: event,
    details: <String, dynamic>{
      'elapsedMs': stopwatch.elapsedMilliseconds,
      ...details,
    },
  );
}

Future<String> _localSharedToCountSubquery(Database db) async {
  final sharedToExpression = await _sharedToCountExpression(db);
  return '''
      SELECT post_id, $sharedToExpression AS local_shared_to_count
      FROM post_passes
      GROUP BY post_id
    ''';
}

Future<String> _sharedToCountExpression(Database db) async {
  final columns = await db.rawQuery('PRAGMA table_info(post_passes)');
  final hasRecipientCount = columns.any(
    (column) => column['name'] == 'recipient_count',
  );
  return hasRecipientCount ? 'SUM(COALESCE(recipient_count, 1))' : 'COUNT(*)';
}

Future<String> _sharedToBaselineExpression(Database db) async {
  final columns = await db.rawQuery(
    'PRAGMA table_info(post_repost_projection_state)',
  );
  final hasSharedToCountBaseline = columns.any(
    (column) => column['name'] == 'shared_to_count_baseline',
  );
  return hasSharedToCountBaseline
      ? 'COALESCE(NULLIF(prs.shared_to_count_baseline, 0), prs.repost_total_baseline, 0)'
      : 'COALESCE(prs.repost_total_baseline, 0)';
}

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
  final stopwatch = Stopwatch()..start();
  try {
    final localSharedToCountSubquery = await _localSharedToCountSubquery(db);
    final sharedToBaselineExpression = await _sharedToBaselineExpression(db);
    final rows = await db.rawQuery(
      '''
        SELECT
          p.*,
          po.origin_kind,
          po.pass_id,
          po.passer_peer_id,
          po.passer_username,
          po.pass_created_at,
          COALESCE(pc.local_share_count, 0) +
              COALESCE(prs.repost_total_baseline, 0) AS share_count,
          COALESCE(psc.local_shared_to_count, 0) +
              $sharedToBaselineExpression AS total_shared_to_count,
          COALESCE(fs.is_hidden, 0) AS is_hidden,
          COALESCE(fs.is_read, 0) AS is_read,
          COALESCE(fs.last_focused_at, '') AS last_focused_at
        FROM posts p
        LEFT JOIN post_feed_state fs ON fs.post_id = p.post_id
        LEFT JOIN post_origin po ON po.post_id = p.post_id
        LEFT JOIN post_repost_projection_state prs ON prs.post_id = p.post_id
        LEFT JOIN (
          SELECT post_id, COUNT(*) AS local_share_count
          FROM post_passes
          GROUP BY post_id
        ) pc ON pc.post_id = p.post_id
        LEFT JOIN (
          $localSharedToCountSubquery
        ) psc ON psc.post_id = p.post_id
        WHERE p.post_id = ?
        LIMIT 1
      ''',
      <Object?>[postId],
    );
    final row = rows.isEmpty ? null : rows.first;
    _emitPostsDbTiming(
      event: 'POSTS_DB_LOAD_POST_TIMING',
      stopwatch: stopwatch,
      details: <String, dynamic>{
        'postId': postId,
        'outcome': row == null ? 'miss' : 'hit',
      },
    );
    return row;
  } catch (e) {
    _emitPostsDbTiming(
      event: 'POSTS_DB_LOAD_POST_TIMING',
      stopwatch: stopwatch,
      details: <String, dynamic>{
        'postId': postId,
        'outcome': 'error',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}

Future<List<Map<String, Object?>>> dbLoadPostsByIds(
  Database db,
  List<String> postIds,
) async {
  final uniquePostIds = postIds.toSet().toList(growable: false);
  if (uniquePostIds.isEmpty) {
    return const <Map<String, Object?>>[];
  }
  final stopwatch = Stopwatch()..start();
  try {
    final localSharedToCountSubquery = await _localSharedToCountSubquery(db);
    final sharedToBaselineExpression = await _sharedToBaselineExpression(db);
    final placeholders = List<String>.filled(
      uniquePostIds.length,
      '?',
    ).join(', ');
    final rows = await db.rawQuery('''
        SELECT
          p.*,
          po.origin_kind,
          po.pass_id,
          po.passer_peer_id,
          po.passer_username,
          po.pass_created_at,
          COALESCE(pc.local_share_count, 0) +
              COALESCE(prs.repost_total_baseline, 0) AS share_count,
          COALESCE(psc.local_shared_to_count, 0) +
              $sharedToBaselineExpression AS total_shared_to_count,
          COALESCE(fs.is_hidden, 0) AS is_hidden,
          COALESCE(fs.is_read, 0) AS is_read,
          COALESCE(fs.last_focused_at, '') AS last_focused_at
        FROM posts p
        LEFT JOIN post_feed_state fs ON fs.post_id = p.post_id
        LEFT JOIN post_origin po ON po.post_id = p.post_id
        LEFT JOIN post_repost_projection_state prs ON prs.post_id = p.post_id
        LEFT JOIN (
          SELECT post_id, COUNT(*) AS local_share_count
          FROM post_passes
          GROUP BY post_id
        ) pc ON pc.post_id = p.post_id
        LEFT JOIN (
          $localSharedToCountSubquery
        ) psc ON psc.post_id = p.post_id
        WHERE p.post_id IN ($placeholders)
      ''', uniquePostIds);
    _emitPostsDbTiming(
      event: 'POSTS_DB_LOAD_BY_IDS_TIMING',
      stopwatch: stopwatch,
      details: <String, dynamic>{
        'requestedCount': uniquePostIds.length,
        'loadedCount': rows.length,
      },
    );
    return rows;
  } catch (e) {
    _emitPostsDbTiming(
      event: 'POSTS_DB_LOAD_BY_IDS_TIMING',
      stopwatch: stopwatch,
      details: <String, dynamic>{
        'requestedCount': uniquePostIds.length,
        'outcome': 'error',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}

Future<List<Map<String, Object?>>> dbLoadPostsFeed(Database db) async {
  final stopwatch = Stopwatch()..start();
  try {
    final localSharedToCountSubquery = await _localSharedToCountSubquery(db);
    final sharedToBaselineExpression = await _sharedToBaselineExpression(db);
    final rows = await db.rawQuery('''
      SELECT
        p.*,
        po.origin_kind,
        po.pass_id,
        po.passer_peer_id,
        po.passer_username,
        po.pass_created_at,
        COALESCE(pc.local_share_count, 0) +
            COALESCE(prs.repost_total_baseline, 0) AS share_count,
        COALESCE(psc.local_shared_to_count, 0) +
            $sharedToBaselineExpression AS total_shared_to_count,
        COALESCE(fs.is_hidden, 0) AS is_hidden,
        COALESCE(fs.is_read, 0) AS is_read,
        COALESCE(fs.last_focused_at, '') AS last_focused_at
      FROM posts p
      LEFT JOIN post_feed_state fs ON fs.post_id = p.post_id
      LEFT JOIN post_origin po ON po.post_id = p.post_id
      LEFT JOIN post_repost_projection_state prs ON prs.post_id = p.post_id
      LEFT JOIN (
        SELECT post_id, COUNT(*) AS local_share_count
        FROM post_passes
        GROUP BY post_id
      ) pc ON pc.post_id = p.post_id
      LEFT JOIN (
        $localSharedToCountSubquery
      ) psc ON psc.post_id = p.post_id
      WHERE COALESCE(fs.is_hidden, 0) = 0
      ORDER BY p.visible_at DESC, p.post_created_at DESC, p.post_id DESC
    ''');
    _emitPostsDbTiming(
      event: 'POSTS_DB_LOAD_FEED_TIMING',
      stopwatch: stopwatch,
      details: <String, dynamic>{'loadedCount': rows.length},
    );
    return rows;
  } catch (e) {
    _emitPostsDbTiming(
      event: 'POSTS_DB_LOAD_FEED_TIMING',
      stopwatch: stopwatch,
      details: <String, dynamic>{'outcome': 'error', 'error': e.toString()},
    );
    rethrow;
  }
}

Future<Map<String, int>> dbLoadViewerSharedToCountsForPosts(
  Database db,
  List<String> postIds,
  String viewerPeerId,
) async {
  if (postIds.isEmpty || viewerPeerId.isEmpty) {
    return const <String, int>{};
  }
  final sharedToExpression = await _sharedToCountExpression(db);
  final placeholders = List<String>.filled(postIds.length, '?').join(', ');
  final rows = await db.rawQuery(
    '''
      SELECT post_id, $sharedToExpression AS viewer_shared_to_count
      FROM post_passes
      WHERE post_id IN ($placeholders)
        AND sender_peer_id = ?
        AND is_incoming = 0
      GROUP BY post_id
    ''',
    <Object?>[...postIds, viewerPeerId],
  );
  return <String, int>{
    for (final row in rows)
      if (row['post_id'] is String)
        row['post_id'] as String:
            ((row['viewer_shared_to_count'] as num?)?.toInt() ?? 0),
  };
}

Future<List<Map<String, Object?>>> dbLoadRetryableOutgoingPosts(
  Database db,
) async {
  final localSharedToCountSubquery = await _localSharedToCountSubquery(db);
  final sharedToBaselineExpression = await _sharedToBaselineExpression(db);
  return db.rawQuery('''
      SELECT
        p.*,
        po.origin_kind,
        po.pass_id,
        po.passer_peer_id,
        po.passer_username,
        po.pass_created_at,
        COALESCE(pc.local_share_count, 0) +
            COALESCE(prs.repost_total_baseline, 0) AS share_count,
        COALESCE(psc.local_shared_to_count, 0) +
            $sharedToBaselineExpression AS total_shared_to_count,
        COALESCE(fs.is_hidden, 0) AS is_hidden,
        COALESCE(fs.is_read, 0) AS is_read,
        COALESCE(fs.last_focused_at, '') AS last_focused_at
      FROM posts p
      LEFT JOIN post_feed_state fs ON fs.post_id = p.post_id
      LEFT JOIN post_origin po ON po.post_id = p.post_id
      LEFT JOIN post_repost_projection_state prs ON prs.post_id = p.post_id
      LEFT JOIN (
        SELECT post_id, COUNT(*) AS local_share_count
        FROM post_passes
        GROUP BY post_id
      ) pc ON pc.post_id = p.post_id
      LEFT JOIN (
        $localSharedToCountSubquery
      ) psc ON psc.post_id = p.post_id
      WHERE p.is_incoming = 0
        AND p.delivery_status IN ('sending', 'partial', 'failed')
      ORDER BY p.visible_at DESC, p.post_created_at DESC, p.post_id DESC
    ''');
}

Future<List<Map<String, Object?>>> dbLoadExpiredPosts(
  Database db,
  String nowIso,
) async {
  final localSharedToCountSubquery = await _localSharedToCountSubquery(db);
  final sharedToBaselineExpression = await _sharedToBaselineExpression(db);
  return db.rawQuery(
    '''
      SELECT
        p.*,
        po.origin_kind,
        po.pass_id,
        po.passer_peer_id,
        po.passer_username,
        po.pass_created_at,
        COALESCE(pc.local_share_count, 0) +
            COALESCE(prs.repost_total_baseline, 0) AS share_count,
        COALESCE(psc.local_shared_to_count, 0) +
            $sharedToBaselineExpression AS total_shared_to_count,
        COALESCE(fs.is_hidden, 0) AS is_hidden,
        COALESCE(fs.is_read, 0) AS is_read,
        COALESCE(fs.last_focused_at, '') AS last_focused_at
      FROM posts p
      LEFT JOIN post_feed_state fs ON fs.post_id = p.post_id
      LEFT JOIN post_origin po ON po.post_id = p.post_id
      LEFT JOIN post_repost_projection_state prs ON prs.post_id = p.post_id
      LEFT JOIN (
        SELECT post_id, COUNT(*) AS local_share_count
        FROM post_passes
        GROUP BY post_id
      ) pc ON pc.post_id = p.post_id
      LEFT JOIN (
        $localSharedToCountSubquery
      ) psc ON psc.post_id = p.post_id
      WHERE p.keep_available = 0
        AND p.expires_at <= ?
    ''',
    <Object?>[nowIso],
  );
}

Future<void> dbDeletePostCascade(Database db, String postId) async {
  await db.transaction((txn) async {
    await _deleteRequiredPostRows(txn, 'post_comment_reactions', postId);
    await _deleteRequiredPostRows(txn, 'post_reactions', postId);
    await _deleteRequiredPostRows(txn, 'post_comments', postId);
    await _deleteRequiredPostRows(txn, 'post_media_attachments', postId);
    await _deleteRequiredPostRows(txn, 'post_media_upload_recovery', postId);
    await _deleteRequiredPostRows(txn, 'post_pending_child_events', postId);
    await _deleteRequiredPostRows(txn, 'post_recipients', postId);
    await _deleteRequiredPostRows(txn, 'post_passes', postId);
    await _deleteRequiredPostRows(txn, 'post_origin', postId);
    await _deleteRequiredPostRows(
      txn,
      'post_repost_engagement_participants',
      postId,
    );
    await _deleteRequiredPostRows(
      txn,
      'post_repost_heart_baseline_peers',
      postId,
    );
    await _deleteRequiredPostRows(txn, 'post_repost_projection_state', postId);
    await _deleteRequiredPostRows(txn, 'post_pins', postId);
    await _deleteRequiredPostRows(txn, 'post_pin_dismissals', postId);
    await _deleteRequiredPostRows(txn, 'post_feed_state', postId);
    await _deleteRequiredPostRows(txn, 'post_pass_avatar_snapshots', postId);
    await _deleteRequiredPostRows(txn, 'posts', postId);
  });
}

Future<void> _deleteRequiredPostRows(
  Transaction txn,
  String table,
  String postId,
) async {
  final exists = await txn.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
    <Object?>[table],
  );
  if (exists.isEmpty) {
    throw StateError(
      'Expected posts cascade table "$table" to exist before deleting post "$postId".',
    );
  }
  await txn.delete(table, where: 'post_id = ?', whereArgs: <Object?>[postId]);
}
