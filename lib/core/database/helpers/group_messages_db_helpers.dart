import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../media/group_media_blob_custody.dart';
import '../../notifications/deterministic_notification_id.dart';
import '../../services/protected_group_content_contract.dart';
import '../../utils/flow_event_emitter.dart';
import '../direct_media_blob_custody.dart';
import '../db_write_transaction.dart';
import 'direct_media_blob_custody_db_helpers.dart';
import 'group_message_local_deletions_db_helpers.dart';
import 'group_event_log_db_helpers.dart';
import 'group_notification_display_outbox_db_helpers.dart';
import 'group_notification_read_acknowledgement_db_helpers.dart';
import 'group_notification_reconciliation_outbox_db_helpers.dart';
import 'group_parent_write_guard.dart';
import 'protected_group_content_db_helpers.dart';

const _groupRemovalCutoffMessageIdLike = 'sys-member_removed_cutoff:%';

/// Inserts a group message into the database.
///
/// Returns whether the requested message identity was accepted by the current
/// parent authority. A locally deleted message, an absent/marked parent, or a
/// conflicting message identity returns false without granting projection or
/// outgoing-work authority to the caller.
Future<bool> dbInsertGroupMessage(
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
      return false;
    }

    try {
      final inserted = await dbInsertOrdinaryGroupOwnedRow(
        db,
        table: 'group_messages',
        row: row,
      );
      if (!inserted) {
        emitFlowEvent(
          layer: 'DB',
          event: 'GROUP_MESSAGES_DB_INSERT_REFUSED_PARENT',
          details: {'id': id.length > 8 ? id.substring(0, 8) : id},
        );
        return false;
      }
    } on DatabaseException catch (e) {
      if (!_isGroupMessageIdUniqueConflict(e)) {
        rethrow;
      }
      if (!await _handleDuplicateGroupMessageInsert(db, row)) {
        return false;
      }
    }

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MESSAGES_DB_INSERT_SUCCESS',
      details: {'id': id.length > 8 ? id.substring(0, 8) : id},
    );
    return true;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MESSAGES_DB_INSERT_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Exact protected-reaction target qualification at the durable boundary.
/// GroupMessageRepositoryImpl deliberately does not hydrate attachment rows,
/// so model-only checks cannot enforce the blob-free content contract.
Future<bool> dbIsStrictGroupReactionTargetEligible(
  DatabaseExecutor db,
  Map<String, Object?> expected,
) async {
  final messageId = expected['id'] as String? ?? '';
  final groupId = expected['group_id'] as String? ?? '';
  if (messageId.isEmpty || groupId.isEmpty) return false;
  final rows = await db.rawQuery(
    'SELECT 1 FROM group_messages message '
    'WHERE message.id = ? AND message.group_id = ? '
    'AND message.sender_peer_id = ? AND message.timestamp = ? '
    "AND message.text NOT LIKE '{\"__sys\":%' "
    "AND COALESCE(message.quoted_message_id, '') = '' "
    'AND COALESCE(message.is_forwarded, 0) = 0 '
    'AND COALESCE(message.media_policy_version, 0) = 0 '
    'AND NOT EXISTS (SELECT 1 FROM media_attachments attachment '
    'WHERE attachment.message_id = message.id) LIMIT 1',
    <Object?>[
      messageId,
      groupId,
      expected['sender_peer_id'],
      expected['timestamp'],
    ],
  );
  return rows.isNotEmpty;
}

/// The only low-level message insert allowed for a marked group. It accepts a
/// visible self-removal timeline row bound to the exact current marker; absent,
/// changed, or unmarked parents perform no write. Ordinary callers must use
/// [dbInsertGroupMessage].
Future<bool> dbInsertExactSelfRemovalTimelineMessage(
  DatabaseExecutor db,
  Map<String, Object?> row, {
  required String expectedSelfRemovedAt,
}) async {
  final groupId = row['group_id'] as String? ?? '';
  final id = row['id'] as String? ?? '';
  if (groupId.isEmpty ||
      !id.startsWith('sys-member_removed:$groupId:') ||
      await dbIsGroupMessageLocallyDeleted(db, id)) {
    return false;
  }
  try {
    return await dbInsertExactMarkedGroupOwnedRow(
      db,
      table: 'group_messages',
      row: row,
      expectedSelfRemovedAt: expectedSelfRemovedAt,
    );
  } on DatabaseException catch (error) {
    if (!_isGroupMessageIdUniqueConflict(error)) rethrow;
    final existing = await db.query(
      'group_messages',
      where: 'id = ? AND group_id = ?',
      whereArgs: [id, groupId],
      limit: 1,
    );
    return existing.isNotEmpty &&
        _sameGroupMessageIdentity(existing.single, row);
  }
}

bool _isGroupMessageIdUniqueConflict(DatabaseException error) {
  final message = error.toString().toLowerCase();
  return message.contains('unique constraint failed') &&
      message.contains('group_messages.id');
}

Future<bool> _handleDuplicateGroupMessageInsert(
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
    return false;
  }

  final existingIncoming = _isIncomingGroupMessageRow(existing);
  final incoming = _isIncomingGroupMessageRow(row);
  if (!existingIncoming && !incoming) {
    return _updateGroupMessageRow(db, row);
  }

  if (existingIncoming && incoming) {
    if (_isRepairPlaceholderRow(existing) && !_isRepairPlaceholderRow(row)) {
      return _updateGroupMessageRow(db, row);
    }
    final existingQuote = existing['quoted_message_id'] as String?;
    final incomingQuote = row['quoted_message_id'] as String?;
    if ((existingQuote == null || existingQuote.isEmpty) &&
        incomingQuote != null &&
        incomingQuote.isNotEmpty) {
      return await dbUpdateOrdinaryGroupOwnedRows(
            db,
            table: 'group_messages',
            groupId: row['group_id'] as String? ?? '',
            values: {'quoted_message_id': incomingQuote},
            where:
                "id = ? AND NOT (status = 'send_failed' "
                'AND wire_envelope IS NULL AND inbox_retry_payload IS NULL)',
            whereArgs: [row['id']],
          ) >
          0;
    }
  }
  return true;
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

