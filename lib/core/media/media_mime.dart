/// MIME of the one document type chat can send (414).
const String kPdfMime = 'application/pdf';

/// MIME for a file whose extension chat does not know.
const String kUnknownMediaMime = 'application/octet-stream';

/// File extension to MIME for the chat composers and the share sheet.
///
/// 414 merged four private copies of this map (1:1 composer, group composer,
/// share batch). Only the group copy knew `heif`; it is now shared.
const Map<String, String> kChatMediaMimeByExtension = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'heic': 'image/heic',
  'heif': 'image/heic',
  'mp4': 'video/mp4',
  'mov': 'video/quicktime',
  'avi': 'video/x-msvideo',
  'mkv': 'video/x-matroska',
  'm4v': 'video/x-m4v',
  'm4a': 'audio/mp4',
  'aac': 'audio/aac',
  'pdf': kPdfMime,
};

/// MIME for [path] by its extension, or [kUnknownMediaMime].
String mimeFromPath(String path) {
  final ext = path.split('.').last.toLowerCase();
  return kChatMediaMimeByExtension[ext] ?? kUnknownMediaMime;
}

/// True only for document MIMEs chat can send and open. PDF only (414 D1).
bool isSupportedDocumentMime(String? mime) =>
    mime != null && mime.trim().toLowerCase() == kPdfMime;

/// True when [bytes] start with the PDF file signature `%PDF-`.
bool hasPdfSignature(List<int> bytes) =>
    bytes.length >= 5 &&
    bytes[0] == 0x25 &&
    bytes[1] == 0x50 &&
    bytes[2] == 0x44 &&
    bytes[3] == 0x46 &&
    bytes[4] == 0x2D;
