import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/database/db_write_transaction.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_local_transfer_runtime.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_transfer_flow.dart';
import 'package:flutter_app/features/account_migration/application/migration_breadcrumb.dart';
import 'package:flutter_app/features/account_migration/application/migration_cutover_coordinator.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_active_importer.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_import_staging.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_schema_inventory.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_snapshot_exporter.dart';
import 'package:flutter_app/features/account_migration/application/migration_entry_stream_source.dart';
import 'package:flutter_app/features/account_migration/application/migration_export_authorization.dart';
import 'package:flutter_app/features/account_migration/application/migration_file_manifest_builder.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_reference_collector.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_registry.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_staging.dart';
import 'package:flutter_app/features/account_migration/application/migration_segment_crypto.dart';
import 'package:flutter_app/features/account_migration/application/migration_transfer_checkpoint_store.dart';
import 'package:flutter_app/features/account_migration/domain/models/account_migration_authority_state.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_cutover_record.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_database_manifest.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_file_manifest.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_qr_payload.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_secure_storage_key.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_transfer_manifest.dart';
import 'package:flutter_app/features/account_migration/domain/repositories/account_migration_authority_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';

class AccountMigrationBundleAssemblyException implements Exception {
  final String message;

  const AccountMigrationBundleAssemblyException(this.message);

  @override
  String toString() => 'AccountMigrationBundleAssemblyException($message)';
}

class AccountMigrationBundleImportException implements Exception {
  final String message;

  const AccountMigrationBundleImportException(this.message);

  @override
  String toString() => 'AccountMigrationBundleImportException($message)';
}

class AccountMigrationProductionBundleSource {
  final Database sourceDb;
  final SecureKeyStore primaryStore;
  final SecureKeyStore? sharedStore;
  final String documentsRootPath;
  final String exportDirectoryPath;
  final MigrationDatabaseSnapshotExporter snapshotExporter;

  /// Streaming file IO seam: every content read (length, hash, chunk stream)
  /// goes through this reader, so tests can prove no whole-file reads happen.
  final MigrationEntryFileReader fileReader;

  final int segmentSize;
  final String sourceAppVersion;
  final String sourceBuildNumber;

  const AccountMigrationProductionBundleSource({
    required this.sourceDb,
    required this.primaryStore,
    this.sharedStore,
    required this.documentsRootPath,
    required this.exportDirectoryPath,
    required this.snapshotExporter,
    this.fileReader = const IoMigrationEntryFileReader(),
    this.segmentSize = 1024 * 1024,
    this.sourceAppVersion = MigrationDatabaseManifest.unknownAppVersion,
    this.sourceBuildNumber = MigrationDatabaseManifest.unknownBuildNumber,
  });

  Future<AccountMigrationLocalTransferBundle> call(
    AccountMigrationTransferRequest request,
  ) async {
    var phase = 'validateConfiguration';
    void enterPhase(String next) {
      phase = next;
      migrationBreadcrumb('ASSEMBLY_PHASE', fields: {'phase': next});
    }

    try {
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_BUNDLE_SOURCE_START',
        details: {'sessionId': request.sessionId},
      );
      migrationBreadcrumb('ASSEMBLY_PHASE', fields: {'phase': phase});
      if (segmentSize <= 0) {
        throw const AccountMigrationBundleAssemblyException(
          'segment size must be positive',
        );
      }

      enterPhase('prepareExportDirectory');
      final exportDir = Directory(exportDirectoryPath);
      await exportDir.create(recursive: true);

      final snapshotPath = p.join(
        exportDirectoryPath,
        '${Uri.encodeComponent(request.sessionId)}.identity.snapshot.db',
      );
      // A retried attempt re-exports over the previous attempt's snapshot;
      // SQLCipher/VACUUM INTO refuses to overwrite an existing target.
      for (final stale in [
        snapshotPath,
        '$snapshotPath-wal',
        '$snapshotPath-shm',
        '$snapshotPath-journal',
      ]) {
        final staleFile = File(stale);
        if (await staleFile.exists()) {
          await staleFile.delete();
        }
      }
      enterPhase('readDatabaseKey');
      final dbKey = await primaryStore.read(
        MigrationSecureStorageRegistry.dbEncryptionKey,
      );
      if (dbKey == null || dbKey.isEmpty) {
        throw const AccountMigrationBundleAssemblyException(
          'missing critical secure value: db_encryption_key',
        );
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_BUNDLE_SOURCE_DB_KEY_READY',
        details: {'sessionId': request.sessionId},
      );

      enterPhase('loadDatabaseRows');
      final rows = await _loadBundleRows(sourceDb);
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_BUNDLE_SOURCE_ROWS_LOADED',
        details: {
          'sessionId': request.sessionId,
          'chatMediaCount': rows.chatMediaRows.length,
          'directMediaBlobCustodyCount': rows.directMediaBlobCustodyRows.length,
          'postMediaCount': rows.postMediaRows.length,
          'postMediaRecoveryCount': rows.postMediaRecoveryRows.length,
          'contactCount': rows.contactRows.length,
          'identityCount': rows.identityRows.length,
          'groupCount': rows.groupRows.length,
          'groupMaterialRowCount': rows.groupKeyRows.length,
          'groupMaterialDraftRowCount': rows.groupKeyDraftRows.length,
        },
      );
      final discoveredKeys = MigrationSecureStorageReferenceCollector()
          .collectDiscoveredKeys(
            committedGroupKeyRows: rows.groupKeyRows,
            pendingGroupKeyRows: rows.groupKeyDraftRows,
            mediaAttachmentRows: rows.chatMediaRows,
          );

