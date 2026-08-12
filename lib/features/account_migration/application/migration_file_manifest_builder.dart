import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/media/direct_media_blob_artifact_store.dart'
    show kDirectMediaBlobArtifactRootDirectory;
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_file_manifest.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:path/path.dart' as p;

typedef MigrationSecureValueReader = Future<String?> Function(String key);

class MigrationFileManifestBuilder {
  final String documentsRootPath;
  final MigrationSecureValueReader? secureValueReader;

  const MigrationFileManifestBuilder({
    required this.documentsRootPath,
    this.secureValueReader,
  });

  Future<MigrationFileManifest> build({
    Iterable<Map<String, Object?>> chatMediaRows = const [],
    Iterable<Map<String, Object?>> directMediaBlobCustodyRows = const [],
    Iterable<Map<String, Object?>> postMediaRows = const [],
    Iterable<Map<String, Object?>> postMediaRecoveryRows = const [],
    Iterable<Map<String, Object?>> contactRows = const [],
    Iterable<Map<String, Object?>> identityRows = const [],
    Iterable<Map<String, Object?>> groupRows = const [],
    bool scanDocumentsForCacheAndTransients = true,
  }) async {
    final items = <MigrationFileManifestItem>[];
    final issues = <MigrationFileManifestIssue>[];
    final pathRepairs = <MigrationFilePathRepair>[];
    final includedPaths = <String>{};
    final materializedIdentityRows = identityRows.toList(growable: false);
    final identityScopes = materializedIdentityRows
        .map((row) => _stringValue(row['peer_id']))
        .whereType<String>()
        .where((peerId) => peerId == peerId.trim())
        .map((peerId) => sha256.convert(utf8.encode(peerId)).toString())
        .toSet();

    for (final row in directMediaBlobCustodyRows) {
      await _addDirectMediaBlobCustody(
        items: items,
        issues: issues,
        includedPaths: includedPaths,
        allowedIdentityScopes: identityScopes,
        row: row,
      );
    }

    for (final row in chatMediaRows) {
      await _addChatMedia(items, issues, pathRepairs, includedPaths, row);
    }
    for (final row in postMediaRows) {
      await _addPostMedia(items, issues, includedPaths, row);
    }
    for (final row in postMediaRecoveryRows) {
      await _addPendingPostMedia(items, issues, includedPaths, row);
    }
    for (final row in contactRows) {
      await _addPathBackedItem(
        items: items,
        issues: issues,
        includedPaths: includedPaths,
        row: row,
        storedPathField: 'avatar_path',
        sourceTable: 'contacts',
        sourceId: _stringValue(row['peer_id']) ?? 'unknown-contact',
        kind: MigrationFileManifestItemKind.contactAvatar,
      );
    }
    for (final row in materializedIdentityRows) {
      final explicitAvatarPath = _stringValue(row['avatar_path']);
      final peerId = _stringValue(row['peer_id']) ?? 'identity';
      await _addPathBackedItem(
        items: items,
        issues: issues,
        includedPaths: includedPaths,
        row: {
          ...row,
          'avatar_path':
              explicitAvatarPath ??
              (row['avatar_version'] == null
                  ? null
                  : p.posix.join('media', 'avatars', '$peerId.jpg')),
        },
        storedPathField: 'avatar_path',
        sourceTable: 'identity',
        sourceId: peerId,
        kind: MigrationFileManifestItemKind.identityAvatar,
      );
    }
    for (final row in groupRows) {
      await _addPathBackedItem(
        items: items,
        issues: issues,
        includedPaths: includedPaths,
        row: row,
        storedPathField: 'avatar_path',
        sourceTable: 'groups',
        sourceId: _stringValue(row['id']) ?? 'unknown-group',
        kind: MigrationFileManifestItemKind.groupAvatar,
      );
    }

    if (scanDocumentsForCacheAndTransients) {
      await _scanForCacheAndTransients(items, issues, includedPaths);
    }

    items.sort((a, b) => a.relativePath.compareTo(b.relativePath));
    issues.sort((a, b) {
      final pathCompare = (a.relativePath ?? '').compareTo(
        b.relativePath ?? '',
      );
      if (pathCompare != 0) return pathCompare;
      return a.code.name.compareTo(b.code.name);
    });

    return MigrationFileManifest(
      items: items,
      issues: issues,
      pathRepairs: pathRepairs,
    );
  }

