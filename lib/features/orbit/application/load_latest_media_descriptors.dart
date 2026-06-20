import 'package:flutter_app/features/conversation/domain/models/media_preview_descriptor.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';

/// Loads [MediaPreviewDescriptor]s for a set of latest-message ids, used by the
/// orbit friend/group loaders to label a media-only latest message.
///
/// Prefers the key-free [MediaPreviewDescriptorLookup] fast path; falls back to
/// `getAttachmentsForMessages` (correct, but hydrates keys) when the repo does
/// not implement it — so test fakes need no new method. Returns an empty map
/// when no repo is supplied or there is nothing to look up.
Future<Map<String, MediaPreviewDescriptor>> loadLatestMediaDescriptors({
  required MediaAttachmentRepository? mediaAttachmentRepo,
  required List<String> messageIds,
}) async {
  if (mediaAttachmentRepo == null || messageIds.isEmpty) {
    return const <String, MediaPreviewDescriptor>{};
  }

  final repo = mediaAttachmentRepo;
  if (repo is MediaPreviewDescriptorLookup) {
    return (repo as MediaPreviewDescriptorLookup).getMediaPreviewDescriptors(
      messageIds,
    );
  }

  final byMessage = await repo.getAttachmentsForMessages(messageIds);
  final result = <String, MediaPreviewDescriptor>{};
  byMessage.forEach((messageId, attachments) {
    final descriptor = MediaPreviewDescriptor.fromAttachments(attachments);
    if (descriptor != null) result[messageId] = descriptor;
  });
  return result;
}
