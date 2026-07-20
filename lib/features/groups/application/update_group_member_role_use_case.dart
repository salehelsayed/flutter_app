import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_membership_event_watermark.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/groups/application/group_role_update_authorization.dart';
// Single canonical source for these shared membership-mutation messages to
// avoid the duplicate-declaration ambiguity between add/remove use cases.
import 'package:flutter_app/features/groups/application/remove_group_member_use_case.dart'
    show
        groupMembershipMutationDissolvedMessage,
        staleGroupMembershipEventMessage;
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

const lastAdminRoleChangeBlockedMessage =
    "You can't remove the last admin from this group.";

/// Updates a member role after group creation and synchronizes the new
/// authoritative config with the bridge validator.
///
/// Returns the canonical `(eventAt, eventId)` pair the mutation minted and
/// recorded in the local membership watermark, so the caller can publish the
/// SAME pair in the signed audit (keeping the local watermark id consistent
/// with the wire id for deterministic equal-instant convergence). Returns
/// `null` when the call is a no-op (the target already holds [role]).
Future<({DateTime eventAt, String eventId})?> updateGroupMemberRole({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required String groupId,
  required String memberPeerId,
  required MemberRole role,
  required String selfPeerId,
  DateTime? eventAt,
  Future<void> Function()? beforeCommit,
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

  // Serialize the whole read-modify-write under the shared per-group
  // membership lock so concurrent add/remove/role mutations cannot lose
  // updates on the admin-count math or the watermark. The recovery gate stays
  // outside the lock, mirroring add/remove.
  return runGroupMembershipMutationLocked<
    ({DateTime eventAt, String eventId})?
  >(
    groupId: groupId,
    action: () async {
      final group = await groupRepo.getGroup(groupId);
      if (group == null) {
        throw StateError('Group not found: $groupId');
      }
      if (group.isDissolved) {
        throw StateError(groupMembershipMutationDissolvedMessage);
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
          event:
              'GROUP_UPDATE_MEMBER_ROLE_USE_CASE_PERMISSION_ESCALATION_BLOCKED',
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
        return null;
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

      // Stale gate (mirrors add/remove): an *explicit* caller that hands us an
      // older-or-equal event is rejected. The live local-admin path passes no
      // eventAt and is instead lifted past a skew-advanced watermark by the
      // monotonic mint below, so it never self-blocks.
      final providedEventAt = eventAt?.toUtc();
      if (providedEventAt != null &&
          isStaleGroupMembershipEvent(
            eventAt: providedEventAt,
            lastMembershipEventAt: group.lastMembershipEventAt,
          )) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_UPDATE_MEMBER_ROLE_USE_CASE_STALE_EVENT',
          details: {
            'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
            'peerId': memberPeerId.length > 8
                ? memberPeerId.substring(0, 8)
                : memberPeerId,
            'eventAt': providedEventAt.toIso8601String(),
          },
        );
        throw StateError(staleGroupMembershipEventMessage);
      }
      final normalizedEventAt = nextMembershipEventAt(
        group.lastMembershipEventAt,
        now: providedEventAt,
      );
      final mintedEventId = canonicalMembershipEventId(
        transitionType: 'member_role_updated',
        groupId: groupId,
        actorPeerId: selfPeerId,
        eventAt: normalizedEventAt,
      );

      final previousMyRole = group.myRole;
      final updatedMyRole = memberPeerId == selfPeerId
          ? (role == MemberRole.admin ? GroupRole.admin : GroupRole.member)
          : group.myRole;

      // Extracted signed role transitions use this final in-lock check to
      // revalidate external join evidence after signing but before the first
      // role/config/watermark write.
      await beforeCommit?.call();

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
          eventId: mintedEventId,
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
        return (eventAt: normalizedEventAt, eventId: mintedEventId);
      } catch (error) {
        await groupRepo.updateMemberRole(
          groupId,
          memberPeerId,
          targetMember.role,
        );
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
    },
  );
}
