import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Migration 046: durable staging for intro responses that arrive before send.
Future<void> runPendingIntroductionResponsesMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'PENDING_INTRO_RESPONSES_MIGRATION_START',
    details: {'migration': '046_pending_introduction_responses'},
  );

  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_introduction_responses (
        response_key TEXT PRIMARY KEY,
        introduction_id TEXT NOT NULL,
        action TEXT NOT NULL CHECK(action IN ('accept', 'pass')),
        responder_id TEXT NOT NULL,
        responder_username TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_pending_intro_responses_intro_id
      ON pending_introduction_responses(introduction_id, created_at, response_key)
    ''');

    emitFlowEvent(
      layer: 'DB',
      event: 'PENDING_INTRO_RESPONSES_MIGRATION_SUCCESS',
      details: {'migration': '046_pending_introduction_responses'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'PENDING_INTRO_RESPONSES_MIGRATION_ERROR',
      details: {
        'migration': '046_pending_introduction_responses',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
