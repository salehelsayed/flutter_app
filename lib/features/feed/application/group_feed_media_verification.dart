import 'dart:io';

import 'package:flutter_app/core/media/app_owned_media_delete_telemetry.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/group_media_mime_policy.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

Future<List<MediaAttachment>> resolveGroupFeedMediaForDisplay({
  required List<MediaAttachment> attachments,
  MediaFileManager? mediaFileManager,
}) async {
  final resolved = <MediaAttachment>[];
  for (final attachment in attachments) {
    resolved.add(
      await _resolveGroupFeedAttachmentForDisplay(
        attachment: attachment,
        mediaFileManager: mediaFileManager,
      ),
    );
  }
  return resolved;
}

Future<MediaAttachment> _resolveGroupFeedAttachmentForDisplay({
  required MediaAttachment attachment,
  MediaFileManager? mediaFileManager,
}) async {
  final localPath = attachment.localPath;
  final resolvedPath = localPath != null && mediaFileManager != null
      ? await mediaFileManager.resolveStoredPath(localPath)
      : localPath;

  if (attachment.downloadStatus != 'done') {
    return resolvedPath == null
        ? attachment
        : attachment.copyWith(localPath: resolvedPath);
  }

  Future<MediaAttachment> block({
    required String reason,
    required String status,
    required bool fileExists,
    int? fileBytes,
  }) async {
    _emitGroupFeedMediaVerifyEvent(
      event: 'GROUP_FEED_MEDIA_DISPLAY_VERIFY_BLOCKED',
      attachment: attachment,
      resolvedPath: resolvedPath,
      fileExists: fileExists,
      fileBytes: fileBytes,
      reason: reason,
      deleteAttempted: false,
    );
    return attachment.copyWith(localPath: resolvedPath, downloadStatus: status);
  }

  var fileExists = false;
  int? fileBytes;
  File? file;
  if (resolvedPath != null) {
    file = File(resolvedPath);
    fileExists = file.existsSync();
    if (fileExists) {
      fileBytes = file.lengthSync();
    }
  }

  _emitGroupFeedMediaVerifyEvent(
    event: 'GROUP_FEED_MEDIA_DISPLAY_VERIFY_START',
    attachment: attachment,
    resolvedPath: resolvedPath,
    fileExists: fileExists,
    fileBytes: fileBytes,
    deleteAttempted: false,
  );

  final contentHashValidation =
      GroupMediaIntegrityPolicy.validateRequiredContentHash(
        attachment.contentHash,
      );
  if (!contentHashValidation.isValid) {
    return block(
      reason: contentHashValidation.reason ?? 'invalid_content_hash',
      status: kMediaDownloadStatusIntegrityFailed,
      fileExists: fileExists,
      fileBytes: fileBytes,
    );
  }

  if (!attachment.hasEncryptionMetadata) {
    return block(
      reason: 'missing_encryption_metadata',
      status: kMediaDownloadStatusIntegrityFailed,
      fileExists: fileExists,
      fileBytes: fileBytes,
    );
  }

  if (resolvedPath == null || file == null) {
    _emitGroupFeedMediaVerifyEvent(
      event: 'GROUP_FEED_MEDIA_LOCAL_FILE_MISSING',
      attachment: attachment,
      resolvedPath: resolvedPath,
      fileExists: false,
      reason: 'missing_local_path',
      deleteAttempted: false,
    );
    return block(
      reason: 'missing_local_path',
      status: kMediaDownloadStatusPending,
      fileExists: false,
    );
  }

  if (!fileExists) {
    _emitGroupFeedMediaVerifyEvent(
      event: 'GROUP_FEED_MEDIA_LOCAL_FILE_MISSING',
      attachment: attachment,
      resolvedPath: resolvedPath,
      fileExists: false,
      reason: 'missing_file',
      deleteAttempted: false,
    );
    return block(
      reason: 'missing_file',
      status: kMediaDownloadStatusPending,
      fileExists: false,
    );
  }

  if (attachment.size > 0 &&
      fileBytes != null &&
      fileBytes != attachment.size) {
    return block(
      reason: 'file_size_mismatch',
      status: kMediaDownloadStatusIntegrityFailed,
      fileExists: true,
      fileBytes: fileBytes,
    );
  }

  final mimeValidation = await GroupMediaMimePolicy.validateFile(
    path: resolvedPath,
    mime: attachment.mime,
    mediaType: attachment.mediaType,
  );
  if (!mimeValidation.isValid) {
    return block(
      reason: mimeValidation.reason ?? 'invalid_file',
      status: kMediaDownloadStatusIntegrityFailed,
      fileExists: true,
      fileBytes: fileBytes,
    );
  }

  _emitGroupFeedMediaVerifyEvent(
    event: 'GROUP_FEED_MEDIA_PLAINTEXT_HASH_VALIDATION_SKIPPED',
    attachment: attachment,
    resolvedPath: resolvedPath,
    fileExists: true,
    fileBytes: fileBytes,
    contentHashScope: 'relay_blob',
    plaintextHashValidationSkipped: true,
    deleteAttempted: false,
  );
  _emitGroupFeedMediaVerifyEvent(
    event: 'GROUP_FEED_MEDIA_DISPLAY_VERIFY_ALLOWED',
    attachment: attachment,
    resolvedPath: resolvedPath,
    fileExists: true,
    fileBytes: fileBytes,
    reason: 'display_allowed_without_plaintext_hash_validation',
    contentHashScope: 'relay_blob',
    plaintextHashValidationSkipped: true,
    deleteAttempted: false,
  );
  return attachment.copyWith(localPath: resolvedPath);
}

void _emitGroupFeedMediaVerifyEvent({
  required String event,
  required MediaAttachment attachment,
  required String? resolvedPath,
  required bool fileExists,
  int? fileBytes,
  String? reason,
  String? contentHashScope,
  bool? plaintextHashValidationSkipped,
  required bool deleteAttempted,
}) {
  emitFlowEvent(
    layer: 'FL',
    event: event,
    details: {
      'attachmentIdPrefix': _idPrefix(attachment.id),
      'messageIdPrefix': _idPrefix(attachment.messageId),
      'pathKind': appOwnedMediaPathKind(resolvedPath ?? attachment.localPath),
      'storedPathKind': appOwnedMediaPathKind(attachment.localPath),
      'fileExists': fileExists,
      if (fileBytes != null) 'fileBytes': fileBytes,
      'expectedSizeBytes': attachment.size,
      'hasContentHash': GroupMediaIntegrityPolicy.validateRequiredContentHash(
        attachment.contentHash,
      ).isValid,
      'hasEncryptionMetadata': attachment.hasEncryptionMetadata,
      'status': attachment.downloadStatus,
      if (reason != null) 'reason': reason,
      if (contentHashScope != null) 'contentHashScope': contentHashScope,
      if (plaintextHashValidationSkipped != null)
        'plaintextHashValidationSkipped': plaintextHashValidationSkipped,
      'deleteAttempted': deleteAttempted,
    },
  );
}

String _idPrefix(String value) {
  if (value.length <= 8) return value;
  return value.substring(0, 8);
}
