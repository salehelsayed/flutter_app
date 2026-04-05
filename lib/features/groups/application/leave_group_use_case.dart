import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

const lastAdminLeaveBlockedMessage =
    "You can't leave this group because you're the only admin.";

/// Leaves a group: unsubscribes from the topic and removes all local data.
Future<void> leaveGroup({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required String groupId,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_LEAVE_USE_CASE_BEGIN',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );

  final group = await groupRepo.getGroup(groupId);
  if (group?.myRole == GroupRole.admin) {
    final members = await groupRepo.getMembers(groupId);
    final adminCount = members
        .where((member) => member.role == MemberRole.admin)
        .length;

    if (adminCount == 1) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_LEAVE_USE_CASE_BLOCKED_LAST_ADMIN',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          'adminCount': adminCount,
        },
      );
      throw StateError(lastAdminLeaveBlockedMessage);
    }
  }

  // 1. Call bridge to leave the group topic
  await callGroupLeave(bridge, groupId);

  // 2. Remove all members from repo
  await groupRepo.removeAllMembers(groupId);

  // 3. Remove all keys from repo
  await groupRepo.removeAllKeys(groupId);

  // 4. Delete group from repo
  await groupRepo.deleteGroup(groupId);

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_LEAVE_USE_CASE_SUCCESS',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );
}
