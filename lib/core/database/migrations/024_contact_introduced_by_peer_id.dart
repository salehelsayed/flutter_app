import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Adds the `introduced_by_peer_id` column to the contacts table.
///
/// Stores the introducer's peerId when a contact was created via
/// mutual acceptance of an introduction (complements `introduced_by`
/// which stores the username).
Future<void> runContactIntroducedByPeerIdMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'CONTACT_INTRODUCED_BY_PEER_ID_MIGRATION_START',
    details: {'migration': '024_contact_introduced_by_peer_id'},
  );

  try {
    await db.execute(
      'ALTER TABLE contacts ADD COLUMN introduced_by_peer_id TEXT',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'CONTACT_INTRODUCED_BY_PEER_ID_MIGRATION_SUCCESS',
      details: {'migration': '024_contact_introduced_by_peer_id'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'CONTACT_INTRODUCED_BY_PEER_ID_MIGRATION_ERROR',
      details: {
        'migration': '024_contact_introduced_by_peer_id',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
