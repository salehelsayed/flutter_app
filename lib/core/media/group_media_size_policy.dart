import 'dart:io';

import 'package:flutter_app/core/constants/media_constants.dart';
import 'package:flutter_app/core/media/group_media_mime_policy.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

// Per-type media size caps (09-P1, OQ-1). These gate SENDS (compose/upload) and
// are validated against final (post-compression) bytes. GIF reuses the dedicated
// [kMaxGifFileSize] (media_constants.dart). The relay's 5 GB ceiling stays as a
// hard backstop only (INV-SZ-3) — it is never the user-facing limit.
const int kGroupMediaImageLimitBytes = 25 * 1024 * 1024; // 25 MB
const int kGroupMediaVideoLimitBytes = 250 * 1024 * 1024; // 250 MB
const int kGroupMediaAudioLimitBytes = 16 * 1024 * 1024; // 16 MB
const int kGroupMediaFileLimitBytes = 100 * 1024 * 1024; // 100 MB

// The largest single-attachment cap across all media types (== the video cap).
// Used as the permissive cross-type backstop on the RECEIVE / render / recovery
// paths (which must never newly hide already-received local media) and as a DoS
// ceiling on incoming descriptors. A value at or below this may still be
// rejected by its narrower per-type cap on the SEND path.
const int kGroupMediaPerAttachmentLimitBytes = kGroupMediaVideoLimitBytes;

// Total bytes summed across every attachment in a single message/send.
const int kGroupMediaTotalMessageLimitBytes = 500 * 1024 * 1024; // 500 MB

/// Resolves the per-type SEND cap for [mime]. GIF is checked first (its cap is
/// the dedicated [kMaxGifFileSize]); then image / video / audio; everything else
/// (including unknown / empty mimes) falls back to the generic file cap.
int groupMediaPerTypeLimitBytes(String? mime) {
  final normalized = GroupMediaMimePolicy.normalizeMime(mime);
  if (normalized == 'image/gif') return kMaxGifFileSize;
  final mediaType = normalized == null
      ? 'file'
      : MediaAttachment.mediaTypeFromMime(normalized);
  switch (mediaType) {
    case 'image':
      return kGroupMediaImageLimitBytes;
    case 'video':
      return kGroupMediaVideoLimitBytes;
    case 'audio':
      return kGroupMediaAudioLimitBytes;
    default:
      return kGroupMediaFileLimitBytes;
  }
}

/// Type-aware rejection reason matching [groupMediaPerTypeLimitBytes].
String _perTypeSizeReason(String? mime) {
  final normalized = GroupMediaMimePolicy.normalizeMime(mime);
  if (normalized == 'image/gif') return 'gif_size_exceeded';
  final mediaType = normalized == null
      ? 'file'
      : MediaAttachment.mediaTypeFromMime(normalized);
  switch (mediaType) {
    case 'image':
      return 'image_size_exceeded';
    case 'video':
      return 'video_size_exceeded';
    case 'audio':
      return 'voice_size_exceeded';
    default:
      return 'file_size_exceeded';
  }
}

class GroupMediaSizePolicy {
  static GroupMediaValidationResult validateRawDescriptors(
    List<Map<String, dynamic>>? descriptors, {
    int? perMediaLimitBytes,
    int totalLimitBytes = kGroupMediaTotalMessageLimitBytes,
  }) {
    if (descriptors == null || descriptors.isEmpty) {
      return const GroupMediaValidationResult.valid();
    }

    var totalBytes = 0;
    for (final descriptor in descriptors) {
      final rawSize = descriptor['size'];
      if (rawSize is! int) {
        return const GroupMediaValidationResult.invalid('invalid_media_size');
      }

      final validation = validateSize(
        sizeBytes: rawSize,
        mime: descriptor['mime'] is String
            ? descriptor['mime'] as String
            : null,
        perMediaLimitBytes: perMediaLimitBytes,
      );
      if (!validation.isValid) return validation;

      totalBytes += rawSize;
      if (totalBytes > totalLimitBytes) {
        return const GroupMediaValidationResult.invalid(
          'total_media_size_exceeded',
        );
      }
    }

    return const GroupMediaValidationResult.valid();
  }

  static GroupMediaValidationResult validateAttachments(
    List<MediaAttachment>? attachments, {
    int? perMediaLimitBytes,
    int totalLimitBytes = kGroupMediaTotalMessageLimitBytes,
  }) {
    if (attachments == null || attachments.isEmpty) {
      return const GroupMediaValidationResult.valid();
    }

    var totalBytes = 0;
    for (final attachment in attachments) {
      final validation = validateSize(
        sizeBytes: attachment.size,
        mime: attachment.mime,
        perMediaLimitBytes: perMediaLimitBytes,
      );
      if (!validation.isValid) return validation;

      totalBytes += attachment.size;
      if (totalBytes > totalLimitBytes) {
        return const GroupMediaValidationResult.invalid(
          'total_media_size_exceeded',
        );
      }
    }

    return const GroupMediaValidationResult.valid();
  }

  static GroupMediaValidationResult validateSize({
    required int sizeBytes,
    required String? mime,
    int? perMediaLimitBytes,
  }) {
    if (sizeBytes <= 0) {
      return const GroupMediaValidationResult.invalid('invalid_media_size');
    }

    if (perMediaLimitBytes != null) {
      // Explicit override: test caps + the receive/render cross-type backstop.
      // The per-type table is ignored and the generic reason is reported, but
      // the dedicated GIF clamp still applies (it always has).
      if (sizeBytes > perMediaLimitBytes) {
        return const GroupMediaValidationResult.invalid('media_size_exceeded');
      }
      final normalizedMime = GroupMediaMimePolicy.normalizeMime(mime);
      if (normalizedMime == 'image/gif' && sizeBytes > kMaxGifFileSize) {
        return const GroupMediaValidationResult.invalid('gif_size_exceeded');
      }
      return const GroupMediaValidationResult.valid();
    }

    // SEND path: derive the per-type cap and report a type-aware reason.
    if (sizeBytes > groupMediaPerTypeLimitBytes(mime)) {
      return GroupMediaValidationResult.invalid(_perTypeSizeReason(mime));
    }
    return const GroupMediaValidationResult.valid();
  }

  static Future<GroupMediaValidationResult> validateLocalFile({
    required String path,
    required String? mime,
    int? perMediaLimitBytes,
  }) async {
    final file = File(path);
    if (!await file.exists()) {
      return const GroupMediaValidationResult.invalid('missing_file');
    }

    final sizeBytes = await file.length();
    return validateSize(
      sizeBytes: sizeBytes,
      mime: mime,
      perMediaLimitBytes: perMediaLimitBytes,
    );
  }
}
