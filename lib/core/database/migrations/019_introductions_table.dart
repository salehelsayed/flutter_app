import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// SQL statement to create the introductions table.
const String _createIntroductionsTableSql = '''
CREATE TABLE IF NOT EXISTS introductions (
  id TEXT PRIMARY KEY,
  introducer_id TEXT NOT NULL,
  recipient_id TEXT NOT NULL,
  introduced_id TEXT NOT NULL,
  introducer_username TEXT,
  recipient_username TEXT,
  introduced_username TEXT,
  recipient_status TEXT NOT NULL DEFAULT 'pending'
    CHECK(recipient_status IN ('pending','accepted','passed')),
  introduced_status TEXT NOT NULL DEFAULT 'pending'
    CHECK(introduced_status IN ('pending','accepted','passed')),
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK(status IN ('pending','mutual_accepted','passed','expired')),
  created_at TEXT NOT NULL,
  recipient_responded_at TEXT,
  introduced_responded_at TEXT
);
''';

/// SQL statement to create index on introductions for fast lookups by recipient.
const String _createRecipientIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_introductions_recipient ON introductions(recipient_id);
''';

/// SQL statement to create index on introductions for fast lookups by introduced.
const String _createIntroducedIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_introductions_introduced ON introductions(introduced_id);
''';

/// SQL statement to create index on introductions for fast lookups by introducer.
const String _createIntroducerIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_introductions_introducer ON introductions(introducer_id);
''';

/// Runs the introductions table migration.
///
/// Creates the introductions table and indexes. Idempotent via IF NOT EXISTS.
///
/// Emits flow events:
/// - `INTRODUCTIONS_DB_MIGRATION_START`
/// - `INTRODUCTIONS_DB_MIGRATION_SUCCESS`
/// - `INTRODUCTIONS_DB_MIGRATION_ERROR`
Future<void> runIntroductionsTableMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'INTRODUCTIONS_DB_MIGRATION_START',
    details: {'migration': '019_introductions_table'},
  );

  try {
    await db.execute(_createIntroductionsTableSql);
    await db.execute(_createRecipientIndexSql);
    await db.execute(_createIntroducedIndexSql);
    await db.execute(_createIntroducerIndexSql);

    emitFlowEvent(
      layer: 'DB',
      event: 'INTRODUCTIONS_DB_MIGRATION_SUCCESS',
      details: {'migration': '019_introductions_table'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'INTRODUCTIONS_DB_MIGRATION_ERROR',
      details: {'migration': '019_introductions_table', 'error': e.toString()},
    );
    rethrow;
  }
}
