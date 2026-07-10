import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/models/media_preview_descriptor.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';

/// Loads [MediaPreviewDescriptor]s for a set of latest-message ids, used by the
/// orbit friend/group loaders to label a media-only latest message.
///
/// 228: [owner] names the lane the ids belong to — the friend loader passes
/// [MediaOwnerLane.direct], the group loader [MediaOwnerLane.group] — so a
/// same-ID sibling in the other lane can never label the wrong preview.
///
/// Prefers the key-free [MediaPreviewDescriptorLookup] fast path; falls back to
/// `getAttachmentsForMessages` (correct, but hydrates keys) when the repo does
/// not implement it — so test fakes need no new method. Returns an empty map
/// when no repo is supplied or there is nothing to look up.
Future<Map<String, MediaPreviewDescriptor>> loadLatestMediaDescriptors({
  required MediaAttachmentRepository? mediaAttachmentRepo,
  required List<String> messageIds,
  required MediaOwnerLane owner,
}) async {
  if (mediaAttachmentRepo == null || messageIds.isEmpty) {
    return const <String, MediaPreviewDescriptor>{};
  }

  final repo = mediaAttachmentRepo;
  if (repo is MediaPreviewDescriptorLookup) {
    return (repo as MediaPreviewDescriptorLookup).getMediaPreviewDescriptors(
      messageIds,
      owner: owner,
    );
  }

  final byMessage = await repo.getAttachmentsForMessages(
    messageIds,
    owner: owner,
  );
  final result = <String, MediaPreviewDescriptor>{};
  byMessage.forEach((messageId, attachments) {
    final descriptor = MediaPreviewDescriptor.fromAttachments(attachments);
    if (descriptor != null) result[messageId] = descriptor;
  });
  return result;
}
