import 'package:flutter_app/features/groups/domain/models/group_invite_delivery_attempt.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

/// The action Orbit may safely offer after re-reading the group and its
/// membership state.
enum GroupExitDisposition {
  noOp,
  leave,
  soleAdminRecovery,
  pendingRoleSync,
  deleteDissolvedLocally,
  selfRemovedDeleteLocally,
}

class GroupExitSnapshot {
  const GroupExitSnapshot({
    required this.disposition,
    required this.group,
    required this.members,
    required this.eligibleSuccessors,
    required this.pendingRoleBroadcasts,
  });

  final GroupExitDisposition disposition;
  final GroupModel? group;
  final List<GroupMember> members;
  final List<GroupMember> eligibleSuccessors;
  final List<GroupPendingBroadcast> pendingRoleBroadcasts;

  bool get hasPendingRoleSync => pendingRoleBroadcasts.isNotEmpty;
}

/// Loads the authoritative state used by Orbit's group-exit action.
///
/// The row passed to Orbit is deliberately not accepted here: a swipe can stay
/// open while membership, dissolve, or retry state changes underneath it.
Future<GroupExitSnapshot> resolveGroupExitSnapshot({
  required GroupRepository groupRepo,
  required String groupId,
  required String selfPeerId,
  GroupMessageRepository? messageRepo,
  GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepo,
  Future<List<GroupPendingBroadcast>> Function(String groupId)?
  loadPendingBroadcasts,
}) async {
  final group = await groupRepo.getGroup(groupId);
  if (group == null) {
    return const GroupExitSnapshot(
      disposition: GroupExitDisposition.noOp,
      group: null,
      members: <GroupMember>[],
      eligibleSuccessors: <GroupMember>[],
      pendingRoleBroadcasts: <GroupPendingBroadcast>[],
    );
  }

  if (group.isDissolved) {
    return GroupExitSnapshot(
      disposition: GroupExitDisposition.deleteDissolvedLocally,
      group: group,
      members: const <GroupMember>[],
      eligibleSuccessors: const <GroupMember>[],
      pendingRoleBroadcasts: const <GroupPendingBroadcast>[],
    );
  }

  final selfRemovedAt = group.selfRemovedAt?.toUtc();
  final List<GroupMember> members;
  try {
    members = await groupRepo.getMembers(groupId);
  } catch (_) {
    if (selfRemovedAt == null) rethrow;
    // The fresh group row proves this is a marked membership instance, but a
    // failed roster read cannot prove that self is absent. Fail closed without
    // falling through to voluntary leave; a later retry will classify again.
    return GroupExitSnapshot(
      disposition: GroupExitDisposition.noOp,
      group: group,
      members: const <GroupMember>[],
      eligibleSuccessors: const <GroupMember>[],
      pendingRoleBroadcasts: const <GroupPendingBroadcast>[],
    );
  }
  final selfIsPresent = members.any((member) => member.peerId == selfPeerId);
  final membershipAdvancedAfterRemoval =
      selfRemovedAt != null &&
      (group.lastMembershipEventAt?.toUtc().isAfter(selfRemovedAt) ?? false);
  if (selfRemovedAt != null &&
      !selfIsPresent &&
      !membershipAdvancedAfterRemoval) {
    return GroupExitSnapshot(
      disposition: GroupExitDisposition.selfRemovedDeleteLocally,
      group: group,
      members: members,
      eligibleSuccessors: const <GroupMember>[],
      pendingRoleBroadcasts: const <GroupPendingBroadcast>[],
    );
  }

  final List<GroupPendingBroadcast> pending;
  try {
    pending = loadPendingBroadcasts == null
        ? const <GroupPendingBroadcast>[]
        : await loadPendingBroadcasts(groupId);
  } catch (_) {
    if (selfRemovedAt == null) rethrow;
    // A marker contradiction (restored self or newer membership) refuses the
    // local-delete branch, but a failed pending-state read must still not turn
    // the marked row into an ordinary voluntary-leave action.
    return GroupExitSnapshot(
      disposition: GroupExitDisposition.noOp,
      group: group,
      members: members,
      eligibleSuccessors: const <GroupMember>[],
      pendingRoleBroadcasts: const <GroupPendingBroadcast>[],
    );
  }
  final pendingRoleBroadcasts = pending
      .where(
        (broadcast) =>
            broadcast.groupId == groupId &&
            isPendingGroupMemberRoleBroadcastKind(broadcast.kind),
      )
      .toList(growable: false);

  if (pendingRoleBroadcasts.isNotEmpty) {
    return GroupExitSnapshot(
      disposition: GroupExitDisposition.pendingRoleSync,
      group: group,
      members: members,
      eligibleSuccessors: const <GroupMember>[],
      pendingRoleBroadcasts: pendingRoleBroadcasts,
    );
  }

  final hasAuthoritativePeerAdmin = members.any(
    (member) => member.peerId != selfPeerId && member.role == MemberRole.admin,
  );
  if (group.myRole != GroupRole.admin || hasAuthoritativePeerAdmin) {
    return GroupExitSnapshot(
      disposition: GroupExitDisposition.leave,
      group: group,
      members: members,
      eligibleSuccessors: const <GroupMember>[],
      pendingRoleBroadcasts: const <GroupPendingBroadcast>[],
    );
  }

  final attempts =
      await inviteDeliveryAttemptRepo?.getAttemptsForGroup(groupId) ??
      const <GroupInviteDeliveryAttempt>[];
  final attemptsByPeerId = <String, GroupInviteDeliveryAttempt>{
    for (final attempt in attempts) attempt.peerId: attempt,
  };
  final eligibleSuccessors = <GroupMember>[];
  for (final member in members) {
    if (member.peerId == selfPeerId || member.role == MemberRole.admin) {
      continue;
    }
    final joinedAt = await messageRepo?.getLatestSystemEventTimestampForTarget(
      groupId,
      eventType: 'member_joined',
      targetId: member.peerId,
    );
    final removedAt = await messageRepo?.getLatestSystemEventTimestampForTarget(
      groupId,
      eventType: 'member_removed',
      targetId: member.peerId,
    );
    if (hasCurrentGroupJoinEvidence(
      memberJoinedAt: joinedAt,
      memberRemovedAt: removedAt,
      inviteAttempt: attemptsByPeerId[member.peerId],
    )) {
      eligibleSuccessors.add(member);
    }
  }

  return GroupExitSnapshot(
    disposition: GroupExitDisposition.soleAdminRecovery,
    group: group,
    members: members,
    eligibleSuccessors: List<GroupMember>.unmodifiable(eligibleSuccessors),
    pendingRoleBroadcasts: const <GroupPendingBroadcast>[],
  );
}

