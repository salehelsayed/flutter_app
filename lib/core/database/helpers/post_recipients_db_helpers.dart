import 'package:sqflite_sqlcipher/sqflite.dart';

import 'post_schema_capabilities.dart';

Future<void> dbUpsertPostRecipientDelivery(
  Database db,
  Map<String, Object?> row,
) async {
  final insertRow = Map<String, Object?>.from(row);
  final capabilities = await loadPostSchemaCapabilities(db);
  if (!capabilities.hasRecipientNearbyDistanceM) {
    insertRow.remove('nearby_distance_m');
  }
  if (!capabilities.hasRecipientDeliveryOwnerKind) {
    insertRow.remove('delivery_owner_kind');
  }
  if (!capabilities.hasRecipientDeliveryOwnerId) {
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
  final capabilities = await loadPostSchemaCapabilities(db);
  if (!capabilities.hasRecipientDeliveryOwnerColumns) {
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
  final capabilities = await loadPostSchemaCapabilities(db);
  if (!capabilities.hasRecipientDeliveryOwnerColumns) {
    return const <Map<String, Object?>>[];
  }
  return db.query(
    'post_recipients',
    where: 'delivery_owner_kind = ? AND delivery_owner_id = ?',
    whereArgs: <Object?>['post_pass', passId],
    orderBy: 'recipient_peer_id ASC',
  );
}
