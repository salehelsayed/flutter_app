import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_schema_inventory.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_database_manifest.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' show Database;
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

class MigrationDatabaseSnapshotExportException implements Exception {
  final String message;

  const MigrationDatabaseSnapshotExportException(this.message);

  @override
  String toString() => 'MigrationDatabaseSnapshotExportException($message)';
}

class MigrationDatabaseSnapshotExportResult {
  final String destinationPath;
  final MigrationDatabaseManifest manifest;

  const MigrationDatabaseSnapshotExportResult({
    required this.destinationPath,
    required this.manifest,
  });
}

class MigrationSqlCipherCapability {
  final bool isSupported;
  final String? failure;
  final String cipherVersion;
  final int exportedRowCount;

  const MigrationSqlCipherCapability._({
    required this.isSupported,
    required this.failure,
    required this.cipherVersion,
    required this.exportedRowCount,
  });

  factory MigrationSqlCipherCapability.supported({
    required String cipherVersion,
    required int exportedRowCount,
  }) {
    return MigrationSqlCipherCapability._(
      isSupported: true,
      failure: null,
      cipherVersion: cipherVersion,
      exportedRowCount: exportedRowCount,
    );
  }

  factory MigrationSqlCipherCapability.unsupported(String failure) {
    return MigrationSqlCipherCapability._(
      isSupported: false,
      failure: failure,
      cipherVersion: '',
      exportedRowCount: 0,
    );
  }
}

abstract class MigrationSqlCipherExportAdapter {
  Future<MigrationDatabaseCipherMetadata> captureCipherMetadata(Database db);

  Future<void> exportSqlCipherDatabase({
    required Database sourceDb,
    required String destinationPath,
    required String destinationKey,
    required MigrationDatabaseCipherMetadata cipherMetadata,
  });

  Future<Database> openExportedDatabase({
    required String path,
    required String key,
    required MigrationDatabaseCipherMetadata cipherMetadata,
  });

  Future<String> runIntegrityCheck(Database db);
}

class MigrationDatabaseSnapshotExporter {
  final MigrationSqlCipherExportAdapter adapter;
  final bool closeExportedDatabaseAfterValidation;

  const MigrationDatabaseSnapshotExporter({
    this.adapter = const DefaultMigrationSqlCipherExportAdapter(),
    this.closeExportedDatabaseAfterValidation = true,
  });

  Future<MigrationDatabaseSnapshotExportResult> exportSnapshot({
    required Database sourceDb,
    required String destinationPath,
    required String destinationKey,
    required String sourceAppVersion,
    required String sourceBuildNumber,
  }) async {
    final cipherMetadata = await adapter.captureCipherMetadata(sourceDb);
    if (cipherMetadata.policy != MigrationDatabaseCipherPolicy.compatible) {
      throw const MigrationDatabaseSnapshotExportException(
        'SQLCipher metadata is not compatible with migration export',
      );
    }
    await adapter.exportSqlCipherDatabase(
      sourceDb: sourceDb,
      destinationPath: destinationPath,
      destinationKey: destinationKey,
      cipherMetadata: cipherMetadata,
    );
    Database? exportedDb;
    try {
      exportedDb = await adapter.openExportedDatabase(
        path: destinationPath,
        key: destinationKey,
        cipherMetadata: cipherMetadata,
      );
      await _eraseInstallationLocalRows(exportedDb);
      final integrityResult = await adapter.runIntegrityCheck(exportedDb);
      if (integrityResult.toLowerCase() != 'ok') {
        throw MigrationDatabaseSnapshotExportException(
          'Exported database integrity check failed: $integrityResult',
        );
      }
      final inventory = await MigrationDatabaseSchemaInventory.fromDatabase(
        exportedDb,
      );
      if (closeExportedDatabaseAfterValidation) {
        await exportedDb.close();
        exportedDb = null;
      }
      final checksum = await computeFileChecksum(destinationPath);
      return MigrationDatabaseSnapshotExportResult(
        destinationPath: destinationPath,
        manifest: MigrationDatabaseManifest.current(
          sourceAppVersion: sourceAppVersion,
          sourceBuildNumber: sourceBuildNumber,
          schemaInventory: inventory,
          databaseChecksumSha256: checksum,
          cipherMetadata: cipherMetadata,
        ),
      );
    } finally {
      if (closeExportedDatabaseAfterValidation) {
        await exportedDb?.close();
      }
    }
  }

  static Future<String> computeFileChecksum(String path) async {
    final digest = sha256.convert(await File(path).readAsBytes());
    return digest.toString();
  }

  static Future<void> _eraseInstallationLocalRows(Database db) async {
    for (final tableName
        in MigrationDatabaseSchemaInventory.installationLocalTableNames) {
      final present = await db.rawQuery(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
        <Object?>[tableName],
      );
      if (present.isNotEmpty) {
        await db.delete(tableName);
      }
    }
  }

