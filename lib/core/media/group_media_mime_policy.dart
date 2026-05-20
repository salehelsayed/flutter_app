import 'dart:io';

import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

class GroupMediaValidationResult {
  final bool isValid;
  final String? reason;

  const GroupMediaValidationResult.valid() : isValid = true, reason = null;

  const GroupMediaValidationResult.invalid(this.reason) : isValid = false;
}

class GroupMediaMimePolicy {
  static const Map<String, String> allowedMimeToMediaType = {
    'image/jpeg': 'image',
    'image/png': 'image',
    'image/gif': 'image',
    'image/webp': 'image',
    'image/heic': 'image',
    'video/mp4': 'video',
    'video/quicktime': 'video',
    'audio/mp4': 'audio',
    'audio/aac': 'audio',
    'audio/mpeg': 'audio',
    'audio/ogg': 'audio',
    'application/octet-stream': 'file',
  };

  static String? normalizeMime(String? mime) {
    final normalized = mime?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    return normalized;
  }

  static String? mediaTypeForMime(String? mime) {
    final normalized = normalizeMime(mime);
    if (normalized == null) return null;
    return allowedMimeToMediaType[normalized];
  }

  static bool isAllowedMime(String? mime) => mediaTypeForMime(mime) != null;

  static GroupMediaValidationResult validateDescriptor({
    required String? mime,
    String? mediaType,
  }) {
    final normalizedMime = normalizeMime(mime);
    if (normalizedMime == null) {
      return const GroupMediaValidationResult.invalid('missing_mime');
    }

    final expectedMediaType = allowedMimeToMediaType[normalizedMime];
    if (expectedMediaType == null) {
      return const GroupMediaValidationResult.invalid('disallowed_mime');
    }

    final normalizedMediaType = mediaType?.trim().toLowerCase();
    if (normalizedMediaType != null &&
        normalizedMediaType.isNotEmpty &&
        normalizedMediaType != expectedMediaType) {
      return const GroupMediaValidationResult.invalid('media_type_mismatch');
    }

    return const GroupMediaValidationResult.valid();
  }

  static bool isValidDescriptor({required String? mime, String? mediaType}) {
    return validateDescriptor(mime: mime, mediaType: mediaType).isValid;
  }

  static MediaAttachment sanitizeAttachment(MediaAttachment attachment) {
    final result = validateDescriptor(
      mime: attachment.mime,
      mediaType: attachment.mediaType,
    );
    if (!result.isValid) {
      throw FormatException(result.reason ?? 'invalid_group_media');
    }

    final normalizedMime = normalizeMime(attachment.mime)!;
    return attachment.copyWith(
      mime: normalizedMime,
      mediaType: allowedMimeToMediaType[normalizedMime],
    );
  }

  static MediaAttachment sanitizeWireAttachment(
    Map<String, dynamic> rawAttachment, {
    required String messageId,
  }) {
    return sanitizeAttachment(
      MediaAttachment.fromJson(rawAttachment).copyWith(messageId: messageId),
    );
  }

  static Future<GroupMediaValidationResult> validateFile({
    required String path,
    required String? mime,
    String? mediaType,
  }) async {
    final descriptor = validateDescriptor(mime: mime, mediaType: mediaType);
    if (!descriptor.isValid) return descriptor;

    final file = File(path);
    if (!await file.exists()) {
      return const GroupMediaValidationResult.invalid('missing_file');
    }

    final bytes = await file
        .openRead(0, 64)
        .fold<List<int>>(<int>[], (buffer, chunk) => buffer..addAll(chunk));
    if (bytes.isEmpty) {
      return const GroupMediaValidationResult.invalid('empty_file');
    }

    final normalizedMime = normalizeMime(mime)!;
    final detected = _detectKnownSignature(bytes);
    if (detected == _DetectedSignature.unknown) {
      return const GroupMediaValidationResult.valid();
    }
    if (detected == _DetectedSignature.html ||
        detected == _DetectedSignature.exe ||
        detected == _DetectedSignature.pdf ||
        detected == _DetectedSignature.zip) {
      return const GroupMediaValidationResult.invalid('dangerous_signature');
    }
    if (!_signatureMatchesMime(detected, normalizedMime)) {
      return const GroupMediaValidationResult.invalid(
        'mime_signature_mismatch',
      );
    }

    return const GroupMediaValidationResult.valid();
  }

