import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Migration 004: Makes private_key and mnemonic12 columns nullable.
///
/// After this migration, secrets can be stored exclusively in secure storage
/// with the DB columns set to NULL.
///
/// Uses the standard SQLite "rename → create new → copy → drop old" pattern
/// because SQLite does not support ALTER COLUMN.
Future<void> runNullifySecretColumnsMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'NULLIFY_SECRETS_MIGRATION_START',
    details: {'migration': '004_nullify_secret_columns'},
  );

  try {
    await db.transaction((txn) async {
      // 1. Rename old table
      await txn.execute('ALTER TABLE identity RENAME TO identity_old');

      // 2. Create new table with nullable secret columns
      await txn.execute('''
CREATE TABLE identity (
  id INTEGER PRIMARY KEY,
  peer_id TEXT NOT NULL,
  public_key TEXT NOT NULL,
  private_key TEXT,
  mnemonic12 TEXT,
  ml_kem_public_key TEXT,
  ml_kem_secret_key TEXT,
  username TEXT NOT NULL DEFAULT 'Username',
  avatar_path TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
''');

      // 3. Copy data from old table
      await txn.execute('''
INSERT INTO identity (id, peer_id, public_key, private_key, mnemonic12,
  ml_kem_public_key, ml_kem_secret_key, username, avatar_path,
  created_at, updated_at)
SELECT id, peer_id, public_key, private_key, mnemonic12,
  ml_kem_public_key, ml_kem_secret_key, username, avatar_path,
  created_at, updated_at
FROM identity_old
''');

      // 4. Drop old table
      await txn.execute('DROP TABLE identity_old');
    });

    emitFlowEvent(
      layer: 'DB',
      event: 'NULLIFY_SECRETS_MIGRATION_SUCCESS',
      details: {'migration': '004_nullify_secret_columns'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'NULLIFY_SECRETS_MIGRATION_ERROR',
      details: {'migration': '004_nullify_secret_columns', 'error': e.toString()},
    );
    rethrow;
  }
}
