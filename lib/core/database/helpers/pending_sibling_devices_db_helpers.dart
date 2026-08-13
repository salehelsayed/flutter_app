import 'package:sqflite_sqlcipher/sqflite.dart';

import 'group_parent_write_guard.dart';

/// DB helpers for the R2 pending-sibling-device store (await-user-decision).
Future<void> dbUpsertPendingSiblingDevice(
  Database db,
  Map<String, Object?> row,
) => dbUpsertPendingSiblingDeviceWithExecutor(db, row);

/// Transaction-body variant used when sibling intent must commit beside other
/// group authority in one outer SQL transaction.
Future<void> dbUpsertPendingSiblingDeviceWithExecutor(
  DatabaseExecutor db,
  Map<String, Object?> row,
) async {
  await dbInsertOrdinaryGroupOwnedRow(
    db,
    table: 'pending_sibling_devices',
    row: row,
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<List<Map<String, Object?>>> dbLoadPendingSiblingDevicesForGroup(
  Database db,
  String groupId,
) async {
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'pending_sibling_devices.group_id',
  );
  return db.rawQuery(
    'SELECT * FROM pending_sibling_devices '
    'WHERE group_id = ? AND $parent ORDER BY announced_at DESC',
    [groupId],
  );
}

Future<Map<String, Object?>?> dbLoadPendingSiblingDevice(
  Database db,
  String groupId,
  String memberPeerId,
  String deviceId,
) async {
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'pending_sibling_devices.group_id',
  );
  final rows = await db.rawQuery(
    'SELECT * FROM pending_sibling_devices '
    'WHERE group_id = ? AND member_peer_id = ? AND device_id = ? '
    'AND $parent LIMIT 1',
    [groupId, memberPeerId, deviceId],
  );
  return rows.isEmpty ? null : rows.first;
}

Future<void> dbDeletePendingSiblingDevice(
  Database db,
  String groupId,
  String memberPeerId,
  String deviceId,
) => dbDeletePendingSiblingDeviceWithExecutor(
  db,
  groupId,
  memberPeerId,
  deviceId,
);

Future<void> dbDeletePendingSiblingDeviceWithExecutor(
  DatabaseExecutor db,
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
