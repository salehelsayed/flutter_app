import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/announce_restored_device_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

void main() {
  late FakeBridge bridge;
  late InMemoryGroupRepository groupRepo;

  const announced = GroupMemberDeviceIdentity(
    deviceId: 'bob-tablet',
    transportPeerId: 'bob-tablet',
    deviceSigningPublicKey: 'bob-tablet-signing',
    mlKemPublicKey: 'mlkem-bob-tablet',
  );

  GroupModel group(String id, {bool dissolved = false}) => GroupModel(
    id: id,
    name: id,
    type: GroupType.chat,
    topicName: 'topic-$id',
    createdAt: DateTime.utc(2026, 1, 1),
    createdBy: 'bob',
    myRole: GroupRole.member,
    isDissolved: dissolved,
  );

  setUp(() async {
    bridge = FakeBridge();
    bridge.responses['group:publish'] = {
      'ok': true,
      'messageId': 'm',
      'topicPeers': 1,
    };
    groupRepo = InMemoryGroupRepository();
    await groupRepo.saveGroup(group('g-active-1'));
    await groupRepo.saveGroup(group('g-active-2'));
    await groupRepo.saveGroup(group('g-dissolved', dissolved: true));
  });

  Future<int> announce({required bool enabled}) => announceRestoredDeviceToGroups(
    bridge: bridge,
    groupRepo: groupRepo,
    selfPeerId: 'bob',
    accountSigningPublicKey: 'pk-bob',
    accountSigningPrivateKey: 'sk-bob',
    selfUsername: 'Bob',
    announcedDevice: announced,
    nowUtc: () => DateTime.utc(2026, 5, 1, 12),
    multiDeviceSyncEnabled: enabled,
  );

  test('announces to every active (non-dissolved) group, signed by the account', () async {
    final count = await announce(enabled: true);

    expect(count, 2, reason: 'the dissolved group is skipped');
    final publishes = bridge.commandLog.where((c) => c == 'group:publish');
    expect(publishes, hasLength(2));
  });

  test('is a no-op when multiDeviceSync is off', () async {
    final count = await announce(enabled: false);
    expect(count, 0);
    expect(bridge.commandLog.where((c) => c == 'group:publish'), isEmpty);
  });
}
