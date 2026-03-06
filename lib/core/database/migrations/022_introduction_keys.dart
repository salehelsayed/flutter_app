import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Adds key columns to the introductions table for storing
/// the introduced party's public keys.
///
/// These keys are needed to create a contact on mutual acceptance.
Future<void> runIntroductionKeysMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'INTRODUCTION_KEYS_MIGRATION_START',
    details: {'migration': '022_introduction_keys'},
  );

  try {
    await db.execute(
      'ALTER TABLE introductions ADD COLUMN introduced_public_key TEXT',
    );
    await db.execute(
      'ALTER TABLE introductions ADD COLUMN introduced_ml_kem_public_key TEXT',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'INTRODUCTION_KEYS_MIGRATION_SUCCESS',
      details: {'migration': '022_introduction_keys'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'INTRODUCTION_KEYS_MIGRATION_ERROR',
      details: {'migration': '022_introduction_keys', 'error': e.toString()},
    );
    rethrow;
  }
}
