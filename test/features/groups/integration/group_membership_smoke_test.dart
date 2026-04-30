import 'dart:convert';

import 'package:flutter_app/features/groups/application/add_group_member_use_case.dart';
import 'package:flutter_app/features/groups/application/dissolve_group_use_case.dart'
    as group_dissolve;
import 'package:flutter_app/features/groups/application/delete_group_and_messages_use_case.dart';
import 'package:flutter_app/features/groups/application/leave_group_use_case.dart';
import 'package:flutter_app/features/groups/application/remove_group_member_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart'
    as group_send;
import 'package:flutter/widgets.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/fake_group_pubsub_network.dart';
import '../../../shared/fakes/fake_notification_service.dart';
import '../../../shared/fakes/group_test_user.dart';

void main() {
  late FakeGroupPubSubNetwork network;

  setUp(() {
    network = FakeGroupPubSubNetwork();
  });

  Future<void> pump() => Future.delayed(const Duration(milliseconds: 50));

  Future<void> waitUntil(
    Future<bool> Function() condition, {
    int maxTicks = 20,
  }) async {
    for (var i = 0; i < maxTicks; i++) {
      if (await condition()) return;
      await pump();
    }
  }

  Map<String, dynamic> decodeReplayPayload(Map<String, dynamic> inboxPayload) {
    final envelope =
        jsonDecode(inboxPayload['message'] as String) as Map<String, dynamic>;
    final ciphertext = envelope['ciphertext'];
    if (envelope['kind'] == 'group_offline_replay' && ciphertext is String) {
      return jsonDecode(ciphertext) as Map<String, dynamic>;
    }
    return envelope;
  }

  group('Multi-user group membership smoke tests', () {
    // -----------------------------------------------------------------------
    // 1. Admin removes member — removed member stops receiving messages.
    // -----------------------------------------------------------------------
    test(
      'admin removes member — removed member stops receiving messages',
      () async {
        const groupId = 'grp-remove-001';

        // Create 4 users
        final alice = GroupTestUser.create(
          peerId: 'peer-alice',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-charlie',
          username: 'Charlie',
          network: network,
        );
        final diana = GroupTestUser.create(
          peerId: 'peer-diana',
          username: 'Diana',
          network: network,
        );

        // Alice creates group and adds everyone
        await alice.createGroup(groupId: groupId, name: 'Test Group');
        await alice.addMember(groupId: groupId, invitee: bob);
        await alice.addMember(groupId: groupId, invitee: charlie);
        await alice.addMember(groupId: groupId, invitee: diana);

        // Start all listeners
        alice.start();
        bob.start();
        charlie.start();
        diana.start();

        // Alice sends "Before removal"
        await alice.sendGroupMessage(groupId: groupId, text: 'Before removal');
        await pump();

        // Alice removes Bob
        await alice.removeMember(
          groupId: groupId,
          memberPeerId: bob.peerId,
          memberUsername: 'Bob',
        );
        await pump();

        // Alice sends "After removal"
        await alice.sendGroupMessage(groupId: groupId, text: 'After removal');
        await pump();

        // Load incoming messages for each user
        final bobMessages = await bob.loadGroupMessages(groupId);
        final charlieMessages = await charlie.loadGroupMessages(groupId);
        final dianaMessages = await diana.loadGroupMessages(groupId);

        // Filter to incoming only
        final bobIncoming = bobMessages.where((m) => m.isIncoming).toList();
        final charlieIncoming = charlieMessages
            .where((m) => m.isIncoming)
            .toList();
        final dianaIncoming = dianaMessages.where((m) => m.isIncoming).toList();

        // Bob: only 1 incoming message ("Before removal")
        expect(bobIncoming, hasLength(1));
        expect(bobIncoming[0].text, equals('Before removal'));

        final charlieRegular = charlieIncoming
            .where(
              (message) =>
                  message.text == 'Before removal' ||
                  message.text == 'After removal',
            )
            .toList();
        final dianaRegular = dianaIncoming
            .where(
              (message) =>
                  message.text == 'Before removal' ||
                  message.text == 'After removal',
            )
            .toList();

        // Charlie: the regular before/after texts plus a persisted removal
        // timeline entry are all allowed now; pin the ordinary chat flow
        // explicitly.
        expect(charlieRegular, hasLength(2));
        expect(
          charlieRegular.map((m) => m.text).toList(),
          containsAll(['Before removal', 'After removal']),
        );

        // Diana sees the same ordinary chat flow.
        expect(dianaRegular, hasLength(2));
        expect(
          dianaRegular.map((m) => m.text).toList(),
          containsAll(['Before removal', 'After removal']),
        );

        // Bob should NOT be subscribed on the network anymore
        expect(network.isSubscribed(groupId, bob.peerId), isFalse);

        // Cleanup
        alice.dispose();
        bob.dispose();
        charlie.dispose();
        diana.dispose();
      },
    );

    // -----------------------------------------------------------------------
    // 2. Admin removes member — remaining members update their local member
    //    list.
    // -----------------------------------------------------------------------
    test(
      'admin removes member — remaining members update their local member list',
      () async {
        const groupId = 'grp-remove-002';

        final admin = GroupTestUser.create(
          peerId: 'peer-admin',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-charlie',
          username: 'Charlie',
          network: network,
        );

        // Admin creates group and adds Bob and Charlie
        await admin.createGroup(groupId: groupId, name: 'Test Group');
        await admin.addMember(groupId: groupId, invitee: bob);
        await admin.addMember(groupId: groupId, invitee: charlie);

        // Start all listeners
        admin.start();
        bob.start();
        charlie.start();

        // Admin removes Charlie
        await admin.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: 'Charlie',
        );
        await pump();

        // Bob should NOT have Charlie in his local group repo
        final bobMembers = await bob.groupRepo.getMembers(groupId);
        final bobMemberPeerIds = bobMembers.map((m) => m.peerId).toSet();
        expect(bobMemberPeerIds, isNot(contains(charlie.peerId)));

        // Admin should NOT have Charlie either (removed locally before broadcast)
        final adminMembers = await admin.groupRepo.getMembers(groupId);
        final adminMemberPeerIds = adminMembers.map((m) => m.peerId).toSet();
        expect(adminMemberPeerIds, isNot(contains(charlie.peerId)));

        // Cleanup
        admin.dispose();
        bob.dispose();
        charlie.dispose();
      },
    );

    test(
      'non-admin raw membership removal event is ignored by peers',
      () async {
        const groupId = 'grp-auth-001';

        final admin = GroupTestUser.create(
          peerId: 'peer-admin',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-bob',
          username: 'Bob',
          network: network,
        );

        await admin.createGroup(groupId: groupId, name: 'Auth Guard');
        await admin.addMember(groupId: groupId, invitee: bob);

        admin.start();
        bob.start();

        admin.bridge.commandLog.clear();

        final forgedText = jsonEncode({
          '__sys': 'member_removed',
          'member': {'peerId': admin.peerId, 'username': admin.username},
          'groupConfig': {
            'name': 'Auth Guard',
            'groupType': 'chat',
            'members': [
              {
                'peerId': bob.peerId,
                'username': bob.username,
                'role': 'writer',
                'publicKey': bob.publicKey,
              },
            ],
            'createdBy': admin.peerId,
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
        });

        await network.publish(groupId, bob.peerId, {
          'groupId': groupId,
          'senderId': bob.peerId,
          'senderUsername': bob.username,
          'keyEpoch': 0,
          'text': forgedText,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });
        await pump();

        Future<void> expectCanonicalMembers(GroupTestUser user) async {
          final members = await user.groupRepo.getMembers(groupId);
          expect(members.map((member) => member.peerId).toSet(), {
            admin.peerId,
            bob.peerId,
          });
        }

        await expectCanonicalMembers(admin);
        await expectCanonicalMembers(bob);

        expect(await admin.groupRepo.getGroup(groupId), isNotNull);
        expect(await admin.loadGroupMessages(groupId), isEmpty);
        expect(admin.bridge.commandLog, isNot(contains('group:updateConfig')));

        admin.dispose();
        bob.dispose();
      },
    );

    // -----------------------------------------------------------------------
    // 3. Self-removal — removed user calls leaveGroup and cleans up.
    // -----------------------------------------------------------------------
    test(
      'self-removal — removed user calls leaveGroup and cleans up',
      () async {
        const groupId = 'grp-remove-003';

        final admin = GroupTestUser.create(
          peerId: 'peer-admin',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-charlie',
          username: 'Charlie',
          network: network,
        );

        // Admin creates group and adds Bob and Charlie
        await admin.createGroup(groupId: groupId, name: 'Test Group');
        await admin.addMember(groupId: groupId, invitee: bob);
        await admin.addMember(groupId: groupId, invitee: charlie);

        // Start all listeners
        admin.start();
        bob.start();
        charlie.start();

        // Listen to Bob's groupRemovedStream BEFORE the removal
        final removedGroupIds = <String>[];
        final removedSub = bob.groupMessageListener.groupRemovedStream.listen((
          gid,
        ) {
          removedGroupIds.add(gid);
        });

        // Admin removes Bob
        await admin.removeMember(
          groupId: groupId,
          memberPeerId: bob.peerId,
          memberUsername: 'Bob',
        );
        await pump();

        // Bob's groupRemovedStream should have emitted the groupId
        expect(removedGroupIds, contains(groupId));

        // Bob's groupRepo should have no group (leaveGroup deletes it)
        final bobGroup = await bob.groupRepo.getGroup(groupId);
        expect(bobGroup, isNull);

        // Bob's bridge.commandLog should contain 'group:leave'
        expect(bob.bridge.commandLog, contains('group:leave'));

        // Cleanup
        await removedSub.cancel();
        admin.dispose();
        bob.dispose();
        charlie.dispose();
      },
    );

    // -----------------------------------------------------------------------
    // 4. Sole admin leave is blocked while only non-admin members remain.
    // -----------------------------------------------------------------------
    test('sole admin cannot leave while only writer members remain', () async {
      const groupId = 'grp-admin-leave-004';

      final admin = GroupTestUser.create(
        peerId: 'peer-admin',
        username: 'Admin',
        network: network,
      );
      final bob = GroupTestUser.create(
        peerId: 'peer-bob',
        username: 'Bob',
        network: network,
      );

      await admin.createGroup(groupId: groupId, name: 'Test Group');
      await admin.addMember(groupId: groupId, invitee: bob);

      admin.start();
      bob.start();

      await expectLater(
        leaveGroup(
          bridge: admin.bridge,
          groupRepo: admin.groupRepo,
          groupId: groupId,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains(lastAdminLeaveBlockedMessage),
          ),
        ),
      );

      expect(admin.bridge.commandLog, isNot(contains('group:leave')));
      expect(await admin.groupRepo.getGroup(groupId), isNotNull);
      expect(
        (await admin.groupRepo.getMembers(
          groupId,
        )).map((member) => member.peerId).toSet(),
        {'peer-admin', 'peer-bob'},
      );

      await admin.sendGroupMessage(groupId: groupId, text: 'Still here');
      await pump();

      final bobIncoming = (await bob.loadGroupMessages(
        groupId,
      )).where((entry) => entry.isIncoming).toList();
      expect(
        bobIncoming.where((entry) => entry.text == 'Still here'),
        hasLength(1),
      );

      admin.dispose();
      bob.dispose();
    });

    test(
      'promoted admin gains admin role and can perform admin-only actions',
      () async {
        const groupId = 'grp-admin-role-004';

        final admin = GroupTestUser.create(
          peerId: 'peer-admin',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-charlie',
          username: 'Charlie',
          network: network,
        );

        await admin.createGroup(groupId: groupId, name: 'Admin Roles');
        await admin.addMember(groupId: groupId, invitee: bob);
        await admin.addMember(groupId: groupId, invitee: charlie);

        admin.start();
        bob.start();
        charlie.start();

        await admin.updateMemberRole(
          groupId: groupId,
          memberPeerId: bob.peerId,
          role: MemberRole.admin,
        );
        await pump();

        final bobGroup = await bob.groupRepo.getGroup(groupId);
        final bobMember = await bob.groupRepo.getMember(groupId, bob.peerId);
        final adminViewOfBob = await admin.groupRepo.getMember(
          groupId,
          bob.peerId,
        );

        expect(bobGroup, isNotNull);
        expect(bobGroup!.myRole, GroupRole.admin);
        expect(bobMember, isNotNull);
        expect(bobMember!.role, MemberRole.admin);
        expect(adminViewOfBob, isNotNull);
        expect(adminViewOfBob!.role, MemberRole.admin);

        await bob.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
        );
        await pump();

        expect(await bob.groupRepo.getMember(groupId, charlie.peerId), isNull);
        expect(
          await admin.groupRepo.getMember(groupId, charlie.peerId),
          isNull,
        );
        expect(network.isSubscribed(groupId, charlie.peerId), isFalse);

        admin.dispose();
        bob.dispose();
        charlie.dispose();
      },
    );

    test(
      'multi-admin leave keeps remaining admin healthy and synchronized',
      () async {
        const groupId = 'grp-admin-leave-005';

        final admin = GroupTestUser.create(
          peerId: 'peer-admin',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-charlie',
          username: 'Charlie',
          network: network,
        );

        await admin.createGroup(groupId: groupId, name: 'Admin Leave');
        await admin.addMember(groupId: groupId, invitee: bob);
        await admin.addMember(groupId: groupId, invitee: charlie);

        admin.start();
        bob.start();
        charlie.start();

        await admin.updateMemberRole(
          groupId: groupId,
          memberPeerId: bob.peerId,
          role: MemberRole.admin,
        );
        await pump();

        await admin.leaveGroup(groupId);
        await pump();

        expect(await admin.groupRepo.getGroup(groupId), isNull);
        expect(network.isSubscribed(groupId, admin.peerId), isFalse);

        final bobGroup = await bob.groupRepo.getGroup(groupId);
        final charlieGroup = await charlie.groupRepo.getGroup(groupId);
        expect(bobGroup, isNotNull);
        expect(charlieGroup, isNotNull);
        expect(bobGroup!.myRole, GroupRole.admin);
        expect(charlieGroup!.myRole, GroupRole.member);

        final bobMembers = await bob.groupRepo.getMembers(groupId);
        final charlieMembers = await charlie.groupRepo.getMembers(groupId);
        expect(bobMembers.map((member) => member.peerId).toSet(), {
          'peer-bob',
          'peer-charlie',
        });
        expect(charlieMembers.map((member) => member.peerId).toSet(), {
          'peer-bob',
          'peer-charlie',
        });

        await bob.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
        );
        await waitUntil(
          () async => await charlie.groupRepo.getGroup(groupId) == null,
        );

        expect(await bob.groupRepo.getMember(groupId, charlie.peerId), isNull);
        expect(await charlie.groupRepo.getGroup(groupId), isNull);

        admin.dispose();
        bob.dispose();
        charlie.dispose();
      },
    );

    test(
      'concurrent admin changes converge to one final member/admin map',
      () async {
        const groupId = 'grp-admin-converge-006';
        final createdAt = DateTime.parse('2026-04-05T12:09:56.000Z').toUtc();
        final bobJoinedAt = DateTime.parse('2026-04-05T12:09:57.000Z').toUtc();
        final charlieJoinedAt = DateTime.parse(
          '2026-04-05T12:09:58.000Z',
        ).toUtc();
        final dianaJoinedAt = DateTime.parse(
          '2026-04-05T12:09:59.000Z',
        ).toUtc();
        const initialPromoteAt = '2026-04-05T12:10:00.000Z';
        const promoteAt = '2026-04-05T12:10:01.000Z';
        const removeAt = '2026-04-05T12:10:02.000Z';
        final initialPromoteAtTime = DateTime.parse(initialPromoteAt).toUtc();
        final promoteAtTime = DateTime.parse(promoteAt).toUtc();
        final removeAtTime = DateTime.parse(removeAt).toUtc();

        final admin = GroupTestUser.create(
          peerId: 'peer-admin',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-charlie',
          username: 'Charlie',
          network: network,
        );
        final diana = GroupTestUser.create(
          peerId: 'peer-diana',
          username: 'Diana',
          network: network,
        );

        await admin.createGroup(
          groupId: groupId,
          name: 'Concurrent Admin',
          createdAt: createdAt,
        );
        await admin.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: bobJoinedAt,
        );
        await admin.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: charlieJoinedAt,
        );
        await admin.addMember(
          groupId: groupId,
          invitee: diana,
          joinedAt: dianaJoinedAt,
        );

        admin.start();
        bob.start();
        charlie.start();
        diana.start();

        await admin.updateMemberRole(
          groupId: groupId,
          memberPeerId: bob.peerId,
          role: MemberRole.admin,
          changedAt: initialPromoteAtTime,
        );
        await pump();

        await admin.updateMemberRole(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          role: MemberRole.admin,
          changedAt: promoteAtTime,
        );
        await pump();

        await bob.removeMember(
          groupId: groupId,
          memberPeerId: diana.peerId,
          memberUsername: diana.username,
          removedAt: removeAtTime,
        );
        await pump();

        Future<void> expectCanonicalState(GroupTestUser user) async {
          final members = await user.groupRepo.getMembers(groupId);
          final roles = {
            for (final member in members) member.peerId: member.role,
          };
          expect(roles, {
            'peer-admin': MemberRole.admin,
            'peer-bob': MemberRole.admin,
            'peer-charlie': MemberRole.admin,
          });
          expect(
            (await user.groupRepo.getGroup(groupId))!.lastMembershipEventAt,
            DateTime.parse(removeAt).toUtc(),
          );
        }

        await expectCanonicalState(admin);
        await expectCanonicalState(bob);
        await expectCanonicalState(charlie);

        expect(await diana.groupRepo.getGroup(groupId), isNull);
        expect(network.isSubscribed(groupId, diana.peerId), isFalse);

        admin.dispose();
        bob.dispose();
        charlie.dispose();
        diana.dispose();
      },
    );

    test(
      'conflicting remove and promote of the same member converge to removal',
      () async {
        const groupId = 'grp-admin-conflict-007';
        final createdAt = DateTime.parse('2026-04-05T12:19:56.000Z').toUtc();
        final bobJoinedAt = DateTime.parse('2026-04-05T12:19:57.000Z').toUtc();
        final charlieJoinedAt = DateTime.parse(
          '2026-04-05T12:19:58.000Z',
        ).toUtc();
        const initialPromoteAt = '2026-04-05T12:20:00.000Z';
        const promoteAt = '2026-04-05T12:20:01.000Z';
        const removeAt = '2026-04-05T12:20:02.000Z';
        final initialPromoteAtTime = DateTime.parse(initialPromoteAt).toUtc();
        final promoteAtTime = DateTime.parse(promoteAt).toUtc();
        final removeAtTime = DateTime.parse(removeAt).toUtc();

        final admin = GroupTestUser.create(
          peerId: 'peer-admin',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-charlie',
          username: 'Charlie',
          network: network,
        );

        await admin.createGroup(
          groupId: groupId,
          name: 'Conflict Admin',
          createdAt: createdAt,
        );
        await admin.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: bobJoinedAt,
        );
        await admin.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: charlieJoinedAt,
        );

        admin.start();
        bob.start();
        charlie.start();

        await admin.updateMemberRole(
          groupId: groupId,
          memberPeerId: bob.peerId,
          role: MemberRole.admin,
          changedAt: initialPromoteAtTime,
        );
        await pump();

        await admin.updateMemberRole(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          role: MemberRole.admin,
          changedAt: promoteAtTime,
        );
        await pump();

        await bob.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: removeAtTime,
        );
        await pump();

        Future<void> expectRemovalWinner(GroupTestUser user) async {
          final members = await user.groupRepo.getMembers(groupId);
          final roles = {
            for (final member in members) member.peerId: member.role,
          };
          expect(roles, {
            'peer-admin': MemberRole.admin,
            'peer-bob': MemberRole.admin,
          });
          expect(
            (await user.groupRepo.getGroup(groupId))!.lastMembershipEventAt,
            DateTime.parse(removeAt).toUtc(),
          );
        }

        await expectRemovalWinner(admin);
        await expectRemovalWinner(bob);
        expect(await charlie.groupRepo.getGroup(groupId), isNull);
        expect(network.isSubscribed(groupId, charlie.peerId), isFalse);

        admin.dispose();
        bob.dispose();
        charlie.dispose();
      },
    );

    // -----------------------------------------------------------------------
    // 5. Removed member loses send permission after self-removal cleanup.
    // -----------------------------------------------------------------------
    test('removed member cannot send after self-removal cleanup', () async {
      const groupId = 'grp-remove-send-004';

      final admin = GroupTestUser.create(
        peerId: 'peer-admin',
        username: 'Admin',
        network: network,
      );
      final bob = GroupTestUser.create(
        peerId: 'peer-bob',
        username: 'Bob',
        network: network,
      );
      final charlie = GroupTestUser.create(
        peerId: 'peer-charlie',
        username: 'Charlie',
        network: network,
      );

      await admin.createGroup(groupId: groupId, name: 'Test Group');
      await admin.addMember(groupId: groupId, invitee: bob);
      await admin.addMember(groupId: groupId, invitee: charlie);

      admin.start();
      bob.start();
      charlie.start();

      await admin.removeMember(
        groupId: groupId,
        memberPeerId: bob.peerId,
        memberUsername: 'Bob',
      );
      await pump();

      final (result, message) = await bob.sendGroupMessageViaBridge(
        groupId: groupId,
        text: 'Should not send',
      );

      expect(result, group_send.SendGroupMessageResult.groupNotFound);
      expect(message, isNull);
      expect(await bob.groupRepo.getGroup(groupId), isNull);
      expect(await bob.msgRepo.getMessageCount(groupId), 0);
      expect(
        bob.bridge.commandLog.where((command) => command == 'group:publish'),
        isEmpty,
      );

      final adminIncoming = (await admin.loadGroupMessages(
        groupId,
      )).where((entry) => entry.isIncoming).toList();
      final charlieIncoming = (await charlie.loadGroupMessages(
        groupId,
      )).where((entry) => entry.isIncoming).toList();

      expect(
        adminIncoming.where((entry) => entry.text == 'Should not send'),
        isEmpty,
      );
      expect(
        charlieIncoming.where((entry) => entry.text == 'Should not send'),
        isEmpty,
      );

      admin.dispose();
      bob.dispose();
      charlie.dispose();
    });

    test(
      'remaining peers accept only delayed removed-sender envelopes from before the persisted cutoff',
      () async {
        const groupId = 'grp-remove-boundary-005';

        final admin = GroupTestUser.create(
          peerId: 'peer-admin',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-charlie',
          username: 'Charlie',
          network: network,
        );

        await admin.createGroup(groupId: groupId, name: 'Test Group');
        await admin.addMember(groupId: groupId, invitee: bob);
        await admin.addMember(groupId: groupId, invitee: charlie);

        admin.start();
        bob.start();
        charlie.start();

        await admin.removeMember(
          groupId: groupId,
          memberPeerId: bob.peerId,
          memberUsername: 'Bob',
        );
        await pump();

        final charlieMessages = await charlie.loadGroupMessages(groupId);
        final removalEntry = charlieMessages.firstWhere(
          (entry) =>
              entry.id.startsWith(
                'sys-member_removed:$groupId:${bob.peerId}:',
              ) &&
              entry.text == 'Admin removed Bob',
        );
        final cutoff = removalEntry.timestamp.toUtc();

        await network.publish(groupId, bob.peerId, {
          'groupId': groupId,
          'senderId': bob.peerId,
          'senderUsername': 'Bob',
          'keyEpoch': 0,
          'text': 'Before cutoff delayed',
          'timestamp': cutoff
              .subtract(const Duration(milliseconds: 1))
              .toIso8601String(),
          'messageId': 'msg-before-cutoff-delayed',
        });
        await network.publish(groupId, bob.peerId, {
          'groupId': groupId,
          'senderId': bob.peerId,
          'senderUsername': 'Bob',
          'keyEpoch': 0,
          'text': 'At cutoff delayed',
          'timestamp': cutoff.toIso8601String(),
          'messageId': 'msg-at-cutoff-delayed',
        });
        await pump();

        final adminIncoming = (await admin.loadGroupMessages(
          groupId,
        )).where((entry) => entry.isIncoming).toList();
        final charlieIncoming = (await charlie.loadGroupMessages(
          groupId,
        )).where((entry) => entry.isIncoming).toList();

        expect(
          adminIncoming.where((entry) => entry.text == 'Before cutoff delayed'),
          hasLength(1),
        );
        expect(
          charlieIncoming.where(
            (entry) => entry.text == 'Before cutoff delayed',
          ),
          hasLength(1),
        );
        expect(
          adminIncoming.where((entry) => entry.text == 'At cutoff delayed'),
          isEmpty,
        );
        expect(
          charlieIncoming.where((entry) => entry.text == 'At cutoff delayed'),
          isEmpty,
        );

        admin.dispose();
        bob.dispose();
        charlie.dispose();
      },
    );

    // -----------------------------------------------------------------------
    // 6. Add member success + member_added system message — existing members
    //    update local member list and the new member can participate.
    // -----------------------------------------------------------------------
    test(
      'add member syncs every member list and the new member can participate',
      () async {
        const groupId = 'grp-add-004';

        final admin = GroupTestUser.create(
          peerId: 'peer-admin',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-charlie',
          username: 'Charlie',
          network: network,
        );

        // Admin creates group and adds Bob (but NOT Charlie yet)
        await admin.createGroup(groupId: groupId, name: 'Test Group');
        await admin.addMember(groupId: groupId, invitee: bob);

        // Start listeners for admin and Bob
        admin.start();
        bob.start();

        // Admin adds Charlie (saves to repos + subscribes)
        await admin.addMember(groupId: groupId, invitee: charlie);

        // Admin broadcasts member_added system message
        await admin.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await pump();

        // Charlie starts after the bootstrap data is written to local repos.
        charlie.start();

        Future<void> expectSyncedMembers(GroupTestUser user) async {
          final members = await user.groupRepo.getMembers(groupId);
          expect(members.map((member) => member.peerId).toSet(), {
            'peer-admin',
            'peer-bob',
            'peer-charlie',
          });
          final rolesByPeerId = {
            for (final member in members) member.peerId: member.role,
          };
          expect(rolesByPeerId['peer-admin'], MemberRole.admin);
          expect(rolesByPeerId['peer-bob'], MemberRole.writer);
          expect(rolesByPeerId['peer-charlie'], MemberRole.writer);
        }

        // All participants should converge on the same member list and roles.
        await expectSyncedMembers(admin);
        await expectSyncedMembers(bob);
        await expectSyncedMembers(charlie);

        // Bob's bridge.commandLog should contain 'group:updateConfig'
        expect(bob.bridge.commandLog, contains('group:updateConfig'));

        // The newly added member can participate once bootstrap is complete.
        await charlie.sendGroupMessage(groupId: groupId, text: 'Hi team');
        await pump();

        final adminIncoming = (await admin.loadGroupMessages(
          groupId,
        )).where((message) => message.isIncoming).toList();
        final bobIncoming = (await bob.loadGroupMessages(
          groupId,
        )).where((message) => message.isIncoming).toList();
        final charlieOutgoing = (await charlie.loadGroupMessages(
          groupId,
        )).where((message) => !message.isIncoming).toList();

        expect(adminIncoming, hasLength(1));
        expect(adminIncoming.single.text, 'Hi team');
        expect(
          bobIncoming.map((message) => message.text),
          containsAll(['Admin added Charlie', 'Hi team']),
        );
        expect(charlieOutgoing, hasLength(1));
        expect(charlieOutgoing.single.text, 'Hi team');

        // Cleanup
        admin.dispose();
        bob.dispose();
        charlie.dispose();
      },
    );

    test(
      'writer leave emits a durable left-the-group event for remaining members',
      () async {
        const groupId = 'grp-writer-leave-004b';

        final admin = GroupTestUser.create(
          peerId: 'peer-admin',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-charlie',
          username: 'Charlie',
          network: network,
        );

        await admin.createGroup(groupId: groupId, name: 'Leave Test');
        await admin.addMember(groupId: groupId, invitee: bob);
        await admin.addMember(groupId: groupId, invitee: charlie);

        admin.start();
        bob.start();
        charlie.start();

        await bob.leaveGroup(groupId);
        await pump();

        expect(await bob.groupRepo.getGroup(groupId), isNull);

        final adminMembers = await admin.groupRepo.getMembers(groupId);
        final charlieMembers = await charlie.groupRepo.getMembers(groupId);
        expect(
          adminMembers.map((member) => member.peerId),
          isNot(contains('peer-bob')),
        );
        expect(
          charlieMembers.map((member) => member.peerId),
          isNot(contains('peer-bob')),
        );

        final adminMessages = await admin.loadGroupMessages(groupId);
        final charlieMessages = await charlie.loadGroupMessages(groupId);
        expect(
          adminMessages.map((message) => message.text),
          contains('Bob left the group'),
        );
        expect(
          charlieMessages.map((message) => message.text),
          contains('Bob left the group'),
        );

        admin.dispose();
        bob.dispose();
        charlie.dispose();
      },
    );

    test(
      'duplicate re-add returns error and leaves member lists unchanged',
      () async {
        const groupId = 'grp-add-duplicate-004';

        final admin = GroupTestUser.create(
          peerId: 'peer-admin',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-bob',
          username: 'Bob',
          network: network,
        );

        await admin.createGroup(groupId: groupId, name: 'Duplicate Add Guard');
        await admin.addMember(groupId: groupId, invitee: bob);

        admin.start();
        bob.start();
        await pump();

        admin.bridge.commandLog.clear();

        await expectLater(
          addGroupMember(
            bridge: admin.bridge,
            groupRepo: admin.groupRepo,
            groupId: groupId,
            newMember: GroupMember(
              groupId: groupId,
              peerId: bob.peerId,
              username: 'Changed Bob',
              role: MemberRole.reader,
              publicKey: bob.publicKey,
              joinedAt: DateTime.now().toUtc(),
            ),
            selfPeerId: admin.peerId,
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('already exists'),
            ),
          ),
        );
        await pump();

        expect(admin.bridge.commandLog, isEmpty);

        Future<void> expectStableMembers(GroupTestUser user) async {
          final members = await user.groupRepo.getMembers(groupId);
          expect(members.map((member) => member.peerId).toSet(), {
            'peer-admin',
            'peer-bob',
          });

          final bobRows = members.where(
            (member) => member.peerId == 'peer-bob',
          );
          expect(bobRows, hasLength(1));
          expect(bobRows.single.username, 'Bob');
          expect(bobRows.single.role, MemberRole.writer);
        }

        await expectStableMembers(admin);
        await expectStableMembers(bob);
        expect(await admin.loadGroupMessages(groupId), isEmpty);
        expect(await bob.loadGroupMessages(groupId), isEmpty);

        admin.dispose();
        bob.dispose();
      },
    );

    test(
      'non-member removal returns error and leaves member lists unchanged',
      () async {
        const groupId = 'grp-remove-absent-008';

        final admin = GroupTestUser.create(
          peerId: 'peer-admin',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-bob',
          username: 'Bob',
          network: network,
        );

        await admin.createGroup(groupId: groupId, name: 'Absent Remove Guard');
        await admin.addMember(groupId: groupId, invitee: bob);

        admin.start();
        bob.start();
        await pump();

        admin.bridge.commandLog.clear();

        await expectLater(
          removeGroupMember(
            bridge: admin.bridge,
            groupRepo: admin.groupRepo,
            groupId: groupId,
            memberPeerId: 'peer-charlie',
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('Member not found'),
            ),
          ),
        );
        await pump();

        expect(admin.bridge.commandLog, isEmpty);

        Future<void> expectStableMembers(GroupTestUser user) async {
          final members = await user.groupRepo.getMembers(groupId);
          expect(members.map((member) => member.peerId).toSet(), {
            'peer-admin',
            'peer-bob',
          });
        }

        await expectStableMembers(admin);
        await expectStableMembers(bob);
        expect(network.isSubscribed(groupId, bob.peerId), isTrue);
        expect(await admin.loadGroupMessages(groupId), isEmpty);
        expect(await bob.loadGroupMessages(groupId), isEmpty);

        admin.dispose();
        bob.dispose();
      },
    );

    test(
      'new member cannot send before bootstrap key exists, then succeeds after bootstrap completes',
      () async {
        const groupId = 'grp-add-bootstrap-guard';

        final admin = GroupTestUser.create(
          peerId: 'peer-admin',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-charlie',
          username: 'Charlie',
          network: network,
        );

        Future<void> saveKey(
          GroupTestUser user, {
          required int epoch,
          required String encryptedKey,
        }) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: epoch,
              encryptedKey: encryptedKey,
              createdAt: DateTime.now().toUtc(),
            ),
          );
        }

        await admin.createGroup(groupId: groupId, name: 'Bootstrap Guard');
        await admin.addMember(groupId: groupId, invitee: bob);

        admin.start();
        bob.start();

        await admin.addMember(groupId: groupId, invitee: charlie);
        await admin.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await pump();
        charlie.start();

        final (blockedResult, blockedMessage) = await charlie
            .sendGroupMessageViaBridge(groupId: groupId, text: 'Too early');

        expect(blockedResult, group_send.SendGroupMessageResult.error);
        expect(blockedMessage, isNull);
        expect(charlie.bridge.commandLog, isEmpty);
        expect(await charlie.loadGroupMessages(groupId), isEmpty);
        expect(
          (await admin.loadGroupMessages(
            groupId,
          )).where((message) => message.isIncoming),
          isEmpty,
        );
        expect(
          (await bob.loadGroupMessages(groupId))
              .where((message) => message.isIncoming)
              .map((message) => message.text),
          contains('Admin added Charlie'),
        );

        await saveKey(charlie, epoch: 1, encryptedKey: 'group-key-epoch-1');

        final (postBootstrapResult, postBootstrapMessage) = await charlie
            .sendGroupMessageViaBridge(groupId: groupId, text: 'Hi team');
        await pump();

        expect(postBootstrapResult, group_send.SendGroupMessageResult.success);
        expect(postBootstrapMessage, isNotNull);
        expect(postBootstrapMessage!.text, 'Hi team');
        expect(postBootstrapMessage.keyGeneration, 1);

        final adminIncoming = (await admin.loadGroupMessages(
          groupId,
        )).where((message) => message.isIncoming).toList();
        final bobIncoming = (await bob.loadGroupMessages(
          groupId,
        )).where((message) => message.isIncoming).toList();
        final charlieOutgoing = (await charlie.loadGroupMessages(
          groupId,
        )).where((message) => !message.isIncoming).toList();

        expect(adminIncoming, hasLength(1));
        expect(adminIncoming.single.text, 'Hi team');
        expect(bobIncoming, hasLength(2));
        expect(
          bobIncoming.map((message) => message.text).toList(),
          containsAll(['Admin added Charlie', 'Hi team']),
        );
        expect(charlieOutgoing, hasLength(1));
        expect(charlieOutgoing.single.text, 'Hi team');

        admin.dispose();
        bob.dispose();
        charlie.dispose();
      },
    );

    // -----------------------------------------------------------------------
    // 6. Post-removal messaging — admin can still send to remaining members.
    // -----------------------------------------------------------------------
    test(
      'post-removal messaging — admin can still send to remaining members',
      () async {
        const groupId = 'grp-post-remove-005';

        final admin = GroupTestUser.create(
          peerId: 'peer-admin',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-charlie',
          username: 'Charlie',
          network: network,
        );
        final diana = GroupTestUser.create(
          peerId: 'peer-diana',
          username: 'Diana',
          network: network,
        );

        // Admin creates group and adds everyone
        await admin.createGroup(groupId: groupId, name: 'Test Group');
        await admin.addMember(groupId: groupId, invitee: bob);
        await admin.addMember(groupId: groupId, invitee: charlie);
        await admin.addMember(groupId: groupId, invitee: diana);

        // Start all listeners
        admin.start();
        bob.start();
        charlie.start();
        diana.start();

        // Admin removes Bob
        await admin.removeMember(
          groupId: groupId,
          memberPeerId: bob.peerId,
          memberUsername: 'Bob',
        );
        await pump();

        // Clear Bob's bridge command log to track only post-removal activity
        // (Bob already processed the member_removed system message above)

        // Admin sends "Still here"
        await admin.sendGroupMessage(groupId: groupId, text: 'Still here');

        // Charlie sends "Me too"
        await charlie.sendGroupMessage(groupId: groupId, text: 'Me too');
        await pump();

        // Helper to get incoming messages for a user
        Future<List<GroupMessage>> incomingFor(GroupTestUser user) async {
          final msgs = await user.loadGroupMessages(groupId);
          return msgs.where((m) => m.isIncoming).toList();
        }

        final adminIncoming = await incomingFor(admin);
        final charlieIncoming = await incomingFor(charlie);
        final dianaIncoming = await incomingFor(diana);
        final bobIncoming = await incomingFor(bob);

        // Admin: has "Me too" incoming (from Charlie)
        expect(adminIncoming.map((m) => m.text).toList(), contains('Me too'));

        // Charlie: has "Still here" incoming (from Admin)
        expect(
          charlieIncoming.map((m) => m.text).toList(),
          contains('Still here'),
        );

        // Diana: has both "Still here" and "Me too" incoming
        final dianaTexts = dianaIncoming.map((m) => m.text).toList();
        expect(dianaTexts, containsAll(['Still here', 'Me too']));

        // Bob: has 0 messages after removal (no incoming post-removal messages)
        // Bob may still have the system message processing result but those
        // are not saved as regular messages. Check only text messages.
        final bobPostRemovalTexts = bobIncoming
            .where((m) => m.text == 'Still here' || m.text == 'Me too')
            .toList();
        expect(bobPostRemovalTexts, isEmpty);

        // Cleanup
        admin.dispose();
        bob.dispose();
        charlie.dispose();
        diana.dispose();
      },
    );

    test(
      'remaining member receives readable removal timeline event while member list updates',
      () async {
        const groupId = 'grp-remove-visible-013';

        final admin = GroupTestUser.create(
          peerId: 'peer-admin',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-charlie',
          username: 'Charlie',
          network: network,
        );

        await admin.createGroup(groupId: groupId, name: 'Visible Removal');
        await admin.addMember(groupId: groupId, invitee: bob);
        await admin.addMember(groupId: groupId, invitee: charlie);

        admin.start();
        bob.start();
        charlie.start();

        final bobTimelineEvents = <GroupMessage>[];
        final bobTimelineSub = bob.groupMessageListener.groupMessageStream
            .listen((message) {
              if (message.groupId == groupId) {
                bobTimelineEvents.add(message);
              }
            });

        await admin.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: 'Charlie',
        );
        await pump();

        expect(
          bobTimelineEvents.map((message) => message.text).toList(),
          contains('Admin removed Charlie'),
        );
        expect(
          (await bob.groupRepo.getMembers(
            groupId,
          )).map((member) => member.peerId).toSet(),
          {'peer-admin', 'peer-bob'},
        );

        await bobTimelineSub.cancel();
        admin.dispose();
        bob.dispose();
        charlie.dispose();
      },
    );

    // -----------------------------------------------------------------------
    // 7. Re-add after removal — the removed member resumes active group use,
    //    does not see removed-period traffic, and syncs the current key/member
    //    state.
    // -----------------------------------------------------------------------
    test(
      'removed member can be re-added with current state and resumes send/receive',
      () async {
        const groupId = 'grp-rejoin-007';
        final initialKeyCreatedAt = DateTime.utc(2026, 4, 4, 12);
        final rotatedKeyCreatedAt = DateTime.utc(2026, 4, 4, 12, 1);

        final admin = GroupTestUser.create(
          peerId: 'peer-admin',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-charlie',
          username: 'Charlie',
          network: network,
        );

        Future<void> saveKey(
          GroupTestUser user, {
          required int epoch,
          required String encryptedKey,
          required DateTime createdAt,
        }) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: epoch,
              encryptedKey: encryptedKey,
              createdAt: createdAt,
            ),
          );
        }

        await admin.createGroup(groupId: groupId, name: 'Rejoin Group');
        await saveKey(
          admin,
          epoch: 1,
          encryptedKey: 'group-key-epoch-1',
          createdAt: initialKeyCreatedAt,
        );

        await admin.addMember(groupId: groupId, invitee: bob);
        await saveKey(
          bob,
          epoch: 1,
          encryptedKey: 'group-key-epoch-1',
          createdAt: initialKeyCreatedAt,
        );

        await admin.addMember(groupId: groupId, invitee: charlie);
        await saveKey(
          charlie,
          epoch: 1,
          encryptedKey: 'group-key-epoch-1',
          createdAt: initialKeyCreatedAt,
        );

        admin.start();
        bob.start();
        charlie.start();

        await admin.sendGroupMessage(groupId: groupId, text: 'Before removal');
        await pump();

        await admin.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: 'Charlie',
        );
        await pump();

        expect(await charlie.groupRepo.getGroup(groupId), isNull);
        expect(network.isSubscribed(groupId, charlie.peerId), isFalse);

        await saveKey(
          admin,
          epoch: 2,
          encryptedKey: 'group-key-epoch-2',
          createdAt: rotatedKeyCreatedAt,
        );
        await saveKey(
          bob,
          epoch: 2,
          encryptedKey: 'group-key-epoch-2',
          createdAt: rotatedKeyCreatedAt,
        );

        await admin.sendGroupMessage(groupId: groupId, text: 'During removal');
        await pump();

        await admin.addMember(groupId: groupId, invitee: charlie);
        await saveKey(
          charlie,
          epoch: 2,
          encryptedKey: 'group-key-epoch-2',
          createdAt: rotatedKeyCreatedAt,
        );
        await admin.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await pump();

        expect(await charlie.groupRepo.getGroup(groupId), isNotNull);
        expect(network.isSubscribed(groupId, charlie.peerId), isTrue);

        final charlieMembers = await charlie.groupRepo.getMembers(groupId);
        expect(charlieMembers.map((member) => member.peerId).toSet(), {
          'peer-admin',
          'peer-bob',
          'peer-charlie',
        });
        final charlieRoles = {
          for (final member in charlieMembers) member.peerId: member.role,
        };
        expect(charlieRoles['peer-admin'], MemberRole.admin);
        expect(charlieRoles['peer-bob'], MemberRole.writer);
        expect(charlieRoles['peer-charlie'], MemberRole.writer);

        final charlieKey = await charlie.groupRepo.getLatestKey(groupId);
        expect(charlieKey, isNotNull);
        expect(charlieKey!.keyGeneration, 2);
        expect(charlieKey.encryptedKey, 'group-key-epoch-2');

        await charlie.sendGroupMessage(groupId: groupId, text: 'I am back');
        await pump();

        final adminIncomingAfterRejoin = (await admin.loadGroupMessages(
          groupId,
        )).where((message) => message.isIncoming).toList();
        final bobIncomingAfterRejoin = (await bob.loadGroupMessages(
          groupId,
        )).where((message) => message.isIncoming).toList();
        final charlieOutgoingAfterRejoin = (await charlie.loadGroupMessages(
          groupId,
        )).where((message) => !message.isIncoming).toList();

        expect(
          adminIncomingAfterRejoin.map((message) => message.text),
          contains('I am back'),
        );
        expect(
          bobIncomingAfterRejoin.map((message) => message.text),
          contains('I am back'),
        );
        expect(
          charlieOutgoingAfterRejoin.map((message) => message.text),
          contains('I am back'),
        );
        expect(
          charlieOutgoingAfterRejoin
              .where((message) => message.text == 'I am back')
              .single
              .keyGeneration,
          2,
        );

        await admin.sendGroupMessage(groupId: groupId, text: 'Welcome back');
        await pump();

        final charlieAllMessages = await charlie.loadGroupMessages(groupId);
        final charlieIncomingTexts = charlieAllMessages
            .where((message) => message.isIncoming)
            .map((message) => message.text)
            .toList();

        expect(charlieIncomingTexts, contains('Before removal'));
        expect(charlieIncomingTexts, contains('Welcome back'));
        expect(charlieIncomingTexts, isNot(contains('During removal')));

        admin.dispose();
        bob.dispose();
        charlie.dispose();
      },
    );

    test(
      'removed member notifications stay off until rejoin becomes effective',
      () async {
        const groupId = 'grp-rejoin-notify-005';
        final charlieNotificationService = FakeNotificationService();
        final charlieTracker = ActiveConversationTracker();

        final admin = GroupTestUser.create(
          peerId: 'peer-admin',
          username: 'Admin',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-charlie',
          username: 'Charlie',
          network: network,
          notificationService: charlieNotificationService,
          groupConversationTracker: charlieTracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
        );

        await admin.createGroup(groupId: groupId, name: 'Rejoin Notifications');
        await admin.addMember(groupId: groupId, invitee: charlie);

        admin.start();
        charlie.start();

        await admin.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: 'Charlie',
        );
        await pump();

        expect(await charlie.groupRepo.getGroup(groupId), isNull);
        expect(network.isSubscribed(groupId, charlie.peerId), isFalse);

        await admin.sendGroupMessage(groupId: groupId, text: 'While removed');
        await pump();

        expect(
          charlieNotificationService.shown,
          isEmpty,
          reason: 'Removed members must not receive local notifications',
        );

        await admin.addMember(groupId: groupId, invitee: charlie);
        await admin.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await pump();

        expect(await charlie.groupRepo.getGroup(groupId), isNotNull);
        expect(network.isSubscribed(groupId, charlie.peerId), isTrue);
        expect(charlieNotificationService.shown, isEmpty);

        await admin.sendGroupMessage(groupId: groupId, text: 'After rejoin');
        await pump();

        expect(charlieNotificationService.shown, hasLength(1));
        expect(
          charlieNotificationService.shown.single.contactPeerId,
          'group:$groupId',
        );
        expect(
          charlieNotificationService.shown.single.senderUsername,
          'Rejoin Notifications',
        );
        expect(
          charlieNotificationService.shown.single.messageText,
          'Admin: After rejoin',
        );

        final charlieIncomingTexts = (await charlie.loadGroupMessages(groupId))
            .where((message) => message.isIncoming)
            .map((message) => message.text)
            .toList();
        expect(charlieIncomingTexts, contains('After rejoin'));
        expect(charlieIncomingTexts, isNot(contains('While removed')));

        admin.dispose();
        charlie.dispose();
      },
    );

    test(
      'long mixed-content group text survives delivery and notification preview',
      () async {
        const groupId = 'grp-mixed-text-006';
        final bobNotificationService = FakeNotificationService();
        final bobTracker = ActiveConversationTracker();
        final longPrefix = List.filled(18, 'LongSegment-006').join(' ');
        final complexText =
            '$longPrefix 😀🚀 مرحبا بالعالم & <xml> [brackets] {curly} %25 + = ? !';

        final admin = GroupTestUser.create(
          peerId: 'peer-admin',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-bob',
          username: 'Bob',
          network: network,
          notificationService: bobNotificationService,
          groupConversationTracker: bobTracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
        );

        await admin.createGroup(groupId: groupId, name: 'Mixed Text Group');
        await admin.addMember(groupId: groupId, invitee: bob);

        admin.start();
        bob.start();

        await admin.sendGroupMessage(groupId: groupId, text: complexText);
        await pump();

        final adminOutgoing = (await admin.loadGroupMessages(
          groupId,
        )).where((message) => !message.isIncoming).toList();
        expect(adminOutgoing, hasLength(1));
        expect(adminOutgoing.single.text, complexText);

        final bobIncoming = (await bob.loadGroupMessages(
          groupId,
        )).where((message) => message.isIncoming).toList();
        expect(bobIncoming, hasLength(1));
        expect(bobIncoming.single.text, complexText);
        expect(bobIncoming.single.text.length, complexText.length);

        expect(bobNotificationService.shown, hasLength(1));
        expect(
          bobNotificationService.shown.single.contactPeerId,
          'group:$groupId',
        );
        expect(
          bobNotificationService.shown.single.senderUsername,
          'Mixed Text Group',
        );
        expect(
          bobNotificationService.shown.single.messageText,
          'Admin: $complexText',
        );

        admin.dispose();
        bob.dispose();
      },
    );

    test(
      'remaining member receives readable re-add timeline event while member list updates',
      () async {
        const groupId = 'grp-readd-visible-007';

        final admin = GroupTestUser.create(
          peerId: 'peer-admin',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-charlie',
          username: 'Charlie',
          network: network,
        );

        await admin.createGroup(groupId: groupId, name: 'Re-add Visibility');
        await admin.addMember(groupId: groupId, invitee: bob);
        await admin.addMember(groupId: groupId, invitee: charlie);

        admin.start();
        bob.start();
        charlie.start();

        await admin.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: 'Charlie',
        );
        await pump();

        final bobTimelineEvents = <GroupMessage>[];
        final bobTimelineSub = bob.groupMessageListener.groupMessageStream
            .listen((message) {
              if (message.groupId == groupId) {
                bobTimelineEvents.add(message);
              }
            });

        await admin.addMember(groupId: groupId, invitee: charlie);
        await admin.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await pump();

        expect(
          bobTimelineEvents.map((message) => message.text).toList(),
          contains('Admin added Charlie'),
        );
        expect(
          (await bob.groupRepo.getMembers(
            groupId,
          )).map((member) => member.peerId).toSet(),
          {'peer-admin', 'peer-bob', 'peer-charlie'},
        );

        await bobTimelineSub.cancel();
        admin.dispose();
        bob.dispose();
        charlie.dispose();
      },
    );

    test(
      'offline member converges to dissolved state through replay, cannot send afterwards, and can delete locally without affecting others',
      () async {
        const groupId = 'grp-dissolve-001';

        final alice = GroupTestUser.create(
          peerId: 'peer-alice',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-bob',
          username: 'Bob',
          network: network,
        );

        Future<void> saveKey(GroupTestUser user, {required int epoch}) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: epoch,
              encryptedKey: 'group-key-epoch-$epoch',
              createdAt: DateTime.now().toUtc(),
            ),
          );
        }

        await alice.createGroup(groupId: groupId, name: 'Temporary Group');
        await saveKey(alice, epoch: 1);
        await alice.addMember(groupId: groupId, invitee: bob);
        await saveKey(bob, epoch: 1);

        alice.start();

        final (result, dissolvedGroup) = await alice.dissolveGroupViaBridge(
          groupId: groupId,
        );

        expect(result, group_dissolve.DissolveGroupResult.success);
        expect(dissolvedGroup, isNotNull);
        expect(dissolvedGroup!.isDissolved, isTrue);
        expect(network.isSubscribed(groupId, alice.peerId), isFalse);
        expect(network.isSubscribed(groupId, bob.peerId), isFalse);

        final inboxRaw = alice.bridge.sentMessages.lastWhere(
          (message) =>
              (jsonDecode(message) as Map<String, dynamic>)['cmd'] ==
              'group:inboxStore',
        );
        final inboxPayload =
            (jsonDecode(inboxRaw) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;

        await bob.groupMessageListener.handleReplayEnvelope(
          decodeReplayPayload(inboxPayload),
        );
        await pump();

        final bobGroup = await bob.groupRepo.getGroup(groupId);
        expect(bobGroup, isNotNull);
        expect(bobGroup!.isDissolved, isTrue);

        final bobLatest = await bob.msgRepo.getLatestMessage(groupId);
        expect(bobLatest, isNotNull);
        expect(bobLatest!.text, 'Alice dissolved the group');

        final (sendResult, sendMessage) = await bob.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'Too late',
        );

        expect(sendResult, group_send.SendGroupMessageResult.groupDissolved);
        expect(sendMessage, isNull);
        expect(bob.bridge.commandLog, isNot(contains('group:publish')));

        bob.bridge.commandLog.clear();

        await deleteGroupAndMessages(
          bridge: bob.bridge,
          groupRepo: bob.groupRepo,
          groupMessageRepo: bob.msgRepo,
          groupId: groupId,
          deleteLocallyIfDissolved: true,
        );
        await pump();

        expect(await bob.groupRepo.getGroup(groupId), isNull);
        expect(await bob.groupRepo.getMembers(groupId), isEmpty);
        expect(await bob.groupRepo.getLatestKey(groupId), isNull);
        expect(await bob.msgRepo.getMessageCount(groupId), 0);
        expect(bob.bridge.commandLog, isNot(contains('group:leave')));

        final aliceGroup = await alice.groupRepo.getGroup(groupId);
        expect(aliceGroup, isNotNull);
        expect(aliceGroup!.isDissolved, isTrue);

        alice.dispose();
        bob.dispose();
      },
    );
  });
}
