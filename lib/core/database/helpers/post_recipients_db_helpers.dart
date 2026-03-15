import 'package:sqflite_sqlcipher/sqflite.dart';

Future<void> dbUpsertPostRecipientDelivery(
  Database db,
  Map<String, Object?> row,
) async {
  await db.insert(
    'post_recipients',
    row,
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
