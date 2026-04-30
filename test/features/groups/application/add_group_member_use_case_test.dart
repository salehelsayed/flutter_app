import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/add_group_member_use_case.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_membership_limit_policy.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

void main() {
  late FakeBridge bridge;
  late InMemoryGroupRepository groupRepo;

  final adminGroup = GroupModel(
    id: 'group-1',
    name: 'Test Group',
    type: GroupType.chat,
    topicName: 'group-topic-1',
    createdAt: DateTime.now().toUtc(),
    createdBy: 'peer-admin',
    myRole: GroupRole.admin,
  );

  final memberGroup = GroupModel(
    id: 'group-2',
    name: 'Member Group',
    type: GroupType.chat,
    topicName: 'group-topic-2',
    createdAt: DateTime.now().toUtc(),
    createdBy: 'peer-admin',
    myRole: GroupRole.member,
  );

  setUp(() async {
    bridge = FakeBridge();
    groupRepo = InMemoryGroupRepository();
    groupRecoveryGate.resetForTest();

    await groupRepo.saveGroup(adminGroup);
    await groupRepo.saveGroup(memberGroup);
  });

  tearDown(() {
    groupRecoveryGate.resetForTest();
  });

  Future<void> seedGroupMembers({
    required String groupId,
    required int totalMembers,
  }) async {
    for (var index = 0; index < totalMembers; index++) {
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: index == 0 ? 'peer-admin' : 'peer-seed-$index',
          username: index == 0 ? 'Admin' : 'Seed $index',
          role: index == 0 ? MemberRole.admin : MemberRole.writer,
          joinedAt: DateTime.now().toUtc(),
        ),
      );
    }
  }

  test('adds member successfully when caller is admin', () async {
    final newMember = GroupMember(
      groupId: 'group-1',
      peerId: 'peer-new',
      username: 'NewUser',
      role: MemberRole.writer,
      joinedAt: DateTime.now().toUtc(),
    );

    await addGroupMember(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: 'group-1',
      newMember: newMember,
      selfPeerId: 'peer-admin',
    );

    final members = await groupRepo.getMembers('group-1');
    expect(members.length, 1);
    expect(members.first.peerId, 'peer-new');
  });

  test('allows adding the 50th member under the shared contract', () async {
    await seedGroupMembers(
      groupId: 'group-1',
      totalMembers: groupMembershipLimit - 1,
    );

    final newMember = GroupMember(
      groupId: 'group-1',
      peerId: 'peer-50',
      username: 'Member Fifty',
      role: MemberRole.writer,
      joinedAt: DateTime.now().toUtc(),
    );

    await addGroupMember(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: 'group-1',
      newMember: newMember,
      selfPeerId: 'peer-admin',
    );

    final saved = await groupRepo.getMember('group-1', 'peer-50');
    expect(saved, isNotNull);
    final members = await groupRepo.getMembers('group-1');
    expect(members.length, groupMembershipLimit);
  });

  test('rejects when caller is not admin', () async {
    final newMember = GroupMember(
      groupId: 'group-2',
      peerId: 'peer-new',
      username: 'NewUser',
      role: MemberRole.writer,
      joinedAt: DateTime.now().toUtc(),
    );

    expect(
      () => addGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: 'group-2',
        newMember: newMember,
        selfPeerId: 'peer-member',
      ),
      throwsA(isA<StateError>()),
    );

    expect(await groupRepo.getMember('group-2', 'peer-new'), isNull);
    expect(bridge.commandLog, isEmpty);
  });

  test(
    'allows writer with invite permission override to add a member',
    () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-2',
          peerId: 'peer-inviter',
          username: 'Inviter',
          role: MemberRole.writer,
          permissions: const GroupMemberPermissions(inviteMembers: true),
          publicKey: 'pk-inviter',
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      final newMember = GroupMember(
        groupId: 'group-2',
        peerId: 'peer-custom',
        username: 'CustomInvitee',
        role: MemberRole.reader,
        publicKey: 'pk-custom',
        joinedAt: DateTime.now().toUtc(),
      );

      await addGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: 'group-2',
        newMember: newMember,
        selfPeerId: 'peer-inviter',
      );

      expect(await groupRepo.getMember('group-2', 'peer-custom'), isNotNull);
      expect(bridge.commandLog, contains('group:updateConfig'));

      final updateConfigMessage = bridge.sentMessages.firstWhere((message) {
        final parsed = jsonDecode(message) as Map<String, dynamic>;
        return parsed['cmd'] == 'group:updateConfig';
      });
      final payload =
          (jsonDecode(updateConfigMessage) as Map<String, dynamic>)['payload']
              as Map<String, dynamic>;
      final groupConfig = payload['groupConfig'] as Map<String, dynamic>;
      final members = (groupConfig['members'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final inviterEntry = members.firstWhere(
        (member) => member['peerId'] == 'peer-inviter',
      );
      expect(inviterEntry['role'], 'writer');
      expect(inviterEntry['permissions'], {'inviteMembers': true});
    },
  );

  test(
    'rechecks revoked invite permission before adding a queued member',
    () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-2',
          peerId: 'peer-inviter',
          username: 'Inviter',
          role: MemberRole.writer,
          permissions: const GroupMemberPermissions(inviteMembers: true),
          publicKey: 'pk-inviter',
          joinedAt: DateTime.now().toUtc(),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-2',
          peerId: 'peer-inviter',
          username: 'Inviter',
          role: MemberRole.writer,
          publicKey: 'pk-inviter',
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      final queuedMember = GroupMember(
        groupId: 'group-2',
        peerId: 'peer-stale-invite',
        username: 'StaleInvitee',
        role: MemberRole.reader,
        publicKey: 'pk-stale-invite',
        joinedAt: DateTime.now().toUtc(),
      );

      await expectLater(
        addGroupMember(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: 'group-2',
          newMember: queuedMember,
          selfPeerId: 'peer-inviter',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Only admins can add members'),
          ),
        ),
      );

      expect(await groupRepo.getMember('group-2', 'peer-stale-invite'), isNull);
      expect(bridge.commandLog, isEmpty);
    },
  );

  test('denies admin whose invite permission override is false', () async {
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-admin',
        username: 'Admin',
        role: MemberRole.admin,
        permissions: const GroupMemberPermissions(inviteMembers: false),
        joinedAt: DateTime.now().toUtc(),
      ),
    );

    final newMember = GroupMember(
      groupId: 'group-1',
      peerId: 'peer-denied',
      username: 'DeniedUser',
      role: MemberRole.writer,
      joinedAt: DateTime.now().toUtc(),
    );

    await expectLater(
      addGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: 'group-1',
        newMember: newMember,
        selfPeerId: 'peer-admin',
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Only admins can add members'),
        ),
      ),
    );

    expect(await groupRepo.getMember('group-1', 'peer-denied'), isNull);
    expect(bridge.commandLog, isEmpty);
  });

  test('rejects while group recovery is in progress', () async {
    final newMember = GroupMember(
      groupId: 'group-1',
      peerId: 'peer-new',
      username: 'NewUser',
      role: MemberRole.writer,
      joinedAt: DateTime.now().toUtc(),
    );

    groupRecoveryGate.begin();
    try {
      await expectLater(
        addGroupMember(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: 'group-1',
          newMember: newMember,
          selfPeerId: 'peer-admin',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains(groupRecoveryPendingError),
          ),
        ),
      );
    } finally {
      groupRecoveryGate.end();
    }

    expect(bridge.commandLog, isEmpty);
    final saved = await groupRepo.getMember('group-1', 'peer-new');
    expect(saved, isNull);
  });

  test('throws when group not found', () async {
    final newMember = GroupMember(
      groupId: 'nonexistent-group',
      peerId: 'peer-new',
      username: 'NewUser',
      role: MemberRole.writer,
      joinedAt: DateTime.now().toUtc(),
    );

    expect(
      () => addGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: 'nonexistent-group',
        newMember: newMember,
        selfPeerId: 'peer-admin',
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Group not found'),
        ),
      ),
    );
  });

  test(
    'rejects duplicate member before sync and preserves original row',
    () async {
      final originalMember = GroupMember(
        groupId: 'group-1',
        peerId: 'peer-duplicate',
        username: 'FirstAdd',
        role: MemberRole.writer,
        joinedAt: DateTime.now().toUtc(),
      );

      await addGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: 'group-1',
        newMember: originalMember,
        selfPeerId: 'peer-admin',
      );

      bridge.commandLog.clear();

      final duplicateAttempt = GroupMember(
        groupId: 'group-1',
        peerId: 'peer-duplicate',
        username: 'SecondAdd',
        role: MemberRole.reader,
        joinedAt: DateTime.now().toUtc(),
      );

      await expectLater(
        addGroupMember(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: 'group-1',
          newMember: duplicateAttempt,
          selfPeerId: 'peer-admin',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('already exists'),
          ),
        ),
      );

      final members = await groupRepo.getMembers('group-1');
      final duplicates = members
          .where((m) => m.peerId == 'peer-duplicate')
          .toList();
      expect(duplicates.length, 1);
      expect(duplicates.first.username, 'FirstAdd');
      expect(duplicates.first.role, MemberRole.writer);
      expect(bridge.commandLog, isEmpty);
    },
  );

  test('rejects adding a 51st member before config sync', () async {
    await seedGroupMembers(
      groupId: 'group-1',
      totalMembers: groupMembershipLimit,
    );
    bridge.commandLog.clear();

    final newMember = GroupMember(
      groupId: 'group-1',
      peerId: 'peer-over-limit',
      username: 'Overflow',
      role: MemberRole.writer,
      joinedAt: DateTime.now().toUtc(),
    );

    await expectLater(
      addGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: 'group-1',
        newMember: newMember,
        selfPeerId: 'peer-admin',
      ),
      throwsA(
        isA<GroupMembershipLimitException>()
            .having((e) => e.maxMembers, 'maxMembers', groupMembershipLimit)
            .having(
              (e) => e.currentMemberCount,
              'currentMemberCount',
              groupMembershipLimit,
            )
            .having(
              (e) => e.requestedAdditionalMembers,
              'requestedAdditionalMembers',
              1,
            ),
      ),
    );

    expect(await groupRepo.getMember('group-1', 'peer-over-limit'), isNull);
    expect(bridge.commandLog, isEmpty);
  });

  test('saves member to repo', () async {
    final newMember = GroupMember(
      groupId: 'group-1',
      peerId: 'peer-saved',
      username: 'SavedUser',
      role: MemberRole.reader,
      joinedAt: DateTime.now().toUtc(),
    );

    await addGroupMember(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: 'group-1',
      newMember: newMember,
      selfPeerId: 'peer-admin',
    );

    final saved = await groupRepo.getMember('group-1', 'peer-saved');
    expect(saved, isNotNull);
    expect(saved!.username, 'SavedUser');
    expect(saved.role, MemberRole.reader);
  });

  test('rolls back DB when group:updateConfig fails', () async {
    bridge.responses['group:updateConfig'] = {
      'ok': false,
      'errorCode': 'CONFIG_SYNC_FAILED',
      'errorMessage': 'bridge rejected config',
    };

    final newMember = GroupMember(
      groupId: 'group-1',
      peerId: 'peer-rollback',
      username: 'RollbackUser',
      role: MemberRole.writer,
      joinedAt: DateTime.now().toUtc(),
    );

    await expectLater(
      addGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: 'group-1',
        newMember: newMember,
        selfPeerId: 'peer-admin',
      ),
      throwsA(isA<Exception>()),
    );

    final saved = await groupRepo.getMember('group-1', 'peer-rollback');
    expect(saved, isNull);
  });

  test('syncBridgeConfig false skips bridge config sync', () async {
    final newMember = GroupMember(
      groupId: 'group-1',
      peerId: 'peer-no-sync',
      username: 'NoSyncUser',
      role: MemberRole.writer,
      joinedAt: DateTime.now().toUtc(),
    );

    await addGroupMember(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: 'group-1',
      newMember: newMember,
      selfPeerId: 'peer-admin',
      syncBridgeConfig: false,
    );

    final saved = await groupRepo.getMember('group-1', 'peer-no-sync');
    expect(saved, isNotNull);
    expect(
      bridge.commandLog.where((command) => command == 'group:updateConfig'),
      isEmpty,
    );
  });
}
