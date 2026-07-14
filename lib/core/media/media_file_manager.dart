import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/media/app_owned_media_delete_telemetry.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// One app-owned temporary forward directory with concurrency-safe,
/// idempotent cleanup.
///
/// Direct and group forward lanes may shape their own typed capture results,
/// but directory ownership and disposal live here so they cannot grow
/// feature-specific retry or orphan-cleanup implementations.
class MediaForwardSnapshotLease {
  MediaForwardSnapshotLease._({
    required this.directory,
    required MediaFileManager mediaFileManager,
  }) : _mediaFileManager = mediaFileManager;

  final Directory directory;
  final MediaFileManager _mediaFileManager;
  bool _disposed = false;
  Future<bool>? _disposeInFlight;

  Future<void> dispose() async {
    if (_disposed) return;
    final current = _disposeInFlight;
    if (current != null) {
      await current;
      return;
    }
    final attempt = _mediaFileManager.deleteGroupForwardSnapshotDirectory(
      directory.path,
    );
    _disposeInFlight = attempt;
    try {
      if (await attempt) {
        _disposed = true;
      }
    } finally {
      if (identical(_disposeInFlight, attempt)) {
        _disposeInFlight = null;
      }
    }
  }
}

/// Manages local file paths for media attachments.
///
/// Directory structure: `<app_documents>/media/<contactPeerId>/<blobId>.<ext>`
///
/// Paths stored in the database use the **relative** format
/// `media/<contactPeerId>/<blobId>.<ext>` so they survive iOS container UUID
/// changes across app restarts. Use [resolveStoredPath] to get an absolute
/// path for file I/O or display.
class MediaFileManager {
  static const String groupForwardSnapshotRootDirectoryName =
      'mknoon_group_forward_snapshots_v1';
  static const String groupForwardSnapshotDirectoryPrefix = 'snapshot_';
  static const Duration groupForwardSnapshotStaleAfter = Duration(hours: 6);
  static const int _groupForwardSnapshotScanLimit = 64;
  static const int _groupForwardSnapshotDeleteLimit = 16;
  static const int _groupForwardSnapshotDeleteAttempts = 3;
  static final Set<String> _activeGroupForwardSnapshotDirectories = <String>{};
  static final Set<String> _failedGroupForwardSnapshotDirectories = <String>{};

  /// Process-wide cached documents-dir for SYNCHRONOUS path resolution at the
  /// render boundary.
  ///
  /// 127 (round 3): the conversation render gate (`MediaGridCell`,
  /// `MediaThumbnailImage`) checks `File(localPath).existsSync()` and the DB
  /// stores a RELATIVE path. On iOS a relative path resolves against the
  /// process CWD (not Documents), so the gate fails. The async
  /// [resolveStoredPath] cannot run inside a synchronous `build()`, so the
  /// render boundary needs this seeded, sync resolver — mirroring
  /// `UserAvatar.setDocumentsDir`. Seeded once at startup via
  /// [cacheDocumentsDir].
  static String? _cachedDocumentsDir;

  static bool _emittedNoCacheDiagnostic = false;

  /// Seeds the cached documents dir for [resolveStoredPathSync]. Call once at
  /// startup (after `getApplicationDocumentsDirectory()`).
  static void cacheDocumentsDir(String path) {
    _cachedDocumentsDir = path;
  }

  /// The cached documents dir, or null if not yet seeded (tests/non-iOS).
  static String? get cachedDocumentsDir => _cachedDocumentsDir;

  /// Test-only: clears the process-wide cache + diagnostic latch.
  @visibleForTesting
  static void debugResetDocumentsDirCache() {
    _cachedDocumentsDir = null;
    _emittedNoCacheDiagnostic = false;
  }

