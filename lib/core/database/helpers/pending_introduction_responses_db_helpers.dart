import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

Future<void> dbUpsertPendingIntroductionResponse(
  Database db,
  Map<String, Object?> row,
) async {
  final responseKey = row['response_key'] as String? ?? '';

  emitFlowEvent(
    layer: 'DB',
    event: 'PENDING_INTRO_RESPONSES_DB_UPSERT_START',
    details: {
      'responseKey': responseKey.length > 10
          ? responseKey.substring(0, 10)
          : responseKey,
    },
  );

  try {
    await db.insert(
      'pending_introduction_responses',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'PENDING_INTRO_RESPONSES_DB_UPSERT_SUCCESS',
      details: {
        'responseKey': responseKey.length > 10
            ? responseKey.substring(0, 10)
            : responseKey,
      },
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'PENDING_INTRO_RESPONSES_DB_UPSERT_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

Future<List<Map<String, Object?>>> dbLoadPendingIntroductionResponses(
  Database db,
  String introductionId,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'PENDING_INTRO_RESPONSES_DB_LOAD_START',
    details: {'introductionId': introductionId},
  );

  try {
    final rows = await db.query(
      'pending_introduction_responses',
      where: 'introduction_id = ?',
      whereArgs: [introductionId],
      orderBy: 'created_at ASC, response_key ASC',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'PENDING_INTRO_RESPONSES_DB_LOAD_SUCCESS',
      details: {'introductionId': introductionId, 'count': rows.length},
    );
    return rows;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'PENDING_INTRO_RESPONSES_DB_LOAD_ERROR',
      details: {'introductionId': introductionId, 'error': e.toString()},
    );
    rethrow;
  }
}

Future<void> dbDeletePendingIntroductionResponse(
  Database db,
  String responseKey,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'PENDING_INTRO_RESPONSES_DB_DELETE_START',
    details: {
      'responseKey': responseKey.length > 10
          ? responseKey.substring(0, 10)
          : responseKey,
    },
  );

  try {
    await db.delete(
      'pending_introduction_responses',
      where: 'response_key = ?',
      whereArgs: [responseKey],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'PENDING_INTRO_RESPONSES_DB_DELETE_SUCCESS',
      details: {
        'responseKey': responseKey.length > 10
            ? responseKey.substring(0, 10)
            : responseKey,
      },
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'PENDING_INTRO_RESPONSES_DB_DELETE_ERROR',
      details: {'responseKey': responseKey, 'error': e.toString()},
    );
    rethrow;
  }
}
