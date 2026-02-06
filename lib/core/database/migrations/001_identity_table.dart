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
  avatar_path TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
''';

/// SQL statement to create the contacts table.
///
/// Stores contacts added via QR code scanning.
const String _createContactsTableSql = '''
CREATE TABLE IF NOT EXISTS contacts (
  peer_id TEXT PRIMARY KEY,
  public_key TEXT NOT NULL,
  rendezvous TEXT NOT NULL,
  username TEXT NOT NULL,
  signature TEXT NOT NULL,
  scanned_at TEXT NOT NULL,
  avatar_path TEXT
);
''';

/// SQL statement to create the contact_requests table.
///
/// Stores pending contact requests received via P2P.
const String _createContactRequestsTableSql = '''
CREATE TABLE IF NOT EXISTS contact_requests (
  peer_id TEXT PRIMARY KEY,
  public_key TEXT NOT NULL,
  rendezvous TEXT NOT NULL,
  username TEXT NOT NULL,
  signature TEXT NOT NULL,
  received_at TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending'
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

  // Create contacts table
  emitFlowEvent(
    layer: 'DB',
    event: 'ID_DB_CONTACTS_MIGRATION_START',
    details: {'table': 'contacts'},
  );

  try {
    await db.execute(_createContactsTableSql);

    emitFlowEvent(
      layer: 'DB',
      event: 'ID_DB_CONTACTS_MIGRATION_SUCCESS',
      details: {'table': 'contacts'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'ID_DB_CONTACTS_MIGRATION_ERROR',
      details: {'table': 'contacts', 'error': e.toString()},
    );
    rethrow;
  }

  // Create contact_requests table
  emitFlowEvent(
    layer: 'DB',
    event: 'ID_DB_CONTACT_REQUESTS_MIGRATION_START',
    details: {'table': 'contact_requests'},
  );

  try {
    await db.execute(_createContactRequestsTableSql);

    emitFlowEvent(
      layer: 'DB',
      event: 'ID_DB_CONTACT_REQUESTS_MIGRATION_SUCCESS',
      details: {'table': 'contact_requests'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'ID_DB_CONTACT_REQUESTS_MIGRATION_ERROR',
      details: {'table': 'contact_requests', 'error': e.toString()},
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