  /// Synchronous twin of [resolveStoredPath] for the render boundary.
  ///
  /// Pure string work over the cached documents dir. Returns [storedPath]
  /// unchanged when the cache is unseeded or the format is unknown; idempotent
  /// on already-absolute paths and self-correcting for stale absolute paths
  /// left by a prior iOS container (the legacy `/media/` extraction re-roots
  /// them under the current documents dir).
  static String resolveStoredPathSync(String storedPath) {
    final docsDir = _cachedDocumentsDir;
    if (docsDir == null) {
      // 128: the cache should be seeded at startup. If a render-boundary resolve
      // hits a null cache, the seed never ran (stale build / ordering) — emit
      // once so a device log pinpoints it instead of silently passing through.
      if (!_emittedNoCacheDiagnostic) {
        _emittedNoCacheDiagnostic = true;
        emitFlowEvent(
          layer: 'FL',
          event: 'MEDIA_RESOLVE_SYNC_NO_CACHE',
          details: const {},
        );
      }
      return storedPath;
    }
    if (storedPath.startsWith('pending_uploads/') ||
        storedPath.startsWith('pending_uploads\\') ||
        storedPath.startsWith('media/') ||
        storedPath.startsWith('media\\') ||
        storedPath.startsWith('local_media/') ||
        storedPath.startsWith('local_media\\') ||
        storedPath.startsWith('post_media/') ||
        storedPath.startsWith('post_media\\')) {
      return p.join(docsDir, storedPath);
    }
    final mediaIndex = storedPath.indexOf('/media/');
    if (mediaIndex != -1) {
      return p.join(docsDir, storedPath.substring(mediaIndex + 1));
    }
    final localMediaIndex = storedPath.indexOf('/local_media/');
    if (localMediaIndex != -1) {
      return p.join(docsDir, storedPath.substring(localMediaIndex + 1));
    }
    final postMediaIndex = storedPath.indexOf('/post_media/');
    if (postMediaIndex != -1) {
      return p.join(docsDir, storedPath.substring(postMediaIndex + 1));
    }
    return storedPath;
  }

  /// Returns the absolute local file path for a media attachment.
  ///
  /// Creates the parent directory if it doesn't exist.
  Future<String> localPathForAttachment({
    required String contactPeerId,
    required String blobId,
    required String mime,
  }) async {
    final dir = await _mediaDir(contactPeerId);
    final ext = MediaFilePathConvention.extensionFromMime(mime);
    return p.join(dir.path, '$blobId$ext');
  }

  /// Returns the relative path for a media attachment (no leading slash).
  ///
  /// Format: `media/<contactPeerId>/<blobId>.<ext>`
  /// This is the format stored in the database.
  String relativePathForAttachment({
    required String contactPeerId,
    required String blobId,
    required String mime,
  }) {
    return MediaFilePathConvention.relativePathForAttachment(
      contactPeerId: contactPeerId,
      blobId: blobId,
      mime: mime,
    );
  }

  /// Returns the independently trusted root for canonical attachment files.
  ///
  /// Unlike [resolveStoredPath], this never derives authority from a stored
  /// path or from a `/media/` substring supplied by a database row. Security
  /// boundaries must construct their expected target beneath this root first,
  /// then treat legacy-path resolution only as a compatibility comparison.
  Future<String> trustedMediaRootPath() async {
    final appDir = await getApplicationDocumentsDirectory();
    return p.join(appDir.path, 'media');
  }

  /// App-owned, process-temporary storage for immutable forward snapshots.
  ///
  /// A dedicated root keeps scavenging bounded and prevents cleanup from ever
  /// enumerating or deleting unrelated system-temp entries.
  @protected
  Future<String> groupForwardSnapshotRootPath() async =>
      p.join(Directory.systemTemp.path, groupForwardSnapshotRootDirectoryName);

