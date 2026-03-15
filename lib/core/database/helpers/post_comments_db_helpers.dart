import 'package:sqflite_sqlcipher/sqflite.dart';

Future<void> dbInsertPostComment(Database db, Map<String, Object?> row) async {
  await db.insert(
    'post_comments',
    row,
    conflictAlgorithm: ConflictAlgorithm.ignore,
  );
}

Future<Map<String, Object?>?> dbLoadPostComment(
  Database db,
  String commentId,
) async {
  final rows = await db.query(
    'post_comments',
    where: 'comment_id = ?',
    whereArgs: <Object?>[commentId],
    limit: 1,
  );
  if (rows.isEmpty) {
    return null;
  }
  return rows.first;
}

Future<List<Map<String, Object?>>> dbLoadPostComments(
  Database db,
  String postId,
) async {
  return db.query(
    'post_comments',
    where: 'post_id = ?',
    whereArgs: <Object?>[postId],
    orderBy: 'commented_at ASC, comment_id ASC',
  );
}
