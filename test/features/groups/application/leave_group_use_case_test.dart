import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/leave_group_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

void main() {
  late FakeBridge bridge;
  late InMemoryGroupRepository groupRepo;

  final testGroup = GroupModel(
    id: 'group-1',
    name: 'Test Group',
    type: GroupType.chat,
    topicName: 'group-topic-1',
    createdAt: DateTime.now().toUtc(),
    createdBy: 'peer-1',
    myRole: GroupRole.member,
  );

  setUp(() async {
    bridge = FakeBridge();
    groupRepo = InMemoryGroupRepository();

    await groupRepo.saveGroup(testGroup);
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-1',
        role: MemberRole.writer,
        joinedAt: DateTime.now().toUtc(),
      ),
    );
    await groupRepo.saveKey(
      GroupKeyInfo(
        groupId: 'group-1',
        keyGeneration: 0,
        encryptedKey: 'key-data',
        createdAt: DateTime.now().toUtc(),
      ),
    );

    bridge.responses['group:leave'] = {'ok': true};
  });

  test('leaves group successfully', () async {
    await leaveGroup(bridge: bridge, groupRepo: groupRepo, groupId: 'group-1');

    final group = await groupRepo.getGroup('group-1');
    expect(group, isNull);
  });

  test('cleans up all data (members, keys, group)', () async {
    await leaveGroup(bridge: bridge, groupRepo: groupRepo, groupId: 'group-1');

    // Group deleted
    final group = await groupRepo.getGroup('group-1');
    expect(group, isNull);

    // Members removed
    final members = await groupRepo.getMembers('group-1');
    expect(members, isEmpty);

    // Keys removed
    final key = await groupRepo.getLatestKey('group-1');
    expect(key, isNull);
  });

  test('calls bridge leave command', () async {
    await leaveGroup(bridge: bridge, groupRepo: groupRepo, groupId: 'group-1');

    expect(bridge.commandLog, contains('group:leave'));
  });

  test('blocks sole admin from leaving', () async {
    const groupId = 'group-admin-only';
    final adminGroup = GroupModel(
      id: groupId,
      name: 'Admin Group',
      type: GroupType.chat,
      topicName: 'group-topic-admin',
      createdAt: DateTime.now().toUtc(),
      createdBy: 'peer-admin',
      myRole: GroupRole.admin,
    );

    await groupRepo.saveGroup(adminGroup);
    await groupRepo.saveMember(
      GroupMember(
        groupId: groupId,
        peerId: 'peer-admin',
        username: 'Admin',
        role: MemberRole.admin,
        joinedAt: DateTime.now().toUtc(),
      ),
    );

    await expectLater(
      leaveGroup(bridge: bridge, groupRepo: groupRepo, groupId: groupId),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains(lastAdminLeaveBlockedMessage),
        ),
      ),
    );

    expect(await groupRepo.getGroup(groupId), isNotNull);
    expect(await groupRepo.getMembers(groupId), hasLength(1));
    expect(bridge.commandLog, isNot(contains('group:leave')));
  });

  test('allows admin to leave when another admin exists', () async {
    const groupId = 'group-shared-admins';
    final adminGroup = GroupModel(
      id: groupId,
      name: 'Shared Admin Group',
      type: GroupType.chat,
      topicName: 'group-topic-shared',
      createdAt: DateTime.now().toUtc(),
      createdBy: 'peer-admin',
      myRole: GroupRole.admin,
    );

    await groupRepo.saveGroup(adminGroup);
    await groupRepo.saveMember(
      GroupMember(
        groupId: groupId,
        peerId: 'peer-admin',
        username: 'Admin',
        role: MemberRole.admin,
        joinedAt: DateTime.now().toUtc(),
      ),
    );
    await groupRepo.saveMember(
      GroupMember(
        groupId: groupId,
        peerId: 'peer-other-admin',
        username: 'Other Admin',
        role: MemberRole.admin,
        joinedAt: DateTime.now().toUtc(),
      ),
    );
    await groupRepo.saveKey(
      GroupKeyInfo(
        groupId: groupId,
        keyGeneration: 0,
        encryptedKey: 'shared-key-data',
        createdAt: DateTime.now().toUtc(),
      ),
    );

    await leaveGroup(bridge: bridge, groupRepo: groupRepo, groupId: groupId);

    expect(await groupRepo.getGroup(groupId), isNull);
    expect(bridge.commandLog, contains('group:leave'));
  });
}