  /// Creates and registers one active forward-snapshot directory.
  ///
  /// A bounded stale-orphan pass runs first so a prior failed dispose is
  /// reclaimed by the next safe forward operation.
  Future<Directory> createGroupForwardSnapshotDirectory() async {
    await scavengeGroupForwardSnapshotOrphans();
    final rootPath = p.normalize(await groupForwardSnapshotRootPath());
    if (!_isTrustedGroupForwardSnapshotRoot(rootPath)) {
      throw const FileSystemException('Untrusted forward snapshot root');
    }
    final rootType = await FileSystemEntity.type(rootPath, followLinks: false);
    if (rootType == FileSystemEntityType.link ||
        (rootType != FileSystemEntityType.directory &&
            rootType != FileSystemEntityType.notFound)) {
      throw const FileSystemException('Unsafe forward snapshot root');
    }
    if (rootType == FileSystemEntityType.notFound) {
      await Directory(rootPath).create(recursive: true);
    }
    if (await FileSystemEntity.type(rootPath, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const FileSystemException('Unsafe forward snapshot root');
    }

    final created = await Directory(
      rootPath,
    ).createTemp(groupForwardSnapshotDirectoryPrefix);
    final createdPath = p.normalize(created.path);
    if (!_isOwnedGroupForwardSnapshotDirectory(
      directoryPath: createdPath,
      rootPath: rootPath,
    )) {
      try {
        await created.delete(recursive: true);
      } catch (_) {}
      throw const FileSystemException('Unsafe forward snapshot directory');
    }
    _activeGroupForwardSnapshotDirectories.add(createdPath);
    return Directory(createdPath);
  }

  /// Allocates one shared forward snapshot lease.
  ///
  /// All callers must dispose the lease in a `finally` block. A failed bounded
  /// delete remains registered for the existing orphan scavenger.
  Future<MediaForwardSnapshotLease> createMediaForwardSnapshotLease() async {
    final directory = await createGroupForwardSnapshotDirectory();
    return MediaForwardSnapshotLease._(
      directory: directory,
      mediaFileManager: this,
    );
  }

  /// Deletes one owned snapshot directory with bounded retries.
  ///
  /// Missing directories are successful (idempotent). A failed deletion is
  /// removed from the active set and remembered for the next scavenger pass.
  Future<bool> deleteGroupForwardSnapshotDirectory(String directoryPath) async {
    final normalized = p.normalize(directoryPath);
    final rootPath = p.normalize(await groupForwardSnapshotRootPath());
    if (!_isTrustedGroupForwardSnapshotRoot(rootPath) ||
        !_isOwnedGroupForwardSnapshotDirectory(
          directoryPath: normalized,
          rootPath: rootPath,
        )) {
      return false;
    }
    final initialType = await FileSystemEntity.type(
      normalized,
      followLinks: false,
    );
    if (initialType == FileSystemEntityType.notFound) {
      _activeGroupForwardSnapshotDirectories.remove(normalized);
      _failedGroupForwardSnapshotDirectories.remove(normalized);
      return true;
    }
    if (await FileSystemEntity.type(rootPath, followLinks: false) !=
        FileSystemEntityType.directory) {
      return false;
    }

    var deleted = false;
    for (
      var attempt = 0;
      attempt < _groupForwardSnapshotDeleteAttempts;
      attempt++
    ) {
      final type = await FileSystemEntity.type(normalized, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        deleted = true;
        break;
      }
      if (type != FileSystemEntityType.directory) {
        break;
      }
      try {
        await deleteGroupForwardSnapshotDirectoryOnce(Directory(normalized));
      } catch (_) {}
      if (await FileSystemEntity.type(normalized, followLinks: false) ==
          FileSystemEntityType.notFound) {
        deleted = true;
        break;
      }
      if (attempt + 1 < _groupForwardSnapshotDeleteAttempts) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    _activeGroupForwardSnapshotDirectories.remove(normalized);
    if (deleted) {
      _failedGroupForwardSnapshotDirectories.remove(normalized);
    } else {
      _failedGroupForwardSnapshotDirectories.add(normalized);
    }
    return deleted;
  }

  /// One physical deletion attempt. Tests may override this failure seam; all
  /// ownership checks, retry bounds, and orphan tracking remain non-bypassable
  /// in [deleteGroupForwardSnapshotDirectory].
  @protected
  Future<void> deleteGroupForwardSnapshotDirectoryOnce(Directory directory) =>
      directory.delete(recursive: true);

  /// Reclaims only inactive, app-owned snapshot children.
  ///
  /// Normal calls delete stale or previously failed entries. Startup may set
  /// [deleteFreshOrphans] because no snapshot from the prior process can still
  /// be active. Scanning and deletion are both strictly bounded.
  Future<int> scavengeGroupForwardSnapshotOrphans({
    bool deleteFreshOrphans = false,
    DateTime? now,
  }) async {
    final rootPath = p.normalize(await groupForwardSnapshotRootPath());
    if (!_isTrustedGroupForwardSnapshotRoot(rootPath) ||
        await FileSystemEntity.type(rootPath, followLinks: false) !=
            FileSystemEntityType.directory) {
      return 0;
    }

    final effectiveNow = now ?? DateTime.now();
    var inspected = 0;
    var deleted = 0;
    try {
      await for (final entity in Directory(rootPath).list(followLinks: false)) {
        if (inspected >= _groupForwardSnapshotScanLimit ||
            deleted >= _groupForwardSnapshotDeleteLimit) {
          break;
        }
        inspected++;
        final candidatePath = p.normalize(entity.path);
        if (!_isOwnedGroupForwardSnapshotDirectory(
              directoryPath: candidatePath,
              rootPath: rootPath,
            ) ||
            _activeGroupForwardSnapshotDirectories.contains(candidatePath)) {
          continue;
        }
        if (await FileSystemEntity.type(candidatePath, followLinks: false) !=
            FileSystemEntityType.directory) {
          continue;
        }
        var shouldDelete =
            deleteFreshOrphans ||
            _failedGroupForwardSnapshotDirectories.contains(candidatePath);
        if (!shouldDelete) {
          try {
            final modified = (await entity.stat()).modified;
            shouldDelete =
                !modified.isAfter(effectiveNow) &&
                effectiveNow.difference(modified) >=
                    groupForwardSnapshotStaleAfter;
          } catch (_) {
            shouldDelete = false;
          }
        }
        if (shouldDelete &&
            await deleteGroupForwardSnapshotDirectory(candidatePath)) {
          deleted++;
        }
      }
    } catch (_) {
      return deleted;
    }
    return deleted;
  }

  bool _isOwnedGroupForwardSnapshotDirectory({
    required String directoryPath,
    required String rootPath,
  }) {
    if (!p.isAbsolute(directoryPath) ||
        !p.isAbsolute(rootPath) ||
        !p.equals(p.dirname(directoryPath), rootPath)) {
      return false;
    }
    return RegExp(
      '^${RegExp.escape(groupForwardSnapshotDirectoryPrefix)}[A-Za-z0-9_-]+\$',
    ).hasMatch(p.basename(directoryPath));
  }

  bool _isTrustedGroupForwardSnapshotRoot(String rootPath) {
    final systemTempPath = p.normalize(Directory.systemTemp.path);
    if (!p.isAbsolute(rootPath) ||
        !p.isWithin(systemTempPath, rootPath) ||
        p.basename(rootPath) != groupForwardSnapshotRootDirectoryName) {
      return false;
    }
    return true;
  }

  /// Returns the absolute local file path for a Posts attachment.
  Future<String> localPathForPostAttachment({
    required String postId,
    required String blobId,
    required String mime,
  }) async {
    final dir = await _postMediaDir(postId);
    final ext = MediaFilePathConvention.extensionFromMime(mime);
    return p.join(dir.path, '$blobId$ext');
  }

  /// Returns the relative path for a Posts attachment (no leading slash).
  String relativePathForPostAttachment({
    required String postId,
    required String blobId,
    required String mime,
  }) {
    return MediaFilePathConvention.relativePathForPostAttachment(
      postId: postId,
      blobId: blobId,
      mime: mime,
    );
  }

  /// Copies a file to durable pending-upload storage.
  ///
  /// Returns the RELATIVE path (for DB storage) of the durable copy.
  /// Format: `pending_uploads/<messageId>/<attachmentId>.<ext>`
  Future<String> copyToDurableStorage({
    required String sourceFilePath,
    required String messageId,
    required String attachmentId,
    required String mime,
  }) async {
    final appDir = await getApplicationDocumentsDirectory();
    final destDir = Directory(
      p.join(appDir.path, 'pending_uploads', messageId),
    );
    if (!await destDir.exists()) {
      await destDir.create(recursive: true);
    }
    final relativePath = MediaFilePathConvention.relativePathForPendingUpload(
      messageId: messageId,
      attachmentId: attachmentId,
      mime: mime,
    );
    final destPath = p.join(appDir.path, relativePath);
    await File(sourceFilePath).copy(destPath);
    return relativePath;
  }

  /// Deletes the pending-upload directory for a message after successful upload.
  Future<void> deletePendingUploadDir(String messageId) async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'pending_uploads', messageId));
    await deleteAppOwnedMediaDirectoryIfExists(
      directory: dir,
      caller: 'MediaFileManager.deletePendingUploadDir',
      reason: 'pending_upload_dir_cleanup',
      recursive: true,
      details: {'messageId': messageId},
    );
  }

  /// Deletes only app-owned durable pending-upload files for [messageId].
  ///
  /// Arbitrary absolute source/gallery paths are ignored even if they were
  /// persisted on the message.
  Future<void> deleteOwnedPendingUploadFilesForMessage({
    required String messageId,
    required Iterable<String?> storedPaths,
  }) async {
    for (final storedPath in storedPaths) {
      if (storedPath == null || storedPath.isEmpty) {
        continue;
      }
      if (!_isOwnedPendingUploadPathForMessage(
        storedPath: storedPath,
        messageId: messageId,
      )) {
        continue;
      }
      final resolvedPath = await resolveStoredPath(storedPath);
      await deleteFile(
        resolvedPath,
        caller: 'MediaFileManager.deleteOwnedPendingUploadFilesForMessage',
        reason: 'owned_pending_upload_file_cleanup',
        storedPath: storedPath,
        details: {'messageId': messageId},
      );
    }
  }

  /// Resolves a stored path (relative or legacy absolute) to an absolute path.
  ///
  /// - Relative paths like `media/...` get prepended with the documents dir.
  /// - Legacy absolute paths containing `/media/` get their relative portion
  ///   extracted and resolved against the current documents dir.
  /// - Other absolute paths are returned as-is.
  Future<String> resolveStoredPath(String storedPath) async {
    // New-style relative path
    if (storedPath.startsWith('pending_uploads/') ||
        storedPath.startsWith('pending_uploads\\') ||
        storedPath.startsWith('media/') ||
        storedPath.startsWith('media\\') ||
        storedPath.startsWith('local_media/') ||
        storedPath.startsWith('local_media\\') ||
        storedPath.startsWith('post_media/') ||
        storedPath.startsWith('post_media\\')) {
      final appDir = await getApplicationDocumentsDirectory();
      return p.join(appDir.path, storedPath);
    }
    // Legacy absolute path — extract relative portion after /media/
    final mediaIndex = storedPath.indexOf('/media/');
    if (mediaIndex != -1) {
      final relativePortion = storedPath.substring(mediaIndex + 1);
      final appDir = await getApplicationDocumentsDirectory();
      return p.join(appDir.path, relativePortion);
    }
    final localMediaIndex = storedPath.indexOf('/local_media/');
    if (localMediaIndex != -1) {
      final relativePortion = storedPath.substring(localMediaIndex + 1);
      final appDir = await getApplicationDocumentsDirectory();
      return p.join(appDir.path, relativePortion);
    }
    final postMediaIndex = storedPath.indexOf('/post_media/');
    if (postMediaIndex != -1) {
      final relativePortion = storedPath.substring(postMediaIndex + 1);
      final appDir = await getApplicationDocumentsDirectory();
      return p.join(appDir.path, relativePortion);
    }
    // Unknown format — return as-is
    return storedPath;
  }

  /// Deletes all media files for a contact.
  Future<void> deleteMediaForContact(String contactPeerId) async {
    final dir = await _mediaDir(contactPeerId);
    await deleteAppOwnedMediaDirectoryIfExists(
      directory: dir,
      caller: 'MediaFileManager.deleteMediaForContact',
      reason: 'contact_media_dir_cleanup',
      recursive: true,
      details: {'contactPeerId': contactPeerId},
    );
  }

  /// Deletes a single file at the given path.
  Future<void> deleteFile(
    String localPath, {
    String caller = 'MediaFileManager.deleteFile',
    String reason = 'media_file_delete',
    String? storedPath,
    Map<String, Object?> details = const {},
    bool redactTelemetry = false,
  }) async {
    await deleteAppOwnedMediaFileIfExists(
      file: File(localPath),
      caller: caller,
      reason: reason,
      storedPath: storedPath,
      details: details,
      redactTelemetry: redactTelemetry,
    );
  }

  Future<void> deleteMediaForPost(String postId) async {
    final dir = await _postMediaDir(postId);
    await deleteAppOwnedMediaDirectoryIfExists(
      directory: dir,
      caller: 'MediaFileManager.deleteMediaForPost',
      reason: 'post_media_dir_cleanup',
      recursive: true,
      details: {'postId': postId},
    );
  }

  Future<Directory> _mediaDir(String contactPeerId) async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'media', contactPeerId));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> _postMediaDir(String postId) async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'post_media', postId));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  bool _isOwnedPendingUploadPathForMessage({
    required String storedPath,
    required String messageId,
  }) {
    final normalized = storedPath.replaceAll('\\', '/');
    final relativePrefix = 'pending_uploads/$messageId/';
    return normalized.startsWith(relativePrefix) ||
        normalized.contains('/$relativePrefix');
  }
}
