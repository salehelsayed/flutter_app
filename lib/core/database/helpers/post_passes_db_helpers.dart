import 'package:sqflite_sqlcipher/sqflite.dart';

import 'post_schema_capabilities.dart';

Future<void> dbUpsertPostPass(Database db, Map<String, Object?> row) async {
  final insertRow = Map<String, Object?>.from(row);
  final capabilities = await loadPostSchemaCapabilities(db);
  if (!capabilities.hasPassDeliveryStatus) {
    insertRow.remove('delivery_status');
  }
  if (!capabilities.hasPassInnerPayloadJson) {
    insertRow.remove('inner_payload_json');
  }
  if (!capabilities.hasPassRecipientCount) {
    insertRow.remove('recipient_count');
  }
  await db.insert(
    'post_passes',
    insertRow,
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<Map<String, Object?>?> dbLoadPostPass(Database db, String passId) async {
  final rows = await db.query(
    'post_passes',
    where: 'pass_id = ?',
    whereArgs: <Object?>[passId],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.first;
}

Future<List<Map<String, Object?>>> dbLoadPostPasses(
  Database db,
  String postId,
) async {
  return db.query(
    'post_passes',
    where: 'post_id = ?',
    whereArgs: <Object?>[postId],
    orderBy: 'passed_at DESC, pass_id DESC',
  );
}

Future<int> dbCountPostPasses(Database db, String postId) async {
  final rows = await db.rawQuery(
    '''
      SELECT COUNT(*) AS share_count
      FROM post_passes
      WHERE post_id = ?
    ''',
    <Object?>[postId],
  );
  return (rows.first['share_count'] as num?)?.toInt() ?? 0;
}

Future<List<Map<String, Object?>>> dbLoadPostPassCounts(
  Database db,
  List<String> postIds,
) async {
  final placeholders = List<String>.filled(postIds.length, '?').join(', ');
  return db.rawQuery('''
      SELECT post_id, COUNT(*) AS share_count
      FROM post_passes
      WHERE post_id IN ($placeholders)
      GROUP BY post_id
    ''', postIds);
}

Future<List<Map<String, Object?>>> dbLoadRetryableOutgoingPostPasses(
  Database db,
) async {
  final capabilities = await loadPostSchemaCapabilities(db);
  if (!capabilities.hasPassDeliveryStatus) {
    return db.query(
      'post_passes',
      where: 'is_incoming = ?',
      whereArgs: const <Object?>[0],
      orderBy: 'passed_at DESC, pass_id DESC',
    );
  }
  return db.query(
    'post_passes',
    where: 'is_incoming = ? AND delivery_status IN (?, ?, ?)',
    whereArgs: const <Object?>[0, 'sending', 'partial', 'failed'],
    orderBy: 'passed_at DESC, pass_id DESC',
  );
}

Future<void> dbSavePassAvatarSnapshot(
  Database db,
  String postId,
  String authorPeerId,
  List<int> avatarBlob,
  String createdAt,
) async {
  await db.insert('post_pass_avatar_snapshots', <String, Object?>{
    'post_id': postId,
    'author_peer_id': authorPeerId,
    'avatar_blob': avatarBlob,
    'created_at': createdAt,
  }, conflictAlgorithm: ConflictAlgorithm.ignore);
}

Future<List<int>?> dbLoadPassAvatarSnapshot(Database db, String postId) async {
  final rows = await db.query(
    'post_pass_avatar_snapshots',
    columns: const ['avatar_blob'],
    where: 'post_id = ?',
    whereArgs: <Object?>[postId],
    limit: 1,
  );
  if (rows.isEmpty) {
    return null;
  }
  return rows.first['avatar_blob'] as List<int>?;
}

Future<Map<String, List<int>>> dbLoadPassAvatarSnapshotsForPosts(
  Database db,
  List<String> postIds,
) async {
  if (postIds.isEmpty) {
    return const <String, List<int>>{};
  }
  final placeholders = List<String>.filled(postIds.length, '?').join(', ');
  final rows = await db.rawQuery(
    'SELECT post_id, avatar_blob FROM post_pass_avatar_snapshots WHERE post_id IN ($placeholders)',
    postIds,
  );
  return <String, List<int>>{
    for (final row in rows)
      if (row['post_id'] is String && row['avatar_blob'] is List<int>)
        row['post_id'] as String: row['avatar_blob'] as List<int>,
  };
}
