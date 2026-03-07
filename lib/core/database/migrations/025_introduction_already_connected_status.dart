import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Recreates the introductions table with an updated CHECK constraint
/// on the `status` column to include `already_connected`.
///
/// SQLite doesn't support ALTER CHECK, so we recreate the table.
Future<void> runIntroductionAlreadyConnectedMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'INTRODUCTION_ALREADY_CONNECTED_MIGRATION_START',
    details: {'migration': '025_introduction_already_connected_status'},
  );

  try {
    await db.execute('''
      CREATE TABLE introductions_new (
        id TEXT PRIMARY KEY,
        introducer_id TEXT NOT NULL,
        recipient_id TEXT NOT NULL,
        introduced_id TEXT NOT NULL,
        introducer_username TEXT,
        recipient_username TEXT,
        introduced_username TEXT,
        recipient_status TEXT NOT NULL DEFAULT 'pending'
          CHECK(recipient_status IN ('pending','accepted','passed')),
        introduced_status TEXT NOT NULL DEFAULT 'pending'
          CHECK(introduced_status IN ('pending','accepted','passed')),
        status TEXT NOT NULL DEFAULT 'pending'
          CHECK(status IN ('pending','mutual_accepted','passed','expired','already_connected')),
        created_at TEXT NOT NULL,
        recipient_responded_at TEXT,
        introduced_responded_at TEXT,
        introduced_public_key TEXT,
        introduced_ml_kem_public_key TEXT,
        recipient_public_key TEXT,
        recipient_ml_kem_public_key TEXT
      )
    ''');
    await db.execute(
        'INSERT INTO introductions_new SELECT * FROM introductions');
    await db.execute('DROP TABLE introductions');
    await db
        .execute('ALTER TABLE introductions_new RENAME TO introductions');

    // Recreate indexes
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_introductions_recipient ON introductions(recipient_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_introductions_introduced ON introductions(introduced_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_introductions_introducer ON introductions(introducer_id)');

    emitFlowEvent(
      layer: 'DB',
      event: 'INTRODUCTION_ALREADY_CONNECTED_MIGRATION_SUCCESS',
      details: {'migration': '025_introduction_already_connected_status'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'INTRODUCTION_ALREADY_CONNECTED_MIGRATION_ERROR',
      details: {
        'migration': '025_introduction_already_connected_status',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