      enterPhase('collectSecureStorage');
      final secureEntries = await _collectSecureEntries(discoveredKeys);
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_BUNDLE_SOURCE_SECURE_ENTRIES_COLLECTED',
        details: {
          'sessionId': request.sessionId,
          'secureEntryCount': secureEntries.length,
          'discoveredKeyCount': discoveredKeys.length,
        },
      );

      enterPhase('buildFilePayload');
      final filePayload = await _buildFilePayload(
        rows,
        sessionId: request.sessionId,
      );
      enterPhase('applyFilePathRepairs');
      await _applyFilePathRepairs(
        filePayload.pathRepairs,
        sessionId: request.sessionId,
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_BUNDLE_SOURCE_FILE_PAYLOAD_BUILT',
        details: {
          'sessionId': request.sessionId,
          'fileEntryCount': filePayload.entries.length,
          'fileEntryBytes': _fileEntryBytes(filePayload.entries),
          'fileEntryCountsByKind': _fileManifestItemCountsByKind(
            filePayload.manifestJson,
          ),
          'fileEntries': _fileEntryTelemetryDetails(
            manifestJson: filePayload.manifestJson,
            entries: filePayload.entries,
          ),
        },
      );

      enterPhase('exportDatabaseSnapshot');
      final snapshot = await snapshotExporter.exportSnapshot(
        sourceDb: sourceDb,
        destinationPath: snapshotPath,
        destinationKey: dbKey,
        sourceAppVersion: sourceAppVersion,
        sourceBuildNumber: sourceBuildNumber,
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_BUNDLE_SOURCE_SNAPSHOT_EXPORTED',
        details: {
          'sessionId': request.sessionId,
          'databaseVersion': snapshot.manifest.databaseVersion,
        },
      );

      // The snapshot stays on disk and is streamed chunk-by-chunk; only the
      // small metadata blob (secure values + manifests) is materialized.
      enterPhase('writeMetadataBlob');
      final metadata = _AccountMigrationBundleMetadata(
        sessionId: request.sessionId,
        databaseManifest: snapshot.manifest,
        secureStorageEntries: secureEntries,
        fileManifestJson: filePayload.manifestJson,
      );
      final metadataPath = p.join(
        exportDirectoryPath,
        '${Uri.encodeComponent(request.sessionId)}.metadata.json',
      );
      await File(metadataPath).writeAsString(
        migrationTransferCanonicalJson(metadata.toJson()),
        flush: true,
      );

      enterPhase('buildEntryStream');
      final metadataSha256 = await fileReader.sha256Hex(metadataPath);
      final bundleId =
          'bundle-${migrationTransferStringSha256Hex('${request.sessionId}:'
          '${snapshot.manifest.databaseChecksumSha256}:'
          '$metadataSha256').substring(0, 32)}';
      final entryInputs = <MigrationEntryStreamInput>[
        MigrationEntryStreamInput(
          entryId: 'database',
          kind: MigrationTransferEntryKind.database,
          filePath: snapshot.destinationPath,
        ),
        for (final entry in filePayload.entries)
          MigrationEntryStreamInput(
            entryId: entry.entryId,
            kind: MigrationTransferEntryKind.file,
            filePath: entry.absolutePath,
            relativePath: entry.relativePath,
            sizeBytes: entry.sizeBytes,
            sha256: entry.sha256,
          ),
        MigrationEntryStreamInput(
          entryId: 'secure-values',
          kind: MigrationTransferEntryKind.secureValues,
          filePath: metadataPath,
          sizeBytes: null,
          sha256: metadataSha256,
        ),
      ];
      final bundle =
          await MigrationEntryStreamSource(
            fileReader: fileReader,
            chunkSize: segmentSize,
          ).build(
            sessionId: request.sessionId,
            bundleId: bundleId,
            entries: entryInputs,
            cleanupAfterSuccess: () async {
              for (final path in [snapshot.destinationPath, metadataPath]) {
                final file = File(path);
                if (await file.exists()) {
                  await file.delete();
                }
              }
            },
          );
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_BUNDLE_SOURCE_BUILT',
        details: {
          'sessionId': request.sessionId,
          'entryCount': bundle.manifest.entries.length,
          'segmentCount': bundle.manifest.totalChunkCount,
          'totalBytes': bundle.manifest.totalBytes,
        },
      );
      migrationBreadcrumb(
        'ASSEMBLY_OK',
        fields: {
          'segments': bundle.manifest.totalChunkCount,
          'entries': bundle.manifest.entries.length,
        },
      );
      return bundle;
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_BUNDLE_SOURCE_FAILED',
        details: {
          'sessionId': request.sessionId,
          'phase': phase,
          'errorType': accountMigrationTransferErrorType(error),
          'reason': accountMigrationBundleSourceFailureReason(error),
        },
      );
      // Release-visible failure breadcrumb (see migration_breadcrumb.dart): the
      // emitFlowEvent above is gated off in release builds, so this names the
      // failing assembly phase + reason in the device console for field
      // diagnostics. detail is value-redacted by the primitive.
      migrationBreadcrumb(
        'ASSEMBLY_FAIL',
        fields: {
          'phase': phase,
          'type': accountMigrationTransferErrorType(error),
          'reason': accountMigrationBundleSourceFailureReason(error),
          'detail': error,
        },
      );
      rethrow;
    }
  }

  Future<List<_SecureStorageBundleEntry>> _collectSecureEntries(
    Iterable<MigrationSecureStorageKey> discoveredKeys,
  ) async {
    final registryKeys = MigrationSecureStorageRegistry.resolve(
      discoveredKeys: discoveredKeys,
    );
    final entries = <_SecureStorageBundleEntry>[];
    for (final key in registryKeys) {
      if (!key.includeInExportPayload) {
        continue;
      }
      if (key.scope == MigrationSecureStoreScope.iosSharedAccessGroup &&
          sharedStore == null) {
        continue;
      }

      final value = await _storeFor(key.scope).read(key.activeKey);
      if (value == null || value.isEmpty) {
        if (key.criticality == MigrationSecureStorageKeyCriticality.critical) {
          throw AccountMigrationBundleAssemblyException(
            'missing critical secure value: ${key.sortKey}',
          );
        }
        continue;
      }
      entries.add(_SecureStorageBundleEntry(key: key, value: value));
    }
    return entries;
  }

  SecureKeyStore _storeFor(MigrationSecureStoreScope scope) {
    switch (scope) {
      case MigrationSecureStoreScope.primary:
        return primaryStore;
      case MigrationSecureStoreScope.iosSharedAccessGroup:
        final store = sharedStore;
        if (store == null) {
          throw const AccountMigrationBundleAssemblyException(
            'shared secure store is not configured',
          );
        }
        return store;
    }
  }

  Future<_FileBundlePayload> _buildFilePayload(
    _BundleRows rows, {
    required String sessionId,
  }) async {
    var fileManifest = await _buildMigrationFileManifest(rows);
    fileManifest = await _downgradeMissingChatMediaIssues(
      manifest: fileManifest,
      sessionId: sessionId,
      phase: 'build',
    );

    _emitFileManifestIssues(
      sessionId: sessionId,
      phase: 'build',
      issues: fileManifest.issues,
    );
    if (fileManifest.issues.any((issue) => issue.blocking)) {
      _emitSourceRelayFreeMediaAudit(
        sessionId: sessionId,
        rows: rows,
        manifest: fileManifest,
        fileEntryCount: 0,
        fileEntryBytes: 0,
        phase: 'build',
      );
      _emitFileManifestDegraded(
        sessionId: sessionId,
        fileEntryCount: 0,
        issues: fileManifest.issues,
      );
      throw AccountMigrationBundleAssemblyException(
        'file manifest has blocking issues: '
        '${_fileManifestIssueCodeNames(fileManifest.issues).join(',')}',
      );
    }

    final exportedItems = <MigrationFileManifestItem>[];
    final runtimeIssues = <MigrationFileManifestIssue>[];
    final entries = <_FileEntryRef>[];
    for (final item in fileManifest.items) {
      final absolutePath = _safeJoin(documentsRootPath, item.relativePath);
      // Streaming re-verification (size + hash) guards against the file
      // changing between manifest build and entry stream — file contents are
      // never materialized in RAM.
      final int sizeBytes;
      final String sha256Hex;
      try {
        sizeBytes = await fileReader.length(absolutePath);
        sha256Hex = await fileReader.sha256Hex(absolutePath);
      } on FileSystemException {
        runtimeIssues.add(
          MigrationFileManifestIssue(
            code: MigrationFileManifestIssueCode.missingRequiredFile,
            sourceTable: item.sourceTable,
            sourceId: item.sourceId,
            relativePath: item.relativePath,
            criticality: item.criticality,
          ),
        );
        continue;
      }

      if (sizeBytes != item.sizeBytes || sha256Hex != item.sha256) {
        runtimeIssues.add(
          MigrationFileManifestIssue(
            code: MigrationFileManifestIssueCode.fileSizeMismatch,
            sourceTable: item.sourceTable,
            sourceId: item.sourceId,
            relativePath: item.relativePath,
            criticality: item.criticality,
          ),
        );
        continue;
      }

      exportedItems.add(item);
      entries.add(
        _FileEntryRef(
          entryId: 'file-${entries.length}',
          relativePath: item.relativePath,
          absolutePath: absolutePath,
          sha256: item.sha256,
          sizeBytes: sizeBytes,
        ),
      );
    }

    _emitFileManifestIssues(
      sessionId: sessionId,
      phase: 'read',
      issues: runtimeIssues,
    );

    var manifest = MigrationFileManifest(
      items: exportedItems,
      issues: [...fileManifest.issues, ...runtimeIssues],
      pathRepairs: fileManifest.pathRepairs,
    );
    manifest = await _downgradeMissingChatMediaIssues(
      manifest: manifest,
      sessionId: sessionId,
      phase: 'read',
    );
    _emitSourceRelayFreeMediaAudit(
      sessionId: sessionId,
      rows: rows,
      manifest: manifest,
      fileEntryCount: entries.length,
      fileEntryBytes: _fileEntryBytes(entries),
      phase: 'read',
    );
    if (manifest.issues.any((issue) => issue.blocking)) {
      _emitFileManifestDegraded(
        sessionId: sessionId,
        fileEntryCount: entries.length,
        issues: manifest.issues,
      );
      throw AccountMigrationBundleAssemblyException(
        'file manifest has blocking issues: '
        '${_fileManifestIssueCodeNames(manifest.issues).join(',')}',
      );
    }
    return _FileBundlePayload(
      manifestJson: manifest.toJson(),
      entries: entries,
      pathRepairs: manifest.pathRepairs,
    );
  }

  Future<MigrationFileManifest> _buildMigrationFileManifest(_BundleRows rows) {
    return MigrationFileManifestBuilder(
      documentsRootPath: documentsRootPath,
      secureValueReader: primaryStore.read,
    ).build(
      chatMediaRows: rows.chatMediaRows,
      directMediaBlobCustodyRows: rows.directMediaBlobCustodyRows,
      postMediaRows: rows.postMediaRows,
      postMediaRecoveryRows: rows.postMediaRecoveryRows,
      contactRows: rows.contactRows,
      identityRows: rows.identityRows,
      groupRows: rows.groupRows,
      scanDocumentsForCacheAndTransients: false,
    );
  }

  Future<MigrationFileManifest> _downgradeMissingChatMediaIssues({
    required MigrationFileManifest manifest,
    required String sessionId,
    required String phase,
  }) async {
    final issuesToDowngrade = manifest.issues
        .where(_shouldDowngradeMissingChatMediaIssue)
        .toList(growable: false);
    if (issuesToDowngrade.isEmpty) {
      return manifest;
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'ACCOUNT_MIGRATION_BUNDLE_SOURCE_MISSING_MEDIA_DOWNGRADE_START',
      details: {
        'sessionId': sessionId,
        'phase': phase,
        'downgradeCount': issuesToDowngrade.length,
        'targetDownloadStatus': kMediaDownloadStatusIntegrityFailed,
        'issueCodes': _fileManifestIssueCodeNames(issuesToDowngrade),
        'issues': _fileManifestIssueDetails(issuesToDowngrade),
      },
    );

    var updatedRowCount = 0;
    await dbWriteTransaction(sourceDb, (txn) async {
      for (final issue in issuesToDowngrade) {
        updatedRowCount += await txn.update(
          'media_attachments',
          {
            'local_path': null,
            'download_status': kMediaDownloadStatusIntegrityFailed,
          },
          where: 'id = ?',
          whereArgs: [issue.sourceId],
        );
      }
    });

    final downgradedIssues = issuesToDowngrade.toSet();
    final sanitizedIssues = manifest.issues
        .map(
          (issue) => downgradedIssues.contains(issue)
              ? MigrationFileManifestIssue(
                  code: issue.code,
                  sourceTable: issue.sourceTable,
                  sourceId: issue.sourceId,
                  relativePath: issue.relativePath,
                  blocking: false,
                  criticality: issue.criticality,
                  diagnostics: issue.diagnostics,
                )
              : issue,
        )
        .toList(growable: false);

    emitFlowEvent(
      layer: 'FL',
      event: 'ACCOUNT_MIGRATION_BUNDLE_SOURCE_MISSING_MEDIA_DOWNGRADE_SUCCESS',
      details: {
        'sessionId': sessionId,
        'phase': phase,
        'downgradeCount': issuesToDowngrade.length,
        'updatedRowCount': updatedRowCount,
        'targetDownloadStatus': kMediaDownloadStatusIntegrityFailed,
        'issueCodes': _fileManifestIssueCodeNames(sanitizedIssues),
        'issues': _fileManifestIssueDetails(sanitizedIssues),
      },
    );

    return MigrationFileManifest(
      items: manifest.items,
      issues: sanitizedIssues,
      pathRepairs: manifest.pathRepairs,
    );
  }

  bool _shouldDowngradeMissingChatMediaIssue(MigrationFileManifestIssue issue) {
    return issue.blocking &&
        issue.sourceTable == 'media_attachments' &&
        issue.code == MigrationFileManifestIssueCode.missingRequiredFile &&
        issue.criticality == MigrationFileCriticality.nonCriticalCache;
  }

  Future<void> _applyFilePathRepairs(
    List<MigrationFilePathRepair> repairs, {
    required String sessionId,
  }) async {
    final mediaRepairs = repairs
        .where((repair) => repair.sourceTable == 'media_attachments')
        .toList(growable: false);
    if (mediaRepairs.isEmpty) {
      return;
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'ACCOUNT_MIGRATION_BUNDLE_SOURCE_FILE_PATH_REPAIR_START',
      details: {'sessionId': sessionId, 'repairCount': mediaRepairs.length},
    );
    await dbWriteTransaction(sourceDb, (txn) async {
      for (final repair in mediaRepairs) {
        await txn.update(
          'media_attachments',
          {'local_path': repair.relativePath},
          where: 'id = ?',
          whereArgs: [repair.sourceId],
        );
      }
    });
    emitFlowEvent(
      layer: 'FL',
      event: 'ACCOUNT_MIGRATION_BUNDLE_SOURCE_FILE_PATH_REPAIR_SUCCESS',
      details: {'sessionId': sessionId, 'repairCount': mediaRepairs.length},
    );
  }

  void _emitFileManifestIssues({
    required String sessionId,
    required String phase,
    required List<MigrationFileManifestIssue> issues,
  }) {
    if (issues.isEmpty) {
      return;
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'ACCOUNT_MIGRATION_BUNDLE_SOURCE_FILE_MANIFEST_ISSUES',
      details: {
        'sessionId': sessionId,
        'phase': phase,
        'issueCount': issues.length,
        'blockingIssueCount': issues.where((issue) => issue.blocking).length,
        'issueCodes': _fileManifestIssueCodeNames(issues),
        'issues': _fileManifestIssueDetails(issues),
      },
    );
    _emitFileManifestIssueDetails(
      sessionId: sessionId,
      phase: phase,
      issues: issues,
    );
  }

  void _emitFileManifestDegraded({
    required String sessionId,
    required int fileEntryCount,
    required List<MigrationFileManifestIssue> issues,
  }) {
    emitFlowEvent(
      layer: 'FL',
      event: 'ACCOUNT_MIGRATION_BUNDLE_SOURCE_FILE_MANIFEST_DEGRADED',
      details: {
        'sessionId': sessionId,
        'fileEntryCount': fileEntryCount,
        'issueCount': issues.length,
        'blockingIssueCount': issues.where((issue) => issue.blocking).length,
        'issueCodes': _fileManifestIssueCodeNames(issues),
        'issues': _fileManifestIssueDetails(issues),
      },
    );
  }

  void _emitFileManifestIssueDetails({
    required String sessionId,
    required String phase,
    required List<MigrationFileManifestIssue> issues,
  }) {
    for (var i = 0; i < issues.length; i += 1) {
      final issue = issues[i];
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_BUNDLE_SOURCE_FILE_MANIFEST_ISSUE',
        details: {
          'sessionId': sessionId,
          'phase': phase,
          'issueIndex': i,
          'issueCount': issues.length,
          ..._fileManifestIssueTelemetryDetail(issue),
        },
      );
      if (issue.sourceTable == 'media_attachments' &&
          issue.code == MigrationFileManifestIssueCode.missingRequiredFile &&
          issue.diagnostics.isNotEmpty) {
        final compactDiagnostics = _compactFileManifestIssueDiagnostics(
          issue.diagnostics,
        );
        emitFlowEvent(
          layer: 'FL',
          event: 'ACCOUNT_MIGRATION_BUNDLE_SOURCE_MISSING_MEDIA_DIAGNOSTIC',
          details: {
            'sessionId': sessionId,
            'phase': phase,
            'issueIndex': i,
            'issueCount': issues.length,
            'sourceId': issue.sourceId,
            if (issue.relativePath != null) 'relativePath': issue.relativePath,
            'blocking': issue.blocking,
            if (issue.criticality != null)
              'criticality': issue.criticality!.name,
            'diagnostics': compactDiagnostics,
          },
        );
        final candidates = _fileManifestIssueCandidateDiagnostics(
          issue.diagnostics,
        );
        for (
          var candidateIndex = 0;
          candidateIndex < candidates.length;
          candidateIndex += 1
        ) {
          emitFlowEvent(
            layer: 'FL',
            event:
                'ACCOUNT_MIGRATION_BUNDLE_SOURCE_MISSING_MEDIA_CANDIDATE_DIAGNOSTIC',
            details: {
              'sessionId': sessionId,
              'phase': phase,
              'issueIndex': i,
              'issueCount': issues.length,
              'sourceId': issue.sourceId,
              if (issue.relativePath != null)
                'relativePath': issue.relativePath,
              'blocking': issue.blocking,
              if (issue.criticality != null)
                'criticality': issue.criticality!.name,
              'candidateIndex': candidateIndex,
              'candidateCount': candidates.length,
              'candidateDiagnostic': candidates[candidateIndex],
            },
          );
        }
      }
    }
  }

  void _emitSourceRelayFreeMediaAudit({
    required String sessionId,
    required _BundleRows rows,
    required MigrationFileManifest manifest,
    required int fileEntryCount,
    required int fileEntryBytes,
    required String phase,
  }) {
    final blockingIssueCount = manifest.issues
        .where((issue) => issue.blocking)
        .length;
    final missingRequiredMediaCount = manifest.issues
        .where(
          (issue) =>
              issue.sourceTable == 'media_attachments' &&
              issue.code == MigrationFileManifestIssueCode.missingRequiredFile,
        )
        .length;
    final sanitizedMissingMediaCount = manifest.issues
        .where(
          (issue) =>
              !issue.blocking &&
              issue.sourceTable == 'media_attachments' &&
              issue.code == MigrationFileManifestIssueCode.missingRequiredFile,
        )
        .length;
    final migratedChatMediaCount = manifest.items
        .where(
          (item) =>
              item.sourceTable == 'media_attachments' &&
              (item.kind == MigrationFileManifestItemKind.chatMedia ||
                  item.kind == MigrationFileManifestItemKind.pendingUpload),
        )
        .length;

    emitFlowEvent(
      layer: 'FL',
      event: 'ACCOUNT_MIGRATION_BUNDLE_SOURCE_RELAY_FREE_MEDIA_AUDIT',
      details: {
        'sessionId': sessionId,
        'phase': phase,
        'policy': 'sanitize_missing_media_without_relay',
        'sourceTransport': 'move_bundle_direct_wifi',
        'relayMediaDownloadCount': 0,
        'requiredChatMediaCount': _requiredChatMediaRowCount(
          rows.chatMediaRows,
        ),
        'migratedChatMediaCount': migratedChatMediaCount,
        'fileEntryCount': fileEntryCount,
        'fileEntryBytes': fileEntryBytes,
        'blockingIssueCount': blockingIssueCount,
        'missingRequiredMediaCount': missingRequiredMediaCount,
        'sanitizedMissingMediaCount': sanitizedMissingMediaCount,
        'relayDependencyRisk':
            blockingIssueCount > 0 || sanitizedMissingMediaCount > 0,
      },
    );
  }

  int _requiredChatMediaRowCount(Iterable<Map<String, Object?>> rows) {
    return rows.where(_requiresLocalChatMediaFile).length;
  }

  bool _requiresLocalChatMediaFile(Map<String, Object?> row) {
    final status = _stringValue(row['download_status']) ?? '';
    return status.isEmpty || status == 'done' || status == 'upload_pending';
  }

  String? _stringValue(Object? value) {
    if (value is String && value.isNotEmpty) {
      return value;
    }
    return null;
  }
}

