import 'package:flutter_app/core/database/db_write_transaction.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_import_staging.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_schema_inventory.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class MigrationDatabaseActiveImportException implements Exception {
  final String message;

  const MigrationDatabaseActiveImportException(this.message);

  @override
  String toString() => 'MigrationDatabaseActiveImportException($message)';
}

class MigrationDatabaseActiveImportResult {
  final List<String> importedTables;
  final int importedRows;

  const MigrationDatabaseActiveImportResult({
    required this.importedTables,
    required this.importedRows,
  });
}

class MigrationDatabaseActiveImporter {
  final Database activeDatabase;

  const MigrationDatabaseActiveImporter({required this.activeDatabase});

  Future<MigrationDatabaseActiveImportResult> importVerifiedStagedDatabase(
    MigrationDatabaseImportStagingResult staged,
  ) async {
    final compatibility = staged.manifest.compatibility();
    if (!compatibility.isAccepted) {
      throw MigrationDatabaseActiveImportException(
        'Incompatible staged database manifest: ${compatibility.errors}',
      );
    }

    final activeInventory = await MigrationDatabaseSchemaInventory.fromDatabase(
      activeDatabase,
    );
    if (activeInventory.schemaHash != staged.manifest.schemaHash) {
      throw const MigrationDatabaseActiveImportException(
        'Active database schema does not match staged migration manifest',
      );
    }

    final stagedLogicalChecksum =
        await MigrationDatabaseImportStaging.computeDatabaseChecksumForTesting(
          staged.database,
        );
    final tableRows = <String, List<Map<String, Object?>>>{};
    for (final tableName in staged.manifest.schemaInventory.tableNames) {
      tableRows[tableName] = await staged.database.query(tableName);
    }

    var foreignKeysWereEnabled = false;
    final foreignKeyRows = await activeDatabase.rawQuery('PRAGMA foreign_keys');
    if (foreignKeyRows.isNotEmpty) {
      final value = foreignKeyRows.first.values.first;
      foreignKeysWereEnabled = value == 1 || value == '1';
    }

    if (foreignKeysWereEnabled) {
      await activeDatabase.execute('PRAGMA foreign_keys = OFF');
    }
    try {
      var importedRows = 0;
      await dbWriteTransaction(activeDatabase, (txn) async {
        for (final tableName in staged.manifest.schemaInventory.tableNames) {
          await txn.delete(tableName);
        }
        for (final entry in tableRows.entries) {
          for (final row in entry.value) {
            await txn.insert(
              entry.key,
              row,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            importedRows += 1;
          }
        }
      });

      final integrity = await _runQuickCheck(activeDatabase);
      if (integrity.toLowerCase() != 'ok') {
        throw MigrationDatabaseActiveImportException(
          'Active database integrity check failed after import: $integrity',
        );
      }
      final importedChecksum =
          await MigrationDatabaseImportStaging.computeDatabaseChecksumForTesting(
            activeDatabase,
          );
      if (importedChecksum != stagedLogicalChecksum) {
        throw const MigrationDatabaseActiveImportException(
          'Active database checksum does not match imported staged database',
        );
      }

      return MigrationDatabaseActiveImportResult(
        importedTables: List.unmodifiable(
          staged.manifest.schemaInventory.tableNames,
        ),
        importedRows: importedRows,
      );
    } finally {
      if (foreignKeysWereEnabled) {
        await activeDatabase.execute('PRAGMA foreign_keys = ON');
      }
    }
  }

  static Future<String> _runQuickCheck(Database db) async {
    final rows = await db.rawQuery('PRAGMA quick_check');
    if (rows.isEmpty) {
      return 'missing quick_check result';
    }
    return rows.first.values.first?.toString() ?? 'missing quick_check result';
  }
}