/// Whether a non-admin roster row has current proof that the peer accepted the
/// latest membership attempt.
///
/// `GroupMember.joinedAt` and admin-authored add events are intentionally not
/// inputs. A peer-authored `member_joined` must be later than both removal and
/// a later re-invite. Without that event, only a current durable invite attempt
/// whose status is `joined` qualifies.
bool hasCurrentGroupJoinEvidence({
  required DateTime? memberJoinedAt,
  required DateTime? memberRemovedAt,
  required GroupInviteDeliveryAttempt? inviteAttempt,
}) {
  final joinedAt = memberJoinedAt?.toUtc();
  final removedAt = memberRemovedAt?.toUtc();
  if (joinedAt != null) {
    final attemptedAt = inviteAttempt?.attemptedAt.toUtc();
    final isCurrentJoinEvent =
        (removedAt == null || joinedAt.isAfter(removedAt)) &&
        (attemptedAt == null || joinedAt.isAfter(attemptedAt));
    if (isCurrentJoinEvent) {
      return true;
    }
    // A stale historical join does not mask a later durable attempt whose
    // own `joined` status proves acceptance of the current invitation.
  }

  if (inviteAttempt?.status != GroupInviteDeliveryStatus.joined) {
    return false;
  }
  final joinedAttemptAt = inviteAttempt!.updatedAt.toUtc();
  return removedAt == null || joinedAttemptAt.isAfter(removedAt);
}
