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

  /// Resolves a stored path (relative or legacy absolute) to an absolute path.
  ///
  /// - Relative paths like `media/...` get prepended with the documents dir.
  /// - Legacy absolute paths containing `/media/` get their relative portion
  ///   extracted and resolved against the current documents dir.
  /// - Other absolute paths are returned as-is.
  Future<String> resolveStoredPath(String storedPath) async {
    // New-style relative path
    if (storedPath.startsWith('media/') || storedPath.startsWith('media\\')) {
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

  Future<Directory> _mediaDir(String contactPeerId) async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'media', contactPeerId));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
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
