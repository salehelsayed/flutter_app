import 'package:sqflite_sqlcipher/sqflite.dart';

Future<void> dbUpsertPostOrigin(Database db, Map<String, Object?> row) async {
  await db.insert(
    'post_origin',
    row,
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<Map<String, Object?>?> dbLoadPostOrigin(
  Database db,
  String postId,
) async {
  final rows = await db.query(
    'post_origin',
    where: 'post_id = ?',
    whereArgs: <Object?>[postId],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.first;
}
