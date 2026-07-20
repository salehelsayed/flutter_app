import 'package:sqflite_sqlcipher/sqflite.dart';

import '../db_write_transaction.dart';
import '../../media/direct_private_media_path_guard.dart';
import '../../media/media_file_path_convention.dart';
import '../../media/media_owner_lane.dart';
import '../../media/outgoing_direct_private_mutation_coordinator.dart';
import '../../secure_storage/secret_storage_references.dart';
import '../../utils/flow_event_emitter.dart';

const _visibleMessageFilter = 'hidden_at IS NULL';

/// Inserts a message into the database.
Future<void> dbInsertMessage(Database db, Map<String, Object?> row) async {
  final id = row['id'] as String? ?? '';

  emitFlowEvent(
    layer: 'DB',
    event: 'MESSAGES_DB_INSERT_START',
    details: {'id': id.length > 8 ? id.substring(0, 8) : id},
  );

  try {
    await dbWriteTransaction(db, (txn) async {
      final existingRows = await txn.query(
        'messages',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      final merged = Map<String, Object?>.from(row);
      if (existingRows.isNotEmpty) {
        final existing = existingRows.single;
        final version = (existing['private_media_policy_version'] as num?)
            ?.toInt();
        final mode = existing['private_media_mode'] as String?;
        final existingIsRedacted =
            version != null &&
            version > 0 &&
            const {
              'protected',
              'view_once',
              'disappearing',
              'unsupported',
            }.contains(mode);
        if (existingIsRedacted) {
          for (final column in const [
            'private_media_policy_version',
            'private_media_mode',
            'private_media_duration_seconds',
            'private_media_state',
            'private_media_received_at_ms',
            'private_media_expires_at_ms',
            'private_media_revealed_at_ms',
            'private_media_terminal_at_ms',
            'hidden_at',
          ]) {
            merged[column] = existing[column];
          }
          if (existing['deleted_at'] != null) {
            merged['deleted_at'] = existing['deleted_at'];
            merged['deleted_by_peer_id'] = existing['deleted_by_peer_id'];
          }
          final existingHighWater =
              (existing['private_media_clock_high_water_ms'] as num?)
                  ?.toInt() ??
              0;
          final incomingHighWater =
              (merged['private_media_clock_high_water_ms'] as num?)?.toInt() ??
              0;
          merged['private_media_clock_high_water_ms'] =
              existingHighWater > incomingHighWater
              ? existingHighWater
              : incomingHighWater;
          // A hidden/deleted private tombstone has already scrubbed content;
          // a stale full-row save may never restore it.
          if (existing['hidden_at'] != null || existing['deleted_at'] != null) {
            merged['text'] = existing['text'];
            merged['wire_envelope'] = existing['wire_envelope'];
          }
        }
      }
      if (existingRows.isEmpty) {
        await txn.insert('messages', merged);
      } else {
        await txn.update('messages', merged, where: 'id = ?', whereArgs: [id]);
      }
    });

    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_INSERT_SUCCESS',
      details: {'id': id.length > 8 ? id.substring(0, 8) : id},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_INSERT_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Returns true if an incoming 1:1 message with the same logical content
/// already exists (F8 content dedup — the 1:1 twin of
/// [dbExistsGroupMessageByContent]).
///
/// Keyed on `(contact_peer_id, sender_peer_id, text, timestamp)` over incoming
/// rows. Catches a divergent-id re-delivery that preserves the original wire
/// timestamp, which the `id`-only gate misses.
Future<bool> dbExistsMessageByContent(
  Database db,
  String contactPeerId,
  String senderPeerId,
  String text,
  String timestamp,
) async {
  final rows = await db.query(
    'messages',
    columns: const ['id'],
    where:
        'contact_peer_id = ? AND sender_peer_id = ? AND text = ? AND timestamp = ? AND is_incoming = 1',
    whereArgs: [contactPeerId, senderPeerId, text, timestamp],
    limit: 1,
  );
  return rows.isNotEmpty;
}

/// Returns true if an incoming 1:1 message with the same wire-stamped
/// `dedup_key` already exists (F8 tier-2).
///
/// `dedup_key` is a propagated source-message id, so this survives a
/// forward/share that re-mints BOTH id and timestamp — which the timestamp-
/// exact [dbExistsMessageByContent] cannot catch. Keyed on
/// `(contact_peer_id, sender_peer_id, dedup_key)` over incoming rows.
Future<bool> dbExistsMessageByDedupKey(
  Database db,
  String contactPeerId,
  String senderPeerId,
  String dedupKey,
) async {
  if (dedupKey.isEmpty) return false; // never dedup on an absent key
  final rows = await db.query(
    'messages',
    columns: const ['id'],
    where:
        'contact_peer_id = ? AND sender_peer_id = ? AND dedup_key = ? AND is_incoming = 1',
    whereArgs: [contactPeerId, senderPeerId, dedupKey],
    limit: 1,
  );
  return rows.isNotEmpty;
}

/// Loads a page of messages for a contact, ordered by timestamp ASC.
///
/// Returns at most [limit] messages. When [beforeTimestamp] is null,
/// returns the most recent page. When provided, returns messages older
/// than that cursor. Results are returned in chronological (ASC) order.
Future<List<Map<String, Object?>>> dbLoadMessagesPage(
  Database db,
  String contactPeerId, {
  int limit = 50,
  String? beforeTimestamp,
}) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MESSAGES_DB_LOAD_PAGE_START',
    details: {
      'contactPeerId': contactPeerId.length > 10
          ? contactPeerId.substring(0, 10)
          : contactPeerId,
      'limit': limit,
      'hasCursor': beforeTimestamp != null,
    },
  );

  try {
    final List<Map<String, Object?>> results;
    if (beforeTimestamp != null) {
      results = await db.query(
        'messages',
        where:
            'contact_peer_id = ? AND $_visibleMessageFilter AND timestamp < ?',
        whereArgs: [contactPeerId, beforeTimestamp],
        orderBy: 'timestamp DESC',
        limit: limit,
      );
    } else {
      results = await db.query(
        'messages',
        where: 'contact_peer_id = ? AND $_visibleMessageFilter',
        whereArgs: [contactPeerId],
        orderBy: 'timestamp DESC',
        limit: limit,
      );
    }

    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_LOAD_PAGE_SUCCESS',
      details: {'count': results.length},
    );

    return results.reversed.toList();
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_LOAD_PAGE_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads all messages for a contact, ordered by timestamp ASC.
Future<List<Map<String, Object?>>> dbLoadMessagesForContact(
  Database db,
  String contactPeerId,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MESSAGES_DB_LOAD_FOR_CONTACT_START',
    details: {
      'contactPeerId': contactPeerId.length > 10
          ? contactPeerId.substring(0, 10)
          : contactPeerId,
    },
  );

  try {
    final results = await db.query(
      'messages',
      where: 'contact_peer_id = ? AND $_visibleMessageFilter',
      whereArgs: [contactPeerId],
      orderBy: 'timestamp ASC',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_LOAD_FOR_CONTACT_SUCCESS',
      details: {'count': results.length},
    );

    return results;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_LOAD_FOR_CONTACT_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads the latest message for a contact (most recent by timestamp).
Future<Map<String, Object?>?> dbLoadLatestMessageForContact(
  Database db,
  String contactPeerId,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MESSAGES_DB_LOAD_LATEST_START',
    details: {
      'contactPeerId': contactPeerId.length > 10
          ? contactPeerId.substring(0, 10)
          : contactPeerId,
    },
  );

  try {
    final results = await db.query(
      'messages',
      where: 'contact_peer_id = ? AND $_visibleMessageFilter',
      whereArgs: [contactPeerId],
      orderBy: 'timestamp DESC',
      limit: 1,
    );

    if (results.isNotEmpty) {
      emitFlowEvent(
        layer: 'DB',
        event: 'MESSAGES_DB_LOAD_LATEST_FOUND',
        details: {},
      );
      return results.first;
    } else {
      emitFlowEvent(
        layer: 'DB',
        event: 'MESSAGES_DB_LOAD_LATEST_NOT_FOUND',
        details: {},
      );
      return null;
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_LOAD_LATEST_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads conversation summaries for the provided contacts.
///
/// Returns one row per contact that has at least one message. Contacts with no
/// messages are omitted so callers can provide their own zero-value fallback.
Future<List<Map<String, Object?>>> dbLoadConversationThreadSummaries(
  Database db,
  List<String> contactPeerIds,
) async {
  if (contactPeerIds.isEmpty) return const [];

  final placeholders = List.filled(contactPeerIds.length, '?').join(', ');
  final results = await db.rawQuery('''
    SELECT
      summary.contact_peer_id,
      summary.message_count,
      summary.unread_count,
      summary.last_outgoing_at,
      latest.id AS latest_id,
      latest.contact_peer_id AS latest_contact_peer_id,
      latest.sender_peer_id AS latest_sender_peer_id,
      latest.text AS latest_text,
      latest.timestamp AS latest_timestamp,
      latest.status AS latest_status,
      latest.is_incoming AS latest_is_incoming,
      latest.created_at AS latest_created_at,
      latest.edited_at AS latest_edited_at,
      latest.read_at AS latest_read_at,
      latest.quoted_message_id AS latest_quoted_message_id,
      latest.deleted_at AS latest_deleted_at,
      latest.deleted_by_peer_id AS latest_deleted_by_peer_id,
      latest.hidden_at AS latest_hidden_at,
      latest.transport AS latest_transport,
      latest.wire_envelope AS latest_wire_envelope
    FROM (
      SELECT
        contact_peer_id,
        -- 160 A0: tombstone reconciliation — message_count/unread_count exclude
        -- soft-deleted (deleted_at) rows so totalMessageCount matches the feed
        -- getters' visible-non-deleted view (additionalCount == total-1). The
        -- WHERE stays hidden_at-only so a deleted-not-hidden row still yields a
        -- summary row (its tombstone metadata can be the `latest`).
        SUM(CASE WHEN deleted_at IS NULL THEN 1 ELSE 0 END) AS message_count,
        SUM(
          CASE
            WHEN is_incoming = 1 AND read_at IS NULL AND deleted_at IS NULL
              THEN 1
            ELSE 0
          END
        ) AS unread_count,
        -- 160 A0: newest non-deleted OUTGOING timestamp, so the feed can derive
        -- hasReply / conversationState / lastRepliedAt from the summary instead
        -- of scanning a windowed message slice (where an old reply may be off
        -- the window). NULL when the thread has no outgoing reply.
        MAX(
          CASE WHEN is_incoming = 0 AND deleted_at IS NULL THEN timestamp END
        ) AS last_outgoing_at
      FROM messages
      WHERE contact_peer_id IN ($placeholders)
        AND $_visibleMessageFilter
      GROUP BY contact_peer_id
    ) summary
    LEFT JOIN messages latest
      ON latest.id = (
        SELECT inner_latest.id
        FROM messages inner_latest
        WHERE inner_latest.contact_peer_id = summary.contact_peer_id
          AND inner_latest.hidden_at IS NULL
        ORDER BY inner_latest.timestamp DESC,
                 inner_latest.created_at DESC,
                 inner_latest.id DESC
        LIMIT 1
      )
    ''', contactPeerIds);
  return results;
}

/// Updates the status of a message by ID.
Future<int> dbUpdateMessageStatus(Database db, String id, String status) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MESSAGES_DB_UPDATE_STATUS_START',
    details: {'id': id.length > 8 ? id.substring(0, 8) : id, 'status': status},
  );

  try {
    final updated = await db.update(
      'messages',
      {'status': status},
      // A late transport/status callback never outranks durable local
      // hide/delete intent, regardless of media policy.
      where: 'id = ? AND hidden_at IS NULL AND deleted_at IS NULL',
      whereArgs: [id],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_UPDATE_STATUS_SUCCESS',
      details: {
        'id': id.length > 8 ? id.substring(0, 8) : id,
        'rowsUpdated': updated,
      },
    );
    return updated;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_UPDATE_STATUS_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Returns the total number of messages.
Future<int> dbGetMessageCount(Database db) async {
  try {
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM messages');
    return Sqflite.firstIntValue(result) ?? 0;
  } catch (e) {
    return 0;
  }
}

/// Returns the total number of messages for a specific contact.
Future<int> dbCountMessagesForContact(Database db, String contactPeerId) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MESSAGES_DB_COUNT_FOR_CONTACT_START',
    details: {
      'contactPeerId': contactPeerId.length > 10
          ? contactPeerId.substring(0, 10)
          : contactPeerId,
    },
  );

  try {
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM messages '
      'WHERE contact_peer_id = ? AND $_visibleMessageFilter',
      [contactPeerId],
    );
    final count = Sqflite.firstIntValue(result) ?? 0;

    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_COUNT_FOR_CONTACT_SUCCESS',
      details: {'count': count},
    );

    return count;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_COUNT_FOR_CONTACT_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Marks all unread incoming messages for a contact as read.
Future<int> dbMarkConversationAsRead(Database db, String contactPeerId) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MESSAGES_DB_MARK_READ_START',
    details: {
      'contactPeerId': contactPeerId.length > 10
          ? contactPeerId.substring(0, 10)
          : contactPeerId,
    },
  );

  try {
    final now = DateTime.now().toUtc().toIso8601String();
    final count = await db.rawUpdate(
      'UPDATE messages SET read_at = ? '
      'WHERE contact_peer_id = ? AND is_incoming = 1 '
      'AND read_at IS NULL AND $_visibleMessageFilter',
      [now, contactPeerId],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_MARK_READ_SUCCESS',
      details: {'count': count},
    );

    return count;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_MARK_READ_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Returns the number of unread incoming messages for a specific contact.
Future<int> dbCountUnreadForContact(Database db, String contactPeerId) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MESSAGES_DB_COUNT_UNREAD_CONTACT_START',
    details: {
      'contactPeerId': contactPeerId.length > 10
          ? contactPeerId.substring(0, 10)
          : contactPeerId,
    },
  );

  try {
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM messages '
      'WHERE contact_peer_id = ? AND is_incoming = 1 '
      'AND read_at IS NULL AND $_visibleMessageFilter',
      [contactPeerId],
    );
    final count = Sqflite.firstIntValue(result) ?? 0;

    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_COUNT_UNREAD_CONTACT_SUCCESS',
      details: {'count': count},
    );

    return count;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_COUNT_UNREAD_CONTACT_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Returns the total number of unread incoming messages across all contacts.
Future<int> dbCountTotalUnread(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MESSAGES_DB_COUNT_TOTAL_UNREAD_START',
    details: {},
  );

  try {
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM messages '
      'WHERE is_incoming = 1 AND read_at IS NULL AND $_visibleMessageFilter',
    );
    final count = Sqflite.firstIntValue(result) ?? 0;

    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_COUNT_TOTAL_UNREAD_SUCCESS',
      details: {'count': count},
    );

    return count;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_COUNT_TOTAL_UNREAD_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Returns the total number of unread incoming messages excluding archived contacts.
