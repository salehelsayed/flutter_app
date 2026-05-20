import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';
import 'group_message_local_deletions_db_helpers.dart';

const _groupRemovalCutoffMessageIdLike = 'sys-member_removed_cutoff:%';

/// Inserts a group message into the database.
Future<void> dbInsertGroupMessage(
  DatabaseExecutor db,
  Map<String, Object?> row,
) async {
  final id = row['id'] as String? ?? '';

  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_MESSAGES_DB_INSERT_START',
    details: {'id': id.length > 8 ? id.substring(0, 8) : id},
  );

  try {
    if (await dbIsGroupMessageLocallyDeleted(db, id)) {
      emitFlowEvent(
        layer: 'DB',
        event: 'GROUP_MESSAGES_DB_INSERT_SKIPPED_LOCAL_DELETION',
        details: {'id': id.length > 8 ? id.substring(0, 8) : id},
      );
      return;
    }

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

/// Loads a page of group messages, ordered by timestamp ASC, id ASC.
///
/// Returns at most [limit] messages starting at [offset].
Future<List<Map<String, Object?>>> dbLoadGroupMessagesPage(
  DatabaseExecutor db,
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
    // Get the most recent messages (DESC), then reverse to ASC.
    final results = await db.query(
      'group_messages',
      where: 'group_id = ? AND id NOT LIKE ?',
      whereArgs: [groupId, _groupRemovalCutoffMessageIdLike],
      orderBy: 'timestamp DESC, id DESC',
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

/// Loads all messages for a group, ordered by timestamp ASC, id ASC.
Future<List<Map<String, Object?>>> dbLoadAllGroupMessages(
  DatabaseExecutor db,
  String groupId,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_MESSAGES_DB_LOAD_ALL_START',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );

  try {
    final results = await db.query(
      'group_messages',
      where: 'group_id = ? AND id NOT LIKE ?',
      whereArgs: [groupId, _groupRemovalCutoffMessageIdLike],
      orderBy: 'timestamp ASC, id ASC',
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

/// Loads the timestamp of the latest synthetic `member_removed` message for a
/// removed sender in a group.
Future<String?> dbLoadLatestGroupRemovalTimestampForSender(
  DatabaseExecutor db,
  String groupId,
  String senderPeerId,
) async {
  final rows = await db.query(
    'group_messages',
    columns: ['timestamp'],
    where: 'group_id = ? AND (id LIKE ? OR id LIKE ?)',
    whereArgs: [
      groupId,
      'sys-member_removed:$groupId:$senderPeerId:%',
      'sys-member_removed_cutoff:$groupId:$senderPeerId:%',
    ],
    orderBy: 'timestamp DESC, id DESC',
    limit: 1,
  );
  if (rows.isEmpty) return null;
  return rows.first['timestamp'] as String?;
}

/// Loads the latest message for a group (most recent by timestamp, then id).
Future<Map<String, Object?>?> dbLoadLatestGroupMessage(
  DatabaseExecutor db,
  String groupId,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_MESSAGES_DB_LOAD_LATEST_START',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );

  try {
    final results = await db.query(
      'group_messages',
      where: 'group_id = ? AND id NOT LIKE ?',
      whereArgs: [groupId, _groupRemovalCutoffMessageIdLike],
      orderBy: 'timestamp DESC, id DESC',
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

/// Loads conversation summaries for the provided groups.
///
/// Returns one row per group that has at least one message. Groups with no
/// messages are omitted so callers can provide their own zero-value fallback.
Future<List<Map<String, Object?>>> dbLoadGroupThreadSummaries(
  DatabaseExecutor db,
  List<String> groupIds,
) async {
  if (groupIds.isEmpty) return const [];

  final placeholders = List.filled(groupIds.length, '?').join(', ');
  final results = await db.rawQuery('''
    SELECT
      summary.group_id,
      summary.unread_count,
      latest.id AS latest_id,
      latest.group_id AS latest_group_id,
      latest.sender_peer_id AS latest_sender_peer_id,
      latest.transport_peer_id AS latest_transport_peer_id,
      latest.sender_username AS latest_sender_username,
      latest.text AS latest_text,
      latest.timestamp AS latest_timestamp,
      latest.quoted_message_id AS latest_quoted_message_id,
      latest.key_generation AS latest_key_generation,
      latest.status AS latest_status,
      latest.is_incoming AS latest_is_incoming,
      latest.read_at AS latest_read_at,
      latest.created_at AS latest_created_at
    FROM (
      SELECT
        group_id,
        SUM(
          CASE
            WHEN is_incoming = 1 AND read_at IS NULL THEN 1
            ELSE 0
          END
        ) AS unread_count
      FROM group_messages
      WHERE group_id IN ($placeholders)
        AND id NOT LIKE '$_groupRemovalCutoffMessageIdLike'
      GROUP BY group_id
    ) summary
    LEFT JOIN group_messages latest
      ON latest.id = (
        SELECT inner_latest.id
        FROM group_messages inner_latest
        WHERE inner_latest.group_id = summary.group_id
          AND inner_latest.id NOT LIKE '$_groupRemovalCutoffMessageIdLike'
        ORDER BY inner_latest.timestamp DESC,
                 inner_latest.id DESC
        LIMIT 1
      )
    ''', groupIds);
  return results;
}

/// Loads a single group message by ID.
Future<Map<String, Object?>?> dbLoadGroupMessage(
  DatabaseExecutor db,
  String id,
) async {
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
  DatabaseExecutor db,
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
Future<int> dbCountGroupMessages(DatabaseExecutor db, String groupId) async {
  try {
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM group_messages WHERE group_id = ? AND id NOT LIKE ?',
      [groupId, _groupRemovalCutoffMessageIdLike],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  } catch (e) {
    return 0;
  }
}

/// Returns the number of unread incoming messages in a group.
Future<int> dbCountUnreadGroupMessages(
  DatabaseExecutor db,
  String groupId,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_MESSAGES_DB_COUNT_UNREAD_START',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );

  try {
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM group_messages WHERE group_id = ? AND is_incoming = 1 AND read_at IS NULL AND id NOT LIKE ?',
      [groupId, _groupRemovalCutoffMessageIdLike],
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
Future<int> dbCountTotalUnreadGroupMessages(DatabaseExecutor db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_MESSAGES_DB_COUNT_TOTAL_UNREAD_START',
    details: {},
  );

  try {
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM group_messages WHERE is_incoming = 1 AND read_at IS NULL AND id NOT LIKE ?',
      [_groupRemovalCutoffMessageIdLike],
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
Future<int> dbMarkGroupMessagesAsRead(
  DatabaseExecutor db,
  String groupId,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_MESSAGES_DB_MARK_READ_START',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );

  try {
    final now = DateTime.now().toUtc().toIso8601String();
    final count = await db.rawUpdate(
      'UPDATE group_messages SET read_at = ? WHERE group_id = ? AND is_incoming = 1 AND read_at IS NULL AND id NOT LIKE ?',
      [now, groupId, _groupRemovalCutoffMessageIdLike],
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
  DatabaseExecutor db,
  String groupId,
  String senderPeerId,
  String text,
  String timestamp,
) async {
  final result = await db.query(
    'group_messages',
    where:
        'group_id = ? AND sender_peer_id = ? AND text = ? AND timestamp = ? AND id NOT LIKE ?',
    whereArgs: [
      groupId,
      senderPeerId,
      text,
      timestamp,
      _groupRemovalCutoffMessageIdLike,
    ],
    limit: 1,
  );
  return result.isNotEmpty;
}

/// Deletes all group messages for a group. Returns the number deleted.
Future<int> dbDeleteGroupMessagesForGroup(
  DatabaseExecutor db,
  String groupId,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_MESSAGES_DB_DELETE_FOR_GROUP_START',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );

  try {
    final existingRows = await db.query(
      'group_messages',
      columns: ['id', 'group_id'],
      where: 'group_id = ?',
      whereArgs: [groupId],
    );
    for (final row in existingRows) {
      final messageId = row['id'] as String?;
      final rowGroupId = row['group_id'] as String?;
      if (messageId == null || rowGroupId == null) continue;
      await dbUpsertGroupMessageLocalDeletion(
        db,
        messageId: messageId,
        groupId: rowGroupId,
      );
    }

    final count = await db.delete(
      'group_messages',
      where: 'group_id = ?',
      whereArgs: [groupId],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MESSAGES_DB_DELETE_FOR_GROUP_SUCCESS',
      details: {'count': count},
    );

    return count;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MESSAGES_DB_DELETE_FOR_GROUP_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Deletes a single group message by ID.
Future<void> dbDeleteGroupMessage(DatabaseExecutor db, String id) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_MESSAGES_DB_DELETE_START',
    details: {'id': id.length > 8 ? id.substring(0, 8) : id},
  );

  try {
    final existingRows = await db.query(
      'group_messages',
      columns: ['group_id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (existingRows.isNotEmpty) {
      final groupId = existingRows.first['group_id'] as String?;
      if (groupId != null && groupId.isNotEmpty) {
        await dbUpsertGroupMessageLocalDeletion(
          db,
          messageId: id,
          groupId: groupId,
        );
      }
    }

    await db.delete('group_messages', where: 'id = ?', whereArgs: [id]);

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

/// Loads outgoing group messages stuck in 'sending' status older than [olderThan].
///
/// Returns raw row maps ordered by timestamp ASC, limited to [limit].
Future<List<Map<String, dynamic>>> dbLoadStuckSendingGroupMessages(
  DatabaseExecutor db, {
  required DateTime olderThan,
  int limit = 50,
}) async {
  final threshold = olderThan.toUtc().toIso8601String();
  return db.rawQuery(
    "SELECT * FROM group_messages WHERE status = 'sending' AND is_incoming = 0 AND timestamp < ? ORDER BY timestamp ASC, id ASC LIMIT ?",
    [threshold, limit],
  );
}

/// Loads outgoing group messages with 'failed' status.
///
/// Returns raw row maps ordered by timestamp ASC.
Future<List<Map<String, dynamic>>> dbLoadFailedOutgoingGroupMessages(
  DatabaseExecutor db, {
  int? limit,
}) async {
  final sql = StringBuffer(
    "SELECT * FROM group_messages WHERE status = 'failed' AND is_incoming = 0 ORDER BY timestamp ASC, id ASC",
  );
  if (limit != null) {
    sql.write(' LIMIT ?');
    return db.rawQuery(sql.toString(), [limit]);
  }
  return db.rawQuery(sql.toString());
}

/// Loads outgoing group messages where inbox store failed (inbox_stored = 0)
/// and an inbox retry payload is available.
///
/// Returns raw row maps ordered by timestamp ASC, limited to [limit].
Future<List<Map<String, dynamic>>> dbLoadGroupMessagesWithFailedInboxStore(
  DatabaseExecutor db, {
  int limit = 50,
}) async {
  return db.rawQuery(
    "SELECT * FROM group_messages WHERE is_incoming = 0 AND inbox_stored = 0 AND status IN ('sent', 'pending') AND inbox_retry_payload IS NOT NULL ORDER BY timestamp ASC, id ASC LIMIT ?",
    [limit],
  );
}

/// Transitions outgoing 'sending' messages to 'failed'.
///
/// When [olderThan] is provided, only messages older than the cutoff are
/// transitioned. When omitted, all outgoing sending rows are transitioned.
///
/// Returns the number of rows affected.
Future<int> dbTransitionGroupSendingToFailed(
  DatabaseExecutor db, {
  DateTime? olderThan,
}) async {
  if (olderThan == null) {
    return db.rawUpdate(
      "UPDATE group_messages SET status = 'failed' WHERE status = 'sending' AND is_incoming = 0",
    );
  }

  final threshold = olderThan.toUtc().toIso8601String();
  return db.rawUpdate(
    "UPDATE group_messages SET status = 'failed' WHERE status = 'sending' AND is_incoming = 0 AND timestamp < ?",
    [threshold],
  );
}

/// Updates the inbox_stored flag for a group message.
Future<void> dbUpdateGroupMessageInboxStored(
  DatabaseExecutor db,
  String id, {
  required bool stored,
}) async {
  await db.rawUpdate(
    'UPDATE group_messages SET inbox_stored = ? WHERE id = ?',
    [stored ? 1 : 0, id],
  );
}

/// Updates (or clears) the inbox_retry_payload for a group message.
Future<void> dbUpdateGroupMessageInboxRetryPayload(
  DatabaseExecutor db,
  String id,
  String? inboxRetryPayload,
) async {
  await db.rawUpdate(
    'UPDATE group_messages SET inbox_retry_payload = ? WHERE id = ?',
    [inboxRetryPayload, id],
  );
}

/// Updates (or clears) the wire_envelope for a group message.
Future<void> dbUpdateGroupMessageWireEnvelope(
  DatabaseExecutor db,
  String id,
  String? wireEnvelope,
) async {
  await db.rawUpdate(
    'UPDATE group_messages SET wire_envelope = ? WHERE id = ?',
    [wireEnvelope, id],
  );
}
