import 'package:sqflite/sqflite.dart';

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
