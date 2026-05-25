import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/groups/application/remove_group_member_use_case.dart';
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
    createdBy: 'peer-admin',
    myRole: GroupRole.admin,
  );

  setUp(() async {
    bridge = FakeBridge();
    groupRepo = InMemoryGroupRepository();
    groupRecoveryGate.resetForTest();

    await groupRepo.saveGroup(testGroup);
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-admin',
        username: 'Admin',
        role: MemberRole.admin,
        publicKey: 'pk-admin',
        joinedAt: DateTime.now().toUtc(),
      ),
    );
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-to-remove',
        username: 'RemoveMe',
        role: MemberRole.writer,
        publicKey: 'pk-remove',
        joinedAt: DateTime.now().toUtc(),
      ),
    );
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-bystander',
        username: 'Bystander',
        role: MemberRole.writer,
        publicKey: 'pk-bystander',
        joinedAt: DateTime.now().toUtc(),
      ),
    );
  });

  tearDown(() {
    groupRecoveryGate.resetForTest();
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

  test('GM-015 blocks creator/admin self-removal before mutation', () async {
    const groupId = 'group-gm015-self-remove';
    const alicePeerId = 'peer-gm015-alice';
    const bobPeerId = 'peer-gm015-bob';
    const charliePeerId = 'peer-gm015-charlie';
    final createdAt = DateTime.utc(2026, 5, 11, 1);
    final eventAt = createdAt.add(const Duration(minutes: 1));
    final keyCreatedAt = createdAt.add(const Duration(seconds: 30));

    await groupRepo.saveGroup(
      GroupModel(
        id: groupId,
        name: 'GM-015 Group',
        type: GroupType.chat,
        topicName: 'group-topic-gm015',
        createdAt: createdAt,
        createdBy: alicePeerId,
        myRole: GroupRole.admin,
      ),
    );
    await groupRepo.saveMember(
      GroupMember(
        groupId: groupId,
        peerId: alicePeerId,
        username: 'Alice',
        role: MemberRole.admin,
        publicKey: 'pk-gm015-alice',
        joinedAt: createdAt,
      ),
    );
    await groupRepo.saveMember(
      GroupMember(
        groupId: groupId,
        peerId: bobPeerId,
        username: 'Bob',
        role: MemberRole.writer,
        publicKey: 'pk-gm015-bob',
        joinedAt: createdAt.add(const Duration(seconds: 1)),
      ),
    );
    await groupRepo.saveMember(
      GroupMember(
        groupId: groupId,
        peerId: charliePeerId,
        username: 'Charlie',
        role: MemberRole.writer,
        publicKey: 'pk-gm015-charlie',
        joinedAt: createdAt.add(const Duration(seconds: 2)),
      ),
    );
    await groupRepo.saveKey(
      GroupKeyInfo(
        groupId: groupId,
        keyGeneration: 1,
        encryptedKey: 'gm015-initial-key',
        createdAt: keyCreatedAt,
      ),
    );

    await expectLater(
      removeGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        memberPeerId: alicePeerId,
        selfPeerId: alicePeerId,
        actorUsername: 'Alice',
        eventAt: eventAt,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains(lastAdminRemovalBlockedMessage),
        ),
      ),
    );

    final group = await groupRepo.getGroup(groupId);
    expect(group, isNotNull);
    expect(group!.createdBy, alicePeerId);
    expect(group.isDissolved, isFalse);
    final members = await groupRepo.getMembers(groupId);
    expect(members.map((member) => member.peerId), [
      alicePeerId,
      bobPeerId,
      charliePeerId,
    ]);
    expect(
      members.where((member) => member.role == MemberRole.admin),
      hasLength(1),
    );
    expect(
      members.singleWhere((member) => member.peerId == alicePeerId).role,
      MemberRole.admin,
    );
    final latestKey = await groupRepo.getLatestKey(groupId);
    expect(latestKey, isNotNull);
    expect(latestKey!.keyGeneration, 1);
    expect(latestKey.encryptedKey, 'gm015-initial-key');
    expect(latestKey.createdAt, keyCreatedAt);
    expect(bridge.commandLog, isNot(contains('group:updateConfig')));
    expect(bridge.commandLog, isNot(contains('group:publish')));
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
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-member-only',
        peerId: 'peer-target',
        role: MemberRole.writer,
        joinedAt: DateTime.now().toUtc(),
      ),
    );

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

  test(
    'ML-013 bare writer cannot remove active member or sync config',
    () async {
      const groupId = 'group-ml013-remove';
      await groupRepo.saveGroup(
        GroupModel(
          id: groupId,
          name: 'ML-013 Remove Guard',
          type: GroupType.chat,
          topicName: 'group-topic-ml013-remove',
          createdAt: DateTime.now().toUtc(),
          createdBy: 'peer-admin',
          myRole: GroupRole.member,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: 'peer-admin',
          username: 'Admin',
          role: MemberRole.admin,
          publicKey: 'pk-admin',
          joinedAt: DateTime.now().toUtc(),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: 'peer-b',
          username: 'Writer',
          role: MemberRole.writer,
          publicKey: 'pk-b',
          joinedAt: DateTime.now().toUtc(),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: 'peer-c',
          username: 'Target',
          role: MemberRole.writer,
          publicKey: 'pk-c',
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      await expectLater(
        removeGroupMember(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: groupId,
          memberPeerId: 'peer-c',
          selfPeerId: 'peer-b',
        ),
        throwsA(isA<StateError>()),
      );

      expect(await groupRepo.getMember(groupId, 'peer-c'), isNotNull);
      expect(bridge.commandLog, isNot(contains('group:updateConfig')));
    },
  );

  test(
    'allows writer with remove permission override to remove member',
    () async {
      const groupId = 'group-custom-remove';
      await groupRepo.saveGroup(
        GroupModel(
          id: groupId,
          name: 'Moderated Group',
          type: GroupType.chat,
          topicName: 'group-topic-moderated',
          createdAt: DateTime.now().toUtc(),
          createdBy: 'peer-admin',
          myRole: GroupRole.member,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: 'peer-moderator',
          username: 'Moderator',
          role: MemberRole.writer,
          permissions: const GroupMemberPermissions(removeMembers: true),
          publicKey: 'pk-moderator',
          joinedAt: DateTime.now().toUtc(),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: 'peer-target',
          username: 'Target',
          role: MemberRole.reader,
          publicKey: 'pk-target',
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      await removeGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        memberPeerId: 'peer-target',
        selfPeerId: 'peer-moderator',
      );

      expect(await groupRepo.getMember(groupId, 'peer-target'), isNull);
      expect(bridge.commandLog, contains('group:updateConfig'));

      final updateConfigMessage = bridge.sentMessages.firstWhere((message) {
        final parsed = jsonDecode(message) as Map<String, dynamic>;
        return parsed['cmd'] == 'group:updateConfig';
      });
      final payload =
          (jsonDecode(updateConfigMessage) as Map<String, dynamic>)['payload']
              as Map<String, dynamic>;
      final groupConfig = payload['groupConfig'] as Map<String, dynamic>;
      final members = (groupConfig['members'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final moderatorEntry = members.firstWhere(
        (member) => member['peerId'] == 'peer-moderator',
      );
      expect(moderatorEntry['role'], 'writer');
      expect(moderatorEntry['permissions'], {'removeMembers': true});
    },
  );

  test('G3-005 writer with remove permission cannot remove an admin', () async {
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-moderator',
        username: 'Moderator',
        role: MemberRole.writer,
        permissions: const GroupMemberPermissions(removeMembers: true),
        publicKey: 'pk-moderator',
        joinedAt: DateTime.utc(2026, 5, 24, 8),
      ),
    );
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-other-admin',
        username: 'Other Admin',
        role: MemberRole.admin,
        publicKey: 'pk-other-admin',
        joinedAt: DateTime.utc(2026, 5, 24, 8, 1),
      ),
    );

    await expectLater(
      removeGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: 'group-1',
        memberPeerId: 'peer-other-admin',
        selfPeerId: 'peer-moderator',
        eventAt: DateTime.utc(2026, 5, 24, 8, 2),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains(removeAdminRoleBoundaryBlockedMessage),
        ),
      ),
    );

    expect(await groupRepo.getMember('group-1', 'peer-other-admin'), isNotNull);
    expect(bridge.commandLog, isNot(contains('group:updateConfig')));
  });

  test(
    'G3-006 rejects stale remove event before local or bridge mutation',
    () async {
      final watermark = DateTime.utc(2026, 5, 24, 9);
      await groupRepo.updateGroup(
        testGroup.copyWith(lastMembershipEventAt: watermark),
      );

      await expectLater(
        removeGroupMember(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: 'group-1',
          memberPeerId: 'peer-to-remove',
          selfPeerId: 'peer-admin',
          eventAt: watermark,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains(staleGroupMembershipEventMessage),
          ),
        ),
      );

      expect(await groupRepo.getMember('group-1', 'peer-to-remove'), isNotNull);
      expect(bridge.commandLog, isNot(contains('group:updateConfig')));
    },
  );

  test('G3-009 saves removed member snapshot before deleting member', () async {
    final removedAt = DateTime.utc(2026, 5, 24, 10);

    await removeGroupMember(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: 'group-1',
      memberPeerId: 'peer-to-remove',
      selfPeerId: 'peer-admin',
      eventAt: removedAt,
    );

    expect(await groupRepo.getMember('group-1', 'peer-to-remove'), isNull);
    final snapshot = await groupRepo.getRemovedMemberSnapshot(
      'group-1',
      'peer-to-remove',
    );
    expect(snapshot, isNotNull);
    expect(snapshot!.publicKey, 'pk-remove');
    expect(snapshot.username, 'RemoveMe');
  });

  test('G3-010 rejects remove on dissolved group before mutation', () async {
    final dissolvedAt = DateTime.utc(2026, 5, 24, 11);
    await groupRepo.updateGroup(
      testGroup.copyWith(
        isDissolved: true,
        dissolvedAt: dissolvedAt,
        dissolvedBy: 'peer-admin',
      ),
    );

    await expectLater(
      removeGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: 'group-1',
        memberPeerId: 'peer-to-remove',
        selfPeerId: 'peer-admin',
        eventAt: dissolvedAt.add(const Duration(minutes: 1)),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains(groupMembershipMutationDissolvedMessage),
        ),
      ),
    );

    expect(await groupRepo.getMember('group-1', 'peer-to-remove'), isNotNull);
    expect(bridge.commandLog, isNot(contains('group:updateConfig')));
  });

  test(
    'rechecks revoked remove permission before removing a queued target',
    () async {
      const groupId = 'group-stale-remove';
      await groupRepo.saveGroup(
        GroupModel(
          id: groupId,
          name: 'Stale Remove Group',
          type: GroupType.chat,
          topicName: 'group-topic-stale-remove',
          createdAt: DateTime.now().toUtc(),
          createdBy: 'peer-admin',
          myRole: GroupRole.member,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: 'peer-moderator',
          username: 'Moderator',
          role: MemberRole.writer,
          permissions: const GroupMemberPermissions(removeMembers: true),
          publicKey: 'pk-moderator',
          joinedAt: DateTime.now().toUtc(),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: 'peer-moderator',
          username: 'Moderator',
          role: MemberRole.writer,
          publicKey: 'pk-moderator',
          joinedAt: DateTime.now().toUtc(),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: 'peer-target',
          username: 'Target',
          role: MemberRole.reader,
          publicKey: 'pk-target',
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      await expectLater(
        removeGroupMember(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: groupId,
          memberPeerId: 'peer-target',
          selfPeerId: 'peer-moderator',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Only admins can remove members'),
          ),
        ),
      );

      expect(await groupRepo.getMember(groupId, 'peer-target'), isNotNull);
      expect(bridge.commandLog, isEmpty);
    },
  );

  test('denies admin whose remove permission override is false', () async {
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-admin',
        username: 'Admin',
        role: MemberRole.admin,
        permissions: const GroupMemberPermissions(removeMembers: false),
        publicKey: 'pk-admin',
        joinedAt: DateTime.now().toUtc(),
      ),
    );

    await expectLater(
      removeGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: 'group-1',
        memberPeerId: 'peer-to-remove',
        selfPeerId: 'peer-admin',
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Only admins can remove members'),
        ),
      ),
    );

    expect(await groupRepo.getMember('group-1', 'peer-to-remove'), isNotNull);
    expect(bridge.commandLog, isEmpty);
  });

  test(
    'blocks removing the last admin before local or bridge changes',
    () async {
      await expectLater(
        removeGroupMember(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: 'group-1',
          memberPeerId: 'peer-admin',
          selfPeerId: 'peer-admin',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains(lastAdminRemovalBlockedMessage),
          ),
        ),
      );

      expect(await groupRepo.getMember('group-1', 'peer-admin'), isNotNull);
      expect(await groupRepo.getMember('group-1', 'peer-to-remove'), isNotNull);
      expect(bridge.commandLog, isEmpty);
    },
  );

  test('allows removing an admin when another admin remains', () async {
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-other-admin',
        username: 'Other Admin',
        role: MemberRole.admin,
        publicKey: 'pk-other-admin',
        joinedAt: DateTime.now().toUtc(),
      ),
    );

    await removeGroupMember(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: 'group-1',
      memberPeerId: 'peer-other-admin',
      selfPeerId: 'peer-admin',
    );

    expect(await groupRepo.getMember('group-1', 'peer-other-admin'), isNull);
    expect(await groupRepo.getMember('group-1', 'peer-admin'), isNotNull);
    expect(bridge.commandLog, contains('group:updateConfig'));
  });

  test('rejects while group recovery is in progress', () async {
    groupRecoveryGate.begin();
    try {
      await expectLater(
        removeGroupMember(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: 'group-1',
          memberPeerId: 'peer-to-remove',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains(groupRecoveryPendingError),
          ),
        ),
      );
    } finally {
      groupRecoveryGate.end();
    }

    final member = await groupRepo.getMember('group-1', 'peer-to-remove');
    expect(member, isNotNull);
    expect(bridge.commandLog, isEmpty);
  });

  test(
    'rejects non-member before sync and preserves existing members',
    () async {
      await expectLater(
        removeGroupMember(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: 'group-1',
          memberPeerId: 'peer-absent',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Member not found'),
          ),
        ),
      );

      expect(bridge.commandLog, isEmpty);
      expect(await groupRepo.getMember('group-1', 'peer-admin'), isNotNull);
      expect(await groupRepo.getMember('group-1', 'peer-to-remove'), isNotNull);
      expect(await groupRepo.getMember('group-1', 'peer-bystander'), isNotNull);
    },
  );

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

  test('groupConfig sent to bridge excludes removed member', () async {
    await removeGroupMember(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: 'group-1',
      memberPeerId: 'peer-to-remove',
    );

    // Parse the group:updateConfig command from sentMessages
    final updateConfigMsg = bridge.sentMessages.firstWhere((m) {
      final parsed = jsonDecode(m) as Map<String, dynamic>;
      return parsed['cmd'] == 'group:updateConfig';
    });
    final payload =
        (jsonDecode(updateConfigMsg) as Map<String, dynamic>)['payload']
            as Map<String, dynamic>;
    final groupConfig = payload['groupConfig'] as Map<String, dynamic>;
    final memberPeerIds = (groupConfig['members'] as List)
        .map((m) => (m as Map<String, dynamic>)['peerId'] as String)
        .toList();

    // Removed member must NOT be in the config
    expect(memberPeerIds, isNot(contains('peer-to-remove')));

    // Admin and bystander must still be present
    expect(memberPeerIds, contains('peer-admin'));
    expect(memberPeerIds, contains('peer-bystander'));
  });

  test(
    'ML-005 online remove excludes target from repo and bridge config while preserving remaining members',
    () async {
      final eventAt = DateTime.utc(2026, 5, 11, 12, 5);
      expect(await groupRepo.getMember('group-1', 'peer-to-remove'), isNotNull);
      expect(await groupRepo.getMember('group-1', 'peer-admin'), isNotNull);
      expect(await groupRepo.getMember('group-1', 'peer-bystander'), isNotNull);

      await removeGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: 'group-1',
        memberPeerId: 'peer-to-remove',
        eventAt: eventAt,
      );

      expect(await groupRepo.getMember('group-1', 'peer-to-remove'), isNull);
      final remainingMembers = await groupRepo.getMembers('group-1');
      expect(remainingMembers.map((member) => member.peerId).toSet(), {
        'peer-admin',
        'peer-bystander',
      });

      expect(bridge.commandLog, equals(['group:updateConfig']));
      final updateConfigMsg = bridge.sentMessages.firstWhere((m) {
        final parsed = jsonDecode(m) as Map<String, dynamic>;
        return parsed['cmd'] == 'group:updateConfig';
      });
      final payload =
          (jsonDecode(updateConfigMsg) as Map<String, dynamic>)['payload']
              as Map<String, dynamic>;
      final groupConfig = payload['groupConfig'] as Map<String, dynamic>;
      final memberPeerIds = (groupConfig['members'] as List)
          .map((m) => (m as Map<String, dynamic>)['peerId'] as String)
          .toSet();

      expect(memberPeerIds, {'peer-admin', 'peer-bystander'});
      expect(memberPeerIds, isNot(contains('peer-to-remove')));

      final updatedGroup = await groupRepo.getGroup('group-1');
      expect(updatedGroup?.lastMembershipEventAt, eventAt);
    },
  );

  test('groupConfig has correct structure with all required fields', () async {
    await removeGroupMember(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: 'group-1',
      memberPeerId: 'peer-to-remove',
    );

    final updateConfigMsg = bridge.sentMessages.firstWhere((m) {
      final parsed = jsonDecode(m) as Map<String, dynamic>;
      return parsed['cmd'] == 'group:updateConfig';
    });
    final payload =
        (jsonDecode(updateConfigMsg) as Map<String, dynamic>)['payload']
            as Map<String, dynamic>;
    final groupConfig = payload['groupConfig'] as Map<String, dynamic>;

    // Top-level required fields
    expect(groupConfig['name'], 'Test Group');
    expect(groupConfig['groupType'], isNotNull);
    expect(groupConfig['createdBy'], 'peer-admin');
    expect(groupConfig['createdAt'], isNotNull);
    expect(groupConfig['members'], isList);

    // Each member must have peerId, role, publicKey
    final members = groupConfig['members'] as List;
    for (final m in members) {
      final member = m as Map<String, dynamic>;
      expect(member['peerId'], isNotNull);
      expect(member['role'], isNotNull);
      expect(member['publicKey'], isNotNull);
    }
  });

  test('restores removed member when group:updateConfig fails', () async {
    bridge.responses['group:updateConfig'] = {
      'ok': false,
      'errorCode': 'CONFIG_SYNC_FAILED',
      'errorMessage': 'bridge rejected config',
    };

    await expectLater(
      removeGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: 'group-1',
        memberPeerId: 'peer-to-remove',
      ),
      throwsA(isA<Exception>()),
    );

    final restored = await groupRepo.getMember('group-1', 'peer-to-remove');
    expect(restored, isNotNull);
    expect(restored!.username, 'RemoveMe');

    final admin = await groupRepo.getMember('group-1', 'peer-admin');
    final bystander = await groupRepo.getMember('group-1', 'peer-bystander');
    expect(admin, isNotNull);
    expect(bystander, isNotNull);
  });

  test('ML-005 config sync failure restores removed online member', () async {
    bridge.responses['group:updateConfig'] = {
      'ok': false,
      'errorCode': 'CONFIG_SYNC_FAILED',
      'errorMessage': 'bridge rejected config',
    };

    await expectLater(
      removeGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: 'group-1',
        memberPeerId: 'peer-to-remove',
        eventAt: DateTime.utc(2026, 5, 11, 12, 10),
      ),
      throwsA(isA<Exception>()),
    );

    final restored = await groupRepo.getMember('group-1', 'peer-to-remove');
    expect(restored, isNotNull);
    expect(restored!.username, 'RemoveMe');
    expect(await groupRepo.getMember('group-1', 'peer-admin'), isNotNull);
    expect(await groupRepo.getMember('group-1', 'peer-bystander'), isNotNull);
    final updatedGroup = await groupRepo.getGroup('group-1');
    expect(updatedGroup?.lastMembershipEventAt, isNull);
  });
}
