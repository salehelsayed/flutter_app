import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/create_group_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

void main() {
  late FakeBridge bridge;
  late InMemoryGroupRepository groupRepo;

  setUp(() {
    bridge = FakeBridge();
    groupRepo = InMemoryGroupRepository();

    // Set up bridge response for group:create (Go returns groupKey + keyEpoch)
    bridge.responses['group:create'] = {
      'ok': true,
      'groupId': 'test-group-id',
      'topicName': 'group-test-group-id',
      'groupKey': 'test-group-key-base64',
      'keyEpoch': 1,
    };
    // Fallback: bridge response for group.keygen (used when create doesn't return key)
    bridge.responses['group.keygen'] = {
      'ok': true,
      'groupKey': 'test-group-key-base64',
    };
  });

  test('creates group successfully', () async {
    final result = await createGroup(
      bridge: bridge,
      groupRepo: groupRepo,
      name: 'Test Group',
      type: GroupType.chat,
      creatorPeerId: 'peer-123',
      creatorPublicKey: 'pk-123',
      creatorMlKemPublicKey: 'mlkem-pk-123',
    );

    expect(result.name, 'Test Group');
    expect(result.type, GroupType.chat);
    expect(result.id, 'test-group-id');
    expect(result.myRole, GroupRole.admin);
  });

  test('throws on empty name', () async {
    expect(
      () => createGroup(
        bridge: bridge,
        groupRepo: groupRepo,
        name: '',
        type: GroupType.chat,
        creatorPeerId: 'peer-123',
        creatorPublicKey: 'pk-123',
        creatorMlKemPublicKey: 'mlkem-pk-123',
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('throws on bridge error', () async {
    bridge.responses['group:create'] = {
      'ok': false,
      'errorCode': 'BRIDGE_ERROR',
      'errorMessage': 'Something went wrong',
    };

    expect(
      () => createGroup(
        bridge: bridge,
        groupRepo: groupRepo,
        name: 'Test Group',
        type: GroupType.chat,
        creatorPeerId: 'peer-123',
        creatorPublicKey: 'pk-123',
        creatorMlKemPublicKey: 'mlkem-pk-123',
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('saves group, member, and key to repo', () async {
    await createGroup(
      bridge: bridge,
      groupRepo: groupRepo,
      name: 'Test Group',
      type: GroupType.chat,
      creatorPeerId: 'peer-123',
      creatorPublicKey: 'pk-123',
      creatorMlKemPublicKey: 'mlkem-pk-123',
    );

    // Group saved
    final savedGroup = await groupRepo.getGroup('test-group-id');
    expect(savedGroup, isNotNull);
    expect(savedGroup!.name, 'Test Group');

    // Member saved
    final members = await groupRepo.getMembers('test-group-id');
    expect(members.length, 1);
    expect(members.first.peerId, 'peer-123');

    // Key saved
    final key = await groupRepo.getLatestKey('test-group-id');
    expect(key, isNotNull);
    expect(key!.encryptedKey, 'test-group-key-base64');
    expect(key.keyGeneration, 1);
  });
}
