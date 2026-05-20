import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/rotate_group_key_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

void main() {
  late FakeBridge bridge;
  late InMemoryGroupRepository groupRepo;

  setUp(() async {
    bridge = FakeBridge();
    groupRepo = InMemoryGroupRepository();

    await groupRepo.saveGroup(
      GroupModel(
        id: 'group-1',
        name: 'Test Group',
        type: GroupType.chat,
        topicName: 'group-topic-1',
        createdAt: DateTime.now().toUtc(),
        createdBy: 'peer-1',
        myRole: GroupRole.admin,
      ),
    );

    await groupRepo.saveKey(
      GroupKeyInfo(
        groupId: 'group-1',
        keyGeneration: 1,
        encryptedKey: 'current-key-gen-1',
        createdAt: DateTime.now().toUtc(),
      ),
    );

    bridge.responses['group:rotateKey'] = {
      'ok': true,
      'keyGeneration': 2,
      'encryptedKey': 'dangerous-legacy-key-gen-2',
    };
  });

  test('KE-014 rotateGroupKey fails closed and preserves latest key', () async {
    await expectLater(
      rotateGroupKey(bridge: bridge, groupRepo: groupRepo, groupId: 'group-1'),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('rotateAndDistributeGroupKey'),
        ),
      ),
    );

    expect(bridge.sendCallCount, 0);
    expect(bridge.commandLog, isEmpty);
    final saved = await groupRepo.getLatestKey('group-1');
    expect(saved, isNotNull);
    expect(saved!.keyGeneration, 1);
    expect(saved.encryptedKey, 'current-key-gen-1');
    expect(await groupRepo.getKeyByGeneration('group-1', 2), isNull);
  });
}