  Future<void> _addDirectMediaBlobCustody({
    required List<MigrationFileManifestItem> items,
    required List<MigrationFileManifestIssue> issues,
    required Set<String> includedPaths,
    required Set<String> allowedIdentityScopes,
    required Map<String, Object?> row,
  }) async {
    final sourceId = _stringValue(row['attachment_id']) ?? 'unknown-custody';
    final rawPath = _stringValue(row['ciphertext_relative_path']);
    final DirectMediaBlobCustodyRow custody;
    try {
      custody = DirectMediaBlobCustodyRow.fromMap(row);
    } on Object {
      _addDirectMediaBlobCustodyIssue(
        issues: issues,
        code: isValidDirectMediaBlobCustodyRelativePath(rawPath)
            ? MigrationFileManifestIssueCode.invalidCustodyArtifact
            : MigrationFileManifestIssueCode.unsupportedAbsolutePath,
        sourceId: sourceId,
        relativePath: rawPath,
        reason: 'invalid_v111_projection',
      );
      return;
    }

    // Incoming rows retain remote ACK authority in the database but do not
    // own a ciphertext artifact. The dynamic database snapshot carries them.
    if (custody.direction == DirectMediaBlobCustodyDirection.incoming) {
      return;
    }

    final relativePath = custody.ciphertextRelativePath!;
    final segments = p.posix.split(relativePath);
    final isOwnedIdentityPath =
        isValidDirectMediaBlobCustodyRelativePath(relativePath) &&
        segments.length >= 3 &&
        segments.first == kDirectMediaBlobArtifactRootDirectory &&
        allowedIdentityScopes.contains(segments[1]) &&
        relativePath.endsWith('.blob');
    if (!isOwnedIdentityPath) {
      _addDirectMediaBlobCustodyIssue(
        issues: issues,
        code: MigrationFileManifestIssueCode.unsupportedAbsolutePath,
        sourceId: sourceId,
        relativePath: relativePath,
        reason: 'unsafe_or_cross_identity_custody_path',
      );
      return;
    }
    if (includedPaths.contains(relativePath)) {
      // 362: v114 sibling target rows deliberately share one canonical
      // encrypted artifact. An exact duplicate (path, hash, size) travels
      // once — every sibling row still arrives in the database snapshot — but
      // a crossed path or proof is corruption and refuses the bundle.
      final exactSharedArtifact = items.any(
        (item) =>
            item.kind == MigrationFileManifestItemKind.directMediaBlobCustody &&
            item.relativePath == relativePath &&
            item.sha256 == custody.contentHash &&
            item.sizeBytes == custody.ciphertextSize,
      );
      if (exactSharedArtifact) {
        return;
      }
      _addDirectMediaBlobCustodyIssue(
        issues: issues,
        code: MigrationFileManifestIssueCode.invalidCustodyArtifact,
        sourceId: sourceId,
        relativePath: relativePath,
        reason: 'crossed_duplicate_custody_proof',
      );
      return;
    }

    final pathState = await _custodyArtifactPathState(relativePath);
    if (pathState != _CustodyArtifactPathState.regularFile) {
      _addDirectMediaBlobCustodyIssue(
        issues: issues,
        code: pathState == _CustodyArtifactPathState.missing
            ? MigrationFileManifestIssueCode.missingRequiredFile
            : MigrationFileManifestIssueCode.unsupportedAbsolutePath,
        sourceId: sourceId,
        relativePath: relativePath,
        reason: pathState == _CustodyArtifactPathState.missing
            ? 'custody_file_missing'
            : 'custody_path_contains_non_directory_or_link',
      );
      return;
    }

    final file = File(_absoluteForRelativePath(relativePath));
    final size = await file.length();
    final digest = (await sha256.bind(file.openRead()).first).toString();
    if (size != custody.ciphertextSize ||
        digest != custody.contentHash ||
        await file.length() != size) {
      _addDirectMediaBlobCustodyIssue(
        issues: issues,
        code: MigrationFileManifestIssueCode.fileSizeMismatch,
        sourceId: sourceId,
        relativePath: relativePath,
        reason: 'custody_file_does_not_match_v111',
      );
      return;
    }

    includedPaths.add(relativePath);
    items.add(
      MigrationFileManifestItem(
        kind: MigrationFileManifestItemKind.directMediaBlobCustody,
        criticality: MigrationFileCriticality.critical,
        relativePath: relativePath,
        sizeBytes: custody.ciphertextSize,
        sha256: custody.contentHash,
        sourceTable: 'direct_media_blob_custody',
        sourceId: custody.attachmentId,
      ),
    );
  }

  void _addDirectMediaBlobCustodyIssue({
    required List<MigrationFileManifestIssue> issues,
    required MigrationFileManifestIssueCode code,
    required String sourceId,
    required String? relativePath,
    required String reason,
  }) {
    issues.add(
      MigrationFileManifestIssue(
        code: code,
        sourceTable: 'direct_media_blob_custody',
        sourceId: sourceId,
        relativePath: relativePath,
        criticality: MigrationFileCriticality.critical,
        diagnostics: <String, Object?>{'reason': reason},
      ),
    );
  }

  Future<_CustodyArtifactPathState> _custodyArtifactPathState(
    String relativePath,
  ) async {
    final root = p.normalize(p.absolute(documentsRootPath));
    final segments = p.posix.split(relativePath);
    final absolutePath = p.normalize(p.joinAll(<String>[root, ...segments]));
    if (!p.isWithin(root, absolutePath)) {
      return _CustodyArtifactPathState.unsafe;
    }

    var current = root;
    for (final segment in segments.take(segments.length - 1)) {
      current = p.join(current, segment);
      final type = await FileSystemEntity.type(current, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        return _CustodyArtifactPathState.missing;
      }
      if (type != FileSystemEntityType.directory) {
        return _CustodyArtifactPathState.unsafe;
      }
    }
    final type = await FileSystemEntity.type(absolutePath, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      return _CustodyArtifactPathState.missing;
    }
    return type == FileSystemEntityType.file
        ? _CustodyArtifactPathState.regularFile
        : _CustodyArtifactPathState.unsafe;
  }

