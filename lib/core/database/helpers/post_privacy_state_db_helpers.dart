import 'package:sqflite_sqlcipher/sqflite.dart';

Future<Map<String, Object?>?> dbLoadPostPrivacyState(Database db) async {
  final rows = await db.query(
    'post_privacy_state',
    where: 'id = ?',
    whereArgs: <Object?>[1],
    limit: 1,
  );
  if (rows.isEmpty) {
    return null;
  }
  return rows.first;
}

Future<void> dbUpsertPostPrivacyState(
  Database db,
  Map<String, Object?> row,
) async {
  await db.insert(
    'post_privacy_state',
    row,
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}
