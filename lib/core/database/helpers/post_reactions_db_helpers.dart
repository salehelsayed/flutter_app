import 'package:sqflite_sqlcipher/sqflite.dart';

Future<void> dbUpsertPostReaction(Database db, Map<String, Object?> row) async {
  await db.insert(
    'post_reactions',
    row,
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<Map<String, Object?>?> dbLoadPostReaction(
  Database db,
  String reactionId,
) async {
  final rows = await db.query(
    'post_reactions',
    where: 'reaction_id = ?',
    whereArgs: <Object?>[reactionId],
    limit: 1,
  );
  if (rows.isEmpty) {
    return null;
  }
  return rows.first;
}

Future<List<Map<String, Object?>>> dbLoadPostReactions(
  Database db,
  String postId,
) async {
  return db.query(
    'post_reactions',
    where: 'post_id = ?',
    whereArgs: <Object?>[postId],
    orderBy: 'reacted_at ASC, reaction_id ASC',
  );
}
