import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';
import '../db_write_transaction.dart';
import 'group_parent_write_guard.dart';

const _reactionReplayAuthorityFields = <String>[
  'reaction_id',
  'group_id',
  'message_id',
  'sender_peer_id',
  'emoji',
  'action',
  'inbox_retry_payload',
  'delivery_status',
  'last_error',
  'created_at',
  'updated_at',
];

bool _sameReactionReplayAuthority(
  Map<String, Object?> current,
  Map<String, Object?> expected,
) {
  for (final field in _reactionReplayAuthorityFields) {
    if (current[field] != expected[field]) return false;
  }
  return true;
}

Future<void> dbUpsertGroupReactionReplayOutboxEntry(
  Database db,
  Map<String, Object?> row,
) async {
  final reactionId = row['reaction_id'] as String? ?? '';

  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_REACTION_REPLAY_OUTBOX_DB_UPSERT_START',
    details: {
      'reactionId': reactionId.length > 8
          ? reactionId.substring(0, 8)
          : reactionId,
    },
  );

  try {
    await dbInsertOrdinaryGroupOwnedRow(
      db,
      table: 'group_reaction_replay_outbox',
      row: row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_REACTION_REPLAY_OUTBOX_DB_UPSERT_SUCCESS',
      details: {
        'reactionId': reactionId.length > 8
            ? reactionId.substring(0, 8)
            : reactionId,
      },
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_REACTION_REPLAY_OUTBOX_DB_UPSERT_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

Future<Map<String, Object?>?> dbLoadGroupReactionReplayOutboxEntry(
  Database db,
  String reactionId,
) async {
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'group_reaction_replay_outbox.group_id',
  );
  final rows = await db.rawQuery(
    'SELECT * FROM group_reaction_replay_outbox '
    'WHERE reaction_id = ? AND $parent LIMIT 1',
    [reactionId],
  );
  if (rows.isEmpty) return null;
  return rows.first;
}

Future<Map<String, Object?>?>
dbLoadLatestGroupReactionReplayOutboxEntryForTarget(
  Database db, {
  required String groupId,
  required String messageId,
  required String senderPeerId,
}) async {
  final parent = await dbOrdinaryGroupParentPredicate(
    db,
    groupIdExpression: 'group_reaction_replay_outbox.group_id',
  );
  final rows = await db.rawQuery(
    'SELECT * FROM group_reaction_replay_outbox '
    'WHERE group_id = ? AND message_id = ? AND sender_peer_id = ? '
    'AND $parent ORDER BY created_at DESC, rowid DESC LIMIT 1',
    [groupId, messageId, senderPeerId],
  );
  if (rows.isEmpty) return null;
  return rows.first;
}

Future<List<Map<String, Object?>>>
dbLoadRetryableGroupReactionReplayOutboxEntries(
  Database db, {
  int limit = 20,
}) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_REACTION_REPLAY_OUTBOX_DB_LOAD_RETRYABLE_START',
    details: {'limit': limit},
  );

  try {
    final parent = await dbOrdinaryGroupParentPredicate(
      db,
      groupIdExpression: 'group_reaction_replay_outbox.group_id',
    );
    final rows = await db.rawQuery(
      'SELECT * FROM group_reaction_replay_outbox '
      'WHERE delivery_status IN (?, ?) AND $parent '
      'ORDER BY created_at ASC, reaction_id ASC LIMIT ?',
      ['pending', 'failed', limit],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_REACTION_REPLAY_OUTBOX_DB_LOAD_RETRYABLE_SUCCESS',
      details: {'count': rows.length},
    );

    return rows;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_REACTION_REPLAY_OUTBOX_DB_LOAD_RETRYABLE_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

Future<void> dbUpdateGroupReactionReplayOutboxEntryStatus(
  Database db,
  String reactionId, {
  required String deliveryStatus,
  String? lastError,
  required String updatedAt,
}) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_REACTION_REPLAY_OUTBOX_DB_UPDATE_STATUS_START',
    details: {
      'reactionId': reactionId.length > 8
          ? reactionId.substring(0, 8)
          : reactionId,
      'deliveryStatus': deliveryStatus,
    },
  );

  try {
    final existing = await db.query(
      'group_reaction_replay_outbox',
      columns: const ['group_id'],
      where: 'reaction_id = ?',
      whereArgs: [reactionId],
      limit: 1,
    );
    if (existing.isEmpty) return;
    await dbUpdateOrdinaryGroupOwnedRows(
      db,
      table: 'group_reaction_replay_outbox',
      groupId: existing.single['group_id'] as String? ?? '',
      values: {
        'delivery_status': deliveryStatus,
        'last_error': lastError,
        'updated_at': updatedAt,
      },
      where: 'reaction_id = ?',
      whereArgs: [reactionId],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_REACTION_REPLAY_OUTBOX_DB_UPDATE_STATUS_SUCCESS',
      details: {
        'reactionId': reactionId.length > 8
            ? reactionId.substring(0, 8)
            : reactionId,
        'deliveryStatus': deliveryStatus,
      },
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_REACTION_REPLAY_OUTBOX_DB_UPDATE_STATUS_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Completes one loaded reaction replay action only while the complete outbox
/// row and its unmarked group parent are unchanged. A newer reaction
/// transition may reuse the same deterministic row id; the old network result
/// must never mark that replacement stored/failed.
Future<bool> dbUpdateGroupReactionReplayOutboxEntryStatusIfExact(
  Database db, {
  required Map<String, Object?> expected,
  required String deliveryStatus,
  String? lastError,
  required String updatedAt,
}) {
  return dbWriteTransaction(db, (txn) async {
    final reactionId = expected['reaction_id'] as String? ?? '';
    final groupId = expected['group_id'] as String? ?? '';
    if (reactionId.isEmpty ||
        groupId.isEmpty ||
        !await dbAllowsOrdinaryGroupWrite(txn, groupId)) {
      return false;
    }
    final rows = await txn.query(
      'group_reaction_replay_outbox',
      where: 'reaction_id = ?',
      whereArgs: [reactionId],
      limit: 1,
    );
    if (rows.isEmpty || !_sameReactionReplayAuthority(rows.single, expected)) {
      return false;
    }
    final updated = await dbUpdateOrdinaryGroupOwnedRows(
      txn,
      table: 'group_reaction_replay_outbox',
      groupId: groupId,
      values: {
        'delivery_status': deliveryStatus,
        'last_error': lastError,
        'updated_at': updatedAt,
      },
      where: 'reaction_id = ? AND delivery_status = ? AND updated_at = ?',
      whereArgs: [
        reactionId,
        expected['delivery_status'],
        expected['updated_at'],
      ],
    );
    return updated == 1;
  });
}

Future<void> dbDeleteGroupReactionReplayOutboxEntry(
  Database db,
  String reactionId,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_REACTION_REPLAY_OUTBOX_DB_DELETE_START',
    details: {
      'reactionId': reactionId.length > 8
          ? reactionId.substring(0, 8)
          : reactionId,
    },
  );

  try {
    await db.delete(
      'group_reaction_replay_outbox',
      where: 'reaction_id = ?',
      whereArgs: [reactionId],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_REACTION_REPLAY_OUTBOX_DB_DELETE_SUCCESS',
      details: {
        'reactionId': reactionId.length > 8
            ? reactionId.substring(0, 8)
            : reactionId,
      },
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_REACTION_REPLAY_OUTBOX_DB_DELETE_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}
