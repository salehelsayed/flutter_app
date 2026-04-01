import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

const _recoverableInboxStagingStatuses = ['pending', 'retryable'];

Future<void> dbInsertInboxStagingEntry(
  Database db,
  Map<String, Object?> row,
) async {
  final entryId = row['entry_id'] as String? ?? '';

  emitFlowEvent(
    layer: 'DB',
    event: 'INBOX_STAGING_DB_INSERT_START',
    details: {
      'entryId': entryId.length > 8 ? entryId.substring(0, 8) : entryId,
    },
  );

  try {
    await db.insert(
      'inbox_staging_entries',
      row,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'INBOX_STAGING_DB_INSERT_SUCCESS',
      details: {
        'entryId': entryId.length > 8 ? entryId.substring(0, 8) : entryId,
      },
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'INBOX_STAGING_DB_INSERT_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

Future<List<Map<String, Object?>>> dbLoadRecoverableInboxStagingEntries(
  Database db, {
  int limit = 50,
  List<String>? entryIds,
}) async {
  final whereClauses = <String>['status IN (?, ?)'];
  final whereArgs = <Object?>[
    _recoverableInboxStagingStatuses[0],
    _recoverableInboxStagingStatuses[1],
  ];

  if (entryIds != null) {
    if (entryIds.isEmpty) {
      return const [];
    }
    whereClauses.add(
      'entry_id IN (${List.filled(entryIds.length, '?').join(', ')})',
    );
    whereArgs.addAll(entryIds);
  }

  emitFlowEvent(
    layer: 'DB',
    event: 'INBOX_STAGING_DB_LOAD_RECOVERABLE_START',
    details: {
      'limit': limit,
      'filtered': entryIds != null,
      if (entryIds != null) 'entryCount': entryIds.length,
    },
  );

  try {
    final rows = await db.query(
      'inbox_staging_entries',
      where: whereClauses.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'relay_timestamp ASC, staged_at ASC, entry_id ASC',
      limit: limit,
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'INBOX_STAGING_DB_LOAD_RECOVERABLE_SUCCESS',
      details: {'count': rows.length},
    );

    return rows;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'INBOX_STAGING_DB_LOAD_RECOVERABLE_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

Future<Map<String, Object?>?> dbLoadInboxStagingEntry(
  Database db,
  String entryId,
) async {
  final rows = await db.query(
    'inbox_staging_entries',
    where: 'entry_id = ?',
    whereArgs: [entryId],
    limit: 1,
  );
  if (rows.isEmpty) return null;
  return rows.first;
}

Future<int> dbDeleteInboxStagingEntry(Database db, String entryId) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'INBOX_STAGING_DB_DELETE_START',
    details: {
      'entryId': entryId.length > 8 ? entryId.substring(0, 8) : entryId,
    },
  );

  try {
    final deleted = await db.delete(
      'inbox_staging_entries',
      where: 'entry_id = ?',
      whereArgs: [entryId],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'INBOX_STAGING_DB_DELETE_SUCCESS',
      details: {'deleted': deleted},
    );

    return deleted;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'INBOX_STAGING_DB_DELETE_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

Future<int> dbMarkInboxStagingEntryRetryable(
  Database db,
  String entryId, {
  required String reasonCode,
  String? reasonDetail,
}) async {
  final attemptedAt = DateTime.now().toUtc().toIso8601String();

  emitFlowEvent(
    layer: 'DB',
    event: 'INBOX_STAGING_DB_MARK_RETRYABLE_START',
    details: {
      'entryId': entryId.length > 8 ? entryId.substring(0, 8) : entryId,
      'reasonCode': reasonCode,
    },
  );

  try {
    final updated = await db.rawUpdate(
      '''
      UPDATE inbox_staging_entries
      SET status = ?,
          attempt_count = attempt_count + 1,
          last_attempted_at = ?,
          reject_reason_code = ?,
          reject_reason_detail = ?
      WHERE entry_id = ?
      ''',
      ['retryable', attemptedAt, reasonCode, reasonDetail, entryId],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'INBOX_STAGING_DB_MARK_RETRYABLE_SUCCESS',
      details: {'updated': updated},
    );

    return updated;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'INBOX_STAGING_DB_MARK_RETRYABLE_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

Future<int> dbMarkInboxStagingEntryRejected(
  Database db,
  String entryId, {
  required String reasonCode,
  String? reasonDetail,
}) async {
  final attemptedAt = DateTime.now().toUtc().toIso8601String();

  emitFlowEvent(
    layer: 'DB',
    event: 'INBOX_STAGING_DB_MARK_REJECTED_START',
    details: {
      'entryId': entryId.length > 8 ? entryId.substring(0, 8) : entryId,
      'reasonCode': reasonCode,
    },
  );

  try {
    final updated = await db.rawUpdate(
      '''
      UPDATE inbox_staging_entries
      SET status = ?,
          attempt_count = attempt_count + 1,
          last_attempted_at = ?,
          reject_reason_code = ?,
          reject_reason_detail = ?
      WHERE entry_id = ?
      ''',
      ['rejected', attemptedAt, reasonCode, reasonDetail, entryId],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'INBOX_STAGING_DB_MARK_REJECTED_SUCCESS',
      details: {'updated': updated},
    );

    return updated;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'INBOX_STAGING_DB_MARK_REJECTED_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}
