import 'package:sqflite_sqlcipher/sqflite.dart';

import '../db_write_transaction.dart';

Future<void> dbReplacePostMediaUploadRecoveryItems(
  Database db,
  String postId,
  List<Map<String, Object?>> rows,
) async {
  await dbWriteTransaction(db, (txn) async {
    await txn.delete(
      'post_media_upload_recovery',
      where: 'post_id = ?',
      whereArgs: <Object?>[postId],
    );
    for (final row in rows) {
      await txn.insert(
        'post_media_upload_recovery',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  });
}

Future<List<Map<String, Object?>>> dbLoadPostMediaUploadRecoveryItems(
  Database db,
  String postId,
) async {
  return db.query(
    'post_media_upload_recovery',
    where: 'post_id = ?',
    whereArgs: <Object?>[postId],
    orderBy: 'position ASC, created_at ASC',
  );
}

Future<List<Map<String, Object?>>> dbLoadPendingPostMediaUploadPosts(
  Database db,
) async {
  return db.rawQuery('''
      SELECT p.*
      FROM posts p
      WHERE p.is_incoming = 0
        AND EXISTS (
          SELECT 1
          FROM post_media_upload_recovery r
          WHERE r.post_id = p.post_id
        )
      ORDER BY p.post_created_at ASC, p.post_id ASC
    ''');
}
