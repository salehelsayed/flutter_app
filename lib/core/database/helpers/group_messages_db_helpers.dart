import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Inserts a group message into the database.
Future<void> dbInsertGroupMessage(Database db, Map<String, Object?> row) async {
  final id = row['id'] as String? ?? '';

  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_MESSAGES_DB_INSERT_START',
    details: {'id': id.length > 8 ? id.substring(0, 8) : id},
  );

  try {
    await db.insert(
      'group_messages',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MESSAGES_DB_INSERT_SUCCESS',
      details: {'id': id.length > 8 ? id.substring(0, 8) : id},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MESSAGES_DB_INSERT_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads a page of group messages, ordered by timestamp ASC.
///
/// Returns at most [limit] messages starting at [offset].
Future<List<Map<String, Object?>>> dbLoadGroupMessagesPage(
  Database db,
  String groupId, {
  int limit = 50,
  int offset = 0,
}) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_MESSAGES_DB_LOAD_PAGE_START',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'limit': limit,
      'offset': offset,
    },
  );

  try {
    // Get the most recent messages (DESC), then reverse to ASC
    final results = await db.query(
      'group_messages',
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'timestamp DESC',
      limit: limit,
      offset: offset,
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MESSAGES_DB_LOAD_PAGE_SUCCESS',
      details: {'count': results.length},
    );

    return results.reversed.toList();
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MESSAGES_DB_LOAD_PAGE_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads all messages for a group, ordered by timestamp ASC.
Future<List<Map<String, Object?>>> dbLoadAllGroupMessages(
  Database db,
  String groupId,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_MESSAGES_DB_LOAD_ALL_START',
    details: {'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId},
  );

  try {
    final results = await db.query(
      'group_messages',
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'timestamp ASC',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MESSAGES_DB_LOAD_ALL_SUCCESS',
      details: {'count': results.length},
    );

    return results;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MESSAGES_DB_LOAD_ALL_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads the latest message for a group (most recent by timestamp).
Future<Map<String, Object?>?> dbLoadLatestGroupMessage(
  Database db,
  String groupId,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_MESSAGES_DB_LOAD_LATEST_START',
    details: {'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId},
  );

  try {
    final results = await db.query(
      'group_messages',
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'timestamp DESC',
      limit: 1,
    );

    if (results.isNotEmpty) {
      emitFlowEvent(
        layer: 'DB',
        event: 'GROUP_MESSAGES_DB_LOAD_LATEST_FOUND',
        details: {},
      );
      return results.first;
    } else {
      emitFlowEvent(
        layer: 'DB',
        event: 'GROUP_MESSAGES_DB_LOAD_LATEST_NOT_FOUND',
        details: {},
      );
      return null;
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MESSAGES_DB_LOAD_LATEST_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads a single group message by ID.
Future<Map<String, Object?>?> dbLoadGroupMessage(Database db, String id) async {
  try {
    final results = await db.query(
      'group_messages',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  } catch (e) {
    return null;
  }
}

/// Updates the status of a group message by ID.
Future<void> dbUpdateGroupMessageStatus(
  Database db,
  String id,
  String status,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_MESSAGES_DB_UPDATE_STATUS_START',
    details: {'id': id.length > 8 ? id.substring(0, 8) : id, 'status': status},
  );

  try {
    await db.update(
      'group_messages',
      {'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MESSAGES_DB_UPDATE_STATUS_SUCCESS',
      details: {'id': id.length > 8 ? id.substring(0, 8) : id},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MESSAGES_DB_UPDATE_STATUS_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Returns the total number of messages in a group.
Future<int> dbCountGroupMessages(Database db, String groupId) async {
  try {
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM group_messages WHERE group_id = ?',
      [groupId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  } catch (e) {
    return 0;
  }
}

/// Returns the number of unread incoming messages in a group.
Future<int> dbCountUnreadGroupMessages(Database db, String groupId) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_MESSAGES_DB_COUNT_UNREAD_START',
    details: {'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId},
  );

  try {
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM group_messages WHERE group_id = ? AND is_incoming = 1 AND read_at IS NULL',
      [groupId],
    );
    final count = Sqflite.firstIntValue(result) ?? 0;

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MESSAGES_DB_COUNT_UNREAD_SUCCESS',
      details: {'count': count},
    );

    return count;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MESSAGES_DB_COUNT_UNREAD_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Returns the total number of unread incoming messages across all groups.
Future<int> dbCountTotalUnreadGroupMessages(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_MESSAGES_DB_COUNT_TOTAL_UNREAD_START',
    details: {},
  );

  try {
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM group_messages WHERE is_incoming = 1 AND read_at IS NULL',
    );
    final count = Sqflite.firstIntValue(result) ?? 0;

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MESSAGES_DB_COUNT_TOTAL_UNREAD_SUCCESS',
      details: {'count': count},
    );

    return count;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MESSAGES_DB_COUNT_TOTAL_UNREAD_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Marks all unread incoming messages for a group as read.
Future<int> dbMarkGroupMessagesAsRead(Database db, String groupId) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_MESSAGES_DB_MARK_READ_START',
    details: {'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId},
  );

  try {
    final now = DateTime.now().toUtc().toIso8601String();
    final count = await db.rawUpdate(
      'UPDATE group_messages SET read_at = ? WHERE group_id = ? AND is_incoming = 1 AND read_at IS NULL',
      [now, groupId],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MESSAGES_DB_MARK_READ_SUCCESS',
      details: {'count': count},
    );

    return count;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MESSAGES_DB_MARK_READ_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Returns true if a group message with the same content already exists.
Future<bool> dbExistsGroupMessageByContent(
  Database db,
  String groupId,
  String senderPeerId,
  String text,
  String timestamp,
) async {
  final result = await db.query(
    'group_messages',
    where:
        'group_id = ? AND sender_peer_id = ? AND text = ? AND timestamp = ?',
    whereArgs: [groupId, senderPeerId, text, timestamp],
    limit: 1,
  );
  return result.isNotEmpty;
}

/// Deletes a single group message by ID.
Future<void> dbDeleteGroupMessage(Database db, String id) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_MESSAGES_DB_DELETE_START',
    details: {'id': id.length > 8 ? id.substring(0, 8) : id},
  );

  try {
    await db.delete(
      'group_messages',
      where: 'id = ?',
      whereArgs: [id],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MESSAGES_DB_DELETE_SUCCESS',
      details: {'id': id.length > 8 ? id.substring(0, 8) : id},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MESSAGES_DB_DELETE_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}
