import 'package:sqflite_sqlcipher/sqflite.dart';

Future<Map<String, Object?>?> dbLoadPostLocationPresence(
  Database db,
  String peerId,
) async {
  final rows = await db.query(
    'post_location_presence',
    where: 'peer_id = ?',
    whereArgs: <Object?>[peerId],
    limit: 1,
  );
  if (rows.isEmpty) {
    return null;
  }
  return rows.first;
}

Future<List<Map<String, Object?>>> dbLoadAllPostLocationPresence(
  Database db,
) async {
  return db.query('post_location_presence', orderBy: 'updated_at DESC');
}

Future<void> dbUpsertPostLocationPresence(
  Database db,
  Map<String, Object?> row,
) async {
  await db.insert(
    'post_location_presence',
    row,
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}
