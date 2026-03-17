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
  final hasDeliveryOwnerKind = columns.any(
    (column) => column['name'] == 'delivery_owner_kind',
  );
  final hasDeliveryOwnerId = columns.any(
    (column) => column['name'] == 'delivery_owner_id',
  );
  if (!hasNearbyDistanceM) {
    insertRow.remove('nearby_distance_m');
  }
  if (!hasDeliveryOwnerKind) {
    insertRow.remove('delivery_owner_kind');
  }
  if (!hasDeliveryOwnerId) {
    insertRow.remove('delivery_owner_id');
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
  final columns = await db.rawQuery("PRAGMA table_info(post_recipients)");
  final hasDeliveryOwnerColumns =
      columns.any((column) => column['name'] == 'delivery_owner_kind') &&
      columns.any((column) => column['name'] == 'delivery_owner_id');
  if (!hasDeliveryOwnerColumns) {
    return db.query(
      'post_recipients',
      where: 'post_id = ?',
      whereArgs: <Object?>[postId],
      orderBy: 'recipient_peer_id ASC',
    );
  }
  return db.query(
    'post_recipients',
    where: 'delivery_owner_kind = ? AND delivery_owner_id = ?',
    whereArgs: <Object?>['post', postId],
    orderBy: 'recipient_peer_id ASC',
  );
}

Future<List<Map<String, Object?>>> dbLoadPostPassRecipientDeliveries(
  Database db,
  String passId,
) async {
  final columns = await db.rawQuery("PRAGMA table_info(post_recipients)");
  final hasDeliveryOwnerColumns =
      columns.any((column) => column['name'] == 'delivery_owner_kind') &&
      columns.any((column) => column['name'] == 'delivery_owner_id');
  if (!hasDeliveryOwnerColumns) {
    return const <Map<String, Object?>>[];
  }
  return db.query(
    'post_recipients',
    where: 'delivery_owner_kind = ? AND delivery_owner_id = ?',
    whereArgs: <Object?>['post_pass', passId],
    orderBy: 'recipient_peer_id ASC',
  );
}
