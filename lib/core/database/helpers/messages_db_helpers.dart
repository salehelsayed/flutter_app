import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Inserts a message into the database.
Future<void> dbInsertMessage(Database db, Map<String, Object?> row) async {
  final id = row['id'] as String? ?? '';

  emitFlowEvent(
    layer: 'DB',
    event: 'MESSAGES_DB_INSERT_START',
    details: {'id': id.length > 8 ? id.substring(0, 8) : id},
  );

  try {
    await db.insert(
      'messages',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

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
      'contactPeerId':
          contactPeerId.length > 10
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
        where: 'contact_peer_id = ? AND timestamp < ?',
        whereArgs: [contactPeerId, beforeTimestamp],
        orderBy: 'timestamp DESC',
        limit: limit,
      );
    } else {
      results = await db.query(
        'messages',
        where: 'contact_peer_id = ?',
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
      'contactPeerId':
          contactPeerId.length > 10
              ? contactPeerId.substring(0, 10)
              : contactPeerId,
    },
  );

  try {
    final results = await db.query(
      'messages',
      where: 'contact_peer_id = ?',
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
      'contactPeerId':
          contactPeerId.length > 10
              ? contactPeerId.substring(0, 10)
              : contactPeerId,
    },
  );

  try {
    final results = await db.query(
      'messages',
      where: 'contact_peer_id = ?',
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

/// Updates the status of a message by ID.
Future<void> dbUpdateMessageStatus(
  Database db,
  String id,
  String status,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MESSAGES_DB_UPDATE_STATUS_START',
    details: {'id': id.length > 8 ? id.substring(0, 8) : id, 'status': status},
  );

  try {
    await db.update(
      'messages',
      {'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_UPDATE_STATUS_SUCCESS',
      details: {'id': id.length > 8 ? id.substring(0, 8) : id},
    );
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
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM messages',
    );
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
      'contactPeerId':
          contactPeerId.length > 10
              ? contactPeerId.substring(0, 10)
              : contactPeerId,
    },
  );

  try {
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM messages WHERE contact_peer_id = ?',
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
      'contactPeerId':
          contactPeerId.length > 10
              ? contactPeerId.substring(0, 10)
              : contactPeerId,
    },
  );

  try {
    final now = DateTime.now().toUtc().toIso8601String();
    final count = await db.rawUpdate(
      'UPDATE messages SET read_at = ? WHERE contact_peer_id = ? AND is_incoming = 1 AND read_at IS NULL',
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
      'contactPeerId':
          contactPeerId.length > 10
              ? contactPeerId.substring(0, 10)
              : contactPeerId,
    },
  );

  try {
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM messages WHERE contact_peer_id = ? AND is_incoming = 1 AND read_at IS NULL',
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
      'SELECT COUNT(*) as count FROM messages WHERE is_incoming = 1 AND read_at IS NULL',
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
      'WHERE m.is_incoming = 1 AND m.read_at IS NULL AND c.is_archived = 0 AND c.is_blocked = 0',
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
Future<int> dbDeleteMessagesForContact(Database db, String contactPeerId) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MESSAGES_DB_DELETE_FOR_CONTACT_START',
    details: {
      'contactPeerId':
          contactPeerId.length > 10
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
