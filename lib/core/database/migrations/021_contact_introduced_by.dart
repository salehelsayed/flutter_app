import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Adds the `introduced_by` column to the contacts table.
///
/// Stores the introducer's username when a contact was created via
/// mutual acceptance of an introduction.
Future<void> runContactIntroducedByMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'CONTACT_INTRODUCED_BY_MIGRATION_START',
    details: {'migration': '021_contact_introduced_by'},
  );

  try {
    await db.execute(
      'ALTER TABLE contacts ADD COLUMN introduced_by TEXT',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'CONTACT_INTRODUCED_BY_MIGRATION_SUCCESS',
      details: {'migration': '021_contact_introduced_by'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'CONTACT_INTRODUCED_BY_MIGRATION_ERROR',
      details: {'migration': '021_contact_introduced_by', 'error': e.toString()},
    );
    rethrow;
  }
}
