import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:flutter_app/core/media/app_owned_media_delete_telemetry.dart';
import 'package:flutter_app/core/media/media_attachment_lifecycle_lock.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/media_library.dart';
import 'package:flutter_app/features/conversation/domain/models/media_storage.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';

/// 229: filesystem seam for [MediaStorageManager] so eviction tests can
/// inject stat/delete/resolve faults independently of the DB callbacks.
abstract class MediaStorageFileGateway {
  /// True when a filesystem entity exists at [absolutePath].
  Future<bool> exists(String absolutePath);

  /// The on-disk length of the file, or null when it does not exist or
  /// cannot be statted.
  Future<int?> lengthOrNull(String absolutePath);

  /// Fully resolves every symlink component of [absolutePath] to the real
  /// target, or null when the path does not exist / cannot be resolved.
  Future<String?> resolveRealPathOrNull(String absolutePath);

  /// Deletes the exact file. A missing file is success (idempotent);
  /// implementations throw on genuine I/O failure.
  Future<void> delete(String absolutePath, {required String reason});
}

/// Production gateway: `dart:io` + the shared app-owned delete telemetry.
class IoMediaStorageFileGateway implements MediaStorageFileGateway {
  const IoMediaStorageFileGateway();

  @override
  Future<bool> exists(String absolutePath) => File(absolutePath).exists();

