import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/add_group_member_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
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

    await groupRepo.saveGroup(adminGroup);
    await groupRepo.saveGroup(memberGroup);
  });

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

  test('throws when member already exists — second add is upsert', () async {
    final member = GroupMember(
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
      newMember: member,
      selfPeerId: 'peer-admin',
    );

    // Add the same peerId again with a different username.
    final memberAgain = GroupMember(
      groupId: 'group-1',
      peerId: 'peer-duplicate',
      username: 'SecondAdd',
      role: MemberRole.reader,
      joinedAt: DateTime.now().toUtc(),
    );

    await addGroupMember(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: 'group-1',
      newMember: memberAgain,
      selfPeerId: 'peer-admin',
    );

    // InMemoryGroupRepository uses upsert semantics — the second save
    // overwrites the first, so there is still exactly 1 member with that
    // peerId, carrying the updated fields.
    final members = await groupRepo.getMembers('group-1');
    final duplicates =
        members.where((m) => m.peerId == 'peer-duplicate').toList();
    expect(duplicates.length, 1);
    expect(duplicates.first.username, 'SecondAdd');
    expect(duplicates.first.role, MemberRole.reader);
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
