import 'dart:io';

import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:path/path.dart' as p;

/// In-memory [MediaFileManager] for tests.
///
/// Returns stub paths without calling getApplicationDocumentsDirectory().
class FakeMediaFileManager extends MediaFileManager {
  static final String _testRootPath = p.join(
    Directory.systemTemp.path,
    'test_docs',
  );

  final List<String> deletedContactIds = <String>[];
  final List<String> deletedPostIds = <String>[];
  final List<String> deletedFilePaths = <String>[];

  /// Override the resolve result for testing.
  String? resolveResult;

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
    if (resolveResult != null) return resolveResult!;
    if (storedPath.startsWith('pending_uploads/') ||
        storedPath.startsWith('pending_uploads\\') ||
        storedPath.startsWith('media/') ||
        storedPath.startsWith('media\\') ||
        storedPath.startsWith('post_media/') ||
        storedPath.startsWith('post_media\\')) {
      return p.join(_testRootPath, storedPath);
    }
    return storedPath;
  }

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
  Future<void> deleteFile(String localPath) async {
    deletedFilePaths.add(localPath);
  }
}