  Future<void> _addChatMedia(
    List<MigrationFileManifestItem> items,
    List<MigrationFileManifestIssue> issues,
    List<MigrationFilePathRepair> pathRepairs,
    Set<String> includedPaths,
    Map<String, Object?> row,
  ) async {
    final sourceId = _stringValue(row['id']) ?? 'unknown-media';
    final status = _stringValue(row['download_status']) ?? '';
    final kind = status == 'upload_pending'
        ? MigrationFileManifestItemKind.pendingUpload
        : MigrationFileManifestItemKind.chatMedia;
    if (!_requiresLocalChatMediaFile(status)) {
      return;
    }
    final expectedSize = _intValue(row['size']);
    final storedPath = _stringValue(row['local_path']);
    final candidates = _chatMediaPathCandidates(row, status);
    final failures = <_PathCandidateFailure>[];

    for (final candidate in candidates) {
      final failure = await _addPathCandidateIfUsable(
        items: items,
        includedPaths: includedPaths,
        pathRepairs: pathRepairs,
        candidate: candidate,
        sourceTable: 'media_attachments',
        sourceId: sourceId,
        kind: kind,
        expectedSize: expectedSize,
        storedPath: storedPath,
        issues: issues,
      );
      if (failure == null) {
        await _validateChatMediaEncryption(issues, row, sourceId);
        return;
      }
      failures.add(failure);
    }

    _addBestPathFailureIssue(
      issues: issues,
      failures: failures,
      row: row,
      sourceTable: 'media_attachments',
      sourceId: sourceId,
      fallbackRelativePath: _fallbackChatMediaIssuePath(row, storedPath),
    );

    await _validateChatMediaEncryption(issues, row, sourceId);
  }

  Future<_PathCandidateFailure?> _addPathCandidateIfUsable({
    required List<MigrationFileManifestItem> items,
    required Set<String> includedPaths,
    required List<MigrationFilePathRepair> pathRepairs,
    required _PathCandidate candidate,
    required String sourceTable,
    required String sourceId,
    required MigrationFileManifestItemKind kind,
    required int? expectedSize,
    required String? storedPath,
    List<MigrationFileManifestIssue>? issues,
  }) async {
    final exportRelativePath =
        candidate.materializeRelativePath ?? candidate.relativePath;
    final baseDiagnostics = <String, Object?>{
      'candidateRelativePath': candidate.relativePath,
      'candidateRelativePathKind': _pathKind(candidate.relativePath),
      'exportRelativePath': exportRelativePath,
      'repairReason': candidate.repairReason,
      'allowTransient': candidate.allowTransient,
      'checkExpectedSize': candidate.checkExpectedSize,
      'repairStoredPath': candidate.repairStoredPath,
      if (candidate.issuePath != null) 'issuePath': candidate.issuePath,
      if (candidate.materializeRelativePath != null)
        'materializeRelativePath': candidate.materializeRelativePath,
    };
    if (candidate.unsupportedStoredPath) {
      return _PathCandidateFailure(
        code: MigrationFileManifestIssueCode.unsupportedAbsolutePath,
        relativePath: candidate.issuePath ?? exportRelativePath,
        diagnostics: {...baseDiagnostics, 'reason': 'unsupported_stored_path'},
      );
    }
    if (!candidate.allowTransient && _isTransientPath(exportRelativePath)) {
      return _PathCandidateFailure(
        code: MigrationFileManifestIssueCode.transientFile,
        relativePath: exportRelativePath,
        blocking: true,
        diagnostics: {...baseDiagnostics, 'reason': 'transient_file'},
      );
    }

    final sourceFile = File(_absoluteForRelativePath(candidate.relativePath));
    if (!await sourceFile.exists()) {
      return _PathCandidateFailure(
        code: candidate.unsupportedStoredPath
            ? MigrationFileManifestIssueCode.unsupportedAbsolutePath
            : MigrationFileManifestIssueCode.missingRequiredFile,
        relativePath: candidate.issuePath ?? exportRelativePath,
        diagnostics: {
          ...baseDiagnostics,
          'reason': 'source_file_missing',
          'absolutePath': sourceFile.path,
          'absolutePathKind': _pathKind(sourceFile.path),
          'fileExists': false,
          'expectedSizeBytes': ?expectedSize,
        },
      );
    }

    final sourceSize = await sourceFile.length();
    if (candidate.checkExpectedSize &&
        expectedSize != null &&
        expectedSize > 0 &&
        expectedSize != sourceSize) {
      if (!candidate.acceptSizeDivergence) {
        return _PathCandidateFailure(
          code: MigrationFileManifestIssueCode.fileSizeMismatch,
          relativePath: exportRelativePath,
          diagnostics: {
            ...baseDiagnostics,
            'reason': 'file_size_mismatch',
            'absolutePath': sourceFile.path,
            'absolutePathKind': _pathKind(sourceFile.path),
            'fileExists': true,
            'fileBytes': sourceSize,
            'expectedSizeBytes': expectedSize,
          },
        );
      }
      // The row's own stored file is authoritative for migration — the
      // `size` column is sender-declared metadata that legitimately
      // diverges for LAN-received media. Bundle the bytes the app actually
      // uses and keep the divergence observable as a non-blocking issue.
      issues?.add(
        MigrationFileManifestIssue(
          code: MigrationFileManifestIssueCode.fileSizeMismatch,
          sourceTable: sourceTable,
          sourceId: sourceId,
          relativePath: exportRelativePath,
          blocking: false,
          criticality: _criticalityForIssuePath(exportRelativePath),
          diagnostics: {
            ...baseDiagnostics,
            'reason': 'stored_file_size_divergence_accepted',
            'absolutePath': sourceFile.path,
            'absolutePathKind': _pathKind(sourceFile.path),
            'fileExists': true,
            'fileBytes': sourceSize,
            'expectedSizeBytes': expectedSize,
          },
        ),
      );
    }

    File exportFile = sourceFile;
    if (exportRelativePath != candidate.relativePath) {
      final targetFile = File(_absoluteForRelativePath(exportRelativePath));
      await targetFile.parent.create(recursive: true);
      await sourceFile.copy(targetFile.path);
      exportFile = targetFile;
    }

    final size = await exportFile.length();
    if (includedPaths.add(exportRelativePath)) {
      final digest = await sha256.bind(exportFile.openRead()).first;
      items.add(
        MigrationFileManifestItem(
          kind: kind,
          criticality: _criticalityForPath(exportRelativePath),
          relativePath: exportRelativePath,
          sizeBytes: size,
          sha256: digest.toString(),
          sourceTable: sourceTable,
          sourceId: sourceId,
          metadata: {
            'selected_candidate_path': candidate.relativePath,
            'selected_candidate_reason': candidate.repairReason,
            'selected_candidate_path_kind': _pathKind(candidate.relativePath),
            if (candidate.materializeRelativePath != null)
              'materialized_from': candidate.relativePath,
            if (storedPath != null) 'stored_path_kind': _pathKind(storedPath),
          },
        ),
      );
    }

    if (candidate.repairStoredPath &&
        _requiresPathRepair(storedPath, exportRelativePath)) {
      pathRepairs.add(
        MigrationFilePathRepair(
          sourceTable: sourceTable,
          sourceId: sourceId,
          oldPath: storedPath,
          relativePath: exportRelativePath,
          reason: candidate.repairReason,
        ),
      );
    }
    return null;
  }

