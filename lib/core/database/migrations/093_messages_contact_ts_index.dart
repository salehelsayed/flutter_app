// ignore_for_file: file_names

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

// QW-5 (db-persistence-2): the hot 1:1 page query is
//   SELECT * FROM messages WHERE contact_peer_id = ? AND hidden_at IS NULL
//   ORDER BY timestamp DESC LIMIT ?
// The 002 indices are single-column (idx_messages_contact on contact_peer_id,
// idx_messages_ts on timestamp), so the planner can satisfy either the
// equality filter OR the order, but not both — leaving a temp b-tree sort.
// A composite (contact_peer_id, timestamp) index satisfies the equality and the
// single-term ORDER BY in one pass (scanned in reverse for DESC), removing the
// sort. The ORDER BY has ONE term, so a 2-col index is sufficient here (contrast
// the group query, 094, which is two-term and needs a 3-col index).
// Index-only, fail-open, IF NOT EXISTS — no data backfill.
const _createMessagesContactTsIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_messages_contact_ts
ON messages(contact_peer_id, timestamp);
''';

Future<void> runMessagesContactTsIndexMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MESSAGES_CONTACT_TS_INDEX_MIGRATION_START',
    details: {'migration': '093_messages_contact_ts_index'},
  );

  try {
    await db.execute(_createMessagesContactTsIndexSql);

    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_CONTACT_TS_INDEX_MIGRATION_SUCCESS',
      details: {'migration': '093_messages_contact_ts_index'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_CONTACT_TS_INDEX_MIGRATION_ERROR',
      details: {
        'migration': '093_messages_contact_ts_index',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
