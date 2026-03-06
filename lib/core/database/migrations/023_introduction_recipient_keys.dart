import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Adds recipient key columns to the introductions table for storing
/// the recipient party's public keys.
///
/// These keys are needed so the introduced party can create a contact
/// with the recipient's correct keys on mutual acceptance.
Future<void> runIntroductionRecipientKeysMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'INTRODUCTION_RECIPIENT_KEYS_MIGRATION_START',
    details: {'migration': '023_introduction_recipient_keys'},
  );

  try {
    await db.execute(
      'ALTER TABLE introductions ADD COLUMN recipient_public_key TEXT',
    );
    await db.execute(
      'ALTER TABLE introductions ADD COLUMN recipient_ml_kem_public_key TEXT',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'INTRODUCTION_RECIPIENT_KEYS_MIGRATION_SUCCESS',
      details: {'migration': '023_introduction_recipient_keys'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'INTRODUCTION_RECIPIENT_KEYS_MIGRATION_ERROR',
      details: {'migration': '023_introduction_recipient_keys', 'error': e.toString()},
    );
    rethrow;
  }
}
