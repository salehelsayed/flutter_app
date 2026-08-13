import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/features/groups/application/group_membership_event_watermark.dart';
import 'package:flutter_app/features/groups/application/group_membership_timeline_message.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/protected_group_authority.dart';
import 'package:flutter_app/features/groups/application/protected_group_authority_history.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/groups/application/remove_group_member_use_case.dart';
import 'package:flutter_app/features/groups/application/signed_group_transition_audit.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
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

  test(
    'G5: live caller mints the canonical (eventAt, eventId) pair lifted past a '
    'skew-advanced watermark, and records it — never self-blocks',
    () async {
      // A peer with a fast clock advanced the membership watermark into the
      // future. The live admin caller passes NO explicit eventAt, so the use
      // case must mint monotonically (lift past the watermark) rather than
      // stale-block, and return the pair it recorded. The wired site must then
      // publish THIS pair (not one reconstructed from its own wall clock — the
      // G5 bug), so concurrent removals tie-break against one id everywhere.
      final futureWatermark = DateTime.utc(2099, 1, 1);
      await groupRepo.saveGroup(
        testGroup.copyWith(lastMembershipEventAt: futureWatermark),
      );

      final minted = await removeGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: 'group-1',
        memberPeerId: 'peer-to-remove',
        selfPeerId: 'peer-admin',
        // No eventAt: mint monotonically (mirrors the role toggle).
      );

      // The minted instant was lifted to watermark + 1µs (monotonic, not a
      // wall-clock-now that would have been < the future watermark).
      expect(minted.eventAt.isAfter(futureWatermark), isTrue);
      expect(
        minted.eventAt,
        futureWatermark.add(const Duration(microseconds: 1)),
      );
      // The id is the canonical pair embedding the NORMALIZED instant.
      expect(
        minted.eventId,
        'member_removed:group-1:peer-admin:'
        '${minted.eventAt.microsecondsSinceEpoch}',
      );
      // The same pair is what the group's watermark now carries (so the wired
      // site can read it back / publish it consistently).
      final updated = await groupRepo.getGroup('group-1');
      expect(updated!.lastMembershipEventId, minted.eventId);
      expect(updated.lastMembershipEventAt?.toUtc(), minted.eventAt);
      // The removal still committed despite the skewed watermark.
      expect(await groupRepo.getMember('group-1', 'peer-to-remove'), isNull);
    },
  );

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

  test(
    'protected remove activates only after native config and exact watermark',
    () async {
      final eventAt = DateTime.utc(2026, 8, 13, 11);
      var activated = 0;
      var rolledBack = 0;
      var activationSawExactCommit = false;

      final minted = await removeGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: 'group-1',
        memberPeerId: 'peer-to-remove',
        selfPeerId: 'peer-admin',
        eventAt: eventAt,
        prepareAuthority:
            ({
              required group,
              required members,
              required removedMember,
              required eventAt,
              required eventId,
            }) async => PreparedGroupMemberRemovalAuthority(
              activate: () async {
                activated++;
                final committedGroup = await groupRepo.getGroup('group-1');
                activationSawExactCommit =
                    bridge.commandLog.contains('group:updateConfig') &&
                    await groupRepo.getMember('group-1', 'peer-to-remove') ==
                        null &&
                    committedGroup?.lastMembershipEventAt?.toUtc() ==
                        eventAt.toUtc() &&
                    committedGroup?.lastMembershipEventId == eventId;
              },
              rollback: () async {
                rolledBack++;
              },
            ),
      );

      expect(minted.eventAt, eventAt);
      expect(
        minted.eventId,
        canonicalMembershipEventId(
          transitionType: 'member_removed',
          groupId: 'group-1',
          actorPeerId: 'peer-admin',
          eventAt: eventAt,
        ),
      );
      expect(activated, 1);
      expect(rolledBack, 0);
      expect(activationSawExactCommit, isTrue);
    },
  );

  test(
    'protected remove timeout preserves PREPARED owner and absent projection',
    () async {
      final timeoutBridge = _TimeoutRemoveUpdateConfigBridge();
      var activated = 0;
      var rolledBack = 0;

      await expectLater(
        removeGroupMember(
          bridge: timeoutBridge,
          groupRepo: groupRepo,
          groupId: 'group-1',
          memberPeerId: 'peer-to-remove',
          selfPeerId: 'peer-admin',
          eventAt: DateTime.utc(2026, 8, 13, 11, 1),
          prepareAuthority:
              ({
                required group,
                required members,
                required removedMember,
                required eventAt,
                required eventId,
              }) async => PreparedGroupMemberRemovalAuthority(
                activate: () async {
                  activated++;
                },
                rollback: () async {
                  rolledBack++;
                },
              ),
        ),
        throwsA(
          isA<GroupMemberRemovalCommitAmbiguous>().having(
            (error) => error.cause,
            'cause',
            isA<TimeoutException>(),
          ),
        ),
      );

      expect(timeoutBridge.updateConfigIssued, isTrue);
      expect(await groupRepo.getMember('group-1', 'peer-to-remove'), isNull);
      expect(
        (await groupRepo.getGroup('group-1'))?.lastMembershipEventAt,
        isNull,
      );
      expect(activated, 0);
      expect(rolledBack, 0);
    },
  );

  test('protected remove definite native rejection restores member then aborts '
      'PREPARED', () async {
    bridge.responses['group:updateConfig'] = {
      'ok': false,
      'errorCode': 'CONFIG_REJECTED',
      'errorMessage': 'exact config rejected',
    };
    var activated = 0;
    var rolledBack = 0;

    await expectLater(
      removeGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: 'group-1',
        memberPeerId: 'peer-to-remove',
        selfPeerId: 'peer-admin',
        eventAt: DateTime.utc(2026, 8, 13, 11, 2),
        prepareAuthority:
            ({
              required group,
              required members,
              required removedMember,
              required eventAt,
              required eventId,
            }) async => PreparedGroupMemberRemovalAuthority(
              activate: () async {
                activated++;
              },
              rollback: () async {
                rolledBack++;
                expect(
                  await groupRepo.getMember('group-1', 'peer-to-remove'),
                  isNotNull,
                );
              },
            ),
      ),
      throwsA(
        isA<BridgeCommandException>().having(
          (error) => error.errorCode,
          'errorCode',
          'CONFIG_REJECTED',
        ),
      ),
    );

    expect(await groupRepo.getMember('group-1', 'peer-to-remove'), isNotNull);
    expect(activated, 0);
    expect(rolledBack, 1);
  });

  test('protected remove activation failure stops egress and retains committed '
      'absence for recovery', () async {
    final eventAt = DateTime.utc(2026, 8, 13, 11, 2, 30);
    var rolledBack = 0;

    await expectLater(
      removeGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: 'group-1',
        memberPeerId: 'peer-to-remove',
        selfPeerId: 'peer-admin',
        eventAt: eventAt,
        prepareAuthority:
            ({
              required group,
              required members,
              required removedMember,
              required eventAt,
              required eventId,
            }) async => PreparedGroupMemberRemovalAuthority(
              activate: () async {
                throw StateError('COMPLETE still pending');
              },
              rollback: () async {
                rolledBack++;
              },
            ),
      ),
      throwsA(
        isA<GroupMemberRemovalCommitAmbiguous>().having(
          (error) => error.cause.toString(),
          'cause',
          contains('COMPLETE still pending'),
        ),
      ),
    );

    expect(await groupRepo.getMember('group-1', 'peer-to-remove'), isNull);
    final committedGroup = await groupRepo.getGroup('group-1');
    expect(committedGroup?.lastMembershipEventAt, eventAt);
    expect(committedGroup?.lastMembershipEventId, isNotNull);
    expect(rolledBack, 0);
    expect(
      bridge.commandLog.where((command) => command == 'group:updateConfig'),
      hasLength(1),
    );
  });

  test('protected remove abort refusal is ambiguous after definite native '
      'rejection', () async {
    bridge.responses['group:updateConfig'] = {
      'ok': false,
      'errorCode': 'CONFIG_REJECTED',
      'errorMessage': 'exact config rejected',
    };

    await expectLater(
      removeGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: 'group-1',
        memberPeerId: 'peer-to-remove',
        selfPeerId: 'peer-admin',
        eventAt: DateTime.utc(2026, 8, 13, 11, 2, 45),
        prepareAuthority:
            ({
              required group,
              required members,
              required removedMember,
              required eventAt,
              required eventId,
            }) async => PreparedGroupMemberRemovalAuthority(
              activate: () async {},
              rollback: () async {
                throw StateError('durable ABORT refused');
              },
            ),
      ),
      throwsA(
        isA<GroupMemberRemovalCommitAmbiguous>()
            .having(
              (error) => error.cause,
              'cause',
              isA<BridgeCommandException>(),
            )
            .having(
              (error) => error.rollbackError.toString(),
              'rollbackError',
              contains('durable ABORT refused'),
            ),
      ),
    );

    expect(
      await groupRepo.getMember('group-1', 'peer-to-remove'),
      isNotNull,
      reason: 'local restore precedes the refused durable abort',
    );
  });

  test(
    'protected remove post-delete repository crash retains PREPARED owner',
    () async {
      final crashRepo = _CrashAfterMemberRemoveRepository(
        crashPeerId: 'peer-to-remove',
      );
      await crashRepo.saveGroup(testGroup);
      for (final member in await groupRepo.getMembers('group-1')) {
        await crashRepo.saveMember(member);
      }
      var rolledBack = 0;

      await expectLater(
        removeGroupMember(
          bridge: bridge,
          groupRepo: crashRepo,
          groupId: 'group-1',
          memberPeerId: 'peer-to-remove',
          selfPeerId: 'peer-admin',
          eventAt: DateTime.utc(2026, 8, 13, 11, 3),
          prepareAuthority:
              ({
                required group,
                required members,
                required removedMember,
                required eventAt,
                required eventId,
              }) async => PreparedGroupMemberRemovalAuthority(
                activate: () async {},
                rollback: () async {
                  rolledBack++;
                },
              ),
        ),
        throwsA(isA<GroupMemberRemovalCommitAmbiguous>()),
      );

      expect(await crashRepo.getMember('group-1', 'peer-to-remove'), isNull);
      expect(rolledBack, 0);
      expect(bridge.commandLog, isNot(contains('group:updateConfig')));
    },
  );

  test(
    'protected remove PREPARED repairs pre/post projection after restart and '
    'completes evidence exactly once',
    () async {
      Future<void> proveShape({required bool memberAlreadyRemoved}) async {
        const groupId = 'group-protected-remove-restart';
        const actorPeerId = 'peer-protected-remove-admin';
        const removedPeerId = 'peer-protected-remove-target';
        final suffix = memberAlreadyRemoved ? 'post' : 'pre';
        final eventAt = DateTime.utc(2026, 8, 13, 15);
        final eventId = 'member-removed-restart-$suffix';
        final createdAt = eventAt.subtract(const Duration(days: 2));
        const actorDevice = GroupMemberDeviceIdentity(
          deviceId: 'protected-remove-admin-device',
          transportPeerId: 'protected-remove-admin-transport',
          deviceSigningPublicKey: 'protected-remove-admin-public-key',
          mlKemPublicKey: 'protected-remove-admin-mlkem',
        );
        const removedDevice = GroupMemberDeviceIdentity(
          deviceId: 'protected-remove-target-device',
          transportPeerId: 'protected-remove-target-transport',
          deviceSigningPublicKey: 'protected-remove-target-public-key',
          mlKemPublicKey: 'protected-remove-target-mlkem',
        );
        const survivorDevice = GroupMemberDeviceIdentity(
          deviceId: 'protected-remove-survivor-device',
          transportPeerId: 'protected-remove-survivor-transport',
          deviceSigningPublicKey: 'protected-remove-survivor-public-key',
          mlKemPublicKey: 'protected-remove-survivor-mlkem',
        );
        final repository = InMemoryGroupRepository();
        final messageRepository = InMemoryGroupMessageRepository();
        final recoveryBridge = PassthroughCryptoBridge();
        final history = _RemoveAuthenticatedAuthorityHistory();
        final evidenceByEventId = <String, Map<String, Object?>>{};
        final group = GroupModel(
          id: groupId,
          name: 'Protected remove restart',
          type: GroupType.chat,
          topicName: 'topic-$groupId',
          createdAt: createdAt,
          createdBy: actorPeerId,
          myRole: GroupRole.admin,
        );
        final actor = GroupMember(
          groupId: groupId,
          peerId: actorPeerId,
          username: 'Protected remove admin',
          role: MemberRole.admin,
          publicKey: actorDevice.deviceSigningPublicKey,
          mlKemPublicKey: actorDevice.mlKemPublicKey,
          devices: const <GroupMemberDeviceIdentity>[actorDevice],
          joinedAt: createdAt.add(const Duration(hours: 1)),
        );
        final removed = GroupMember(
          groupId: groupId,
          peerId: removedPeerId,
          username: 'Protected remove target',
          role: MemberRole.writer,
          publicKey: removedDevice.deviceSigningPublicKey,
          mlKemPublicKey: removedDevice.mlKemPublicKey,
          devices: const <GroupMemberDeviceIdentity>[removedDevice],
          joinedAt: createdAt.add(const Duration(hours: 2)),
        );
        final survivor = GroupMember(
          groupId: groupId,
          peerId: 'peer-protected-remove-survivor',
          username: 'Protected survivor',
          role: MemberRole.writer,
          publicKey: survivorDevice.deviceSigningPublicKey,
          mlKemPublicKey: survivorDevice.mlKemPublicKey,
          devices: const <GroupMemberDeviceIdentity>[survivorDevice],
          joinedAt: createdAt.add(const Duration(hours: 3)),
        );
        await repository.saveGroup(group);
        await repository.saveMember(actor);
        await repository.saveMember(removed);
        await repository.saveMember(survivor);
        await repository.saveRemovedMemberSnapshot(removed, removedAt: eventAt);
        await repository.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'protected-remove-key-v1',
            createdAt: createdAt.add(const Duration(hours: 4)),
          ),
        );

        final remainingMembers = <GroupMember>[actor, survivor];
        final signedPayload = await signGroupSystemTransitionPayload(
          bridge: recoveryBridge,
          groupRepo: repository,
          groupId: groupId,
          transitionType: 'member_removed',
          sourceEventId: eventId,
          eventAt: eventAt,
          actorPeerId: actorPeerId,
          actorUsername: actor.username!,
          actorSigningPublicKey: actorDevice.deviceSigningPublicKey,
          actorPrivateKey: 'protected-remove-admin-private-key',
          actorDeviceId: actorDevice.deviceId,
          actorTransportPeerId: actorDevice.transportPeerId,
          systemPayload: <String, dynamic>{
            '__sys': 'member_removed',
            'member': <String, dynamic>{
              'peerId': removed.peerId,
              'username': removed.username,
            },
            'removedAt': eventAt.toIso8601String(),
            'groupConfig': buildGroupConfigPayload(
              group.copyWith(lastMembershipEventAt: eventAt),
              remainingMembers,
              configVersionOverride: eventAt,
            ),
          },
        );
        final replayData = <String, dynamic>{
          'groupId': groupId,
          'senderId': actorPeerId,
          'senderUsername': actor.username,
          'senderDeviceId': actorDevice.deviceId,
          'transportPeerId': actorDevice.transportPeerId,
          'keyEpoch': 1,
          'text': jsonEncode(signedPayload),
          'timestamp': eventAt.toIso8601String(),
          'messageId': eventId,
        };
        final preparation = await buildProtectedGroupAuthorityRows(
          groupId: groupId,
          transitionId: eventId,
          control: ProtectedGroupAuthorityControl.memberRemove,
          replayData: replayData,
          keyEpoch: 1,
          actorAccountPeerId: actorPeerId,
          actorAccountPublicKey: actorDevice.deviceSigningPublicKey,
          actorAccountPrivateKey: 'protected-remove-admin-private-key',
          senderDevice: actorDevice,
          frozenRecipients: const <GroupMemberDeviceIdentity>[
            actorDevice,
            removedDevice,
            survivorDevice,
          ],
          callSign: (data, privateKey) async => <String, dynamic>{
            'ok': true,
            'signature': 'protected-remove-authority-$suffix',
          },
          callEncrypt:
              ({required recipientMlKemPublicKey, required plaintext}) async =>
                  <String, dynamic>{
                    'ok': true,
                    'kem': 'kem-$recipientMlKemPublicKey',
                    'ciphertext': 'ciphertext-$recipientMlKemPublicKey',
                    'nonce': 'nonce-$recipientMlKemPublicKey',
                  },
          now: () => eventAt,
        );
        final proof = preparation.authorityProof!;
        await history.append(
          phase: AuthenticatedGroupAuthorityPhase.prepared,
          proof: proof,
        );
        if (memberAlreadyRemoved) {
          // Crash shape after the producer's SQL removal but before exact
          // watermark/COMPLETE persistence.
          await repository.removeMember(groupId, removedPeerId);
        }
        recoveryBridge.commandLog.clear();
        recoveryBridge.sentMessages.clear();

        final restartedListener = GroupMessageListener(
          groupRepo: repository,
          msgRepo: messageRepository,
          bridge: recoveryBridge,
          getSelfPeerId: () async => actorPeerId,
          appendGroupEventLogEntry:
              ({
                required groupId,
                required eventType,
                required sourcePeerId,
                required sourceEventId,
                required sourceTimestamp,
                required payload,
                createdAt,
              }) async {
                final row = <String, Object?>{
                  'groupId': groupId,
                  'eventType': eventType,
                  'sourcePeerId': sourcePeerId,
                  'sourceEventId': sourceEventId,
                  'sourceTimestamp': sourceTimestamp,
                  'payload': payload,
                };
                evidenceByEventId.putIfAbsent(sourceEventId, () => row);
                return evidenceByEventId[sourceEventId]!;
              },
        );
        addTearDown(restartedListener.dispose);
        var replayAttempts = 0;

        Future<bool> recover() => recoverLocalPreparedProtectedSystemAuthority(
          proof: proof,
          groupRepository: repository,
          verifyAuthorityProof:
              ({required publicKey, required data, required signature}) async =>
                  true,
          loadAuthorityProof: history.load,
          appendAuthorityProof: history.append,
          applyReplay: (control, protectedReplayData, authority) async {
            replayAttempts++;
            try {
              await restartedListener
                  .handleAuthenticatedAuthorityReplayEnvelope(
                    protectedReplayData,
                    authority: authority,
                    rethrowOnError: true,
                    membershipPhaseHeld: true,
                  );
              final converged = await protectedGroupAuthorityReplayConverged(
                control: control,
                replayData: protectedReplayData,
                groupRepository: repository,
                requireMembershipVersion: true,
                allowDominatingMembershipVersion: true,
              );
              return converged == true
                  ? ProtectedGroupAuthorityApplyResult.applied
                  : ProtectedGroupAuthorityApplyResult.retryable;
            } catch (_) {
              return ProtectedGroupAuthorityApplyResult.retryable;
            }
          },
        );

        expect(await recover(), isTrue, reason: '$suffix-projection restart');
        expect(await repository.getMember(groupId, removedPeerId), isNull);
        final recoveredGroup = await repository.getGroup(groupId);
        expect(recoveredGroup?.lastMembershipEventAt, eventAt);
        expect(recoveredGroup?.lastMembershipEventId, eventId);
        expect(
          recoveryBridge.commandLog.where(
            (command) => command == 'group:updateConfig',
          ),
          hasLength(1),
        );
        expect(
          evidenceByEventId.keys.where((id) => id == eventId),
          hasLength(1),
        );
        expect(history.count(AuthenticatedGroupAuthorityPhase.prepared), 1);
        expect(history.count(AuthenticatedGroupAuthorityPhase.complete), 1);
        expect(replayAttempts, 1);

        expect(
          await recover(),
          isTrue,
          reason: 'COMPLETE is restart-idempotent',
        );
        expect(replayAttempts, 1, reason: 'COMPLETE prevents a second replay');
        expect(
          evidenceByEventId.keys.where((id) => id == eventId),
          hasLength(1),
        );
        expect(
          recoveryBridge.commandLog.where(
            (command) => command == 'group:updateConfig',
          ),
          hasLength(1),
        );
      }

      await proveShape(memberAlreadyRemoved: false);
      await proveShape(memberAlreadyRemoved: true);
    },
  );

  test(
    'protected older remove completes as superseded after later same-subject '
    'remove',
    () async {
      const groupId = 'group-protected-remove-superseded';
      const actorPeerId = 'peer-remove-superseded-admin';
      const targetPeerId = 'peer-remove-superseded-target';
      final createdAt = DateTime.utc(2026, 8, 13, 8);
      final olderRemoveAt = DateTime.utc(2026, 8, 13, 9);
      final laterRemoveAt = DateTime.utc(2026, 8, 13, 11);
      const olderEventId = 'member-remove-before-later-remove';
      const actorDevice = GroupMemberDeviceIdentity(
        deviceId: 'remove-superseded-admin-device',
        transportPeerId: 'remove-superseded-admin-transport',
        deviceSigningPublicKey: 'remove-superseded-admin-public-key',
        mlKemPublicKey: 'remove-superseded-admin-mlkem',
      );
      final repository = InMemoryGroupRepository();
      final messageRepository = InMemoryGroupMessageRepository();
      final recoveryBridge = PassthroughCryptoBridge();
      final history = _RemoveAuthenticatedAuthorityHistory();
      final evidenceByEventId = <String>{};
      final group = GroupModel(
        id: groupId,
        name: 'Superseded protected removal',
        type: GroupType.chat,
        topicName: 'topic-$groupId',
        createdAt: createdAt,
        createdBy: actorPeerId,
        myRole: GroupRole.admin,
        lastMembershipEventAt: laterRemoveAt,
        lastMembershipEventId: 'later-remove-event',
      );
      final actor = GroupMember(
        groupId: groupId,
        peerId: actorPeerId,
        username: 'Admin',
        role: MemberRole.admin,
        publicKey: actorDevice.deviceSigningPublicKey,
        mlKemPublicKey: actorDevice.mlKemPublicKey,
        devices: const <GroupMemberDeviceIdentity>[actorDevice],
        joinedAt: createdAt,
      );
      final historicalTarget = GroupMember(
        groupId: groupId,
        peerId: targetPeerId,
        username: 'Target',
        role: MemberRole.writer,
        publicKey: 'remove-superseded-target-public-key',
        mlKemPublicKey: 'remove-superseded-target-mlkem',
        joinedAt: createdAt.add(const Duration(minutes: 30)),
      );
      await repository.saveGroup(group);
      await repository.saveMember(actor);
      await repository.saveRemovedMemberSnapshot(
        historicalTarget,
        removedAt: laterRemoveAt,
      );
      await repository.saveKey(
        GroupKeyInfo(
          groupId: groupId,
          keyGeneration: 1,
          encryptedKey: 'remove-superseded-key-v1',
          createdAt: createdAt,
        ),
      );
      await messageRepository.saveMessage(
        buildMemberRemovedTimelineMessage(
          groupId: groupId,
          removedPeerId: targetPeerId,
          removedUsername: 'Target',
          senderId: actorPeerId,
          senderUsername: 'Admin',
          eventAt: laterRemoveAt,
        ),
      );

      final signedPayload = await signGroupSystemTransitionPayload(
        bridge: recoveryBridge,
        groupRepo: repository,
        groupId: groupId,
        transitionType: 'member_removed',
        sourceEventId: olderEventId,
        eventAt: olderRemoveAt,
        actorPeerId: actorPeerId,
        actorUsername: 'Admin',
        actorSigningPublicKey: actorDevice.deviceSigningPublicKey,
        actorPrivateKey: 'remove-superseded-admin-private-key',
        actorDeviceId: actorDevice.deviceId,
        actorTransportPeerId: actorDevice.transportPeerId,
        systemPayload: <String, dynamic>{
          '__sys': 'member_removed',
          'member': <String, dynamic>{
            'peerId': targetPeerId,
            'username': 'Target',
          },
          'removedAt': olderRemoveAt.toIso8601String(),
          'groupConfig': buildGroupConfigPayload(
            group.copyWith(
              lastMembershipEventAt: olderRemoveAt,
              lastMembershipEventId: olderEventId,
            ),
            <GroupMember>[actor],
            configVersionOverride: olderRemoveAt,
          ),
        },
      );
      final replayData = <String, dynamic>{
        'groupId': groupId,
        'senderId': actorPeerId,
        'senderUsername': 'Admin',
        'senderDeviceId': actorDevice.deviceId,
        'transportPeerId': actorDevice.transportPeerId,
        'keyEpoch': 1,
        'text': jsonEncode(signedPayload),
        'timestamp': olderRemoveAt.toIso8601String(),
        'messageId': olderEventId,
      };
      final preparation = await buildProtectedGroupAuthorityRows(
        groupId: groupId,
        transitionId: olderEventId,
        control: ProtectedGroupAuthorityControl.memberRemove,
        replayData: replayData,
        keyEpoch: 1,
        actorAccountPeerId: actorPeerId,
        actorAccountPublicKey: actorDevice.deviceSigningPublicKey,
        actorAccountPrivateKey: 'remove-superseded-admin-private-key',
        senderDevice: actorDevice,
        frozenRecipients: const <GroupMemberDeviceIdentity>[actorDevice],
        callSign: (data, privateKey) async => <String, dynamic>{
          'ok': true,
          'signature': 'signed-remove-superseded',
        },
        callEncrypt:
            ({required recipientMlKemPublicKey, required plaintext}) async =>
                <String, dynamic>{'ok': true},
        now: () => olderRemoveAt,
      );
      final proof = preparation.authorityProof!;
      await history.append(
        phase: AuthenticatedGroupAuthorityPhase.prepared,
        proof: proof,
      );
      final listener = GroupMessageListener(
        groupRepo: repository,
        msgRepo: messageRepository,
        bridge: recoveryBridge,
        getSelfPeerId: () async => actorPeerId,
        appendGroupEventLogEntry:
            ({
              required groupId,
              required eventType,
              required sourcePeerId,
              required sourceEventId,
              required sourceTimestamp,
              required payload,
              createdAt,
            }) async {
              evidenceByEventId.add(sourceEventId);
              return <String, Object?>{'sourceEventId': sourceEventId};
            },
      );
      addTearDown(listener.dispose);
      var replayAttempts = 0;

      final recovered = await recoverLocalPreparedProtectedSystemAuthority(
        proof: proof,
        groupRepository: repository,
        verifyAuthorityProof:
            ({required publicKey, required data, required signature}) async =>
                true,
        loadAuthorityProof: history.load,
        appendAuthorityProof: history.append,
        applyReplay: (control, protectedReplayData, authority) async {
          replayAttempts++;
          try {
            await listener.handleAuthenticatedAuthorityReplayEnvelope(
              protectedReplayData,
              authority: authority,
              rethrowOnError: true,
              membershipPhaseHeld: true,
            );
            return ProtectedGroupAuthorityApplyResult.applied;
          } on ProtectedGroupAuthorityReplaySuperseded {
            return ProtectedGroupAuthorityApplyResult.superseded;
          } catch (_) {
            return ProtectedGroupAuthorityApplyResult.retryable;
          }
        },
      );

      expect(recovered, isTrue);
      expect(replayAttempts, 1);
      expect(await repository.getMember(groupId, targetPeerId), isNull);
      expect(history.count(AuthenticatedGroupAuthorityPhase.complete), 1);
      expect(evidenceByEventId, isNot(contains(olderEventId)));
      expect(
        recoveryBridge.commandLog.where(
          (command) => command == 'group:updateConfig',
        ),
        isEmpty,
      );
    },
  );
}