const int _fileManifestIssueDetailLimit = 8;

List<Map<String, Object?>> _fileManifestIssueDetails(
  Iterable<MigrationFileManifestIssue> issues,
) {
  return issues
      .take(_fileManifestIssueDetailLimit)
      .map(_fileManifestIssueTelemetryDetail)
      .toList(growable: false);
}

Map<String, Object?> _fileManifestIssueTelemetryDetail(
  MigrationFileManifestIssue issue,
) {
  final detail = <String, Object?>{
    'code': issue.code.name,
    'sourceTable': issue.sourceTable,
    'blocking': issue.blocking,
    if (issue.criticality != null) 'criticality': issue.criticality!.name,
  };
  if (issue.sourceTable == 'direct_media_blob_custody') {
    return detail;
  }
  return <String, Object?>{
    ...detail,
    'sourceId': issue.sourceId,
    if (issue.relativePath != null) 'relativePath': issue.relativePath,
    if (issue.diagnostics.isNotEmpty)
      'diagnostics': _compactFileManifestIssueDiagnostics(issue.diagnostics),
  };
}

Map<String, Object?> _compactFileManifestIssueDiagnostics(
  Map<String, Object?> diagnostics,
) {
  final compact = Map<String, Object?>.from(diagnostics);
  final candidateDiagnostics = compact.remove('candidateDiagnostics');
  if (candidateDiagnostics is Iterable) {
    compact['candidateDiagnosticsCount'] = candidateDiagnostics.length;
  }
  return compact;
}

List<Map<String, Object?>> _fileManifestIssueCandidateDiagnostics(
  Map<String, Object?> diagnostics,
) {
  final candidateDiagnostics = diagnostics['candidateDiagnostics'];
  if (candidateDiagnostics is! Iterable) {
    return const [];
  }
  return candidateDiagnostics
      .whereType<Map>()
      .map(
        (candidate) => candidate.map(
          (key, value) => MapEntry(key.toString(), value as Object?),
        ),
      )
      .toList(growable: false);
}

List<String> _fileManifestIssueCodeNames(
  Iterable<MigrationFileManifestIssue> issues,
) {
  final names = issues.map((issue) => issue.code.name).toSet().toList()..sort();
  return names;
}

int _fileEntryBytes(Iterable<_FileEntryRef> entries) {
  return entries.fold<int>(0, (sum, entry) => sum + entry.sizeBytes);
}

Map<String, int> _fileManifestItemCountsByKind(
  Map<String, Object?> manifestJson,
) {
  final counts = <String, int>{};
  for (final item in _fileManifestItemsByPath(manifestJson).values) {
    final kind = item['kind'] as String? ?? 'unknown';
    counts[kind] = (counts[kind] ?? 0) + 1;
  }
  return counts;
}

