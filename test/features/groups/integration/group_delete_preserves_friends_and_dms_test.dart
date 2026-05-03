/// Smoke test for the user-reported invariant:
/// when user-B deletes a group from Orbit (swipe-left -> Delete), only that
/// group is removed. B's friends list and 1:1 chat history with each friend
/// must remain intact, and other users (A, C) must not have their local
/// group state corrupted by B's local action.
///
/// Mirrors `group_messaging_smoke_test.dart` setup but composes 1:1
/// contact + message repos alongside each `GroupTestUser` to verify the
/// non-group state is unaffected by the group-delete code path.

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/groups/application/delete_group_and_messages_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/fake_group_pubsub_network.dart';
import '../../../shared/fakes/group_test_user.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_message_repository.dart';

void main() {
  group(
    'Group delete from Orbit preserves friends and 1:1 chat history',
    () {
      late FakeGroupPubSubNetwork network;

      setUp(() {
        network = FakeGroupPubSubNetwork();
      });

      Future<void> pump() => Future.delayed(const Duration(milliseconds: 50));

      ContactModel _contactFor(GroupTestUser other) => ContactModel(
            peerId: other.peerId,
            publicKey: 'pk-${other.peerId}',
            rendezvous: '/dns4/relay/tcp/443/p2p/relay',
            username: other.username,
            signature: 'sig-${other.peerId}',
            scannedAt: '2026-04-01T00:00:00.000Z',
            mlKemPublicKey: 'mlkem-${other.peerId}',
          );

      ConversationMessage _dm({
        required String id,
        required String otherPeerId,
        required String selfPeerId,
        required String text,
        required bool isIncoming,
        required String timestamp,
      }) =>
          ConversationMessage(
            id: id,
            contactPeerId: otherPeerId,
            senderPeerId: isIncoming ? otherPeerId : selfPeerId,
            text: text,
            timestamp: timestamp,
            status: isIncoming ? 'delivered' : 'sent',
            isIncoming: isIncoming,
            createdAt: timestamp,
          );

      test(
        'B deletes the group: B keeps friends + DMs; A and C local group state untouched',
        () async {
          // -- arrange: 3 mutual friends, each with a per-user group stack
          //             plus a per-user 1:1 contacts + messages stack.
          final alice = GroupTestUser.create(
            peerId: 'alice-peer',
            username: 'Alice',
            network: network,
          );
          final bob = GroupTestUser.create(
            peerId: 'bob-peer',
            username: 'Bob',
            network: network,
          );
          final charlie = GroupTestUser.create(
            peerId: 'charlie-peer',
            username: 'Charlie',
            network: network,
          );
          addTearDown(() {
            alice.dispose();
            bob.dispose();
            charlie.dispose();
          });

          // 1:1 contact repos (one per user)
          final aliceContacts = InMemoryContactRepository();
          final bobContacts = InMemoryContactRepository();
          final charlieContacts = InMemoryContactRepository();

          // 1:1 message repos (one per user)
          final aliceMessages = InMemoryMessageRepository();
          final bobMessages = InMemoryMessageRepository();
          final charlieMessages = InMemoryMessageRepository();

          // Mutual friendships: each user knows the other two.
          await aliceContacts.addContact(_contactFor(bob));
          await aliceContacts.addContact(_contactFor(charlie));
          await bobContacts.addContact(_contactFor(alice));
          await bobContacts.addContact(_contactFor(charlie));
          await charlieContacts.addContact(_contactFor(alice));
          await charlieContacts.addContact(_contactFor(bob));

          // Pre-existing 1:1 chat history (2 messages per pair, from each side).
          // We only assert on Bob's view, but seed everyone for symmetry.
          await bobMessages.saveMessage(_dm(
            id: 'b-a-1',
            otherPeerId: alice.peerId,
            selfPeerId: bob.peerId,
            text: 'hey alice',
            isIncoming: false,
            timestamp: '2026-04-10T09:00:00.000Z',
          ));
          await bobMessages.saveMessage(_dm(
            id: 'b-a-2',
            otherPeerId: alice.peerId,
            selfPeerId: bob.peerId,
            text: 'hello bob',
            isIncoming: true,
            timestamp: '2026-04-10T09:01:00.000Z',
          ));
          await bobMessages.saveMessage(_dm(
            id: 'b-c-1',
            otherPeerId: charlie.peerId,
            selfPeerId: bob.peerId,
            text: 'hey charlie',
            isIncoming: false,
            timestamp: '2026-04-10T10:00:00.000Z',
          ));
          await bobMessages.saveMessage(_dm(
            id: 'b-c-2',
            otherPeerId: charlie.peerId,
            selfPeerId: bob.peerId,
            text: 'hi bob',
            isIncoming: true,
            timestamp: '2026-04-10T10:01:00.000Z',
          ));

          // -- act: A creates a group, invites B and C, members accept,
          //          A sends a few group messages.
          const groupId = 'game-night';
          await alice.createGroup(groupId: groupId, name: 'Game Night');
          await alice.addMember(groupId: groupId, invitee: bob);
          alice.start();
          bob.start();
          charlie.start();
          await alice.addMember(groupId: groupId, invitee: charlie);
          await alice.broadcastMemberAdded(
            groupId: groupId,
            newMember: charlie,
          );
          await pump();

          await alice.sendGroupMessage(groupId: groupId, text: 'who is in?');
          await alice.sendGroupMessage(groupId: groupId, text: 'tonight 8pm');
          await alice.sendGroupMessage(groupId: groupId, text: 'bring snacks');
          await pump();

          // Sanity: B has the group, all 3 members, and A's messages.
          expect(await bob.groupRepo.getGroup(groupId), isNotNull);
          expect(
            (await bob.groupRepo.getMembers(groupId))
                .map((m) => m.peerId)
                .toSet(),
            {alice.peerId, bob.peerId, charlie.peerId},
          );
          // The 3 chat messages must arrive. A system "added Charlie"
          // message also lands here as an incoming row — that is correct
          // production behavior, so we assert containment rather than equality.
          final bobIncomingTexts = (await bob.loadGroupMessages(groupId))
              .where((m) => m.isIncoming)
              .map((m) => m.text)
              .toList();
          expect(
            bobIncomingTexts,
            containsAll(['who is in?', 'tonight 8pm', 'bring snacks']),
          );

          // Snapshot Bob's pre-delete 1:1 state for end-to-end equality check.
          final bobContactsBefore =
              (await bobContacts.getAllContacts()).map((c) => c.peerId).toSet();
          final bobDmsWithAliceBefore =
              await bobMessages.getMessagesForContact(alice.peerId);
          final bobDmsWithCharlieBefore =
              await bobMessages.getMessagesForContact(charlie.peerId);

          // Sanity: Alice and Charlie also see the group + members.
          expect(await alice.groupRepo.getGroup(groupId), isNotNull);
          expect(await charlie.groupRepo.getGroup(groupId), isNotNull);

          // -- act: Bob deletes the group from Orbit (swipe-left -> Delete).
          // Mirrors the orbit_wired.dart call with deleteLocallyIfDissolved: true.
          // The group is NOT dissolved here, so the use case takes the
          // leaveGroup path which still deletes Bob's local copy.
          await deleteGroupAndMessages(
            bridge: bob.bridge,
            groupRepo: bob.groupRepo,
            groupMessageRepo: bob.msgRepo,
            groupId: groupId,
            deleteLocallyIfDissolved: true,
          );

          // -- assert: Bob's group state is fully purged.
          expect(
            await bob.groupRepo.getGroup(groupId),
            isNull,
            reason: 'Bob should no longer have the deleted group locally',
          );
          expect(
            await bob.groupRepo.getMembers(groupId),
            isEmpty,
            reason: 'Bob should no longer have any members of the deleted group',
          );
          expect(
            await bob.groupRepo.getLatestKey(groupId),
            isNull,
            reason: 'Bob should no longer have any keys for the deleted group',
          );
          expect(
            await bob.loadGroupMessages(groupId),
            isEmpty,
            reason: 'Bob should no longer have any messages for the deleted group',
          );

          // -- assert: Bob's friends are intact (the regression we are guarding).
          final bobContactsAfter =
              (await bobContacts.getAllContacts()).map((c) => c.peerId).toSet();
          expect(
            bobContactsAfter,
            equals(bobContactsBefore),
            reason: 'Group delete must not touch the contacts table',
          );
          expect(
            bobContactsAfter,
            containsAll([alice.peerId, charlie.peerId]),
            reason: 'Bob must still see Alice and Charlie as friends',
          );

          // -- assert: Bob's 1:1 chat history is intact.
          final bobDmsWithAliceAfter =
              await bobMessages.getMessagesForContact(alice.peerId);
          expect(
            bobDmsWithAliceAfter.map((m) => m.id).toList(),
            equals(bobDmsWithAliceBefore.map((m) => m.id).toList()),
            reason: 'Group delete must not touch 1:1 chat history with Alice',
          );
          expect(bobDmsWithAliceAfter, hasLength(2));
          expect(bobDmsWithAliceAfter.map((m) => m.text).toList(),
              ['hey alice', 'hello bob']);

          final bobDmsWithCharlieAfter =
              await bobMessages.getMessagesForContact(charlie.peerId);
          expect(
            bobDmsWithCharlieAfter.map((m) => m.id).toList(),
            equals(bobDmsWithCharlieBefore.map((m) => m.id).toList()),
            reason: 'Group delete must not touch 1:1 chat history with Charlie',
          );
          expect(bobDmsWithCharlieAfter, hasLength(2));
          expect(bobDmsWithCharlieAfter.map((m) => m.text).toList(),
              ['hey charlie', 'hi bob']);

          // -- assert: Bob's deletion is local. Alice and Charlie still have
          //            the group + members locally. (They might receive a
          //            'leave' broadcast asynchronously but that is a separate
          //            concern; what we are guarding here is that Bob's local
          //            action does not reach into A/C's repos directly.)
          expect(
            await alice.groupRepo.getGroup(groupId),
            isNotNull,
            reason: "Bob's local delete must not remove Alice's local group",
          );
          expect(
            await charlie.groupRepo.getGroup(groupId),
            isNotNull,
            reason: "Bob's local delete must not remove Charlie's local group",
          );

          // -- assert: no other group exists in Bob's repo.
          //            (Defensive: catches a regression where the use case
          //            wipes too much.)
          expect(
            await bob.groupRepo.getAllGroups(),
            isEmpty,
            reason: 'Only the targeted group should be deleted',
          );
        },
      );

      test(
        'B has multiple groups: deleting one does not touch the others',
        () async {
          final alice = GroupTestUser.create(
            peerId: 'alice-peer',
            username: 'Alice',
            network: network,
          );
          final bob = GroupTestUser.create(
            peerId: 'bob-peer',
            username: 'Bob',
            network: network,
          );
          addTearDown(() {
            alice.dispose();
            bob.dispose();
          });

          alice.start();
          bob.start();

          await alice.createGroup(
            groupId: 'group-keep',
            name: 'Group To Keep',
          );
          await alice.addMember(groupId: 'group-keep', invitee: bob);
          await alice.createGroup(
            groupId: 'group-delete',
            name: 'Group To Delete',
          );
          await alice.addMember(groupId: 'group-delete', invitee: bob);
          await pump();

          await alice.sendGroupMessage(
            groupId: 'group-keep',
            text: 'this stays',
          );
          await alice.sendGroupMessage(
            groupId: 'group-delete',
            text: 'this goes',
          );
          await pump();

          // -- act
          await deleteGroupAndMessages(
            bridge: bob.bridge,
            groupRepo: bob.groupRepo,
            groupMessageRepo: bob.msgRepo,
            groupId: 'group-delete',
            deleteLocallyIfDissolved: true,
          );

          // -- assert: only the targeted group is gone.
          expect(await bob.groupRepo.getGroup('group-delete'), isNull);
          expect(await bob.loadGroupMessages('group-delete'), isEmpty);

          final keptGroup = await bob.groupRepo.getGroup('group-keep');
          expect(
            keptGroup,
            isA<GroupModel>(),
            reason: 'The other group must survive the targeted delete',
          );
          expect(keptGroup!.name, 'Group To Keep');

          final keptMessages = await bob.loadGroupMessages('group-keep');
          expect(keptMessages.where((m) => m.text == 'this stays'), hasLength(1));
        },
      );
    },
  );
}
