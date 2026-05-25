import 'dart:io';

import 'package:flutter_app/core/constants/media_constants.dart';
import 'package:flutter_app/core/media/group_media_mime_policy.dart';
import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

const int kGroupMediaPerAttachmentLimitBytes =
    kGeneralMediaAttachmentBudgetBytes;
const int kGroupMediaTotalMessageLimitBytes =
    kGeneralMediaAttachmentBudgetBytes;

class GroupMediaSizePolicy {
  static GroupMediaValidationResult validateRawDescriptors(
    List<Map<String, dynamic>>? descriptors, {
    int perMediaLimitBytes = kGroupMediaPerAttachmentLimitBytes,
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
    int perMediaLimitBytes = kGroupMediaPerAttachmentLimitBytes,
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
    int perMediaLimitBytes = kGroupMediaPerAttachmentLimitBytes,
  }) {
    if (sizeBytes <= 0) {
      return const GroupMediaValidationResult.invalid('invalid_media_size');
    }
    if (sizeBytes > perMediaLimitBytes) {
      return const GroupMediaValidationResult.invalid('media_size_exceeded');
    }

    final normalizedMime = GroupMediaMimePolicy.normalizeMime(mime);
    if (normalizedMime == 'image/gif' && sizeBytes > kMaxGifFileSize) {
      return const GroupMediaValidationResult.invalid('gif_size_exceeded');
    }

    return const GroupMediaValidationResult.valid();
  }

  static Future<GroupMediaValidationResult> validateLocalFile({
    required String path,
    required String? mime,
    int perMediaLimitBytes = kGroupMediaPerAttachmentLimitBytes,
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
