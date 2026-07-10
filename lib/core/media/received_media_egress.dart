import 'dart:convert';

import 'package:crypto/crypto.dart';

const int kMaxMediaEgressItems = 10;

final RegExp _requestIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

enum MediaEgressDestination { photos, files, share }

enum MediaEgressOutcome {
  saved,
  partial,
  cancelled,
  busy,
  permissionDenied,
  rejected,
  platformFailure,
  presented,
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
  });

  final String attachmentId;
  final String storedPath;
  final String mime;
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
    if (items.isEmpty || items.length > kMaxMediaEgressItems) {
      throw ArgumentError.value(items.length, 'items', 'invalid item count');
    }
    final ids = <String>{};
    for (final item in items) {
      if (item.attachmentId.trim().isEmpty ||
          !ids.add(item.attachmentId) ||
          item.sourcePath.isEmpty ||
          item.displayName.isEmpty ||
          !isSupportedMediaEgressMime(item.mime)) {
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
      _ => null,
    };

String mediaEgressDisplayName(String attachmentId, String mime) {
  final extension = mediaEgressExtensionForMime(mime)!;
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
