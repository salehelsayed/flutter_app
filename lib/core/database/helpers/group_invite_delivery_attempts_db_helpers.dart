import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

String _short(String value, {int max = 10}) =>
    value.length > max ? value.substring(0, max) : value;

Future<void> dbUpsertGroupInviteDeliveryAttempt(
  Database db,
  Map<String, Object?> row,
) async {
  final groupId = row['group_id'] as String? ?? '';
  final peerId = row['peer_id'] as String? ?? '';

  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_INVITE_DELIVERY_ATTEMPTS_DB_UPSERT_START',
    details: {'groupId': _short(groupId, max: 8), 'peerId': _short(peerId)},
  );

  try {
    await db.insert(
      'group_invite_delivery_attempts',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_INVITE_DELIVERY_ATTEMPTS_DB_UPSERT_SUCCESS',
      details: {'groupId': _short(groupId, max: 8), 'peerId': _short(peerId)},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_INVITE_DELIVERY_ATTEMPTS_DB_UPSERT_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

Future<Map<String, Object?>?> dbLoadGroupInviteDeliveryAttempt(
  Database db, {
  required String groupId,
  required String peerId,
}) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_INVITE_DELIVERY_ATTEMPTS_DB_LOAD_START',
    details: {'groupId': _short(groupId, max: 8), 'peerId': _short(peerId)},
  );

  try {
    final rows = await db.query(
      'group_invite_delivery_attempts',
      where: 'group_id = ? AND peer_id = ?',
      whereArgs: [groupId, peerId],
      limit: 1,
    );
    final row = rows.isEmpty ? null : rows.first;
    emitFlowEvent(
      layer: 'DB',
      event: row == null
          ? 'GROUP_INVITE_DELIVERY_ATTEMPTS_DB_LOAD_NOT_FOUND'
          : 'GROUP_INVITE_DELIVERY_ATTEMPTS_DB_LOAD_FOUND',
      details: {'groupId': _short(groupId, max: 8), 'peerId': _short(peerId)},
    );
    return row;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_INVITE_DELIVERY_ATTEMPTS_DB_LOAD_ERROR',
      details: {'groupId': groupId, 'peerId': peerId, 'error': e.toString()},
    );
    rethrow;
  }
}

Future<List<Map<String, Object?>>> dbLoadGroupInviteDeliveryAttemptsForGroup(
  Database db,
  String groupId,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_INVITE_DELIVERY_ATTEMPTS_DB_LOAD_GROUP_START',
    details: {'groupId': _short(groupId, max: 8)},
  );

  try {
    final rows = await db.query(
      'group_invite_delivery_attempts',
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'peer_id ASC',
    );
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_INVITE_DELIVERY_ATTEMPTS_DB_LOAD_GROUP_SUCCESS',
      details: {'groupId': _short(groupId, max: 8), 'count': rows.length},
    );
    return rows;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_INVITE_DELIVERY_ATTEMPTS_DB_LOAD_GROUP_ERROR',
      details: {'groupId': groupId, 'error': e.toString()},
    );
    rethrow;
  }
}

Future<void> dbUpdateGroupInviteDeliveryAttemptStatus(
  Database db, {
  required String groupId,
  required String peerId,
  required String status,
  required String updatedAt,
}) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_INVITE_DELIVERY_ATTEMPTS_DB_UPDATE_STATUS_START',
    details: {
      'groupId': _short(groupId, max: 8),
      'peerId': _short(peerId),
      'status': status,
    },
  );

  try {
    await db.update(
      'group_invite_delivery_attempts',
      {'status': status, 'updated_at': updatedAt, 'last_error': null},
      where: 'group_id = ? AND peer_id = ?',
      whereArgs: [groupId, peerId],
    );
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_INVITE_DELIVERY_ATTEMPTS_DB_UPDATE_STATUS_SUCCESS',
      details: {
        'groupId': _short(groupId, max: 8),
        'peerId': _short(peerId),
        'status': status,
      },
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_INVITE_DELIVERY_ATTEMPTS_DB_UPDATE_STATUS_ERROR',
      details: {
        'groupId': groupId,
        'peerId': peerId,
        'status': status,
        'error': e.toString(),
      },
    );
    rethrow;
  }
}

Future<int> dbDeleteGroupInviteDeliveryAttempt(
  Database db, {
  required String groupId,
  required String peerId,
}) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_INVITE_DELIVERY_ATTEMPTS_DB_DELETE_START',
    details: {'groupId': _short(groupId, max: 8), 'peerId': _short(peerId)},
  );

  try {
    final deleted = await db.delete(
      'group_invite_delivery_attempts',
      where: 'group_id = ? AND peer_id = ?',
      whereArgs: [groupId, peerId],
    );
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_INVITE_DELIVERY_ATTEMPTS_DB_DELETE_SUCCESS',
      details: {'deletedCount': deleted},
    );
    return deleted;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_INVITE_DELIVERY_ATTEMPTS_DB_DELETE_ERROR',
      details: {'groupId': groupId, 'peerId': peerId, 'error': e.toString()},
    );
    rethrow;
  }
}

Future<int> dbDeleteGroupInviteDeliveryAttemptsForGroup(
  Database db,
  String groupId,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_INVITE_DELIVERY_ATTEMPTS_DB_DELETE_GROUP_START',
    details: {'groupId': _short(groupId, max: 8)},
  );

  try {
    final deleted = await db.delete(
      'group_invite_delivery_attempts',
      where: 'group_id = ?',
      whereArgs: [groupId],
    );
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_INVITE_DELIVERY_ATTEMPTS_DB_DELETE_GROUP_SUCCESS',
      details: {'groupId': _short(groupId, max: 8), 'deletedCount': deleted},
    );
    return deleted;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_INVITE_DELIVERY_ATTEMPTS_DB_DELETE_GROUP_ERROR',
      details: {'groupId': groupId, 'error': e.toString()},
    );
    rethrow;
  }
}