Future<bool> _updateGroupMessageRow(
  DatabaseExecutor db,
  Map<String, Object?> row,
) async {
  final updates = Map<String, Object?>.from(row)..remove('id');
  if (updates.isEmpty) return true;
  return await dbUpdateOrdinaryGroupOwnedRows(
        db,
        table: 'group_messages',
        groupId: row['group_id'] as String? ?? '',
        values: updates,
        where:
            "id = ? AND NOT (status = 'send_failed' "
            'AND wire_envelope IS NULL AND inbox_retry_payload IS NULL)',
        whereArgs: [row['id']],
      ) >
      0;
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
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'gm.group_id',
  );
  return db.rawQuery(
    '''
      SELECT gm.*
      FROM group_messages gm
      WHERE gm.sender_peer_id = ?
        AND gm.id NOT LIKE ?
        AND $parent
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
    final existing = await db.query(
      'group_messages',
      columns: const ['group_id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (existing.isEmpty) return;
    await dbUpdateOrdinaryGroupOwnedRows(
      db,
      table: 'group_messages',
      groupId: existing.single['group_id'] as String? ?? '',
      values: {'status': status},
      where: "id = ? AND (status != 'send_failed' OR ? = 'send_failed')",
      whereArgs: [id, status],
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
  String groupId, {
  String? acknowledgedContentKind,
  String? acknowledgedEventIdentity,
  String? acknowledgedGeneration,
}) async {
  final acknowledgementParts = <String?>[
    acknowledgedContentKind,
    acknowledgedEventIdentity,
    acknowledgedGeneration,
  ];
  final acknowledgementPartCount = acknowledgementParts
      .where((value) => value != null)
      .length;
  if (acknowledgementPartCount != 0 &&
      acknowledgementPartCount != acknowledgementParts.length) {
    throw ArgumentError(
      'acknowledged content kind, event identity and generation must be '
      'provided together',
    );
  }
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_MESSAGES_DB_MARK_READ_START',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );

  try {
    final count = await _runGroupMessageCleanupTransaction(db, (txn) async {
      final now = DateTime.now().toUtc().toIso8601String();
      final updated = await txn.rawUpdate(
        'UPDATE group_messages SET read_at = ? WHERE group_id = ? AND is_incoming = 1 AND read_at IS NULL AND id NOT LIKE ?',
        [now, groupId, _groupRemovalCutoffMessageIdLike],
      );

      if (await _hasGroupReactionAcknowledgementColumn(txn)) {
        // A conversation-level acknowledgement includes reaction-only cards.
        // Bind it to every reaction that exists in this group *inside the same
        // transaction*. A later ADD replaces its row with a fresh NULL marker,
        // so a post-read notification remains eligible.
        await txn.rawUpdate(
          'UPDATE message_reactions '
          'SET notification_acknowledged_at = ? '
          'WHERE notification_acknowledged_at IS NULL '
          'AND EXISTS (SELECT 1 FROM group_messages AS target '
          'WHERE target.id = message_reactions.message_id '
          'AND target.group_id = ?)',
          <Object?>[now, groupId],
        );
      }

      if (acknowledgementPartCount == acknowledgementParts.length) {
        if (acknowledgedContentKind == 'reaction') {
          await _bindAcknowledgedReactionCustodyToCanonicalRow(
            txn,
            groupId: groupId,
            eventIdentity: acknowledgedEventIdentity!,
          );
        }
        final absorbedByCanonicalRow = acknowledgedContentKind == 'message'
            ? (await txn.query(
                'group_messages',
                columns: const <String>['id'],
                where:
                    'id = ? AND group_id = ? AND is_incoming = 1 '
                    'AND read_at IS NOT NULL',
                whereArgs: <Object?>[acknowledgedEventIdentity, groupId],
                limit: 1,
              )).isNotEmpty
            : (await txn.rawQuery(
                'SELECT 1 FROM message_reactions AS reaction '
                'INNER JOIN group_messages AS target '
                'ON target.id = reaction.message_id '
                'WHERE target.group_id = ? '
                'AND reaction.notification_display_terminal_event_id = ? '
                'AND reaction.notification_acknowledged_at IS NOT NULL '
                'LIMIT 1',
                <Object?>[groupId, acknowledgedEventIdentity],
              )).isNotEmpty;
        if (!absorbedByCanonicalRow) {
          await dbRecordExactGroupNotificationReadAcknowledgement(
            txn,
            groupId: groupId,
            contentKind: acknowledgedContentKind!,
            eventIdentity: acknowledgedEventIdentity!,
            generation: acknowledgedGeneration!,
            acknowledgedAt: now,
          );
        } else if (acknowledgedContentKind == 'message') {
          // A partial/older v106 run may already have left the exact tuple.
          // Canonical read_at now owns the fact, so remove redundant custody.
          await dbConsumeExactGroupNotificationReadAcknowledgement(
            txn,
            groupId: groupId,
            contentKind: 'message',
            eventIdentity: acknowledgedEventIdentity!,
          );
        } else {
          await dbConsumeExactGroupNotificationReadAcknowledgement(
            txn,
            groupId: groupId,
            contentKind: 'reaction',
            eventIdentity: acknowledgedEventIdentity!,
          );
        }
      }

      // Keep ready and not-ready custody until its exact projection lane
      // observes this durable acknowledgement. Deleting custody here leaves a
      // loaded retry with no fact to consult and lets it re-publish after read.
      await dbEnqueueGroupNotificationReconciliationOutbox(
        txn,
        groupId: groupId,
      );
      return updated;
    });

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

Future<void> _bindAcknowledgedReactionCustodyToCanonicalRow(
  DatabaseExecutor db, {
  required String groupId,
  required String eventIdentity,
}) async {
  final table = await db.rawQuery(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' "
    "AND name = 'group_notification_display_outbox' LIMIT 1",
  );
  if (table.isEmpty) return;
  final custodyRows = await db.query(
    'group_notification_display_outbox',
    columns: const <String>[
      'event_id',
      'message_id',
      'actor_peer_id',
      'event_timestamp',
      'reaction_id',
    ],
    where:
        "group_id = ? AND event_kind = 'reaction' "
        "AND reaction_action = 'add' AND reaction_tombstone = 0",
    whereArgs: <Object?>[groupId],
  );
  final exact = custodyRows
      .where((row) {
        final rawEventId = (row['event_id'] as String?)?.trim();
        return rawEventId != null &&
            rawEventId.isNotEmpty &&
            boundedReactionEventIdentity(rawEventId) == eventIdentity;
      })
      .toList(growable: false);
  if (exact.length != 1) return;
  final custody = exact.single;
  await db.rawUpdate(
    'UPDATE message_reactions '
    'SET notification_display_terminal_event_id = ? '
    'WHERE id = ? AND message_id = ? AND sender_peer_id = ? '
    'AND timestamp = ? AND removed_at IS NULL '
    'AND notification_acknowledged_at IS NOT NULL '
    'AND (notification_display_terminal_event_id IS NULL '
    "OR TRIM(notification_display_terminal_event_id) = '' "
    'OR notification_display_terminal_event_id = ?) '
    'AND EXISTS (SELECT 1 FROM group_messages AS target '
    'WHERE target.id = message_reactions.message_id '
    'AND target.group_id = ?)',
    <Object?>[
      eventIdentity,
      custody['reaction_id'],
      custody['message_id'],
      custody['actor_peer_id'],
      custody['event_timestamp'],
      eventIdentity,
      groupId,
    ],
  );
}

Future<bool> _hasGroupReactionAcknowledgementColumn(DatabaseExecutor db) async {
  final columns = await db.rawQuery('PRAGMA table_info(message_reactions)');
  return columns.any(
    (column) => column['name'] == 'notification_acknowledged_at',
  );
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
    final count = await _runGroupMessageCleanupTransaction(db, (txn) async {
      await dbDeleteGroupNotificationDisplayOutboxForGroup(txn, groupId);
      final existingRows = await txn.query(
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
          txn,
          messageId: messageId,
          groupId: rowGroupId,
        );
      }

      return txn.delete(
        'group_messages',
        where: 'group_id = ?',
        whereArgs: [groupId],
      );
    });

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
    await _runGroupMessageCleanupTransaction(db, (txn) async {
      final existingRows = await txn.query(
        'group_messages',
        columns: ['group_id'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (existingRows.isNotEmpty) {
        final groupId = existingRows.first['group_id'] as String?;
        if (groupId != null && groupId.isNotEmpty) {
          await dbDeleteGroupNotificationDisplayOutboxForMessage(
            txn,
            groupId: groupId,
            messageId: id,
          );
          await dbUpsertGroupMessageLocalDeletion(
            txn,
            messageId: id,
            groupId: groupId,
          );
        }
      }
      await txn.delete('group_messages', where: 'id = ?', whereArgs: [id]);
    });

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
    await _runGroupMessageCleanupTransaction(db, (txn) async {
      final existingRows = await txn.query(
        'group_messages',
        columns: const <String>['group_id'],
        where: 'id = ?',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      if (existingRows.isNotEmpty) {
        final groupId = existingRows.single['group_id'] as String?;
        if (groupId != null && groupId.isNotEmpty) {
          await dbDeleteGroupNotificationDisplayOutboxForMessage(
            txn,
            groupId: groupId,
            messageId: id,
          );
        }
      }
      await txn.delete('group_messages', where: 'id = ?', whereArgs: [id]);
    });

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

Future<T> _runGroupMessageCleanupTransaction<T>(
  DatabaseExecutor db,
  Future<T> Function(DatabaseExecutor txn) body,
) {
  if (db is Database) {
    return dbWriteTransaction(db, (txn) => body(txn));
  }
  // A caller such as the group-exit transaction may already own the SQL
  // transaction. Reuse that executor rather than attempting a nested write.
  return body(db);
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
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'group_messages.group_id',
  );
  final sql = StringBuffer(
    "SELECT * FROM group_messages WHERE status = 'failed' "
    'AND is_incoming = 0 AND $parent ORDER BY timestamp ASC, id ASC',
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
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'group_messages.group_id',
  );
  // Finding 05 Phase 4: skip rows still inside their exponential-backoff
  // window. The terminal 'send_failed' status is intentionally NOT included so
  // an exhausted row is never auto-retried — only a manual retry re-arms it.
  final sql = StringBuffer(
    "SELECT * FROM group_messages WHERE status IN ('failed', 'pending') "
    'AND is_incoming = 0 '
    'AND $parent '
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
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'group_messages.group_id',
  );
  final statusClause = markTerminal ? ", status = 'send_failed'" : '';
  await db.rawUpdate(
    'UPDATE group_messages '
    'SET retry_attempt_count = retry_attempt_count + 1, '
    'next_eligible_at = ?$statusClause '
    "WHERE id = ? AND is_incoming = 0 AND status IN ('failed', 'pending') "
    'AND $parent',
    [nextEligibleAtMs, messageId],
  );
}

/// Clears the backoff window for all retryable outgoing group rows so the next
/// retrier pass re-attempts them immediately. Called on a fresh offline→online
/// transition (a reconnect always grants one immediate attempt). Leaves
/// terminal `send_failed` rows untouched. Returns the number of rows re-armed.
Future<int> dbClearGroupMessageRetryBackoff(DatabaseExecutor db) async {
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'group_messages.group_id',
  );
  return db.rawUpdate(
    'UPDATE group_messages SET next_eligible_at = NULL '
    "WHERE is_incoming = 0 AND status IN ('failed', 'pending') "
    'AND next_eligible_at IS NOT NULL AND $parent',
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
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'group_messages.group_id',
  );
  await db.rawUpdate(
    "UPDATE group_messages SET status = 'failed', retry_attempt_count = 0, "
    'next_eligible_at = NULL '
    "WHERE id = ? AND is_incoming = 0 AND status = 'send_failed' "
    'AND ((wire_envelope IS NOT NULL AND length(wire_envelope) > 0) '
    'OR (inbox_retry_payload IS NOT NULL AND length(inbox_retry_payload) > 0)) '
    'AND $parent',
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
  bool strictContentOnly = false,
  int offset = 0,
}) async {
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'group_messages.group_id',
  );
  return db.rawQuery(
    "SELECT * FROM group_messages WHERE is_incoming = 0 "
    "AND inbox_stored = 0 AND status IN ('sent', 'pending', 'queued_offline') "
    'AND inbox_retry_payload IS NOT NULL '
    "AND (? = 0 OR instr(inbox_retry_payload, 'group_content_v1') > 0) "
    'AND $parent '
    'ORDER BY timestamp ASC, id ASC LIMIT ? OFFSET ?',
    [strictContentOnly ? 1 : 0, limit, offset],
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
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'group_messages.group_id',
  );
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
      'AND $parent '
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
    'AND $parent '
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
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'group_messages.group_id',
  );
  await db.rawUpdate(
    'UPDATE group_messages SET inbox_stored = ? '
    "WHERE id = ? AND status != 'send_failed' AND $parent",
    [stored ? 1 : 0, id],
  );
}

/// Updates (or clears) the inbox_retry_payload for a group message.
Future<void> dbUpdateGroupMessageInboxRetryPayload(
  DatabaseExecutor db,
  String id,
  String? inboxRetryPayload,
) async {
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'group_messages.group_id',
  );
  await db.rawUpdate(
    'UPDATE group_messages SET inbox_retry_payload = ? '
    "WHERE id = ? AND status != 'send_failed' AND $parent",
    [inboxRetryPayload, id],
  );
}

/// Updates (or clears) the wire_envelope for a group message.
Future<void> dbUpdateGroupMessageWireEnvelope(
  DatabaseExecutor db,
  String id,
  String? wireEnvelope,
) async {
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'group_messages.group_id',
  );
  await db.rawUpdate(
    'UPDATE group_messages SET wire_envelope = ? '
    "WHERE id = ? AND status != 'send_failed' AND $parent",
    [wireEnvelope, id],
  );
}

const _groupOutgoingRetryAuthorityFields = <String>[
  'id',
  'group_id',
  'sender_peer_id',
  'transport_peer_id',
  'sender_username',
  'text',
  'timestamp',
  'last_send_attempt_at',
  'quoted_message_id',
  'logical_delivery_id',
  'key_generation',
  'status',
  'is_incoming',
  'is_forwarded',
  'media_policy_version',
  'media_lifecycle',
  'media_duration_seconds',
  'media_protected',
  'media_received_at',
  'media_expires_at',
  'media_last_checked_at',
  'media_consumed_at',
  'media_expired_at',
  'media_cleanup_pending',
  'created_at',
  'wire_envelope',
  'inbox_stored',
  'inbox_retry_payload',
  'retry_attempt_count',
  'next_eligible_at',
];

bool _sameGroupOutgoingRetryAuthority(
  Map<String, Object?> current,
  Map<String, Object?> expected,
) {
  for (final field in _groupOutgoingRetryAuthorityFields) {
    final left = current[field];
    final right = expected[field];
    if (left is num && right is num) {
      if (left.toInt() != right.toInt()) return false;
      continue;
    }
    if (left != right) return false;
  }
  return true;
}

/// Exact media-only precursor written by the blob staging transaction.
/// Content authority does not exist until the immutable wire/plaintext owner
/// and retry wrapper are promoted together by the prepared-content transaction.
bool _sameGroupOutgoingBlobPendingAuthority(
  Map<String, Object?> current,
  Map<String, Object?> expected,
) {
  final expectedAttempt = expected['last_send_attempt_at'] as String?;
  final currentAttempt = current['last_send_attempt_at'] as String?;
  final expectedAttemptAt = expectedAttempt == null
      ? null
      : DateTime.tryParse(expectedAttempt)?.toUtc();
  final currentAttemptAt = currentAttempt == null
      ? null
      : DateTime.tryParse(currentAttempt)?.toUtc();
  if (current['wire_envelope'] != null ||
      current['inbox_retry_payload'] != null ||
      expected['wire_envelope'] is! String ||
      (expected['wire_envelope'] as String).isEmpty ||
      expected['inbox_retry_payload'] is! String ||
      (expected['inbox_retry_payload'] as String).isEmpty ||
      expectedAttemptAt == null ||
      (currentAttempt != null &&
          (currentAttemptAt == null ||
              currentAttemptAt.isAfter(expectedAttemptAt)))) {
    return false;
  }
  for (final field in _groupOutgoingRetryAuthorityFields) {
    if (field == 'wire_envelope' ||
        field == 'inbox_retry_payload' ||
        field == 'last_send_attempt_at') {
      continue;
    }
    final left = current[field];
    final right = expected[field];
    if (left is num && right is num) {
      if (left.toInt() != right.toInt()) return false;
    } else if (left != right) {
      return false;
    }
  }
  return true;
}

bool _sameGroupOutgoingZeroTargetBlobPendingAuthority(
  Map<String, Object?> current,
  Map<String, Object?> expected,
) {
  if (expected['inbox_retry_payload'] != null) return false;
  final sentinelExpected = Map<String, Object?>.from(expected)
    ..['inbox_retry_payload'] = '__zero_target_media__';
  return _sameGroupOutgoingBlobPendingAuthority(current, sentinelExpected);
}

bool _isExactStrictRetryRecipientShrink(
  String previousRaw,
  String replacementRaw,
) {
  try {
    final previous = ProtectedGroupContentRetryManifest.decode(previousRaw);
    final replacement = ProtectedGroupContentRetryManifest.decode(
      replacementRaw,
    );
    if (previous.groupId != replacement.groupId ||
        previous.replayEnvelope != replacement.replayEnvelope ||
        previous.contentEventId != replacement.contentEventId ||
        previous.payloadType != replacement.payloadType ||
        previous.pendingRecipientPeerIds.length !=
            replacement.pendingRecipientPeerIds.length + 1 ||
        previous.fullRecipientPeerIds.length !=
            replacement.fullRecipientPeerIds.length) {
      return false;
    }
    for (var index = 0; index < previous.fullRecipientPeerIds.length; index++) {
      if (previous.fullRecipientPeerIds[index] !=
          replacement.fullRecipientPeerIds[index]) {
        return false;
      }
    }
    final prior = previous.pendingRecipientPeerIds.toSet();
    final next = replacement.pendingRecipientPeerIds.toSet();
    return prior.containsAll(next) && prior.difference(next).length == 1;
  } catch (_) {
    return false;
  }
}

/// Atomically shrinks the mutable pending-recipient wrapper for one exact
/// outgoing group-content row. The immutable encrypted envelope stays inside
/// the replacement wrapper byte-for-byte; callers validate that relationship
/// before reaching this DB choke point.
Future<bool> dbReplaceGroupInboxRetryPayloadIfExact(
  Database db,
  Map<String, Object?> expected,
  String replacement,
) async {
  try {
    return await dbWriteTransaction(db, (txn) async {
      final messageId = expected['id'] as String? ?? '';
      final groupId = expected['group_id'] as String? ?? '';
      final previous = expected['inbox_retry_payload'] as String? ?? '';
      ProtectedGroupContentRetryManifest previousManifest;
      ProtectedGroupContentRetryManifest replacementManifest;
      try {
        previousManifest = ProtectedGroupContentRetryManifest.decode(previous);
        replacementManifest = ProtectedGroupContentRetryManifest.decode(
          replacement,
        );
      } on Object {
        return false;
      }
      if (messageId.isEmpty ||
          groupId.isEmpty ||
          previous.isEmpty ||
          replacement.isEmpty ||
          !_isExactStrictRetryRecipientShrink(previous, replacement) ||
          !await dbAllowsOrdinaryGroupWrite(txn, groupId)) {
        return false;
      }
      final hasProtectedMedia = previousManifest.mediaManifest != null;
      if (hasProtectedMedia != (replacementManifest.mediaManifest != null)) {
        return false;
      }
      if (!hasProtectedMedia &&
          await dbHasMediaAttachmentForProtectedGroupMessage(txn, messageId)) {
        return false;
      }
      final rows = await txn.query(
        'group_messages',
        where: 'id = ?',
        whereArgs: [messageId],
        limit: 1,
      );
      if (rows.isEmpty ||
          !_sameGroupOutgoingRetryAuthority(rows.single, expected)) {
        return false;
      }
      _ExactProtectedGroupMediaAuthority? exactMedia;
      Set<String> removedRecipients = const <String>{};
      if (hasProtectedMedia) {
        exactMedia = await _loadExactProtectedGroupMediaAuthority(
          txn,
          retryManifest: previousManifest,
          expectedParent: expected,
          recipientsRequiringStoredRows: previousManifest
              .pendingRecipientPeerIds
              .toSet(),
        );
        if (exactMedia == null) return false;
        removedRecipients = previousManifest.pendingRecipientPeerIds
            .toSet()
            .difference(replacementManifest.pendingRecipientPeerIds.toSet());
        if (removedRecipients.length != 1 ||
            !await _moveProtectedGroupMediaRowsToCleanupPending(
              txn,
              rows: exactMedia.custodyRows,
              recipientPeerIds: removedRecipients,
            )) {
          throw const _GroupContentOwnerCasMiss();
        }
      }
      final count = await txn.rawUpdate(
        'UPDATE group_messages SET inbox_retry_payload = ? '
        'WHERE id = ? AND group_id = ? AND is_incoming = 0 '
        "AND status != 'send_failed' AND inbox_stored = 0 "
        'AND inbox_retry_payload = ?',
        [replacement, messageId, groupId, previous],
      );
      if (count != 1) {
        if (hasProtectedMedia) throw const _GroupContentOwnerCasMiss();
        return false;
      }
      if (hasProtectedMedia) {
        final replacementExpected = Map<String, Object?>.from(expected)
          ..['inbox_retry_payload'] = replacement;
        final readback = await txn.query(
          'group_messages',
          where: 'id = ? AND group_id = ?',
          whereArgs: <Object?>[messageId, groupId],
          limit: 1,
        );
        if (readback.isEmpty ||
            !_sameGroupOutgoingRetryAuthority(
              readback.single,
              replacementExpected,
            ) ||
            await _loadExactProtectedGroupMediaAuthority(
                  txn,
                  retryManifest: replacementManifest,
                  expectedParent: replacementExpected,
                  recipientsRequiringStoredRows: replacementManifest
                      .pendingRecipientPeerIds
                      .toSet(),
                ) ==
                null) {
          throw const _GroupContentOwnerCasMiss();
        }
      }
      return true;
    });
  } on _GroupContentOwnerCasMiss {
    return false;
  }
}

/// Atomically commits custody for one exact group inbox-retry tuple.
///
/// The group predicate and complete message fingerprint are evaluated inside
/// the same SQL transaction as the three-field completion. A B3 terminal row
/// (or the same row observed after accepted re-entry) cannot be revived by a
/// response that belongs to the earlier membership window.
Future<bool> dbCompleteGroupInboxStoreRetry(
  Database db,
  Map<String, Object?> expected,
) {
  return dbWriteTransaction(db, (txn) async {
    final messageId = expected['id'] as String? ?? '';
    final groupId = expected['group_id'] as String? ?? '';
    if (messageId.isEmpty ||
        groupId.isEmpty ||
        !await dbAllowsOrdinaryGroupWrite(txn, groupId)) {
      return false;
    }
    final rows = await txn.query(
      'group_messages',
      where: 'id = ?',
      whereArgs: [messageId],
      limit: 1,
    );
    if (rows.isEmpty ||
        !_sameGroupOutgoingRetryAuthority(rows.single, expected)) {
      return false;
    }
    final count = await txn.rawUpdate(
      "UPDATE group_messages SET inbox_stored = 1, "
      "inbox_retry_payload = NULL, status = 'sent' "
      "WHERE id = ? AND group_id = ? AND is_incoming = 0 "
      "AND status != 'send_failed' AND inbox_stored = 0 "
      'AND inbox_retry_payload = ?',
      [messageId, groupId, expected['inbox_retry_payload']],
    );
    return count == 1;
  });
}

class _GroupContentOwnerCasMiss implements Exception {
  const _GroupContentOwnerCasMiss();
}

/// Atomically records the protected-content event fact and completes the exact
/// outgoing message row that owns it.
///
/// A thrown private sentinel is intentional: returning `false` from inside the
/// transaction would commit event/projection work even when the final owner
/// CAS lost a race. Catching it outside the transaction turns that rollback
/// into the public typed no-op expected by callers.
Future<bool> dbCompleteGroupContentInboxStoreRetryIfExact(
  Database db, {
  required Map<String, Object?> expected,
  required String sourcePeerId,
  required String sourceEventId,
  required String sourceTimestamp,
  required Map<String, Object?> eventPayload,
}) async {
  try {
    return await dbWriteTransaction(db, (txn) async {
      final messageId = expected['id'] as String? ?? '';
      final groupId = expected['group_id'] as String? ?? '';
      if (messageId.isEmpty ||
          groupId.isEmpty ||
          !await dbAllowsOrdinaryGroupWrite(txn, groupId)) {
        return false;
      }
      final rows = await txn.query(
        'group_messages',
        where: 'id = ?',
        whereArgs: <Object?>[messageId],
        limit: 1,
      );
      if (rows.isEmpty ||
          !_sameGroupOutgoingRetryAuthority(rows.single, expected)) {
        return false;
      }
      final retryWrapper = rows.single['inbox_retry_payload'] as String? ?? '';
      late final ProtectedGroupContentRetryManifest retryManifest;
      try {
        // The decoder revalidates the immutable signed envelope/full ACL. This
        // transaction may retire only the one mutable recipient represented by
        // the final accepted receipt.
        retryManifest = ProtectedGroupContentRetryManifest.decode(retryWrapper);
        if (retryManifest.groupId != groupId ||
            retryManifest.payloadType !=
                protectedGroupContentMessagePayloadType ||
            retryManifest.contentEventId != messageId ||
            retryManifest.pendingRecipientPeerIds.length != 1) {
          return false;
        }
      } catch (_) {
        return false;
      }
      if (!await dbHasExactProtectedGroupContentPreparedOwner(
        txn,
        groupId: groupId,
        payloadType: protectedGroupContentMessagePayloadType,
        contentEventId: messageId,
        ownerKind: 'group_message',
        ownerId: messageId,
        ownerStatus: expected['status'] as String? ?? '',
        retryWrapper: retryWrapper,
        eventPayload: eventPayload,
      )) {
        return false;
      }
      if (await dbHasProtectedGroupContentTerminalInTransaction(
        txn,
        groupId: groupId,
        payloadType: 'group_message',
        contentEventId: messageId,
      )) {
        return false;
      }

      final hasProtectedMedia = retryManifest.mediaManifest != null;
      if (hasProtectedMedia) {
        final exactMedia = await _loadExactProtectedGroupMediaAuthority(
          txn,
          retryManifest: retryManifest,
          expectedParent: expected,
          recipientsRequiringStoredRows: retryManifest.pendingRecipientPeerIds
              .toSet(),
        );
        if (exactMedia == null) return false;
        await dbAppendGroupEventLogEntryInTransaction(
          txn,
          groupId: groupId,
          eventType: protectedGroupMessageEventType,
          sourcePeerId: sourcePeerId,
          sourceEventId: sourceEventId,
          sourceTimestamp: sourceTimestamp,
          payload: eventPayload,
        );
        if (!await _moveProtectedGroupMediaRowsToCleanupPending(
          txn,
          rows: exactMedia.custodyRows,
          recipientPeerIds: retryManifest.pendingRecipientPeerIds.toSet(),
        )) {
          throw const _GroupContentOwnerCasMiss();
        }
      } else {
        final committed = await dbCommitProtectedGroupMessageInTransaction(
          txn,
          groupId: groupId,
          sourcePeerId: sourcePeerId,
          sourceEventId: sourceEventId,
          sourceTimestamp: sourceTimestamp,
          eventPayload: eventPayload,
          messageRow: expected,
        );
        if (committed ==
            DbProtectedGroupContentCommitResult.prerequisiteMissing) {
          return false;
        }
      }

      final count = await txn.rawUpdate(
        "UPDATE group_messages SET inbox_stored = 1, "
        "wire_envelope = NULL, inbox_retry_payload = NULL, status = 'sent' "
        "WHERE id = ? AND group_id = ? AND is_incoming = 0 "
        "AND status != 'send_failed' AND inbox_stored = 0 "
        'AND inbox_retry_payload = ?',
        <Object?>[messageId, groupId, retryWrapper],
      );
      if (count != 1) throw const _GroupContentOwnerCasMiss();

      final terminal = Map<String, Object?>.from(expected)
        ..['status'] = 'sent'
        ..['wire_envelope'] = null
        ..['inbox_stored'] = 1
        ..['inbox_retry_payload'] = null;
      final readback = await txn.query(
        'group_messages',
        where: 'id = ?',
        whereArgs: <Object?>[messageId],
        limit: 1,
      );
      if (readback.isEmpty ||
          !_sameGroupOutgoingRetryAuthority(readback.single, terminal)) {
        throw StateError('protected message completion readback failed');
      }
      return true;
    }, exclusive: true);
  } on _GroupContentOwnerCasMiss {
    return false;
  }
}

/// Atomically creates and terminally completes a zero-target protected message.
/// No queued owner can survive without its protected event/projection evidence.
Future<bool> dbStageAndCompleteLocalGroupContentMessage(
  Database db, {
  required Map<String, Object?> expected,
  required String sourcePeerId,
  required String sourceEventId,
  required String sourceTimestamp,
  required Map<String, Object?> eventPayload,
}) async {
  try {
    return await dbWriteTransaction(db, (txn) async {
      final messageId = expected['id'] as String? ?? '';
      final groupId = expected['group_id'] as String? ?? '';
      final plaintext = _protectedMediaStringMap(eventPayload['payload']);
      final declaresMedia =
          plaintext?.containsKey('mediaManifest') == true ||
          plaintext?.containsKey('mediaManifestHash') == true;
      if (messageId.isEmpty ||
          groupId.isEmpty ||
          expected['is_incoming'] != 0 ||
          expected['inbox_stored'] != 0 ||
          expected['inbox_retry_payload'] != null ||
          !await dbAllowsOrdinaryGroupWrite(txn, groupId)) {
        return false;
      }
      final terminal = Map<String, Object?>.from(expected)
        ..['status'] = 'sent'
        ..['wire_envelope'] = null
        ..['inbox_stored'] = 1
        ..['inbox_retry_payload'] = null;
      var rows = await txn.query(
        'group_messages',
        where: 'id = ?',
        whereArgs: <Object?>[messageId],
        limit: 1,
      );
      if (rows.isEmpty) {
        if (declaresMedia) return false;
        final insertRow = Map<String, Object?>.from(expected)
          ..remove('retry_attempt_count')
          ..remove('next_eligible_at');
        if (!await dbInsertGroupMessage(txn, insertRow)) return false;
        rows = await txn.query(
          'group_messages',
          where: 'id = ?',
          whereArgs: <Object?>[messageId],
          limit: 1,
        );
      }
      if (rows.isEmpty) return false;
      var current = rows.single;
      var alreadyTerminal = _sameGroupOutgoingRetryAuthority(current, terminal);
      if (declaresMedia &&
          !alreadyTerminal &&
          !_sameGroupOutgoingRetryAuthority(current, expected)) {
        if (!_sameGroupOutgoingZeroTargetBlobPendingAuthority(
          current,
          expected,
        )) {
          return false;
        }
        final promoted = await txn.rawUpdate(
          'UPDATE group_messages SET last_send_attempt_at = ?, '
          'wire_envelope = ? WHERE id = ? AND group_id = ? '
          'AND is_incoming = 0 AND inbox_stored = 0 '
          'AND wire_envelope IS NULL AND inbox_retry_payload IS NULL',
          <Object?>[
            expected['last_send_attempt_at'],
            expected['wire_envelope'],
            messageId,
            groupId,
          ],
        );
        if (promoted != 1) throw const _GroupContentOwnerCasMiss();
        rows = await txn.query(
          'group_messages',
          where: 'id = ? AND group_id = ?',
          whereArgs: <Object?>[messageId, groupId],
          limit: 1,
        );
        if (rows.isEmpty) throw const _GroupContentOwnerCasMiss();
        current = rows.single;
        alreadyTerminal = _sameGroupOutgoingRetryAuthority(current, terminal);
      }
      if (!alreadyTerminal &&
          !_sameGroupOutgoingRetryAuthority(current, expected)) {
        return false;
      }
      if (declaresMedia) {
        final exactMedia =
            await _loadExactZeroTargetProtectedGroupMediaAuthority(
              txn,
              groupId: groupId,
              messageId: messageId,
              expectedParent: expected,
              eventPayload: eventPayload,
            );
        if (exactMedia == null || exactMedia.custodyRows.isNotEmpty) {
          throw const _GroupContentOwnerCasMiss();
        }
        await dbAppendGroupEventLogEntryInTransaction(
          txn,
          groupId: groupId,
          eventType: protectedGroupMessageEventType,
          sourcePeerId: sourcePeerId,
          sourceEventId: sourceEventId,
          sourceTimestamp: sourceTimestamp,
          payload: eventPayload,
        );
      } else {
        final committed = await dbCommitProtectedGroupMessageInTransaction(
          txn,
          groupId: groupId,
          sourcePeerId: sourcePeerId,
          sourceEventId: sourceEventId,
          sourceTimestamp: sourceTimestamp,
          eventPayload: eventPayload,
          messageRow: alreadyTerminal ? terminal : expected,
        );
        if (committed ==
            DbProtectedGroupContentCommitResult.prerequisiteMissing) {
          return false;
        }
      }
      if (!alreadyTerminal) {
        final updated = await txn.rawUpdate(
          "UPDATE group_messages SET status = 'sent', inbox_stored = 1, "
          'wire_envelope = NULL, inbox_retry_payload = NULL '
          'WHERE id = ? AND group_id = ? '
          'AND is_incoming = 0 AND inbox_stored = 0 '
          'AND inbox_retry_payload IS NULL AND status = ?',
          <Object?>[messageId, groupId, expected['status']],
        );
        if (updated != 1) throw const _GroupContentOwnerCasMiss();
      }
      final readback = await txn.query(
        'group_messages',
        where: 'id = ?',
        whereArgs: <Object?>[messageId],
        limit: 1,
      );
      if (readback.isEmpty ||
          !_sameGroupOutgoingRetryAuthority(readback.single, terminal)) {
        throw StateError('protected local message terminal readback failed');
      }
      return true;
    }, exclusive: true);
  } on _GroupContentOwnerCasMiss {
    return false;
  }
}

Future<bool> dbStagePreparedLocalGroupContentMessage(
  Database db, {
  required Map<String, Object?> expected,
  required String sourcePeerId,
  required String sourceEventId,
  required String sourceTimestamp,
  required Map<String, Object?> preparedEventPayload,
}) {
  return dbWriteTransaction(db, (txn) async {
    final messageId = expected['id'] as String? ?? '';
    final groupId = expected['group_id'] as String? ?? '';
    final retryPayload = expected['inbox_retry_payload'] as String? ?? '';
    ProtectedGroupContentRetryManifest retryManifest;
    try {
      retryManifest = ProtectedGroupContentRetryManifest.decode(retryPayload);
    } on Object {
      return false;
    }
    final hasProtectedMedia = retryManifest.mediaManifest != null;
    if (messageId.isEmpty ||
        groupId.isEmpty ||
        retryPayload.isEmpty ||
        retryManifest.groupId != groupId ||
        retryManifest.contentEventId != messageId ||
        retryManifest.payloadType != protectedGroupContentMessagePayloadType ||
        expected['is_incoming'] != 0 ||
        expected['inbox_stored'] != 0 ||
        !sourceEventId.startsWith('ppm1:') ||
        !await dbAllowsOrdinaryGroupWrite(txn, groupId)) {
      return false;
    }
    if (!hasProtectedMedia &&
        await dbHasMediaAttachmentForProtectedGroupMessage(txn, messageId)) {
      // Preserve the Plan-364 blob-free no-demotion guard byte-for-byte.
      return false;
    }
    if (!isExactProtectedGroupContentPreparedStage(
      groupId: groupId,
      payloadType: 'group_message',
      contentEventId: messageId,
      ownerKind: 'group_message',
      ownerId: messageId,
      ownerStatus: expected['status'] as String? ?? '',
      retryWrapper: retryPayload,
      sourcePeerId: sourcePeerId,
      sourceEventId: sourceEventId,
      sourceTimestamp: sourceTimestamp,
      preparedEventPayload: preparedEventPayload,
    )) {
      return false;
    }
    final preparedPlaintext = preparedEventPayload['payload'];
    if (preparedPlaintext is! Map ||
        !_isExactProtectedPreparedMessageOwner(expected, preparedPlaintext)) {
      return false;
    }
    var rows = await txn.query(
      'group_messages',
      where: 'id = ?',
      whereArgs: <Object?>[messageId],
      limit: 1,
    );
    if (rows.isEmpty) {
      if (hasProtectedMedia) {
        // Strict group media must already own its parent, descriptors and
        // target-qualified stored blob rows before content can be armed.
        return false;
      }
      final insertRow = Map<String, Object?>.from(expected)
        ..remove('retry_attempt_count')
        ..remove('next_eligible_at');
      if (!await dbInsertGroupMessage(txn, insertRow)) return false;
      rows = await txn.query(
        'group_messages',
        where: 'id = ?',
        whereArgs: <Object?>[messageId],
        limit: 1,
      );
    }
    if (rows.isEmpty) {
      return false;
    }
    if (hasProtectedMedia) {
      final exactMedia = await _loadExactProtectedGroupMediaAuthority(
        txn,
        retryManifest: retryManifest,
        expectedParent: expected,
        recipientsRequiringStoredRows: retryManifest.pendingRecipientPeerIds
            .toSet(),
      );
      if (exactMedia == null) return false;
      final current = rows.single;
      if (!_sameGroupOutgoingRetryAuthority(current, expected)) {
        if (!_sameGroupOutgoingBlobPendingAuthority(current, expected)) {
          return false;
        }
        final promoted = await txn.rawUpdate(
          'UPDATE group_messages SET last_send_attempt_at = ?, '
          'wire_envelope = ?, inbox_retry_payload = ? '
          'WHERE id = ? AND group_id = ? '
          'AND is_incoming = 0 AND inbox_stored = 0 '
          'AND wire_envelope IS NULL AND inbox_retry_payload IS NULL',
          <Object?>[
            expected['last_send_attempt_at'],
            expected['wire_envelope'],
            retryPayload,
            messageId,
            groupId,
          ],
        );
        if (promoted != 1) return false;
        rows = await txn.query(
          'group_messages',
          where: 'id = ? AND group_id = ?',
          whereArgs: <Object?>[messageId, groupId],
          limit: 1,
        );
      }
    }
    if (rows.isEmpty ||
        !_sameGroupOutgoingRetryAuthority(rows.single, expected)) {
      return false;
    }
    await dbAppendGroupEventLogEntryInTransaction(
      txn,
      groupId: groupId,
      eventType: protectedGroupContentPreparedEventType,
      sourcePeerId: sourcePeerId,
      sourceEventId: sourceEventId,
      sourceTimestamp: sourceTimestamp,
      payload: preparedEventPayload,
    );
    return true;
  }, exclusive: true);
}

bool _isExactProtectedPreparedMessageOwner(
  Map<String, Object?> expected,
  Map<Object?, Object?> payload,
) {
  final rowTimestamp = expected['timestamp'];
  final payloadTimestamp = payload['timestamp'];
  final rowAt = rowTimestamp is String ? DateTime.tryParse(rowTimestamp) : null;
  final payloadAt = payloadTimestamp is String
      ? DateTime.tryParse(payloadTimestamp)
      : null;
  return expected['id'] == payload['messageId'] &&
      expected['group_id'] == payload['groupId'] &&
      expected['sender_peer_id'] == payload['senderId'] &&
      expected['transport_peer_id'] == payload['transportPeerId'] &&
      expected['sender_username'] == payload['senderUsername'] &&
      expected['text'] == payload['text'] &&
      expected['logical_delivery_id'] == payload['logicalDeliveryId'] &&
      expected['key_generation'] == payload['keyEpoch'] &&
      expected['quoted_message_id'] == payload['quotedMessageId'] &&
      (expected['is_forwarded'] as num?)?.toInt() ==
          (payload['isForwarded'] == true ? 1 : 0) &&
      (expected['media_policy_version'] as num?)?.toInt() == 0 &&
      rowAt != null &&
      payloadAt != null &&
      rowAt.toUtc() == payloadAt.toUtc();
}

final class _ProtectedGroupMediaTargetProjection {
  const _ProtectedGroupMediaTargetProjection({
    required this.recipientPeerId,
    required this.custodyKind,
    required this.custodyContract,
    required this.expiresAtMs,
  });

  final String recipientPeerId;
  final String custodyKind;
  final String custodyContract;
  final int expiresAtMs;

  Map<String, Object?> toJson() => <String, Object?>{
    'custodyKind': custodyKind,
    'custodyContract': custodyContract,
    'expiresAtMs': expiresAtMs,
  };
}

final class _ProtectedGroupMediaAttachmentProjection {
  const _ProtectedGroupMediaAttachmentProjection({
    required this.attachmentId,
    required this.custodyBlobId,
    required this.ciphertextSha256,
    required this.ciphertextSize,
    required this.mime,
    required this.mediaType,
    required this.width,
    required this.height,
    required this.durationMs,
    required this.waveform,
    required this.encryptionScheme,
    required this.encryptionKeyBase64,
    required this.encryptionNonce,
    required this.caption,
    required this.targets,
  });

  final String attachmentId;
  final String custodyBlobId;
  final String ciphertextSha256;
  final int ciphertextSize;
  final String mime;
  final String mediaType;
  final int? width;
  final int? height;
  final int? durationMs;
  final List<Object?> waveform;
  final String encryptionScheme;
  final String encryptionKeyBase64;
  final String encryptionNonce;
  final String? caption;
  final List<_ProtectedGroupMediaTargetProjection> targets;

  Map<String, Object?> toJson() => <String, Object?>{
    'attachmentId': attachmentId,
    'custodyBlobId': custodyBlobId,
    'ciphertextSha256': ciphertextSha256,
    'ciphertextSize': ciphertextSize,
    'mime': mime,
    'mediaType': mediaType,
    if (width != null) 'width': width,
    if (height != null) 'height': height,
    if (durationMs != null) 'durationMs': durationMs,
    if (waveform.isNotEmpty) 'waveform': waveform,
    'encryptionScheme': encryptionScheme,
    'encryptionKeyBase64': encryptionKeyBase64,
    'encryptionNonce': encryptionNonce,
    if (caption != null) 'caption': caption,
    'expiresAtMs': targets.map((target) => target.expiresAtMs).toList(),
  };
}

final class _ProtectedGroupMediaProjection {
  const _ProtectedGroupMediaProjection({
    required this.groupId,
    required this.messageId,
    required this.recipientPeerIds,
    required this.attachments,
  });

  final String groupId;
  final String messageId;
  final List<String> recipientPeerIds;
  final List<_ProtectedGroupMediaAttachmentProjection> attachments;

  Map<String, Object?> toJson() => <String, Object?>{
    'schema': 'group_media_manifest_v1',
    'groupId': groupId,
    'messageId': messageId,
    'custodyKind': kGroupMediaBlobCustodyKind,
    'custodyContract': kDirectMediaBlobCustodyContract,
    'recipientPeerIds': recipientPeerIds,
    'attachments': attachments.map((entry) => entry.toJson()).toList(),
  };
}

final class _ExactProtectedGroupMediaAuthority {
  const _ExactProtectedGroupMediaAuthority({
    required this.projection,
    required this.custodyRows,
  });

  final _ProtectedGroupMediaProjection projection;
  final List<DirectMediaBlobCustodyRow> custodyRows;
}

const Set<String> _protectedGroupMediaAttachmentRequiredKeys = <String>{
  'attachmentId',
  'custodyBlobId',
  'ciphertextSha256',
  'ciphertextSize',
  'mime',
  'mediaType',
  'encryptionScheme',
  'encryptionKeyBase64',
  'encryptionNonce',
  'expiresAtMs',
};
const Set<String> _protectedGroupMediaAttachmentAllowedKeys = <String>{
  ..._protectedGroupMediaAttachmentRequiredKeys,
  'width',
  'height',
  'durationMs',
  'waveform',
  'caption',
};
final RegExp _protectedGroupMediaSha256 = RegExp(r'^[0-9a-f]{64}$');
final RegExp _protectedGroupMediaBlobId = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

_ProtectedGroupMediaProjection? _parseProtectedGroupMediaProjection({
  required ProtectedGroupContentRetryManifest retryManifest,
}) {
  final raw = retryManifest.mediaManifest;
  if (raw == null || retryManifest.mediaManifestHash == null) return null;
  try {
    final decoded = jsonDecode(raw);
    final manifest = _protectedMediaStringMap(decoded);
    if (manifest == null ||
        !_sameProtectedMediaKeys(manifest, const <String>{
          'schema',
          'groupId',
          'messageId',
          'custodyKind',
          'custodyContract',
          'recipientPeerIds',
          'attachments',
        }) ||
        manifest['schema'] != 'group_media_manifest_v1' ||
        manifest['groupId'] != retryManifest.groupId ||
        manifest['messageId'] != retryManifest.contentEventId ||
        manifest['custodyKind'] != kGroupMediaBlobCustodyKind ||
        manifest['custodyContract'] != kDirectMediaBlobCustodyContract ||
        manifest['recipientPeerIds'] is! List ||
        manifest['attachments'] is! List) {
      return null;
    }
    final rawRecipientPeerIds = manifest['recipientPeerIds'] as List;
    if (rawRecipientPeerIds.any((value) => value is! String)) return null;
    final targetRecipients = rawRecipientPeerIds.cast<String>();
    final sortedRecipients = targetRecipients.toList()..sort();
    if (!_sameProtectedMediaStrings(targetRecipients, sortedRecipients) ||
        !_sameProtectedMediaStrings(
          targetRecipients,
          retryManifest.fullRecipientPeerIds,
        ) ||
        targetRecipients.any(
          (recipientPeerId) => _protectedMediaString(recipientPeerId) == null,
        )) {
      return null;
    }
    final rawAttachments = manifest['attachments'] as List;
    if (rawAttachments.isEmpty) return null;
    final attachments = <_ProtectedGroupMediaAttachmentProjection>[];
    final attachmentIds = <String>{};
    final custodyBlobIds = <String>{};
    String? previousAttachmentId;
    for (final rawAttachment in rawAttachments) {
      final attachment = _protectedMediaStringMap(rawAttachment);
      if (attachment == null ||
          attachment.keys.any(
            (key) => !_protectedGroupMediaAttachmentAllowedKeys.contains(key),
          ) ||
          !_protectedGroupMediaAttachmentRequiredKeys.every(
            attachment.containsKey,
          )) {
        return null;
      }
      final attachmentId = _protectedMediaString(attachment['attachmentId']);
      final custodyBlobId = _protectedMediaString(attachment['custodyBlobId']);
      final ciphertextSha256 = _protectedMediaString(
        attachment['ciphertextSha256'],
      );
      final ciphertextSize = attachment['ciphertextSize'];
      final mime = _protectedMediaString(attachment['mime']);
      final mediaType = _protectedMediaString(attachment['mediaType']);
      final encryptionScheme = _protectedMediaString(
        attachment['encryptionScheme'],
      );
      final encryptionKeyBase64 = _protectedMediaString(
        attachment['encryptionKeyBase64'],
      );
      final encryptionNonce = _protectedMediaString(
        attachment['encryptionNonce'],
      );
      final width = attachment['width'];
      final height = attachment['height'];
      final durationMs = attachment['durationMs'];
      final rawWaveform = attachment['waveform'];
      final caption = attachment['caption'];
      final rawExpiries = attachment['expiresAtMs'];
      if (attachmentId == null ||
          custodyBlobId == null ||
          ciphertextSha256 == null ||
          ciphertextSize is! int ||
          ciphertextSize <= 16 ||
          mime == null ||
          !RegExp(r'^[^/\s]+/[^/\s]+$').hasMatch(mime) ||
          mediaType == null ||
          encryptionScheme != 'blob_aes_256_gcm_v1' ||
          encryptionKeyBase64 == null ||
          encryptionNonce == null ||
          !_protectedGroupMediaSha256.hasMatch(ciphertextSha256) ||
          !_protectedGroupMediaBlobId.hasMatch(custodyBlobId) ||
          (width != null && (width is! int || width <= 0)) ||
          (height != null && (height is! int || height <= 0)) ||
          (durationMs != null && (durationMs is! int || durationMs < 0)) ||
          (caption != null && _protectedMediaString(caption) == null) ||
          (rawWaveform != null && rawWaveform is! List) ||
          rawExpiries is! List ||
          rawExpiries.length != targetRecipients.length ||
          !attachmentIds.add(attachmentId) ||
          !custodyBlobIds.add(custodyBlobId) ||
          (previousAttachmentId != null &&
              previousAttachmentId.compareTo(attachmentId) >= 0)) {
        return null;
      }
      previousAttachmentId = attachmentId;
      final waveform = rawWaveform == null
          ? const <Object?>[]
          : List<Object?>.from(rawWaveform as List);
      if (waveform.any((sample) => sample is! num || !sample.isFinite)) {
        return null;
      }
      final targets = <_ProtectedGroupMediaTargetProjection>[];
      for (var index = 0; index < targetRecipients.length; index++) {
        final recipientPeerId = targetRecipients[index];
        final expiresAtMs = rawExpiries[index];
        if (expiresAtMs is! int || expiresAtMs <= 0) {
          return null;
        }
        targets.add(
          _ProtectedGroupMediaTargetProjection(
            recipientPeerId: recipientPeerId,
            custodyKind: kGroupMediaBlobCustodyKind,
            custodyContract: kDirectMediaBlobCustodyContract,
            expiresAtMs: expiresAtMs,
          ),
        );
      }
      attachments.add(
        _ProtectedGroupMediaAttachmentProjection(
          attachmentId: attachmentId,
          custodyBlobId: custodyBlobId,
          ciphertextSha256: ciphertextSha256,
          ciphertextSize: ciphertextSize,
          mime: mime,
          mediaType: mediaType,
          width: width as int?,
          height: height as int?,
          durationMs: durationMs as int?,
          waveform: waveform,
          encryptionScheme: encryptionScheme as String,
          encryptionKeyBase64: encryptionKeyBase64,
          encryptionNonce: encryptionNonce,
          caption: caption as String?,
          targets: List<_ProtectedGroupMediaTargetProjection>.unmodifiable(
            targets,
          ),
        ),
      );
    }
    final projection = _ProtectedGroupMediaProjection(
      groupId: retryManifest.groupId,
      messageId: retryManifest.contentEventId,
      recipientPeerIds: List<String>.unmodifiable(targetRecipients),
      attachments: List<_ProtectedGroupMediaAttachmentProjection>.unmodifiable(
        attachments,
      ),
    );
    return jsonEncode(projection.toJson()) == raw ? projection : null;
  } on Object {
    return null;
  }
}

Future<_ExactProtectedGroupMediaAuthority?>
_loadExactProtectedGroupMediaAuthority(
  DatabaseExecutor txn, {
  required ProtectedGroupContentRetryManifest retryManifest,
  required Map<String, Object?> expectedParent,
  required Set<String> recipientsRequiringStoredRows,
}) async {
  final projection = _parseProtectedGroupMediaProjection(
    retryManifest: retryManifest,
  );
  if (projection == null ||
      !retryManifest.fullRecipientPeerIds.toSet().containsAll(
        recipientsRequiringStoredRows,
      )) {
    return null;
  }
  final attachmentRows = await txn.query(
    'media_attachments',
    where: 'message_id = ? AND owner_lane = ?',
    whereArgs: <Object?>[projection.messageId, 'group'],
  );
  if (attachmentRows.length != projection.attachments.length) return null;
  final attachmentById = <String, Map<String, Object?>>{
    for (final row in attachmentRows) row['id']! as String: row,
  };
  final expectedCaption =
      (expectedParent['text'] as String?)?.trim().isEmpty == false
      ? expectedParent['text'] as String
      : null;
  for (var index = 0; index < projection.attachments.length; index++) {
    final commitment = projection.attachments[index];
    final row = attachmentById[commitment.attachmentId];
    final fingerprint = computeGroupMediaBlobCustodyFingerprint(
      groupId: projection.groupId,
      messageId: projection.messageId,
      attachmentId: commitment.attachmentId,
      custodyBlobId: commitment.custodyBlobId,
      contentHash: commitment.ciphertextSha256,
      ciphertextSize: commitment.ciphertextSize,
      recipientPeerIds: commitment.targets.map(
        (target) => target.recipientPeerId,
      ),
    );
    if (row == null ||
        row['message_id'] != projection.messageId ||
        row['owner_lane'] != 'group' ||
        row['mime'] != commitment.mime ||
        (row['size'] as num?)?.toInt() != commitment.ciphertextSize - 16 ||
        row['media_type'] != commitment.mediaType ||
        row['width'] != commitment.width ||
        row['height'] != commitment.height ||
        row['duration_ms'] != commitment.durationMs ||
        row['waveform'] !=
            (commitment.waveform.isEmpty
                ? null
                : jsonEncode(commitment.waveform)) ||
        row['content_hash'] != commitment.ciphertextSha256 ||
        row['encryption_key_base64'] != commitment.encryptionKeyBase64 ||
        row['encryption_nonce'] != commitment.encryptionNonce ||
        row['encryption_scheme'] != commitment.encryptionScheme ||
        row['group_media_blob_custody_fingerprint'] != fingerprint ||
        commitment.caption != (index == 0 ? expectedCaption : null)) {
      return null;
    }
  }

  final custodyRows = await dbLoadGroupMediaBlobCustodyForMessage(
    txn,
    groupId: projection.groupId,
    messageId: projection.messageId,
  );
  final expectedTargets = <String, _ProtectedGroupMediaTargetProjection>{};
  final attachmentForTarget =
      <String, _ProtectedGroupMediaAttachmentProjection>{};
  for (final attachment in projection.attachments) {
    for (final target in attachment.targets) {
      final key = _protectedGroupMediaTargetKey(
        attachment.attachmentId,
        target.recipientPeerId,
      );
      expectedTargets[key] = target;
      attachmentForTarget[key] = attachment;
    }
  }
  final foundStored = <String>{};
  final foundRows = <String>{};
  for (final row in custodyRows) {
    final recipient = row.recipientPeerId;
    if (row.ownerLane != MediaBlobCustodyOwnerLane.group ||
        row.groupId != projection.groupId ||
        row.messageId != projection.messageId ||
        row.direction != DirectMediaBlobCustodyDirection.outgoing ||
        recipient == null) {
      return null;
    }
    final key = _protectedGroupMediaTargetKey(row.attachmentId, recipient);
    final target = expectedTargets[key];
    final attachment = attachmentForTarget[key];
    if (target == null || attachment == null || !foundRows.add(key)) {
      return null;
    }
    final requiresStored = recipientsRequiringStoredRows.contains(recipient);
    if (row.custodyBlobId != attachment.custodyBlobId ||
        row.custodyKind != target.custodyKind ||
        row.custodyContract != target.custodyContract ||
        row.contentHash != attachment.ciphertextSha256 ||
        row.ciphertextSize != attachment.ciphertextSize ||
        row.transportMime != kDirectMediaBlobTransportMime ||
        row.expiresAtMs != target.expiresAtMs ||
        row.inboxCustodyIncarnationId != null ||
        row.state !=
            (requiresStored
                ? DirectMediaBlobCustodyState.outgoingStored
                : DirectMediaBlobCustodyState.outgoingCleanupPending)) {
      return null;
    }
    if (requiresStored) foundStored.add(key);
  }
  for (final entry in expectedTargets.entries) {
    if (recipientsRequiringStoredRows.contains(entry.value.recipientPeerId) &&
        !foundStored.contains(entry.key)) {
      return null;
    }
  }
  return _ExactProtectedGroupMediaAuthority(
    projection: projection,
    custodyRows: List<DirectMediaBlobCustodyRow>.unmodifiable(custodyRows),
  );
}

Future<_ExactProtectedGroupMediaAuthority?>
_loadExactZeroTargetProtectedGroupMediaAuthority(
  DatabaseExecutor txn, {
  required String groupId,
  required String messageId,
  required Map<String, Object?> expectedParent,
  required Map<String, Object?> eventPayload,
}) async {
  final plaintext = _protectedMediaStringMap(eventPayload['payload']);
  final rawManifest = plaintext?['mediaManifest'];
  final manifestHash = plaintext?['mediaManifestHash'];
  if (plaintext == null ||
      rawManifest is! String ||
      manifestHash is! String ||
      !_protectedGroupMediaSha256.hasMatch(manifestHash) ||
      sha256.convert(utf8.encode(rawManifest)).toString() != manifestHash ||
      eventPayload['groupId'] != groupId ||
      eventPayload['contentEventId'] != messageId ||
      eventPayload['payloadType'] != protectedGroupContentMessagePayloadType ||
      eventPayload['recipientPeerIds'] is! List ||
      (eventPayload['recipientPeerIds'] as List).isNotEmpty ||
      plaintext['groupId'] != groupId ||
      plaintext['messageId'] != messageId ||
      plaintext['recipientPeerIds'] is! List ||
      (plaintext['recipientPeerIds'] as List).isNotEmpty) {
    return null;
  }
  final synthetic = ProtectedGroupContentRetryManifest(
    groupId: groupId,
    replayEnvelope: '__local_zero_target__',
    contentEventId: messageId,
    payloadType: protectedGroupContentMessagePayloadType,
    pendingRecipientPeerIds: const <String>[],
    fullRecipientPeerIds: const <String>[],
    keyEpoch: (expectedParent['key_generation'] as num?)?.toInt() ?? -1,
    logicalSenderPeerId: expectedParent['sender_peer_id'] as String? ?? '',
    senderDeviceId: eventPayload['senderDeviceId'] as String? ?? '',
    senderTransportPeerId: expectedParent['transport_peer_id'] as String? ?? '',
    senderPublicKey: eventPayload['senderPublicKey'] as String? ?? '',
    plaintextHash: sha256
        .convert(utf8.encode(jsonEncode(plaintext)))
        .toString(),
    reactionTargetMessageId: null,
    reactionAction: null,
    mediaManifest: rawManifest,
    mediaManifestHash: manifestHash,
  );
  return _loadExactProtectedGroupMediaAuthority(
    txn,
    retryManifest: synthetic,
    expectedParent: expectedParent,
    recipientsRequiringStoredRows: const <String>{},
  );
}

Map<String, Object?>? _protectedMediaStringMap(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) return null;
  return value.map<String, Object?>(
    (key, entryValue) => MapEntry(key as String, entryValue),
  );
}

String? _protectedMediaString(Object? value) =>
    value is String && value.isNotEmpty && value.trim() == value ? value : null;

bool _sameProtectedMediaKeys(
  Map<String, Object?> value,
  Set<String> expected,
) =>
    value.length == expected.length && value.keys.toSet().containsAll(expected);

bool _sameProtectedMediaStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

String _protectedGroupMediaTargetKey(
  String attachmentId,
  String recipientPeerId,
) => '$attachmentId\u0000$recipientPeerId';

Future<bool> _moveProtectedGroupMediaRowsToCleanupPending(
  DatabaseExecutor txn, {
  required Iterable<DirectMediaBlobCustodyRow> rows,
  required Set<String> recipientPeerIds,
}) async {
  for (final current in rows) {
    if (!recipientPeerIds.contains(current.recipientPeerId)) continue;
    if (current.state != DirectMediaBlobCustodyState.outgoingStored) {
      return false;
    }
    final changed =
        await dbTransitionGroupMediaBlobCustodyIfExactWithinTransaction(
          txn,
          expected: current,
          next: current.copyWith(
            state: DirectMediaBlobCustodyState.outgoingCleanupPending,
          ),
        );
    if (!changed) return false;
  }
  return true;
}

/// Atomically terminalizes one exact nonempty-ACL protected message owner.
/// The immutable prepared fact is checked in the same transaction as terminal
/// evidence and the owner CAS, so a stale authority can neither resume relay
/// stores nor leave an unaccounted queued row after reconciliation.
Future<bool> dbTerminalizePreparedLocalGroupContentMessageIfExact(
  Database db, {
  required Map<String, Object?> expected,
  required Map<String, Object?> preparedEventPayload,
  required String terminalSourcePeerId,
  required String terminalSourceEventId,
  required String terminalSourceTimestamp,
  required Map<String, Object?> terminalEventPayload,
}) async {
  try {
    return await dbWriteTransaction(
      db,
      (txn) =>
          dbTerminalizePreparedLocalGroupContentMessageIfExactInTransaction(
            txn,
            expected: expected,
            preparedEventPayload: preparedEventPayload,
            terminalSourcePeerId: terminalSourcePeerId,
            terminalSourceEventId: terminalSourceEventId,
            terminalSourceTimestamp: terminalSourceTimestamp,
            terminalEventPayload: terminalEventPayload,
          ),
      exclusive: true,
    );
  } on _GroupContentOwnerCasMiss {
    return false;
  }
}

/// Transaction-scoped form used by authority reconciliation so terminalizing
/// the owner, rolling back invalid success, and advancing its page frontier
/// share one outer commit. A post-evidence CAS miss throws to roll that commit
/// back; precondition misses return false before any write.
Future<bool> dbTerminalizePreparedLocalGroupContentMessageIfExactInTransaction(
  DatabaseExecutor txn, {
  required Map<String, Object?> expected,
  required Map<String, Object?> preparedEventPayload,
  required String terminalSourcePeerId,
  required String terminalSourceEventId,
  required String terminalSourceTimestamp,
  required Map<String, Object?> terminalEventPayload,
}) async {
  final messageId = expected['id'] as String? ?? '';
  final groupId = expected['group_id'] as String? ?? '';
  final retryWrapper = expected['inbox_retry_payload'] as String? ?? '';
  if (messageId.isEmpty ||
      groupId.isEmpty ||
      retryWrapper.isEmpty ||
      expected['is_incoming'] != 0 ||
      expected['inbox_stored'] != 0) {
    return false;
  }
  late final ProtectedGroupContentRetryManifest retryManifest;
  try {
    retryManifest = ProtectedGroupContentRetryManifest.decode(retryWrapper);
  } on Object {
    return false;
  }
  if (retryManifest.groupId != groupId ||
      retryManifest.contentEventId != messageId ||
      retryManifest.payloadType != protectedGroupContentMessagePayloadType) {
    return false;
  }
  final terminal = Map<String, Object?>.from(expected)
    ..['status'] = 'send_failed'
    ..['wire_envelope'] = null
    ..['inbox_retry_payload'] = null;
  final rows = await txn.query(
    'group_messages',
    where: 'id = ? AND group_id = ?',
    whereArgs: <Object?>[messageId, groupId],
    limit: 1,
  );
  if (rows.isEmpty) return false;
  final current = rows.single;
  final alreadyTerminal = _sameGroupOutgoingRetryAuthority(current, terminal);
  if (!alreadyTerminal &&
      !_sameGroupOutgoingRetryAuthority(current, expected)) {
    return false;
  }
  if (!await dbHasExactProtectedGroupContentPreparedOwner(
    txn,
    groupId: groupId,
    payloadType: 'group_message',
    contentEventId: messageId,
    ownerKind: 'group_message',
    ownerId: messageId,
    ownerStatus: expected['status'] as String? ?? '',
    retryWrapper: retryWrapper,
    eventPayload: preparedEventPayload,
  )) {
    return false;
  }
  final hasTerminal = await dbHasProtectedGroupContentTerminalInTransaction(
    txn,
    groupId: groupId,
    payloadType: 'group_message',
    contentEventId: messageId,
  );
  if (hasTerminal) return alreadyTerminal;
  _ExactProtectedGroupMediaAuthority? exactMedia;
  if (retryManifest.mediaManifest != null) {
    exactMedia = await _loadExactProtectedGroupMediaAuthority(
      txn,
      retryManifest: retryManifest,
      expectedParent: expected,
      recipientsRequiringStoredRows: retryManifest.pendingRecipientPeerIds
          .toSet(),
    );
    if (exactMedia == null) return false;
  } else if (await dbHasMediaAttachmentForProtectedGroupMessage(
    txn,
    messageId,
  )) {
    return false;
  }
  await dbCommitProtectedGroupContentTerminalInTransaction(
    txn,
    groupId: groupId,
    sourcePeerId: terminalSourcePeerId,
    sourceEventId: terminalSourceEventId,
    sourceTimestamp: terminalSourceTimestamp,
    eventPayload: terminalEventPayload,
  );
  if (exactMedia != null &&
      !await _moveProtectedGroupMediaRowsToCleanupPending(
        txn,
        rows: exactMedia.custodyRows,
        recipientPeerIds: retryManifest.pendingRecipientPeerIds.toSet(),
      )) {
    throw const _GroupContentOwnerCasMiss();
  }
  if (!alreadyTerminal) {
    final updated = await txn.rawUpdate(
      "UPDATE group_messages SET status = 'send_failed', "
      'wire_envelope = NULL, inbox_retry_payload = NULL '
      'WHERE id = ? AND group_id = ? '
      'AND is_incoming = 0 AND inbox_stored = 0 '
      'AND status = ? AND inbox_retry_payload = ?',
      <Object?>[messageId, groupId, expected['status'], retryWrapper],
    );
    if (updated != 1) throw const _GroupContentOwnerCasMiss();
  }
  final readback = await txn.query(
    'group_messages',
    where: 'id = ? AND group_id = ?',
    whereArgs: <Object?>[messageId, groupId],
    limit: 1,
  );
  if (readback.isEmpty ||
      !_sameGroupOutgoingRetryAuthority(readback.single, terminal)) {
    throw StateError('protected message terminal owner readback failed');
  }
  return true;
}

Future<bool> dbHasExactPreparedLocalGroupContentMessage(
  DatabaseExecutor db, {
  required Map<String, Object?> expected,
  required Map<String, Object?> eventPayload,
}) async {
  final messageId = expected['id'] as String? ?? '';
  final groupId = expected['group_id'] as String? ?? '';
  final retryWrapper = expected['inbox_retry_payload'] as String? ?? '';
  if (messageId.isEmpty || groupId.isEmpty || retryWrapper.isEmpty) {
    return false;
  }
  late final ProtectedGroupContentRetryManifest retryManifest;
  try {
    retryManifest = ProtectedGroupContentRetryManifest.decode(retryWrapper);
  } on Object {
    return false;
  }
  if (retryManifest.groupId != groupId ||
      retryManifest.contentEventId != messageId ||
      retryManifest.payloadType != protectedGroupContentMessagePayloadType) {
    return false;
  }
  final rows = await db.query(
    'group_messages',
    where: 'id = ? AND group_id = ?',
    whereArgs: <Object?>[messageId, groupId],
    limit: 1,
  );
  if (rows.isEmpty ||
      !_sameGroupOutgoingRetryAuthority(rows.single, expected) ||
      !await dbHasExactProtectedGroupContentPreparedOwner(
        db,
        groupId: groupId,
        payloadType: 'group_message',
        contentEventId: messageId,
        ownerKind: 'group_message',
        ownerId: messageId,
        ownerStatus: expected['status'] as String? ?? '',
        retryWrapper: retryWrapper,
        eventPayload: eventPayload,
      )) {
    return false;
  }
  if (retryManifest.mediaManifest == null) {
    return !await dbHasMediaAttachmentForProtectedGroupMessage(db, messageId);
  }
  return await _loadExactProtectedGroupMediaAuthority(
        db,
        retryManifest: retryManifest,
        expectedParent: expected,
        recipientsRequiringStoredRows: retryManifest.pendingRecipientPeerIds
            .toSet(),
      ) !=
      null;
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
