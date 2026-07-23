import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

/// Applies the group-upload completion field-ownership contract.
///
/// Identity, owner, creation time, thumbnail authority, and both local retry
/// counters remain owned by the exact pending row. The upload result owns the
/// normalized media metadata, durable path, integrity data, and encryption
/// metadata that are learned while transferring the blob.
MediaAttachment applyGroupUploadCompletionAuthority({
  required MediaAttachment expectedAttachment,
  required MediaAttachment completedAttachment,
}) {
  return MediaAttachment(
    id: expectedAttachment.id,
    messageId: expectedAttachment.messageId,
    mime: completedAttachment.mime,
    size: completedAttachment.size,
    mediaType: completedAttachment.mediaType,
    width: completedAttachment.width,
    height: completedAttachment.height,
    durationMs: completedAttachment.durationMs,
    localPath: completedAttachment.localPath,
    downloadStatus: completedAttachment.downloadStatus,
    createdAt: expectedAttachment.createdAt,
    waveform: completedAttachment.waveform,
    uploadRetryCount: expectedAttachment.uploadRetryCount,
    downloadRetryCount: expectedAttachment.downloadRetryCount,
    contentHash: completedAttachment.contentHash,
    thumbnailHash: expectedAttachment.thumbnailHash,
    encryptionKeyBase64: completedAttachment.encryptionKeyBase64,
    encryptionNonce: completedAttachment.encryptionNonce,
    encryptionScheme: completedAttachment.encryptionScheme,
    ownerLane: expectedAttachment.ownerLane,
    isBookmarked: expectedAttachment.isBookmarked,
    lastPlaybackPositionMs: expectedAttachment.lastPlaybackPositionMs,
  );
}
