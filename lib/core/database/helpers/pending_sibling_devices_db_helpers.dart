import 'package:sqflite_sqlcipher/sqflite.dart';

/// DB helpers for the R2 pending-sibling-device store (await-user-decision).
Future<void> dbUpsertPendingSiblingDevice(
  Database db,
  Map<String, Object?> row,
) async {
  await db.insert(
    'pending_sibling_devices',
    row,
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<List<Map<String, Object?>>> dbLoadPendingSiblingDevicesForGroup(
  Database db,
  String groupId,
) {
  return db.query(
    'pending_sibling_devices',
    where: 'group_id = ?',
    whereArgs: [groupId],
    orderBy: 'announced_at DESC',
  );
}

Future<Map<String, Object?>?> dbLoadPendingSiblingDevice(
  Database db,
  String groupId,
  String memberPeerId,
  String deviceId,
) async {
  final rows = await db.query(
    'pending_sibling_devices',
    where: 'group_id = ? AND member_peer_id = ? AND device_id = ?',
    whereArgs: [groupId, memberPeerId, deviceId],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.first;
}

Future<void> dbDeletePendingSiblingDevice(
  Database db,
  String groupId,
  String memberPeerId,
  String deviceId,
) async {
  await db.delete(
    'pending_sibling_devices',
    where: 'group_id = ? AND member_peer_id = ? AND device_id = ?',
    whereArgs: [groupId, memberPeerId, deviceId],
  );
}