  void _addBestPathFailureIssue({
    required List<MigrationFileManifestIssue> issues,
    required List<_PathCandidateFailure> failures,
    required Map<String, Object?> row,
    required String sourceTable,
    required String sourceId,
    required String? fallbackRelativePath,
  }) {
    final failure =
        _firstFailureWithCode(
          failures,
          MigrationFileManifestIssueCode.fileSizeMismatch,
        ) ??
        _firstFailureWithCode(
          failures,
          MigrationFileManifestIssueCode.missingRequiredFile,
        ) ??
        _firstFailureWithCode(
          failures,
          MigrationFileManifestIssueCode.unsupportedAbsolutePath,
        ) ??
        (failures.isEmpty ? null : failures.first);
    issues.add(
      MigrationFileManifestIssue(
        code:
            failure?.code ?? MigrationFileManifestIssueCode.missingRequiredFile,
        sourceTable: sourceTable,
        sourceId: sourceId,
        relativePath: failure?.relativePath ?? fallbackRelativePath,
        blocking: failure?.blocking ?? true,
        criticality: _criticalityForIssuePath(
          failure?.relativePath ?? fallbackRelativePath,
        ),
        diagnostics: _chatMediaIssueDiagnostics(
          row: row,
          selectedFailure: failure,
          failures: failures,
        ),
      ),
    );
  }

  Map<String, Object?> _chatMediaIssueDiagnostics({
    required Map<String, Object?> row,
    required _PathCandidateFailure? selectedFailure,
    required List<_PathCandidateFailure> failures,
  }) {
    final storedPath = _stringValue(row['local_path']);
    final diagnostics = <String, Object?>{
      'messageId': _stringValue(row['message_id']),
      'downloadStatus': _stringValue(row['download_status']) ?? '',
      'mime': _stringValue(row['mime']),
      'mediaType': _stringValue(row['media_type']),
      'sizeBytes': _intValue(row['size']),
      'storedPath': storedPath,
      'storedPathKind': _pathKind(storedPath),
      'migrationGroupId': _stringValue(row['migration_group_id']),
      'migrationContactPeerId': _stringValue(row['migration_contact_peer_id']),
      'hasContentHash': _stringValue(row['content_hash']) != null,
      'hasCryptoMaterial': _stringValue(row['encryption_key_base64']) != null,
      'hasCryptoIv': _stringValue(row['encryption_nonce']) != null,
      'encryptionScheme': _stringValue(row['encryption_scheme']),
      'hasCompleteEncryptionMetadata': _hasCompleteChatMediaEncryptionMetadata(
        row,
      ),
      'candidateCount': failures.length,
      'candidateDiagnostics': failures
          .map((failure) => failure.diagnostics)
          .toList(growable: false),
    };
    if (selectedFailure != null) {
      diagnostics['selectedReason'] = selectedFailure.diagnostics['reason'];
      diagnostics['selectedCandidateRelativePath'] =
          selectedFailure.diagnostics['candidateRelativePath'];
    }
    diagnostics.removeWhere((_, value) => value == null);
    return diagnostics;
  }

