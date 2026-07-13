import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';
import '../db_write_transaction.dart';

/// Mutation kind accepted by [dbApplyIncomingReactionMutation].
enum DbIncomingReactionMutation { add, remove }

/// Result of one transactional incoming-reaction compare/write decision.
enum DbIncomingReactionApplyResult {
  inserted,
  updated,
  removed,
  exactReplay,
  stale,
}

/// Atomically applies an incoming ADD or REMOVE using the sender-authored
/// timestamp as the last-writer-wins comparand.
///
/// The read, comparison, and write intentionally live in one SQL transaction.
/// This makes the decision shared by every repository instance and isolate
/// using the same SQLCipher database instead of relying on an object-local
/// Dart mutex. A REMOVE writes a complete tombstone (including when it arrives
/// before its ADD), so an older delayed ADD cannot resurrect the reaction.
Future<DbIncomingReactionApplyResult> dbApplyIncomingReactionMutation(
  Database db,
  Map<String, Object?> row, {
  required DbIncomingReactionMutation mutation,
}) async {
  final id = _requiredReactionString(row, 'id');
  final messageId = _requiredReactionString(row, 'message_id');
  final senderPeerId = _requiredReactionString(row, 'sender_peer_id');
  final timestamp = _requiredReactionString(row, 'timestamp');

  emitFlowEvent(
    layer: 'DB',
    event: 'REACTION_DB_ATOMIC_APPLY_START',
    details: {
      'id': id.length > 8 ? id.substring(0, 8) : id,
      'mutation': mutation.name,
    },
  );

  try {
    final result = await dbWriteTransaction(db, (txn) async {
      final rows = await txn.query(
        'message_reactions',
        where: 'message_id = ? AND sender_peer_id = ?',
        whereArgs: [messageId, senderPeerId],
        limit: 1,
      );
      final current = rows.isEmpty ? null : rows.single;
      final incomingAt = DateTime.tryParse(timestamp);
      final currentTimestamp = current == null
          ? null
          : (current['removed_at'] as String? ??
                current['timestamp'] as String?);
      final currentAt = currentTimestamp == null
          ? null
          : DateTime.tryParse(currentTimestamp);
      if (incomingAt != null &&
          currentAt != null &&
          incomingAt.isBefore(currentAt)) {
        return DbIncomingReactionApplyResult.stale;
      }

      final currentId = current?['id'] as String?;
      final isExactReplay = mutation == DbIncomingReactionMutation.add
          ? currentId == id
          : currentId == id && current?['removed_at'] != null;
      if (isExactReplay) {
        return DbIncomingReactionApplyResult.exactReplay;
      }

      final normalizedRow = Map<String, Object?>.from(row);
      normalizedRow['removed_at'] =
          mutation == DbIncomingReactionMutation.remove ? timestamp : null;
      await txn.insert(
        'message_reactions',
        normalizedRow,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      if (mutation == DbIncomingReactionMutation.remove) {
        return DbIncomingReactionApplyResult.removed;
      }
      return current == null
          ? DbIncomingReactionApplyResult.inserted
          : DbIncomingReactionApplyResult.updated;
    });

    emitFlowEvent(
      layer: 'DB',
      event: 'REACTION_DB_ATOMIC_APPLY_SUCCESS',
      details: {'mutation': mutation.name, 'result': result.name},
    );
    return result;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'REACTION_DB_ATOMIC_APPLY_ERROR',
      details: {'mutation': mutation.name, 'error': e.toString()},
    );
    rethrow;
  }
}

String _requiredReactionString(Map<String, Object?> row, String key) {
  final value = row[key];
  if (value is! String || value.trim().isEmpty) {
    throw ArgumentError.value(value, key, 'must be a non-empty String');
  }
  return value;
}

/// Inserts or replaces a reaction in the database.
///
/// Uses REPLACE conflict algorithm so that re-inserting with the same
/// (message_id, sender_peer_id) pair replaces the existing row.
Future<void> dbInsertReaction(Database db, Map<String, Object?> row) async {
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
  Database db,
  String messageId,
) async {
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
  Database db,
  List<String> messageIds,
) async {
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
  Database db,
  String messageId,
  String senderPeerId, {
  String? removedAtTimestamp,
}) async {
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
  Database db,
  String messageId,
  String senderPeerId,
) async {
  final rows = await db.query(
    'message_reactions',
    where: 'message_id = ? AND sender_peer_id = ?',
    whereArgs: [messageId, senderPeerId],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.single;
}

/// Loads the bounded latest active/tombstoned reaction state for group
/// messages authored by [accountPeerId]. The shared reaction table also holds
/// direct-message rows, so the join is the causal lane discriminator.
Future<List<Map<String, Object?>>> dbLoadGroupReactionComparandsForProjection(
  Database db,
  String accountPeerId, {
  int limit = 1024,
}) async {
  if (accountPeerId.trim().isEmpty || limit <= 0) return const [];
  return db.rawQuery(
    'SELECT r.* FROM message_reactions AS r '
    'INNER JOIN group_messages AS g ON g.id = r.message_id '
    'WHERE g.sender_peer_id = ? '
    'ORDER BY COALESCE(r.removed_at, r.timestamp) DESC, r.id ASC '
    'LIMIT ?',
    <Object?>[accountPeerId, limit],
  );
}

/// Deletes all reactions for a specific message.
Future<int> dbDeleteReactionsForMessage(Database db, String messageId) async {
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
  Database db,
  String contactPeerId,
) async {
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
