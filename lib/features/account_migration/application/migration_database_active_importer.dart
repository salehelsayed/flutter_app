import 'dart:convert';

import 'package:crypto/crypto.dart';
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

typedef MigrationDatabaseActiveIntegrityCheck =
    Future<String> Function(DatabaseExecutor db);
typedef MigrationDatabaseActiveLogicalChecksum =
    Future<String> Function(DatabaseExecutor db);

final class _ActiveDatabaseTrigger {
  final String name;
  final String sql;

  const _ActiveDatabaseTrigger({required this.name, required this.sql});
}

class MigrationDatabaseActiveImporter {
  final Database activeDatabase;
  final MigrationDatabaseActiveIntegrityCheck? _activeIntegrityCheck;
  final MigrationDatabaseActiveLogicalChecksum? _activeLogicalChecksum;

  const MigrationDatabaseActiveImporter({
    required this.activeDatabase,
    MigrationDatabaseActiveIntegrityCheck? activeIntegrityCheck,
    MigrationDatabaseActiveLogicalChecksum? activeLogicalChecksum,
  }) : _activeIntegrityCheck = activeIntegrityCheck,
       _activeLogicalChecksum = activeLogicalChecksum;

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

    final stagedLogicalChecksum = await _computeTransferableLogicalChecksum(
      staged.database,
    );
    final transferableTableNames =
        staged.manifest.schemaInventory.transferableTableNames;
    final tableRows = <String, List<Map<String, Object?>>>{};
    for (final tableName in transferableTableNames) {
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
        final activeTriggers = await _snapshotActiveTriggers(txn);
        for (final trigger in activeTriggers) {
          await txn.execute(
            'DROP TRIGGER IF EXISTS ${_quoteIdentifier(trigger.name)}',
          );
        }

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

        for (final trigger in activeTriggers) {
          await txn.execute(trigger.sql);
        }

        final integrity = await (_activeIntegrityCheck ?? _runQuickCheck)(txn);
        if (integrity.toLowerCase() != 'ok') {
          throw MigrationDatabaseActiveImportException(
            'Active database integrity check failed after import: $integrity',
          );
        }
        final importedChecksum =
            await (_activeLogicalChecksum ??
                _computeTransferableLogicalChecksum)(txn);
        if (importedChecksum != stagedLogicalChecksum) {
          throw const MigrationDatabaseActiveImportException(
            'Active database checksum does not match imported staged database',
          );
        }
      });

      return MigrationDatabaseActiveImportResult(
        importedTables: List.unmodifiable(transferableTableNames),
        importedRows: importedRows,
      );
    } finally {
      if (foreignKeysWereEnabled) {
        await activeDatabase.execute('PRAGMA foreign_keys = ON');
      }
    }
  }

  static Future<List<_ActiveDatabaseTrigger>> _snapshotActiveTriggers(
    DatabaseExecutor db,
  ) async {
    final rows = await db.rawQuery(
      "SELECT name, sql FROM sqlite_master WHERE type = 'trigger' "
      'ORDER BY name',
    );
    final triggers = <_ActiveDatabaseTrigger>[];
    for (final row in rows) {
      final name = (row['name'] as String?)?.trim();
      final sql = (row['sql'] as String?)?.trim();
      if (name == null || name.isEmpty || sql == null || sql.isEmpty) {
        throw const MigrationDatabaseActiveImportException(
          'Active database contains a trigger that cannot be restored',
        );
      }
      triggers.add(_ActiveDatabaseTrigger(name: name, sql: sql));
    }
    return triggers;
  }

  static String _quoteIdentifier(String value) {
    return '"${value.replaceAll('"', '""')}"';
  }

  static Future<String> _runQuickCheck(DatabaseExecutor db) async {
    final rows = await db.rawQuery('PRAGMA quick_check');
    if (rows.isEmpty) {
      return 'missing quick_check result';
    }
    return rows.first.values.first?.toString() ?? 'missing quick_check result';
  }

  static Future<String> _computeTransferableLogicalChecksum(
    DatabaseExecutor db,
  ) async {
    final inventory = await MigrationDatabaseSchemaInventory.fromDatabase(db);
    final payload = <String, Object?>{};
    for (final tableName in inventory.tableNames) {
      final columns = inventory.tables[tableName] ?? const <String>[];
      final rows =
          MigrationDatabaseSchemaInventory.isInstallationLocal(tableName)
          ? const <Map<String, Object?>>[]
          : await db.query(tableName);
      payload[tableName] = rows
          .map(
            (row) => <String, Object?>{
              for (final column in columns)
                column: _normalizeChecksumValue(row[column]),
            },
          )
          .toList(growable: false);
    }
    return sha256.convert(utf8.encode(jsonEncode(payload))).toString();
  }

  static Object? _normalizeChecksumValue(Object? value) {
    if (value is DateTime) return value.toIso8601String();
    if (value is List<int>) return base64Encode(value);
    return value;
  }
}
