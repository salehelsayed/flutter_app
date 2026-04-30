import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:flutter_app/core/media/group_media_mime_policy.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

const String kMediaDownloadStatusPending = 'pending';
const String kMediaDownloadStatusDownloading = 'downloading';
const String kMediaDownloadStatusDone = 'done';
const String kMediaDownloadStatusFailed = 'failed';
const String kMediaDownloadStatusIntegrityFailed = 'integrity_failed';
const String kMediaDownloadStatusUploadPending = 'upload_pending';
const String kMediaDownloadStatusUploadFailed = 'upload_failed';
const String kMediaDownloadStatusUploadCancelled = 'upload_cancelled';

class GroupMediaIntegrityPolicy {
  static final RegExp _sha256HexPattern = RegExp(r'^[a-f0-9]{64}$');

  static String? normalizeSha256Hex(String? digest) {
    final normalized = digest?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    if (!_sha256HexPattern.hasMatch(normalized)) return null;
    return normalized;
  }

  static GroupMediaValidationResult validateRequiredContentHash(
    String? digest,
  ) {
    final raw = digest?.trim();
    if (raw == null || raw.isEmpty) {
      return const GroupMediaValidationResult.invalid('missing_content_hash');
    }
    if (normalizeSha256Hex(raw) == null) {
      return const GroupMediaValidationResult.invalid('malformed_content_hash');
    }
    return const GroupMediaValidationResult.valid();
  }

  static GroupMediaValidationResult validateOptionalThumbnailHash(
    String? digest,
  ) {
    final raw = digest?.trim();
    if (raw == null || raw.isEmpty) {
      return const GroupMediaValidationResult.valid();
    }
    if (normalizeSha256Hex(raw) == null) {
      return const GroupMediaValidationResult.invalid(
        'malformed_thumbnail_hash',
      );
    }
    return const GroupMediaValidationResult.valid();
  }

  static bool hasValidContentHash(MediaAttachment attachment) {
    return validateRequiredContentHash(attachment.contentHash).isValid;
  }

  static bool canDisplayVerifiedGroupMedia(MediaAttachment attachment) {
    return attachment.downloadStatus == kMediaDownloadStatusDone &&
        attachment.localPath != null &&
        hasValidContentHash(attachment) &&
        attachment.hasEncryptionMetadata;
  }

  static bool isQuarantinedGroupMedia(MediaAttachment attachment) {
    return attachment.downloadStatus == kMediaDownloadStatusIntegrityFailed;
  }

  static bool isRetryableDownloadFailure(MediaAttachment attachment) {
    return attachment.downloadStatus == kMediaDownloadStatusFailed ||
        attachment.downloadStatus == kMediaDownloadStatusIntegrityFailed;
  }

  static bool isUnavailableMedia(
    MediaAttachment attachment, {
    bool requireVerifiedContentHash = false,
  }) {
    switch (attachment.downloadStatus) {
      case kMediaDownloadStatusFailed:
      case kMediaDownloadStatusIntegrityFailed:
      case kMediaDownloadStatusUploadFailed:
      case kMediaDownloadStatusUploadCancelled:
        return true;
    }

    if (requireVerifiedContentHash &&
        attachment.downloadStatus == kMediaDownloadStatusDone) {
      return !canDisplayVerifiedGroupMedia(attachment);
    }

    return false;
  }

  static Future<String> computeFileSha256Hex(String path) async {
    final file = File(path);
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  static Future<GroupMediaValidationResult> validateFileContentHash({
    required String path,
    required String? expectedHash,
  }) async {
    final expected = normalizeSha256Hex(expectedHash);
    if (expected == null) {
      return validateRequiredContentHash(expectedHash);
    }

    final file = File(path);
    if (!await file.exists()) {
      return const GroupMediaValidationResult.invalid('missing_file');
    }

    final actual = await computeFileSha256Hex(path);
    if (actual != expected) {
      return const GroupMediaValidationResult.invalid('content_hash_mismatch');
    }
    return const GroupMediaValidationResult.valid();
  }
}
