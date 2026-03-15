import 'package:sqflite_sqlcipher/sqflite.dart';

Future<void> dbUpsertPostCommentReaction(
  Database db,
  Map<String, Object?> row,
) async {
  await db.insert(
    'post_comment_reactions',
    row,
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<Map<String, Object?>?> dbLoadPostCommentReaction(
  Database db,
  String reactionId,
) async {
  final rows = await db.query(
    'post_comment_reactions',
    where: 'reaction_id = ?',
    whereArgs: <Object?>[reactionId],
    limit: 1,
  );
  if (rows.isEmpty) {
    return null;
  }
  return rows.first;
}

Future<List<Map<String, Object?>>> dbLoadPostCommentReactions(
  Database db,
  String commentId,
) async {
  return db.query(
    'post_comment_reactions',
    where: 'comment_id = ?',
    whereArgs: <Object?>[commentId],
    orderBy: 'reacted_at ASC, reaction_id ASC',
  );
}
