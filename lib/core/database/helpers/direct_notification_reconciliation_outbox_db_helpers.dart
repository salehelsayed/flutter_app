import 'dart:math' as math;

import 'package:sqflite_sqlcipher/sqflite.dart';

const String _table = 'direct_notification_reconciliation_outbox';
const int kDirectNotificationReconciliationOutboxMaxLoadBatch = 50;

/// Total durable custody, including deferred/backoff rows.
Future<int> dbCountAllDirectNotificationReconciliationOutboxEntries(
  DatabaseExecutor db,
) async {
  if (!await _tableExists(db)) return 0;
  return Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $_table'),
      ) ??
      0;
}

Future<void> dbEnqueueDirectNotificationReconciliationOutbox(
  DatabaseExecutor db, {
  required String peerId,
}) async {
  final normalizedPeerId = peerId.trim();
  if (normalizedPeerId.isEmpty || normalizedPeerId.length > 1024) {
    throw ArgumentError.value(
      peerId,
      'peerId',
      'must contain 1 to 1024 characters',
    );
  }
  if (!await _tableExists(db)) return;
  await db.rawInsert(
    '''
    INSERT INTO $_table (
      peer_id, incarnation_id, revision, retry_count,
      last_attempt_at, next_attempt_at, created_at, updated_at
    ) VALUES (
      ?, lower(hex(randomblob(16))), 1, 0, NULL, NULL,
      strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
      strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
    )
    ON CONFLICT(peer_id) DO UPDATE SET
      revision = revision + 1,
      retry_count = 0,
      last_attempt_at = NULL,
      next_attempt_at = NULL,
      updated_at = excluded.updated_at
    ''',
    <Object?>[normalizedPeerId],
  );
}

Future<Map<String, Object?>?> dbLoadDirectNotificationReconciliationOutboxEntry(
  DatabaseExecutor db,
  String peerId,
) async {
  if (!await _tableExists(db)) return null;
  final rows = await db.query(
    _table,
    where: 'peer_id = ?',
    whereArgs: <Object?>[peerId],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.single;
}

Future<List<Map<String, Object?>>>
dbLoadEligibleDirectNotificationReconciliationOutboxEntries(
  DatabaseExecutor db, {
  int limit = 20,
  required String eligibleAt,
}) async {
  if (limit <= 0 || !await _tableExists(db)) return const [];
  final boundedLimit = math.min(
    limit,
    kDirectNotificationReconciliationOutboxMaxLoadBatch,
  );
  return db.rawQuery(
    'SELECT * FROM $_table '
    'WHERE next_attempt_at IS NULL OR next_attempt_at <= ? '
    'ORDER BY created_at ASC, peer_id ASC LIMIT ?',
    <Object?>[eligibleAt, boundedLimit],
  );
}

Future<String?>
dbLoadEarliestDirectNotificationReconciliationOutboxNextAttemptAt(
  DatabaseExecutor db,
) async {
  if (!await _tableExists(db)) return null;
  final rows = await db.rawQuery(
    'SELECT next_attempt_at FROM $_table '
    'WHERE next_attempt_at IS NOT NULL '
    'ORDER BY next_attempt_at ASC LIMIT 1',
  );
  return rows.isEmpty ? null : rows.single['next_attempt_at'] as String?;
}

Future<bool> dbRecordDirectNotificationReconciliationOutboxFailureIfExact(
  DatabaseExecutor db, {
  required String peerId,
  required String expectedIncarnationId,
  required int expectedRevision,
  required String lastAttemptAt,
  required String nextAttemptAt,
  required String updatedAt,
}) async {
  if (!await _tableExists(db)) return false;
  final updated = await db.rawUpdate(
    'UPDATE $_table SET revision = revision + 1, '
    'retry_count = retry_count + 1, last_attempt_at = ?, '
    'next_attempt_at = ?, updated_at = ? '
    'WHERE peer_id = ? AND incarnation_id = ? AND revision = ?',
    <Object?>[
      lastAttemptAt,
      nextAttemptAt,
      updatedAt,
      peerId,
      expectedIncarnationId,
      expectedRevision,
    ],
  );
  return updated == 1;
}

Future<bool> dbCompleteDirectNotificationReconciliationOutboxIfExact(
  DatabaseExecutor db, {
  required String peerId,
  required String expectedIncarnationId,
  required int expectedRevision,
}) async {
  if (!await _tableExists(db)) return false;
  final deleted = await db.delete(
    _table,
    where: 'peer_id = ? AND incarnation_id = ? AND revision = ?',
    whereArgs: <Object?>[peerId, expectedIncarnationId, expectedRevision],
  );
  return deleted == 1;
}

Future<bool> _tableExists(DatabaseExecutor db) async {
  final rows = await db.rawQuery(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
    const <Object?>[_table],
  );
  return rows.isNotEmpty;
}