class _TimeoutRemoveUpdateConfigBridge extends FakeBridge {
  bool updateConfigIssued = false;

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    if (parsed['cmd'] == 'group:updateConfig') {
      updateConfigIssued = true;
      throw TimeoutException('simulated lost group:updateConfig response');
    }
    return super.send(message);
  }
}

class _CrashAfterMemberRemoveRepository extends InMemoryGroupRepository {
  _CrashAfterMemberRemoveRepository({required this.crashPeerId});

  final String crashPeerId;

  @override
  Future<void> removeMember(String groupId, String peerId) async {
    await super.removeMember(groupId, peerId);
    if (peerId == crashPeerId) {
      throw StateError('simulated crash after durable member delete');
    }
  }
}

final class _RemoveAuthenticatedAuthorityHistory {
  final _proofs =
      <
        (AuthenticatedGroupAuthorityPhase, String),
        AuthenticatedGroupAuthorityProof
      >{};

  Future<AuthenticatedGroupAuthorityProof?> load({
    required String groupId,
    required AuthenticatedGroupAuthorityPhase phase,
    required String eventId,
  }) async {
    final proof = _proofs[(phase, eventId)];
    return proof?.groupId == groupId ? proof : null;
  }

  Future<void> append({
    required AuthenticatedGroupAuthorityPhase phase,
    required AuthenticatedGroupAuthorityProof proof,
  }) async {
    final key = (phase, proof.eventId);
    final existing = _proofs[key];
    if (existing != null &&
        !sameAuthenticatedGroupAuthorityProof(existing, proof)) {
      throw StateError('conflicting remove authority history');
    }
    _proofs[key] = proof;
  }

  int count(AuthenticatedGroupAuthorityPhase phase) =>
      _proofs.keys.where((key) => key.$1 == phase).length;
}