  _PathCandidateFailure? _firstFailureWithCode(
    List<_PathCandidateFailure> failures,
    MigrationFileManifestIssueCode code,
  ) {
    for (final failure in failures) {
      if (failure.code == code) {
        return failure;
      }
    }
    return null;
  }

  bool _requiresLocalChatMediaFile(String status) {
    return status.isEmpty || status == 'done' || status == 'upload_pending';
  }

  List<_PathCandidate> _chatMediaPathCandidates(
    Map<String, Object?> row,
    String status,
  ) {
    final candidates = <_PathCandidate>[];
    final seen = <String>{};
    final storedPath = _stringValue(row['local_path']);
    final sourceId = _stringValue(row['id']);
    final mime = _stringValue(row['mime']);
    final messageId = _stringValue(row['message_id']);

    void addCandidate(
      String relativePath, {
      required String repairReason,
      String? issuePath,
      bool unsupportedStoredPath = false,
      String? materializeRelativePath,
      bool allowTransient = false,
      bool checkExpectedSize = true,
      bool repairStoredPath = true,
      bool acceptSizeDivergence = false,
    }) {
      final normalized = _normalizeRelative(relativePath);
      if (!seen.add(normalized)) {
        return;
      }
      candidates.add(
        _PathCandidate(
          relativePath: normalized,
          repairReason: repairReason,
          issuePath: issuePath,
          unsupportedStoredPath: unsupportedStoredPath,
          materializeRelativePath: materializeRelativePath == null
              ? null
              : _normalizeRelative(materializeRelativePath),
          allowTransient: allowTransient,
          checkExpectedSize: checkExpectedSize,
          repairStoredPath: repairStoredPath,
          acceptSizeDivergence: acceptSizeDivergence,
        ),
      );
    }

    if (storedPath != null) {
      final classified = _classifyStoredPath(storedPath);
      if (classified != null) {
        final canonicalLocalMediaPath = _isLocalMediaRelativePath(classified)
            ? _canonicalChatMediaRelativePath(row, status)
            : null;
        addCandidate(
          classified,
          repairReason: canonicalLocalMediaPath == null
              ? 'normalize_stored_path'
              : 'canonicalize_local_media_path',
          issuePath: canonicalLocalMediaPath,
          materializeRelativePath: canonicalLocalMediaPath,
          acceptSizeDivergence: true,
        );
      }
    }

    if (status == 'upload_pending' &&
        sourceId != null &&
        messageId != null &&
        mime != null) {
      addCandidate(
        MediaFilePathConvention.relativePathForPendingUpload(
          messageId: messageId,
          attachmentId: sourceId,
          mime: mime,
        ),
        repairReason: 'canonical_pending_upload_path',
      );
    }

    if (status != 'upload_pending' && sourceId != null && mime != null) {
      String? canonicalRelativePath;
      final groupId = _stringValue(row['migration_group_id']);
      if (groupId != null) {
        canonicalRelativePath =
            MediaFilePathConvention.relativePathForAttachment(
              contactPeerId: groupId,
              blobId: sourceId,
              mime: mime,
            );
        addCandidate(
          canonicalRelativePath,
          repairReason: 'canonical_group_media_path',
        );
      }

      final contactPeerId = _stringValue(row['migration_contact_peer_id']);
      if (contactPeerId != null) {
        canonicalRelativePath ??=
            MediaFilePathConvention.relativePathForAttachment(
              contactPeerId: contactPeerId,
              blobId: sourceId,
              mime: mime,
            );
        addCandidate(
          canonicalRelativePath,
          repairReason: 'canonical_one_to_one_media_path',
        );
      }

      if (status == 'done' &&
          canonicalRelativePath != null &&
          messageId != null) {
        addCandidate(
          MediaFilePathConvention.relativePathForPendingUpload(
            messageId: messageId,
            attachmentId: sourceId,
            mime: mime,
          ),
          repairReason: 'recover_completed_media_from_pending_upload',
          issuePath: canonicalRelativePath,
          materializeRelativePath: canonicalRelativePath,
        );
      }

      if (status == 'done' &&
          groupId != null &&
          canonicalRelativePath != null &&
          _hasCompleteChatMediaEncryptionMetadata(row)) {
        addCandidate(
          '$canonicalRelativePath.enc',
          repairReason: 'migrate_encrypted_group_media_companion',
          issuePath: canonicalRelativePath,
          allowTransient: true,
          checkExpectedSize: false,
          repairStoredPath: false,
        );
      }
    }

    if (storedPath != null && _classifyStoredPath(storedPath) == null) {
      candidates.add(
        _PathCandidate(
          relativePath: storedPath,
          repairReason: 'unsupported_stored_path',
          issuePath: storedPath,
          unsupportedStoredPath: true,
        ),
      );
    }

    return candidates;
  }

