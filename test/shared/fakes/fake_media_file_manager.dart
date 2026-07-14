import 'dart:io';
import 'dart:isolate';

import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:path/path.dart' as p;

/// In-memory [MediaFileManager] for tests.
///
/// Returns stub paths without calling getApplicationDocumentsDirectory().
class FakeMediaFileManager extends MediaFileManager {
  static final String _testRootPath = p.join(
    Directory.systemTemp.path,
    'mknoon_fake_media_${pid}_${identityHashCode(Isolate.current)}',
    'test_docs',
  );

  /// The test-isolate-local documents root this fake resolves against.
  ///
  /// 162: after the loaders swap the async [resolveStoredPath] for the static
  /// [MediaFileManager.resolveStoredPathSync], a test that still wants the same
  /// absolute paths must seed `MediaFileManager.cacheDocumentsDir(testRootPath)`
  /// (the static twin cannot be intercepted by this instance override).
  static String get testRootPath => _testRootPath;

  final List<String> deletedContactIds = <String>[];
  final List<String> deletedPostIds = <String>[];
  final List<String> deletedFilePaths = <String>[];

  /// Override the resolve result for testing.
  String? resolveResult;

  /// 162 spy: counts async [resolveStoredPath] invocations. After the loaders
  /// swap to the synchronous twin this MUST stay 0 (the static twin never routes
  /// through this instance) — the RED-on-HEAD lever for TC-162-02/03.
  int resolveStoredPathCount = 0;
  int trustedMediaRootPathCount = 0;

  /// Override file existence for testing.
  bool? fileExistsOverride;

  /// Hook for deletePendingUploadDir.
  void Function(String messageId)? onDeletePendingUploadDir;

  @override
  Future<String> copyToDurableStorage({
    required String sourceFilePath,
    required String messageId,
    required String attachmentId,
    required String mime,
  }) async {
    final extension = p.extension(sourceFilePath);
    final directory = Directory(
      p.join(_testRootPath, 'pending_uploads', messageId),
    );
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    final destination = p.join(directory.path, '$attachmentId$extension');
    final durableFile = File(destination);
    if (!durableFile.existsSync()) {
      durableFile.createSync(recursive: true);
    }
    return p.join('pending_uploads', messageId, '$attachmentId$extension');
  }

  @override
  Future<void> deletePendingUploadDir(String messageId) async {
    onDeletePendingUploadDir?.call(messageId);
  }

  @override
  Future<String> localPathForAttachment({
    required String contactPeerId,
    required String blobId,
    required String mime,
  }) async {
    final relativePath = relativePathForAttachment(
      contactPeerId: contactPeerId,
      blobId: blobId,
      mime: mime,
    );
    final absolutePath = p.join(_testRootPath, relativePath);
    final file = File(absolutePath);
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    return absolutePath;
  }

  @override
  Future<String> resolveStoredPath(String storedPath) async {
    resolveStoredPathCount++;
    if (resolveResult != null) return resolveResult!;
    if (storedPath.startsWith('pending_uploads/') ||
        storedPath.startsWith('pending_uploads\\') ||
        storedPath.startsWith('media/') ||
        storedPath.startsWith('media\\') ||
        storedPath.startsWith('post_media/') ||
        storedPath.startsWith('post_media\\')) {
      return p.join(_testRootPath, storedPath);
    }
    final normalized = storedPath.replaceAll('\\', '/');
    final mediaIndex = normalized.indexOf('/media/');
    if (mediaIndex != -1) {
      return p.join(_testRootPath, normalized.substring(mediaIndex + 1));
    }
    return storedPath;
  }

  @override
  Future<String> trustedMediaRootPath() async {
    trustedMediaRootPathCount++;
    return p.join(_testRootPath, 'media');
  }

  @override
  Future<String> groupForwardSnapshotRootPath() async => p.join(
    _testRootPath,
    MediaFileManager.groupForwardSnapshotRootDirectoryName,
  );

  @override
  Future<String> localPathForPostAttachment({
    required String postId,
    required String blobId,
    required String mime,
  }) async {
    final relativePath = relativePathForPostAttachment(
      postId: postId,
      blobId: blobId,
      mime: mime,
    );
    final absolutePath = p.join(_testRootPath, relativePath);
    final file = File(absolutePath);
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    return absolutePath;
  }

  @override
  String relativePathForPostAttachment({
    required String postId,
    required String blobId,
    required String mime,
  }) {
    return 'post_media/$postId/$blobId';
  }

  @override
  Future<void> deleteMediaForContact(String contactPeerId) async {
    deletedContactIds.add(contactPeerId);
  }

  @override
  Future<void> deleteMediaForPost(String postId) async {
    deletedPostIds.add(postId);
  }

  @override
  Future<void> deleteFile(
    String localPath, {
    String caller = 'MediaFileManager.deleteFile',
    String reason = 'media_file_delete',
    String? storedPath,
    Map<String, Object?> details = const {},
    bool redactTelemetry = false,
  }) async {
    deletedFilePaths.add(localPath);
    // 229: mirror the real manager's observable behavior — production code
    // now routes ALL app-owned unlinks through this seam, so tests that
    // seed real files (e.g. stale unsafe copies) must see them disappear,
    // not merely be recorded.
    try {
      final file = File(localPath);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {}
  }
}
