import 'dart:io';

import 'package:flutter_app/core/media/media_mime.dart';

/// Why a local document file may not be sent or opened (414), or null when
/// it is a PDF whose bytes start with `%PDF-`.
///
/// One check for every place that handles a document: the 1:1 upload, the
/// composers, the share sheet and the open action. Group media also passes
/// `GroupMediaMimePolicy.validateFile`, which applies the same rule.
Future<String?> documentFileRejection({
  required String path,
  required String? mime,
}) async {
  if (!isSupportedDocumentMime(mime)) return 'unsupported_document';
  final file = File(path);
  if (!await file.exists()) return 'missing_file';
  RandomAccessFile? reader;
  try {
    reader = await file.open();
    final head = await reader.read(5);
    return hasPdfSignature(head) ? null : 'unknown_signature';
  } on FileSystemException {
    return 'unreadable_file';
  } finally {
    await reader?.close();
  }
}
