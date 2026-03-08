import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
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

  List<GroupMessage> messages =
      await groupMsgRepo.getMessagesPage(groupId, limit: 200);
  if (messages.isEmpty) return null;

  // Batch-attach media to group messages, resolving relative paths
  if (mediaAttachmentRepo != null && messages.isNotEmpty) {
    final ids = messages.map((m) => m.id).toList();
    final mediaMap = await mediaAttachmentRepo.getAttachmentsForMessages(ids);
    if (mediaMap.isNotEmpty) {
      final resolvedMap = <String, List<MediaAttachment>>{};
      if (mediaFileManager != null) {
        for (final entry in mediaMap.entries) {
          final resolved = <MediaAttachment>[];
          for (final a in entry.value) {
            if (a.localPath != null) {
              final absPath = await mediaFileManager.resolveStoredPath(
                a.localPath!,
              );
              resolved.add(a.copyWith(localPath: absPath));
            } else {
              resolved.add(a);
            }
          }
          resolvedMap[entry.key] = resolved;
        }
      }

      final effectiveMap = mediaFileManager != null ? resolvedMap : mediaMap;
      messages = messages
          .map((m) => m.copyWith(media: effectiveMap[m.id] ?? const []))
          .toList();
    }
  }

  return groupGroupMessagesIntoThreads(
    allGroupMessages: messages,
    groups: [group],
  ).firstOrNull;
}
