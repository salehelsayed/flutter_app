import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/feed/application/group_feed_media_verification.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/utils/group_group_messages_into_threads.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

Future<GroupThreadFeedItem?> loadGroupFeedSnapshot({
  required GroupRepository groupRepo,
  required GroupMessageRepository groupMsgRepo,
  required String groupId,
  MediaAttachmentRepository? mediaAttachmentRepo,
  MediaFileManager? mediaFileManager,
}) async {
  final group = await groupRepo.getGroup(groupId);
  if (group == null || group.isArchived) return null;

  List<GroupMessage> messages = await groupMsgRepo.getMessagesPage(
    groupId,
    limit: 200,
  );
  if (messages.isEmpty) return null;

  // Batch-attach media to group messages, resolving relative paths
  if (mediaAttachmentRepo != null && messages.isNotEmpty) {
    final ids = messages.map((m) => m.id).toList();
    final mediaMap = await mediaAttachmentRepo.getAttachmentsForMessages(ids);
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

  return groupGroupMessagesIntoThreads(
    allGroupMessages: messages,
    groups: [group],
  ).firstOrNull;
}
