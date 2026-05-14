import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_membership_event_watermark.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/groups/application/group_role_update_authorization.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

const lastAdminRoleChangeBlockedMessage =
    "You can't remove the last admin from this group.";

/// Updates a member role after group creation and synchronizes the new
/// authoritative config with the bridge validator.
Future<void> updateGroupMemberRole({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required String groupId,
  required String memberPeerId,
  required MemberRole role,
  required String selfPeerId,
  DateTime? eventAt,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_UPDATE_MEMBER_ROLE_USE_CASE_BEGIN',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'peerId': memberPeerId.length > 8
          ? memberPeerId.substring(0, 8)
          : memberPeerId,
      'role': role.toValue(),
    },
  );

  if (isGroupRecoveryInProgress()) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_UPDATE_MEMBER_ROLE_USE_CASE_RECOVERY_PENDING',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      },
    );
    throw StateError(groupRecoveryPendingError);
  }

  final group = await groupRepo.getGroup(groupId);
  if (group == null) {
    throw StateError('Group not found: $groupId');
  }

  final selfMember = await groupRepo.getMember(groupId, selfPeerId);
  final canManageRoles = selfMember != null
      ? selfMember.permissions.allows(
          GroupMemberPermission.manageRoles,
          selfMember.role,
        )
      : group.myRole == GroupRole.admin;
  if (!canManageRoles) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_UPDATE_MEMBER_ROLE_USE_CASE_NOT_ADMIN',
      details: {'role': group.myRole.toValue()},
    );
    throw StateError(
      'Only admins can manage member roles unless role-management permission is granted',
    );
  }

  final targetMember = await groupRepo.getMember(groupId, memberPeerId);
  if (targetMember == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_UPDATE_MEMBER_ROLE_USE_CASE_MEMBER_NOT_FOUND',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'peerId': memberPeerId.length > 8
            ? memberPeerId.substring(0, 8)
            : memberPeerId,
      },
    );
    throw StateError('Member not found');
  }

  if (selfMember != null &&
      !canApplyGroupMemberRoleUpdate(
        actor: selfMember,
        newRole: role,
        existingRole: targetMember.role,
        existingPermissions: targetMember.permissions,
      )) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_UPDATE_MEMBER_ROLE_USE_CASE_PERMISSION_ESCALATION_BLOCKED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'peerId': memberPeerId.length > 8
            ? memberPeerId.substring(0, 8)
            : memberPeerId,
        'role': role.toValue(),
      },
    );
    throw StateError(permissionEscalationBlockedMessage);
  }

  if (targetMember.role == role) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_UPDATE_MEMBER_ROLE_USE_CASE_NOOP',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'peerId': memberPeerId.length > 8
            ? memberPeerId.substring(0, 8)
            : memberPeerId,
        'role': role.toValue(),
      },
    );
    return;
  }

  final members = await groupRepo.getMembers(groupId);
  final adminCountAfter = members.where((member) {
    if (member.peerId == memberPeerId) {
      return role == MemberRole.admin;
    }
    return member.role == MemberRole.admin;
  }).length;

  if (adminCountAfter == 0) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_UPDATE_MEMBER_ROLE_USE_CASE_LAST_ADMIN_BLOCKED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'peerId': memberPeerId.length > 8
            ? memberPeerId.substring(0, 8)
            : memberPeerId,
      },
    );
    throw StateError(lastAdminRoleChangeBlockedMessage);
  }

  final previousMyRole = group.myRole;
  final updatedMyRole = memberPeerId == selfPeerId
      ? (role == MemberRole.admin ? GroupRole.admin : GroupRole.member)
      : group.myRole;
  final normalizedEventAt = eventAt?.toUtc() ?? DateTime.now().toUtc();

  await groupRepo.updateMemberRole(groupId, memberPeerId, role);
  if (updatedMyRole != group.myRole) {
    await groupRepo.updateGroup(group.copyWith(myRole: updatedMyRole));
  }

  try {
    final updatedMembers = await groupRepo.getMembers(groupId);
    await callGroupUpdateConfig(
      bridge,
      groupId: groupId,
      groupConfig: buildGroupConfigPayload(
        group.copyWith(lastMembershipEventAt: normalizedEventAt),
        updatedMembers,
        configVersionOverride: normalizedEventAt,
      ),
    );
    await recordGroupMembershipEventWatermark(
      groupRepo: groupRepo,
      groupId: groupId,
      eventAt: normalizedEventAt,
    );

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_UPDATE_MEMBER_ROLE_USE_CASE_SUCCESS',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'peerId': memberPeerId.length > 8
            ? memberPeerId.substring(0, 8)
            : memberPeerId,
        'role': role.toValue(),
      },
    );
  } catch (error) {
    await groupRepo.updateMemberRole(groupId, memberPeerId, targetMember.role);
    if (updatedMyRole != previousMyRole) {
      await groupRepo.updateGroup(group.copyWith(myRole: previousMyRole));
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_UPDATE_MEMBER_ROLE_USE_CASE_REVERTED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'peerId': memberPeerId.length > 8
            ? memberPeerId.substring(0, 8)
            : memberPeerId,
      },
    );
    rethrow;
  }
}
