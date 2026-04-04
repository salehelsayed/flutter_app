import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/push/application/prepare_notification_open_use_case.dart';

Future<void> prepareNotificationRouteTarget({
  required NotificationRouteTarget routeTarget,
  required Future<void> Function() drainOfflineInbox,
  required Bridge bridge,
  required GroupRepository? groupRepository,
  required GroupMessageRepository? groupMessageRepository,
  GroupMessageListener? groupMessageListener,
  required MediaAttachmentRepository mediaAttachmentRepository,
  required ReactionRepository? reactionRepository,
}) async {
  final result = await prepareNotificationOpen(
    routeTarget: routeTarget,
    drainOfflineInbox: drainOfflineInbox,
    drainGroupOfflineInboxForGroup: (groupId) async {
      final groupRepo = groupRepository;
      final groupMsgRepo = groupMessageRepository;
      if (groupRepo == null || groupMsgRepo == null) {
        throw StateError('group notification recovery is unavailable');
      }

      await drainGroupOfflineInboxForGroup(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: groupMsgRepo,
        groupId: groupId,
        groupMessageListener: groupMessageListener,
        mediaAttachmentRepo: mediaAttachmentRepository,
        reactionRepo: reactionRepository,
      );
    },
  );

  if (!result.ok) {
    throw StateError(result.error ?? 'notification open preparation failed');
  }
}