List<Map<String, Object?>> _fileEntryTelemetryDetails({
  required Map<String, Object?> manifestJson,
  required List<_FileEntryRef> entries,
}) {
  final manifestItems = _fileManifestItemsByPath(manifestJson);
  return entries
      .take(_fileManifestIssueDetailLimit)
      .map(
        (entry) => _fileEntryTelemetryDetail(
          entry: entry,
          manifestItem: manifestItems[entry.relativePath],
          bytesLength: entry.sizeBytes,
        ),
      )
      .toList(growable: false);
}

Map<String, Map<String, Object?>> _fileManifestItemsByPath(
  Map<String, Object?> manifestJson,
) {
  final itemsByPath = <String, Map<String, Object?>>{};
  final rawItems = manifestJson['items'];
  if (rawItems is! List) {
    return itemsByPath;
  }
  for (final raw in rawItems.whereType<Map>()) {
    final relativePath = raw['relative_path'] as String?;
    if (relativePath == null || relativePath.isEmpty) {
      continue;
    }
    itemsByPath[relativePath] = <String, Object?>{
      'kind': raw['kind'],
      'criticality': raw['criticality'],
      'relativePath': relativePath,
      'sourceTable': raw['source_table'],
      'sourceId': raw['source_id'],
      'sizeBytes': raw['size_bytes'],
      'sha256': raw['sha256'],
      if (raw['metadata'] is Map)
        'metadata': Map<String, Object?>.from(raw['metadata'] as Map),
    };
  }
  return itemsByPath;
}

Map<String, Object?> _fileEntryTelemetryDetail({
  required _FileEntryRef entry,
  required Map<String, Object?>? manifestItem,
  int? bytesLength,
  bool? writeVerified,
}) {
  if (manifestItem?['kind'] ==
          MigrationFileManifestItemKind.directMediaBlobCustody.name ||
      manifestItem?['kind'] ==
          MigrationFileManifestItemKind.groupMediaBlobCustody.name) {
    return <String, Object?>{
      'kind': manifestItem?['kind'],
      'criticality': manifestItem?['criticality'],
      'sourceTable': manifestItem?['sourceTable'],
      'writeVerified': ?writeVerified,
    };
  }
  final sha256 = manifestItem?['sha256'] as String? ?? entry.sha256;
  final details = <String, Object?>{
    'relativePath': entry.relativePath,
    'kind': manifestItem?['kind'],
    'criticality': manifestItem?['criticality'],
    'sourceTable': manifestItem?['sourceTable'],
    'sourceId': manifestItem?['sourceId'],
    'manifestSizeBytes': manifestItem?['sizeBytes'],
    'entryBytes': bytesLength ?? entry.sizeBytes,
    'sha256Prefix': _sha256Prefix(sha256),
    if (manifestItem?['metadata'] is Map) 'metadata': manifestItem?['metadata'],
  };
  if (writeVerified != null) {
    details['writeVerified'] = writeVerified;
  }
  return details;
}

String _sha256Prefix(String sha256) {
  return sha256.length <= 12 ? sha256 : sha256.substring(0, 12);
}

typedef MigrationLedgerStoreFactory =
    MigrationTransferLedgerStore Function(String sessionDirectoryPath);

MigrationTransferLedgerStore _defaultLedgerStoreFactory(
  String sessionDirectoryPath,
) {
  return FileMigrationTransferLedgerStore(
    filePath: p.join(sessionDirectoryPath, 'ledger.json'),
  );
}

