import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

Future<void> dbUpsertPostMediaAttachment(
  Database db,
  Map<String, Object?> row,
) async {
  final mediaId = row['media_id'] as String? ?? '';
  emitFlowEvent(
    layer: 'DB',
    event: 'POST_MEDIA_DB_UPSERT_START',
    details: {'mediaId': mediaId},
  );
  try {
    await db.insert(
      'post_media_attachments',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    emitFlowEvent(
      layer: 'DB',
      event: 'POST_MEDIA_DB_UPSERT_SUCCESS',
      details: {'mediaId': mediaId},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'POST_MEDIA_DB_UPSERT_ERROR',
      details: {'mediaId': mediaId, 'error': e.toString()},
    );
    rethrow;
  }
}

Future<List<Map<String, Object?>>> dbLoadPostMediaAttachments(
  Database db,
  String postId,
) async {
  return db.query(
    'post_media_attachments',
    where: 'post_id = ?',
    whereArgs: [postId],
    orderBy: 'position ASC, created_at ASC, media_id ASC',
  );
}

Future<List<Map<String, Object?>>> dbLoadPostMediaAttachmentsForPosts(
  Database db,
  List<String> postIds,
) async {
  if (postIds.isEmpty) {
    return const <Map<String, Object?>>[];
  }
  final placeholders = List<String>.filled(postIds.length, '?').join(',');
  return db.rawQuery('''
      SELECT *
      FROM post_media_attachments
      WHERE post_id IN ($placeholders)
      ORDER BY post_id ASC, position ASC, created_at ASC, media_id ASC
    ''', postIds);
}

Future<void> dbUpdatePostMediaLocalPath(
  Database db,
  String mediaId,
  String localPath,
) async {
  await db.update(
    'post_media_attachments',
    <String, Object?>{'local_path': localPath, 'download_status': 'done'},
    where: 'media_id = ?',
    whereArgs: [mediaId],
  );
}

Future<void> dbUpdatePostMediaDownloadStatus(
  Database db,
  String mediaId,
  String downloadStatus,
) async {
  await db.update(
    'post_media_attachments',
    <String, Object?>{'download_status': downloadStatus},
    where: 'media_id = ?',
    whereArgs: [mediaId],
  );
}

Future<void> dbReplacePostMediaAttachments(
  Database db,
  String postId,
  List<Map<String, Object?>> rows,
) async {
  await db.transaction((txn) async {
    await txn.delete(
      'post_media_attachments',
      where: 'post_id = ?',
      whereArgs: <Object?>[postId],
    );
    for (final row in rows) {
      await txn.insert(
        'post_media_attachments',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  });
}
