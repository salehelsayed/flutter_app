import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/utils/group_group_messages_into_threads.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

Future<GroupThreadFeedItem?> loadGroupFeedSnapshot({
  required GroupRepository groupRepo,
  required GroupMessageRepository groupMsgRepo,
  required String groupId,
}) async {
  final group = await groupRepo.getGroup(groupId);
  if (group == null || group.isArchived) return null;

  final messages = await groupMsgRepo.getMessagesPage(groupId, limit: 200);
  if (messages.isEmpty) return null;

  return groupGroupMessagesIntoThreads(
    allGroupMessages: messages,
    groups: [group],
  ).firstOrNull;
}
