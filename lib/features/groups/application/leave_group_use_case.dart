import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

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
