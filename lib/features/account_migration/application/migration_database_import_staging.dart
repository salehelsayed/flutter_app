import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_schema_inventory.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_snapshot_exporter.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_registry.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_staging.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_database_manifest.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_secure_storage_key.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

class MigrationDatabaseImportStagingException implements Exception {
  final String message;

  const MigrationDatabaseImportStagingException(this.message);

  @override
  String toString() => 'MigrationDatabaseImportStagingException($message)';
}

class MigrationDatabaseImportStagingResult {
  final Database database;
  final MigrationDatabaseManifest manifest;
  final String stagedDatabasePath;

  const MigrationDatabaseImportStagingResult({
    required this.database,
    required this.manifest,
    required this.stagedDatabasePath,
  });
}

abstract class MigrationStagedDatabaseOpener {
  Future<Database> open({
    required String path,
    required String key,
    required MigrationDatabaseCipherMetadata cipherMetadata,
  });
}

class MigrationDatabaseImportStaging {
  final MigrationSecureStorageStaging secureStorageStaging;
  final MigrationStagedDatabaseOpener opener;

  const MigrationDatabaseImportStaging({
    required this.secureStorageStaging,
    this.opener = const DefaultMigrationStagedDatabaseOpener(),
  });

  Future<MigrationDatabaseImportStagingResult> openVerifiedStagedDatabase({
    required String sessionId,
    required String stagedDatabasePath,
    required MigrationDatabaseManifest manifest,
  }) async {
    final compatibility = manifest.compatibility();
    if (!compatibility.isAccepted) {
      throw MigrationDatabaseImportStagingException(
        'Incompatible database manifest: ${compatibility.errors}',
      );
    }
    final dbKey = MigrationSecureStorageRegistry.fixedKey(
      scope: MigrationSecureStoreScope.primary,
      activeKey: MigrationSecureStorageRegistry.dbEncryptionKey,
    );
    if (dbKey == null) {
      throw const MigrationDatabaseImportStagingException(
        'Database encryption key is not registered for account migration',
      );
    }
    final stagedKey = await secureStorageStaging.readStagedValue(
      sessionId: sessionId,
      key: dbKey,
    );
    if (stagedKey == null || stagedKey.isEmpty) {
      throw const MigrationDatabaseImportStagingException(
        'Missing staged database encryption key',
      );
    }

    final file = File(stagedDatabasePath);
    final hasFile = await file.exists();
    if (hasFile) {
      final fileChecksum =
          await MigrationDatabaseSnapshotExporter.computeFileChecksum(
            stagedDatabasePath,
          );
      if (fileChecksum != manifest.databaseChecksumSha256) {
        throw const MigrationDatabaseImportStagingException(
          'Staged database checksum does not match manifest',
        );
      }
    }

    final database = await opener.open(
      path: stagedDatabasePath,
      key: stagedKey,
      cipherMetadata: manifest.cipherMetadata,
    );
    final integrity = await _runQuickCheck(database);
    if (integrity.toLowerCase() != 'ok') {
      throw MigrationDatabaseImportStagingException(
        'Staged database integrity check failed: $integrity',
      );
    }
    final inventory = await MigrationDatabaseSchemaInventory.fromDatabase(
      database,
    );
    if (inventory.schemaHash != manifest.schemaHash) {
      throw const MigrationDatabaseImportStagingException(
        'Staged database schema hash does not match manifest',
      );
    }
    if (!hasFile) {
      final logicalChecksum = await computeDatabaseChecksumForTesting(database);
      if (logicalChecksum != manifest.databaseChecksumSha256) {
        throw const MigrationDatabaseImportStagingException(
          'Staged database checksum does not match manifest',
        );
      }
    }

    return MigrationDatabaseImportStagingResult(
      database: database,
      manifest: manifest,
      stagedDatabasePath: stagedDatabasePath,
    );
  }

  static Future<String> computeDatabaseChecksumForTesting(
    DatabaseExecutor db,
  ) async {
    final inventory = await MigrationDatabaseSchemaInventory.fromDatabase(db);
    final payload = <String, Object?>{};
    for (final tableName in inventory.tableNames) {
      final columns = inventory.tables[tableName] ?? const <String>[];
      final rows = await db.query(tableName);
      payload[tableName] = rows
          .map(
            (row) => {
              for (final column in columns)
                column: _normalizeValue(row[column]),
            },
          )
          .toList(growable: false);
    }
    return sha256.convert(utf8.encode(jsonEncode(payload))).toString();
  }

  static Object? _normalizeValue(Object? value) {
    if (value is DateTime) {
      return value.toIso8601String();
    }
    if (value is List<int>) {
      return base64Encode(value);
    }
    return value;
  }

  static Future<String> _runQuickCheck(Database db) async {
    final rows = await db.rawQuery('PRAGMA quick_check');
    if (rows.isEmpty) {
      return 'missing quick_check result';
    }
    return rows.first.values.first?.toString() ?? 'missing quick_check result';
  }
}

class DefaultMigrationStagedDatabaseOpener
    implements MigrationStagedDatabaseOpener {
  const DefaultMigrationStagedDatabaseOpener();

  @override
  Future<Database> open({
    required String path,
    required String key,
    required MigrationDatabaseCipherMetadata cipherMetadata,
  }) {
    if (cipherMetadata.policy != MigrationDatabaseCipherPolicy.compatible) {
      throw const MigrationDatabaseImportStagingException(
        'Unsupported SQLCipher metadata for staged database',
      );
    }
    return sqlcipher.openDatabase(
      path,
      password: key, // SNAPSHOT_PASSPHRASE
      readOnly: false,
      singleInstance: false,
      onConfigure: (db) async {
        if (cipherMetadata.kdfIter != null) {
          await db.execute('PRAGMA kdf_iter = ${cipherMetadata.kdfIter}');
        }
        if (cipherMetadata.cipherPageSize != null) {
          await db.execute(
            'PRAGMA cipher_page_size = ${cipherMetadata.cipherPageSize}',
          );
        }
      },
    );
  }
}
