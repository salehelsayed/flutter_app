import 'package:flutter_app/core/media/media_file_manager.dart';

/// In-memory [MediaFileManager] for tests.
///
/// Returns stub paths without calling getApplicationDocumentsDirectory().
class FakeMediaFileManager extends MediaFileManager {
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
    if (storedPath.startsWith('media/') || storedPath.startsWith('media\\')) {
      return '/tmp/test_docs/$storedPath';
    }
    return storedPath;
  }

  @override
  Future<void> deleteMediaForContact(String contactPeerId) async {}

  @override
  Future<void> deleteFile(String localPath) async {}
}
