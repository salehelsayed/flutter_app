import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Manages local file paths for media attachments.
///
/// Directory structure: `<app_documents>/media/<contactPeerId>/<blobId>.<ext>`
///
/// Paths stored in the database use the **relative** format
/// `media/<contactPeerId>/<blobId>.<ext>` so they survive iOS container UUID
/// changes across app restarts. Use [resolveStoredPath] to get an absolute
/// path for file I/O or display.
class MediaFileManager {
  /// Returns the absolute local file path for a media attachment.
  ///
  /// Creates the parent directory if it doesn't exist.
  Future<String> localPathForAttachment({
    required String contactPeerId,
    required String blobId,
    required String mime,
  }) async {
    final dir = await _mediaDir(contactPeerId);
    final ext = _extensionFromMime(mime);
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
    final ext = _extensionFromMime(mime);
    return p.join('media', contactPeerId, '$blobId$ext');
  }

  /// Returns the absolute local file path for a Posts attachment.
  Future<String> localPathForPostAttachment({
    required String postId,
    required String blobId,
    required String mime,
  }) async {
    final dir = await _postMediaDir(postId);
    final ext = _extensionFromMime(mime);
    return p.join(dir.path, '$blobId$ext');
  }

  /// Returns the relative path for a Posts attachment (no leading slash).
  String relativePathForPostAttachment({
    required String postId,
    required String blobId,
    required String mime,
  }) {
    final ext = _extensionFromMime(mime);
    return p.join('post_media', postId, '$blobId$ext');
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
    final ext = _extensionFromMime(mime);
    final appDir = await getApplicationDocumentsDirectory();
    final destDir = Directory(
      p.join(appDir.path, 'pending_uploads', messageId),
    );
    if (!await destDir.exists()) {
      await destDir.create(recursive: true);
    }
    final destPath = p.join(destDir.path, '$attachmentId$ext');
    await File(sourceFilePath).copy(destPath);
    return p.join('pending_uploads', messageId, '$attachmentId$ext');
  }

  /// Deletes the pending-upload directory for a message after successful upload.
  Future<void> deletePendingUploadDir(String messageId) async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'pending_uploads', messageId));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
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
      await deleteFile(resolvedPath);
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
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// Deletes a single file at the given path.
  Future<void> deleteFile(String localPath) async {
    final file = File(localPath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> deleteMediaForPost(String postId) async {
    final dir = await _postMediaDir(postId);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
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

  static String _extensionFromMime(String mime) {
    const mimeToExt = {
      'image/jpeg': '.jpg',
      'image/png': '.png',
      'image/gif': '.gif',
      'image/webp': '.webp',
      'image/heic': '.heic',
      'video/mp4': '.mp4',
      'video/quicktime': '.mov',
      'audio/aac': '.aac',
      'audio/mpeg': '.mp3',
      'audio/mp4': '.m4a',
      'audio/ogg': '.ogg',
      'application/pdf': '.pdf',
    };
    return mimeToExt[mime] ?? '';
  }
}
