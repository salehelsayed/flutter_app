import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/groups/application/update_group_member_role_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

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
