import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

Future<void> runIntroductionOutboxMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'INTRODUCTION_OUTBOX_MIGRATION_START',
    details: {'migration': '047_introduction_outbox'},
  );

  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS introduction_outbox_deliveries (
        delivery_id TEXT PRIMARY KEY,
        introduction_id TEXT NOT NULL,
        action TEXT NOT NULL,
        target_peer_id TEXT NOT NULL,
        sender_peer_id TEXT NOT NULL,
        raw_envelope TEXT NOT NULL,
        delivery_status TEXT NOT NULL,
        delivery_path TEXT NOT NULL,
        last_error TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_intro_outbox_retry ON introduction_outbox_deliveries(delivery_status, updated_at ASC, delivery_id ASC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_intro_outbox_intro ON introduction_outbox_deliveries(introduction_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_intro_outbox_target ON introduction_outbox_deliveries(target_peer_id)',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'INTRODUCTION_OUTBOX_MIGRATION_SUCCESS',
      details: {'migration': '047_introduction_outbox'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'INTRODUCTION_OUTBOX_MIGRATION_ERROR',
      details: {'migration': '047_introduction_outbox', 'error': e.toString()},
    );
    rethrow;
  }
}
