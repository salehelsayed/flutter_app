import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_membership_event_watermark.dart';
import 'package:flutter_app/features/groups/application/group_membership_timeline_message.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

const lastAdminRemovalBlockedMessage =
    "You can't remove the last admin from this group.";
const removeAdminRoleBoundaryBlockedMessage =
    'Only admins can remove admins or manage role boundaries';
const groupMembershipMutationDissolvedMessage =
    'Cannot mutate membership of a dissolved group';
const staleGroupMembershipEventMessage = 'Stale group membership event';

class PreparedGroupMemberRemovalAuthority {
  const PreparedGroupMemberRemovalAuthority({
    required this.activate,
    required this.rollback,
  });

  final Future<void> Function() activate;
  final Future<void> Function() rollback;
}

/// The protected member-removal projection may have committed even though a
/// repository projection, native config response, or local watermark write
/// failed. The durable PREPARED transition remains the restart repair owner.
class GroupMemberRemovalCommitAmbiguous implements Exception {
  const GroupMemberRemovalCommitAmbiguous({
    required this.cause,
    this.rollbackError,
  });

  final Object cause;
  final Object? rollbackError;

  @override
  String toString() {
    final rollback = rollbackError;
    return rollback == null
        ? 'Group member removal commit outcome is ambiguous: $cause'
        : 'Group member removal commit outcome is ambiguous: $cause; '
              'local rollback or durable abort also failed: $rollback';
  }
}

typedef PrepareGroupMemberRemovalAuthority =
    Future<PreparedGroupMemberRemovalAuthority?> Function({
      required GroupModel group,
      required List<GroupMember> members,
      required GroupMember removedMember,
      required DateTime eventAt,
      required String eventId,
    });

