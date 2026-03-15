import 'package:sqflite_sqlcipher/sqflite.dart';

Future<void> dbUpsertPostPinState(Database db, Map<String, Object?> row) async {
  await db.insert(
    'post_pins',
    row,
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<Map<String, Object?>?> dbLoadPostPinState(
  Database db,
  String postId,
) async {
  final rows = await db.query(
    'post_pins',
    where: 'post_id = ?',
    whereArgs: <Object?>[postId],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.first;
}

Future<List<Map<String, Object?>>> dbLoadActivePostPinStates(
  Database db,
) async {
  return db.query(
    'post_pins',
    where: 'state = ?',
    whereArgs: const <Object?>['active'],
    orderBy: 'effective_at DESC, post_id DESC',
  );
}