class AccountMigrationProductionBundleReceiver
    implements
        AccountMigrationLocalBundleCutoverReceiver,
        AccountMigrationLocalStreamBundleReceiver {
  final MigrationStreamCrypto streamCrypto;
  final MigrationSecureStorageStaging secureStorageStaging;
  final MigrationDatabaseImportStaging databaseImportStaging;
  final MigrationDatabaseActiveImporter? activeDatabaseImporter;
  final MigrationCutoverCoordinator? cutoverCoordinator;
  final AccountMigrationAuthorityRepository? authorityRepository;
  final Future<void> Function(String accountPeerId)?
  publishCanonicalAccountBinding;
  final String stagingDirectoryPath;
  final String documentsRootPath;
  final MigrationLedgerStoreFactory ledgerStoreFactory;

  final _sessions = <String, _BundleReceiveSession>{};

  AccountMigrationProductionBundleReceiver({
    required this.streamCrypto,
    required this.secureStorageStaging,
    required this.databaseImportStaging,
    this.activeDatabaseImporter,
    this.cutoverCoordinator,
    this.authorityRepository,
    this.publishCanonicalAccountBinding,
    required this.stagingDirectoryPath,
    required this.documentsRootPath,
    this.ledgerStoreFactory = _defaultLedgerStoreFactory,
  });

  @override
  Future<bool> acceptTranscript({
    required AuthenticatedMigrationChannelTranscript transcript,
    required MigrationPendingPairingSession pendingSession,
  }) async {
    return transcript.sessionId == pendingSession.sessionId &&
        transcript.newPhoneEphemeralPublicKey ==
            pendingSession.newPhoneEphemeralPublicKey;
  }

  @override
  Future<bool> acceptManifest({
    required MigrationTransferManifest manifest,
    required AuthenticatedMigrationChannelTranscript transcript,
    required MigrationPendingPairingSession pendingSession,
  }) async {
    if (manifest.sessionId != pendingSession.sessionId ||
        manifest.sessionId != transcript.sessionId) {
      return false;
    }
    // Fail closed on protocol mismatch in BOTH directions: this build only
    // imports entry-streamed v2 bundles, so a v1 manifest is rejected typed
    // (senderTooOld) instead of entering the retired whole-payload path.
    final compatibility = manifest.compatibility(
      importerProtocolVersion: MigrationTransferManifest.protocolVersion,
    );
    if (!compatibility.isAccepted) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_BUNDLE_RECEIVER_MANIFEST_INCOMPATIBLE',
        details: {
          'sessionId': manifest.sessionId,
          'protocolVersion': manifest.protocolVersionValue,
          'importerProtocolVersion': MigrationTransferManifest.protocolVersion,
          'errors': compatibility.errors
              .map((error) => error.name)
              .toList(growable: false),
        },
      );
      return false;
    }

    final sessionDir = Directory(
      p.join(stagingDirectoryPath, Uri.encodeComponent(manifest.sessionId)),
    );
    await _sweepOrphanedSessionDirectories(keep: sessionDir.path);
    final manifestFile = File(p.join(sessionDir.path, 'manifest.json'));
    final entriesDir = Directory(p.join(sessionDir.path, 'entries'));
    final manifestJson = migrationTransferCanonicalJson(manifest.toJson());
    final ledger = ledgerStoreFactory(sessionDir.path);
    var resumed = false;
    MigrationTransferManifest? previousManifest;
    if (await manifestFile.exists()) {
      final previousJson = await manifestFile.readAsString();
      if (previousJson == manifestJson) {
        resumed = true;
      } else {
        try {
          final decoded = jsonDecode(previousJson);
          if (decoded is Map<String, dynamic>) {
            previousManifest = MigrationTransferManifest.fromJson(decoded);
          }
        } catch (_) {
          // A torn manifest copy means no carry-over — wipe below.
        }
      }
    }
    if (!resumed) {
      // A different manifest restarts the transfer, but per-entry progress
      // whose (sha, size, chunkSize) is unchanged carries over — a re-built
      // bundle with a changed DB snapshot must not resend unchanged media.
      await _carryOverOrWipeStaging(
        sessionDir: sessionDir,
        entriesDir: entriesDir,
        ledger: ledger,
        previousManifest: previousManifest,
        manifest: manifest,
      );
    }
    await entriesDir.create(recursive: true);
    await manifestFile.writeAsString(manifestJson, flush: true);
    final session = _BundleReceiveSession(
      manifest: manifest,
      sessionDirectoryPath: sessionDir.path,
      entriesDirectoryPath: entriesDir.path,
      ledger: ledger,
    );
    _sessions[manifest.sessionId] = session;

    // Zero-size entries never produce a wire chunk; they verify from the
    // manifest hash alone.
    for (final entry in manifest.entries) {
      if (entry.sizeBytes > 0) {
        continue;
      }
      if (entry.sha256 != _emptySha256Hex) {
        return false;
      }
      await File(
        p.join(entriesDir.path, _entryFileName(entry.entryId)),
      ).writeAsBytes(const [], flush: true);
      await ledger.markEntryVerified(
        manifest: manifest,
        entryId: entry.entryId,
        sizeBytes: 0,
        sha256: entry.sha256,
      );
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'ACCOUNT_MIGRATION_BUNDLE_RECEIVER_MANIFEST_STAGED',
      details: {
        'sessionId': manifest.sessionId,
        'bundleId': manifest.bundleId,
        'entryCount': manifest.entries.length,
        'chunkCount': manifest.totalChunkCount,
        'totalBytes': manifest.totalBytes,
        'resumed': resumed,
      },
    );
    return true;
  }

  /// Carries per-entry progress forward into a changed manifest when the
  /// entry is byte-identical (same sha/size/chunkSize), wipes the rest.
  Future<void> _carryOverOrWipeStaging({
    required Directory sessionDir,
    required Directory entriesDir,
    required MigrationTransferLedgerStore ledger,
    required MigrationTransferManifest? previousManifest,
    required MigrationTransferManifest manifest,
  }) async {
    if (previousManifest == null ||
        previousManifest.sessionId != manifest.sessionId) {
      if (await sessionDir.exists()) {
        await sessionDir.delete(recursive: true);
      }
      return;
    }

    final previousStatus = await ledger.status(previousManifest);
    final previouslyVerified = previousStatus.verifiedEntryIds.toSet();
    final keptFileNames = <String>{};
    var carriedEntryCount = 0;
    for (final entry in manifest.entries) {
      final previous = previousManifest.entryById(entry.entryId);
      if (previous == null ||
          previous.sha256 != entry.sha256 ||
          previous.sizeBytes != entry.sizeBytes ||
          previous.chunkSize != entry.chunkSize) {
        continue;
      }
      if (previouslyVerified.contains(entry.entryId)) {
        await ledger.markEntryVerified(
          manifest: manifest,
          entryId: entry.entryId,
          sizeBytes: entry.sizeBytes,
          sha256: entry.sha256,
        );
        keptFileNames.add(_entryFileName(entry.entryId));
        carriedEntryCount += 1;
      } else {
        final offset = previousStatus.entryOffsets[entry.entryId] ?? 0;
        if (offset > 0) {
          await ledger.recordProgress(
            manifest: manifest,
            entryId: entry.entryId,
            verifiedOffset: offset,
            incrementalSha256: '',
          );
          keptFileNames.add('${_entryFileName(entry.entryId)}.partial');
          carriedEntryCount += 1;
        }
      }
    }
    if (previousManifest.bundleId != manifest.bundleId) {
      await ledger.clear(
        sessionId: previousManifest.sessionId,
        bundleId: previousManifest.bundleId,
      );
    }
    if (await entriesDir.exists()) {
      await for (final child in entriesDir.list()) {
        if (child is File && !keptFileNames.contains(p.basename(child.path))) {
          await child.delete();
        }
      }
    }
    final staleStagedDb = File(p.join(sessionDir.path, 'identity.staged.db'));
    if (await staleStagedDb.exists()) {
      await staleStagedDb.delete();
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'ACCOUNT_MIGRATION_BUNDLE_RECEIVER_STAGING_CARRIED_OVER',
      details: {
        'sessionId': manifest.sessionId,
        'carriedEntryCount': carriedEntryCount,
        'entryCount': manifest.entries.length,
      },
    );
  }

  /// Staging dirs from abandoned/cancelled sessions can never be resumed
  /// (their pairing session is gone), so a new move sweeps them.
  Future<void> _sweepOrphanedSessionDirectories({required String keep}) async {
    try {
      final root = Directory(stagingDirectoryPath);
      if (!await root.exists()) {
        return;
      }
      await for (final child in root.list()) {
        if (child is Directory && child.path != keep) {
          await child.delete(recursive: true);
        }
      }
    } catch (_) {
      // Sweeping is best-effort hygiene; never block a new transfer on it.
    }
  }

  @override
  Future<bool> acceptSegment({
    required MigrationTransferManifest manifest,
    required MigrationEncryptedSegment segment,
    required AuthenticatedMigrationChannelTranscript transcript,
    required MigrationPendingPairingSession pendingSession,
  }) async {
    // Protocol v1 whole-payload segments are retired; v1 manifests are
    // already rejected at acceptManifest, so this is unreachable in practice.
    emitFlowEvent(
      layer: 'FL',
      event: 'ACCOUNT_MIGRATION_BUNDLE_RECEIVER_SEGMENT_RETIRED',
      details: {'sessionId': manifest.sessionId, 'segmentIndex': segment.index},
    );
    return false;
  }

  @override
  Future<AccountMigrationChunkAcceptOutcome> acceptChunk({
    required MigrationTransferManifest manifest,
    required MigrationEncryptedChunk chunk,
    required AuthenticatedMigrationChannelTranscript transcript,
    required MigrationPendingPairingSession pendingSession,
  }) async {
    final session = _sessions[manifest.sessionId];
    if (session == null || session.manifest.bundleId != manifest.bundleId) {
      return const AccountMigrationChunkAcceptOutcome(
        code: AccountMigrationChunkAcceptCode.sessionUnavailable,
      );
    }
    final ledger = session.ledger;
    final descriptor = manifest.entryById(chunk.entryId);
    if (descriptor == null) {
      return await _chunkOutcome(
        session,
        AccountMigrationChunkAcceptCode.unknownEntry,
      );
    }
    if (chunk.offset < 0 ||
        chunk.offset >= descriptor.sizeBytes ||
        chunk.offset % descriptor.chunkSize != 0 ||
        chunk.chunkIndex != chunk.offset ~/ descriptor.chunkSize) {
      return await _chunkOutcome(
        session,
        AccountMigrationChunkAcceptCode.entryMismatch,
      );
    }
    final remaining = descriptor.sizeBytes - chunk.offset;
    final expectedLength = remaining < descriptor.chunkSize
        ? remaining
        : descriptor.chunkSize;
    final expectedIsFinal =
        chunk.offset + expectedLength >= descriptor.sizeBytes;
    if (chunk.isFinal != expectedIsFinal) {
      return await _chunkOutcome(
        session,
        AccountMigrationChunkAcceptCode.entryMismatch,
      );
    }

    final entryState = await ledger.entryState(
      manifest: manifest,
      entryId: chunk.entryId,
    );
    if (entryState?.verified ?? false) {
      return await _chunkOutcome(
        session,
        AccountMigrationChunkAcceptCode.duplicate,
      );
    }
    final verifiedOffset = entryState?.verifiedOffset ?? 0;
    if (chunk.offset + expectedLength <= verifiedOffset) {
      // Retransmission of an already-applied chunk: idempotent accept, no
      // double write, the offset/hash state stays untouched.
      return await _chunkOutcome(
        session,
        AccountMigrationChunkAcceptCode.duplicate,
      );
    }
    if (chunk.offset != verifiedOffset) {
      return await _chunkOutcome(
        session,
        AccountMigrationChunkAcceptCode.outOfOrder,
      );
    }

    // A resumed attempt re-encapsulates, so a new KEM ciphertext re-derives
    // the session key; chunks under the old key are already on disk.
    var decryptSession = session.decryptSession;
    if (decryptSession == null ||
        decryptSession.kemCiphertext != chunk.kemCiphertext) {
      try {
        decryptSession = await streamCrypto.decapsulateSession(
          ownMlKemSecretKey: pendingSession.newPhoneEphemeralSecretKey,
          sessionId: manifest.sessionId,
          bundleId: manifest.bundleId,
          direction: MigrationStreamDirection.oldToNew,
          kemCiphertext: chunk.kemCiphertext,
        );
      } on MigrationStreamCryptoException {
        return await _chunkOutcome(
          session,
          AccountMigrationChunkAcceptCode.decryptFailed,
        );
      }
      session.decryptSession = decryptSession;
    }
    final Uint8List plaintext;
    try {
      plaintext = await streamCrypto.decryptChunk(
        session: decryptSession,
        encryptedChunk: chunk,
        associatedData: MigrationChunkAssociatedData(
          sessionId: manifest.sessionId,
          bundleId: manifest.bundleId,
          entryId: chunk.entryId,
          chunkIndex: chunk.chunkIndex,
          offset: chunk.offset,
          isFinal: chunk.isFinal,
        ),
      );
    } on MigrationStreamCryptoException {
      return await _chunkOutcome(
        session,
        AccountMigrationChunkAcceptCode.decryptFailed,
      );
    }
    if (plaintext.length != expectedLength) {
      return await _chunkOutcome(
        session,
        AccountMigrationChunkAcceptCode.decryptFailed,
      );
    }

    final partialFile = File(
      p.join(
        session.entriesDirectoryPath,
        '${_entryFileName(chunk.entryId)}.partial',
      ),
    );
    final hash = await _ensureEntryHash(
      session,
      chunk.entryId,
      verifiedOffset,
      partialFile,
      descriptor.chunkSize,
    );
    final raf = await partialFile.open(mode: FileMode.append);
    try {
      await raf.setPosition(chunk.offset);
      await raf.writeFrom(plaintext);
      await raf.flush();
    } finally {
      await raf.close();
    }
    hash.add(plaintext);

    if (chunk.isFinal) {
      final digest = hash.closeHex();
      session.entryHashes.remove(chunk.entryId);
      if (digest != descriptor.sha256) {
        // A corrupted partial fails the entry, not the account: reset the
        // entry so the sender restarts it from offset 0.
        await partialFile.delete();
        await ledger.recordProgress(
          manifest: manifest,
          entryId: chunk.entryId,
          verifiedOffset: 0,
          incrementalSha256: '',
        );
        emitFlowEvent(
          layer: 'FL',
          event: 'ACCOUNT_MIGRATION_BUNDLE_RECEIVER_ENTRY_HASH_MISMATCH',
          details: {
            'sessionId': manifest.sessionId,
            'entryId': chunk.entryId,
            'sizeBytes': descriptor.sizeBytes,
          },
        );
        return await _chunkOutcome(
          session,
          AccountMigrationChunkAcceptCode.decryptFailed,
        );
      }
      await partialFile.rename(
        p.join(session.entriesDirectoryPath, _entryFileName(chunk.entryId)),
      );
      await ledger.markEntryVerified(
        manifest: manifest,
        entryId: chunk.entryId,
        sizeBytes: descriptor.sizeBytes,
        sha256: digest,
      );
    } else {
      await ledger.recordProgress(
        manifest: manifest,
        entryId: chunk.entryId,
        verifiedOffset: chunk.offset + plaintext.length,
        incrementalSha256: '',
      );
    }
    return await _chunkOutcome(
      session,
      AccountMigrationChunkAcceptCode.accepted,
    );
  }

  @override
  Future<MigrationTransferLedgerStatus?> transferStatus({
    required MigrationTransferManifest manifest,
    required AuthenticatedMigrationChannelTranscript transcript,
    required MigrationPendingPairingSession pendingSession,
  }) async {
    final session = _sessions[manifest.sessionId];
    if (session == null || session.manifest.bundleId != manifest.bundleId) {
      return null;
    }
    return session.ledger.status(manifest);
  }

  Future<AccountMigrationChunkAcceptOutcome> _chunkOutcome(
    _BundleReceiveSession session,
    AccountMigrationChunkAcceptCode code,
  ) async {
    final manifest = session.manifest;
    final status = await session.ledger.status(manifest);
    final verifiedEntries = status.verifiedEntryIds.toSet();
    var verifiedChunks = 0;
    for (final entry in manifest.entries) {
      if (entry.sizeBytes == 0) {
        continue;
      }
      if (verifiedEntries.contains(entry.entryId)) {
        verifiedChunks += entry.chunkCount;
      } else {
        verifiedChunks +=
            (status.entryOffsets[entry.entryId] ?? 0) ~/ entry.chunkSize;
      }
    }
    return AccountMigrationChunkAcceptOutcome(
      code: code,
      verifiedChunkCount: verifiedChunks,
      totalChunkCount: manifest.totalChunkCount,
    );
  }

  /// Returns the in-memory incremental hash for an entry, rebuilding it from
  /// the on-disk partial after a receiver restart (the ledger offset tells us
  /// how many bytes are already verified).
  Future<_EntryIncrementalHash> _ensureEntryHash(
    _BundleReceiveSession session,
    String entryId,
    int verifiedOffset,
    File partialFile,
    int chunkSize,
  ) async {
    final existing = session.entryHashes[entryId];
    if (existing != null && existing.hashedBytes == verifiedOffset) {
      return existing;
    }
    final rebuilt = _EntryIncrementalHash();
    if (verifiedOffset > 0 && await partialFile.exists()) {
      final raf = await partialFile.open();
      try {
        var remaining = verifiedOffset;
        while (remaining > 0) {
          final take = remaining < chunkSize ? remaining : chunkSize;
          final block = await raf.read(take);
          if (block.isEmpty) {
            break;
          }
          rebuilt.add(block);
          remaining -= block.length;
        }
      } finally {
        await raf.close();
      }
    }
    session.entryHashes[entryId] = rebuilt;
    return rebuilt;
  }

  @override
  Future<bool> complete({
    required MigrationTransferManifest manifest,
    required AuthenticatedMigrationChannelTranscript transcript,
    required MigrationPendingPairingSession pendingSession,
  }) async {
    final session = _sessions[manifest.sessionId];
    if (session == null || session.manifest.bundleId != manifest.bundleId) {
      return false;
    }

    final stageTracker = _ReceiverStageTracker(
      sessionId: manifest.sessionId,
      stageEvent: 'ACCOUNT_MIGRATION_BUNDLE_RECEIVER_COMPLETE_STAGE',
      failureEvent: 'ACCOUNT_MIGRATION_BUNDLE_RECEIVER_COMPLETE_FAILED',
    );
    try {
      // Every entry was hash-verified chunk-by-chunk on arrival, so complete
      // is a ledger check plus staged-DB validation — never a whole-account
      // re-inflation (the v1 payloadDecode stage no longer exists).
      stageTracker.begin('ledgerCheck');
      final missingEntryCount = await session.ledger.missingEntryCount(
        manifest,
      );
      if (missingEntryCount > 0) {
        emitFlowEvent(
          layer: 'FL',
          event: 'ACCOUNT_MIGRATION_BUNDLE_RECEIVER_COMPLETE_MISSING_ENTRIES',
          details: {
            'sessionId': manifest.sessionId,
            'missingEntryCount': missingEntryCount,
            'entryCount': manifest.entries.length,
          },
        );
        return false;
      }
      stageTracker.done();

      stageTracker.begin('secureStaging');
      final metadata = await _readBundleMetadata(session, manifest);
      final stageableEntries = metadata.secureStorageEntries
          .where((entry) => secureStorageStaging.supportsScope(entry.key.scope))
          .toList(growable: false);
      final droppedSharedEntryCount =
          metadata.secureStorageEntries.length - stageableEntries.length;
      if (droppedSharedEntryCount > 0) {
        emitFlowEvent(
          layer: 'FL',
          event:
              'ACCOUNT_MIGRATION_BUNDLE_RECEIVER_SHARED_SCOPE_ENTRIES_DROPPED',
          details: {
            'sessionId': manifest.sessionId,
            'scope': MigrationSecureStoreScope.iosSharedAccessGroup.name,
            'droppedCount': droppedSharedEntryCount,
          },
        );
      }
      for (final entry in stageableEntries) {
        await secureStorageStaging.stageValue(
          sessionId: manifest.sessionId,
          key: entry.key,
          value: entry.value,
        );
      }
      stageTracker.done();

      stageTracker.begin('stagedDbOpen');
      final databaseEntry = manifest.entries
          .where((entry) => entry.kind == MigrationTransferEntryKind.database)
          .single;
      final stagedDbPath = p.join(
        session.sessionDirectoryPath,
        'identity.staged.db',
      );
      final databaseEntryFile = File(
        p.join(
          session.entriesDirectoryPath,
          _entryFileName(databaseEntry.entryId),
        ),
      );
      if (await databaseEntryFile.exists()) {
        await databaseEntryFile.rename(stagedDbPath);
      } else if (!await File(stagedDbPath).exists()) {
        throw const AccountMigrationBundleImportException(
          'staged database entry is missing',
        );
      }
      final staged = await databaseImportStaging.openVerifiedStagedDatabase(
        sessionId: manifest.sessionId,
        stagedDatabasePath: stagedDbPath,
        manifest: metadata.databaseManifest,
      );
      stageTracker.done();

      stageTracker.begin('importFiles');
      await _finalizeImportedFilesByRename(session, manifest, metadata);
      stageTracker.done();

      stageTracker.begin('authorityRecord');
      session.verifiedImport = _VerifiedBundleImport(
        staged: staged,
        promotionKeys: _promotionKeysForSecureEntries(stageableEntries)
            .where((key) => secureStorageStaging.supportsScope(key.scope))
            .toList(growable: false),
        stagedKeys: stageableEntries
            .map((entry) => entry.key)
            .toList(growable: false),
      );
      await authorityRepository?.saveAuthority(
        AccountMigrationAuthorityRecord(
          state:
              AccountMigrationAuthorityState.migrationVerifiedWaitingForCutover,
          accountPeerId: transcript.oldPhonePeerId,
        ),
      );
      stageTracker.done();
      return true;
    } on Object catch (error) {
      stageTracker.failed(error);
      return false;
    }
  }

  @override
  Future<MigrationCutoverRecord?> acceptOldBlockProof({
    required MigrationTransferManifest manifest,
    required AuthenticatedMigrationChannelTranscript transcript,
    required MigrationPendingPairingSession pendingSession,
    required MigrationCutoverRecord oldBlockProof,
  }) async {
    final importer = activeDatabaseImporter;
    final coordinator = cutoverCoordinator;
    if (importer == null || coordinator == null) {
      return null;
    }
    final session = _sessions[manifest.sessionId];
    final verifiedImport = session?.verifiedImport;
    if (session == null ||
        verifiedImport == null ||
        session.manifest.bundleId != manifest.bundleId) {
      return null;
    }
    if (!_isValidOldBlockProof(
      oldBlockProof,
      sessionId: manifest.sessionId,
      accountPeerId: transcript.oldPhonePeerId,
    )) {
      return null;
    }

    final stageTracker = _ReceiverStageTracker(
      sessionId: manifest.sessionId,
      stageEvent: 'ACCOUNT_MIGRATION_BUNDLE_RECEIVER_OLD_BLOCK_PROOF_STAGE',
      failureEvent: 'ACCOUNT_MIGRATION_BUNDLE_RECEIVER_OLD_BLOCK_PROOF_FAILED',
    );
    try {
      stageTracker.begin('activeDbImport');
      await importer.importVerifiedStagedDatabase(verifiedImport.staged);
      stageTracker.done();
      stageTracker.begin('securePromotion');
      await secureStorageStaging.promote(
        sessionId: manifest.sessionId,
        registryKeys: verifiedImport.promotionKeys,
      );
      stageTracker.done();
      stageTracker.begin('canonicalAccountBinding');
      await publishCanonicalAccountBinding?.call(transcript.oldPhonePeerId);
      stageTracker.done();
      stageTracker.begin('recordOldBlockProof');
      await coordinator.recordOldBlockProofReceived(
        sessionId: manifest.sessionId,
        accountPeerId: transcript.oldPhonePeerId,
        devicePeerId: pendingSession.newPhoneEphemeralPublicKey,
        oldBlockProof: oldBlockProof,
      );
      stageTracker.done();
      stageTracker.begin('commitNewActive');
      final newActiveProof = await coordinator.commitNewActive(
        sessionId: manifest.sessionId,
        accountPeerId: transcript.oldPhonePeerId,
        devicePeerId: pendingSession.newPhoneEphemeralPublicKey,
        importVerified: true,
        oldBlockProof: oldBlockProof,
      );
      stageTracker.done();
      if (!newActiveProof.provesNewActiveCommitted) {
        return null;
      }
      stageTracker.begin('cleanup');
      Object? cleanupError;
      try {
        await _closeVerifiedImport(verifiedImport);
      } on Object catch (error) {
        cleanupError = error;
      }
      final secureStagingCleanupError = await _deleteStagingValuesBestEffort(
        sessionId: manifest.sessionId,
        keys: verifiedImport.stagedKeys,
      );
      final sessionStagingCleanupError = await _deleteSessionStagingBestEffort(
        session,
        manifest,
      );
      cleanupError ??= secureStagingCleanupError;
      cleanupError ??= sessionStagingCleanupError;
      if (cleanupError == null) {
        stageTracker.done();
      } else {
        stageTracker.failed(cleanupError);
      }
      return newActiveProof;
    } on Object catch (error) {
      stageTracker.failed(error);
      return null;
    }
  }

  /// Reads the small metadata entry (secure values + database manifest +
  /// file manifest) staged on disk; this is the only entry complete() parses.
  Future<_AccountMigrationBundleMetadata> _readBundleMetadata(
    _BundleReceiveSession session,
    MigrationTransferManifest manifest,
  ) async {
    final metadataEntries = manifest.entries
        .where((entry) => entry.kind == MigrationTransferEntryKind.secureValues)
        .toList(growable: false);
    if (metadataEntries.length != 1) {
      throw const AccountMigrationBundleImportException(
        'bundle must carry exactly one secure-values metadata entry',
      );
    }
    final file = File(
      p.join(
        session.entriesDirectoryPath,
        _entryFileName(metadataEntries.single.entryId),
      ),
    );
    if (!await file.exists()) {
      throw const AccountMigrationBundleImportException(
        'secure-values metadata entry is missing',
      );
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const AccountMigrationBundleImportException(
        'bundle metadata is malformed',
      );
    }
    final metadata = _AccountMigrationBundleMetadata.fromJson(decoded);
    if (metadata.sessionId != manifest.sessionId) {
      throw const AccountMigrationBundleImportException(
        'bundle session mismatch',
      );
    }
    return metadata;
  }

  /// P2-6: verified entry files move into the documents root via same-volume
  /// rename — no copy, no read-back re-verify (the incremental hash already
  /// proved the bytes against the manifest).
  Future<void> _finalizeImportedFilesByRename(
    _BundleReceiveSession session,
    MigrationTransferManifest manifest,
    _AccountMigrationBundleMetadata metadata,
  ) async {
    if (metadata.fileManifestJson['valid'] == false) {
      throw const AccountMigrationBundleImportException(
        'file manifest has blocking issues',
      );
    }
    final fileEntries = manifest.entries
        .where((entry) => entry.kind == MigrationTransferEntryKind.file)
        .toList(growable: false);
    final manifestItems = _fileManifestItemsByPath(metadata.fileManifestJson);
    emitFlowEvent(
      layer: 'FL',
      event: 'ACCOUNT_MIGRATION_BUNDLE_IMPORT_FILES_START',
      details: {
        'sessionId': manifest.sessionId,
        'manifestItemCount': manifestItems.length,
        'fileEntryCount': fileEntries.length,
        'fileEntryBytes': fileEntries.fold<int>(
          0,
          (sum, entry) => sum + entry.sizeBytes,
        ),
        'fileEntryCountsByKind': _fileManifestItemCountsByKind(
          metadata.fileManifestJson,
        ),
      },
    );

    var writtenCount = 0;
    var bytesWritten = 0;
    final writtenDetails = <Map<String, Object?>>[];
    for (final entry in fileEntries) {
      final relativePath = entry.relativePath;
      if (relativePath == null || relativePath.isEmpty) {
        throw AccountMigrationBundleImportException(
          'file entry is missing a relative path: ${entry.entryId}',
        );
      }
      final manifestItem = manifestItems[relativePath];
      final expectedSha = manifestItem?['sha256'] as String?;
      if (expectedSha == null || expectedSha != entry.sha256) {
        throw AccountMigrationBundleImportException(
          'file entry missing from manifest: $relativePath',
        );
      }
      final source = File(
        p.join(session.entriesDirectoryPath, _entryFileName(entry.entryId)),
      );
      if (!await source.exists()) {
        throw AccountMigrationBundleImportException(
          'verified entry file is missing: ${entry.entryId}',
        );
      }
      final destination = File(_safeJoin(documentsRootPath, relativePath));
      await destination.parent.create(recursive: true);
      await source.rename(destination.path);
      writtenCount += 1;
      bytesWritten += entry.sizeBytes;
      if (writtenDetails.length < _fileManifestIssueDetailLimit) {
        final isCustodyArtifact =
            manifestItem?['kind'] ==
                MigrationFileManifestItemKind.directMediaBlobCustody.name ||
            manifestItem?['kind'] ==
                MigrationFileManifestItemKind.groupMediaBlobCustody.name;
        writtenDetails.add(
          isCustodyArtifact
              ? <String, Object?>{
                  'kind': manifestItem?['kind'],
                  'criticality': manifestItem?['criticality'],
                  'sourceTable': manifestItem?['sourceTable'],
                  'writeVerified': true,
                }
              : <String, Object?>{
                  'relativePath': relativePath,
                  'kind': manifestItem?['kind'],
                  'criticality': manifestItem?['criticality'],
                  'sourceTable': manifestItem?['sourceTable'],
                  'sourceId': manifestItem?['sourceId'],
                  'manifestSizeBytes': manifestItem?['sizeBytes'],
                  'entryBytes': entry.sizeBytes,
                  'sha256Prefix': _sha256Prefix(entry.sha256),
                  'writeVerified': true,
                },
        );
      }
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'ACCOUNT_MIGRATION_BUNDLE_IMPORT_FILES_WRITTEN',
      details: {
        'sessionId': manifest.sessionId,
        'manifestItemCount': manifestItems.length,
        'fileEntryCount': fileEntries.length,
        'writtenCount': writtenCount,
        'bytesWritten': bytesWritten,
        'entries': writtenDetails,
      },
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'ACCOUNT_MIGRATION_BUNDLE_IMPORT_RELAY_FREE_MEDIA_AUDIT',
      details: {
        'sessionId': manifest.sessionId,
        'transport': 'move_bundle',
        'relayMediaDownloadCount': 0,
        'manifestItemCount': manifestItems.length,
        'fileEntryCount': fileEntries.length,
        'writtenCount': writtenCount,
        'bytesWritten': bytesWritten,
        'fileEntryCountsByKind': _fileManifestItemCountsByKind(
          metadata.fileManifestJson,
        ),
        'relayDependencyRisk':
            writtenCount != fileEntries.length ||
            fileEntries.length != manifestItems.length,
      },
    );
  }

  Future<Object?> _deleteStagingValuesBestEffort({
    required String sessionId,
    required Iterable<MigrationSecureStorageKey> keys,
  }) async {
    try {
      await secureStorageStaging.deleteStagingValues(
        sessionId: sessionId,
        registryKeys: keys,
      );
      return null;
    } on Object catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event:
            'ACCOUNT_MIGRATION_BUNDLE_RECEIVER_SECURE_STAGING_CLEANUP_FAILED',
        details: {
          'sessionId': sessionId,
          'errorType': accountMigrationTransferErrorType(error),
        },
      );
      // Staging cleanup must not hide the already durable new-active proof.
      return error;
    }
  }

  /// P2-8: after the cutover proof is durable, the session staging dir
  /// (entry files, staged DB, ledger, manifest copy) is residue — delete it.
  Future<Object?> _deleteSessionStagingBestEffort(
    _BundleReceiveSession session,
    MigrationTransferManifest manifest,
  ) async {
    try {
      await session.ledger.clear(
        sessionId: manifest.sessionId,
        bundleId: manifest.bundleId,
      );
      final dir = Directory(session.sessionDirectoryPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_BUNDLE_RECEIVER_STAGING_CLEANED',
        details: {'sessionId': manifest.sessionId},
      );
      return null;
    } on Object catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_BUNDLE_RECEIVER_STAGING_CLEANUP_FAILED',
        details: {
          'sessionId': manifest.sessionId,
          'errorType': accountMigrationTransferErrorType(error),
        },
      );
      return error;
    }
  }
}

