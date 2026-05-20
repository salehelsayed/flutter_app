import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/add_group_member_use_case.dart';
import 'package:flutter_app/features/groups/application/create_group_use_case.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/remove_group_member_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

void main() {
  group('UP-001 membership/config sync', () {
    late FakeBridge bridge;
    late InMemoryGroupRepository groupRepo;

    setUp(() {
      bridge = FakeBridge(
        initialResponses: {
          'group:create': {
            'ok': true,
            'groupId': 'up001-group',
            'topicName': 'topic-up001-group',
            'groupKey': 'up001-group-key',
            'keyEpoch': 1,
          },
        },
      );
      groupRepo = InMemoryGroupRepository();
    });

    Future<void> expectDbMembers(Set<String> expectedPeerIds) async {
      final members = await groupRepo.getMembers('up001-group');
      expect(members.map((member) => member.peerId).toSet(), expectedPeerIds);
    }

    Future<void> expectDbAndLatestConfig({
      required String groupId,
      required Set<String> expectedPeerIds,
    }) async {
      await expectDbMembers(expectedPeerIds);

      final updateConfigPayload = _payloadsFor(
        bridge,
        'group:updateConfig',
      ).last;
      expect(updateConfigPayload['groupId'], groupId);
      final groupConfig =
          updateConfigPayload['groupConfig'] as Map<String, dynamic>;
      expect(
        isGroupConfigStateHashValid(groupId: groupId, groupConfig: groupConfig),
        isTrue,
      );
      final configPeerIds = (groupConfig['members'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((member) => member['peerId'] as String)
          .toSet();
      expect(configPeerIds, expectedPeerIds);
    }

    test(
      'create add remove and re-add keep local DB and Go config payloads aligned',
      () async {
        final group = await createGroup(
          bridge: bridge,
          groupRepo: groupRepo,
          name: 'UP-001 Group',
          type: GroupType.chat,
          creatorPeerId: 'peer-admin',
          creatorPublicKey: 'pk-admin',
          creatorMlKemPublicKey: 'mlkem-admin',
          creatorUsername: 'Admin',
        );

        await expectDbMembers({'peer-admin'});
        final createPayload = _payloadsFor(bridge, 'group:create').single;
        expect(createPayload['creatorPeerId'], 'peer-admin');
        expect(createPayload['creatorPublicKey'], 'pk-admin');
        expect(createPayload['creatorMlKemPublicKey'], 'mlkem-admin');

        final bobFirstJoin = _member(
          peerId: 'peer-bob',
          username: 'Bob',
          joinedAt: DateTime.utc(2026, 5, 13, 10),
        );
        await addGroupMember(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: group.id,
          newMember: bobFirstJoin,
          selfPeerId: 'peer-admin',
        );
        await expectDbAndLatestConfig(
          groupId: group.id,
          expectedPeerIds: {'peer-admin', 'peer-bob'},
        );

        await removeGroupMember(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: group.id,
          memberPeerId: 'peer-bob',
          selfPeerId: 'peer-admin',
          eventAt: DateTime.utc(2026, 5, 13, 11),
        );
        await expectDbAndLatestConfig(
          groupId: group.id,
          expectedPeerIds: {'peer-admin'},
        );

        final bobRejoin = _member(
          peerId: 'peer-bob',
          username: 'Bob',
          joinedAt: DateTime.utc(2026, 5, 13, 12),
        );
        await addGroupMember(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: group.id,
          newMember: bobRejoin,
          selfPeerId: 'peer-admin',
        );
        await expectDbAndLatestConfig(
          groupId: group.id,
          expectedPeerIds: {'peer-admin', 'peer-bob'},
        );

        expect(
          bridge.commandLog.where((command) => command == 'group:updateConfig'),
          hasLength(3),
        );
      },
    );
  });
}

GroupMember _member({
  required String peerId,
  required String username,
  required DateTime joinedAt,
}) {
  return GroupMember(
    groupId: 'up001-group',
    peerId: peerId,
    username: username,
    role: MemberRole.writer,
    publicKey: 'pk-$peerId',
    mlKemPublicKey: 'mlkem-$peerId',
    joinedAt: joinedAt,
  );
}

List<Map<String, dynamic>> _payloadsFor(FakeBridge bridge, String command) {
  return bridge.sentMessages
      .map((message) => jsonDecode(message) as Map<String, dynamic>)
      .where((message) => message['cmd'] == command)
      .map((message) => message['payload'] as Map<String, dynamic>)
      .toList(growable: false);
}