  bool _hasCompleteChatMediaEncryptionMetadata(Map<String, Object?> row) {
    final key = _stringValue(row['encryption_key_base64']);
    final nonce = _stringValue(row['encryption_nonce']);
    final scheme = _stringValue(row['encryption_scheme']);
    final contentHash = _stringValue(row['content_hash']);
    return key != null &&
        key.isNotEmpty &&
        nonce != null &&
        nonce.isNotEmpty &&
        scheme == kMediaAttachmentEncryptionSchemeBlobAesGcmV1 &&
        contentHash != null &&
        contentHash.isNotEmpty;
  }

  String? _fallbackChatMediaIssuePath(
    Map<String, Object?> row,
    String? storedPath,
  ) {
    if (storedPath != null) {
      return storedPath;
    }
    final sourceId = _stringValue(row['id']);
    final mime = _stringValue(row['mime']);
    final groupId = _stringValue(row['migration_group_id']);
    if (sourceId != null && mime != null && groupId != null) {
      return MediaFilePathConvention.relativePathForAttachment(
        contactPeerId: groupId,
        blobId: sourceId,
        mime: mime,
      );
    }
    final contactPeerId = _stringValue(row['migration_contact_peer_id']);
    if (sourceId != null && mime != null && contactPeerId != null) {
      return MediaFilePathConvention.relativePathForAttachment(
        contactPeerId: contactPeerId,
        blobId: sourceId,
        mime: mime,
      );
    }
    return null;
  }

  String? _canonicalChatMediaRelativePath(
    Map<String, Object?> row,
    String status,
  ) {
    if (status == 'upload_pending') {
      return null;
    }
    final sourceId = _stringValue(row['id']);
    final mime = _stringValue(row['mime']);
    if (sourceId == null || mime == null) {
      return null;
    }
    final groupId = _stringValue(row['migration_group_id']);
    if (groupId != null) {
      return MediaFilePathConvention.relativePathForAttachment(
        contactPeerId: groupId,
        blobId: sourceId,
        mime: mime,
      );
    }
    final contactPeerId = _stringValue(row['migration_contact_peer_id']);
    if (contactPeerId != null) {
      return MediaFilePathConvention.relativePathForAttachment(
        contactPeerId: contactPeerId,
        blobId: sourceId,
        mime: mime,
      );
    }
    return null;
  }

  bool _requiresPathRepair(String? storedPath, String relativePath) {
    if (storedPath == null || storedPath.isEmpty) {
      return true;
    }
    final classified = _classifyStoredPath(storedPath);
    return classified != relativePath || p.isAbsolute(storedPath);
  }

  Future<void> _addPostMedia(
    List<MigrationFileManifestItem> items,
    List<MigrationFileManifestIssue> issues,
    Set<String> includedPaths,
    Map<String, Object?> row,
  ) async {
    final sourceId = _stringValue(row['media_id']) ?? 'unknown-post-media';
    await _addPathBackedItem(
      items: items,
      issues: issues,
      includedPaths: includedPaths,
      row: row,
      storedPathField: 'local_path',
      sourceTable: 'post_media_attachments',
      sourceId: sourceId,
      kind: MigrationFileManifestItemKind.postMedia,
      expectedSize: _intValue(row['size_bytes']),
    );
    _validatePostMediaCrypto(issues, row, sourceId);
  }

  Future<void> _addPendingPostMedia(
    List<MigrationFileManifestItem> items,
    List<MigrationFileManifestIssue> issues,
    Set<String> includedPaths,
    Map<String, Object?> row,
  ) {
    return _addPathBackedItem(
      items: items,
      issues: issues,
      includedPaths: includedPaths,
      row: row,
      storedPathField: 'local_file_path',
      sourceTable: 'post_media_upload_recovery',
      sourceId: _stringValue(row['post_id']) ?? 'unknown-post',
      kind: MigrationFileManifestItemKind.pendingUpload,
    );
  }