bool _isValidOldBlockProof(
  MigrationCutoverRecord proof, {
  required String sessionId,
  required String accountPeerId,
}) {
  return proof.sessionId == sessionId &&
      proof.accountPeerId == accountPeerId &&
      proof.deviceRole == MigrationCutoverDeviceRole.oldPhone &&
      proof.provesOldNetworkBlocked;
}

List<MigrationSecureStorageKey> _promotionKeysForSecureEntries(
  List<_SecureStorageBundleEntry> secureStorageEntries,
) {
  final keys = <MigrationSecureStorageKey>[];
  for (final entry in secureStorageEntries) {
    if (entry.key.category ==
        MigrationSecureStorageKeyCategory.dbEncryptionKey) {
      continue;
    }
    keys.add(entry.key);
  }
  final secretsMigrated = MigrationSecureStorageRegistry.fixedKey(
    scope: MigrationSecureStoreScope.primary,
    activeKey: MigrationSecureStorageRegistry.secretsMigrated,
  );
  if (secretsMigrated != null) {
    keys.add(secretsMigrated);
  }
  for (final key in MigrationSecureStorageRegistry.fixedKeys) {
    if (key.policy == MigrationSecureStorageKeyPolicy.clearRegenerate) {
      keys.add(key);
    }
  }
  return MigrationSecureStorageRegistry.deduplicateAndSort(keys);
}

