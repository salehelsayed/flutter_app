import 'package:path/path.dart' as p;

class MediaFilePathConvention {
  const MediaFilePathConvention._();

  static String relativePathForAttachment({
    required String contactPeerId,
    required String blobId,
    required String mime,
  }) {
    final ext = extensionFromMime(mime);
    return p.posix.join('media', contactPeerId, '$blobId$ext');
  }

  /// Receiver-side protected-photo inline thumbnail sibling (plan 301).
  ///
  /// Deliberately extension-fixed: the inline payload is always a sender-side
  /// JPEG regardless of the source attachment's mime.
  static String relativeThumbnailPathForAttachment({
    required String contactPeerId,
    required String blobId,
  }) {
    return p.posix.join('media', contactPeerId, '$blobId.thumb.jpg');
  }

  static String relativePathForPostAttachment({
    required String postId,
    required String blobId,
    required String mime,
  }) {
    final ext = extensionFromMime(mime);
    return p.posix.join('post_media', postId, '$blobId$ext');
  }

  static String relativePathForPendingUpload({
    required String messageId,
    required String attachmentId,
    required String mime,
  }) {
    final ext = extensionFromMime(mime);
    return p.posix.join('pending_uploads', messageId, '$attachmentId$ext');
  }

  static String extensionFromMime(String mime) {
    const mimeToExt = {
      'image/jpeg': '.jpg',
      'image/png': '.png',
      'image/gif': '.gif',
      'image/webp': '.webp',
      'image/heic': '.heic',
      'video/mp4': '.mp4',
      'video/quicktime': '.mov',
      // Re-encode-fallback containers (the original container kept when the
      // video re-encode returns null). Must map to a playable extension so
      // the file is openable — never '' (extensionless) or .bin.
      'video/x-m4v': '.m4v',
      'video/x-msvideo': '.avi',
      'video/x-matroska': '.mkv',
      'audio/aac': '.aac',
      'audio/mpeg': '.mp3',
      'audio/mp4': '.m4a',
      'audio/ogg': '.ogg',
      'application/pdf': '.pdf',
    };
    return mimeToExt[mime] ?? '';
  }
}
