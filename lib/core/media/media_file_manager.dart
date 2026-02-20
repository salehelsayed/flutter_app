import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Manages local file paths for media attachments.
///
/// Directory structure: `<app_documents>/media/<contactPeerId>/<blobId>.<ext>`
class MediaFileManager {
  /// Resolves the local file path for a media attachment.
  Future<String> localPathForAttachment({
    required String contactPeerId,
    required String blobId,
    required String mime,
  }) async {
    final dir = await _mediaDir(contactPeerId);
    final ext = _extensionFromMime(mime);
    return p.join(dir.path, '$blobId$ext');
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