Future<void> _closeVerifiedImport(_VerifiedBundleImport verifiedImport) async {
  final database = verifiedImport.staged.database;
  if (database.isOpen) {
    await database.close();
  }
}

/// Small, always-materializable bundle metadata (protocol v2): secure
/// storage values plus the database/file manifests. Travels as the
/// `secure-values` entry; file and database CONTENTS stream separately.
class _AccountMigrationBundleMetadata {
  static const version = 2;

  final String sessionId;
  final MigrationDatabaseManifest databaseManifest;
  final List<_SecureStorageBundleEntry> secureStorageEntries;
  final Map<String, Object?> fileManifestJson;

  const _AccountMigrationBundleMetadata({
    required this.sessionId,
    required this.databaseManifest,
    required this.secureStorageEntries,
    required this.fileManifestJson,
  });

  factory _AccountMigrationBundleMetadata.fromJson(Map<String, dynamic> json) {
    if (json['version'] != version) {
      throw const AccountMigrationBundleImportException(
        'unsupported bundle metadata version',
      );
    }
    final secureEntries = json['secure_storage'];
    final files = json['files'];
    final database = json['database'];
    if (secureEntries is! List || files is! Map || database is! Map) {
      throw const AccountMigrationBundleImportException(
        'bundle metadata is incomplete',
      );
    }
    return _AccountMigrationBundleMetadata(
      sessionId: json['session_id'] as String,
      databaseManifest: _databaseManifestFromJson(
        Map<String, dynamic>.from(database['manifest'] as Map),
      ),
      secureStorageEntries: secureEntries
          .whereType<Map>()
          .map(
            (entry) => _SecureStorageBundleEntry.fromJson(
              Map<String, dynamic>.from(entry),
            ),
          )
          .toList(growable: false),
      fileManifestJson: Map<String, Object?>.from(
        files['manifest'] as Map? ?? const {},
      ),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'version': version,
      'session_id': sessionId,
      'database': {'manifest': databaseManifest.toJson()},
      'secure_storage': secureStorageEntries
          .map((entry) => entry.toJson())
          .toList(growable: false),
      'files': {'manifest': fileManifestJson},
    };
  }
}

class _SecureStorageBundleEntry {
  final MigrationSecureStorageKey key;
  final String value;

  const _SecureStorageBundleEntry({required this.key, required this.value});

