// ignore_for_file: file_names

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';
import '117_call_history.dart';

const String _migrationName = '118_call_history_read_state';

/// 410: read state for the local call timeline.
///
/// Messages already carry read state, so the unread badge could only ever
/// describe half of a conversation. `read_at` is nullable with no default, so
/// every row that already exists starts UNREAD — the truthful state for a call
/// the user has not seen. Only an incoming call the user never took can be
/// unread; the query layer owns that rule, not the schema.
Future<void> runCallHistoryReadStateMigration(Database database) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'CALL_HISTORY_READ_STATE_MIGRATION_START',
    details: const <String, Object?>{'migration': _migrationName},
  );
  try {
    final columns = await database.rawQuery(
      'PRAGMA table_info($kCallHistoryTable)',
    );
    final alreadyPresent = columns.any((column) => column['name'] == 'read_at');
    if (!alreadyPresent) {
      // SQLite cannot add a CHECK constraint to an existing table through
      // ALTER, so the timestamp guard rides a trigger instead — the same
      // shape the table's other timestamps enforce inline.
      await database.execute(
        'ALTER TABLE $kCallHistoryTable ADD COLUMN read_at TEXT',
      );
      await database.execute(_createReadAtGuardSql);
      await database.execute(_createUnreadIndexSql);
    }
    emitFlowEvent(
      layer: 'DB',
      event: 'CALL_HISTORY_READ_STATE_MIGRATION_SUCCESS',
      details: const <String, Object?>{'migration': _migrationName},
    );
  } catch (error) {
    emitFlowEvent(
      layer: 'DB',
      event: 'CALL_HISTORY_READ_STATE_MIGRATION_ERROR',
      details: <String, Object?>{
        'migration': _migrationName,
        'error': error.toString(),
      },
    );
    rethrow;
  }
}

const String _createReadAtGuardSql =
    '''
CREATE TRIGGER IF NOT EXISTS trg_call_history_read_at_is_timestamp
BEFORE UPDATE OF read_at ON $kCallHistoryTable
WHEN NEW.read_at IS NOT NULL AND (
  typeof(NEW.read_at) != 'text' OR strftime('%s', NEW.read_at) IS NULL
)
BEGIN
  SELECT RAISE(ABORT, 'call_history.read_at must be a timestamp');
END
''';

/// Unread lookups are per contact and always filter on a NULL `read_at`.
const String _createUnreadIndexSql =
    '''
CREATE INDEX IF NOT EXISTS idx_call_history_contact_unread
ON $kCallHistoryTable(contact_account_peer_id, read_at)
''';
