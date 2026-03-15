import 'package:sqflite_sqlcipher/sqflite.dart';

Future<void> dbUpsertPostPinDismissal(
  Database db,
  Map<String, Object?> row,
) async {
  await db.insert(
    'post_pin_dismissals',
    row,
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<List<Map<String, Object?>>> dbLoadPostPinDismissals(Database db) async {
  return db.query(
    'post_pin_dismissals',
    orderBy: 'dismissed_at DESC, post_id DESC',
  );
}

Future<void> dbDeletePostPinDismissal(Database db, String postId) async {
  await db.delete(
    'post_pin_dismissals',
    where: 'post_id = ?',
    whereArgs: <Object?>[postId],
  );
}
