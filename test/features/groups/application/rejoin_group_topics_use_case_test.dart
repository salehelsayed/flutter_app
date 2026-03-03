import 'dart:convert';

import 'package:flutter_app/features/groups/application/rejoin_group_topics_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

void main() {
  late FakeBridge bridge;
  late InMemoryGroupRepository groupRepo;

  setUp(() {
    bridge = FakeBridge();
    groupRepo = InMemoryGroupRepository();
  });

  /// Helper to create a group with members and a key in the repo.
  Future<void> seedGroup({
    required String groupId,
    required String name,
    List<GroupMember>? members,
    GroupKeyInfo? keyInfo,
  }) async {
    await groupRepo.saveGroup(GroupModel(
      id: groupId,
      name: name,
      type: GroupType.chat,
      topicName: 'topic-$groupId',
      createdAt: DateTime.now().toUtc(),
      createdBy: 'admin-peer',
      myRole: GroupRole.admin,
    ));

    if (members != null) {
      for (final m in members) {
        await groupRepo.saveMember(m);
      }
    }

    if (keyInfo != null) {
      await groupRepo.saveKey(keyInfo);
    }
  }

  group('rejoinGroupTopics', () {
    test('calls callGroupJoinWithConfig for each active group', () async {
      // -- arrange --
      final now = DateTime.now().toUtc();

      await seedGroup(
        groupId: 'group-1',
        name: 'Group One',
        members: [
          GroupMember(
            groupId: 'group-1',
            peerId: 'alice',
            username: 'Alice',
            role: MemberRole.admin,
            publicKey: 'pk-alice',
            joinedAt: now,
          ),
          GroupMember(
            groupId: 'group-1',
            peerId: 'bob',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-bob',
            joinedAt: now,
          ),
        ],
        keyInfo: GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 1,
          encryptedKey: 'key-1-base64',
          createdAt: now,
        ),
      );

      await seedGroup(
        groupId: 'group-2',
        name: 'Group Two',
        members: [
          GroupMember(
            groupId: 'group-2',
            peerId: 'alice',
            username: 'Alice',
            role: MemberRole.admin,
            publicKey: 'pk-alice',
            joinedAt: now,
          ),
        ],
        keyInfo: GroupKeyInfo(
          groupId: 'group-2',
          keyGeneration: 3,
          encryptedKey: 'key-2-base64',
          createdAt: now,
        ),
      );

      // -- act --
      await rejoinGroupTopics(bridge: bridge, groupRepo: groupRepo);

      // -- assert --
      final joinCommands = bridge.sentMessages
          .map((m) => jsonDecode(m) as Map<String, dynamic>)
          .where((m) => m['cmd'] == 'group:join')
          .toList();

      expect(joinCommands, hasLength(2));

      final groupIds =
          joinCommands.map((c) => c['payload']['groupId'] as String).toSet();
      expect(groupIds, {'group-1', 'group-2'});
    });

    test('skips groups with no key info', () async {
      final now = DateTime.now().toUtc();

      // Group with key
      await seedGroup(
        groupId: 'group-with-key',
        name: 'Has Key',
        members: [
          GroupMember(
            groupId: 'group-with-key',
            peerId: 'alice',
            username: 'Alice',
            role: MemberRole.admin,
            publicKey: 'pk-alice',
            joinedAt: now,
          ),
        ],
        keyInfo: GroupKeyInfo(
          groupId: 'group-with-key',
          keyGeneration: 1,
          encryptedKey: 'key-base64',
          createdAt: now,
        ),
      );

      // Group without key — should be skipped
      await seedGroup(
        groupId: 'group-no-key',
        name: 'No Key',
        members: [
          GroupMember(
            groupId: 'group-no-key',
            peerId: 'alice',
            username: 'Alice',
            role: MemberRole.admin,
            publicKey: 'pk-alice',
            joinedAt: now,
          ),
        ],
        // No keyInfo
      );

      // -- act --
      await rejoinGroupTopics(bridge: bridge, groupRepo: groupRepo);

      // -- assert --
      final joinCommands = bridge.sentMessages
          .map((m) => jsonDecode(m) as Map<String, dynamic>)
          .where((m) => m['cmd'] == 'group:join')
          .toList();

      expect(joinCommands, hasLength(1));
      expect(joinCommands.first['payload']['groupId'], 'group-with-key');
    });

    test('continues on individual join error', () async {
      final now = DateTime.now().toUtc();

      await seedGroup(
        groupId: 'group-fail',
        name: 'Will Fail',
        members: [
          GroupMember(
            groupId: 'group-fail',
            peerId: 'alice',
            username: 'Alice',
            role: MemberRole.admin,
            publicKey: 'pk-alice',
            joinedAt: now,
          ),
        ],
        keyInfo: GroupKeyInfo(
          groupId: 'group-fail',
          keyGeneration: 1,
          encryptedKey: 'key-fail',
          createdAt: now,
        ),
      );

      await seedGroup(
        groupId: 'group-ok',
        name: 'Will Succeed',
        members: [
          GroupMember(
            groupId: 'group-ok',
            peerId: 'alice',
            username: 'Alice',
            role: MemberRole.admin,
            publicKey: 'pk-alice',
            joinedAt: now,
          ),
        ],
        keyInfo: GroupKeyInfo(
          groupId: 'group-ok',
          keyGeneration: 1,
          encryptedKey: 'key-ok',
          createdAt: now,
        ),
      );

      // Make all joins fail — the important thing is the function doesn't throw
      bridge.responses['group:join'] = {'ok': false, 'errorCode': 'TEST_FAIL'};

      // -- act -- (should not throw)
      await rejoinGroupTopics(bridge: bridge, groupRepo: groupRepo);

      // -- assert: both groups were attempted despite errors --
      final joinCommands = bridge.sentMessages
          .map((m) => jsonDecode(m) as Map<String, dynamic>)
          .where((m) => m['cmd'] == 'group:join')
          .toList();

      expect(joinCommands, hasLength(2),
          reason: 'Both groups should be attempted even when joins fail');
    });

    test('does nothing when no active groups exist', () async {
      // -- act --
      await rejoinGroupTopics(bridge: bridge, groupRepo: groupRepo);

      // -- assert --
      expect(bridge.sendCallCount, 0);
      expect(bridge.sentMessages, isEmpty);
    });

    test('builds correct groupConfig from stored members', () async {
      final now = DateTime.now().toUtc();

      await seedGroup(
        groupId: 'group-config',
        name: 'Config Test',
        members: [
          GroupMember(
            groupId: 'group-config',
            peerId: 'admin-peer',
            username: 'Admin',
            role: MemberRole.admin,
            publicKey: 'pk-admin',
            mlKemPublicKey: 'mlkem-admin',
            joinedAt: now,
          ),
          GroupMember(
            groupId: 'group-config',
            peerId: 'member-peer',
            username: 'Member',
            role: MemberRole.writer,
            publicKey: 'pk-member',
            joinedAt: now,
          ),
        ],
        keyInfo: GroupKeyInfo(
          groupId: 'group-config',
          keyGeneration: 5,
          encryptedKey: 'key-config-base64',
          createdAt: now,
        ),
      );

      // -- act --
      await rejoinGroupTopics(bridge: bridge, groupRepo: groupRepo);

      // -- assert --
      final joinCommands = bridge.sentMessages
          .map((m) => jsonDecode(m) as Map<String, dynamic>)
          .where((m) => m['cmd'] == 'group:join')
          .toList();

      expect(joinCommands, hasLength(1));
      final payload = joinCommands.first['payload'] as Map<String, dynamic>;

      expect(payload['groupId'], 'group-config');
      expect(payload['groupKey'], 'key-config-base64');
      expect(payload['keyEpoch'], 5);

      final config = payload['groupConfig'] as Map<String, dynamic>;
      expect(config['name'], 'Config Test');
      expect(config['groupType'], 'chat');

      final members = config['members'] as List<dynamic>;
      expect(members, hasLength(2));

      final adminMember = members.firstWhere(
          (m) => (m as Map<String, dynamic>)['peerId'] == 'admin-peer');
      expect(adminMember['publicKey'], 'pk-admin');
      expect(adminMember['mlKemPublicKey'], 'mlkem-admin');
      expect(adminMember['role'], 'admin');

      final regularMember = members.firstWhere(
          (m) => (m as Map<String, dynamic>)['peerId'] == 'member-peer');
      expect(regularMember['publicKey'], 'pk-member');
      expect(regularMember['role'], 'writer');
    });

    test('skips archived groups', () async {
      final now = DateTime.now().toUtc();

      // Active group
      await seedGroup(
        groupId: 'group-active',
        name: 'Active',
        members: [
          GroupMember(
            groupId: 'group-active',
            peerId: 'alice',
            username: 'Alice',
            role: MemberRole.admin,
            publicKey: 'pk-alice',
            joinedAt: now,
          ),
        ],
        keyInfo: GroupKeyInfo(
          groupId: 'group-active',
          keyGeneration: 1,
          encryptedKey: 'key-active',
          createdAt: now,
        ),
      );

      // Archived group
      await seedGroup(
        groupId: 'group-archived',
        name: 'Archived',
        members: [
          GroupMember(
            groupId: 'group-archived',
            peerId: 'alice',
            username: 'Alice',
            role: MemberRole.admin,
            publicKey: 'pk-alice',
            joinedAt: now,
          ),
        ],
        keyInfo: GroupKeyInfo(
          groupId: 'group-archived',
          keyGeneration: 1,
          encryptedKey: 'key-archived',
          createdAt: now,
        ),
      );
      await groupRepo.archiveGroup('group-archived');

      // -- act --
      await rejoinGroupTopics(bridge: bridge, groupRepo: groupRepo);

      // -- assert --
      final joinCommands = bridge.sentMessages
          .map((m) => jsonDecode(m) as Map<String, dynamic>)
          .where((m) => m['cmd'] == 'group:join')
          .toList();

      expect(joinCommands, hasLength(1));
      expect(joinCommands.first['payload']['groupId'], 'group-active');
    });
  });
}
