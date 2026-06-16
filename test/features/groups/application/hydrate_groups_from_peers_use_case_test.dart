import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/hydrate_groups_from_peers_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';

void main() {
  late FakeBridge bridge;
  late InMemoryGroupRepository groupRepo;
  late InMemoryGroupMessageRepository msgRepo;

  GroupModel group(String id, {bool dissolved = false}) => GroupModel(
    id: id,
    name: id,
    type: GroupType.chat,
    topicName: 'topic-$id',
    createdAt: DateTime.utc(2026, 1, 1),
    createdBy: 'self',
    myRole: GroupRole.member,
    isDissolved: dissolved,
  );

  setUp(() async {
    bridge = FakeBridge();
    groupRepo = InMemoryGroupRepository();
    msgRepo = InMemoryGroupMessageRepository();
    await groupRepo.saveGroup(group('g-active'));
    await groupRepo.saveKey(
      GroupKeyInfo(
        groupId: 'g-active',
        keyGeneration: 1,
        encryptedKey: 'k1',
        createdAt: DateTime.utc(2026, 1, 1),
      ),
    );
    await groupRepo.saveGroup(group('g-dissolved', dissolved: true));
  });

  test('is a no-op (no side effects) when multiDeviceSync is off', () async {
    final count = await hydrateGroupsFromPeers(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      multiDeviceSyncEnabled: false,
    );
    expect(count, 0);
    expect(bridge.commandLog, isEmpty, reason: 'no rejoin / no drain when off');
  });

  test('when on, rejoins topics and drains only non-dissolved groups', () async {
    final count = await hydrateGroupsFromPeers(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      multiDeviceSyncEnabled: true,
    );
    // Only the single active group is drained; the dissolved one is skipped.
    expect(count, 1);
    // rejoinGroupTopics ran (it issues bridge work for the keyed active group).
    expect(bridge.commandLog, isNotEmpty);
  });
}