bool _memberAllows(
  GroupMember? member,
  GroupRole fallbackRole,
  GroupMemberPermission permission,
) {
  return member != null
      ? member.permissions.allows(permission, member.role)
      : fallbackRole == GroupRole.admin;
}

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
/// Returns the canonical `(eventAt, eventId)` pair the removal minted and
/// recorded in the local membership watermark, so the caller can publish the
/// SAME pair in the signed audit (keeping the local watermark id consistent
/// with the wire id for deterministic equal-instant convergence).
Future<({DateTime eventAt, String eventId})> removeGroupMember({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required String groupId,
  required String memberPeerId,
  String? selfPeerId,
  String? actorUsername,
  DateTime? eventAt,
  GroupMessageRepository? msgRepo,
  PrepareGroupMemberRemovalAuthority? prepareAuthority,
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

  if (isGroupRecoveryInProgress()) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REMOVE_MEMBER_USE_CASE_RECOVERY_PENDING',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'peerId': memberPeerId.length > 8
            ? memberPeerId.substring(0, 8)
            : memberPeerId,
      },
    );
    throw StateError(groupRecoveryPendingError);
  }

  return runGroupMembershipMutationLocked<({DateTime eventAt, String eventId})>(
    groupId: groupId,
    action: () async {
      // 1. Load group, verify caller is admin
      final group = await groupRepo.getGroup(groupId);
      if (group == null) {
        throw StateError('Group not found: $groupId');
      }
      if (group.isDissolved) {
        throw StateError(groupMembershipMutationDissolvedMessage);
      }

      final selfMember = selfPeerId == null
          ? null
          : await groupRepo.getMember(groupId, selfPeerId);
      final canRemove = _memberAllows(
        selfMember,
        group.myRole,
        GroupMemberPermission.removeMembers,
      );
      final canManageRoles = _memberAllows(
        selfMember,
        group.myRole,
        GroupMemberPermission.manageRoles,
      );
      if (!canRemove) {
        throw StateError(
          'Only admins can remove members unless remove permission is granted',
        );
      }

      // Stale gate for an *explicit* older-or-equal event; the live caller
      // passes no eventAt and is lifted past a skew-advanced watermark by the
      // monotonic mint below (never self-blocks).
      final providedEventAt = eventAt?.toUtc();
      if (providedEventAt != null &&
          isStaleGroupMembershipEvent(
            eventAt: providedEventAt,
            lastMembershipEventAt: group.lastMembershipEventAt,
          )) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_REMOVE_MEMBER_USE_CASE_STALE_EVENT',
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
        transitionType: 'member_removed',
        groupId: groupId,
        actorPeerId: selfPeerId ?? group.createdBy,
        eventAt: normalizedEventAt,
      );

      final removedMember = await groupRepo.getMember(groupId, memberPeerId);
      if (removedMember == null) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_REMOVE_MEMBER_USE_CASE_MEMBER_NOT_FOUND',
          details: {
            'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
            'peerId': memberPeerId.length > 8
                ? memberPeerId.substring(0, 8)
                : memberPeerId,
          },
        );
        throw StateError('Member not found');
      }

      if (removedMember.role == MemberRole.admin) {
        if (!canManageRoles) {
          emitFlowEvent(
            layer: 'FL',
            event: 'GROUP_REMOVE_MEMBER_USE_CASE_ROLE_BOUNDARY_BLOCKED',
            details: {
              'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
              'peerId': memberPeerId.length > 8
                  ? memberPeerId.substring(0, 8)
                  : memberPeerId,
            },
          );
          throw StateError(removeAdminRoleBoundaryBlockedMessage);
        }
        final members = await groupRepo.getMembers(groupId);
        final adminCount = members
            .where((member) => member.role == MemberRole.admin)
            .length;
        if (adminCount <= 1) {
          emitFlowEvent(
            layer: 'FL',
            event: 'GROUP_REMOVE_MEMBER_USE_CASE_LAST_ADMIN_BLOCKED',
            details: {
              'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
              'peerId': memberPeerId.length > 8
                  ? memberPeerId.substring(0, 8)
                  : memberPeerId,
            },
          );
          throw StateError(lastAdminRemovalBlockedMessage);
        }
      }

      final snapshotRepo = groupRepo is RemovedGroupMemberSnapshotRepository
          ? groupRepo as RemovedGroupMemberSnapshotRepository
          : null;
      if (snapshotRepo == null) {
        throw StateError(
          'Removed-member snapshot repository capability required',
        );
      }

      GroupMessage? removalCutoffMessage;
      if (msgRepo != null) {
        removalCutoffMessage = buildMemberRemovedTimelineMessage(
          groupId: groupId,
          removedPeerId: memberPeerId,
          removedUsername: removedMember.username,
          senderId: selfPeerId ?? group.createdBy,
          senderUsername: actorUsername ?? '',
          eventAt: normalizedEventAt,
        );
        await msgRepo.saveMessage(removalCutoffMessage);
      }

      await snapshotRepo.saveRemovedMemberSnapshot(
        removedMember,
        removedAt: normalizedEventAt,
      );

      final membersBeforeRemoval = await groupRepo.getMembers(groupId);
      final preparedAuthority = await prepareAuthority?.call(
        group: group,
        members: membersBeforeRemoval,
        removedMember: removedMember,
        eventAt: normalizedEventAt,
        eventId: mintedEventId,
      );

      late final List<GroupMember> remainingMembers;
      try {
        // 2. Remove member from local DB.
        await groupRepo.removeMember(groupId, memberPeerId);

        // 3. Build updated GroupConfig from remaining members and update Go config.
        remainingMembers = await groupRepo.getMembers(groupId);
        final groupConfig = buildGroupConfigPayload(
          group.copyWith(lastMembershipEventAt: normalizedEventAt),
          remainingMembers,
          configVersionOverride: normalizedEventAt,
        );
        await callGroupUpdateConfig(
          bridge,
          groupId: groupId,
          groupConfig: groupConfig,
        );
        await recordGroupMembershipEventWatermark(
          groupRepo: groupRepo,
          groupId: groupId,
          eventAt: normalizedEventAt,
          eventId: mintedEventId,
        );
      } catch (e, stackTrace) {
        // GroupRepositoryImpl deletes SQL before its fallible external
        // projection. An error from removeMember itself is therefore just as
        // ambiguous as timeout/transport loss or a post-native watermark
        // failure. The sole definite native rejection is BridgeCommandException.
        if (preparedAuthority != null && e is! BridgeCommandException) {
          emitFlowEvent(
            layer: 'FL',
            event: 'GROUP_REMOVE_MEMBER_USE_CASE_COMMIT_AMBIGUOUS',
            details: {
              'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
              'memberPeerId': memberPeerId.length > 8
                  ? memberPeerId.substring(0, 8)
                  : memberPeerId,
            },
          );
          Error.throwWithStackTrace(
            GroupMemberRemovalCommitAmbiguous(cause: e),
            stackTrace,
          );
        }

        Object? rollbackError;
        try {
          await groupRepo.saveMember(removedMember);
          if (removalCutoffMessage != null) {
            await msgRepo?.deleteMessage(removalCutoffMessage.id);
          }
          // Abort only after the exact pre-removal local shape is restored.
          await preparedAuthority?.rollback();
        } catch (rollbackFailure) {
          rollbackError = rollbackFailure;
        }
        emitFlowEvent(
          layer: 'FL',
          event: rollbackError == null
              ? 'GROUP_REMOVE_MEMBER_USE_CASE_REVERTED'
              : 'GROUP_REMOVE_MEMBER_USE_CASE_COMMIT_AMBIGUOUS',
          details: {
            'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
            'memberPeerId': memberPeerId.length > 8
                ? memberPeerId.substring(0, 8)
                : memberPeerId,
            'rollbackFailed': rollbackError != null,
          },
        );
        if (rollbackError != null && preparedAuthority != null) {
          Error.throwWithStackTrace(
            GroupMemberRemovalCommitAmbiguous(
              cause: e,
              rollbackError: rollbackError,
            ),
            stackTrace,
          );
        }
        Error.throwWithStackTrace(e, stackTrace);
      }
      try {
        await preparedAuthority?.activate();
      } catch (error, stackTrace) {
        // The durable protected row remains the retry owner. Surface the
        // unresolved COMPLETE boundary so callers stop ordinary publish/fanout;
        // the local removal and native ACL commit are never rolled back.
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_REMOVE_MEMBER_PROTECTED_ACTIVATION_DEFERRED',
          details: {
            'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
            'memberPeerId': memberPeerId.length > 8
                ? memberPeerId.substring(0, 8)
                : memberPeerId,
            'error': error.toString(),
          },
        );
        Error.throwWithStackTrace(
          GroupMemberRemovalCommitAmbiguous(cause: error),
          stackTrace,
        );
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
      return (eventAt: normalizedEventAt, eventId: mintedEventId);
    },
  );
}
