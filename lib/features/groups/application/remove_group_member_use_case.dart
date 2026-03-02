import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

/// Removes a member from a group, rotates the group key, and returns the
/// new key info for distribution to remaining members.
///
/// The caller must be an admin of the group.
Future<GroupKeyInfo> removeGroupMember({
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

  // 2. Remove member from repo
  await groupRepo.removeMember(groupId, memberPeerId);

  // 3. Rotate key via bridge
  final rotateResult = await callGroupRotateKey(bridge, groupId);
  if (rotateResult['ok'] != true) {
    throw Exception(
      rotateResult['errorMessage'] ?? 'Failed to rotate group key',
    );
  }

  // 4. Save new key to repo
  final newKeyGeneration = rotateResult['keyGeneration'] as int? ?? 1;
  final newEncryptedKey = rotateResult['encryptedKey'] as String? ?? '';
  final now = DateTime.now().toUtc();

  final newKeyInfo = GroupKeyInfo(
    groupId: groupId,
    keyGeneration: newKeyGeneration,
    encryptedKey: newEncryptedKey,
    createdAt: now,
  );
  await groupRepo.saveKey(newKeyInfo);

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_REMOVE_MEMBER_USE_CASE_SUCCESS',
    details: {'newKeyGeneration': newKeyGeneration},
  );

  return newKeyInfo;
}