Future<int> dbCountTotalUnreadExcludingArchived(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MESSAGES_DB_COUNT_TOTAL_UNREAD_EXCL_ARCHIVED_START',
    details: {},
  );

  try {
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM messages m '
      'JOIN contacts c ON m.contact_peer_id = c.peer_id '
      'WHERE m.is_incoming = 1 AND m.read_at IS NULL '
      'AND m.hidden_at IS NULL AND c.is_archived = 0 AND c.is_blocked = 0',
    );
    final count = Sqflite.firstIntValue(result) ?? 0;

    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_COUNT_TOTAL_UNREAD_EXCL_ARCHIVED_SUCCESS',
      details: {'count': count},
    );

    return count;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_COUNT_TOTAL_UNREAD_EXCL_ARCHIVED_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Deletes all messages for a contact.
Future<int> dbDeleteMessagesForContact(
  Database db,
  String contactPeerId,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MESSAGES_DB_DELETE_FOR_CONTACT_START',
    details: {
      'contactPeerId': contactPeerId.length > 10
          ? contactPeerId.substring(0, 10)
          : contactPeerId,
    },
  );

  try {
    final count = await db.delete(
      'messages',
      where: 'contact_peer_id = ?',
      whereArgs: [contactPeerId],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_DELETE_FOR_CONTACT_SUCCESS',
      details: {'count': count},
    );

    return count;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_DELETE_FOR_CONTACT_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Deletes a single message by ID.
Future<int> dbDeleteMessage(Database db, String id) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MESSAGES_DB_DELETE_START',
    details: {'id': id.length > 8 ? id.substring(0, 8) : id},
  );

  try {
    final count = await db.delete('messages', where: 'id = ?', whereArgs: [id]);

    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_DELETE_SUCCESS',
      details: {'count': count},
    );

    return count;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_DELETE_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads all outgoing messages with status='failed', ordered by timestamp ASC.
