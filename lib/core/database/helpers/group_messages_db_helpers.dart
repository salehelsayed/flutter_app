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

    try {
      await db.insert('group_messages', row);
    } on DatabaseException catch (e) {
      if (!_isGroupMessageIdUniqueConflict(e)) {
        rethrow;
      }
      await _handleDuplicateGroupMessageInsert(db, row);
    }

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

bool _isGroupMessageIdUniqueConflict(DatabaseException error) {
  final message = error.toString().toLowerCase();
  return message.contains('unique constraint failed') &&
      message.contains('group_messages.id');
}

Future<void> _handleDuplicateGroupMessageInsert(
  DatabaseExecutor db,
  Map<String, Object?> row,
) async {
  final id = row['id'] as String? ?? '';
  final existingRows = await db.query(
    'group_messages',
    where: 'id = ?',
    whereArgs: [id],
    limit: 1,
  );
  if (existingRows.isEmpty) {
    throw StateError('group_messages id conflict without existing row: $id');
  }

  final existing = existingRows.first;
  if (!_sameGroupMessageIdentity(existing, row)) {
    return;
  }

  final existingIncoming = _isIncomingGroupMessageRow(existing);
  final incoming = _isIncomingGroupMessageRow(row);
  if (!existingIncoming && !incoming) {
    await _updateGroupMessageRow(db, row);
    return;
  }

  if (existingIncoming && incoming) {
    if (_isRepairPlaceholderRow(existing) && !_isRepairPlaceholderRow(row)) {
      await _updateGroupMessageRow(db, row);
      return;
    }
    final existingQuote = existing['quoted_message_id'] as String?;
    final incomingQuote = row['quoted_message_id'] as String?;
    if ((existingQuote == null || existingQuote.isEmpty) &&
        incomingQuote != null &&
        incomingQuote.isNotEmpty) {
      await db.update(
        'group_messages',
        {'quoted_message_id': incomingQuote},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
  }
}

bool _sameGroupMessageIdentity(
  Map<String, Object?> existing,
  Map<String, Object?> incoming,
) {
  return existing['group_id'] == incoming['group_id'] &&
      existing['sender_peer_id'] == incoming['sender_peer_id'];
}

bool _isIncomingGroupMessageRow(Map<String, Object?> row) {
  final value = row['is_incoming'];
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.toLowerCase();
    return normalized == '1' || normalized == 'true';
  }
  return true;
}

bool _isRepairPlaceholderRow(Map<String, Object?> row) {
  if (!_isIncomingGroupMessageRow(row)) return false;
  final status = row['status'];
  return status == 'pending_key' || status == 'undecryptable';
}

Future<void> _updateGroupMessageRow(
  DatabaseExecutor db,
  Map<String, Object?> row,
) async {
  final updates = Map<String, Object?>.from(row)..remove('id');
  if (updates.isEmpty) return;
  await db.update(
    'group_messages',
    updates,
    where: 'id = ?',
    whereArgs: [row['id']],
  );
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

/// Loads an indexed, bounded window around one live exact-group anchor.
/// This is three constant-bounded queries (anchor, older side, newer side),
/// never an offset/page scan. Locally deleted parents and synthetic removal
/// cutoffs are excluded at the query boundary.
Future<List<Map<String, Object?>>> dbLoadGroupMessagesAround(
  DatabaseExecutor db,
  String groupId,
  String anchorMessageId, {
  int before = 25,
  int after = 25,
}) async {
  if (before < 0 || before > 25 || after < 0 || after > 25) {
    throw ArgumentError('before and after must each be 0..25');
  }
  const live = '''
    gm.group_id = ?
    AND gm.id NOT LIKE ?
    AND NOT EXISTS (
      SELECT 1
      FROM group_message_local_deletions deleted
      WHERE deleted.message_id = gm.id
        AND deleted.group_id = gm.group_id
    )
  ''';
  final anchorRows = await db.rawQuery(
    '''
      SELECT gm.*
      FROM group_messages gm
      WHERE gm.id = ? AND $live
      LIMIT 1
    ''',
    [anchorMessageId, groupId, _groupRemovalCutoffMessageIdLike],
  );
  if (anchorRows.isEmpty) return const [];
  final anchor = anchorRows.single;
  final timestamp = anchor['timestamp'] as String;
  final id = anchor['id'] as String;

  final older = before == 0
      ? const <Map<String, Object?>>[]
      : await db.rawQuery(
          '''
            SELECT gm.*
            FROM group_messages gm
            WHERE $live
              AND (gm.timestamp < ? OR (gm.timestamp = ? AND gm.id < ?))
            ORDER BY gm.timestamp DESC, gm.id DESC
            LIMIT ?
          ''',
          [
            groupId,
            _groupRemovalCutoffMessageIdLike,
            timestamp,
            timestamp,
            id,
            before,
          ],
        );
  final newer = after == 0
      ? const <Map<String, Object?>>[]
      : await db.rawQuery(
          '''
            SELECT gm.*
            FROM group_messages gm
            WHERE $live
              AND (gm.timestamp > ? OR (gm.timestamp = ? AND gm.id > ?))
            ORDER BY gm.timestamp ASC, gm.id ASC
            LIMIT ?
          ''',
          [
            groupId,
            _groupRemovalCutoffMessageIdLike,
            timestamp,
            timestamp,
            id,
            after,
          ],
        );
  return [...older.reversed, anchor, ...newer];
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

/// Bounded authoritative rows for the iOS group-reaction authored-target
/// projection. Account identity, not device-local `is_incoming`, owns the
/// target so sibling-device copies remain eligible.
Future<List<Map<String, Object?>>> dbLoadAuthoredGroupMessagesForProjection(
  DatabaseExecutor db,
  String accountPeerId, {
  int limit = 256,
}) async {
  final normalizedAccountPeerId = accountPeerId.trim();
  if (normalizedAccountPeerId.isEmpty) return const [];
  if (limit <= 0) throw ArgumentError.value(limit, 'limit', 'must be positive');
  return db.rawQuery(
    '''
      SELECT gm.*
      FROM group_messages gm
      WHERE gm.sender_peer_id = ?
        AND gm.id NOT LIKE ?
        AND NOT EXISTS (
          SELECT 1
          FROM group_message_local_deletions deleted
          WHERE deleted.message_id = gm.id
            AND deleted.group_id = gm.group_id
        )
      ORDER BY gm.timestamp DESC, gm.id ASC
      LIMIT ?
    ''',
    [normalizedAccountPeerId, _groupRemovalCutoffMessageIdLike, limit],
  );
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
      latest.media_policy_version AS latest_media_policy_version,
      latest.media_lifecycle AS latest_media_lifecycle,
      latest.media_duration_seconds AS latest_media_duration_seconds,
      latest.media_protected AS latest_media_protected,
      latest.media_received_at AS latest_media_received_at,
      latest.media_expires_at AS latest_media_expires_at,
      latest.media_last_checked_at AS latest_media_last_checked_at,
      latest.media_consumed_at AS latest_media_consumed_at,
      latest.media_expired_at AS latest_media_expired_at,
      latest.media_cleanup_pending AS latest_media_cleanup_pending,
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

/// Loads batched preview aggregates for the provided groups (161
/// db-persistence-5, QUERY half).
///
/// One row per group that has at least one (non-cutoff) message, carrying
/// `message_count` (total), `unread_count`, `last_outgoing_at` (newest outgoing
/// timestamp, NULL when none), and the single latest row — so the feed builds
/// a collapsed group card's counts + state + "View earlier" affordance from the
/// summary instead of decrypting the group's full per-group page. The windowed
/// message slice itself is loaded separately, and ONLY for pending groups, in
/// `load_feed_use_case`. The `sys-member_removed_cutoff:` rows are excluded from
/// EVERY sub-query (total, unread, last_outgoing, and the latest pick). Distinct
/// from [dbLoadGroupThreadSummaries] so the orbit unread-badge path is untouched.
Future<List<Map<String, Object?>>> dbLoadGroupThreadPreviews(
  DatabaseExecutor db,
  List<String> groupIds,
) async {
  if (groupIds.isEmpty) return const [];

  final placeholders = List.filled(groupIds.length, '?').join(', ');
  final results = await db.rawQuery('''
    SELECT
      summary.group_id,
      summary.message_count,
      summary.unread_count,
      summary.last_outgoing_at,
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
      latest.media_policy_version AS latest_media_policy_version,
      latest.media_lifecycle AS latest_media_lifecycle,
      latest.media_duration_seconds AS latest_media_duration_seconds,
      latest.media_protected AS latest_media_protected,
      latest.media_received_at AS latest_media_received_at,
      latest.media_expires_at AS latest_media_expires_at,
      latest.media_last_checked_at AS latest_media_last_checked_at,
      latest.media_consumed_at AS latest_media_consumed_at,
      latest.media_expired_at AS latest_media_expired_at,
      latest.media_cleanup_pending AS latest_media_cleanup_pending,
      latest.read_at AS latest_read_at,
      latest.created_at AS latest_created_at
    FROM (
      SELECT
        group_id,
        COUNT(*) AS message_count,
        SUM(
          CASE
            WHEN is_incoming = 1 AND read_at IS NULL THEN 1
            ELSE 0
          END
        ) AS unread_count,
        MAX(
          CASE WHEN is_incoming = 0 THEN timestamp END
        ) AS last_outgoing_at
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
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MESSAGES_DB_LOAD_ONE_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads the first visible row with a shared logical delivery identity.
Future<Map<String, Object?>?> dbLoadGroupMessageByLogicalDeliveryId(
  DatabaseExecutor db,
  String groupId,
  String senderPeerId,
  String logicalDeliveryId,
) async {
  final normalizedLogicalDeliveryId = logicalDeliveryId.trim();
  if (normalizedLogicalDeliveryId.isEmpty) {
    return null;
  }

  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_MESSAGES_DB_LOAD_LOGICAL_DELIVERY_START',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'senderId': senderPeerId.length > 8
          ? senderPeerId.substring(0, 8)
          : senderPeerId,
    },
  );

  try {
    final results = await db.query(
      'group_messages',
      where:
          'group_id = ? AND sender_peer_id = ? AND logical_delivery_id = ? AND id NOT LIKE ?',
      whereArgs: [
        groupId,
        senderPeerId,
        normalizedLogicalDeliveryId,
        _groupRemovalCutoffMessageIdLike,
      ],
      orderBy: 'timestamp ASC, id ASC',
      limit: 1,
    );

    emitFlowEvent(
      layer: 'DB',
      event: results.isEmpty
          ? 'GROUP_MESSAGES_DB_LOAD_LOGICAL_DELIVERY_NOT_FOUND'
          : 'GROUP_MESSAGES_DB_LOAD_LOGICAL_DELIVERY_FOUND',
      details: {'count': results.length},
    );
    return results.isNotEmpty ? results.first : null;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MESSAGES_DB_LOAD_LOGICAL_DELIVERY_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
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

/// Deletes a group message for internal membership-window repair without
/// recording a local deletion tombstone.
Future<void> dbDeleteGroupMessageForMembershipRepair(
  DatabaseExecutor db,
  String id,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_MESSAGES_DB_MEMBERSHIP_REPAIR_DELETE_START',
    details: {'id': id.length > 8 ? id.substring(0, 8) : id},
  );

  try {
    await db.delete('group_messages', where: 'id = ?', whereArgs: [id]);

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MESSAGES_DB_MEMBERSHIP_REPAIR_DELETE_SUCCESS',
      details: {'id': id.length > 8 ? id.substring(0, 8) : id},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MESSAGES_DB_MEMBERSHIP_REPAIR_DELETE_ERROR',
      details: {
        'id': id.length > 8 ? id.substring(0, 8) : id,
        'error': e.toString(),
      },
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
    "SELECT * FROM group_messages WHERE status = 'sending' AND is_incoming = 0 AND COALESCE(last_send_attempt_at, timestamp) < ? ORDER BY timestamp ASC, id ASC LIMIT ?",
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

/// Loads outgoing group messages eligible for text send retry.
///
/// Includes failed rows and in-doubt pending rows. Returns raw row maps ordered
/// by timestamp ASC.
Future<List<Map<String, dynamic>>> dbLoadRetryableOutgoingGroupMessages(
  DatabaseExecutor db, {
  int? limit,
  int? nowMs,
}) async {
  final now = nowMs ?? DateTime.now().toUtc().millisecondsSinceEpoch;
  // Finding 05 Phase 4: skip rows still inside their exponential-backoff
  // window. The terminal 'send_failed' status is intentionally NOT included so
  // an exhausted row is never auto-retried — only a manual retry re-arms it.
  final sql = StringBuffer(
    "SELECT * FROM group_messages WHERE status IN ('failed', 'pending') "
    'AND is_incoming = 0 '
    'AND (next_eligible_at IS NULL OR next_eligible_at <= ?) '
    'ORDER BY timestamp ASC, id ASC',
  );
  final args = <Object?>[now];
  if (limit != null) {
    sql.write(' LIMIT ?');
    args.add(limit);
  }
  return db.rawQuery(sql.toString(), args);
}

/// Records a failed background retry attempt for [messageId]: increments
/// `retry_attempt_count`, schedules the next eligible time, and — when the
/// attempt budget is exhausted ([markTerminal]) — flips the row to the terminal
/// `send_failed` status so it is no longer auto-retried. Only affects a row
/// that is still retryable (`failed`/`pending`) and outgoing.
Future<void> dbRecordGroupMessageRetryFailure(
  DatabaseExecutor db,
  String messageId, {
  required int nextEligibleAtMs,
  required bool markTerminal,
}) async {
  final statusClause = markTerminal ? ", status = 'send_failed'" : '';
  await db.rawUpdate(
    'UPDATE group_messages '
    'SET retry_attempt_count = retry_attempt_count + 1, '
    'next_eligible_at = ?$statusClause '
    "WHERE id = ? AND is_incoming = 0 AND status IN ('failed', 'pending')",
    [nextEligibleAtMs, messageId],
  );
}

/// Clears the backoff window for all retryable outgoing group rows so the next
/// retrier pass re-attempts them immediately. Called on a fresh offline→online
/// transition (a reconnect always grants one immediate attempt). Leaves
/// terminal `send_failed` rows untouched. Returns the number of rows re-armed.
Future<int> dbClearGroupMessageRetryBackoff(DatabaseExecutor db) async {
  return db.rawUpdate(
    'UPDATE group_messages SET next_eligible_at = NULL '
    "WHERE is_incoming = 0 AND status IN ('failed', 'pending') "
    'AND next_eligible_at IS NOT NULL',
  );
}

/// Re-arms a terminal `send_failed` row for a user-initiated manual retry:
/// clears the backoff window, resets the attempt counter, and returns the row
/// to the retryable `failed` status so the normal send path can re-attempt it
/// with a fresh budget. No-op for rows that are not `send_failed`.
Future<void> dbResetGroupMessageRetryState(
  DatabaseExecutor db,
  String messageId,
) async {
  await db.rawUpdate(
    "UPDATE group_messages SET status = 'failed', retry_attempt_count = 0, "
    'next_eligible_at = NULL '
    "WHERE id = ? AND is_incoming = 0 AND status = 'send_failed'",
    [messageId],
  );
}

/// Loads outgoing group messages where inbox store failed (inbox_stored = 0)
/// and an inbox retry payload is available.
///
/// 210b: includes `queued_offline` — a real offline send persists that status
/// with its repush payload armed (publish-without-custody), and this repush
/// lane is its LIVE-app self-heal on reconnect (settling the row to 'sent',
/// i.e. the clock→tick transition). The app-resume sweep
/// ([dbTransitionGroupSendingToFailed]) remains the fallback for rows without
/// a payload.
///
/// Returns raw row maps ordered by timestamp ASC, limited to [limit].
Future<List<Map<String, dynamic>>> dbLoadGroupMessagesWithFailedInboxStore(
  DatabaseExecutor db, {
  int limit = 50,
}) async {
  return db.rawQuery(
    "SELECT * FROM group_messages WHERE is_incoming = 0 AND inbox_stored = 0 AND status IN ('sent', 'pending', 'queued_offline') AND inbox_retry_payload IS NOT NULL ORDER BY timestamp ASC, id ASC LIMIT ?",
    [limit],
  );
}

/// Transitions stuck outgoing rows to 'failed' so the retry lane re-drives them.
///
/// Covers two stuck states:
/// - `sending`: an in-flight send that never settled. When [olderThan] is
///   provided, only rows older than the cutoff are transitioned (a fresh
///   in-flight send is not yet "stuck"); when omitted, all outgoing sending
///   rows are transitioned.
/// - 210/210b `queued_offline`: a message composed while the sender was
///   offline. Only a PAYLOAD-LESS row transitions (regardless of age) — a row
///   with `inbox_retry_payload` is owned by the repush lane
///   ([dbLoadGroupMessagesWithFailedInboxStore] → settles to 'sent' with a
///   custody-first store, no re-publish), and this sweep runs BEFORE that lane
///   in every live wiring (retrier tick, app resume, app pause). Flipping a
///   payload-armed row to 'failed' here would show a dishonest red bubble
///   after a pause/resume while still offline and bypass the custody-first
///   repush on reconnect (review 210b-F1).
///
/// Returns the number of rows affected.
Future<int> dbTransitionGroupSendingToFailed(
  DatabaseExecutor db, {
  DateTime? olderThan,
}) async {
  final hasMediaAttachments = (await db.rawQuery(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' "
    "AND name = 'media_attachments' LIMIT 1",
  )).isNotEmpty;
  final pendingUploadExclusion = hasMediaAttachments
      ? 'AND NOT EXISTS (SELECT 1 FROM media_attachments attachment '
            'WHERE attachment.message_id = group_messages.id '
            "AND attachment.owner_lane = 'group' "
            "AND attachment.download_status = 'upload_pending')"
      : '';
  if (olderThan == null) {
    return db.rawUpdate(
      "UPDATE group_messages SET status = 'failed' "
      "WHERE (status = 'sending' "
      "OR (status = 'queued_offline' AND inbox_retry_payload IS NULL)) "
      'AND is_incoming = 0 '
      '$pendingUploadExclusion',
    );
  }

  final threshold = olderThan.toUtc().toIso8601String();
  return db.rawUpdate(
    "UPDATE group_messages SET status = 'failed' "
    'WHERE is_incoming = 0 '
    "AND ((status = 'sending' "
    'AND COALESCE(last_send_attempt_at, timestamp) < ?) '
    "OR (status = 'queued_offline' AND inbox_retry_payload IS NULL)) "
    '$pendingUploadExclusion',
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

// ---------------------------------------------------------------------------
// Group private-media lifecycle (Plan 238)
// ---------------------------------------------------------------------------

/// Establishes the sender's device-local lifecycle anchor only after a
/// delivery path has obtained live or relay custody.
Future<int> dbAnchorOutgoingGroupPrivateMediaCustody(
  DatabaseExecutor db,
  String id, {
  required int nowMs,
}) {
  return db.rawUpdate(
    'UPDATE group_messages SET '
    'media_received_at = ?, '
    'media_expires_at = CASE '
    "WHEN media_lifecycle = 'disappearing' "
    'THEN ? + (media_duration_seconds * 1000) ELSE NULL END, '
    'media_last_checked_at = CASE '
    "WHEN media_lifecycle = 'disappearing' THEN ? "
    'ELSE media_last_checked_at END '
    'WHERE id = ? AND is_incoming = 0 '
    'AND media_policy_version = 1 AND media_protected = 1 '
    "AND media_lifecycle IN ('standard','view_once','disappearing') "
    'AND media_received_at IS NULL AND media_consumed_at IS NULL '
    'AND media_expired_at IS NULL AND media_cleanup_pending = 0',
    [nowMs, nowMs, nowMs, id],
  );
}

/// Durable View Once claim at the group contract's reveal boundary.
///
/// The parent row is the authority. Cleanup happens only after this CAS (or a
/// later recovery pass observes it), so a crash can never make the item
/// available again merely because its file survived.
Future<int> dbConsumeGroupPrivateMedia(
  DatabaseExecutor db,
  String id, {
  required int nowMs,
}) {
  return db.rawUpdate(
    'UPDATE group_messages SET '
    'media_consumed_at = COALESCE(media_consumed_at, ?), '
    'media_last_checked_at = MAX(COALESCE(media_last_checked_at, 0), ?), '
    'media_cleanup_pending = 1 '
    'WHERE id = ? AND is_incoming = 1 '
    'AND media_policy_version = 1 '
    "AND media_lifecycle = 'view_once' AND media_protected = 1 "
    'AND media_consumed_at IS NULL AND media_expired_at IS NULL '
    'AND media_cleanup_pending = 0',
    [nowMs, nowMs, id],
  );
}

/// Atomically advances the persisted high-water clock and expires one active
/// disappearing parent when the monotonic effective time reaches its deadline.
/// Incoming and outgoing rows share this device-local rule; their anchor is
/// established by receiver commit and sender custody success respectively.
Future<int> dbAdvanceGroupPrivateMediaClock(
  DatabaseExecutor db,
  String id, {
  required int nowMs,
}) {
  return db.rawUpdate(
    'UPDATE group_messages SET '
    'media_last_checked_at = MAX(COALESCE(media_last_checked_at, 0), ?), '
    'media_expired_at = CASE '
    'WHEN MAX(COALESCE(media_last_checked_at, 0), ?) >= media_expires_at '
    'THEN COALESCE(media_expired_at, '
    'MAX(COALESCE(media_last_checked_at, 0), ?)) '
    'ELSE media_expired_at END, '
    'media_cleanup_pending = CASE '
    'WHEN MAX(COALESCE(media_last_checked_at, 0), ?) >= media_expires_at '
    'THEN 1 ELSE media_cleanup_pending END '
    'WHERE id = ? AND media_policy_version = 1 '
    "AND media_lifecycle = 'disappearing' AND media_protected = 1 "
    'AND media_received_at IS NOT NULL AND media_expires_at IS NOT NULL '
    'AND media_consumed_at IS NULL AND media_expired_at IS NULL',
    [nowMs, nowMs, nowMs, nowMs, id],
  );
}

/// Rechecks the exact private parent after advancing its high-water clock.
/// Intended for attachment save/download transactions; callers must still
/// verify the exact attachment owner and identity in the same transaction.
Future<bool> dbAdvanceAndQualifyGroupPrivateMediaParent(
  DatabaseExecutor db,
  String id, {
  required String groupId,
  required int nowMs,
}) async {
  await dbAdvanceGroupPrivateMediaClock(db, id, nowMs: nowMs);
  final rows = await db.rawQuery(
    'SELECT 1 FROM group_messages WHERE id = ? AND group_id = ? '
    'AND media_policy_version = 1 AND media_protected = 1 '
    "AND media_lifecycle IN ('standard','view_once','disappearing') "
    'AND media_consumed_at IS NULL AND media_expired_at IS NULL '
    'AND media_cleanup_pending = 0 '
    "AND (media_lifecycle != 'disappearing' OR ("
    'media_expires_at IS NOT NULL AND media_last_checked_at IS NOT NULL '
    'AND media_last_checked_at < media_expires_at)) LIMIT 1',
    [id, groupId],
  );
  return rows.isNotEmpty;
}

Future<int?> dbLoadNextGroupPrivateMediaExpiryAtMs(DatabaseExecutor db) async {
  final rows = await db.rawQuery(
    'SELECT MIN(media_expires_at) AS next_expiry FROM group_messages '
    'WHERE media_policy_version = 1 AND media_protected = 1 '
    "AND media_lifecycle = 'disappearing' "
    'AND media_received_at IS NOT NULL AND media_expires_at IS NOT NULL '
    'AND media_consumed_at IS NULL AND media_expired_at IS NULL '
    'AND media_cleanup_pending = 0',
  );
  return (rows.single['next_expiry'] as num?)?.toInt();
}

Future<List<Map<String, Object?>>> dbLoadActiveGroupPrivateMediaDisappearing(
  DatabaseExecutor db, {
  int limit = 100,
}) {
  return db.query(
    'group_messages',
    where:
        'media_policy_version = 1 AND media_protected = 1 '
        "AND media_lifecycle = 'disappearing' "
        'AND media_received_at IS NOT NULL AND media_expires_at IS NOT NULL '
        'AND media_consumed_at IS NULL AND media_expired_at IS NULL '
        'AND media_cleanup_pending = 0',
    orderBy: 'media_expires_at ASC, id ASC',
    limit: limit,
  );
}

/// Bounded terminal cleanup queue. A pending parent remains selectable even
/// after its last attachment row was deleted: cleanup clears the parent marker
/// after row deletion, so a crash between those writes must converge on the
/// next recovery pass. Once the marker is clear, the attachment existence
/// predicate keeps completed placeholders out of later passes.
Future<List<Map<String, Object?>>> dbLoadGroupPrivateMediaRecoveryCandidates(
  DatabaseExecutor db, {
  int limit = 100,
}) {
  return db.query(
    'group_messages',
    where:
        'media_policy_version > 0 AND ('
        'media_cleanup_pending = 1 OR (('
        'media_consumed_at IS NOT NULL OR media_expired_at IS NOT NULL '
        "OR media_lifecycle = 'unsupported') "
        'AND EXISTS (SELECT 1 FROM media_attachments attachment '
        'WHERE attachment.message_id = group_messages.id '
        "AND attachment.owner_lane = 'group')))",
    orderBy: 'COALESCE(media_last_checked_at, 0) ASC, id ASC',
    limit: limit,
  );
}

Future<int> dbRotateGroupPrivateMediaRecoveryCandidate(
  DatabaseExecutor db,
  String id, {
  required int nowMs,
}) {
  return db.rawUpdate(
    'UPDATE group_messages SET media_last_checked_at = MAX('
    'COALESCE(media_last_checked_at, 0) + 1, ?) '
    'WHERE id = ? AND media_policy_version > 0 AND ('
    'media_cleanup_pending = 1 OR media_consumed_at IS NOT NULL '
    "OR media_expired_at IS NOT NULL OR media_lifecycle = 'unsupported')",
    [nowMs, id],
  );
}

/// Clears the retry marker only after every exact group-owned attachment row
/// is gone. A failed/partial cleanup therefore stays durably discoverable.
Future<int> dbCompleteGroupPrivateMediaCleanup(DatabaseExecutor db, String id) {
  return db.rawUpdate(
    'UPDATE group_messages SET media_cleanup_pending = 0 '
    'WHERE id = ? AND media_policy_version > 0 '
    'AND (media_consumed_at IS NOT NULL OR media_expired_at IS NOT NULL '
    "OR media_lifecycle = 'unsupported') "
    'AND NOT EXISTS (SELECT 1 FROM media_attachments attachment '
    'WHERE attachment.message_id = group_messages.id '
    "AND attachment.owner_lane = 'group')",
    [id],
  );
}