  factory _SecureStorageBundleEntry.fromJson(Map<String, dynamic> json) {
    return _SecureStorageBundleEntry(
      key: _secureStorageKeyFromJson(
        Map<String, dynamic>.from(json['key'] as Map),
      ),
      value: utf8.decode(base64Decode(json['value_base64'] as String)),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'key': _secureStorageKeyToJson(key),
      'value_base64': base64Encode(utf8.encode(value)),
    };
  }
}

class _FileBundlePayload {
  final Map<String, Object?> manifestJson;
  final List<_FileEntryRef> entries;
  final List<MigrationFilePathRepair> pathRepairs;

  const _FileBundlePayload({
    required this.manifestJson,
    required this.entries,
    this.pathRepairs = const [],
  });
}

/// Reference to an on-disk file selected for the bundle — size and hash only,
/// never the contents (protocol v2 streams them at send time).
class _FileEntryRef {
  final String entryId;
  final String relativePath;
  final String absolutePath;
  final String sha256;
  final int sizeBytes;

  const _FileEntryRef({
    required this.entryId,
    required this.relativePath,
    required this.absolutePath,
    required this.sha256,
    required this.sizeBytes,
  });
}

/// Tracks the named stage a receiver completion/proof call is executing so
/// the previously silent `on Object` catch paths emit sanitized diagnostics.
class _ReceiverStageTracker {
  final String sessionId;
  final String stageEvent;
  final String failureEvent;
  final Stopwatch _stopwatch = Stopwatch()..start();
  String _stage = 'start';
  int _stageStartMs = 0;

  _ReceiverStageTracker({
    required this.sessionId,
    required this.stageEvent,
    required this.failureEvent,
  });

  void begin(String stage) {
    _stage = stage;
    _stageStartMs = _stopwatch.elapsedMilliseconds;
  }

  void done() {
    emitFlowEvent(
      layer: 'FL',
      event: stageEvent,
      details: {
        'sessionId': sessionId,
        'stage': _stage,
        'elapsedMs': _stopwatch.elapsedMilliseconds - _stageStartMs,
      },
    );
  }

  void failed(Object error) {
    final reason = sanitizeDiagnosticText(error);
    emitFlowEvent(
      layer: 'FL',
      event: failureEvent,
      details: {
        'sessionId': sessionId,
        'stage': _stage,
        'elapsedMs': _stopwatch.elapsedMilliseconds - _stageStartMs,
        'errorType': error.runtimeType.toString(),
        'reason': reason.length > 200 ? reason.substring(0, 200) : reason,
      },
    );
  }
}

class _BundleReceiveSession {
  final MigrationTransferManifest manifest;
  final String sessionDirectoryPath;
  final String entriesDirectoryPath;
  final MigrationTransferLedgerStore ledger;
  final entryHashes = <String, _EntryIncrementalHash>{};
  MigrationStreamDecryptSession? decryptSession;
  _VerifiedBundleImport? verifiedImport;

  _BundleReceiveSession({
    required this.manifest,
    required this.sessionDirectoryPath,
    required this.entriesDirectoryPath,
    required this.ledger,
  });
}

/// SHA-256 of zero bytes — a zero-size entry must declare exactly this hash.
const _emptySha256Hex =
    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

String _entryFileName(String entryId) => Uri.encodeComponent(entryId);

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// Running SHA-256 over an entry's plaintext, advanced one chunk at a time.
class _EntryIncrementalHash {
  final _DigestSink _digestSink = _DigestSink();
  late final ByteConversionSink _input = sha256.startChunkedConversion(
    _digestSink,
  );
  int hashedBytes = 0;

  void add(List<int> bytes) {
    _input.add(bytes);
    hashedBytes += bytes.length;
  }

  String closeHex() {
    _input.close();
    return _digestSink.value!.toString();
  }
}

class _VerifiedBundleImport {
  final MigrationDatabaseImportStagingResult staged;
  final List<MigrationSecureStorageKey> promotionKeys;
  final List<MigrationSecureStorageKey> stagedKeys;

  const _VerifiedBundleImport({
    required this.staged,
    required this.promotionKeys,
    required this.stagedKeys,
  });
}

class _BundleRows {
  final List<Map<String, Object?>> chatMediaRows;
  final List<Map<String, Object?>> directMediaBlobCustodyRows;
  final List<Map<String, Object?>> postMediaRows;
  final List<Map<String, Object?>> postMediaRecoveryRows;
  final List<Map<String, Object?>> contactRows;
  final List<Map<String, Object?>> identityRows;
  final List<Map<String, Object?>> groupRows;
  final List<Map<String, Object?>> groupKeyRows;
  final List<Map<String, Object?>> groupKeyDraftRows;

  const _BundleRows({
    required this.chatMediaRows,
    required this.directMediaBlobCustodyRows,
    required this.postMediaRows,
    required this.postMediaRecoveryRows,
    required this.contactRows,
    required this.identityRows,
    required this.groupRows,
    required this.groupKeyRows,
    required this.groupKeyDraftRows,
  });
}

Future<_BundleRows> _loadBundleRows(Database db) async {
  return _BundleRows(
    chatMediaRows: await _queryChatMediaRows(db),
    directMediaBlobCustodyRows: await _queryTableIfExists(
      db,
      'direct_media_blob_custody',
    ),
    postMediaRows: await _queryTableIfExists(db, 'post_media_attachments'),
    postMediaRecoveryRows: await _queryTableIfExists(
      db,
      'post_media_upload_recovery',
    ),
    contactRows: await _queryTableIfExists(db, 'contacts'),
    identityRows: await _queryTableIfExists(db, 'identity'),
    groupRows: await _queryTableIfExists(db, 'groups'),
    groupKeyRows: await _queryTableIfExists(db, 'group_keys'),
    groupKeyDraftRows: await _queryTableIfExists(
      db,
      'group_key_rotation_drafts',
    ),
  );
}

Future<List<Map<String, Object?>>> _queryChatMediaRows(Database db) async {
  if (!await _tableExists(db, 'media_attachments')) {
    return const [];
  }
  final hasMessages = await _tableExists(db, 'messages');
  final hasGroupMessages = await _tableExists(db, 'group_messages');
  if (!hasMessages && !hasGroupMessages) {
    return db.query('media_attachments');
  }

  final selects = <String>['ma.*'];
  final joins = <String>[];
  if (hasMessages) {
    selects.add('m.contact_peer_id AS migration_contact_peer_id');
    joins.add('LEFT JOIN messages m ON m.id = ma.message_id');
  }
  if (hasGroupMessages) {
    selects.add('gm.group_id AS migration_group_id');
    joins.add('LEFT JOIN group_messages gm ON gm.id = ma.message_id');
  }
  return db.rawQuery(
    'SELECT ${selects.join(', ')} '
    'FROM media_attachments ma '
    '${joins.join(' ')}',
  );
}

Future<List<Map<String, Object?>>> _queryTableIfExists(
  Database db,
  String tableName,
) async {
  if (!await _tableExists(db, tableName)) {
    return const [];
  }
  return db.query(tableName);
}

Future<bool> _tableExists(Database db, String tableName) async {
  final exists = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
    [tableName],
  );
  return exists.isNotEmpty;
}

Map<String, Object?> _secureStorageKeyToJson(MigrationSecureStorageKey key) {
  return {
    'scope': key.scope.name,
    'active_key': key.activeKey,
    'category': key.category.name,
    'policy': key.policy.name,
    'criticality': key.criticality.name,
    'include_in_export_payload': key.includeInExportPayload,
  };
}

MigrationSecureStorageKey _secureStorageKeyFromJson(Map<String, dynamic> json) {
  return MigrationSecureStorageKey(
    scope: _enumByName(MigrationSecureStoreScope.values, json['scope']),
    activeKey: json['active_key'] as String,
    category: _enumByName(
      MigrationSecureStorageKeyCategory.values,
      json['category'],
    ),
    policy: _enumByName(MigrationSecureStorageKeyPolicy.values, json['policy']),
    criticality: _enumByName(
      MigrationSecureStorageKeyCriticality.values,
      json['criticality'],
    ),
    includeInExportPayload: json['include_in_export_payload'] as bool?,
  );
}

T _enumByName<T extends Enum>(List<T> values, Object? name) {
  for (final value in values) {
    if (value.name == name) {
      return value;
    }
  }
  throw AccountMigrationBundleImportException('unknown enum value: $name');
}

MigrationDatabaseManifest _databaseManifestFromJson(Map<String, dynamic> json) {
  final cipher = Map<String, dynamic>.from(json['cipher_metadata'] as Map);
  return MigrationDatabaseManifest(
    protocolVersionValue: json['protocol_version'] as int,
    minimumImporterProtocolVersion:
        json['minimum_importer_protocol_version'] as int,
    sourceAppVersion: json['source_app_version'] as String,
    sourceBuildNumber: json['source_build_number'] as String,
    databaseVersion: json['database_version'] as int,
    schemaHash: json['schema_hash'] as String,
    schemaInventory: MigrationDatabaseSchemaInventory.fromTables({
      for (final entry in Map<String, dynamic>.from(
        json['schema_inventory'] as Map,
      ).entries)
        entry.key: (entry.value as List).whereType<String>().toList(),
    }),
    databaseChecksumSha256: json['database_checksum_sha256'] as String,
    cipherMetadata: MigrationDatabaseCipherMetadata(
      cipherVersion: cipher['cipher_version'] as String,
      kdfIter: cipher['kdf_iter'] as int?,
      cipherPageSize: cipher['cipher_page_size'] as int?,
      policy: _enumByName(
        MigrationDatabaseCipherPolicy.values,
        cipher['policy'],
      ),
    ),
  );
}

String _safeJoin(String root, String relativePath) {
  final normalized = p.posix.normalize(relativePath);
  if (p.posix.isAbsolute(normalized) ||
      normalized == '..' ||
      normalized.startsWith('../')) {
    throw AccountMigrationBundleImportException(
      'unsafe relative path: $relativePath',
    );
  }
  return p.joinAll([root, ...p.posix.split(normalized)]);
}
