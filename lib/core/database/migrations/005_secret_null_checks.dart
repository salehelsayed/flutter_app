import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Migration 005: Adds CHECK constraints enforcing that secret columns
/// remain NULL in the identity table.
///
/// After the secrets migration (DB → secure storage) has run, the three
/// secret columns (private_key, mnemonic12, ml_kem_secret_key) must never
/// hold values again.  This migration recreates the table with CHECK
/// constraints so any accidental INSERT / UPDATE that sets a non-NULL
/// value is rejected at the DB level.
///
/// Idempotent: checks sqlite_master for existing CHECK constraints before
/// running, so it is safe to call on every launch.
///
/// Uses the standard SQLite "rename → create new → copy → drop old" pattern
/// because SQLite does not support ALTER TABLE … ADD CONSTRAINT.
Future<void> runSecretNullChecksMigration(Database db) async {
  // Idempotency: skip if CHECK constraints already present
  final schema = await db.rawQuery(
    "SELECT sql FROM sqlite_master WHERE type='table' AND name='identity'",
  );
  if (schema.isNotEmpty) {
    final sql = schema.first['sql'] as String? ?? '';
    if (sql.contains('CHECK')) {
      emitFlowEvent(
        layer: 'DB',
        event: 'SECRET_NULL_CHECKS_MIGRATION_ALREADY_DONE',
        details: {'migration': '005_secret_null_checks'},
      );
      return;
    }
  }

  emitFlowEvent(
    layer: 'DB',
    event: 'SECRET_NULL_CHECKS_MIGRATION_START',
    details: {'migration': '005_secret_null_checks'},
  );

  try {
    await db.transaction((txn) async {
      // 1. Rename old table
      await txn.execute('ALTER TABLE identity RENAME TO identity_old');

      // 2. Create new table with CHECK constraints on secret columns
      //    and avatar_blob BLOB for encrypted avatar storage
      await txn.execute('''
CREATE TABLE identity (
  id INTEGER PRIMARY KEY,
  peer_id TEXT NOT NULL,
  public_key TEXT NOT NULL,
  private_key TEXT CHECK (private_key IS NULL),
  mnemonic12 TEXT CHECK (mnemonic12 IS NULL),
  ml_kem_public_key TEXT,
  ml_kem_secret_key TEXT CHECK (ml_kem_secret_key IS NULL),
  username TEXT NOT NULL DEFAULT 'Username',
  avatar_path TEXT,
  avatar_blob BLOB,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
''');

      // 3. Copy data from old table
      await txn.execute('''
INSERT INTO identity (id, peer_id, public_key, private_key, mnemonic12,
  ml_kem_public_key, ml_kem_secret_key, username, avatar_path,
  avatar_blob, created_at, updated_at)
SELECT id, peer_id, public_key, private_key, mnemonic12,
  ml_kem_public_key, ml_kem_secret_key, username, avatar_path,
  NULL, created_at, updated_at
FROM identity_old
''');

      // 4. Drop old table
      await txn.execute('DROP TABLE identity_old');
    });

    emitFlowEvent(
      layer: 'DB',
      event: 'SECRET_NULL_CHECKS_MIGRATION_SUCCESS',
      details: {'migration': '005_secret_null_checks'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'SECRET_NULL_CHECKS_MIGRATION_ERROR',
      details: {'migration': '005_secret_null_checks', 'error': e.toString()},
    );
    rethrow;
  }
}