///
/// Returns at most [limit] rows (default 50).
Future<List<Map<String, Object?>>> dbLoadFailedOutgoingMessages(
  Database db, {
  int limit = 50,
}) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MESSAGES_DB_LOAD_FAILED_OUTGOING_START',
    details: {'limit': limit},
  );

  try {
    final results = await db.query(
      'messages',
      where: "status = ? AND is_incoming = 0",
      whereArgs: ['failed'],
      orderBy: 'timestamp ASC',
      limit: limit,
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_LOAD_FAILED_OUTGOING_SUCCESS',
      details: {'count': results.length},
    );

    return results;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_LOAD_FAILED_OUTGOING_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads outgoing messages with status='sent' and a non-null wire_envelope
/// that are older than [olderThan]. These are messages that were written to
/// the stream but not ACK'd, and need inbox retry.
///
/// Returns at most [limit] rows ordered by timestamp ASC.
Future<List<Map<String, Object?>>> dbLoadUnackedOutgoingMessages(
  Database db, {
  required DateTime olderThan,
  int limit = 50,
}) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MESSAGES_DB_LOAD_UNACKED_OUTGOING_START',
    details: {'limit': limit},
  );

  try {
    final results = await db.query(
      'messages',
      where:
          "status = ? AND is_incoming = 0 AND wire_envelope IS NOT NULL AND timestamp < ?",
      whereArgs: ['sent', olderThan.toUtc().toIso8601String()],
      orderBy: 'timestamp ASC',
      limit: limit,
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_LOAD_UNACKED_OUTGOING_SUCCESS',
      details: {'count': results.length},
    );

    return results;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_LOAD_UNACKED_OUTGOING_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads outgoing inbox-custody rows that need a custody verification sweep.
///
/// Rows are selected only when they still have the original wire envelope, are
/// non-terminal `inboxed`, and either have never been checked or were checked
/// before [recheckOlderThan].
Future<List<Map<String, Object?>>> dbLoadInboxCustodyOutgoingMessages(
  Database db, {
  required Duration recheckOlderThan,
  int limit = 50,
  DateTime? now,
}) async {
  final cutoff = (now ?? DateTime.now())
      .toUtc()
      .subtract(recheckOlderThan)
      .toIso8601String();

  emitFlowEvent(
    layer: 'DB',
    event: 'MESSAGES_DB_LOAD_INBOX_CUSTODY_START',
    details: {'limit': limit},
  );

  try {
    final results = await db.query(
      'messages',
      where: '''
status = ?
AND is_incoming = 0
AND wire_envelope IS NOT NULL
AND wire_envelope != ''
AND (custody_checked_at IS NULL OR custody_checked_at < ?)
''',
      whereArgs: ['inboxed', cutoff],
      orderBy: 'timestamp ASC',
      limit: limit,
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_LOAD_INBOX_CUSTODY_SUCCESS',
      details: {'count': results.length},
    );
    return results;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_LOAD_INBOX_CUSTODY_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

Future<void> dbMarkInboxCustodyChecked(
  Database db,
  String id, {
  int? relayExpiresAtMs,
  DateTime? checkedAt,
}) async {
  final values = <String, Object?>{
    'custody_checked_at': (checkedAt ?? DateTime.now())
        .toUtc()
        .toIso8601String(),
  };
  if (relayExpiresAtMs != null) {
    values['relay_expires_at'] = relayExpiresAtMs;
  }

  await db.update(
    'messages',
    values,
    where: 'id = ? AND status = ?',
    whereArgs: [id, 'inboxed'],
  );
}

/// Loads outgoing messages with status='sending' that are older than
/// [olderThan]. These are candidates for immediate retry without waiting
/// for the next app-resume event.
///
/// Returns at most [limit] rows ordered by timestamp ASC.
Future<List<Map<String, Object?>>> dbLoadStuckSendingOutgoingMessages(
  Database db, {
  required DateTime olderThan,
  int limit = 50,
}) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MESSAGES_DB_LOAD_STUCK_SENDING_START',
    details: {'limit': limit},
  );

  try {
    final results = await db.query(
      'messages',
      where: "status = ? AND is_incoming = 0 AND timestamp < ?",
      whereArgs: ['sending', olderThan.toUtc().toIso8601String()],
      orderBy: 'timestamp ASC',
      limit: limit,
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_LOAD_STUCK_SENDING_SUCCESS',
      details: {'count': results.length},
    );

    return results;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_LOAD_STUCK_SENDING_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads a single message by ID.
Future<Map<String, Object?>?> dbLoadMessage(Database db, String id) async {
  try {
    final results = await db.query(
      'messages',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  } catch (e) {
    return null;
  }
}

/// Loads all outgoing messages with status='sending'.
///
/// Used by [handleAppPaused] to find in-flight messages that need to be
/// transitioned to 'failed' before the process is frozen by the OS.
Future<List<Map<String, Object?>>> dbLoadSendingOutgoingMessages(
  Database db,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MESSAGES_DB_LOAD_SENDING_START',
    details: {},
  );

  try {
    final rows = await db.query(
      'messages',
      where: 'status = ? AND is_incoming = 0',
      whereArgs: ['sending'],
      orderBy: 'timestamp ASC',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_LOAD_SENDING_DONE',
      details: {'count': rows.length},
    );

    return rows;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_LOAD_SENDING_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Only transitions status if the current status matches [fromStatus].
/// Returns the number of rows updated (0 if the row already advanced).
///
/// Used by [handleAppPaused] to safely transition 'sending' -> 'failed'
/// without overwriting a concurrently completed 'delivered'/'sent' status.
Future<int> dbConditionalTransitionStatus(
  Database db,
  String id, {
  required String fromStatus,
  required String toStatus,
}) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MESSAGES_DB_CONDITIONAL_TRANSITION_START',
    details: {
      'id': id.length > 8 ? id.substring(0, 8) : id,
      'from': fromStatus,
      'to': toStatus,
    },
  );

  try {
    final count = await db.rawUpdate(
      'UPDATE messages SET status = ? WHERE id = ? AND status = ?',
      [toStatus, id, fromStatus],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_CONDITIONAL_TRANSITION_DONE',
      details: {
        'id': id.length > 8 ? id.substring(0, 8) : id,
        'rowsUpdated': count,
      },
    );

    return count;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_CONDITIONAL_TRANSITION_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Transitions all outgoing messages stuck in status='sending' that are
/// older than [olderThan] to status='failed'.
///
/// Safe to call on every resume — messages younger than the threshold
/// are untouched. wire_envelope is preserved so retryFailedMessages can
/// use the full re-encrypt path (wire_envelope will typically be null
/// for stuck 'sending' rows — the envelope is only serialized inside
/// sendChatMessage, which never completed).
///
/// [limit] is reserved for future use — SQLite UPDATE does not support LIMIT
/// natively and the current query does not apply it.
///
/// The recovery query uses the `timestamp` column (ISO-8601 strings compare
/// lexicographically correctly). No index on (status, is_incoming, timestamp)
/// exists, but recovery runs at most once per resume and the message table
/// is small, so a full scan is acceptable.
///
/// Returns the number of rows updated.
Future<int> dbRecoverStuckSendingMessages(
  Database db, {
  required DateTime olderThan,
  int limit = 50,
}) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MESSAGES_DB_RECOVER_STUCK_SENDING_START',
    details: {'olderThan': olderThan.toIso8601String()},
  );

  try {
    final hasMediaAttachments = (await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' "
      "AND name = 'media_attachments' LIMIT 1",
    )).isNotEmpty;
    final pendingUploadExclusion = hasMediaAttachments
        ? 'AND NOT EXISTS (SELECT 1 FROM media_attachments attachment '
              'WHERE attachment.message_id = messages.id '
              "AND attachment.owner_lane = 'direct' "
              "AND attachment.download_status = 'upload_pending')"
        : '';
    final count = await db.rawUpdate(
      "UPDATE messages SET status = 'failed' "
      "WHERE status = 'sending' AND is_incoming = 0 AND timestamp < ? "
      '$pendingUploadExclusion',
      [olderThan.toUtc().toIso8601String()],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_RECOVER_STUCK_SENDING_SUCCESS',
      details: {'count': count},
    );

    return count;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_RECOVER_STUCK_SENDING_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Updates the wire_envelope column for a message by ID.
///
/// Used by sendChatMessage to persist the serialized envelope before the
/// transport race, so a crash during the race leaves a retryable DB row.
Future<void> dbUpdateWireEnvelope(
  Database db,
  String id,
  String wireEnvelope,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MESSAGES_DB_UPDATE_WIRE_ENVELOPE_START',
    details: {'id': id.length > 8 ? id.substring(0, 8) : id},
  );

  try {
    await dbWriteTransaction(db, (txn) async {
      final rows = await txn.query(
        'messages',
        columns: const <String>[
          'is_incoming',
          'hidden_at',
          'deleted_at',
          'private_media_policy_version',
          'private_media_mode',
        ],
        where: 'id = ?',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final row = rows.single;
      final version = (row['private_media_policy_version'] as num?)?.toInt();
      final mode = row['private_media_mode'] as String?;
      final genericOutgoing =
          ((row['is_incoming'] as num?)?.toInt() ?? 0) == 0 &&
          row['hidden_at'] == null &&
          row['deleted_at'] == null &&
          ((version == null && mode == null) ||
              (version == 0 && (mode == null || mode == 'ordinary')) ||
              (version == 1 && mode == 'disappearing'));
      if (!genericOutgoing) return;
      await txn.rawUpdate(
        'UPDATE messages SET wire_envelope = ? WHERE id = ? '
        'AND is_incoming = 0 AND hidden_at IS NULL AND deleted_at IS NULL '
        'AND ((private_media_policy_version IS NULL '
        'AND private_media_mode IS NULL) '
        'OR (private_media_policy_version = 0 '
        "AND (private_media_mode IS NULL OR private_media_mode = 'ordinary')) "
        'OR (private_media_policy_version = 1 '
        "AND private_media_mode = 'disappearing'))",
        <Object?>[wireEnvelope, id],
      );
    });

    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_UPDATE_WIRE_ENVELOPE_SUCCESS',
      details: {'id': id.length > 8 ? id.substring(0, 8) : id},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_UPDATE_WIRE_ENVELOPE_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Update-only first persistence for an outgoing protected/View-Once
/// Delete-for-Everyone tombstone.
///
/// A physical parent removal is authoritative: this helper never INSERTs. A
/// concurrent local hide is preserved because `hidden_at` and all private
/// lifecycle columns are deliberately outside the update set.
Future<bool> dbCommitOutgoingDirectPrivateDeleteForEveryoneTombstone(
  Database db,
  Map<String, Object?> expectedRow,
  Map<String, Object?> tombstoneRow,
) {
  final messageId = tombstoneRow['id'] as String? ?? '';
  final contactPeerId = tombstoneRow['contact_peer_id'] as String? ?? '';
  final senderPeerId = tombstoneRow['sender_peer_id'] as String? ?? '';
  final deletedAt = tombstoneRow['deleted_at'] as String? ?? '';
  final deletedByPeerId = tombstoneRow['deleted_by_peer_id'] as String? ?? '';
  final envelope = tombstoneRow['wire_envelope'] as String? ?? '';
  final mode = tombstoneRow['private_media_mode'] as String?;
  final expectedStatus = expectedRow['status'] as String?;
  final shapeIsValid =
      messageId.isNotEmpty &&
      contactPeerId.isNotEmpty &&
      senderPeerId.isNotEmpty &&
      deletedAt.isNotEmpty &&
      deletedByPeerId == senderPeerId &&
      envelope.isNotEmpty &&
      tombstoneRow['text'] == '' &&
      tombstoneRow['status'] == 'sending' &&
      tombstoneRow['transport'] == null &&
      (tombstoneRow['is_incoming'] as num?)?.toInt() == 0 &&
      (tombstoneRow['private_media_policy_version'] as num?)?.toInt() == 1 &&
      const <String>{'protected', 'view_once'}.contains(mode) &&
      expectedRow['id'] == messageId &&
      expectedRow['contact_peer_id'] == contactPeerId &&
      expectedRow['sender_peer_id'] == senderPeerId &&
      (expectedRow['is_incoming'] as num?)?.toInt() == 0 &&
      (expectedRow['private_media_policy_version'] as num?)?.toInt() == 1 &&
      expectedRow['private_media_mode'] == mode &&
      (expectedStatus == 'delivered' || expectedStatus == 'inboxed');
  if (!shapeIsValid) return Future<bool>.value(false);

  bool exactTombstone(Map<String, Object?> row) =>
      row['contact_peer_id'] == contactPeerId &&
      row['sender_peer_id'] == senderPeerId &&
      (row['is_incoming'] as num?)?.toInt() == 0 &&
      (row['private_media_policy_version'] as num?)?.toInt() == 1 &&
      row['private_media_mode'] == mode &&
      row['text'] == '' &&
      row['transport'] == null &&
      row['deleted_at'] == deletedAt &&
      row['deleted_by_peer_id'] == deletedByPeerId &&
      row['wire_envelope'] == envelope;

  return dbWriteTransaction(db, (txn) async {
    final rows = await txn.query(
      'messages',
      where: 'id = ?',
      whereArgs: <Object?>[messageId],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    final current = rows.single;
    if (current['deleted_at'] != null) return exactTombstone(current);
    if (current['contact_peer_id'] != contactPeerId ||
        current['sender_peer_id'] != senderPeerId ||
        (current['is_incoming'] as num?)?.toInt() != 0 ||
        (current['private_media_policy_version'] as num?)?.toInt() != 1 ||
        current['private_media_mode'] != mode ||
        !const <String>{'delivered', 'inboxed'}.contains(current['status'])) {
      return false;
    }

    final changed = await txn.rawUpdate(
      'UPDATE messages SET text = ?, status = ?, transport = NULL, '
      'deleted_at = ?, deleted_by_peer_id = ?, wire_envelope = ? '
      'WHERE id = ? AND contact_peer_id = ? AND sender_peer_id = ? '
      'AND is_incoming = 0 AND deleted_at IS NULL '
      'AND private_media_policy_version = 1 '
      "AND private_media_mode IN ('protected','view_once') "
      "AND status IN ('delivered','inboxed')",
      <Object?>[
        '',
        'sending',
        deletedAt,
        deletedByPeerId,
        envelope,
        messageId,
        contactPeerId,
        senderPeerId,
      ],
    );
    if (changed == 1) return true;
    final after = await txn.query(
      'messages',
      where: 'id = ?',
      whereArgs: <Object?>[messageId],
      limit: 1,
    );
    return after.isNotEmpty && exactTombstone(after.single);
  });
}

/// Update-only staging for a rebuilt private deletion retry envelope.
///
/// The exact failed tombstone must still exist with the caller-observed
/// envelope value. Only `wire_envelope` changes; physical removal, lifecycle,
/// hidden state, and deletion identity always win.
Future<bool> dbStageOutgoingDirectPrivateDeleteForEveryoneRetryEnvelope(
  Database db,
  Map<String, Object?> tombstoneRow, {
  required String? expectedEnvelope,
  required String envelope,
}) {
  final messageId = tombstoneRow['id'] as String? ?? '';
  final contactPeerId = tombstoneRow['contact_peer_id'] as String? ?? '';
  final senderPeerId = tombstoneRow['sender_peer_id'] as String? ?? '';
  final deletedAt = tombstoneRow['deleted_at'] as String? ?? '';
  final deletedByPeerId = tombstoneRow['deleted_by_peer_id'] as String? ?? '';
  final mode = tombstoneRow['private_media_mode'] as String?;
  final shapeIsValid =
      envelope.isNotEmpty &&
      DirectPrivateMediaPathGuard.isSafeSegment(messageId) &&
      DirectPrivateMediaPathGuard.isSafeSegment(contactPeerId) &&
      DirectPrivateMediaPathGuard.isSafeSegment(senderPeerId) &&
      deletedAt.isNotEmpty &&
      deletedByPeerId == senderPeerId &&
      tombstoneRow['text'] == '' &&
      tombstoneRow['status'] == 'failed' &&
      (tombstoneRow['is_incoming'] as num?)?.toInt() == 0 &&
      (tombstoneRow['private_media_policy_version'] as num?)?.toInt() == 1 &&
      const <String>{'protected', 'view_once'}.contains(mode);
  if (!shapeIsValid) return Future<bool>.value(false);

  return dbWriteTransaction(db, (txn) async {
    final rows = await txn.query(
      'messages',
      where: 'id = ?',
      whereArgs: <Object?>[messageId],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    final current = rows.single;
    if (current['contact_peer_id'] != contactPeerId ||
        current['sender_peer_id'] != senderPeerId ||
        (current['is_incoming'] as num?)?.toInt() != 0 ||
        (current['private_media_policy_version'] as num?)?.toInt() != 1 ||
        current['private_media_mode'] != mode ||
        current['text'] != '' ||
        current['status'] != 'failed' ||
        current['deleted_at'] != deletedAt ||
        current['deleted_by_peer_id'] != deletedByPeerId ||
        current['wire_envelope'] != expectedEnvelope) {
      return false;
    }
    if (expectedEnvelope == envelope) return true;

    final envelopePredicate = expectedEnvelope == null
        ? 'wire_envelope IS NULL'
        : 'wire_envelope = ?';
    final updateArgs = <Object?>[
      envelope,
      messageId,
      contactPeerId,
      senderPeerId,
      '',
      'failed',
      deletedAt,
      deletedByPeerId,
    ];
    if (expectedEnvelope != null) updateArgs.add(expectedEnvelope);
    final changed = await txn.rawUpdate(
      'UPDATE messages SET wire_envelope = ? '
      'WHERE id = ? AND contact_peer_id = ? AND sender_peer_id = ? '
      'AND is_incoming = 0 AND private_media_policy_version = 1 '
      "AND private_media_mode IN ('protected','view_once') "
      'AND text = ? AND status = ? AND deleted_at = ? '
      'AND deleted_by_peer_id = ? AND $envelopePredicate',
      updateArgs,
    );
    return changed == 1;
  });
}

/// Update-only transport settlement for the exact private deletion tombstone.
///
/// The expected deletion marker and envelope are the comparands. Missing rows
/// remain missing, a concurrent hide is never cleared, and private lifecycle
/// state is never rewritten from a stale message snapshot.
Future<bool> dbSettleOutgoingDirectPrivateDeleteForEveryoneTombstone(
  Database db,
  Map<String, Object?> tombstoneRow, {
  required String expectedEnvelope,
}) {
  final messageId = tombstoneRow['id'] as String? ?? '';
  final contactPeerId = tombstoneRow['contact_peer_id'] as String? ?? '';
  final senderPeerId = tombstoneRow['sender_peer_id'] as String? ?? '';
  final deletedAt = tombstoneRow['deleted_at'] as String? ?? '';
  final deletedByPeerId = tombstoneRow['deleted_by_peer_id'] as String? ?? '';
  final status = tombstoneRow['status'] as String? ?? '';
  final transport = tombstoneRow['transport'] as String?;
  final targetEnvelope = tombstoneRow['wire_envelope'] as String?;
  final targetHiddenAt = tombstoneRow['hidden_at'] as String?;
  final mode = tombstoneRow['private_media_mode'] as String?;
  const statuses = <String>{'failed', 'sent', 'inboxed', 'delivered'};
  final shapeIsValid =
      messageId.isNotEmpty &&
      contactPeerId.isNotEmpty &&
      senderPeerId.isNotEmpty &&
      deletedAt.isNotEmpty &&
      deletedByPeerId == senderPeerId &&
      expectedEnvelope.isNotEmpty &&
      statuses.contains(status) &&
      (tombstoneRow['is_incoming'] as num?)?.toInt() == 0 &&
      (tombstoneRow['private_media_policy_version'] as num?)?.toInt() == 1 &&
      const <String>{'protected', 'view_once'}.contains(mode) &&
      (status == 'delivered'
          ? targetEnvelope == null && targetHiddenAt == deletedAt
          : targetEnvelope == expectedEnvelope && targetHiddenAt == null) &&
      (status != 'inboxed' || transport == 'inbox');
  if (!shapeIsValid) return Future<bool>.value(false);

  final allowedCurrentStatuses = switch (status) {
    'delivered' => const <String>['sending', 'failed', 'sent', 'inboxed'],
    'inboxed' => const <String>['sending', 'failed', 'sent', 'inboxed'],
    'sent' => const <String>['sending', 'failed', 'sent'],
    'failed' => const <String>['sending', 'failed'],
    _ => const <String>[],
  };
  return dbWriteTransaction(db, (txn) async {
    final rows = await txn.query(
      'messages',
      where: 'id = ?',
      whereArgs: <Object?>[messageId],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    final current = rows.single;
    if (current['contact_peer_id'] != contactPeerId ||
        current['sender_peer_id'] != senderPeerId ||
        (current['is_incoming'] as num?)?.toInt() != 0 ||
        (current['private_media_policy_version'] as num?)?.toInt() != 1 ||
        current['private_media_mode'] != mode ||
        current['text'] != '' ||
        current['deleted_at'] != deletedAt ||
        current['deleted_by_peer_id'] != deletedByPeerId) {
      return false;
    }
    final alreadySettled =
        current['status'] == status &&
        current['transport'] == transport &&
        current['wire_envelope'] == targetEnvelope &&
        (targetHiddenAt == null || current['hidden_at'] != null);
    if (alreadySettled) return true;
    if (current['wire_envelope'] != expectedEnvelope ||
        !allowedCurrentStatuses.contains(current['status'])) {
      return false;
    }

    final placeholders = List<String>.filled(
      allowedCurrentStatuses.length,
      '?',
    ).join(',');
    final changed = await txn.rawUpdate(
      'UPDATE messages SET status = ?, transport = ?, wire_envelope = ?, '
      'hidden_at = CASE WHEN hidden_at IS NULL THEN ? ELSE hidden_at END '
      'WHERE id = ? AND contact_peer_id = ? AND sender_peer_id = ? '
      'AND is_incoming = 0 AND private_media_policy_version = 1 '
      "AND private_media_mode IN ('protected','view_once') "
      'AND text = ? AND deleted_at = ? AND deleted_by_peer_id = ? '
      'AND wire_envelope = ? AND status IN ($placeholders)',
      <Object?>[
        status,
        transport,
        targetEnvelope,
        targetHiddenAt,
        messageId,
        contactPeerId,
        senderPeerId,
        '',
        deletedAt,
        deletedByPeerId,
        expectedEnvelope,
        ...allowedCurrentStatuses,
      ],
    );
    return changed == 1;
  });
}

/// Clears a stale transport envelope immediately before a key-rotating
/// outgoing direct-private upload. The exact parent/attachment qualification
/// and the column-only mutation share one transaction, so failure occurs
/// before the caller reads plaintext bytes.
Future<bool> dbInvalidateWireEnvelopeBeforePrivateUpload(
  Database db, {
  required String messageId,
  required String attachmentId,
  required String expectedPendingLocalPath,
}) {
  if (messageId.isEmpty ||
      attachmentId.isEmpty ||
      expectedPendingLocalPath.isEmpty) {
    return Future<bool>.value(false);
  }
  return dbWriteTransaction(db, (txn) async {
    final qualified = await txn.rawQuery(
      'SELECT 1 FROM messages parent '
      'JOIN media_attachments attachment '
      'ON attachment.message_id = parent.id '
      'WHERE parent.id = ? AND parent.is_incoming = 0 '
      'AND parent.hidden_at IS NULL AND parent.deleted_at IS NULL '
      "AND parent.status IN ('sending','failed') "
      'AND parent.private_media_policy_version = 1 '
      "AND parent.private_media_mode IN ('protected','view_once') "
      'AND ((parent.private_media_state = \'available\' '
      'AND parent.private_media_revealed_at_ms IS NULL '
      'AND parent.private_media_terminal_at_ms IS NULL) '
      'OR (parent.private_media_state IN (\'opening\',\'viewing\') '
      'AND parent.private_media_terminal_at_ms IS NULL) '
      'OR (parent.private_media_state = \'consumed\' '
      'AND parent.private_media_terminal_at_ms IS NOT NULL)) '
      'AND attachment.id = ? AND attachment.owner_lane = ? '
      "AND attachment.download_status = 'upload_pending' "
      'AND attachment.local_path = ? LIMIT 1',
      <Object?>[messageId, attachmentId, 'direct', expectedPendingLocalPath],
    );
    if (qualified.isEmpty) return false;
    final count = await txn.rawUpdate(
      'UPDATE messages SET wire_envelope = NULL WHERE id = ? '
      'AND is_incoming = 0 AND hidden_at IS NULL AND deleted_at IS NULL '
      "AND status IN ('sending','failed') "
      'AND private_media_policy_version = 1 '
      "AND private_media_mode IN ('protected','view_once') "
      'AND ((private_media_state = \'available\' '
      'AND private_media_revealed_at_ms IS NULL '
      'AND private_media_terminal_at_ms IS NULL) '
      'OR (private_media_state IN (\'opening\',\'viewing\') '
      'AND private_media_terminal_at_ms IS NULL) '
      'OR (private_media_state = \'consumed\' '
      'AND private_media_terminal_at_ms IS NOT NULL)) '
      'AND EXISTS (SELECT 1 FROM media_attachments attachment '
      'WHERE attachment.message_id = messages.id '
      'AND attachment.id = ? AND attachment.owner_lane = ? '
      "AND attachment.download_status = 'upload_pending' "
      'AND attachment.local_path = ?)',
      <Object?>[messageId, attachmentId, 'direct', expectedPendingLocalPath],
    );
    return count == 1;
  });
}

/// Restores retryable parent status when a key-rotating private upload
/// completed but encryption/envelope handoff failed before any envelope became
/// durable. Every predicate is repeated by the update so a concurrent
/// hide/delete/removal or attachment replacement wins without fallback.
Future<bool> dbMarkOutgoingDirectPrivateUploadHandoffFailed(
  Database db, {
  required String messageId,
  required String attachmentId,
  required String expectedPendingLocalPath,
}) {
  if (messageId.isEmpty ||
      attachmentId.isEmpty ||
      expectedPendingLocalPath.isEmpty) {
    return Future<bool>.value(false);
  }
  return dbWriteTransaction(db, (txn) async {
    final count = await txn.rawUpdate(
      "UPDATE messages SET status = 'failed' "
      "WHERE id = ? AND status = 'sending' AND is_incoming = 0 "
      'AND hidden_at IS NULL AND deleted_at IS NULL '
      'AND wire_envelope IS NULL '
      'AND private_media_policy_version = 1 '
      "AND private_media_mode IN ('protected','view_once') "
      "AND ((private_media_state = 'available' "
      'AND private_media_revealed_at_ms IS NULL '
      'AND private_media_terminal_at_ms IS NULL) '
      "OR (private_media_state IN ('opening','viewing') "
      'AND private_media_terminal_at_ms IS NULL) '
      "OR (private_media_state = 'consumed' "
      'AND private_media_terminal_at_ms IS NOT NULL)) '
      'AND EXISTS (SELECT 1 FROM media_attachments attachment '
      'WHERE attachment.message_id = messages.id '
      'AND attachment.id = ? AND attachment.owner_lane = ? '
      "AND attachment.download_status = 'upload_pending' "
      'AND attachment.local_path = ?) '
      'AND 1 = (SELECT COUNT(*) FROM media_attachments sibling '
      'WHERE sibling.message_id = messages.id '
      'AND sibling.owner_lane = ?)',
      <Object?>[
        messageId,
        attachmentId,
        MediaOwnerLane.direct.dbValue,
        expectedPendingLocalPath,
        MediaOwnerLane.direct.dbValue,
      ],
    );
    return count == 1;
  });
}

/// Final, exact outgoing-private transport handoff.
///
/// A canonical `done` row is durable completion authority in `available` and
/// in the terminal no-envelope restart shape. A pending row is authority only
/// while the caller proves that this process owns the matching deferred or
/// transport-only completion fingerprint. The parent and exact single-row
/// attachment predicates are repeated by the envelope UPDATE itself.
Future<OutgoingDirectPrivateEnvelopeHandoffOutcome>
dbCommitOutgoingDirectPrivateWireEnvelope(
  Database db,
  Map<String, Object?> completionRow, {
  required String expectedPendingLocalPath,
  required String envelope,
  required bool hasOwnedPendingCompletion,
}) {
  final messageId = completionRow['message_id'] as String? ?? '';
  final attachmentId = completionRow['id'] as String? ?? '';
  final mime = completionRow['mime'] as String? ?? '';
  final size = (completionRow['size'] as num?)?.toInt() ?? 0;
  bool hasValue(String field) {
    final value = completionRow[field];
    return value is String && value.trim().isNotEmpty;
  }

  if (messageId.isEmpty ||
      attachmentId.isEmpty ||
      mime.isEmpty ||
      size <= 0 ||
      envelope.trim().isEmpty ||
      completionRow['owner_lane'] != MediaOwnerLane.direct.dbValue ||
      completionRow['download_status'] != 'done' ||
      !hasValue('content_hash') ||
      !hasValue('encryption_key_base64') ||
      !hasValue('encryption_nonce') ||
      !hasValue('encryption_scheme')) {
    return Future<OutgoingDirectPrivateEnvelopeHandoffOutcome>.value(
      OutgoingDirectPrivateEnvelopeHandoffOutcome.refused,
    );
  }

  return dbWriteTransaction(db, (txn) async {
    final parentRows = await txn.query(
      'messages',
      where: 'id = ?',
      whereArgs: <Object?>[messageId],
      limit: 1,
    );
    if (parentRows.isEmpty) {
      return OutgoingDirectPrivateEnvelopeHandoffOutcome.refused;
    }
    final parent = parentRows.single;
    final contactPeerId = parent['contact_peer_id'] as String? ?? '';
    if (((parent['is_incoming'] as num?)?.toInt() ?? 0) != 0 ||
        parent['hidden_at'] != null ||
        parent['deleted_at'] != null ||
        (parent['private_media_policy_version'] as num?)?.toInt() != 1 ||
        !const <String>{
          'protected',
          'view_once',
        }.contains(parent['private_media_mode']) ||
        !const <String>{'sending', 'failed'}.contains(parent['status']) ||
        !DirectPrivateMediaPathGuard.identifiersAreSafe(
          contactPeerId: contactPeerId,
          messageId: messageId,
          attachmentId: attachmentId,
        )) {
      return OutgoingDirectPrivateEnvelopeHandoffOutcome.refused;
    }

    late final String canonicalPath;
    late final String conventionPendingPath;
    try {
      canonicalPath = MediaFilePathConvention.relativePathForAttachment(
        contactPeerId: contactPeerId,
        blobId: attachmentId,
        mime: mime,
      );
      conventionPendingPath =
          MediaFilePathConvention.relativePathForPendingUpload(
            messageId: messageId,
            attachmentId: attachmentId,
            mime: mime,
          );
    } catch (_) {
      return OutgoingDirectPrivateEnvelopeHandoffOutcome.refused;
    }
    if (expectedPendingLocalPath != conventionPendingPath ||
        completionRow['local_path'] != canonicalPath) {
      return OutgoingDirectPrivateEnvelopeHandoffOutcome.refused;
    }

    final rows = await txn.query(
      'media_attachments',
      where: 'message_id = ? AND owner_lane = ?',
      whereArgs: <Object?>[messageId, MediaOwnerLane.direct.dbValue],
    );
    if (rows.length != 1 || rows.single['id'] != attachmentId) {
      return OutgoingDirectPrivateEnvelopeHandoffOutcome.refused;
    }
    final persisted = rows.single;
    final expectedKeyReference = secureStoreReferenceForKey(
      mediaAttachmentEncryptionKeyStoreName(attachmentId),
    );
    final canonicalFingerprintMatches =
        persisted['local_path'] == canonicalPath &&
        persisted['download_status'] == 'done' &&
        persisted['mime'] == mime &&
        persisted['size'] == size &&
        persisted['content_hash'] == completionRow['content_hash'] &&
        persisted['thumbnail_hash'] == completionRow['thumbnail_hash'] &&
        persisted['encryption_key_base64'] == expectedKeyReference &&
        persisted['encryption_nonce'] == completionRow['encryption_nonce'] &&
        persisted['encryption_scheme'] == completionRow['encryption_scheme'];
    final pendingIdentityMatches =
        persisted['local_path'] == conventionPendingPath &&
        persisted['download_status'] == 'upload_pending' &&
        persisted['mime'] == mime &&
        persisted['size'] == size;
    final state = parent['private_media_state'] as String?;
    final terminalAt = parent['private_media_terminal_at_ms'];
    final bool useCanonicalPredicate;
    if (state == 'available' &&
        parent['private_media_revealed_at_ms'] == null &&
        terminalAt == null &&
        canonicalFingerprintMatches) {
      useCanonicalPredicate = true;
    } else if ((state == 'opening' || state == 'viewing') &&
        terminalAt == null &&
        hasOwnedPendingCompletion &&
        pendingIdentityMatches) {
      useCanonicalPredicate = false;
    } else if (state == 'consumed' && terminalAt != null) {
      if (canonicalFingerprintMatches) {
        useCanonicalPredicate = true;
      } else if (hasOwnedPendingCompletion && pendingIdentityMatches) {
        useCanonicalPredicate = false;
      } else {
        return OutgoingDirectPrivateEnvelopeHandoffOutcome.refused;
      }
    } else {
      return OutgoingDirectPrivateEnvelopeHandoffOutcome.refused;
    }

    final existingEnvelope = parent['wire_envelope'];
    final envelopeMissing =
        existingEnvelope == null ||
        (existingEnvelope is String && existingEnvelope.isEmpty) ||
        (existingEnvelope is List<int> && existingEnvelope.isEmpty);
    if (!envelopeMissing) {
      return existingEnvelope == envelope
          ? OutgoingDirectPrivateEnvelopeHandoffOutcome.idempotent
          : OutgoingDirectPrivateEnvelopeHandoffOutcome.refused;
    }

    final statePredicate = switch (state) {
      'available' =>
        "private_media_state = 'available' "
            'AND private_media_revealed_at_ms IS NULL '
            'AND private_media_terminal_at_ms IS NULL',
      'opening' || 'viewing' =>
        'private_media_state = ? AND private_media_terminal_at_ms IS NULL',
      'consumed' =>
        "private_media_state = 'consumed' "
            'AND private_media_terminal_at_ms IS NOT NULL',
      _ => '0',
    };
    final attachmentPredicate = useCanonicalPredicate
        ? "attachment.download_status = 'done' "
              'AND attachment.local_path = ? AND attachment.mime = ? '
              'AND attachment.size = ? AND attachment.content_hash = ? '
              'AND attachment.thumbnail_hash IS ? '
              'AND attachment.encryption_key_base64 = ? '
              'AND attachment.encryption_nonce = ? '
              'AND attachment.encryption_scheme = ?'
        : "attachment.download_status = 'upload_pending' "
              'AND attachment.local_path = ? AND attachment.mime = ? '
              'AND attachment.size = ?';
    final args = <Object?>[
      envelope,
      messageId,
      if (state == 'opening' || state == 'viewing') state,
      attachmentId,
      MediaOwnerLane.direct.dbValue,
      if (useCanonicalPredicate) ...<Object?>[
        canonicalPath,
        mime,
        size,
        completionRow['content_hash'],
        completionRow['thumbnail_hash'],
        expectedKeyReference,
        completionRow['encryption_nonce'],
        completionRow['encryption_scheme'],
      ] else ...<Object?>[conventionPendingPath, mime, size],
      MediaOwnerLane.direct.dbValue,
    ];
    final changed = await txn.rawUpdate(
      'UPDATE messages SET wire_envelope = ? WHERE id = ? '
      'AND is_incoming = 0 AND hidden_at IS NULL AND deleted_at IS NULL '
      "AND status IN ('sending','failed') "
      'AND private_media_policy_version = 1 '
      "AND private_media_mode IN ('protected','view_once') "
      'AND $statePredicate '
      'AND (wire_envelope IS NULL OR length(wire_envelope) = 0) '
      'AND EXISTS (SELECT 1 FROM media_attachments attachment '
      'WHERE attachment.message_id = messages.id AND attachment.id = ? '
      'AND attachment.owner_lane = ? AND $attachmentPredicate) '
      'AND (SELECT COUNT(*) FROM media_attachments exact_set '
      'WHERE exact_set.message_id = messages.id '
      'AND exact_set.owner_lane = ?) = 1',
      args,
    );
    return changed == 1
        ? OutgoingDirectPrivateEnvelopeHandoffOutcome.committed
        : OutgoingDirectPrivateEnvelopeHandoffOutcome.refused;
  });
}

/// Post-network transport settlement for one exact outgoing protected or
/// view-once message.
///
/// This is intentionally a column-only CAS. It never rewrites content,
/// deletion markers, private lifecycle fields, or attachments. A concurrent
/// user hide/delete (including physical parent removal) wins and is reported
/// as [OutgoingDirectPrivateTransportSettlementOutcome.preservedUserIntent]
/// so callers cannot fall back to a stale full save.
Future<OutgoingDirectPrivateTransportSettlementOutcome>
dbSettleOutgoingDirectPrivateTransport(
  Database db, {
  required String messageId,
  required String? attachmentId,
  required String expectedEnvelope,
  required String status,
  required String? transport,
  required int? relayExpiresAt,
}) {
  const statuses = <String>{'failed', 'sent', 'inboxed', 'delivered'};
  const transports = <String>{
    'wifi',
    'local',
    'direct',
    'reuse',
    'relay',
    'inbox',
  };
  final shapeIsValid =
      messageId.isNotEmpty &&
      (attachmentId == null || attachmentId.isNotEmpty) &&
      expectedEnvelope.isNotEmpty &&
      statuses.contains(status) &&
      (transport == null || transports.contains(transport)) &&
      (status != 'inboxed' || transport == 'inbox') &&
      (status != 'failed' || transport == null) &&
      (relayExpiresAt == null ||
          (relayExpiresAt > 0 && status == 'inboxed' && transport == 'inbox'));
  if (!shapeIsValid) {
    return Future<OutgoingDirectPrivateTransportSettlementOutcome>.value(
      OutgoingDirectPrivateTransportSettlementOutcome.refused,
    );
  }

  return dbWriteTransaction(db, (txn) async {
    final parents = await txn.query(
      'messages',
      where: 'id = ?',
      whereArgs: <Object?>[messageId],
      limit: 1,
    );
    if (parents.isEmpty) {
      return OutgoingDirectPrivateTransportSettlementOutcome
          .preservedUserIntent;
    }
    final parent = parents.single;
    if (parent['hidden_at'] != null || parent['deleted_at'] != null) {
      return OutgoingDirectPrivateTransportSettlementOutcome
          .preservedUserIntent;
    }
    final contactPeerId = parent['contact_peer_id'] as String? ?? '';
    final identifiersAreSafe = attachmentId == null
        ? DirectPrivateMediaPathGuard.isSafeSegment(contactPeerId) &&
              DirectPrivateMediaPathGuard.isSafeSegment(messageId)
        : DirectPrivateMediaPathGuard.identifiersAreSafe(
            contactPeerId: contactPeerId,
            messageId: messageId,
            attachmentId: attachmentId,
          );
    if (((parent['is_incoming'] as num?)?.toInt() ?? 0) != 0 ||
        (parent['private_media_policy_version'] as num?)?.toInt() != 1 ||
        !const <String>{
          'protected',
          'view_once',
        }.contains(parent['private_media_mode']) ||
        !identifiersAreSafe) {
      return OutgoingDirectPrivateTransportSettlementOutcome.refused;
    }

    final directAttachments = await txn.query(
      'media_attachments',
      columns: const <String>['id', 'download_status'],
      where: 'message_id = ? AND owner_lane = ?',
      whereArgs: <Object?>[messageId, MediaOwnerLane.direct.dbValue],
    );
    final privateState = parent['private_media_state'];
    final revealedAt = parent['private_media_revealed_at_ms'];
    final terminalAt = parent['private_media_terminal_at_ms'];
    final lifecycleAcceptsLiveAttachment =
        (privateState == 'available' &&
            revealedAt == null &&
            terminalAt == null) ||
        (const <String>{'opening', 'viewing'}.contains(privateState) &&
            terminalAt == null) ||
        (privateState == 'consumed' && terminalAt != null);
    final cleanedTerminalAuthority =
        privateState == 'consumed' &&
        terminalAt != null &&
        directAttachments.isEmpty;
    final localAuthorityIsExact =
        cleanedTerminalAuthority ||
        (attachmentId != null &&
            lifecycleAcceptsLiveAttachment &&
            directAttachments.length == 1 &&
            directAttachments.single['id'] == attachmentId &&
            const <String>{
              'done',
              'upload_pending',
            }.contains(directAttachments.single['download_status']));
    if (!localAuthorityIsExact) {
      return OutgoingDirectPrivateTransportSettlementOutcome.refused;
    }

    final targetEnvelope = status == 'delivered' ? null : expectedEnvelope;
    final alreadySettled =
        parent['status'] == status &&
        parent['transport'] == transport &&
        parent['relay_expires_at'] == relayExpiresAt &&
        parent['wire_envelope'] == targetEnvelope;
    if (alreadySettled) {
      return OutgoingDirectPrivateTransportSettlementOutcome.idempotent;
    }
    if (parent['wire_envelope'] != expectedEnvelope) {
      return OutgoingDirectPrivateTransportSettlementOutcome.refused;
    }

    final allowedCurrentStatuses = switch (status) {
      'delivered' => const <String>['sending', 'failed', 'sent', 'inboxed'],
      'inboxed' => const <String>['sending', 'failed', 'sent', 'inboxed'],
      'sent' => const <String>['sending', 'failed', 'sent'],
      'failed' => const <String>['sending', 'failed'],
      _ => const <String>[],
    };
    if (!allowedCurrentStatuses.contains(parent['status'])) {
      return OutgoingDirectPrivateTransportSettlementOutcome.refused;
    }
    final statusPlaceholders = List<String>.filled(
      allowedCurrentStatuses.length,
      '?',
    ).join(',');
    const cleanedTerminalPredicate =
        '(private_media_state = \'consumed\' '
        'AND private_media_terminal_at_ms IS NOT NULL '
        'AND NOT EXISTS (SELECT 1 FROM media_attachments cleaned_attachment '
        'WHERE cleaned_attachment.message_id = messages.id '
        'AND cleaned_attachment.owner_lane = ?))';
    final localAuthorityPredicate = attachmentId == null
        ? 'AND $cleanedTerminalPredicate'
        : 'AND ($cleanedTerminalPredicate OR ('
              '((private_media_state = \'available\' '
              'AND private_media_revealed_at_ms IS NULL '
              'AND private_media_terminal_at_ms IS NULL) '
              'OR (private_media_state IN (\'opening\',\'viewing\') '
              'AND private_media_terminal_at_ms IS NULL) '
              'OR (private_media_state = \'consumed\' '
              'AND private_media_terminal_at_ms IS NOT NULL)) '
              'AND EXISTS (SELECT 1 FROM media_attachments attachment '
              'WHERE attachment.message_id = messages.id '
              'AND attachment.id = ? AND attachment.owner_lane = ? '
              "AND attachment.download_status IN ('done','upload_pending')) "
              'AND (SELECT COUNT(*) FROM media_attachments exact_set '
              'WHERE exact_set.message_id = messages.id '
              'AND exact_set.owner_lane = ?) = 1))';
    final localAuthorityArgs = attachmentId == null
        ? <Object?>[MediaOwnerLane.direct.dbValue]
        : <Object?>[
            MediaOwnerLane.direct.dbValue,
            attachmentId,
            MediaOwnerLane.direct.dbValue,
            MediaOwnerLane.direct.dbValue,
          ];
    final changed = await txn.rawUpdate(
      'UPDATE messages SET status = ?, transport = ?, '
      'relay_expires_at = ?, wire_envelope = ? '
      'WHERE id = ? AND is_incoming = 0 '
      'AND hidden_at IS NULL AND deleted_at IS NULL '
      'AND private_media_policy_version = 1 '
      "AND private_media_mode IN ('protected','view_once') "
      'AND wire_envelope = ? AND status IN ($statusPlaceholders) '
      '$localAuthorityPredicate',
      <Object?>[
        status,
        transport,
        relayExpiresAt,
        targetEnvelope,
        messageId,
        expectedEnvelope,
        ...allowedCurrentStatuses,
        ...localAuthorityArgs,
      ],
    );
    if (changed == 1) {
      return OutgoingDirectPrivateTransportSettlementOutcome.committed;
    }

    final after = await txn.query(
      'messages',
      where: 'id = ?',
      whereArgs: <Object?>[messageId],
      limit: 1,
    );
    if (after.isEmpty ||
        after.single['hidden_at'] != null ||
        after.single['deleted_at'] != null) {
      return OutgoingDirectPrivateTransportSettlementOutcome
          .preservedUserIntent;
    }
    return OutgoingDirectPrivateTransportSettlementOutcome.refused;
  });
}

// ---------------------------------------------------------------------------
// Direct private-media lifecycle (Plan 234 / Session 03)
// ---------------------------------------------------------------------------

({bool valid, String sql, List<Object?> args})
_directPrivateMediaLeaseIdentityPredicate({
  required bool? isIncoming,
  required String? mode,
  required String? attachmentId,
  required String? storedLocalPath,
}) {
  final fields = <Object?>[isIncoming, mode, attachmentId, storedLocalPath];
  if (fields.every((field) => field == null)) {
    return (valid: true, sql: '', args: const <Object?>[]);
  }
  final modeAllowed = isIncoming == true
      ? mode == 'view_once'
      : isIncoming == false
      ? mode == 'protected' || mode == 'view_once'
      : false;
  if (!modeAllowed ||
      attachmentId == null ||
      attachmentId.isEmpty ||
      storedLocalPath == null ||
      storedLocalPath.isEmpty) {
    return (valid: false, sql: '', args: const <Object?>[]);
  }
  final downloadStatusPredicate = isIncoming == true
      ? "= 'done'"
      : "IN ('done','upload_pending')";
  return (
    valid: true,
    sql:
        'AND is_incoming = ? AND private_media_mode = ? '
        'AND EXISTS (SELECT 1 FROM media_attachments lease_attachment '
        'WHERE lease_attachment.message_id = messages.id '
        'AND lease_attachment.id = ? '
        "AND lease_attachment.owner_lane = 'direct' "
        'AND lease_attachment.download_status $downloadStatusPredicate '
        'AND lease_attachment.local_path = ?) ',
    args: <Object?>[isIncoming! ? 1 : 0, mode, attachmentId, storedLocalPath],
  );
}

/// CAS: only one qualified direct private parent may claim `available` as
/// `opening`. Incoming authority is View Once only; outgoing authority is the
/// sender's single one-more-look for protected or View Once media.
Future<int> dbClaimDirectPrivateMediaOpening(
  Database db,
  String id, {
  required int nowMs,
  bool? isIncoming,
  String? mode,
  String? attachmentId,
  String? storedLocalPath,
}) {
  final identity = _directPrivateMediaLeaseIdentityPredicate(
    isIncoming: isIncoming,
    mode: mode,
    attachmentId: attachmentId,
    storedLocalPath: storedLocalPath,
  );
  if (!identity.valid) return Future<int>.value(0);
  return db.rawUpdate(
    "UPDATE messages SET private_media_state = 'opening', "
    'private_media_clock_high_water_ms = '
    'MAX(COALESCE(private_media_clock_high_water_ms, 0), ?) '
    "WHERE id = ? AND hidden_at IS NULL "
    "AND deleted_at IS NULL AND private_media_policy_version = 1 "
    "AND ((is_incoming = 1 AND private_media_mode = 'view_once') "
    "OR (is_incoming = 0 AND private_media_mode IN ('protected','view_once'))) "
    '${identity.sql}'
    "AND private_media_state = 'available' "
    'AND private_media_terminal_at_ms IS NULL',
    <Object?>[nowMs, id, ...identity.args],
  );
}

/// CAS: records the first rendered frame exactly once for a qualified lease.
Future<int> dbMarkDirectPrivateMediaViewing(
  Database db,
  String id, {
  required int nowMs,
  bool? isIncoming,
  String? mode,
  String? attachmentId,
  String? storedLocalPath,
}) {
  final identity = _directPrivateMediaLeaseIdentityPredicate(
    isIncoming: isIncoming,
    mode: mode,
    attachmentId: attachmentId,
    storedLocalPath: storedLocalPath,
  );
  if (!identity.valid) return Future<int>.value(0);
  return db.rawUpdate(
    "UPDATE messages SET private_media_state = 'viewing', "
    'private_media_revealed_at_ms = '
    'COALESCE(private_media_revealed_at_ms, ?), '
    'private_media_clock_high_water_ms = '
    'MAX(COALESCE(private_media_clock_high_water_ms, 0), ?) '
    "WHERE id = ? AND hidden_at IS NULL "
    "AND deleted_at IS NULL AND private_media_policy_version = 1 "
    "AND ((is_incoming = 1 AND private_media_mode = 'view_once') "
    "OR (is_incoming = 0 AND private_media_mode IN ('protected','view_once'))) "
    '${identity.sql}'
    "AND private_media_state = 'opening' "
    'AND private_media_terminal_at_ms IS NULL',
    <Object?>[nowMs, nowMs, id, ...identity.args],
  );
}

/// CAS used only after the engine proves ownership of the same-process,
/// pre-first-frame lease. Persisted state alone never grants rollback.
Future<int> dbRollbackDirectPrivateMediaOpening(
  Database db,
  String id, {
  bool? isIncoming,
  String? mode,
  String? attachmentId,
  String? storedLocalPath,
}) {
  final identity = _directPrivateMediaLeaseIdentityPredicate(
    isIncoming: isIncoming,
    mode: mode,
    attachmentId: attachmentId,
    storedLocalPath: storedLocalPath,
  );
  if (!identity.valid) return Future<int>.value(0);
  return db.rawUpdate(
    "UPDATE messages SET private_media_state = 'available' "
    "WHERE id = ? AND hidden_at IS NULL "
    "AND deleted_at IS NULL AND private_media_policy_version = 1 "
    "AND ((is_incoming = 1 AND private_media_mode = 'view_once') "
    "OR (is_incoming = 0 AND private_media_mode IN ('protected','view_once'))) "
    '${identity.sql}'
    "AND private_media_state = 'opening' "
    'AND private_media_revealed_at_ms IS NULL '
    'AND private_media_terminal_at_ms IS NULL',
    <Object?>[id, ...identity.args],
  );
}

/// Exact fail-closed quarantine used only after terminalization persistence
/// failed and an authoritative reread still proved the original row available.
/// Every durable authority dimension is included in the same CAS.
Future<int> dbQuarantineIndeterminateDirectPrivateMediaAvailable(
  Database db,
  String id, {
  required bool isIncoming,
  required String mode,
  required String attachmentId,
  required String storedLocalPath,
  required int nowMs,
}) {
  final modeAllowed = isIncoming
      ? mode == 'view_once'
      : mode == 'protected' || mode == 'view_once';
  if (!modeAllowed ||
      id.isEmpty ||
      attachmentId.isEmpty ||
      storedLocalPath.isEmpty) {
    return Future<int>.value(0);
  }
  final downloadStatusPredicate = isIncoming
      ? "= 'done'"
      : "IN ('done','upload_pending')";
  return db.rawUpdate(
    "UPDATE messages SET private_media_state = 'opening', "
    'private_media_clock_high_water_ms = '
    'MAX(COALESCE(private_media_clock_high_water_ms, 0), ?) '
    'WHERE id = ? AND is_incoming = ? AND hidden_at IS NULL '
    'AND deleted_at IS NULL AND private_media_policy_version = 1 '
    'AND private_media_mode = ? '
    "AND private_media_state = 'available' "
    'AND private_media_revealed_at_ms IS NULL '
    'AND private_media_terminal_at_ms IS NULL '
    'AND EXISTS (SELECT 1 FROM media_attachments attachment '
    'WHERE attachment.message_id = messages.id '
    'AND attachment.id = ? '
    "AND attachment.owner_lane = 'direct' "
    'AND attachment.download_status $downloadStatusPredicate '
    'AND attachment.local_path = ?)',
    <Object?>[
      nowMs,
      id,
      isIncoming ? 1 : 0,
      mode,
      attachmentId,
      storedLocalPath,
    ],
  );
}

/// CAS terminal claim for View Once. File/key cleanup must happen only after
/// this write succeeds (or after a later pass observes the durable terminal).
Future<int> dbConsumeDirectPrivateMedia(
  Database db,
  String id, {
  required int nowMs,
  bool? isIncoming,
  String? mode,
  String? attachmentId,
  String? storedLocalPath,
}) {
  final identity = _directPrivateMediaLeaseIdentityPredicate(
    isIncoming: isIncoming,
    mode: mode,
    attachmentId: attachmentId,
    storedLocalPath: storedLocalPath,
  );
  if (!identity.valid) return Future<int>.value(0);
  return db.rawUpdate(
    "UPDATE messages SET private_media_state = 'consumed', "
    'private_media_terminal_at_ms = '
    'COALESCE(private_media_terminal_at_ms, ?), '
    'private_media_clock_high_water_ms = '
    'MAX(COALESCE(private_media_clock_high_water_ms, 0), ?) '
    "WHERE id = ? AND hidden_at IS NULL "
    "AND deleted_at IS NULL AND private_media_policy_version = 1 "
    "AND ((is_incoming = 1 AND private_media_mode = 'view_once') "
    "OR (is_incoming = 0 AND private_media_mode IN ('protected','view_once'))) "
    '${identity.sql}'
    "AND private_media_state IN ('opening', 'viewing') "
    'AND private_media_terminal_at_ms IS NULL',
    <Object?>[nowMs, nowMs, id, ...identity.args],
  );
}

/// Atomically advances receiver-local clock state and expires a disappearing
/// parent at `effectiveNow >= expiresAt`. Normal rows expire from `available`;
/// impossible legacy/corrupt opening/viewing rows are terminalized fail closed.
/// Returns 1 when the addressed visible disappearing row was evaluated.
Future<int> dbAdvanceDirectPrivateMediaClockWithinTransaction(
  DatabaseExecutor txn,
  String id, {
  required int nowMs,
}) async {
  final evaluated = await txn.rawUpdate(
    'UPDATE messages SET private_media_clock_high_water_ms = '
    'MAX(COALESCE(private_media_clock_high_water_ms, 0), ?) '
    "WHERE id = ? AND is_incoming = 1 AND hidden_at IS NULL "
    "AND deleted_at IS NULL AND private_media_policy_version = 1 "
    "AND private_media_mode = 'disappearing' "
    "AND private_media_state IN ('available', 'opening', 'viewing') "
    'AND private_media_terminal_at_ms IS NULL '
    'AND private_media_expires_at_ms IS NOT NULL',
    [nowMs, id],
  );
  if (evaluated == 0) return 0;
  await txn.rawUpdate(
    "UPDATE messages SET private_media_state = 'expired', "
    'private_media_terminal_at_ms = '
    'COALESCE(private_media_terminal_at_ms, '
    'private_media_clock_high_water_ms) '
    "WHERE id = ? AND private_media_mode = 'disappearing' "
    "AND private_media_state IN ('available', 'opening', 'viewing') "
    'AND private_media_terminal_at_ms IS NULL '
    'AND private_media_expires_at_ms IS NOT NULL '
    'AND private_media_clock_high_water_ms >= private_media_expires_at_ms',
    [id],
  );
  return evaluated;
}

/// Shared write-side qualification for every direct-private attachment
/// mutation. The monotonic clock/rollback decision and the final active-parent
/// predicate run in the caller's transaction, so guarded save, local-ready,
/// failure, and final download commit cannot drift from expiry semantics.
Future<bool> dbAdvanceAndQualifyDirectPrivateMediaParentWithinTransaction(
  DatabaseExecutor txn,
  String id, {
  required int nowMs,
}) async {
  await dbAdvanceDirectPrivateMediaClockWithinTransaction(
    txn,
    id,
    nowMs: nowMs,
  );
  final parent = await txn.rawQuery(
    'SELECT 1 FROM messages WHERE id = ? AND is_incoming = 1 '
    'AND hidden_at IS NULL AND deleted_at IS NULL '
    'AND private_media_policy_version = 1 '
    "AND private_media_mode IN ('protected','view_once','disappearing') "
    "AND private_media_state = 'available' "
    'AND private_media_terminal_at_ms IS NULL '
    "AND (private_media_mode != 'disappearing' OR ("
    'private_media_expires_at_ms IS NOT NULL AND '
    'private_media_clock_high_water_ms IS NOT NULL AND '
    'private_media_clock_high_water_ms < private_media_expires_at_ms)) '
    'LIMIT 1',
    [id],
  );
  return parent.isNotEmpty;
}

Future<int> dbAdvanceDirectPrivateMediaClock(
  Database db,
  String id, {
  required int nowMs,
}) {
  return dbWriteTransaction(
    db,
    (txn) => dbAdvanceDirectPrivateMediaClockWithinTransaction(
      txn,
      id,
      nowMs: nowMs,
    ),
  );
}

/// Impossible/corrupt non-View-Once opening/viewing rows fail closed to the
/// existing terminal `unsupported` state; they never become a normal mode
/// transition or regain availability.
Future<int> dbFailClosedCorruptDirectPrivateMediaState(
  Database db,
  String id, {
  required int nowMs,
}) {
  return db.rawUpdate(
    "UPDATE messages SET private_media_state = 'unsupported', "
    'private_media_terminal_at_ms = '
    'COALESCE(private_media_terminal_at_ms, ?), '
    'private_media_clock_high_water_ms = '
    'MAX(COALESCE(private_media_clock_high_water_ms, 0), ?) '
    "WHERE id = ? AND is_incoming = 1 AND hidden_at IS NULL "
    "AND deleted_at IS NULL AND private_media_policy_version = 1 "
    "AND private_media_mode IN ('protected', 'disappearing') "
    "AND private_media_state IN ('opening', 'viewing') "
    'AND private_media_terminal_at_ms IS NULL',
    [nowMs, nowMs, id],
  );
}

/// Durable local Delete-for-me authority for private/unsupported direct rows.
/// The existing lifecycle state is intentionally retained: protected and
/// disappearing content must never be mislabeled consumed/expired.
Future<int> dbHideDirectPrivateMediaForMe(
  Database db,
  String id, {
  required String hiddenAt,
  required int nowMs,
}) {
  return db.rawUpdate(
    'UPDATE messages SET hidden_at = ?, text = ?, wire_envelope = NULL, '
    'private_media_terminal_at_ms = '
    'COALESCE(private_media_terminal_at_ms, ?), '
    'private_media_clock_high_water_ms = '
    'MAX(COALESCE(private_media_clock_high_water_ms, 0), ?) '
    'WHERE id = ? AND hidden_at IS NULL '
    "AND private_media_mode IN "
    "('protected', 'view_once', 'disappearing', 'unsupported')",
    [hiddenAt, '', nowMs, nowMs, id],
  );
}

/// Cross-table final commit for a direct private download.
///
/// Parent high-water/expiry evaluation and the exact attachment
/// `downloading -> done` path commit share one SQLite transaction. A process
/// lock orders file/key I/O, while this predicate is the durable authority
/// across processes and crashes.
Future<int> dbCommitDirectPrivateMediaDownloadIfEligible(
  Database db, {
  required String messageId,
  required String attachmentId,
  required String localPath,
  required int nowMs,
}) {
  return dbWriteTransaction(db, (txn) async {
    final identity = await txn.rawQuery(
      'SELECT parent.contact_peer_id AS contact_peer_id, '
      'attachment.mime AS mime FROM media_attachments attachment '
      'JOIN messages parent ON parent.id = attachment.message_id '
      'WHERE attachment.id = ? AND attachment.message_id = ? '
      "AND attachment.owner_lane = 'direct' LIMIT 1",
      [attachmentId, messageId],
    );
    if (identity.isEmpty) return 0;
    final expectedLocalPath = MediaFilePathConvention.relativePathForAttachment(
      contactPeerId: identity.single['contact_peer_id'] as String,
      blobId: attachmentId,
      mime: identity.single['mime'] as String,
    );
    if (localPath != expectedLocalPath) return 0;
    final parentEligible =
        await dbAdvanceAndQualifyDirectPrivateMediaParentWithinTransaction(
          txn,
          messageId,
          nowMs: nowMs,
        );
    if (!parentEligible) return 0;
    return txn.rawUpdate(
      'UPDATE media_attachments SET local_path = ?, download_status = ?, '
      'download_retry_count = 0 '
      'WHERE id = ? AND message_id = ? AND owner_lane = ? '
      'AND download_status = ? '
      'AND EXISTS ('
      'SELECT 1 FROM messages parent '
      'WHERE parent.id = ? AND parent.is_incoming = 1 '
      'AND parent.hidden_at IS NULL AND parent.deleted_at IS NULL '
      'AND parent.private_media_policy_version = 1 '
      "AND parent.private_media_mode IN "
      "('protected', 'view_once', 'disappearing') "
      "AND parent.private_media_state = 'available' "
      'AND parent.private_media_terminal_at_ms IS NULL '
      "AND (parent.private_media_mode != 'disappearing' OR ("
      'parent.private_media_expires_at_ms IS NOT NULL AND '
      'parent.private_media_clock_high_water_ms < '
      'parent.private_media_expires_at_ms)))',
      [
        localPath,
        'done',
        attachmentId,
        messageId,
        'direct',
        'downloading',
        messageId,
      ],
    );
  });
}

/// Next visible, available disappearing deadline for the foreground scheduler.
Future<int?> dbLoadNextDirectPrivateMediaExpiryAtMs(Database db) async {
  final rows = await db.rawQuery(
    'SELECT MIN(private_media_expires_at_ms) AS next_expiry '
    'FROM messages WHERE is_incoming = 1 AND hidden_at IS NULL '
    "AND deleted_at IS NULL AND private_media_policy_version = 1 "
    "AND private_media_mode = 'disappearing' "
    "AND private_media_state = 'available' "
    'AND private_media_terminal_at_ms IS NULL '
    'AND private_media_expires_at_ms IS NOT NULL',
  );
  return (rows.single['next_expiry'] as num?)?.toInt();
}

/// Bounded recipient-authored targets mirrored into the shared iOS Keychain
/// for reaction-notification eligibility. This is a projection query only; it
/// does not create reaction unread state or alter message rows.
Future<List<Map<String, Object?>>>
dbLoadLocallyAuthoredMessagesForReactionProjection(
  Database db, {
  int limit = 256,
}) {
  return db.query(
    'messages',
    where: 'is_incoming = 0 AND hidden_at IS NULL AND deleted_at IS NULL',
    orderBy: 'timestamp DESC, id ASC',
    limit: limit,
  );
}

Future<List<Map<String, Object?>>> dbLoadActiveDirectPrivateMediaDisappearing(
  Database db, {
  int limit = 100,
}) {
  return db.query(
    'messages',
    where:
        'is_incoming = 1 AND hidden_at IS NULL AND deleted_at IS NULL '
        'AND private_media_policy_version = 1 '
        "AND private_media_mode = 'disappearing' "
        "AND private_media_state = 'available' "
        'AND private_media_terminal_at_ms IS NULL '
        'AND private_media_expires_at_ms IS NOT NULL',
    orderBy: 'private_media_expires_at_ms ASC, id ASC',
    limit: limit,
  );
}

/// Bounded direct-parent candidates for resume/startup recovery. Hidden
/// private tombstones and durable consumed/expired rows stay queryable so
/// cleanup can retry after a file/key failure.
Future<List<Map<String, Object?>>> dbLoadDirectPrivateMediaRecoveryCandidates(
  Database db, {
  int limit = 100,
}) {
  return db.query(
    'messages',
    where:
        "private_media_mode IN ('protected','view_once','disappearing','unsupported') "
        'AND ((((is_incoming = 1 AND private_media_mode = \'view_once\') '
        "OR (is_incoming = 0 AND private_media_mode IN ('protected','view_once'))) "
        'AND private_media_policy_version = 1 '
        "AND private_media_state IN ('opening','viewing')) "
        'OR (is_incoming = 1 AND hidden_at IS NULL AND deleted_at IS NULL '
        'AND private_media_policy_version = 1 '
        "AND private_media_mode IN ('protected','view_once','disappearing') "
        "AND private_media_state = 'available' "
        'AND private_media_terminal_at_ms IS NULL '
        'AND EXISTS (SELECT 1 FROM media_attachments active_download '
        'WHERE active_download.message_id = messages.id '
        "AND active_download.owner_lane = 'direct' "
        "AND active_download.download_status = 'downloading')) "
        'OR ((private_media_state IN '
        "('consumed','expired','unsupported') OR hidden_at IS NOT NULL "
        'OR deleted_at IS NOT NULL) '
        'AND private_media_policy_version IS NOT NULL '
        'AND private_media_policy_version > 0 '
        'AND EXISTS (SELECT 1 FROM media_attachments attachment '
        "WHERE attachment.message_id = messages.id AND attachment.owner_lane = 'direct'))) ",
    orderBy: 'COALESCE(private_media_clock_high_water_ms, 0) ASC, id ASC',
    limit: limit,
  );
}

/// Durably rotates one failed recovery candidate to the end of the bounded
/// queue. Active available rows are deliberately ineligible.
Future<int> dbRotateDirectPrivateMediaRecoveryCandidate(
  Database db,
  String id, {
  required int nowMs,
}) {
  return db.rawUpdate(
    'UPDATE messages SET private_media_clock_high_water_ms = MAX('
    'COALESCE(private_media_clock_high_water_ms, 0) + 1, ?) '
    'WHERE id = ? '
    "AND private_media_mode IN ('protected','view_once','disappearing','unsupported') "
    'AND ((((is_incoming = 1 AND private_media_mode = \'view_once\') '
    "OR (is_incoming = 0 AND private_media_mode IN ('protected','view_once'))) "
    'AND private_media_policy_version = 1 '
    "AND private_media_state IN ('opening','viewing')) "
    'OR (is_incoming = 1 AND hidden_at IS NULL AND deleted_at IS NULL '
    'AND private_media_policy_version = 1 '
    "AND private_media_mode IN ('protected','view_once','disappearing') "
    "AND private_media_state = 'available' "
    'AND private_media_terminal_at_ms IS NULL '
    'AND EXISTS (SELECT 1 FROM media_attachments active_download '
    'WHERE active_download.message_id = messages.id '
    "AND active_download.owner_lane = 'direct' "
    "AND active_download.download_status = 'downloading')) "
    'OR ((private_media_state IN '
    "('consumed','expired','unsupported') OR hidden_at IS NOT NULL "
    'OR deleted_at IS NOT NULL) '
    'AND private_media_policy_version IS NOT NULL '
    'AND private_media_policy_version > 0 '
    'AND EXISTS (SELECT 1 FROM media_attachments attachment '
    "WHERE attachment.message_id = messages.id AND attachment.owner_lane = 'direct'))) ",
    [nowMs, id],
  );
}
