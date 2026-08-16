import 'dart:math' as math;

import 'package:sqflite_sqlcipher/sqflite.dart';

const String _table = 'group_notification_reconciliation_outbox';
const int kGroupNotificationReconciliationOutboxMaxLoadBatch = 50;

/// Total durable custody, including deferred/backoff rows.
Future<int> dbCountAllGroupNotificationReconciliationOutboxEntries(
  DatabaseExecutor db,
) async {
  if (!await _tableExists(db)) return 0;
  return Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $_table'),
      ) ??
      0;
}

/// Enqueues a canonical group-notification reconciliation pass.
///
/// The opaque incarnation token distinguishes a later row created for the
/// same group after completion. Fresh work coalesces into the existing row,
/// advances its revision, and clears any retry delay so current canonical
/// state is projected promptly.
Future<void> dbEnqueueGroupNotificationReconciliationOutbox(
  DatabaseExecutor db, {
  required String groupId,
}) async {
  final normalizedGroupId = groupId.trim();
  if (normalizedGroupId.isEmpty) {
    throw ArgumentError.value(groupId, 'groupId', 'must be non-empty');
  }
  if (!await _tableExists(db)) return;

  await db.rawInsert(
    '''
    INSERT INTO $_table (
      group_id,
      incarnation_id,
      revision,
      retry_count,
      last_attempt_at,
      next_attempt_at,
      created_at,
      updated_at
    ) VALUES (
      ?,
      lower(hex(randomblob(16))),
      1,
      0,
      NULL,
      NULL,
      strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
      strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
    )
    ON CONFLICT(group_id) DO UPDATE SET
      revision = revision + 1,
      retry_count = 0,
      last_attempt_at = NULL,
      next_attempt_at = NULL,
      updated_at = excluded.updated_at
  ''',
    <Object?>[normalizedGroupId],
  );
}

Future<Map<String, Object?>?> dbLoadGroupNotificationReconciliationOutboxEntry(
  DatabaseExecutor db,
  String groupId,
) async {
  if (!await _tableExists(db)) return null;
  final rows = await db.query(
    _table,
    where: 'group_id = ?',
    whereArgs: <Object?>[groupId],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.single;
}

Future<List<Map<String, Object?>>>
dbLoadEligibleGroupNotificationReconciliationOutboxEntries(
  DatabaseExecutor db, {
  int limit = 20,
  required String eligibleAt,
}) async {
  if (limit <= 0 || !await _tableExists(db)) return const [];
  final boundedLimit = math.min(
    limit,
    kGroupNotificationReconciliationOutboxMaxLoadBatch,
  );
  return db.rawQuery(
    'SELECT * FROM $_table '
    'WHERE next_attempt_at IS NULL OR next_attempt_at <= ? '
    'ORDER BY created_at ASC, group_id ASC LIMIT ?',
    <Object?>[eligibleAt, boundedLimit],
  );
}

/// Returns the earliest persisted retry deadline, if every row is deferred.
Future<String?>
dbLoadEarliestGroupNotificationReconciliationOutboxNextAttemptAt(
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

Future<bool> dbRecordGroupNotificationReconciliationOutboxFailureIfExact(
  DatabaseExecutor db, {
  required String groupId,
  required String expectedIncarnationId,
  required int expectedRevision,
  required String lastAttemptAt,
  required String nextAttemptAt,
  required String updatedAt,
}) async {
  if (!await _tableExists(db)) return false;
  final updated = await db.rawUpdate(
    'UPDATE $_table SET '
    'revision = revision + 1, retry_count = retry_count + 1, '
    'last_attempt_at = ?, next_attempt_at = ?, updated_at = ? '
    'WHERE group_id = ? AND incarnation_id = ? AND revision = ?',
    <Object?>[
      lastAttemptAt,
      nextAttemptAt,
      updatedAt,
      groupId,
      expectedIncarnationId,
      expectedRevision,
    ],
  );
  return updated == 1;
}

/// Completes only the exact loaded incarnation and revision.
///
/// [expectedIncarnationId] prevents a delayed completion from deleting a new
/// row that reused the same group id and reset its revision after completion.
Future<bool> dbCompleteGroupNotificationReconciliationOutboxIfExact(
  DatabaseExecutor db, {
  required String groupId,
  required String expectedIncarnationId,
  required int expectedRevision,
}) async {
  if (!await _tableExists(db)) return false;
  final deleted = await db.delete(
    _table,
    where: 'group_id = ? AND incarnation_id = ? AND revision = ?',
    whereArgs: <Object?>[groupId, expectedIncarnationId, expectedRevision],
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
