import 'package:sqflite/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Adds ML-KEM-768 key columns for post-quantum message encryption.
///
/// - identity: ml_kem_public_key, ml_kem_secret_key (own keypair)
/// - contacts: ml_kem_public_key (recipient's public key)
/// - contact_requests: ml_kem_public_key (sender's public key)
Future<void> runMlKemKeysMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MLKEM_DB_MIGRATION_START',
    details: {'migration': '003_mlkem_keys'},
  );

  try {
    await db.execute(
      'ALTER TABLE identity ADD COLUMN ml_kem_public_key TEXT',
    );
    await db.execute(
      'ALTER TABLE identity ADD COLUMN ml_kem_secret_key TEXT',
    );
    await db.execute(
      'ALTER TABLE contacts ADD COLUMN ml_kem_public_key TEXT',
    );
    await db.execute(
      'ALTER TABLE contact_requests ADD COLUMN ml_kem_public_key TEXT',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'MLKEM_DB_MIGRATION_SUCCESS',
      details: {'migration': '003_mlkem_keys'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MLKEM_DB_MIGRATION_ERROR',
      details: {'migration': '003_mlkem_keys', 'error': e.toString()},
    );
    rethrow;
  }
}
