import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/media/attachment_file_name.dart';

const int kMaxMediaEgressItems = 10;

final RegExp _requestIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

enum MediaEgressDestination {
  photos,
  files,
  share,

  /// 414: show one PDF in the system viewer (iOS Quick Look, Android
  /// ACTION_VIEW). Like [share], it reports presentation, not per-item saves.
  open;

  /// True for destinations whose native result is a presentation outcome with
  /// no per-item results.
  bool get isPresentation => this == share || this == open;
}

enum MediaEgressOutcome {
  saved,
  partial,
  cancelled,
  busy,
  permissionDenied,
  rejected,
  platformFailure,
  presented,

  /// 414: no installed app can view the document (Android `open` only).
  noViewer,
}

enum MediaEgressItemOutcome {
  saved,
  cancelled,
  busy,
  permissionDenied,
  missingFile,
  unsupportedType,
  outsideOwnedRoot,
  identityConflict,
  platformFailure,
}

class ReceivedMediaEgressCandidate {
  const ReceivedMediaEgressCandidate({
    required this.attachmentId,
    required this.storedPath,
    required this.mime,
    this.fileName,
  });

  final String attachmentId;
  final String storedPath;
  final String mime;

  /// 414: the document's display name, used for the exported file name.
  final String? fileName;
}

class MediaEgressItem {
  const MediaEgressItem({
    required this.attachmentId,
    required this.sourcePath,
    required this.mime,
    required this.displayName,
  });

  final String attachmentId;
  final String sourcePath;
  final String mime;
  final String displayName;

  Map<String, Object> toMap() => <String, Object>{
    'attachmentId': attachmentId,
    'sourcePath': sourcePath,
    'mime': mime,
    'displayName': displayName,
  };
}

class MediaEgressRequest {
  MediaEgressRequest({
    required this.requestId,
    required this.destination,
    required List<MediaEgressItem> items,
  }) : items = List<MediaEgressItem>.unmodifiable(items) {
    if (!isValidMediaEgressRequestId(requestId)) {
      throw ArgumentError.value(requestId, 'requestId', 'invalid request ID');
    }
    if (items.isEmpty ||
        items.length > kMaxMediaEgressItems ||
        (destination == MediaEgressDestination.open && items.length != 1)) {
      throw ArgumentError.value(items.length, 'items', 'invalid item count');
    }
    final ids = <String>{};
    for (final item in items) {
      if (item.attachmentId.trim().isEmpty ||
          !ids.add(item.attachmentId) ||
          item.sourcePath.isEmpty ||
          item.displayName.isEmpty ||
          !isSupportedMediaEgressMime(item.mime) ||
          !isMediaEgressMimeAllowedFor(destination, item.mime)) {
        throw ArgumentError('invalid media item');
      }
    }
  }

  final String requestId;
  final MediaEgressDestination destination;
  final List<MediaEgressItem> items;

  Map<String, Object> toMap() => <String, Object>{
    'requestId': requestId,
    'destination': destination.name,
    'items': items.map((item) => item.toMap()).toList(growable: false),
  };
}

class MediaEgressItemResult {
  const MediaEgressItemResult({
    required this.attachmentId,
    required this.outcome,
  });

  final String attachmentId;
  final MediaEgressItemOutcome outcome;
}

class MediaEgressResult {
  const MediaEgressResult({
    required this.requestId,
    required this.outcome,
    required this.items,
  });

  final String requestId;
  final MediaEgressOutcome outcome;
  final List<MediaEgressItemResult> items;
}

bool isValidMediaEgressRequestId(String value) =>
    _requestIdPattern.hasMatch(value);

bool isSupportedMediaEgressMime(String mime) =>
    mediaEgressExtensionForMime(mime) != null;

/// 414: a PDF can be saved to Files, shared or opened, never saved to Photos.
/// `open` takes PDFs only.
bool isMediaEgressMimeAllowedFor(
  MediaEgressDestination destination,
  String mime,
) {
  final isPdf = mime.toLowerCase() == 'application/pdf';
  return switch (destination) {
    MediaEgressDestination.photos => !isPdf,
    MediaEgressDestination.open => isPdf,
    MediaEgressDestination.files || MediaEgressDestination.share => true,
  };
}

String? mediaEgressExtensionForMime(String mime) =>
    switch (mime.toLowerCase()) {
      'image/jpeg' => '.jpg',
      'image/png' => '.png',
      'image/gif' => '.gif',
      'image/webp' => '.webp',
      'image/heic' => '.heic',
      'video/mp4' => '.mp4',
      'video/quicktime' => '.mov',
      'video/webm' => '.webm',
      'application/pdf' => '.pdf',
      _ => null,
    };

String mediaEgressDisplayName(
  String attachmentId,
  String mime, {
  String? preferredName,
}) {
  final extension = mediaEgressExtensionForMime(mime)!;
  // 414: a document keeps its own clean name, always with the right
  // extension so the receiving app knows the type.
  final preferred = sanitizeAttachmentFileName(preferredName);
  if (preferred != null) {
    return preferred.toLowerCase().endsWith(extension)
        ? preferred
        : sanitizeAttachmentFileName('$preferred$extension')!;
  }
  var safe = attachmentId.replaceAll(RegExp('[^A-Za-z0-9_-]'), '_');
  safe = safe.replaceAll(RegExp('_+'), '_');
  if (safe.isEmpty) safe = 'attachment';
  if (safe != attachmentId || safe.length > 72) {
    final suffix = sha256
        .convert(utf8.encode(attachmentId))
        .toString()
        .substring(0, 12);
    if (safe.length > 59) safe = safe.substring(0, 59);
    safe = '${safe}_$suffix';
  }
  return '$safe$extension';
}
