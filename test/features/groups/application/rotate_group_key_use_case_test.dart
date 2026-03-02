import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/rotate_group_key_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

void main() {
  late FakeBridge bridge;
  late InMemoryGroupRepository groupRepo;

  setUp(() async {
    bridge = FakeBridge();
    groupRepo = InMemoryGroupRepository();

    await groupRepo.saveGroup(GroupModel(
      id: 'group-1',
      name: 'Test Group',
      type: GroupType.chat,
      topicName: 'group-topic-1',
      createdAt: DateTime.now().toUtc(),
      createdBy: 'peer-1',
      myRole: GroupRole.admin,
    ));

    bridge.responses['group:rotateKey'] = {
      'ok': true,
      'keyGeneration': 2,
      'encryptedKey': 'rotated-key-gen-2',
    };
  });

  test('rotates key successfully', () async {
    final keyInfo = await rotateGroupKey(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: 'group-1',
    );

    expect(keyInfo.keyGeneration, 2);
    expect(keyInfo.encryptedKey, 'rotated-key-gen-2');
  });

  test('saves new key to repo', () async {
    await rotateGroupKey(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: 'group-1',
    );

    final saved = await groupRepo.getLatestKey('group-1');
    expect(saved, isNotNull);
    expect(saved!.keyGeneration, 2);
    expect(saved.encryptedKey, 'rotated-key-gen-2');
  });

  test('returns GroupKeyInfo with correct data', () async {
    final keyInfo = await rotateGroupKey(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: 'group-1',
    );

    expect(keyInfo.groupId, 'group-1');
    expect(keyInfo.keyGeneration, 2);
    expect(keyInfo.encryptedKey, 'rotated-key-gen-2');
  });
}
