import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Inserts a group member into the database.
Future<void> dbInsertGroupMember(Database db, Map<String, Object?> row) async {
  final groupId = row['group_id'] as String? ?? '';
  final peerId = row['peer_id'] as String? ?? '';

  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_MEMBERS_DB_INSERT_START',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'peerId': peerId.length > 8 ? peerId.substring(0, 8) : peerId,
    },
  );

  try {
    await db.insert(
      'group_members',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MEMBERS_DB_INSERT_SUCCESS',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'peerId': peerId.length > 8 ? peerId.substring(0, 8) : peerId,
      },
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MEMBERS_DB_INSERT_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads all members of a group, ordered by joined_at ASC.
Future<List<Map<String, Object?>>> dbLoadAllGroupMembers(
  Database db,
  String groupId,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_MEMBERS_DB_LOAD_ALL_START',
    details: {'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId},
  );

  try {
    final results = await db.query(
      'group_members',
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'joined_at ASC',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MEMBERS_DB_LOAD_ALL_SUCCESS',
      details: {'count': results.length},
    );

    return results;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MEMBERS_DB_LOAD_ALL_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads a single group member by group ID and peer ID.
Future<Map<String, Object?>?> dbLoadGroupMember(
  Database db,
  String groupId,
  String peerId,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_MEMBERS_DB_LOAD_START',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'peerId': peerId.length > 8 ? peerId.substring(0, 8) : peerId,
    },
  );

  try {
    final results = await db.query(
      'group_members',
      where: 'group_id = ? AND peer_id = ?',
      whereArgs: [groupId, peerId],
      limit: 1,
    );

    if (results.isNotEmpty) {
      emitFlowEvent(
        layer: 'DB',
        event: 'GROUP_MEMBERS_DB_LOAD_FOUND',
        details: {},
      );
      return results.first;
    } else {
      emitFlowEvent(
        layer: 'DB',
        event: 'GROUP_MEMBERS_DB_LOAD_NOT_FOUND',
        details: {},
      );
      return null;
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MEMBERS_DB_LOAD_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Updates the role of a group member.
Future<void> dbUpdateGroupMemberRole(
  Database db,
  String groupId,
  String peerId,
  String role,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_MEMBERS_DB_UPDATE_ROLE_START',
    details: {'role': role},
  );

  try {
    await db.update(
      'group_members',
      {'role': role},
      where: 'group_id = ? AND peer_id = ?',
      whereArgs: [groupId, peerId],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MEMBERS_DB_UPDATE_ROLE_SUCCESS',
      details: {'role': role},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MEMBERS_DB_UPDATE_ROLE_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Deletes a single group member.
Future<void> dbDeleteGroupMember(
  Database db,
  String groupId,
  String peerId,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_MEMBERS_DB_DELETE_START',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'peerId': peerId.length > 8 ? peerId.substring(0, 8) : peerId,
    },
  );

  try {
    await db.delete(
      'group_members',
      where: 'group_id = ? AND peer_id = ?',
      whereArgs: [groupId, peerId],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MEMBERS_DB_DELETE_SUCCESS',
      details: {},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MEMBERS_DB_DELETE_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Returns the count of members in a group.
Future<int> dbCountGroupMembers(Database db, String groupId) async {
  try {
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM group_members WHERE group_id = ?',
      [groupId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  } catch (e) {
    return 0;
  }
}

/// Deletes all members of a group.
Future<void> dbDeleteAllGroupMembers(Database db, String groupId) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_MEMBERS_DB_DELETE_ALL_START',
    details: {'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId},
  );

  try {
    await db.delete(
      'group_members',
      where: 'group_id = ?',
      whereArgs: [groupId],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MEMBERS_DB_DELETE_ALL_SUCCESS',
      details: {},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MEMBERS_DB_DELETE_ALL_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}
