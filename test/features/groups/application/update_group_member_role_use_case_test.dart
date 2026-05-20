import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/groups/application/signed_group_transition_audit.dart';
import 'package:flutter_app/features/groups/application/update_group_member_role_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

class _TimeoutCommandBridge extends FakeBridge {
  final String command;

  _TimeoutCommandBridge(this.command);

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == command) {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);
      throw TimeoutException('Simulated $command timeout');
    }
    return super.send(message);
  }
}

void main() {
  late FakeBridge bridge;
  late InMemoryGroupRepository groupRepo;

  final adminGroup = GroupModel(
    id: 'group-1',
    name: 'Admin Group',
    type: GroupType.chat,
    topicName: 'group-topic-1',
    createdAt: DateTime.now().toUtc(),
    createdBy: 'peer-admin',
    myRole: GroupRole.admin,
  );

  setUp(() async {
    bridge = FakeBridge();
    groupRepo = InMemoryGroupRepository();
    groupRecoveryGate.resetForTest();

    await groupRepo.saveGroup(adminGroup);
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-admin',
        username: 'Admin',
        role: MemberRole.admin,
        publicKey: 'pk-admin',
        joinedAt: DateTime.now().toUtc(),
      ),
    );
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-writer',
        username: 'Writer',
        role: MemberRole.writer,
        publicKey: 'pk-writer',
        joinedAt: DateTime.now().toUtc(),
      ),
    );
  });

  tearDown(() {
    groupRecoveryGate.resetForTest();
  });

  test(
    'PREREQ-SIGNED-COMMIT-AUDIT builds signed member_role_updated payload before publish',
    () async {
      final eventAt = DateTime.utc(2026, 5, 1, 12, 3);
      final groupConfig = {
        'name': 'Admin Group',
        'groupType': 'chat',
        'members': [
          {
            'peerId': 'peer-admin',
            'username': 'Admin',
            'role': 'admin',
            'publicKey': 'pk-admin',
          },
          {
            'peerId': 'peer-writer',
            'username': 'Writer',
            'role': 'admin',
            'publicKey': 'pk-writer',
          },
        ],
        'createdBy': 'peer-admin',
        'createdAt': adminGroup.createdAt.toUtc().toIso8601String(),
      };
      final signed = await signGroupSystemTransitionPayload(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: 'group-1',
        transitionType: 'member_role_updated',
        sourceEventId: 'role-audit-1',
        eventAt: eventAt,
        actorPeerId: 'peer-admin',
        actorUsername: 'Admin',
        actorSigningPublicKey: 'pk-admin',
        actorPrivateKey: 'sk-admin',
        systemPayload: {
          '__sys': 'member_role_updated',
          'member': {
            'peerId': 'peer-writer',
            'username': 'Writer',
            'role': 'admin',
            'publicKey': 'pk-writer',
          },
          'groupConfig': groupConfig,
        },
      );

      expect(signed[signedGroupTransitionAuditField], isNotNull);
      expect(bridge.commandLog, contains('payload.sign'));
    },
  );

  test('promotes member to admin and syncs bridge config', () async {
    await updateGroupMemberRole(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: 'group-1',
      memberPeerId: 'peer-writer',
      role: MemberRole.admin,
      selfPeerId: 'peer-admin',
    );

    final updated = await groupRepo.getMember('group-1', 'peer-writer');
    expect(updated, isNotNull);
    expect(updated!.role, MemberRole.admin);
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
    final writerEntry = members.firstWhere(
      (member) => member['peerId'] == 'peer-writer',
    );
    expect(writerEntry['role'], 'admin');
  });

  test(
    'BB-013 group:updateConfig timeout rolls back the optimistic role mutation',
    () async {
      final timeoutBridge = _TimeoutCommandBridge('group:updateConfig');

      await expectLater(
        updateGroupMemberRole(
          bridge: timeoutBridge,
          groupRepo: groupRepo,
          groupId: 'group-1',
          memberPeerId: 'peer-writer',
          role: MemberRole.admin,
          selfPeerId: 'peer-admin',
        ),
        throwsA(isA<TimeoutException>()),
      );

      final writer = await groupRepo.getMember('group-1', 'peer-writer');
      expect(writer, isNotNull);
      expect(writer!.role, MemberRole.writer);
      expect(timeoutBridge.commandLog, ['group:updateConfig']);
    },
  );

  test('rejects non-admin caller', () async {
    const groupId = 'group-member-only';
    await groupRepo.saveGroup(
      GroupModel(
        id: groupId,
        name: 'Member Group',
        type: GroupType.chat,
        topicName: 'topic-member',
        createdAt: DateTime.now().toUtc(),
        createdBy: 'peer-admin',
        myRole: GroupRole.member,
      ),
    );
    await groupRepo.saveMember(
      GroupMember(
        groupId: groupId,
        peerId: 'peer-target',
        username: 'Target',
        role: MemberRole.writer,
        publicKey: 'pk-target',
        joinedAt: DateTime.now().toUtc(),
      ),
    );

    await expectLater(
      updateGroupMemberRole(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        memberPeerId: 'peer-target',
        role: MemberRole.admin,
        selfPeerId: 'peer-member',
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Only admins can manage member roles'),
        ),
      ),
    );

    expect(bridge.commandLog, isEmpty);
  });

  test('ML-013 bare writer cannot update member role or sync config', () async {
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-target',
        username: 'Target',
        role: MemberRole.writer,
        publicKey: 'pk-target',
        joinedAt: DateTime.now().toUtc(),
      ),
    );

    await expectLater(
      updateGroupMemberRole(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: 'group-1',
        memberPeerId: 'peer-target',
        role: MemberRole.admin,
        selfPeerId: 'peer-writer',
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Only admins can manage member roles'),
        ),
      ),
    );

    final target = await groupRepo.getMember('group-1', 'peer-target');
    expect(target, isNotNull);
    expect(target!.role, MemberRole.writer);
    expect(bridge.commandLog, isEmpty);
  });

  test(
    'allows writer with manage-roles permission override to update role',
    () async {
      const groupId = 'group-custom-manage';
      await groupRepo.saveGroup(
        GroupModel(
          id: groupId,
          name: 'Managed Group',
          type: GroupType.chat,
          topicName: 'topic-managed',
          createdAt: DateTime.now().toUtc(),
          createdBy: 'peer-admin',
          myRole: GroupRole.member,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: 'peer-manager',
          username: 'Manager',
          role: MemberRole.writer,
          permissions: const GroupMemberPermissions(manageRoles: true),
          publicKey: 'pk-manager',
          joinedAt: DateTime.now().toUtc(),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: 'peer-existing-admin',
          username: 'Existing Admin',
          role: MemberRole.admin,
          publicKey: 'pk-existing-admin',
          joinedAt: DateTime.now().toUtc(),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: 'peer-target',
          username: 'Target',
          role: MemberRole.reader,
          publicKey: 'pk-target',
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      await updateGroupMemberRole(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        memberPeerId: 'peer-target',
        role: MemberRole.writer,
        selfPeerId: 'peer-manager',
      );

      final updated = await groupRepo.getMember(groupId, 'peer-target');
      expect(updated, isNotNull);
      expect(updated!.role, MemberRole.writer);
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
      final managerEntry = members.firstWhere(
        (member) => member['peerId'] == 'peer-manager',
      );
      expect(managerEntry['role'], 'writer');
      expect(managerEntry['permissions'], {'manageRoles': true});
    },
  );

  test(
    'writer with manage-roles permission cannot promote a member to admin',
    () async {
      const groupId = 'group-custom-manage-no-admin-grant';
      await groupRepo.saveGroup(
        GroupModel(
          id: groupId,
          name: 'Managed Group',
          type: GroupType.chat,
          topicName: 'topic-managed-no-admin-grant',
          createdAt: DateTime.now().toUtc(),
          createdBy: 'peer-admin',
          myRole: GroupRole.member,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: 'peer-manager',
          username: 'Manager',
          role: MemberRole.writer,
          permissions: const GroupMemberPermissions(manageRoles: true),
          publicKey: 'pk-manager',
          joinedAt: DateTime.now().toUtc(),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: 'peer-existing-admin',
          username: 'Existing Admin',
          role: MemberRole.admin,
          publicKey: 'pk-existing-admin',
          joinedAt: DateTime.now().toUtc(),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: 'peer-target',
          username: 'Target',
          role: MemberRole.reader,
          publicKey: 'pk-target',
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      await expectLater(
        updateGroupMemberRole(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: groupId,
          memberPeerId: 'peer-target',
          role: MemberRole.admin,
          selfPeerId: 'peer-manager',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('cannot grant roles or permissions'),
          ),
        ),
      );

      final target = await groupRepo.getMember(groupId, 'peer-target');
      expect(target, isNotNull);
      expect(target!.role, MemberRole.reader);
      expect(bridge.commandLog, isEmpty);
    },
  );

  test('writer with manage-roles permission cannot demote an admin', () async {
    const groupId = 'group-custom-manage-no-admin-touch';
    await groupRepo.saveGroup(
      GroupModel(
        id: groupId,
        name: 'Managed Group',
        type: GroupType.chat,
        topicName: 'topic-managed-no-admin-touch',
        createdAt: DateTime.now().toUtc(),
        createdBy: 'peer-admin',
        myRole: GroupRole.member,
      ),
    );
    await groupRepo.saveMember(
      GroupMember(
        groupId: groupId,
        peerId: 'peer-manager',
        username: 'Manager',
        role: MemberRole.writer,
        permissions: const GroupMemberPermissions(manageRoles: true),
        publicKey: 'pk-manager',
        joinedAt: DateTime.now().toUtc(),
      ),
    );
    await groupRepo.saveMember(
      GroupMember(
        groupId: groupId,
        peerId: 'peer-admin',
        username: 'Admin',
        role: MemberRole.admin,
        publicKey: 'pk-admin',
        joinedAt: DateTime.now().toUtc(),
      ),
    );

    await expectLater(
      updateGroupMemberRole(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        memberPeerId: 'peer-admin',
        role: MemberRole.writer,
        selfPeerId: 'peer-manager',
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('cannot grant roles or permissions'),
        ),
      ),
    );

    final admin = await groupRepo.getMember(groupId, 'peer-admin');
    expect(admin, isNotNull);
    expect(admin!.role, MemberRole.admin);
    expect(bridge.commandLog, isEmpty);
  });

  test(
    'rechecks revoked manage-roles permission before applying queued role update',
    () async {
      const groupId = 'group-stale-manage';
      await groupRepo.saveGroup(
        GroupModel(
          id: groupId,
          name: 'Stale Managed Group',
          type: GroupType.chat,
          topicName: 'topic-stale-managed',
          createdAt: DateTime.now().toUtc(),
          createdBy: 'peer-admin',
          myRole: GroupRole.member,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: 'peer-manager',
          username: 'Manager',
          role: MemberRole.writer,
          permissions: const GroupMemberPermissions(manageRoles: true),
          publicKey: 'pk-manager',
          joinedAt: DateTime.now().toUtc(),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: 'peer-manager',
          username: 'Manager',
          role: MemberRole.writer,
          publicKey: 'pk-manager',
          joinedAt: DateTime.now().toUtc(),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: 'peer-existing-admin',
          username: 'Existing Admin',
          role: MemberRole.admin,
          publicKey: 'pk-existing-admin',
          joinedAt: DateTime.now().toUtc(),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: 'peer-target',
          username: 'Target',
          role: MemberRole.reader,
          publicKey: 'pk-target',
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      await expectLater(
        updateGroupMemberRole(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: groupId,
          memberPeerId: 'peer-target',
          role: MemberRole.writer,
          selfPeerId: 'peer-manager',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Only admins can manage member roles'),
          ),
        ),
      );

      final target = await groupRepo.getMember(groupId, 'peer-target');
      expect(target, isNotNull);
      expect(target!.role, MemberRole.reader);
      expect(bridge.commandLog, isEmpty);
    },
  );

  test(
    'denies admin whose manage-roles permission override is false',
    () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-admin',
          username: 'Admin',
          role: MemberRole.admin,
          permissions: const GroupMemberPermissions(manageRoles: false),
          publicKey: 'pk-admin',
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      await expectLater(
        updateGroupMemberRole(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: 'group-1',
          memberPeerId: 'peer-writer',
          role: MemberRole.admin,
          selfPeerId: 'peer-admin',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Only admins can manage member roles'),
          ),
        ),
      );

      final writer = await groupRepo.getMember('group-1', 'peer-writer');
      expect(writer, isNotNull);
      expect(writer!.role, MemberRole.writer);
      expect(bridge.commandLog, isEmpty);
    },
  );

  test('rejects non-member target before sync', () async {
    await expectLater(
      updateGroupMemberRole(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: 'group-1',
        memberPeerId: 'peer-missing',
        role: MemberRole.admin,
        selfPeerId: 'peer-admin',
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Member not found'),
        ),
      ),
    );

    expect(bridge.commandLog, isEmpty);
  });

  test('blocks removing the last admin from the group', () async {
    await expectLater(
      updateGroupMemberRole(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: 'group-1',
        memberPeerId: 'peer-admin',
        role: MemberRole.writer,
        selfPeerId: 'peer-admin',
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains(lastAdminRoleChangeBlockedMessage),
        ),
      ),
    );

    final admin = await groupRepo.getMember('group-1', 'peer-admin');
    expect(admin, isNotNull);
    expect(admin!.role, MemberRole.admin);
    expect(bridge.commandLog, isEmpty);
  });

  test(
    'allows self demotion when another admin remains and updates myRole',
    () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-other-admin',
          username: 'Other Admin',
          role: MemberRole.admin,
          publicKey: 'pk-other-admin',
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      await updateGroupMemberRole(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: 'group-1',
        memberPeerId: 'peer-admin',
        role: MemberRole.writer,
        selfPeerId: 'peer-admin',
      );

      final selfMember = await groupRepo.getMember('group-1', 'peer-admin');
      final group = await groupRepo.getGroup('group-1');
      expect(selfMember, isNotNull);
      expect(selfMember!.role, MemberRole.writer);
      expect(group, isNotNull);
      expect(group!.myRole, GroupRole.member);
      expect(bridge.commandLog, contains('group:updateConfig'));
    },
  );

  test(
    'ML-020 admin transfer demotes creator while preserving one admin',
    () async {
      await updateGroupMemberRole(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: 'group-1',
        memberPeerId: 'peer-writer',
        role: MemberRole.admin,
        selfPeerId: 'peer-admin',
        eventAt: DateTime.utc(2026, 5, 15, 18),
      );

      await updateGroupMemberRole(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: 'group-1',
        memberPeerId: 'peer-admin',
        role: MemberRole.writer,
        selfPeerId: 'peer-writer',
        eventAt: DateTime.utc(2026, 5, 15, 18, 1),
      );

      final creator = await groupRepo.getMember('group-1', 'peer-admin');
      final promoted = await groupRepo.getMember('group-1', 'peer-writer');
      expect(creator, isNotNull);
      expect(creator!.role, MemberRole.writer);
      expect(promoted, isNotNull);
      expect(promoted!.role, MemberRole.admin);

      final updateConfigMessages = bridge.sentMessages.where((message) {
        final parsed = jsonDecode(message) as Map<String, dynamic>;
        return parsed['cmd'] == 'group:updateConfig';
      }).toList();
      expect(updateConfigMessages, hasLength(2));

      final finalPayload =
          (jsonDecode(updateConfigMessages.last)
                  as Map<String, dynamic>)['payload']
              as Map<String, dynamic>;
      final groupConfig = finalPayload['groupConfig'] as Map<String, dynamic>;
      final members = (groupConfig['members'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final rolesByPeer = <String, String>{
        for (final member in members)
          member['peerId'] as String: member['role'] as String,
      };
      expect(rolesByPeer['peer-admin'], 'writer');
      expect(rolesByPeer['peer-writer'], 'admin');
      expect(rolesByPeer.values.where((role) => role == 'admin'), hasLength(1));
    },
  );

  test('rejects while group recovery is in progress', () async {
    groupRecoveryGate.begin();
    try {
      await expectLater(
        updateGroupMemberRole(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: 'group-1',
          memberPeerId: 'peer-writer',
          role: MemberRole.admin,
          selfPeerId: 'peer-admin',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains(groupRecoveryPendingError),
          ),
        ),
      );
    } finally {
      groupRecoveryGate.end();
    }

    final writer = await groupRepo.getMember('group-1', 'peer-writer');
    expect(writer, isNotNull);
    expect(writer!.role, MemberRole.writer);
    expect(bridge.commandLog, isEmpty);
  });
}
