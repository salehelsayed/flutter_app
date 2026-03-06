import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Inserts or replaces an introduction row.
Future<void> dbInsertIntroduction(Database db, Map<String, Object?> row) async {
  final id = row['id'] as String? ?? '';

  emitFlowEvent(
    layer: 'DB',
    event: 'INTRODUCTIONS_DB_INSERT_START',
    details: {'id': id.length > 10 ? id.substring(0, 10) : id},
  );

  try {
    await db.insert(
      'introductions',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'INTRODUCTIONS_DB_INSERT_SUCCESS',
      details: {'id': id.length > 10 ? id.substring(0, 10) : id},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'INTRODUCTIONS_DB_INSERT_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads a single introduction by ID.
Future<Map<String, Object?>?> dbLoadIntroduction(Database db, String id) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'INTRODUCTIONS_DB_LOAD_START',
    details: {'id': id.length > 10 ? id.substring(0, 10) : id},
  );

  try {
    final results = await db.query(
      'introductions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (results.isNotEmpty) {
      emitFlowEvent(
        layer: 'DB',
        event: 'INTRODUCTIONS_DB_LOAD_FOUND',
        details: {'id': id.length > 10 ? id.substring(0, 10) : id},
      );
      return results.first;
    } else {
      emitFlowEvent(
        layer: 'DB',
        event: 'INTRODUCTIONS_DB_LOAD_NOT_FOUND',
        details: {'id': id.length > 10 ? id.substring(0, 10) : id},
      );
      return null;
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'INTRODUCTIONS_DB_LOAD_ERROR',
      details: {'id': id.length > 10 ? id.substring(0, 10) : id, 'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads all introductions where the user is the recipient.
Future<List<Map<String, Object?>>> dbLoadIntroductionsByRecipient(
  Database db,
  String recipientId,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'INTRODUCTIONS_DB_LOAD_BY_RECIPIENT_START',
    details: {'recipientId': recipientId.length > 10 ? recipientId.substring(0, 10) : recipientId},
  );

  try {
    final results = await db.query(
      'introductions',
      where: 'recipient_id = ?',
      whereArgs: [recipientId],
      orderBy: 'created_at DESC',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'INTRODUCTIONS_DB_LOAD_BY_RECIPIENT_SUCCESS',
      details: {'count': results.length},
    );

    return results;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'INTRODUCTIONS_DB_LOAD_BY_RECIPIENT_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads all introductions where the user is the introduced party.
Future<List<Map<String, Object?>>> dbLoadIntroductionsByIntroduced(
  Database db,
  String introducedId,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'INTRODUCTIONS_DB_LOAD_BY_INTRODUCED_START',
    details: {'introducedId': introducedId.length > 10 ? introducedId.substring(0, 10) : introducedId},
  );

  try {
    final results = await db.query(
      'introductions',
      where: 'introduced_id = ?',
      whereArgs: [introducedId],
      orderBy: 'created_at DESC',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'INTRODUCTIONS_DB_LOAD_BY_INTRODUCED_SUCCESS',
      details: {'count': results.length},
    );

    return results;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'INTRODUCTIONS_DB_LOAD_BY_INTRODUCED_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads all introductions where the user is the introducer.
Future<List<Map<String, Object?>>> dbLoadIntroductionsByIntroducer(
  Database db,
  String introducerId,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'INTRODUCTIONS_DB_LOAD_BY_INTRODUCER_START',
    details: {'introducerId': introducerId.length > 10 ? introducerId.substring(0, 10) : introducerId},
  );

  try {
    final results = await db.query(
      'introductions',
      where: 'introducer_id = ?',
      whereArgs: [introducerId],
      orderBy: 'created_at DESC',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'INTRODUCTIONS_DB_LOAD_BY_INTRODUCER_SUCCESS',
      details: {'count': results.length},
    );

    return results;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'INTRODUCTIONS_DB_LOAD_BY_INTRODUCER_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads introductions for a specific recipient from a specific introducer.
Future<List<Map<String, Object?>>> dbLoadIntroductionsForRecipientAndIntroducer(
  Database db,
  String recipientId,
  String introducerId,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'INTRODUCTIONS_DB_LOAD_BY_RECIPIENT_AND_INTRODUCER_START',
    details: {
      'recipientId': recipientId.length > 10 ? recipientId.substring(0, 10) : recipientId,
      'introducerId': introducerId.length > 10 ? introducerId.substring(0, 10) : introducerId,
    },
  );

  try {
    final results = await db.query(
      'introductions',
      where: 'recipient_id = ? AND introducer_id = ?',
      whereArgs: [recipientId, introducerId],
      orderBy: 'created_at DESC',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'INTRODUCTIONS_DB_LOAD_BY_RECIPIENT_AND_INTRODUCER_SUCCESS',
      details: {'count': results.length},
    );

    return results;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'INTRODUCTIONS_DB_LOAD_BY_RECIPIENT_AND_INTRODUCER_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Updates the recipient's status and responded timestamp.
Future<void> dbUpdateRecipientStatus(
  Database db,
  String id,
  String status,
  String respondedAt,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'INTRODUCTIONS_DB_UPDATE_RECIPIENT_STATUS_START',
    details: {'id': id.length > 10 ? id.substring(0, 10) : id, 'status': status},
  );

  try {
    await db.rawUpdate(
      'UPDATE introductions SET recipient_status = ?, recipient_responded_at = ? WHERE id = ?',
      [status, respondedAt, id],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'INTRODUCTIONS_DB_UPDATE_RECIPIENT_STATUS_SUCCESS',
      details: {'id': id.length > 10 ? id.substring(0, 10) : id, 'status': status},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'INTRODUCTIONS_DB_UPDATE_RECIPIENT_STATUS_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Updates the introduced party's status and responded timestamp.
Future<void> dbUpdateIntroducedStatus(
  Database db,
  String id,
  String status,
  String respondedAt,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'INTRODUCTIONS_DB_UPDATE_INTRODUCED_STATUS_START',
    details: {'id': id.length > 10 ? id.substring(0, 10) : id, 'status': status},
  );

  try {
    await db.rawUpdate(
      'UPDATE introductions SET introduced_status = ?, introduced_responded_at = ? WHERE id = ?',
      [status, respondedAt, id],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'INTRODUCTIONS_DB_UPDATE_INTRODUCED_STATUS_SUCCESS',
      details: {'id': id.length > 10 ? id.substring(0, 10) : id, 'status': status},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'INTRODUCTIONS_DB_UPDATE_INTRODUCED_STATUS_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Updates the overall status of an introduction.
Future<void> dbUpdateOverallStatus(
  Database db,
  String id,
  String status,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'INTRODUCTIONS_DB_UPDATE_OVERALL_STATUS_START',
    details: {'id': id.length > 10 ? id.substring(0, 10) : id, 'status': status},
  );

  try {
    await db.rawUpdate(
      'UPDATE introductions SET status = ? WHERE id = ?',
      [status, id],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'INTRODUCTIONS_DB_UPDATE_OVERALL_STATUS_SUCCESS',
      details: {'id': id.length > 10 ? id.substring(0, 10) : id, 'status': status},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'INTRODUCTIONS_DB_UPDATE_OVERALL_STATUS_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads pending introductions for a user (as recipient or introduced).
Future<List<Map<String, Object?>>> dbLoadPendingIntroductionsForUser(
  Database db,
  String peerId,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'INTRODUCTIONS_DB_LOAD_PENDING_START',
    details: {'peerId': peerId.length > 10 ? peerId.substring(0, 10) : peerId},
  );

  try {
    final results = await db.rawQuery(
      "SELECT * FROM introductions WHERE (recipient_id = ? OR introduced_id = ?) AND status = 'pending' ORDER BY created_at DESC",
      [peerId, peerId],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'INTRODUCTIONS_DB_LOAD_PENDING_SUCCESS',
      details: {'count': results.length},
    );

    return results;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'INTRODUCTIONS_DB_LOAD_PENDING_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Counts pending introductions for a user (as recipient or introduced).
Future<int> dbCountPendingIntroductions(Database db, String peerId) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'INTRODUCTIONS_DB_COUNT_PENDING_START',
    details: {'peerId': peerId.length > 10 ? peerId.substring(0, 10) : peerId},
  );

  try {
    final result = await db.rawQuery(
      "SELECT COUNT(*) as count FROM introductions WHERE (recipient_id = ? OR introduced_id = ?) AND status = 'pending'",
      [peerId, peerId],
    );
    final count = Sqflite.firstIntValue(result) ?? 0;

    emitFlowEvent(
      layer: 'DB',
      event: 'INTRODUCTIONS_DB_COUNT_PENDING_SUCCESS',
      details: {'count': count},
    );

    return count;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'INTRODUCTIONS_DB_COUNT_PENDING_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}