  Future<void> _addPathBackedItem({
    required List<MigrationFileManifestItem> items,
    required List<MigrationFileManifestIssue> issues,
    required Set<String> includedPaths,
    required Map<String, Object?> row,
    required String storedPathField,
    required String sourceTable,
    required String sourceId,
    required MigrationFileManifestItemKind kind,
    int? expectedSize,
  }) async {
    final storedPath = _stringValue(row[storedPathField]);
    if (storedPath == null || storedPath.isEmpty) {
      return;
    }
    final classifiedPath = _classifyStoredPath(storedPath);
    if (classifiedPath == null) {
      issues.add(
        MigrationFileManifestIssue(
          code: MigrationFileManifestIssueCode.unsupportedAbsolutePath,
          sourceTable: sourceTable,
          sourceId: sourceId,
          relativePath: storedPath,
          criticality: _criticalityForIssuePath(storedPath),
        ),
      );
      return;
    }
    if (_isTransientPath(classifiedPath)) {
      issues.add(
        MigrationFileManifestIssue(
          code: MigrationFileManifestIssueCode.transientFile,
          sourceTable: sourceTable,
          sourceId: sourceId,
          relativePath: classifiedPath,
          blocking: false,
          criticality: _criticalityForIssuePath(classifiedPath),
        ),
      );
      return;
    }

    final file = File(_absoluteForRelativePath(classifiedPath));
    if (!await file.exists()) {
      issues.add(
        MigrationFileManifestIssue(
          code: MigrationFileManifestIssueCode.missingRequiredFile,
          sourceTable: sourceTable,
          sourceId: sourceId,
          relativePath: classifiedPath,
          criticality: _criticalityForIssuePath(classifiedPath),
        ),
      );
      return;
    }
    final size = await file.length();
    if (expectedSize != null && expectedSize > 0 && expectedSize != size) {
      // The row's own stored file is authoritative for migration: it gets
      // bundled with its real on-disk size and sha, so a stale size column
      // stays observable but must never block the move.
      issues.add(
        MigrationFileManifestIssue(
          code: MigrationFileManifestIssueCode.fileSizeMismatch,
          sourceTable: sourceTable,
          sourceId: sourceId,
          relativePath: classifiedPath,
          blocking: false,
          criticality: _criticalityForIssuePath(classifiedPath),
          diagnostics: {
            'reason': 'stored_file_size_divergence_accepted',
            'fileExists': true,
            'fileBytes': size,
            'expectedSizeBytes': expectedSize,
          },
        ),
      );
    }
    if (!includedPaths.add(classifiedPath)) {
      return;
    }

    final digest = await sha256.bind(file.openRead()).first;
    items.add(
      MigrationFileManifestItem(
        kind: kind,
        criticality: _criticalityForPath(classifiedPath),
        relativePath: classifiedPath,
        sizeBytes: size,
        sha256: digest.toString(),
        sourceTable: sourceTable,
        sourceId: sourceId,
      ),
    );
  }

  Future<void> _validateChatMediaEncryption(
    List<MigrationFileManifestIssue> issues,
    Map<String, Object?> row,
    String sourceId,
  ) async {
    final key = _stringValue(row['encryption_key_base64']);
    final nonce = _stringValue(row['encryption_nonce']);
    final scheme = _stringValue(row['encryption_scheme']);
    final contentHash = _stringValue(row['content_hash']);
    final hasAnyEncryptionMetadata =
        key != null || nonce != null || scheme != null || contentHash != null;
    if (!hasAnyEncryptionMetadata) {
      return;
    }
    if (key == null ||
        key.isEmpty ||
        nonce == null ||
        nonce.isEmpty ||
        scheme != kMediaAttachmentEncryptionSchemeBlobAesGcmV1 ||
        contentHash == null ||
        contentHash.isEmpty) {
      issues.add(
        MigrationFileManifestIssue(
          code: MigrationFileManifestIssueCode.missingChatMediaMetadata,
          sourceTable: 'media_attachments',
          sourceId: sourceId,
          relativePath: _stringValue(row['local_path']),
          criticality: _criticalityForIssuePath(
            _stringValue(row['local_path']),
          ),
        ),
      );
    }
    if (isSecureStoreReference(key)) {
      final reader = secureValueReader;
      final resolved = reader == null
          ? null
          : await reader(secureStoreKeyFromReference(key!));
      if (resolved == null || resolved.isEmpty) {
        issues.add(
          MigrationFileManifestIssue(
            code: MigrationFileManifestIssueCode.missingSecureStoreKey,
            sourceTable: 'media_attachments',
            sourceId: sourceId,
            relativePath: _stringValue(row['local_path']),
            criticality: _criticalityForIssuePath(
              _stringValue(row['local_path']),
            ),
          ),
        );
      }
    }
  }

  void _validatePostMediaCrypto(
    List<MigrationFileManifestIssue> issues,
    Map<String, Object?> row,
    String sourceId,
  ) {
    final isEncrypted = _boolish(row['is_encrypted']);
    if (!isEncrypted) {
      return;
    }
    final key = _stringValue(row['encryption_key_base64']);
    final nonce = _stringValue(row['encryption_nonce']);
    if (key == null || key.isEmpty || nonce == null || nonce.isEmpty) {
      issues.add(
        MigrationFileManifestIssue(
          code: MigrationFileManifestIssueCode.missingPostMediaCrypto,
          sourceTable: 'post_media_attachments',
          sourceId: sourceId,
          relativePath: _stringValue(row['local_path']),
          criticality: _criticalityForIssuePath(
            _stringValue(row['local_path']),
          ),
        ),
      );
    }
  }

