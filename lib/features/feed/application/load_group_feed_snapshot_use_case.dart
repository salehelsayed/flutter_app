import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/feed/application/group_feed_media_verification.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/utils/group_group_messages_into_threads.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_thread_preview_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

/// Rebuilds a single group's collapsed feed card (used by every per-event
/// refresh: send / live message / nav-return).
///
/// When [pageSize] is provided (161 db-persistence-5), the card is loaded
/// through a bounded NEWEST-first page and its counts/state come from the
/// batched [GroupThreadPreview] (via the cast) so a deep group is not
/// undercounted by the page bound and a just-sent reply stays visible. The
/// pending-filter is NOT applied here (a focused/answered group still rebuilds,
/// so append-stay keeps the reply). [pageSize] null keeps the legacy unbounded
/// behaviour for parity callers.
Future<GroupThreadFeedItem?> loadGroupFeedSnapshot({
  required GroupRepository groupRepo,
  required GroupMessageRepository groupMsgRepo,
  required String groupId,
  int? pageSize,
  MediaAttachmentRepository? mediaAttachmentRepo,
  MediaFileManager? mediaFileManager,
}) async {
  final group = await groupRepo.getGroup(groupId);
  if (group == null || group.isArchived) return null;

  List<GroupMessage> messages = await groupMsgRepo.getMessagesPage(
    groupId,
    limit: pageSize ?? 200,
  );
  if (messages.isEmpty) return null;

  final totalMessageCounts = <String, int>{};
  final unreadCounts = <String, int>{};
  final lastOutgoingAtByGroup = <String, DateTime?>{};
  if (pageSize != null && groupMsgRepo is GroupThreadPreviewRepository) {
    final preview = await (groupMsgRepo as GroupThreadPreviewRepository)
        .getGroupThreadPreview(groupId);
    totalMessageCounts[groupId] = preview.messageCount;
    unreadCounts[groupId] = preview.unreadCount;
    lastOutgoingAtByGroup[groupId] = preview.lastOutgoingAt;
  }

  // Batch-attach media to group messages, resolving relative paths
  if (mediaAttachmentRepo != null && messages.isNotEmpty) {
    final ids = messages
        .where(groupMessageAllowsOrdinaryFeedDerivatives)
        .map((message) => message.id)
        .toList();
    if (ids.isNotEmpty) {
      final mediaMap = await mediaAttachmentRepo.getAttachmentsForMessages(
        ids,
        owner: MediaOwnerLane.group,
      );
      if (mediaMap.isNotEmpty) {
        final resolvedMap = <String, List<MediaAttachment>>{};
        for (final entry in mediaMap.entries) {
          resolvedMap[entry.key] = await resolveGroupFeedMediaForDisplay(
            attachments: entry.value,
            mediaFileManager: mediaFileManager,
          );
        }

        messages = messages
            .map((m) => m.copyWith(media: resolvedMap[m.id] ?? const []))
            .toList();
      }
    }
  }

  messages = messages.map(projectGroupMessageForFeed).toList();

  return groupGroupMessagesIntoThreads(
    allGroupMessages: messages,
    groups: [group],
    totalMessageCounts: totalMessageCounts,
    unreadCounts: unreadCounts,
    lastOutgoingAtByGroup: lastOutgoingAtByGroup,
  ).firstOrNull;
}
