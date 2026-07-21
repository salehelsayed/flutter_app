import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/groups/application/group_exit_policy.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_delivery_attempt.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';

import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

void main() {
  const groupId = 'group-exit-policy';
  const selfPeerId = 'peer-self';
  final now = DateTime.utc(2026, 7, 19, 10);

  GroupModel group({
    GroupRole myRole = GroupRole.admin,
    bool isDissolved = false,
    DateTime? selfRemovedAt,
    DateTime? lastMembershipEventAt,
  }) => GroupModel(
    id: groupId,
    name: 'Orbit group',
    type: GroupType.chat,
    topicName: 'topic-$groupId',
    createdAt: now,
    createdBy: selfPeerId,
    myRole: myRole,
    isDissolved: isDissolved,
    selfRemovedAt: selfRemovedAt,
    lastMembershipEventAt: lastMembershipEventAt,
  );

  GroupMember member(String peerId, MemberRole role) => GroupMember(
    groupId: groupId,
    peerId: peerId,
    username: peerId,
    role: role,
    // Deliberately populated: joinedAt alone is not eligibility evidence.
    joinedAt: now,
  );

  GroupPendingBroadcast pending(String kind) => GroupPendingBroadcast(
    id: 'pending-$kind',
    groupId: groupId,
    kind: kind,
    sysText: '{}',
    recipientPeerIds: const ['peer-candidate'],
    eventAt: now,
    sourceMessageId: 'source-$kind',
    createdAt: now,
    updatedAt: now,
  );

  test('fresh repository state maps every Orbit exit disposition', () async {
    final groupRepo = InMemoryGroupRepository();
    final messageRepo = _EvidenceMessageRepository();
    var pendingRows = <GroupPendingBroadcast>[];

    Future<GroupExitSnapshot> resolve() => resolveGroupExitSnapshot(
      groupRepo: groupRepo,
      groupId: groupId,
      selfPeerId: selfPeerId,
      messageRepo: messageRepo,
      loadPendingBroadcasts: (_) async => pendingRows,
    );

    expect((await resolve()).disposition, GroupExitDisposition.noOp);

    await groupRepo.saveGroup(group(myRole: GroupRole.member));
    expect((await resolve()).disposition, GroupExitDisposition.leave);

    await groupRepo.updateGroup(group());
    await groupRepo.saveMember(member(selfPeerId, MemberRole.admin));
    await groupRepo.saveMember(member('peer-candidate', MemberRole.writer));
    expect(
      (await resolve()).disposition,
      GroupExitDisposition.soleAdminRecovery,
    );

    // Existing peer-admin rows remain authoritative without new-successor
    // join heuristics.
    await groupRepo.updateMemberRole(
      groupId,
      'peer-candidate',
      MemberRole.admin,
    );
    expect((await resolve()).disposition, GroupExitDisposition.leave);

    await groupRepo.updateMemberRole(
      groupId,
      'peer-candidate',
      MemberRole.writer,
    );
    pendingRows = [pending('group_metadata_updated')];
    expect(
      (await resolve()).disposition,
      GroupExitDisposition.soleAdminRecovery,
      reason: 'unrelated pending metadata must not block exit',
    );
    pendingRows = [pending('member_role_updated')];
    expect((await resolve()).disposition, GroupExitDisposition.pendingRoleSync);

    // Re-read beats the captured active row.
    pendingRows = [];
    await groupRepo.updateGroup(group(isDissolved: true));
    expect(
      (await resolve()).disposition,
      GroupExitDisposition.deleteDissolvedLocally,
    );
  });

  test('successor candidates require current joined evidence', () async {
    for (final status in GroupInviteDeliveryStatus.values) {
      final attempt = GroupInviteDeliveryAttempt(
        groupId: groupId,
        peerId: 'peer-candidate',
        status: status,
        attemptedAt: now,
        updatedAt: now.add(const Duration(minutes: 1)),
      );
      expect(
        hasCurrentGroupJoinEvidence(
          memberJoinedAt: null,
          memberRemovedAt: null,
          inviteAttempt: attempt,
        ),
        status == GroupInviteDeliveryStatus.joined,
        reason: 'status $status without member_joined evidence',
      );
    }

    expect(
      hasCurrentGroupJoinEvidence(
        memberJoinedAt: now.add(const Duration(minutes: 3)),
        memberRemovedAt: now.add(const Duration(minutes: 2)),
        inviteAttempt: null,
      ),
      isTrue,
      reason: 'a current peer-authored join qualifies',
    );
    expect(
      hasCurrentGroupJoinEvidence(
        memberJoinedAt: now,
        memberRemovedAt: now.add(const Duration(minutes: 1)),
        inviteAttempt: null,
      ),
      isFalse,
      reason: 'join evidence from before removal is stale',
    );
    expect(
      hasCurrentGroupJoinEvidence(
        memberJoinedAt: now.add(const Duration(minutes: 1)),
        memberRemovedAt: null,
        inviteAttempt: GroupInviteDeliveryAttempt(
          groupId: groupId,
          peerId: 'peer-candidate',
          status: GroupInviteDeliveryStatus.sent,
          attemptedAt: now.add(const Duration(minutes: 2)),
          updatedAt: now.add(const Duration(minutes: 2)),
        ),
      ),
      isFalse,
      reason: 'a later re-invite invalidates older join evidence',
    );
    expect(
      hasCurrentGroupJoinEvidence(
        memberJoinedAt: now.add(const Duration(minutes: 1)),
        memberRemovedAt: now.add(const Duration(minutes: 2)),
        inviteAttempt: GroupInviteDeliveryAttempt(
          groupId: groupId,
          peerId: 'peer-candidate',
          status: GroupInviteDeliveryStatus.joined,
          attemptedAt: now.add(const Duration(minutes: 3)),
          updatedAt: now.add(const Duration(minutes: 4)),
        ),
      ),
      isTrue,
      reason: 'a current joined attempt supersedes stale timeline evidence',
    );
    expect(
      hasCurrentGroupJoinEvidence(
        memberJoinedAt: null,
        memberRemovedAt: null,
        inviteAttempt: null,
      ),
      isFalse,
      reason: 'roster joinedAt/admin-add-only state is not accepted',
    );
  });

  test(
    'durably removed shell outranks stale pending-role and removed-admin snapshots',
    () async {
      for (final role in GroupRole.values) {
        final groupRepo = InMemoryGroupRepository();
        await groupRepo.saveGroup(
          group(myRole: role, selfRemovedAt: now, lastMembershipEventAt: now),
        );

        final snapshot = await resolveGroupExitSnapshot(
          groupRepo: groupRepo,
          groupId: groupId,
          selfPeerId: selfPeerId,
          loadPendingBroadcasts: (_) async => [pending('member_role_updated')],
        );

        expect(
          snapshot.disposition,
          GroupExitDisposition.selfRemovedDeleteLocally,
          reason: 'stale $role and pending-role state must not hide the shell',
        );
      }
    },
  );

  test(
    'removed authority ignores stale key cleanup residue but refuses missing marker self restored dissolved or newer membership',
    () async {
      final groupRepo = InMemoryGroupRepository();

      Future<GroupExitDisposition> resolve() async =>
          (await resolveGroupExitSnapshot(
            groupRepo: groupRepo,
            groupId: groupId,
            selfPeerId: selfPeerId,
          )).disposition;

      await groupRepo.saveGroup(
        group(selfRemovedAt: now, lastMembershipEventAt: now),
      );
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: groupId,
          keyGeneration: 3,
          encryptedKey: 'stale-cleanup-address',
          createdAt: now,
        ),
      );
      expect(await resolve(), GroupExitDisposition.selfRemovedDeleteLocally);

      await groupRepo.updateGroup(group(lastMembershipEventAt: now));
      expect(
        await resolve(),
        isNot(GroupExitDisposition.selfRemovedDeleteLocally),
      );

      await groupRepo.updateGroup(
        group(selfRemovedAt: now, lastMembershipEventAt: now),
      );
      await groupRepo.saveMember(member(selfPeerId, MemberRole.writer));
      expect(
        await resolve(),
        isNot(GroupExitDisposition.selfRemovedDeleteLocally),
      );

      await groupRepo.removeMember(groupId, selfPeerId);
      await groupRepo.updateGroup(
        group(
          selfRemovedAt: now,
          lastMembershipEventAt: now.add(const Duration(seconds: 1)),
        ),
      );
      expect(
        await resolve(),
        isNot(GroupExitDisposition.selfRemovedDeleteLocally),
      );

      await groupRepo.updateGroup(
        group(
          isDissolved: true,
          selfRemovedAt: now,
          lastMembershipEventAt: now,
        ),
      );
      expect(await resolve(), GroupExitDisposition.deleteDissolvedLocally);
    },
  );

  test(
    'fresh marked state fails closed on dependent read faults without blocking proven local deletion',
    () async {
      final groupRepo = _FaultingMembersGroupRepository();
      await groupRepo.saveGroup(
        group(selfRemovedAt: now, lastMembershipEventAt: now),
      );

      groupRepo.failMembers = true;
      var pendingLoads = 0;
      final memberFault = await resolveGroupExitSnapshot(
        groupRepo: groupRepo,
        groupId: groupId,
        selfPeerId: selfPeerId,
        loadPendingBroadcasts: (_) async {
          pendingLoads++;
          throw StateError('pending read must not follow roster failure');
        },
      );
      expect(memberFault.disposition, GroupExitDisposition.noOp);
      expect(memberFault.group?.selfRemovedAt, now);
      expect(pendingLoads, 0);

      groupRepo.failMembers = false;
      final provenRemoved = await resolveGroupExitSnapshot(
        groupRepo: groupRepo,
        groupId: groupId,
        selfPeerId: selfPeerId,
        loadPendingBroadcasts: (_) async {
          pendingLoads++;
          throw StateError('stale pending state must not hide a removed shell');
        },
      );
      expect(
        provenRemoved.disposition,
        GroupExitDisposition.selfRemovedDeleteLocally,
      );
      expect(pendingLoads, 0);

      await groupRepo.saveMember(member(selfPeerId, MemberRole.writer));
      final pendingFault = await resolveGroupExitSnapshot(
        groupRepo: groupRepo,
        groupId: groupId,
        selfPeerId: selfPeerId,
        loadPendingBroadcasts: (_) async {
          pendingLoads++;
          throw StateError('pending read failed');
        },
      );
      expect(pendingFault.disposition, GroupExitDisposition.noOp);
      expect(pendingLoads, 1);

      await groupRepo.updateGroup(
        group(
          isDissolved: true,
          selfRemovedAt: now,
          lastMembershipEventAt: now,
        ),
      );
      groupRepo.failMembers = true;
      final dissolved = await resolveGroupExitSnapshot(
        groupRepo: groupRepo,
        groupId: groupId,
        selfPeerId: selfPeerId,
        loadPendingBroadcasts: (_) async {
          pendingLoads++;
          throw StateError('dissolved classification must not depend on queue');
        },
      );
      expect(
        dissolved.disposition,
        GroupExitDisposition.deleteDissolvedLocally,
      );
      expect(pendingLoads, 1);
    },
  );
}

class _EvidenceMessageRepository extends InMemoryGroupMessageRepository {}

class _FaultingMembersGroupRepository extends InMemoryGroupRepository {
  bool failMembers = false;

  @override
  Future<List<GroupMember>> getMembers(String groupId) {
    if (failMembers) {
      throw StateError('member read failed');
    }
    return super.getMembers(groupId);
  }
}
