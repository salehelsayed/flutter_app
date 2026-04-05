import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

Future<GroupModel> setGroupMuted({
  required GroupRepository groupRepo,
  required String groupId,
  required bool isMuted,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_SET_MUTED_USE_CASE_BEGIN',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'isMuted': isMuted,
    },
  );

  final group = await groupRepo.getGroup(groupId);
  if (group == null) {
    throw StateError('Group not found: $groupId');
  }

  if (group.isMuted == isMuted) {
    return group;
  }

  final updated = group.copyWith(isMuted: isMuted);
  await groupRepo.updateGroup(updated);

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_SET_MUTED_USE_CASE_SUCCESS',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'isMuted': isMuted,
    },
  );

  return updated;
}
