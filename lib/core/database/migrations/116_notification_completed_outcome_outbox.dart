// ignore_for_file: file_names

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

const String kNotificationCompletedOutcomeOutboxTable =
    'notification_completed_outcome_outbox';
const int kNotificationCompletedOutcomeOutboxCapacity = 512;
const Duration kNotificationCompletedOutcomeRetention = Duration(days: 7);

const String _migrationName = '116_notification_completed_outcome_outbox';

/// Creates a bounded, installation-local outbox with deliberately empty
/// historical backfill.
Future<void> runNotificationCompletedOutcomeOutboxMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'NOTIFICATION_COMPLETED_OUTCOME_OUTBOX_MIGRATION_START',
    details: const <String, Object?>{'migration': _migrationName},
  );
  try {
    await db.execute(_createTableSql);
    await db.execute(_createReadyIndexSql);
    await db.execute(_createCapacityTriggerSql);
    await db.execute(_createImmutableAuthorityTriggerSql);
    emitFlowEvent(
      layer: 'DB',
      event: 'NOTIFICATION_COMPLETED_OUTCOME_OUTBOX_MIGRATION_SUCCESS',
      details: const <String, Object?>{'migration': _migrationName},
    );
  } catch (error) {
    emitFlowEvent(
      layer: 'DB',
      event: 'NOTIFICATION_COMPLETED_OUTCOME_OUTBOX_MIGRATION_ERROR',
      details: <String, Object?>{
        'migration': _migrationName,
        'error': error.toString(),
      },
    );
    rethrow;
  }
}

const String _createTableSql =
    '''
CREATE TABLE IF NOT EXISTS $kNotificationCompletedOutcomeOutboxTable (
  wake_correlation TEXT NOT NULL PRIMARY KEY CHECK(
    typeof(wake_correlation) = 'text' AND
    length(wake_correlation) = 64 AND
    length(CAST(wake_correlation AS BLOB)) = 64 AND
    wake_correlation NOT GLOB '*[^0-9a-f]*'
  ),
  outcome TEXT NOT NULL CHECK(
    outcome IN ('in_chat', 'os_posted', 'suppressed_policy')
  ),
  revision INTEGER NOT NULL DEFAULT 1 CHECK(
    typeof(revision) = 'integer' AND revision >= 1
  ),
  retry_count INTEGER NOT NULL DEFAULT 0 CHECK(
    typeof(retry_count) = 'integer' AND retry_count >= 0
  ),
  last_error_code TEXT CHECK(
    last_error_code IS NULL OR (
      typeof(last_error_code) = 'text' AND
      last_error_code = trim(last_error_code) AND
      length(last_error_code) BETWEEN 1 AND 64
    )
  ),
  last_attempt_at TEXT CHECK(
    last_attempt_at IS NULL OR (
      typeof(last_attempt_at) = 'text' AND
      last_attempt_at = trim(last_attempt_at) AND
      length(last_attempt_at) BETWEEN 20 AND 40 AND
      strftime('%s', last_attempt_at) IS NOT NULL
    )
  ),
  next_attempt_at TEXT CHECK(
    next_attempt_at IS NULL OR (
      typeof(next_attempt_at) = 'text' AND
      next_attempt_at = trim(next_attempt_at) AND
      length(next_attempt_at) BETWEEN 20 AND 40 AND
      strftime('%s', next_attempt_at) IS NOT NULL
    )
  ),
  completed_at TEXT NOT NULL CHECK(
    typeof(completed_at) = 'text' AND
    completed_at = trim(completed_at) AND
    length(completed_at) BETWEEN 20 AND 40 AND
    strftime('%s', completed_at) IS NOT NULL
  ),
  created_at TEXT NOT NULL CHECK(
    typeof(created_at) = 'text' AND
    created_at = trim(created_at) AND
    length(created_at) BETWEEN 20 AND 40 AND
    strftime('%s', created_at) IS NOT NULL
  ),
  expires_at TEXT NOT NULL CHECK(
    typeof(expires_at) = 'text' AND
    expires_at = trim(expires_at) AND
    length(expires_at) BETWEEN 20 AND 40 AND
    strftime('%s', expires_at) IS NOT NULL
  ),
  CHECK(
    CAST(strftime('%s', expires_at) AS INTEGER) -
      CAST(strftime('%s', completed_at) AS INTEGER) = 604800
  ),
  CHECK(
    (retry_count = 0 AND last_error_code IS NULL AND
      last_attempt_at IS NULL AND next_attempt_at IS NULL) OR
    (retry_count > 0 AND last_error_code IS NOT NULL AND
      last_attempt_at IS NOT NULL AND next_attempt_at IS NOT NULL AND
      next_attempt_at > last_attempt_at AND next_attempt_at < expires_at)
  )
) WITHOUT ROWID
''';

const String _createReadyIndexSql =
    '''
CREATE INDEX IF NOT EXISTS idx_notification_completed_outcome_ready
ON $kNotificationCompletedOutcomeOutboxTable(
  next_attempt_at, completed_at, wake_correlation
)
''';

const String _createCapacityTriggerSql =
    '''
CREATE TRIGGER IF NOT EXISTS trg_notification_completed_outcome_capacity
BEFORE INSERT ON $kNotificationCompletedOutcomeOutboxTable
WHEN NOT EXISTS (
  SELECT 1 FROM $kNotificationCompletedOutcomeOutboxTable
  WHERE wake_correlation = NEW.wake_correlation
) AND (
  SELECT COUNT(*) FROM $kNotificationCompletedOutcomeOutboxTable
) >= $kNotificationCompletedOutcomeOutboxCapacity
BEGIN
  SELECT RAISE(ABORT, 'notification completed outcome capacity exhausted');
END
''';

const String _createImmutableAuthorityTriggerSql =
    '''
CREATE TRIGGER IF NOT EXISTS trg_notification_completed_outcome_immutable
BEFORE UPDATE ON $kNotificationCompletedOutcomeOutboxTable
WHEN NEW.wake_correlation IS NOT OLD.wake_correlation OR
  NEW.outcome IS NOT OLD.outcome OR
  NEW.completed_at IS NOT OLD.completed_at OR
  NEW.created_at IS NOT OLD.created_at OR
  NEW.expires_at IS NOT OLD.expires_at
BEGIN
  SELECT RAISE(ABORT, 'notification completed outcome authority is immutable');
END
''';