  Future<void> _scanForCacheAndTransients(
    List<MigrationFileManifestItem> items,
    List<MigrationFileManifestIssue> issues,
    Set<String> includedPaths,
  ) async {
    final root = Directory(documentsRootPath);
    if (!await root.exists()) {
      return;
    }
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final relativePath = _normalizeRelative(
        p.relative(entity.path, from: documentsRootPath),
      );
      if (!_isAppOwnedRelativePath(relativePath)) {
        continue;
      }
      if (includedPaths.contains(relativePath)) {
        continue;
      }
      if (_isTransientPath(relativePath)) {
        issues.add(
          MigrationFileManifestIssue(
            code: MigrationFileManifestIssueCode.transientFile,
            sourceTable: 'documents',
            sourceId: relativePath,
            relativePath: relativePath,
            blocking: false,
            criticality: _criticalityForIssuePath(relativePath),
          ),
        );
        continue;
      }
      if (!_isVideoThumbnailPath(relativePath) ||
          !includedPaths.add(relativePath)) {
        continue;
      }
      final size = await entity.length();
      final digest = await sha256.bind(entity.openRead()).first;
      items.add(
        MigrationFileManifestItem(
          kind: MigrationFileManifestItemKind.videoThumbnail,
          criticality: MigrationFileCriticality.nonCriticalCache,
          relativePath: relativePath,
          sizeBytes: size,
          sha256: digest.toString(),
          sourceTable: 'documents',
          sourceId: relativePath,
        ),
      );
    }
  }

  String? _classifyStoredPath(String storedPath) {
    final normalized = _normalizeRelative(storedPath);
    if (_isAppOwnedRelativePath(normalized)) {
      return normalized;
    }
    if (p.isAbsolute(storedPath)) {
      final relativeToCurrentRoot = _relativeIfUnderDocumentsRoot(storedPath);
      if (relativeToCurrentRoot != null) {
        return relativeToCurrentRoot;
      }
      for (final marker in const [
        '/media/',
        '/local_media/',
        '/post_media/',
        '/pending_uploads/',
      ]) {
        final index = normalized.indexOf(marker);
        if (index == -1) {
          continue;
        }
        final relative = normalized.substring(index + 1);
        if (_isAppOwnedRelativePath(relative)) {
          return relative;
        }
      }
    }
    return null;
  }

  String? _relativeIfUnderDocumentsRoot(String path) {
    final absoluteRoot = p.normalize(p.absolute(documentsRootPath));
    final absolutePath = p.normalize(p.absolute(path));
    if (!p.isWithin(absoluteRoot, absolutePath) &&
        absolutePath != absoluteRoot) {
      return null;
    }
    return _normalizeRelative(p.relative(absolutePath, from: absoluteRoot));
  }

  String _absoluteForRelativePath(String relativePath) {
    return p.join(documentsRootPath, relativePath);
  }

  bool _isAppOwnedRelativePath(String path) {
    return path.startsWith('media/') ||
        path.startsWith('local_media/') ||
        path.startsWith('post_media/') ||
        path.startsWith('pending_uploads/');
  }

  bool _isLocalMediaRelativePath(String path) {
    return path.startsWith('local_media/');
  }

  bool _isTransientPath(String path) {
    return path.endsWith('.enc') ||
        path.endsWith('.download.jpg') ||
        RegExp(r'\.raw\.[^/]+\.jpg$').hasMatch(path);
  }

  bool _isVideoThumbnailPath(String path) => path.endsWith('.thumb.jpg');

  MigrationFileCriticality _criticalityForPath(String relativePath) {
    return _isVideoThumbnailPath(relativePath)
        ? MigrationFileCriticality.nonCriticalCache
        : MigrationFileCriticality.critical;
  }

  MigrationFileCriticality _criticalityForIssuePath(String? relativePath) {
    if (relativePath == null || relativePath.isEmpty) {
      return MigrationFileCriticality.critical;
    }
    return _criticalityForPath(relativePath);
  }

  String _normalizeRelative(String path) {
    return path.replaceAll('\\', '/').replaceFirst(RegExp(r'^/+'), '');
  }

  String _pathKind(String? path) {
    if (path == null || path.isEmpty) {
      return 'empty';
    }
    if (p.isAbsolute(path) || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path)) {
      return 'absolute';
    }
    return 'relative';
  }

  String? _stringValue(Object? value) {
    if (value is String && value.isNotEmpty) {
      return value;
    }
    return null;
  }

  int? _intValue(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return null;
  }

  bool _boolish(Object? value) {
    return value == true || value == 1 || value == '1' || value == 'true';
  }
}

enum _CustodyArtifactPathState { regularFile, missing, unsafe }

class _PathCandidate {
  final String relativePath;
  final String repairReason;
  final String? issuePath;
  final bool unsupportedStoredPath;
  final String? materializeRelativePath;
  final bool allowTransient;
  final bool checkExpectedSize;
  final bool repairStoredPath;

  /// True for the row's OWN stored path: that file is what the app already
  /// displays, so a divergent `size` column (sender-declared metadata on
  /// LAN-received media) downgrades to a non-blocking diagnostic instead of
  /// blocking the move. Guess candidates keep the hard size check — there a
  /// mismatch means "possibly the wrong file".
  final bool acceptSizeDivergence;

  const _PathCandidate({
    required this.relativePath,
    required this.repairReason,
    this.issuePath,
    this.unsupportedStoredPath = false,
    this.materializeRelativePath,
    this.allowTransient = false,
    this.checkExpectedSize = true,
    this.repairStoredPath = true,
    this.acceptSizeDivergence = false,
  });
}

class _PathCandidateFailure {
  final MigrationFileManifestIssueCode code;
  final String? relativePath;
  final bool blocking;
  final Map<String, Object?> diagnostics;

  const _PathCandidateFailure({
    required this.code,
    this.relativePath,
    this.blocking = true,
    this.diagnostics = const {},
  });
}
