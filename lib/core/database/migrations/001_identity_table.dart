import 'package:sqflite/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// SQL statement to create the identity table.
///
/// This creates the identity table with all required columns for storing
/// a single active identity. The table uses `IF NOT EXISTS` for idempotency.
const String _createIdentityTableSql = '''
CREATE TABLE IF NOT EXISTS identity (
  id INTEGER PRIMARY KEY,
  peer_id TEXT NOT NULL,
  public_key TEXT NOT NULL,
  private_key TEXT NOT NULL,
  mnemonic12 TEXT NOT NULL,
  username TEXT NOT NULL DEFAULT 'Username',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
''';

/// Runs the identity table migration.
///
/// Creates the identity table in the provided database if it doesn't exist.
/// This function is idempotent and safe to run multiple times.
///
/// Emits flow events:
/// - `ID_DB_IDENTITY_MIGRATION_START` when migration begins
/// - `ID_DB_IDENTITY_MIGRATION_SUCCESS` on successful completion
/// - `ID_DB_IDENTITY_MIGRATION_ERROR` if an error occurs (then rethrows)
///
/// Parameters:
/// - [db]: The sqflite Database instance to run the migration on
///
/// Throws:
/// - Any database exceptions after logging them as flow events
///
/// Example:
/// ```dart
/// final db = await openDatabase('app.db');
/// await runIdentityTableMigration(db);
/// ```
Future<void> runIdentityTableMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'ID_DB_IDENTITY_MIGRATION_START',
    details: {'table': 'identity'},
  );

  try {
    await db.execute(_createIdentityTableSql);

    emitFlowEvent(
      layer: 'DB',
      event: 'ID_DB_IDENTITY_MIGRATION_SUCCESS',
      details: {'table': 'identity'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'ID_DB_IDENTITY_MIGRATION_ERROR',
      details: {'table': 'identity', 'error': e.toString()},
    );
    rethrow;
  }
}

/// Migration class for creating the identity table.
///
/// Provides a class-based interface for running the identity table migration,
/// suitable for integration with migration pipeline patterns.
///
/// Example:
/// ```dart
/// final db = await openDatabase('app.db');
/// await IdentityTableMigration.run(db);
/// ```
class IdentityTableMigration {
  /// The name of this migration for logging and identification.
  static const String migrationName = '001_identity_table';

  /// The table name this migration creates.
  static const String tableName = 'identity';

  /// Runs the identity table migration.
  ///
  /// Creates the identity table in the provided database if it doesn't exist.
  /// This method is idempotent and safe to run multiple times.
  ///
  /// Emits flow events:
  /// - `ID_DB_IDENTITY_MIGRATION_START` when migration begins
  /// - `ID_DB_IDENTITY_MIGRATION_SUCCESS` on successful completion
  /// - `ID_DB_IDENTITY_MIGRATION_ERROR` if an error occurs (then rethrows)
  ///
  /// Parameters:
  /// - [db]: The sqflite Database instance to run the migration on
  ///
  /// Throws:
  /// - Any database exceptions after logging them as flow events
  static Future<void> run(Database db) async {
    await runIdentityTableMigration(db);
  }
}
