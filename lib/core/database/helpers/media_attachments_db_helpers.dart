import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Inserts a media attachment into the database.
Future<void> dbInsertMediaAttachment(
    Database db, Map<String, Object?> row) async {
  final id = row['id'] as String? ?? '';

  emitFlowEvent(
    layer: 'DB',
    event: 'MEDIA_DB_INSERT_START',
    details: {'id': id.length > 8 ? id.substring(0, 8) : id},
  );

  try {
    await db.insert(
      'media_attachments',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_INSERT_SUCCESS',
      details: {'id': id.length > 8 ? id.substring(0, 8) : id},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_INSERT_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads all media attachments for a single message.
Future<List<Map<String, Object?>>> dbLoadMediaForMessage(
    Database db, String messageId) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MEDIA_DB_LOAD_FOR_MESSAGE_START',
    details: {
      'messageId': messageId.length > 8 ? messageId.substring(0, 8) : messageId,
    },
  );

  try {
    final results = await db.query(
      'media_attachments',
      where: 'message_id = ?',
      whereArgs: [messageId],
      orderBy: 'created_at ASC',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_LOAD_FOR_MESSAGE_SUCCESS',
      details: {'count': results.length},
    );

    return results;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_LOAD_FOR_MESSAGE_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads all media attachments for multiple messages in a single query.
Future<List<Map<String, Object?>>> dbLoadMediaForMessages(
    Database db, List<String> messageIds) async {
  if (messageIds.isEmpty) return [];

  emitFlowEvent(
    layer: 'DB',
    event: 'MEDIA_DB_LOAD_FOR_MESSAGES_START',
    details: {'messageCount': messageIds.length},
  );

  try {
    final placeholders = List.filled(messageIds.length, '?').join(',');
    final results = await db.rawQuery(
      'SELECT * FROM media_attachments WHERE message_id IN ($placeholders) ORDER BY created_at ASC',
      messageIds,
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_LOAD_FOR_MESSAGES_SUCCESS',
      details: {'count': results.length},
    );

    return results;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_LOAD_FOR_MESSAGES_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Updates the local path and download status of a media attachment.
Future<void> dbUpdateMediaLocalPath(
    Database db, String id, String localPath, String downloadStatus) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MEDIA_DB_UPDATE_LOCAL_PATH_START',
    details: {'id': id.length > 8 ? id.substring(0, 8) : id},
  );

  try {
    await db.update(
      'media_attachments',
      {'local_path': localPath, 'download_status': downloadStatus},
      where: 'id = ?',
      whereArgs: [id],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_UPDATE_LOCAL_PATH_SUCCESS',
      details: {'id': id.length > 8 ? id.substring(0, 8) : id},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_UPDATE_LOCAL_PATH_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Updates the download status of a media attachment.
Future<void> dbUpdateMediaDownloadStatus(
    Database db, String id, String downloadStatus) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MEDIA_DB_UPDATE_STATUS_START',
    details: {
      'id': id.length > 8 ? id.substring(0, 8) : id,
      'status': downloadStatus,
    },
  );

  try {
    await db.update(
      'media_attachments',
      {'download_status': downloadStatus},
      where: 'id = ?',
      whereArgs: [id],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_UPDATE_STATUS_SUCCESS',
      details: {'id': id.length > 8 ? id.substring(0, 8) : id},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_UPDATE_STATUS_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Deletes all media attachments for a message.
Future<int> dbDeleteMediaForMessage(Database db, String messageId) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MEDIA_DB_DELETE_FOR_MESSAGE_START',
    details: {
      'messageId': messageId.length > 8 ? messageId.substring(0, 8) : messageId,
    },
  );

  try {
    final count = await db.delete(
      'media_attachments',
      where: 'message_id = ?',
      whereArgs: [messageId],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_DELETE_FOR_MESSAGE_SUCCESS',
      details: {'count': count},
    );

    return count;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_DELETE_FOR_MESSAGE_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Deletes all media attachments for a contact via subquery on messages.
Future<int> dbDeleteMediaForContact(
    Database db, String contactPeerId) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MEDIA_DB_DELETE_FOR_CONTACT_START',
    details: {
      'contactPeerId': contactPeerId.length > 10
          ? contactPeerId.substring(0, 10)
          : contactPeerId,
    },
  );

  try {
    final count = await db.rawDelete(
      'DELETE FROM media_attachments WHERE message_id IN '
      '(SELECT id FROM messages WHERE contact_peer_id = ?)',
      [contactPeerId],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_DELETE_FOR_CONTACT_SUCCESS',
      details: {'count': count},
    );

    return count;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_DELETE_FOR_CONTACT_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Returns all media_attachments rows with download_status='upload_pending',
/// ordered by created_at ASC (oldest first).
///
/// These are outgoing attachments whose upload was interrupted before
/// completing. They must be re-uploaded on the next retry cycle.
///
/// Returns at most [limit] rows.
Future<List<Map<String, Object?>>> dbLoadUploadPendingAttachments(
  Database db, {
  int limit = 50,
}) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MEDIA_DB_LOAD_UPLOAD_PENDING_START',
    details: {'limit': limit},
  );

  try {
    final results = await db.query(
      'media_attachments',
      where: "download_status = 'upload_pending'",
      orderBy: 'created_at ASC',
      limit: limit,
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_LOAD_UPLOAD_PENDING_SUCCESS',
      details: {'count': results.length},
    );

    return results;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_LOAD_UPLOAD_PENDING_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads all media attachments with download_status = 'pending'.
Future<List<Map<String, Object?>>> dbLoadPendingMediaDownloads(
    Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MEDIA_DB_LOAD_PENDING_START',
    details: {},
  );

  try {
    final results = await db.query(
      'media_attachments',
      where: "download_status = ?",
      whereArgs: ['pending'],
      orderBy: 'created_at ASC',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_LOAD_PENDING_SUCCESS',
      details: {'count': results.length},
    );

    return results;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_LOAD_PENDING_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}
