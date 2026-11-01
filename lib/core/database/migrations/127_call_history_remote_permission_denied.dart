// ignore_for_file: file_names

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';
import '117_call_history.dart';

const String _migrationName = '127_call_history_remote_permission_denied';
const String _rebuiltTable = 'call_history_v127';

/// Lets `call_history.terminal_reason` hold `remote_permission_denied`: the
/// caller's record of a callee whose microphone is off. SQLite cannot widen a
/// CHECK in place, so the table is rebuilt with every row, its read state,
/// the read-state trigger and both indexes. Running it again changes nothing.
Future<void> runCallHistoryRemotePermissionDeniedMigration(
  Database database,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'CALL_HISTORY_REMOTE_PERMISSION_DENIED_MIGRATION_START',
    details: const <String, Object?>{'migration': _migrationName},
  );
  try {
    final schema = await database.rawQuery(
      "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
      <Object?>[kCallHistoryTable],
    );
    final sql = schema.isEmpty ? '' : schema.single['sql'] as String? ?? '';
    if (!sql.contains("'remote_permission_denied'")) {
      await database.execute('DROP TABLE IF EXISTS $_rebuiltTable');
      await database.execute(_createTableSql(_rebuiltTable));
      await database.execute('''
INSERT INTO $_rebuiltTable ($_columns)
SELECT $_columns FROM $kCallHistoryTable
''');
      await database.execute('DROP TABLE $kCallHistoryTable');
      await database.execute(
        'ALTER TABLE $_rebuiltTable RENAME TO $kCallHistoryTable',
      );
      await database.execute(_createContactTimelineIndexSql);
      await database.execute(_createUnreadIndexSql);
      await database.execute(_createReadAtGuardSql);
    }
    emitFlowEvent(
      layer: 'DB',
      event: 'CALL_HISTORY_REMOTE_PERMISSION_DENIED_MIGRATION_SUCCESS',
      details: const <String, Object?>{'migration': _migrationName},
    );
  } catch (error) {
    emitFlowEvent(
      layer: 'DB',
      event: 'CALL_HISTORY_REMOTE_PERMISSION_DENIED_MIGRATION_ERROR',
      details: <String, Object?>{
        'migration': _migrationName,
        'error': error.toString(),
      },
    );
    rethrow;
  }
}

const String _columns =
    'call_id, contact_account_peer_id, direction, terminal_reason, status, '
    'started_at, connected_at, ended_at, transport_route_class, created_at, '
    'updated_at, read_at';

String _createTableSql(String table) =>
    '''
CREATE TABLE $table (
  call_id TEXT NOT NULL PRIMARY KEY CHECK(
    typeof(call_id) = 'text' AND
    length(call_id) = 36 AND
    call_id = lower(call_id) AND
    substr(call_id, 9, 1) = '-' AND
    substr(call_id, 14, 1) = '-' AND
    substr(call_id, 15, 1) = '4' AND
    substr(call_id, 19, 1) = '-' AND
    substr(call_id, 20, 1) GLOB '[89ab]' AND
    substr(call_id, 24, 1) = '-' AND
    replace(call_id, '-', '') NOT GLOB '*[^0-9a-f]*'
  ),
  contact_account_peer_id TEXT NOT NULL CHECK(
    typeof(contact_account_peer_id) = 'text' AND
    contact_account_peer_id = trim(contact_account_peer_id) AND
    length(contact_account_peer_id) BETWEEN 1 AND 512
  ),
  direction TEXT NOT NULL CHECK(direction IN ('outgoing', 'incoming')),
  terminal_reason TEXT NOT NULL CHECK(terminal_reason IN (
    'declined', 'busy', 'caller_cancelled', 'no_answer', 'remote_hangup',
    'local_hangup', 'permission_denied', 'remote_permission_denied',
    'unsupported', 'signaling_failed', 'media_failed', 'reconnect_failed',
    'expired', 'app_shutdown', 'policy_rejected'
  )),
  status TEXT NOT NULL CHECK(status IN (
    'completed', 'missed', 'declined', 'busy', 'cancelled', 'failed'
  )),
  started_at TEXT NOT NULL CHECK(
    typeof(started_at) = 'text' AND strftime('%s', started_at) IS NOT NULL
  ),
  connected_at TEXT CHECK(
    connected_at IS NULL OR (
      typeof(connected_at) = 'text' AND
      strftime('%s', connected_at) IS NOT NULL AND
      connected_at >= started_at
    )
  ),
  ended_at TEXT NOT NULL CHECK(
    typeof(ended_at) = 'text' AND
    strftime('%s', ended_at) IS NOT NULL AND
    ended_at >= started_at AND
    (connected_at IS NULL OR ended_at >= connected_at)
  ),
  transport_route_class TEXT CHECK(
    transport_route_class IS NULL OR
    transport_route_class IN ('direct', 'circuit_relay', 'ephemeral_mailbox')
  ),
  created_at TEXT NOT NULL CHECK(
    typeof(created_at) = 'text' AND strftime('%s', created_at) IS NOT NULL
  ),
  updated_at TEXT NOT NULL CHECK(
    typeof(updated_at) = 'text' AND
    strftime('%s', updated_at) IS NOT NULL AND
    updated_at >= created_at
  ),
  read_at TEXT
) WITHOUT ROWID
''';

const String _createContactTimelineIndexSql =
    '''
CREATE INDEX IF NOT EXISTS idx_call_history_contact_timeline
ON $kCallHistoryTable(contact_account_peer_id, started_at DESC, call_id ASC)
''';

const String _createUnreadIndexSql =
    '''
CREATE INDEX IF NOT EXISTS idx_call_history_contact_unread
ON $kCallHistoryTable(contact_account_peer_id, read_at)
''';

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
