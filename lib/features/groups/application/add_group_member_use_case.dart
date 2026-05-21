import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_membership_event_watermark.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_membership_limit_policy.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

bool _sameOptionalString(String? left, String? right) {
  String? normalize(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  return normalize(left) == normalize(right);
}

bool _sameOptionalDateTime(DateTime? left, DateTime? right) {
  if (left == null || right == null) return left == right;
  return left.toUtc().isAtSameMomentAs(right.toUtc());
}

bool _samePermissions(
  GroupMemberPermissions left,
  GroupMemberPermissions right,
) {
  return left.inviteMembers == right.inviteMembers &&
      left.removeMembers == right.removeMembers &&
      left.manageRoles == right.manageRoles &&
      left.rotateKeys == right.rotateKeys &&
      left.editMetadata == right.editMetadata &&
      left.pinMessages == right.pinMessages &&
      left.deleteMessages == right.deleteMessages;
}

bool _sameDeviceIdentity(
  GroupMemberDeviceIdentity left,
  GroupMemberDeviceIdentity right,
) {
  return left.deviceId == right.deviceId &&
      left.transportPeerId == right.transportPeerId &&
      left.deviceSigningPublicKey == right.deviceSigningPublicKey &&
      _sameOptionalString(left.mlKemPublicKey, right.mlKemPublicKey) &&
      _sameOptionalString(left.keyPackageId, right.keyPackageId) &&
      _sameOptionalString(
        left.keyPackagePublicMaterial,
        right.keyPackagePublicMaterial,
      ) &&
      left.status == right.status &&
      _sameOptionalDateTime(left.revokedAt, right.revokedAt);
}

bool _sameDeviceSet(
  List<GroupMemberDeviceIdentity> left,
  List<GroupMemberDeviceIdentity> right,
) {
  if (left.isEmpty || right.isEmpty || left.length != right.length) {
    return false;
  }
  final rightByDeviceId = {for (final device in right) device.deviceId: device};
  if (rightByDeviceId.length != right.length) return false;
  for (final leftDevice in left) {
    final rightDevice = rightByDeviceId[leftDevice.deviceId];
    if (rightDevice == null || !_sameDeviceIdentity(leftDevice, rightDevice)) {
      return false;
    }
  }
  return true;
}

bool _isIdenticalDuplicateMemberAdd({
  required GroupMember existingMember,
  required GroupMember newMember,
}) {
  return existingMember.groupId == newMember.groupId &&
      existingMember.peerId == newMember.peerId &&
      _sameOptionalString(existingMember.username, newMember.username) &&
      existingMember.role == newMember.role &&
      _samePermissions(existingMember.permissions, newMember.permissions) &&
      _sameOptionalString(existingMember.publicKey, newMember.publicKey) &&
      _sameOptionalString(
        existingMember.mlKemPublicKey,
        newMember.mlKemPublicKey,
      ) &&
      _sameDeviceSet(existingMember.devices, newMember.devices) &&
      existingMember.joinedAt.toUtc().isAtSameMomentAs(
        newMember.joinedAt.toUtc(),
      );
}

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

  if (isGroupRecoveryInProgress()) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_ADD_MEMBER_USE_CASE_RECOVERY_PENDING',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      },
    );
    throw StateError(groupRecoveryPendingError);
  }

  // 1. Load group, verify caller is admin
  final group = await groupRepo.getGroup(groupId);
  if (group == null) {
    throw StateError('Group not found: $groupId');
  }

  final selfMember = await groupRepo.getMember(groupId, selfPeerId);
  final canInvite = selfMember != null
      ? selfMember.permissions.allows(
          GroupMemberPermission.inviteMembers,
          selfMember.role,
        )
      : group.myRole == GroupRole.admin;
  if (!canInvite) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_ADD_MEMBER_USE_CASE_NOT_ADMIN',
      details: {'role': group.myRole.toValue()},
    );
    throw StateError(
      'Only admins can add members unless invite permission is granted',
    );
  }

  final memberToAdd = newMember.copyWith(peerId: newMember.peerId.trim());
  if (!hasDeliverableGroupMemberIdentity(memberToAdd)) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_ADD_MEMBER_USE_CASE_INVALID_INVITE_TARGET',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'peerId': memberToAdd.peerId.length > 8
            ? memberToAdd.peerId.substring(0, 8)
            : memberToAdd.peerId,
      },
    );
    throw StateError('Cannot add group member without a delivery identity');
  }

  final existingMember = await groupRepo.getMember(groupId, memberToAdd.peerId);
  if (existingMember != null) {
    if (_isIdenticalDuplicateMemberAdd(
      existingMember: existingMember,
      newMember: memberToAdd,
    )) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_ADD_MEMBER_USE_CASE_DUPLICATE_IDEMPOTENT',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          'peerId': memberToAdd.peerId.length > 8
              ? memberToAdd.peerId.substring(0, 8)
              : memberToAdd.peerId,
        },
      );
      return;
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_ADD_MEMBER_USE_CASE_ALREADY_MEMBER',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'peerId': memberToAdd.peerId.length > 8
            ? memberToAdd.peerId.substring(0, 8)
            : memberToAdd.peerId,
      },
    );
    throw StateError('Member already exists');
  }

  final currentMembers = await groupRepo.getMembers(groupId);
  ensureWithinGroupMembershipLimit(
    currentMemberCount: currentMembers.length,
    requestedAdditionalMembers: 1,
  );

  final keyMaterialRejectReason = groupMemberKeyMaterialRejectReason(
    memberToAdd,
  );
  if (keyMaterialRejectReason != null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_ADD_MEMBER_USE_CASE_INVALID_KEY_MATERIAL',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'peerId': memberToAdd.peerId.length > 8
            ? memberToAdd.peerId.substring(0, 8)
            : memberToAdd.peerId,
        'reason': keyMaterialRejectReason,
      },
    );
    throw ArgumentError(
      'Invalid group member key material: $keyMaterialRejectReason',
    );
  }

  // 2. Save member to repo
  await groupRepo.saveMember(memberToAdd);

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
        'peerId': memberToAdd.peerId.length > 8
            ? memberToAdd.peerId.substring(0, 8)
            : memberToAdd.peerId,
      },
    );
    return;
  }

  final allMembers = await groupRepo.getMembers(groupId);
  final membershipEventAt = memberToAdd.joinedAt.toUtc();
  final groupConfig = buildGroupConfigPayload(
    group.copyWith(lastMembershipEventAt: membershipEventAt),
    allMembers,
    configVersionOverride: membershipEventAt,
  );

  try {
    await callGroupUpdateConfig(
      bridge,
      groupId: groupId,
      groupConfig: groupConfig,
    );
    await recordGroupMembershipEventWatermark(
      groupRepo: groupRepo,
      groupId: groupId,
      eventAt: membershipEventAt,
    );

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_ADD_MEMBER_USE_CASE_SUCCESS',
      details: {
        'peerId': memberToAdd.peerId.length > 8
            ? memberToAdd.peerId.substring(0, 8)
            : memberToAdd.peerId,
      },
    );
  } catch (e) {
    await groupRepo.removeMember(groupId, memberToAdd.peerId);
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_ADD_MEMBER_USE_CASE_REVERTED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'peerId': memberToAdd.peerId.length > 8
            ? memberToAdd.peerId.substring(0, 8)
            : memberToAdd.peerId,
      },
    );
    rethrow;
  }
}
