import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

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
    await db.insert(
      'group_reaction_replay_outbox',
      row,
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
  final rows = await db.query(
    'group_reaction_replay_outbox',
    where: 'reaction_id = ?',
    whereArgs: [reactionId],
    limit: 1,
  );
  if (rows.isEmpty) return null;
  return rows.first;
}

Future<List<Map<String, Object?>>> dbLoadRetryableGroupReactionReplayOutboxEntries(
  Database db, {
  int limit = 20,
}) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_REACTION_REPLAY_OUTBOX_DB_LOAD_RETRYABLE_START',
    details: {'limit': limit},
  );

  try {
    final rows = await db.query(
      'group_reaction_replay_outbox',
      where: 'delivery_status IN (?, ?)',
      whereArgs: const ['pending', 'failed'],
      orderBy: 'created_at ASC, reaction_id ASC',
      limit: limit,
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
    await db.update(
      'group_reaction_replay_outbox',
      {
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
