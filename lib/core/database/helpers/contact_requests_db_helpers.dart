import 'package:sqflite/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Loads all pending contact requests from the database.
Future<List<Map<String, Object?>>> dbLoadPendingRequests(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'CONTACT_REQUESTS_DB_LOAD_PENDING_START',
    details: {},
  );

  try {
    final results = await db.query(
      'contact_requests',
      where: 'status = ?',
      whereArgs: ['pending'],
      orderBy: 'received_at DESC',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'CONTACT_REQUESTS_DB_LOAD_PENDING_SUCCESS',
      details: {'count': results.length},
    );

    return results;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'CONTACT_REQUESTS_DB_LOAD_PENDING_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads a single contact request by peer ID.
Future<Map<String, Object?>?> dbLoadRequest(Database db, String peerId) async {
  final peerIdPrefix = peerId.length > 10 ? peerId.substring(0, 10) : peerId;

  emitFlowEvent(
    layer: 'DB',
    event: 'CONTACT_REQUESTS_DB_LOAD_START',
    details: {'peerId': peerIdPrefix},
  );

  try {
    final results = await db.query(
      'contact_requests',
      where: 'peer_id = ?',
      whereArgs: [peerId],
      limit: 1,
    );

    if (results.isNotEmpty) {
      emitFlowEvent(
        layer: 'DB',
        event: 'CONTACT_REQUESTS_DB_LOAD_FOUND',
        details: {'peerId': peerIdPrefix},
      );
      return results.first;
    } else {
      emitFlowEvent(
        layer: 'DB',
        event: 'CONTACT_REQUESTS_DB_LOAD_NOT_FOUND',
        details: {'peerId': peerIdPrefix},
      );
      return null;
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'CONTACT_REQUESTS_DB_LOAD_ERROR',
      details: {'peerId': peerIdPrefix, 'error': e.toString()},
    );
    rethrow;
  }
}

/// Inserts or updates a contact request.
Future<void> dbUpsertRequest(Database db, Map<String, Object?> row) async {
  final peerId = row['peer_id'] as String? ?? '';
  final peerIdPrefix = peerId.length > 10 ? peerId.substring(0, 10) : peerId;

  emitFlowEvent(
    layer: 'DB',
    event: 'CONTACT_REQUESTS_DB_UPSERT_START',
    details: {'peerId': peerIdPrefix},
  );

  try {
    await db.insert(
      'contact_requests',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'CONTACT_REQUESTS_DB_UPSERT_SUCCESS',
      details: {'peerId': peerIdPrefix},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'CONTACT_REQUESTS_DB_UPSERT_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Updates the status of a contact request.
Future<void> dbUpdateRequestStatus(
  Database db,
  String peerId,
  String status,
) async {
  final peerIdPrefix = peerId.length > 10 ? peerId.substring(0, 10) : peerId;

  emitFlowEvent(
    layer: 'DB',
    event: 'CONTACT_REQUESTS_DB_UPDATE_STATUS_START',
    details: {'peerId': peerIdPrefix, 'status': status},
  );

  try {
    await db.update(
      'contact_requests',
      {'status': status},
      where: 'peer_id = ?',
      whereArgs: [peerId],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'CONTACT_REQUESTS_DB_UPDATE_STATUS_SUCCESS',
      details: {'peerId': peerIdPrefix, 'status': status},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'CONTACT_REQUESTS_DB_UPDATE_STATUS_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Deletes a contact request by peer ID.
Future<void> dbDeleteRequest(Database db, String peerId) async {
  final peerIdPrefix = peerId.length > 10 ? peerId.substring(0, 10) : peerId;

  emitFlowEvent(
    layer: 'DB',
    event: 'CONTACT_REQUESTS_DB_DELETE_START',
    details: {'peerId': peerIdPrefix},
  );

  try {
    await db.delete(
      'contact_requests',
      where: 'peer_id = ?',
      whereArgs: [peerId],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'CONTACT_REQUESTS_DB_DELETE_SUCCESS',
      details: {'peerId': peerIdPrefix},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'CONTACT_REQUESTS_DB_DELETE_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Checks if a contact request exists.
Future<bool> dbRequestExists(Database db, String peerId) async {
  try {
    final result = await db.query(
      'contact_requests',
      columns: ['peer_id'],
      where: 'peer_id = ?',
      whereArgs: [peerId],
      limit: 1,
    );
    return result.isNotEmpty;
  } catch (e) {
    return false;
  }
}
