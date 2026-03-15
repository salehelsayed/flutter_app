import 'package:flutter_app/core/media/media_file_manager.dart';

/// In-memory [MediaFileManager] for tests.
///
/// Returns stub paths without calling getApplicationDocumentsDirectory().
class FakeMediaFileManager extends MediaFileManager {
  final List<String> deletedContactIds = <String>[];
  final List<String> deletedPostIds = <String>[];
  final List<String> deletedFilePaths = <String>[];

  @override
  Future<String> localPathForAttachment({
    required String contactPeerId,
    required String blobId,
    required String mime,
  }) async {
    return '/tmp/test_media/$contactPeerId/$blobId';
  }

  @override
  Future<String> resolveStoredPath(String storedPath) async {
    if (storedPath.startsWith('media/') ||
        storedPath.startsWith('media\\') ||
        storedPath.startsWith('post_media/') ||
        storedPath.startsWith('post_media\\')) {
      return '/tmp/test_docs/$storedPath';
    }
    return storedPath;
  }

  @override
  Future<String> localPathForPostAttachment({
    required String postId,
    required String blobId,
    required String mime,
  }) async {
    return '/tmp/test_post_media/$postId/$blobId';
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
