import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/join_group_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

void main() {
  late FakeBridge bridge;
  late InMemoryGroupRepository groupRepo;

  final testGroup = GroupModel(
    id: 'group-join-1',
    name: 'Join Group',
    type: GroupType.chat,
    topicName: 'group-topic-join-1',
    createdAt: DateTime.now().toUtc(),
    createdBy: 'peer-creator',
    myRole: GroupRole.member,
  );

  setUp(() {
    bridge = FakeBridge();
    groupRepo = InMemoryGroupRepository();

    bridge.responses['group:join'] = {'ok': true};
  });

  test('joins group successfully', () async {
    await joinGroup(
      bridge: bridge,
      groupRepo: groupRepo,
      group: testGroup,
      groupKey: 'shared-group-key',
      keyEpoch: 0,
      selfPeerId: 'peer-self',
      selfPublicKey: 'pk-self',
      selfRole: MemberRole.writer,
    );

    final saved = await groupRepo.getGroup('group-join-1');
    expect(saved, isNotNull);
    expect(saved!.name, 'Join Group');
  });

  test('saves group, member, and key', () async {
    await joinGroup(
      bridge: bridge,
      groupRepo: groupRepo,
      group: testGroup,
      groupKey: 'shared-group-key',
      keyEpoch: 0,
      selfPeerId: 'peer-self',
      selfPublicKey: 'pk-self',
      selfRole: MemberRole.writer,
    );

    // Group saved
    final group = await groupRepo.getGroup('group-join-1');
    expect(group, isNotNull);

    // Member saved
    final member = await groupRepo.getMember('group-join-1', 'peer-self');
    expect(member, isNotNull);
    expect(member!.role, MemberRole.writer);

    // Key saved
    final key = await groupRepo.getLatestKey('group-join-1');
    expect(key, isNotNull);
    expect(key!.encryptedKey, 'shared-group-key');
    expect(key.keyGeneration, 0);
  });

  test('calls bridge join command', () async {
    await joinGroup(
      bridge: bridge,
      groupRepo: groupRepo,
      group: testGroup,
      groupKey: 'shared-group-key',
      keyEpoch: 0,
      selfPeerId: 'peer-self',
      selfPublicKey: 'pk-self',
      selfRole: MemberRole.writer,
    );

    expect(bridge.commandLog, contains('group:join'));
  });
}
