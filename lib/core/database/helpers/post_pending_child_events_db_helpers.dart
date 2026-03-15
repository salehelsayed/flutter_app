import 'package:sqflite_sqlcipher/sqflite.dart';

Future<void> dbInsertPendingPostChildEvent(
  Database db,
  Map<String, Object?> row,
) async {
  await db.insert(
    'post_pending_child_events',
    row,
    conflictAlgorithm: ConflictAlgorithm.ignore,
  );
}

Future<List<Map<String, Object?>>> dbLoadPendingPostChildEvents(
  Database db,
  String postId,
) async {
  return db.query(
    'post_pending_child_events',
    where: 'post_id = ?',
    whereArgs: <Object?>[postId],
    orderBy: 'created_at ASC, event_id ASC',
  );
}

Future<void> dbDeletePendingPostChildEvent(Database db, String eventId) async {
  await db.delete(
    'post_pending_child_events',
    where: 'event_id = ?',
    whereArgs: <Object?>[eventId],
  );
}