  @override
  Future<int?> lengthOrNull(String absolutePath) async {
    try {
      return await File(absolutePath).length();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> resolveRealPathOrNull(String absolutePath) async {
    try {
      return await File(absolutePath).resolveSymbolicLinks();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> delete(String absolutePath, {required String reason}) async {
    await deleteAppOwnedMediaFileIfExists(
      file: File(absolutePath),
      caller: 'MediaStorageManager',
      reason: reason,
    );
  }
}

/// Typed outcome of [MediaStorageManager.clearLocalCopy]. Every `rejected*`
/// value is decided BEFORE any DB or file mutation.
enum MediaClearLocalCopyResult {
  /// Claim + delete + path-clear all landed; the local copy is gone.
  cleared,

  /// The row was already evicted with no stored path — nothing to do.
  alreadyCleared,

  /// The row is `downloading`; zero mutation. Retry after it settles.
  busy,

  /// The conditional evicted claim affected zero rows (the row changed
  /// underneath the request) or the claim write itself failed; zero
  /// mutation, no file was touched.
  conflict,

  /// The durable evicted claim survives but the file delete (or the final
  /// path-clear) failed — the row keeps `evicted` plus the expected path, a
  /// later Clear retries deletion, and storage totals keep counting the
  /// bytes until deletion succeeds.
  cleanupFailed,

  /// No attachment row with this id exists.
  rejectedMissingRow,

  /// The row's owner lane is not the requested scope's lane (including
  /// legacy `unresolved` rows, which are never addressable).
  rejectedWrongOwner,

  /// The row's MIME does not match the caller's — the expected canonical
  /// extension cannot be derived from a guess.
  rejectedMimeMismatch,

  /// The row holds no durable local copy (pending/failed/terminal, or done
  /// without a stored path).
  rejectedNotClearable,

  /// The stored path is not the exact canonical relative form (or its exact
  /// current-container absolute equivalent). Misleading legacy absolute
  /// paths require an explicit path repair before Clear;
  /// `resolveStoredPath`-style substring extraction is never authorization.
  rejectedNoncanonicalPath,

  /// The canonical path exists but resolves (via any symlink component)
  /// outside the exact expected target inside this scope's directory.
  rejectedUnsafeTarget,
}

extension MediaClearLocalCopyResultX on MediaClearLocalCopyResult {
  bool get isRejection => name.startsWith('rejected');
}

/// Aggregate result of a per-type batch clear.
class MediaStorageClearSweepResult {
  const MediaStorageClearSweepResult({
    required this.cleared,
    required this.failed,
  });

  final int cleared;
  final int failed;
}

/// 229: user-invoked local media storage management for one conversation
/// scope — exact inventory totals and the safe "remove local copy, keep
/// message" action.
///
/// Ownership is always the caller's typed [MediaLibraryScope]; storage is
/// never inferred from `message_id` or conversation kind. Deletion follows
/// the durable protocol: authorize the exact canonical path, claim the row
/// `evicted` (compare-and-set on owner/id/path/status), delete the exact
/// canonical file, then null the path — never holding a DB transaction
/// across file I/O, never deleting before the durable claim.
class MediaStorageManager {
  MediaStorageManager({
    required MediaAttachmentRepository repository,
    required Future<String> Function() documentsDirectoryProvider,
    MediaStorageFileGateway fileGateway = const IoMediaStorageFileGateway(),
    MediaAttachmentLifecycleLock? lifecycleLock,
  }) : _repository = repository,
       _documentsDirectoryProvider = documentsDirectoryProvider,
       _fileGateway = fileGateway,
       _lifecycleLock = lifecycleLock ?? mediaAttachmentLifecycleLock;

  final MediaAttachmentRepository _repository;
  final Future<String> Function() _documentsDirectoryProvider;
  final MediaStorageFileGateway _fileGateway;
  final MediaAttachmentLifecycleLock _lifecycleLock;

  MediaAttachmentByIdLookup get _byIdLookup {
    final repository = _repository;
    if (repository is! MediaAttachmentByIdLookup) {
      throw StateError(
        'MediaStorageManager requires a MediaAttachmentByIdLookup-capable '
        'repository',
      );
    }
    return repository as MediaAttachmentByIdLookup;
  }

  MediaDownloadStateRepository get _stateRepository {
    final repository = _repository;
    if (repository is! MediaDownloadStateRepository) {
      throw StateError(
        'MediaStorageManager requires a MediaDownloadStateRepository-capable '
        'repository',
      );
    }
    return repository as MediaDownloadStateRepository;
  }

  MediaStorageInventoryRepository get _inventoryRepository {
    final repository = _repository;
    if (repository is! MediaStorageInventoryRepository) {
      throw StateError(
        'MediaStorageManager requires a MediaStorageInventoryRepository-'
        'capable repository',
      );
    }
    return repository as MediaStorageInventoryRepository;
  }

  /// Removes the app-private downloaded copy of one attachment while keeping
  /// the message, descriptor, keys, bookmarks and siblings intact.
  Future<MediaClearLocalCopyResult> clearLocalCopy({
    required MediaLibraryScope scope,
    required String attachmentId,
    required String mime,
  }) async {
    final result = await _lifecycleLock.synchronized(
      attachmentId,
      () =>
          _clearLocalCopy(scope: scope, attachmentId: attachmentId, mime: mime),
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'MEDIA_STORAGE_CLEAR_LOCAL_COPY',
      details: {
        'attachmentId': attachmentId.length > 8
            ? attachmentId.substring(0, 8)
            : attachmentId,
        'scopeKind': scope.lane.dbValue,
        'result': result.name,
      },
    );
    return result;
  }

  Future<MediaClearLocalCopyResult> _clearLocalCopy({
    required MediaLibraryScope scope,
    required String attachmentId,
    required String mime,
  }) async {
    final row = await _byIdLookup.getAttachmentById(attachmentId);
    if (row == null) {
      return MediaClearLocalCopyResult.rejectedMissingRow;
    }
    if (row.ownerLane == null || row.ownerLane != scope.lane) {
      return MediaClearLocalCopyResult.rejectedWrongOwner;
    }
    if (row.mime != mime) {
      return MediaClearLocalCopyResult.rejectedMimeMismatch;
    }

    final status = row.downloadStatus;
    if (status == kMediaDownloadStatusDownloading) {
      return MediaClearLocalCopyResult.busy;
    }
    final storedPath = row.localPath;
    if (status == kMediaDownloadStatusEvicted && storedPath == null) {
      return MediaClearLocalCopyResult.alreadyCleared;
    }
    if ((status != kMediaDownloadStatusDone &&
            status != kMediaDownloadStatusEvicted) ||
        storedPath == null) {
      return MediaClearLocalCopyResult.rejectedNotClearable;
    }

    // Exact canonical-path authorization — BEFORE any DB or file mutation.
    final documentsDir = p.normalize(await _documentsDirectoryProvider());
    final expectedRelative = _expectedRelativePath(scope, attachmentId, mime);
    final expectedAbsolute = p.normalize(
      p.join(documentsDir, expectedRelative),
    );
    if (!_storedPathIsExactCanonical(
      storedPath: storedPath,
      expectedRelative: expectedRelative,
      expectedAbsolute: expectedAbsolute,
    )) {
      return MediaClearLocalCopyResult.rejectedNoncanonicalPath;
    }
    if (!await _resolvedTargetIsExpected(
      documentsDir: documentsDir,
      expectedRelative: expectedRelative,
      expectedAbsolute: expectedAbsolute,
    )) {
      return MediaClearLocalCopyResult.rejectedUnsafeTarget;
    }

    // Durable claim BEFORE deletion. A cleanup-pending row (evicted with a
    // retained path) is already claimed; everything else must win the exact
    // (owner, id, storedPath, done) compare-and-set or nothing is touched.
    if (status == kMediaDownloadStatusDone) {
      final int claimed;
      try {
        claimed = await _stateRepository.claimMediaEvicted(
          attachmentId,
          owner: scope.lane,
          expectedLocalPath: storedPath,
        );
      } catch (_) {
        return MediaClearLocalCopyResult.conflict;
      }
      if (claimed == 0) {
        return MediaClearLocalCopyResult.conflict;
      }
    }

    // Delete the exact canonical file (no DB transaction spans this I/O).
    try {
      await _fileGateway.delete(expectedAbsolute, reason: 'clear_local_copy');
    } catch (_) {
      return MediaClearLocalCopyResult.cleanupFailed;
    }

    // Conditionally null the path now that the bytes are gone. A failure
    // here leaves evicted + stale path, which a fresh manager's inventory
    // reconciles after proving the canonical file absent.
    try {
      await _stateRepository.finalizeMediaEvictedPathCleared(
        attachmentId,
        owner: scope.lane,
      );
    } catch (_) {
      return MediaClearLocalCopyResult.cleanupFailed;
    }
    return MediaClearLocalCopyResult.cleared;
  }

  /// Exact storage totals for [scope]: pages the dedicated all-media storage
  /// query to exhaustion (opaque cursors, pages of at most
  /// [kMediaLibraryMaxPageSize]) and counts only canonical files that
  /// actually exist, at their true on-disk length. Unresolved, hidden,
  /// deleted and tombstoned rows never surface from the query; noncanonical,
  /// exported and missing paths are excluded here. A cleanup-pending evicted
  /// row keeps counting its bytes until deletion succeeds; one whose
  /// canonical file is proven absent is reconciled to a null path.
  ///
  /// User-invoked only — never run this from startup or conversation build.
  Future<MediaStorageInventory> inventory({
    required MediaLibraryScope scope,
  }) async {
    final documentsDir = p.normalize(await _documentsDirectoryProvider());
    final totals = <String, MediaStorageTypeTotal>{
      for (final type in MediaStorageKind.all.mediaTypes)
        type: const MediaStorageTypeTotal(),
    };
    String? cursor;
    do {
      final page = await _inventoryRepository.getMediaStoragePage(
        scope: scope,
        cursor: cursor,
      );
      for (final entry in page.entries) {
        final attachment = entry.attachment;
        final storedPath = attachment.localPath;
        if (storedPath == null) continue;
        final expectedRelative = _expectedRelativePath(
          scope,
          attachment.id,
          attachment.mime,
        );
        final expectedAbsolute = p.normalize(
          p.join(documentsDir, expectedRelative),
        );
        if (!_storedPathIsExactCanonical(
          storedPath: storedPath,
          expectedRelative: expectedRelative,
          expectedAbsolute: expectedAbsolute,
        )) {
          continue;
        }
        if (!await _resolvedTargetIsExpected(
          documentsDir: documentsDir,
          expectedRelative: expectedRelative,
          expectedAbsolute: expectedAbsolute,
        )) {
          continue;
        }
        final length = await _fileGateway.lengthOrNull(expectedAbsolute);
        if (length == null) {
          // Descriptor-only rows contribute nothing. A cleanup-pending
          // evicted row whose canonical file is proven absent reconciles to
          // its durable final form (evicted, null path). Auto-download is
          // never armed here.
          if (attachment.downloadStatus == kMediaDownloadStatusEvicted) {
            try {
              await _stateRepository.finalizeMediaEvictedPathCleared(
                attachment.id,
                owner: scope.lane,
              );
            } catch (_) {}
          }
          continue;
        }
        final type = attachment.mediaType;
        totals[type] = (totals[type] ?? const MediaStorageTypeTotal()).add(
          length,
        );
      }
      cursor = page.nextCursor;
    } while (cursor != null);
    return MediaStorageInventory(byType: Map.unmodifiable(totals));
  }

  /// Clears every clearable local copy of one media type in [scope]
  /// (collects the ids first, then runs [clearLocalCopy] per row, so paging
  /// never races its own mutations).
  Future<MediaStorageClearSweepResult> clearLocalCopiesForType({
    required MediaLibraryScope scope,
    required MediaStorageKind kind,
  }) async {
    final targets = <({String id, String mime})>[];
    String? cursor;
    do {
      final page = await _inventoryRepository.getMediaStoragePage(
        scope: scope,
        kind: kind,
        cursor: cursor,
      );
      for (final entry in page.entries) {
        targets.add((id: entry.attachment.id, mime: entry.attachment.mime));
      }
      cursor = page.nextCursor;
    } while (cursor != null);

    var cleared = 0;
    var failed = 0;
    for (final target in targets) {
      final result = await clearLocalCopy(
        scope: scope,
        attachmentId: target.id,
        mime: target.mime,
      );
      switch (result) {
        case MediaClearLocalCopyResult.cleared:
        case MediaClearLocalCopyResult.alreadyCleared:
          cleared++;
        default:
          failed++;
      }
    }
    return MediaStorageClearSweepResult(cleared: cleared, failed: failed);
  }

  String _expectedRelativePath(
    MediaLibraryScope scope,
    String attachmentId,
    String mime,
  ) => MediaFilePathConvention.relativePathForAttachment(
    contactPeerId: scope.id,
    blobId: attachmentId,
    mime: mime,
  );

  /// The stored column value must be EXACTLY the canonical relative path or
  /// the normalized current-container absolute equivalent. Nothing else —
  /// no substring remaps, no lexical prefixes, no attachment-id-only
  /// matches, no foreign absolute paths.
  bool _storedPathIsExactCanonical({
    required String storedPath,
    required String expectedRelative,
    required String expectedAbsolute,
  }) {
    final normalizedStored = p.normalize(storedPath.replaceAll('\\', '/'));
    return normalizedStored == p.normalize(expectedRelative) ||
        normalizedStored == expectedAbsolute;
  }

  /// When the canonical path exists, every component must resolve to the
  /// real expected target inside this scope's directory under the real
  /// documents root — a symlinked file or a symlinked parent directory
  /// resolves elsewhere and fails closed. A missing path is safe (deletion
  /// is a no-op; nothing to stat).
  Future<bool> _resolvedTargetIsExpected({
    required String documentsDir,
    required String expectedRelative,
    required String expectedAbsolute,
  }) async {
    if (!await _fileGateway.exists(expectedAbsolute)) {
      return true;
    }
    final realDocuments =
        await _fileGateway.resolveRealPathOrNull(documentsDir) ?? documentsDir;
    final realTarget = await _fileGateway.resolveRealPathOrNull(
      expectedAbsolute,
    );
    return realTarget != null &&
        realTarget == p.normalize(p.join(realDocuments, expectedRelative));
  }
}
