import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

/// Adds a new member to a group.
///
/// The caller must be an admin of the group. Saves the member to the
/// local repository. Key distribution happens at a higher level via
/// 1:1 ML-KEM encrypted messages.
Future<void> addGroupMember({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required String groupId,
  required GroupMember newMember,
  required String selfPeerId,
  bool syncBridgeConfig = true,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_ADD_MEMBER_USE_CASE_BEGIN',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'peerId': newMember.peerId.length > 8
          ? newMember.peerId.substring(0, 8)
          : newMember.peerId,
    },
  );

  // 1. Load group, verify caller is admin
  final group = await groupRepo.getGroup(groupId);
  if (group == null) {
    throw StateError('Group not found: $groupId');
  }

  if (group.myRole != GroupRole.admin) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_ADD_MEMBER_USE_CASE_NOT_ADMIN',
      details: {'role': group.myRole.toValue()},
    );
    throw StateError('Only admins can add members');
  }

  // 2. Save member to repo
  await groupRepo.saveMember(newMember);

  if (!syncBridgeConfig) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_ADD_MEMBER_USE_CASE_SKIPPED_SYNC',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      },
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_ADD_MEMBER_USE_CASE_SUCCESS',
      details: {
        'peerId': newMember.peerId.length > 8
            ? newMember.peerId.substring(0, 8)
            : newMember.peerId,
      },
    );
    return;
  }

  final allMembers = await groupRepo.getMembers(groupId);

  final groupConfig = {
    'name': group.name,
    'groupType': group.type.toValue(),
    if (group.description != null) 'description': group.description,
    'members': allMembers
        .map(
          (m) => {
            'peerId': m.peerId,
            'username': m.username,
            'role': m.role.toValue(),
            'publicKey': m.publicKey,
            if (m.mlKemPublicKey != null) 'mlKemPublicKey': m.mlKemPublicKey,
          },
        )
        .toList(),
    'createdBy': group.createdBy,
    'createdAt': group.createdAt.toUtc().toIso8601String(),
  };

  try {
    await callGroupUpdateConfig(
      bridge,
      groupId: groupId,
      groupConfig: groupConfig,
    );

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_ADD_MEMBER_USE_CASE_SUCCESS',
      details: {
        'peerId': newMember.peerId.length > 8
            ? newMember.peerId.substring(0, 8)
            : newMember.peerId,
      },
    );
  } catch (e) {
    await groupRepo.removeMember(groupId, newMember.peerId);
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_ADD_MEMBER_USE_CASE_REVERTED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'peerId': newMember.peerId.length > 8
            ? newMember.peerId.substring(0, 8)
            : newMember.peerId,
      },
    );
    rethrow;
  }
}
