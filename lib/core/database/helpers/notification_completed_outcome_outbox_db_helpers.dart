import 'dart:math' as math;

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../notifications/notification_completed_outcome.dart';
import '../../notifications/notification_completed_outcome_correlation.dart';
import '../db_write_transaction.dart';
import '../migrations/116_notification_completed_outcome_outbox.dart';

const int kNotificationCompletedOutcomeOutboxMaxLoadBatch = 50;

enum NotificationCompletedOutcomeInsertResult {
  inserted,
  existingSame,
  existingDifferent,
  capacity,
  invalid,
}

/// Appends an outcome inside an incumbent display-completion transaction.
///
/// Capacity and immutable-category races are explicit non-throwing outcomes so
/// the caller can safely complete exact display custody without claiming a new
/// wake outcome. Database failures still throw and roll back the outer
/// transaction.
Future<NotificationCompletedOutcomeInsertResult>
dbInsertNotificationCompletedOutcomeWithinTransaction(
  DatabaseExecutor txn, {
  required NotificationCompletedOutcomeCandidate candidate,
  required DateTime now,
  int capacity = kNotificationCompletedOutcomeOutboxCapacity,
}) async {
  if (!await _tableExists(txn)) {
    return NotificationCompletedOutcomeInsertResult.invalid;
  }
  final correlation = tryBuildNotificationCompletedOutcomeCorrelation(
    physicalPeerId: candidate.physicalPeerId,
    producerKind: candidate.producerKind,
    eventKey: candidate.eventKey,
  );
  final utcNow = now.toUtc();
  final completedAt = candidate.completedAt.toUtc();
  final expiresAt = completedAt.add(kNotificationCompletedOutcomeRetention);
  if (correlation == null || !expiresAt.isAfter(utcNow)) {
    return NotificationCompletedOutcomeInsertResult.invalid;
  }

  final nowEncoded = utcNow.toIso8601String();
  await txn.delete(
    kNotificationCompletedOutcomeOutboxTable,
    where: 'expires_at <= ?',
    whereArgs: <Object?>[nowEncoded],
  );

  final existing = await txn.query(
    kNotificationCompletedOutcomeOutboxTable,
    columns: const <String>['outcome'],
    where: 'wake_correlation = ?',
    whereArgs: <Object?>[correlation.digest],
    limit: 1,
  );
  if (existing.isNotEmpty) {
    return existing.single['outcome'] == candidate.outcome.wireValue
        ? NotificationCompletedOutcomeInsertResult.existingSame
        : NotificationCompletedOutcomeInsertResult.existingDifferent;
  }
  if (capacity <= 0) {
    return NotificationCompletedOutcomeInsertResult.capacity;
  }
  final count = Sqflite.firstIntValue(
    await txn.rawQuery(
      'SELECT COUNT(*) FROM $kNotificationCompletedOutcomeOutboxTable',
    ),
  );
  if ((count ?? 0) >= capacity) {
    return NotificationCompletedOutcomeInsertResult.capacity;
  }

  await txn.insert(
    kNotificationCompletedOutcomeOutboxTable,
    <String, Object?>{
      'wake_correlation': correlation.digest,
      'outcome': candidate.outcome.wireValue,
      'revision': 1,
      'retry_count': 0,
      'last_error_code': null,
      'last_attempt_at': null,
      'next_attempt_at': null,
      'completed_at': completedAt.toIso8601String(),
      'created_at': nowEncoded,
      'expires_at': expiresAt.toIso8601String(),
    },
    conflictAlgorithm: ConflictAlgorithm.abort,
  );
  return NotificationCompletedOutcomeInsertResult.inserted;
}

Future<List<Map<String, Object?>>>
dbLoadReadyNotificationCompletedOutcomeOutboxEntries(
  Database db, {
  required DateTime now,
  int limit = 20,
}) {
  if (limit <= 0) return Future.value(const <Map<String, Object?>>[]);
  return dbWriteTransaction(db, (txn) async {
    if (!await _tableExists(txn)) return const <Map<String, Object?>>[];
    final nowEncoded = now.toUtc().toIso8601String();
    await txn.delete(
      kNotificationCompletedOutcomeOutboxTable,
      where: 'expires_at <= ?',
      whereArgs: <Object?>[nowEncoded],
    );
    return txn.rawQuery(
      'SELECT * FROM $kNotificationCompletedOutcomeOutboxTable '
      'WHERE next_attempt_at IS NULL OR next_attempt_at <= ? '
      'ORDER BY COALESCE(next_attempt_at, completed_at) ASC, '
      'created_at ASC, wake_correlation ASC LIMIT ?',
      <Object?>[
        nowEncoded,
        math.min(limit, kNotificationCompletedOutcomeOutboxMaxLoadBatch),
      ],
    );
  }, exclusive: true);
}

Future<Map<String, Object?>?>
dbLoadExactNotificationCompletedOutcomeOutboxEntry(
  DatabaseExecutor db, {
  required String wakeCorrelation,
}) async {
  if (!await _tableExists(db)) return null;
  final rows = await db.query(
    kNotificationCompletedOutcomeOutboxTable,
    where: 'wake_correlation = ?',
    whereArgs: <Object?>[wakeCorrelation],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.single;
}

Future<bool> dbRecordNotificationCompletedOutcomeRetryIfExact(
  DatabaseExecutor db, {
  required String wakeCorrelation,
  required int expectedRevision,
  required String expectedOutcome,
  required String lastErrorCode,
  required DateTime lastAttemptAt,
  required DateTime nextAttemptAt,
}) async {
  final errorCodeIsValid =
      lastErrorCode.isNotEmpty &&
      lastErrorCode.trim() == lastErrorCode &&
      lastErrorCode.length <= 64;
  final last = lastAttemptAt.toUtc();
  final next = nextAttemptAt.toUtc();
  if (!errorCodeIsValid || !next.isAfter(last) || !await _tableExists(db)) {
    return false;
  }
  final updated = await db.rawUpdate(
    'UPDATE $kNotificationCompletedOutcomeOutboxTable '
    'SET revision = revision + 1, retry_count = retry_count + 1, '
    'last_error_code = ?, last_attempt_at = ?, next_attempt_at = ? '
    'WHERE wake_correlation = ? AND revision = ? AND outcome = ? '
    'AND expires_at > ? AND ? < expires_at',
    <Object?>[
      lastErrorCode,
      last.toIso8601String(),
      next.toIso8601String(),
      wakeCorrelation,
      expectedRevision,
      expectedOutcome,
      last.toIso8601String(),
      next.toIso8601String(),
    ],
  );
  return updated == 1;
}

Future<bool> dbCompleteNotificationCompletedOutcomeIfExact(
  DatabaseExecutor db, {
  required String wakeCorrelation,
  required int expectedRevision,
  required String expectedOutcome,
}) async {
  if (!await _tableExists(db)) return false;
  final deleted = await db.delete(
    kNotificationCompletedOutcomeOutboxTable,
    where: 'wake_correlation = ? AND revision = ? AND outcome = ?',
    whereArgs: <Object?>[wakeCorrelation, expectedRevision, expectedOutcome],
  );
  return deleted == 1;
}

Future<bool> _tableExists(DatabaseExecutor db) async {
  final rows = await db.rawQuery(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
    const <Object?>[kNotificationCompletedOutcomeOutboxTable],
  );
  return rows.isNotEmpty;
}
