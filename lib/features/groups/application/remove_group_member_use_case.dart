import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

/// Removes a member from a group and updates the Go topic validator config
/// so the removed member can no longer publish.
///
/// The caller must be an admin of the group. After this call, the caller
/// should broadcast a `member_removed` system message to remaining members
/// so they also update their local state and Go config.
///
/// Key rotation is intentionally NOT done here because the new key epoch
/// would cause signature mismatches at other members until they receive
/// the updated key. Key distribution should be handled separately.
Future<void> removeGroupMember({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required String groupId,
  required String memberPeerId,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_REMOVE_MEMBER_USE_CASE_BEGIN',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'peerId': memberPeerId.length > 8
          ? memberPeerId.substring(0, 8)
          : memberPeerId,
    },
  );

  // 1. Load group, verify caller is admin
  final group = await groupRepo.getGroup(groupId);
  if (group == null) {
    throw StateError('Group not found: $groupId');
  }

  if (group.myRole != GroupRole.admin) {
    throw StateError('Only admins can remove members');
  }

  final removedMember = await groupRepo.getMember(groupId, memberPeerId);

  // 2. Remove member from local DB
  await groupRepo.removeMember(groupId, memberPeerId);

  // 3. Build updated GroupConfig from remaining members and update Go config
  final remainingMembers = await groupRepo.getMembers(groupId);
  final groupConfig = {
    'name': group.name,
    'groupType': group.type.toValue(),
    if (group.description != null) 'description': group.description,
    'members': remainingMembers
        .map((m) => {
              'peerId': m.peerId,
              'username': m.username,
              'role': m.role.toValue(),
              'publicKey': m.publicKey,
              if (m.mlKemPublicKey != null) 'mlKemPublicKey': m.mlKemPublicKey,
            })
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
  } catch (e) {
    if (removedMember != null) {
      await groupRepo.saveMember(removedMember);
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REMOVE_MEMBER_USE_CASE_REVERTED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'memberPeerId': memberPeerId.length > 8
            ? memberPeerId.substring(0, 8)
            : memberPeerId,
      },
    );
    rethrow;
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_REMOVE_MEMBER_USE_CASE_SUCCESS',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'removedPeerId': memberPeerId.length > 8
          ? memberPeerId.substring(0, 8)
          : memberPeerId,
      'remainingMembers': remainingMembers.length,
    },
  );
}