  static Future<MigrationSqlCipherCapability> probeSqlCipherExportCapability({
    required String tempDirectoryPath,
  }) async {
    final sourcePath = '$tempDirectoryPath/sqlcipher-capability-source.db';
    final exportedPath = '$tempDirectoryPath/sqlcipher-capability-export.db';
    const key = 'mig004-capability-key';
    const exportedKey = 'mig004-capability-export-key';
    Database? sourceDb;
    Database? exportedDb;
    final adapter = const DefaultMigrationSqlCipherExportAdapter();
    try {
      await _deleteIfExists(sourcePath);
      await _deleteIfExists(exportedPath);
      sourceDb = await sqlcipher.openDatabase(
        sourcePath,
        password: key, // SNAPSHOT_PASSPHRASE
        version: 1,
        singleInstance: false,
      );
      await sourceDb.execute('CREATE TABLE capability_probe(id INTEGER)');
      await sourceDb.insert('capability_probe', {'id': 1});
      final metadata = await adapter.captureCipherMetadata(sourceDb);
      if (metadata.policy != MigrationDatabaseCipherPolicy.compatible) {
        return MigrationSqlCipherCapability.unsupported(
          'SQLCipher metadata was unsupported: ${metadata.toJson()}',
        );
      }
      await adapter.exportSqlCipherDatabase(
        sourceDb: sourceDb,
        destinationPath: exportedPath,
        destinationKey: exportedKey,
        cipherMetadata: metadata,
      );
      exportedDb = await adapter.openExportedDatabase(
        path: exportedPath,
        key: exportedKey,
        cipherMetadata: metadata,
      );
      final integrity = await adapter.runIntegrityCheck(exportedDb);
      final countRows = await exportedDb.rawQuery(
        'SELECT COUNT(*) AS count FROM capability_probe',
      );
      final count = countRows.first['count'] as int? ?? 0;
      if (integrity.toLowerCase() != 'ok' || count != 1) {
        return MigrationSqlCipherCapability.unsupported(
          'Exported DB failed validation: integrity=$integrity count=$count',
        );
      }
      return MigrationSqlCipherCapability.supported(
        cipherVersion: metadata.cipherVersion,
        exportedRowCount: count,
      );
    } catch (error) {
      return MigrationSqlCipherCapability.unsupported(error.toString());
    } finally {
      await exportedDb?.close();
      await sourceDb?.close();
      await _deleteIfExists(exportedPath);
      await _deleteIfExists(sourcePath);
    }
  }

  static Future<void> _deleteIfExists(String path) async {
    for (final artifact in [path, '$path-wal', '$path-shm', '$path-journal']) {
      final file = File(artifact);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }
}

class DefaultMigrationSqlCipherExportAdapter
    implements MigrationSqlCipherExportAdapter {
  const DefaultMigrationSqlCipherExportAdapter();

  @override
  Future<MigrationDatabaseCipherMetadata> captureCipherMetadata(
    Database db,
  ) async {
    final cipherVersion = await _pragmaString(db, 'cipher_version');
    final kdfIter = await _pragmaInt(db, 'kdf_iter');
    final cipherPageSize = await _pragmaInt(db, 'cipher_page_size');
    return MigrationDatabaseCipherMetadata(
      cipherVersion: cipherVersion ?? '',
      kdfIter: kdfIter,
      cipherPageSize: cipherPageSize,
      policy: cipherVersion == null || cipherVersion.isEmpty
          ? MigrationDatabaseCipherPolicy.unsupported
          : MigrationDatabaseCipherPolicy.compatible,
    );
  }

  @override
  Future<void> exportSqlCipherDatabase({
    required Database sourceDb,
    required String destinationPath,
    required String destinationKey,
    required MigrationDatabaseCipherMetadata cipherMetadata,
  }) async {
    await MigrationDatabaseSnapshotExporter._deleteIfExists(destinationPath);
    final escapedPath = _escapeSqlString(destinationPath);
    final escapedKey = _escapeSqlString(destinationKey);
    await sourceDb.execute(
      "ATTACH DATABASE '$escapedPath' AS migration_export KEY '$escapedKey'",
    );
    try {
      await sourceDb.rawQuery("SELECT sqlcipher_export('migration_export')");
    } finally {
      await sourceDb.execute('DETACH DATABASE migration_export');
    }
  }

  @override
  Future<Database> openExportedDatabase({
    required String path,
    required String key,
    required MigrationDatabaseCipherMetadata cipherMetadata,
  }) {
    if (cipherMetadata.policy != MigrationDatabaseCipherPolicy.compatible) {
      throw const MigrationDatabaseSnapshotExportException(
        'Cannot open exported DB with unsupported cipher metadata',
      );
    }
    return sqlcipher.openDatabase(
      path,
      password: key, // SNAPSHOT_PASSPHRASE
      readOnly: false,
      singleInstance: false,
      onConfigure: (db) => _applyCipherPragmas(db, cipherMetadata),
    );
  }

  @override
  Future<String> runIntegrityCheck(Database db) async {
    final rows = await db.rawQuery('PRAGMA quick_check');
    if (rows.isEmpty) {
      return 'missing quick_check result';
    }
    return rows.first.values.first?.toString() ?? 'missing quick_check result';
  }

  static Future<String?> _pragmaString(Database db, String name) async {
    try {
      final rows = await db.rawQuery('PRAGMA $name');
      if (rows.isEmpty) {
        return null;
      }
      return rows.first.values.first?.toString();
    } catch (_) {
      return null;
    }
  }

  static Future<int?> _pragmaInt(Database db, String name) async {
    final value = await _pragmaString(db, name);
    if (value == null) {
      return null;
    }
    return int.tryParse(value);
  }

  static Future<void> _applyCipherPragmas(
    Database db,
    MigrationDatabaseCipherMetadata metadata,
  ) async {
    if (metadata.kdfIter != null) {
      await db.execute('PRAGMA kdf_iter = ${metadata.kdfIter}');
    }
    if (metadata.cipherPageSize != null) {
      await db.execute('PRAGMA cipher_page_size = ${metadata.cipherPageSize}');
    }
  }

  static String _escapeSqlString(String value) {
    return value.replaceAll("'", "''");
  }
}
