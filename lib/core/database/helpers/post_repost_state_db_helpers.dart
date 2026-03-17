import 'package:sqflite_sqlcipher/sqflite.dart';

Future<void> dbUpsertPostRepostEngagementParticipant(
  Database db,
  Map<String, Object?> row,
) async {
  await db.insert(
    'post_repost_engagement_participants',
    row,
    conflictAlgorithm: ConflictAlgorithm.ignore,
  );
}

Future<List<Map<String, Object?>>> dbLoadPostRepostEngagementParticipants(
  Database db,
  String postId,
) async {
  return db.query(
    'post_repost_engagement_participants',
    where: 'post_id = ?',
    whereArgs: <Object?>[postId],
    orderBy: 'participant_peer_id ASC',
  );
}

Future<void> dbUpsertPostRepostHeartBaselinePeer(
  Database db,
  Map<String, Object?> row,
) async {
  await db.insert(
    'post_repost_heart_baseline_peers',
    row,
    conflictAlgorithm: ConflictAlgorithm.ignore,
  );
}

Future<List<Map<String, Object?>>> dbLoadPostRepostHeartBaselinePeers(
  Database db,
  String postId,
) async {
  return db.query(
    'post_repost_heart_baseline_peers',
    where: 'post_id = ?',
    whereArgs: <Object?>[postId],
    orderBy: 'sender_peer_id ASC',
  );
}

Future<List<Map<String, Object?>>> dbLoadPostRepostHeartBaselinePeersForPosts(
  Database db,
  List<String> postIds,
) async {
  if (postIds.isEmpty) {
    return const <Map<String, Object?>>[];
  }
  final placeholders = List<String>.filled(postIds.length, '?').join(', ');
  return db.rawQuery('''
      SELECT post_id, sender_peer_id
      FROM post_repost_heart_baseline_peers
      WHERE post_id IN ($placeholders)
      ORDER BY post_id ASC, sender_peer_id ASC
    ''', postIds);
}

Future<void> dbInsertPostRepostProjectionState(
  Database db,
  Map<String, Object?> row,
) async {
  await db.insert(
    'post_repost_projection_state',
    row,
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<Map<String, Object?>?> dbLoadPostRepostProjectionState(
  Database db,
  String postId,
) async {
  final rows = await db.query(
    'post_repost_projection_state',
    where: 'post_id = ?',
    whereArgs: <Object?>[postId],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.first;
}

Future<List<Map<String, Object?>>> dbLoadPostRepostProjectionStates(
  Database db,
  List<String> postIds,
) async {
  if (postIds.isEmpty) {
    return const <Map<String, Object?>>[];
  }
  final placeholders = List<String>.filled(postIds.length, '?').join(', ');
  return db.rawQuery('''
      SELECT post_id, repost_total_baseline
      FROM post_repost_projection_state
      WHERE post_id IN ($placeholders)
    ''', postIds);
}
