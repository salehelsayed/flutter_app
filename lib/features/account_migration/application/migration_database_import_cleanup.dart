import 'dart:io';

import 'package:flutter_app/features/account_migration/domain/models/migration_secure_storage_key.dart';

typedef MigrationFailedSecureStorageCleanup =
    Future<void> Function({
      required String sessionId,
      required Iterable<MigrationSecureStorageKey> registryKeys,
    });

class MigrationDatabaseImportCleanup {
  final MigrationFailedSecureStorageCleanup failedSecureStorageCleanup;

  const MigrationDatabaseImportCleanup({
    required this.failedSecureStorageCleanup,
  });

  Future<void> failedImportCleanup({
    required String sessionId,
    required String stagedDatabasePath,
    required String manifestPath,
    Iterable<String> extraArtifactPaths = const [],
    required Iterable<MigrationSecureStorageKey> registryKeys,
  }) async {
    await _deleteArtifacts([
      stagedDatabasePath,
      ..._sqliteSidecars(stagedDatabasePath),
      manifestPath,
      ...extraArtifactPaths,
    ]);
    await failedSecureStorageCleanup(
      sessionId: sessionId,
      registryKeys: registryKeys,
    );
  }

  Future<void> successfulImportCleanup({
    required String stagedDatabasePath,
    required String manifestPath,
    Iterable<String> extraArtifactPaths = const [],
  }) async {
    await _deleteArtifacts([
      stagedDatabasePath,
      ..._sqliteSidecars(stagedDatabasePath),
      manifestPath,
      ...extraArtifactPaths,
    ]);
  }

  Future<void> cancelledImportCleanup({
    required String sessionId,
    required String stagedDatabasePath,
    required String manifestPath,
    Iterable<String> extraArtifactPaths = const [],
    required Iterable<MigrationSecureStorageKey> registryKeys,
  }) {
    return failedImportCleanup(
      sessionId: sessionId,
      stagedDatabasePath: stagedDatabasePath,
      manifestPath: manifestPath,
      extraArtifactPaths: extraArtifactPaths,
      registryKeys: registryKeys,
    );
  }

  static Future<void> _deleteArtifacts(Iterable<String> paths) async {
    for (final path in paths) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  static List<String> _sqliteSidecars(String databasePath) {
    return ['$databasePath-wal', '$databasePath-shm', '$databasePath-journal'];
  }
}
