import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart'
    as group_send;
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/fake_group_pubsub_network.dart';
import '../../../shared/fakes/group_test_user.dart';

void main() {
  late FakeGroupPubSubNetwork network;

  setUp(() {
    network = FakeGroupPubSubNetwork();
  });

  Future<void> pump() => Future.delayed(const Duration(milliseconds: 50));

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
        final bobIncoming =
            bobMessages.where((m) => m.isIncoming).toList();
        final charlieIncoming =
            charlieMessages.where((m) => m.isIncoming).toList();
        final dianaIncoming =
            dianaMessages.where((m) => m.isIncoming).toList();

        // Bob: only 1 incoming message ("Before removal")
        expect(bobIncoming, hasLength(1));
        expect(bobIncoming[0].text, equals('Before removal'));

        // Charlie: 2 incoming messages
        expect(charlieIncoming, hasLength(2));
        expect(
          charlieIncoming.map((m) => m.text).toList(),
          containsAll(['Before removal', 'After removal']),
        );

        // Diana: 2 incoming messages
        expect(dianaIncoming, hasLength(2));
        expect(
          dianaIncoming.map((m) => m.text).toList(),
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
        final removedSub =
            bob.groupMessageListener.groupRemovedStream.listen((gid) {
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
    // 4. Removed member loses send permission after self-removal cleanup.
    // -----------------------------------------------------------------------
    test(
      'removed member cannot send after self-removal cleanup',
      () async {
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
      },
    );

    // -----------------------------------------------------------------------
    // 5. Add member success + member_added system message — existing members
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
        await admin.broadcastMemberAdded(
          groupId: groupId,
          newMember: charlie,
        );
        await pump();

        // Charlie starts after the bootstrap data is written to local repos.
        charlie.start();

        Future<void> expectSyncedMembers(GroupTestUser user) async {
          final members = await user.groupRepo.getMembers(groupId);
          expect(
            members.map((member) => member.peerId).toSet(),
            {'peer-admin', 'peer-bob', 'peer-charlie'},
          );
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
        expect(bobIncoming, hasLength(1));
        expect(bobIncoming.single.text, 'Hi team');
        expect(charlieOutgoing, hasLength(1));
        expect(charlieOutgoing.single.text, 'Hi team');

        // Cleanup
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
        expect(
          adminIncoming.map((m) => m.text).toList(),
          contains('Me too'),
        );

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
            .where((m) =>
                m.text == 'Still here' || m.text == 'Me too')
            .toList();
        expect(bobPostRemovalTexts, isEmpty);

        // Cleanup
        admin.dispose();
        bob.dispose();
        charlie.dispose();
        diana.dispose();
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

        await admin.sendGroupMessage(
          groupId: groupId,
          text: 'During removal',
        );
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
        expect(
          charlieMembers.map((member) => member.peerId).toSet(),
          {'peer-admin', 'peer-bob', 'peer-charlie'},
        );
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
  });
}
