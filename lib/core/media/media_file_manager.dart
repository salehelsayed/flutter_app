import 'dart:io';
import 'package:flutter_app/core/media/app_owned_media_delete_telemetry.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
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
  }) async {
    await deleteAppOwnedMediaFileIfExists(
      file: File(localPath),
      caller: caller,
      reason: reason,
      storedPath: storedPath,
      details: details,
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
