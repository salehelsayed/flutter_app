import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Inserts or replaces a reaction in the database.
///
/// Uses REPLACE conflict algorithm so that re-inserting with the same
/// (message_id, sender_peer_id) pair replaces the existing row.
Future<void> dbInsertReaction(
    Database db, Map<String, Object?> row) async {
  final id = row['id'] as String? ?? '';

  emitFlowEvent(
    layer: 'DB',
    event: 'REACTION_DB_INSERT_START',
    details: {'id': id.length > 8 ? id.substring(0, 8) : id},
  );

  try {
    await db.insert(
      'message_reactions',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'REACTION_DB_INSERT_SUCCESS',
      details: {'id': id.length > 8 ? id.substring(0, 8) : id},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'REACTION_DB_INSERT_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads all reactions for a single message, ordered by timestamp ASC.
Future<List<Map<String, Object?>>> dbLoadReactionsForMessage(
    Database db, String messageId) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'REACTION_DB_LOAD_FOR_MSG_START',
    details: {
      'messageId': messageId.length > 8 ? messageId.substring(0, 8) : messageId,
    },
  );

  try {
    final results = await db.query(
      'message_reactions',
      where: 'message_id = ? AND removed_at IS NULL',
      whereArgs: [messageId],
      orderBy: 'timestamp ASC',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'REACTION_DB_LOAD_FOR_MSG_SUCCESS',
      details: {'count': results.length},
    );

    return results;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'REACTION_DB_LOAD_FOR_MSG_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads all reactions for multiple messages in a single query.
Future<List<Map<String, Object?>>> dbLoadReactionsForMessages(
    Database db, List<String> messageIds) async {
  if (messageIds.isEmpty) return [];

  emitFlowEvent(
    layer: 'DB',
    event: 'REACTION_DB_LOAD_FOR_MSGS_START',
    details: {'messageCount': messageIds.length},
  );

  try {
    final placeholders = List.filled(messageIds.length, '?').join(',');
    final results = await db.rawQuery(
      'SELECT * FROM message_reactions WHERE message_id IN ($placeholders) '
      'AND removed_at IS NULL ORDER BY timestamp ASC',
      messageIds,
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'REACTION_DB_LOAD_FOR_MSGS_SUCCESS',
      details: {'count': results.length},
    );

    return results;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'REACTION_DB_LOAD_FOR_MSGS_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Soft-deletes (tombstones) a reaction for a specific message and sender by
/// setting `removed_at` to the remove's sender-authored timestamp instead of
/// hard-deleting the row. The retained tombstone is the last-writer-wins
/// comparand that lets a later *older* add be recognised as stale and dropped
/// (INV-T1). Falls back to the local clock when [removedAtTimestamp] is null.
///
/// Only updates an existing row (the remove-then-stale-add case, where the
/// remove is applied after the add). Returns the number of rows tombstoned.
Future<int> dbDeleteReaction(
    Database db, String messageId, String senderPeerId,
    {String? removedAtTimestamp}) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'REACTION_DB_TOMBSTONE_START',
    details: {
      'messageId': messageId.length > 8 ? messageId.substring(0, 8) : messageId,
    },
  );

  try {
    final removedAt =
        removedAtTimestamp ?? DateTime.now().toUtc().toIso8601String();
    final count = await db.update(
      'message_reactions',
      {'removed_at': removedAt},
      where: 'message_id = ? AND sender_peer_id = ?',
      whereArgs: [messageId, senderPeerId],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'REACTION_DB_TOMBSTONE_SUCCESS',
      details: {'count': count},
    );

    return count;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'REACTION_DB_TOMBSTONE_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads the single reaction for (message, sender) — including a tombstoned one
/// — for the last-writer-wins comparand. Returns null when no row exists.
Future<Map<String, Object?>?> dbLoadActiveOrTombstonedReactionForSender(
    Database db, String messageId, String senderPeerId) async {
  final rows = await db.query(
    'message_reactions',
    where: 'message_id = ? AND sender_peer_id = ?',
    whereArgs: [messageId, senderPeerId],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.single;
}

/// Deletes all reactions for a specific message.
Future<int> dbDeleteReactionsForMessage(
    Database db, String messageId) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'REACTION_DB_DELETE_FOR_MSG_START',
    details: {
      'messageId': messageId.length > 8 ? messageId.substring(0, 8) : messageId,
    },
  );

  try {
    final count = await db.delete(
      'message_reactions',
      where: 'message_id = ?',
      whereArgs: [messageId],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'REACTION_DB_DELETE_FOR_MSG_SUCCESS',
      details: {'count': count},
    );

    return count;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'REACTION_DB_DELETE_FOR_MSG_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Deletes all reactions for a contact via subquery on messages table.
///
/// Must be called BEFORE dbDeleteMessagesForContact, because the subquery
/// needs the messages rows to exist.
Future<int> dbDeleteReactionsForContact(
    Database db, String contactPeerId) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'REACTION_DB_DELETE_FOR_CONTACT_START',
    details: {
      'contactPeerId': contactPeerId.length > 10
          ? contactPeerId.substring(0, 10)
          : contactPeerId,
    },
  );

  try {
    final count = await db.rawDelete(
      'DELETE FROM message_reactions WHERE message_id IN '
      '(SELECT id FROM messages WHERE contact_peer_id = ?)',
      [contactPeerId],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'REACTION_DB_DELETE_FOR_CONTACT_SUCCESS',
      details: {'count': count},
    );

    return count;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'REACTION_DB_DELETE_FOR_CONTACT_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}
