import 'package:sqflite_sqlcipher/sqflite.dart';

Future<void> dbUpsertPostRecipientDelivery(
  Database db,
  Map<String, Object?> row,
) async {
  final insertRow = Map<String, Object?>.from(row);
  final columns = await db.rawQuery("PRAGMA table_info(post_recipients)");
  final hasNearbyDistanceM = columns.any(
    (column) => column['name'] == 'nearby_distance_m',
  );
  if (!hasNearbyDistanceM) {
    insertRow.remove('nearby_distance_m');
  }
  await db.insert(
    'post_recipients',
    insertRow,
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<List<Map<String, Object?>>> dbLoadPostRecipientDeliveries(
  Database db,
  String postId,
) async {
  return db.query(
    'post_recipients',
    where: 'post_id = ?',
    whereArgs: <Object?>[postId],
    orderBy: 'recipient_peer_id ASC',
  );
}
