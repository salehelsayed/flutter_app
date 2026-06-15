import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Migration 077: Adds the doc-115 relay custody columns to `messages`.
///
/// `relay_expires_at` (INTEGER, ms epoch) records the relay-stamped custody
/// expiry returned by an enriched inbox store; `custody_checked_at` (TEXT,
/// ISO-8601) records the last custody-sweep touch. Both back the 'inboxed'
/// status foundation: relay-inbox acceptance is custody, not delivery, and
/// the sender-side sweep re-stores or truthfully downgrades unconfirmed
/// rows. Both nullable: live-acked and historical rows never carry them.
Future<void> runMessageRelayCustodyMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MESSAGE_RELAY_CUSTODY_MIGRATION_START',
    details: {'migration': '077_message_relay_custody'},
  );

  try {
    final columns = await db.rawQuery('PRAGMA table_info(messages)');
    final columnNames = columns.map((column) => column['name']).toSet();

    if (!columnNames.contains('relay_expires_at')) {
      await db.execute(
        'ALTER TABLE messages ADD COLUMN relay_expires_at INTEGER',
      );
    }
    if (!columnNames.contains('custody_checked_at')) {
      await db.execute(
        'ALTER TABLE messages ADD COLUMN custody_checked_at TEXT',
      );
    }

    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGE_RELAY_CUSTODY_MIGRATION_SUCCESS',
      details: {'migration': '077_message_relay_custody'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGE_RELAY_CUSTODY_MIGRATION_ERROR',
      details: {
        'migration': '077_message_relay_custody',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
