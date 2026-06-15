import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Migration 075: Adds the anti-rollback timestamp for ML-KEM key updates.
///
/// Records the signed-payload `ts` of the last accepted key rotation so a
/// replayed old contact_request can never roll a contact back to a stale key.
Future<void> runContactsMlKemKeyUpdatedTsMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'CONTACTS_ML_KEM_KEY_UPDATED_TS_MIGRATION_START',
    details: {'migration': '075_contacts_ml_kem_key_updated_ts'},
  );

  try {
    final columns = await db.rawQuery('PRAGMA table_info(contacts)');
    final columnNames = columns.map((column) => column['name']).toSet();

    if (columnNames.contains('ml_kem_key_updated_ts')) {
      emitFlowEvent(
        layer: 'DB',
        event: 'CONTACTS_ML_KEM_KEY_UPDATED_TS_MIGRATION_ALREADY_DONE',
        details: {'migration': '075_contacts_ml_kem_key_updated_ts'},
      );
      return;
    }

    await db.execute(
      'ALTER TABLE contacts ADD COLUMN ml_kem_key_updated_ts TEXT',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'CONTACTS_ML_KEM_KEY_UPDATED_TS_MIGRATION_SUCCESS',
      details: {'migration': '075_contacts_ml_kem_key_updated_ts'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'CONTACTS_ML_KEM_KEY_UPDATED_TS_MIGRATION_ERROR',
      details: {
        'migration': '075_contacts_ml_kem_key_updated_ts',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
