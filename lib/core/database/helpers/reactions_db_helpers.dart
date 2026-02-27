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
      where: 'message_id = ?',
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
      'SELECT * FROM message_reactions WHERE message_id IN ($placeholders) ORDER BY timestamp ASC',
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

/// Deletes a reaction for a specific message and sender.
///
/// Returns the number of rows deleted (0 or 1).
Future<int> dbDeleteReaction(
    Database db, String messageId, String senderPeerId) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'REACTION_DB_DELETE_START',
    details: {
      'messageId': messageId.length > 8 ? messageId.substring(0, 8) : messageId,
    },
  );

  try {
    final count = await db.delete(
      'message_reactions',
      where: 'message_id = ? AND sender_peer_id = ?',
      whereArgs: [messageId, senderPeerId],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'REACTION_DB_DELETE_SUCCESS',
      details: {'count': count},
    );

    return count;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'REACTION_DB_DELETE_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
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
