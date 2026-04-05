import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

Future<void> dbUpsertPendingGroupInvite(
  Database db,
  Map<String, Object?> row,
) async {
  final groupId = row['group_id'] as String? ?? '';

  emitFlowEvent(
    layer: 'DB',
    event: 'PENDING_GROUP_INVITES_DB_UPSERT_START',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );

  try {
    await db.insert(
      'pending_group_invites',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'PENDING_GROUP_INVITES_DB_UPSERT_SUCCESS',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      },
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'PENDING_GROUP_INVITES_DB_UPSERT_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

Future<List<Map<String, Object?>>> dbLoadPendingGroupInvites(
  Database db,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'PENDING_GROUP_INVITES_DB_LOAD_ALL_START',
    details: {},
  );

  try {
    final rows = await db.query(
      'pending_group_invites',
      orderBy: 'received_at DESC, group_id ASC',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'PENDING_GROUP_INVITES_DB_LOAD_ALL_SUCCESS',
      details: {'count': rows.length},
    );
    return rows;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'PENDING_GROUP_INVITES_DB_LOAD_ALL_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

Future<Map<String, Object?>?> dbLoadPendingGroupInvite(
  Database db,
  String groupId,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'PENDING_GROUP_INVITES_DB_LOAD_START',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );

  try {
    final rows = await db.query(
      'pending_group_invites',
      where: 'group_id = ?',
      whereArgs: [groupId],
      limit: 1,
    );

    final row = rows.isEmpty ? null : rows.first;
    emitFlowEvent(
      layer: 'DB',
      event: row == null
          ? 'PENDING_GROUP_INVITES_DB_LOAD_NOT_FOUND'
          : 'PENDING_GROUP_INVITES_DB_LOAD_FOUND',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      },
    );
    return row;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'PENDING_GROUP_INVITES_DB_LOAD_ERROR',
      details: {'groupId': groupId, 'error': e.toString()},
    );
    rethrow;
  }
}

Future<void> dbDeletePendingGroupInvite(Database db, String groupId) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'PENDING_GROUP_INVITES_DB_DELETE_START',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );

  try {
    await db.delete(
      'pending_group_invites',
      where: 'group_id = ?',
      whereArgs: [groupId],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'PENDING_GROUP_INVITES_DB_DELETE_SUCCESS',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      },
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'PENDING_GROUP_INVITES_DB_DELETE_ERROR',
      details: {'groupId': groupId, 'error': e.toString()},
    );
    rethrow;
  }
}

Future<int> dbDeleteExpiredPendingGroupInvites(
  Database db,
  String cutoff,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'PENDING_GROUP_INVITES_DB_DELETE_EXPIRED_START',
    details: {'cutoff': cutoff},
  );

  try {
    final deleted = await db.delete(
      'pending_group_invites',
      where: 'expires_at <= ?',
      whereArgs: [cutoff],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'PENDING_GROUP_INVITES_DB_DELETE_EXPIRED_SUCCESS',
      details: {'deletedCount': deleted},
    );
    return deleted;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'PENDING_GROUP_INVITES_DB_DELETE_EXPIRED_ERROR',
      details: {'cutoff': cutoff, 'error': e.toString()},
    );
    rethrow;
  }
}
