import 'dart:io';

import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
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

  if (!GroupMediaIntegrityPolicy.hasValidContentHash(attachment)) {
    return attachment.copyWith(
      localPath: resolvedPath,
      downloadStatus: kMediaDownloadStatusIntegrityFailed,
    );
  }

  if (resolvedPath == null) {
    return attachment;
  }

  final file = File(resolvedPath);
  if (!await file.exists()) {
    return attachment.copyWith(
      localPath: resolvedPath,
      downloadStatus: 'pending',
    );
  }

  final validation = await GroupMediaIntegrityPolicy.validateFileContentHash(
    path: resolvedPath,
    expectedHash: attachment.contentHash,
  );
  if (!validation.isValid) {
    if (validation.reason == 'content_hash_mismatch') {
      try {
        await file.delete();
      } catch (_) {}
    }
    return attachment.copyWith(
      localPath: resolvedPath,
      downloadStatus: kMediaDownloadStatusIntegrityFailed,
    );
  }

  return attachment.copyWith(localPath: resolvedPath);
}
