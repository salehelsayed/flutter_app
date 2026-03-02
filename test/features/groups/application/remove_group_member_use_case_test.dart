import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/remove_group_member_use_case.dart';
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
    createdBy: 'peer-admin',
    myRole: GroupRole.admin,
  );

  setUp(() async {
    bridge = FakeBridge();
    groupRepo = InMemoryGroupRepository();

    await groupRepo.saveGroup(testGroup);
    await groupRepo.saveMember(GroupMember(
      groupId: 'group-1',
      peerId: 'peer-admin',
      username: 'Admin',
      role: MemberRole.admin,
      publicKey: 'pk-admin',
      joinedAt: DateTime.now().toUtc(),
    ));
    await groupRepo.saveMember(GroupMember(
      groupId: 'group-1',
      peerId: 'peer-to-remove',
      username: 'RemoveMe',
      role: MemberRole.writer,
      publicKey: 'pk-remove',
      joinedAt: DateTime.now().toUtc(),
    ));
    await groupRepo.saveMember(GroupMember(
      groupId: 'group-1',
      peerId: 'peer-bystander',
      username: 'Bystander',
      role: MemberRole.writer,
      publicKey: 'pk-bystander',
      joinedAt: DateTime.now().toUtc(),
    ));
  });

  test('removes member from DB', () async {
    await removeGroupMember(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: 'group-1',
      memberPeerId: 'peer-to-remove',
    );

    final member = await groupRepo.getMember('group-1', 'peer-to-remove');
    expect(member, isNull);

    // Other members remain
    final admin = await groupRepo.getMember('group-1', 'peer-admin');
    expect(admin, isNotNull);
    final bystander = await groupRepo.getMember('group-1', 'peer-bystander');
    expect(bystander, isNotNull);
  });

  test('calls group:updateConfig to update Go validator', () async {
    await removeGroupMember(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: 'group-1',
      memberPeerId: 'peer-to-remove',
    );

    expect(bridge.commandLog, contains('group:updateConfig'));
  });

  test('does NOT call group:rotateKey', () async {
    await removeGroupMember(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: 'group-1',
      memberPeerId: 'peer-to-remove',
    );

    expect(bridge.commandLog, isNot(contains('group:rotateKey')));
  });

  test('throws when caller is not admin', () async {
    final memberGroup = GroupModel(
      id: 'group-member-only',
      name: 'Member Group',
      type: GroupType.chat,
      topicName: 'group-topic-member',
      createdAt: DateTime.now().toUtc(),
      createdBy: 'peer-admin',
      myRole: GroupRole.member,
    );
    await groupRepo.saveGroup(memberGroup);
    await groupRepo.saveMember(GroupMember(
      groupId: 'group-member-only',
      peerId: 'peer-target',
      role: MemberRole.writer,
      joinedAt: DateTime.now().toUtc(),
    ));

    expect(
      () => removeGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: 'group-member-only',
        memberPeerId: 'peer-target',
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Only admins can remove members'),
        ),
      ),
    );
  });

  test('removes member from DB before calling bridge', () async {
    await removeGroupMember(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: 'group-1',
      memberPeerId: 'peer-to-remove',
    );

    // Member removed
    final member = await groupRepo.getMember('group-1', 'peer-to-remove');
    expect(member, isNull);

    // Bridge was called for updateConfig
    expect(bridge.commandLog, equals(['group:updateConfig']));
  });
}
