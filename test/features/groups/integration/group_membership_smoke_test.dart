import 'package:flutter_app/features/groups/domain/models/group_message.dart';
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
    // 4. member_added system message — existing members update local member
    //    list.
    // -----------------------------------------------------------------------
    test(
      'member_added system message — existing members update local member list',
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

        // Bob's groupRepo should have Charlie as a member
        final bobMembers = await bob.groupRepo.getMembers(groupId);
        final bobMemberPeerIds = bobMembers.map((m) => m.peerId).toSet();
        expect(bobMemberPeerIds, contains(charlie.peerId));

        // Bob's bridge.commandLog should contain 'group:updateConfig'
        expect(bob.bridge.commandLog, contains('group:updateConfig'));

        // Cleanup
        admin.dispose();
        bob.dispose();
        charlie.dispose();
      },
    );

    // -----------------------------------------------------------------------
    // 5. Post-removal messaging — admin can still send to remaining members.
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
  });
}