  static Future<bool> fileMatchesDeclaredMime({
    required String path,
    required String? mime,
    String? mediaType,
  }) async {
    return (await validateFile(
      path: path,
      mime: mime,
      mediaType: mediaType,
    )).isValid;
  }

  static _DetectedSignature _detectKnownSignature(List<int> bytes) {
    bool startsWith(List<int> prefix) {
      if (bytes.length < prefix.length) return false;
      for (var i = 0; i < prefix.length; i++) {
        if (bytes[i] != prefix[i]) return false;
      }
      return true;
    }

    bool asciiAt(int offset, String value) {
      if (bytes.length < offset + value.length) return false;
      for (var i = 0; i < value.length; i++) {
        if (bytes[offset + i] != value.codeUnitAt(i)) return false;
      }
      return true;
    }

    final lowerAscii = String.fromCharCodes(
      bytes
          .where((byte) => byte >= 0x09 && byte <= 0x7e)
          .take(48)
          .map((byte) => byte >= 0x41 && byte <= 0x5a ? byte + 0x20 : byte),
    );

    if (startsWith(const [0xff, 0xd8, 0xff])) {
      return _DetectedSignature.jpeg;
    }
    if (startsWith(const [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) {
      return _DetectedSignature.png;
    }
    if (asciiAt(0, 'GIF87a') || asciiAt(0, 'GIF89a')) {
      return _DetectedSignature.gif;
    }
    if (asciiAt(0, 'RIFF') && asciiAt(8, 'WEBP')) {
      return _DetectedSignature.webp;
    }
    if (asciiAt(4, 'ftyp')) {
      if (asciiAt(8, 'qt  ')) return _DetectedSignature.quicktime;
      final brandWindow = String.fromCharCodes(
        bytes.skip(8).take(32).where((byte) => byte >= 0x20 && byte <= 0x7e),
      );
      if (brandWindow.contains('heic') ||
          brandWindow.contains('heix') ||
          brandWindow.contains('hevc') ||
          brandWindow.contains('hevx') ||
          brandWindow.contains('mif1') ||
          brandWindow.contains('msf1')) {
        return _DetectedSignature.heic;
      }
      return _DetectedSignature.mp4;
    }
    if (asciiAt(0, 'OggS')) return _DetectedSignature.ogg;
    if (bytes.length >= 2 &&
        bytes[0] == 0xff &&
        (bytes[1] == 0xf1 || bytes[1] == 0xf9)) {
      return _DetectedSignature.aac;
    }
    if (asciiAt(0, 'ID3') ||
        (bytes.length >= 2 && bytes[0] == 0xff && (bytes[1] & 0xe0) == 0xe0)) {
      return _DetectedSignature.mpegAudio;
    }
    if (startsWith(const [0x25, 0x50, 0x44, 0x46])) {
      return _DetectedSignature.pdf;
    }
    if (startsWith(const [0x50, 0x4b, 0x03, 0x04])) {
      return _DetectedSignature.zip;
    }
    if (startsWith(const [0x4d, 0x5a])) return _DetectedSignature.exe;
    if (lowerAscii.startsWith('<!doctype html') ||
        lowerAscii.startsWith('<html') ||
        lowerAscii.startsWith('<script')) {
      return _DetectedSignature.html;
    }

    return _DetectedSignature.unknown;
  }

  static bool _signatureMatchesMime(_DetectedSignature detected, String mime) {
    return switch (detected) {
      _DetectedSignature.jpeg => mime == 'image/jpeg',
      _DetectedSignature.png => mime == 'image/png',
      _DetectedSignature.gif => mime == 'image/gif',
      _DetectedSignature.webp => mime == 'image/webp',
      _DetectedSignature.heic => mime == 'image/heic',
      _DetectedSignature.mp4 => mime == 'video/mp4' || mime == 'audio/mp4',
      _DetectedSignature.quicktime => mime == 'video/quicktime',
      _DetectedSignature.ogg => mime == 'audio/ogg',
      _DetectedSignature.mpegAudio => mime == 'audio/mpeg',
      _DetectedSignature.aac => mime == 'audio/aac',
      _ => false,
    };
  }
}

enum _DetectedSignature {
  unknown,
  jpeg,
  png,
  gif,
  webp,
  heic,
  mp4,
  quicktime,
  ogg,
  mpegAudio,
  aac,
  pdf,
  zip,
  exe,
  html,
}
