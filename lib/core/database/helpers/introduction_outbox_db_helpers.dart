import 'package:sqflite_sqlcipher/sqflite.dart';

import '../db_write_transaction.dart';
import 'introductions_db_helpers.dart';

Future<void> dbUpsertIntroductionOutboxDelivery(
  DatabaseExecutor db,
  Map<String, Object?> row,
) async {
  await db.insert(
    'introduction_outbox_deliveries',
    row,
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<void> dbSaveIntroductionWithOutboxDeliveries(
  Database db,
  Map<String, Object?> introductionRow,
  List<Map<String, Object?>> deliveryRows,
) {
  return dbWriteTransaction(db, (txn) async {
    await dbInsertIntroduction(txn, introductionRow);
    for (final deliveryRow in deliveryRows) {
      await dbUpsertIntroductionOutboxDelivery(txn, deliveryRow);
    }
  });
}

Future<void> dbReplaceIntroductionWithPendingResponseMigration(
  Database db, {
  required Map<String, Object?> introductionRow,
  required List<Map<String, Object?>> deliveryRows,
  required List<String> replacedIntroductionIds,
}) {
  final newIntroductionId = introductionRow['id'] as String;

  return dbWriteTransaction(db, (txn) async {
    final pendingRows = await _loadPendingResponsesForIntroductionIds(
      txn,
      replacedIntroductionIds,
    );

    for (final oldIntroductionId in replacedIntroductionIds) {
      await txn.delete(
        'introduction_outbox_deliveries',
        where: 'introduction_id = ?',
        whereArgs: [oldIntroductionId],
      );
    }
    await _deletePendingResponsesForIntroductionIds(
      txn,
      replacedIntroductionIds,
    );
    await _deleteIntroductionsForIds(txn, replacedIntroductionIds);

    await dbInsertIntroduction(txn, introductionRow);
    for (final deliveryRow in deliveryRows) {
      await dbUpsertIntroductionOutboxDelivery(txn, deliveryRow);
    }

    for (final pendingRow in pendingRows) {
      await _insertMigratedPendingResponse(txn, pendingRow, newIntroductionId);
    }
  });
}

Future<bool> dbSaveIntroductionResponseWithOutboxDeliveries(
  Database db, {
  required String introductionId,
  required bool isRecipient,
  required String responseStatus,
  required String respondedAt,
  required String overallStatus,
  required List<Map<String, Object?>> deliveryRows,
}) {
  final statusColumn = isRecipient ? 'recipient_status' : 'introduced_status';
  final respondedAtColumn = isRecipient
      ? 'recipient_responded_at'
      : 'introduced_responded_at';

  return dbWriteTransaction(db, (txn) async {
    final rowsUpdated = await txn.rawUpdate(
      'UPDATE introductions SET $statusColumn = ?, $respondedAtColumn = ? WHERE id = ? AND $statusColumn = ? AND status = ?',
      [responseStatus, respondedAt, introductionId, 'pending', 'pending'],
    );
    if (rowsUpdated == 0) {
      return false;
    }

    final derivedOverallStatus = await _deriveCurrentOverallStatus(
      txn,
      introductionId,
      fallbackStatus: overallStatus,
    );
    await txn.rawUpdate(
      'UPDATE introductions SET status = ? WHERE id = ? AND status = ?',
      [derivedOverallStatus, introductionId, 'pending'],
    );

    for (final deliveryRow in deliveryRows) {
      await dbUpsertIntroductionOutboxDelivery(txn, deliveryRow);
    }
    return true;
  });
}

Future<String> _deriveCurrentOverallStatus(
  DatabaseExecutor db,
  String introductionId, {
  required String fallbackStatus,
}) async {
  final rows = await db.query(
    'introductions',
    columns: ['recipient_status', 'introduced_status', 'created_at'],
    where: 'id = ?',
    whereArgs: [introductionId],
    limit: 1,
  );
  if (rows.isEmpty) {
    return fallbackStatus;
  }

  final row = rows.single;
  final recipientStatus = row['recipient_status'] as String?;
  final introducedStatus = row['introduced_status'] as String?;
  if (recipientStatus == 'accepted' && introducedStatus == 'accepted') {
    return 'mutual_accepted';
  }
  if (recipientStatus == 'passed' || introducedStatus == 'passed') {
    return 'passed';
  }

  final createdAt = row['created_at'] as String?;
  final createdTime = createdAt == null ? null : DateTime.tryParse(createdAt);
  if (createdTime != null &&
      DateTime.now().toUtc().difference(createdTime).inDays > 30) {
    return 'expired';
  }

  return 'pending';
}

Future<void> dbDeleteIntroductionOutboxDelivery(
  Database db,
  String deliveryId,
) {
  return db.delete(
    'introduction_outbox_deliveries',
    where: 'delivery_id = ?',
    whereArgs: [deliveryId],
  );
}

Future<List<Map<String, Object?>>> _loadPendingResponsesForIntroductionIds(
  DatabaseExecutor db,
  List<String> introductionIds,
) {
  if (introductionIds.isEmpty) {
    return Future.value(const <Map<String, Object?>>[]);
  }
  final placeholders = List.filled(introductionIds.length, '?').join(', ');
  return db.query(
    'pending_introduction_responses',
    where: 'introduction_id IN ($placeholders)',
    whereArgs: introductionIds,
    orderBy: 'created_at ASC, response_key ASC',
  );
}

Future<void> _deletePendingResponsesForIntroductionIds(
  DatabaseExecutor db,
  List<String> introductionIds,
) {
  if (introductionIds.isEmpty) {
    return Future.value();
  }
  final placeholders = List.filled(introductionIds.length, '?').join(', ');
  return db.delete(
    'pending_introduction_responses',
    where: 'introduction_id IN ($placeholders)',
    whereArgs: introductionIds,
  );
}

Future<void> _deleteIntroductionsForIds(
  DatabaseExecutor db,
  List<String> introductionIds,
) async {
  for (final introductionId in introductionIds) {
    await db.delete(
      'introductions',
      where: 'id = ?',
      whereArgs: [introductionId],
    );
  }
}

Future<void> _insertMigratedPendingResponse(
  DatabaseExecutor db,
  Map<String, Object?> row,
  String newIntroductionId,
) {
  final action = row['action'] as String;
  final responderId = row['responder_id'] as String;
  final migratedRow = Map<String, Object?>.from(row)
    ..['introduction_id'] = newIntroductionId
    ..['response_key'] = '$newIntroductionId::$responderId::$action';

  return db.insert(
    'pending_introduction_responses',
    migratedRow,
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<void> dbDeleteIntroductionOutboxDeliveriesForIntroduction(
  Database db,
  String introductionId,
) {
  return db.delete(
    'introduction_outbox_deliveries',
    where: 'introduction_id = ?',
    whereArgs: [introductionId],
  );
}

Future<List<Map<String, Object?>>>
dbLoadIntroductionOutboxDeliveriesForIntroduction(
  Database db,
  String introductionId,
) {
  return db.query(
    'introduction_outbox_deliveries',
    where: 'introduction_id = ?',
    whereArgs: [introductionId],
    orderBy: 'created_at ASC, delivery_id ASC',
  );
}

Future<List<Map<String, Object?>>> dbLoadRetryableIntroductionOutboxDeliveries(
  Database db, {
  required String olderThan,
  int limit = 100,
}) {
  return db.query(
    'introduction_outbox_deliveries',
    where: '''
delivery_status = ?
OR (delivery_status IN (?, ?) AND updated_at <= ?)
OR (delivery_status = ? AND delivery_path = ?)
''',
    whereArgs: ['failed', 'sending', 'sent', olderThan, 'delivered', 'inbox'],
    orderBy: 'created_at ASC, delivery_id ASC',
    limit: limit,
  );
}
