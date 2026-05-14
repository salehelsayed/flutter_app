import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/fake_group_pubsub_network.dart';
import '../../../shared/fakes/group_test_user.dart';

void main() {
  late FakeGroupPubSubNetwork network;

  setUp(() {
    network = FakeGroupPubSubNetwork();
  });

  Future<void> pump([Duration d = const Duration(milliseconds: 50)]) =>
      Future.delayed(d);

  Future<void> waitUntil(
    Future<bool> Function() condition, {
    int maxTicks = 80,
    Duration interval = const Duration(milliseconds: 25),
    String? reason,
  }) async {
    for (var i = 0; i < maxTicks; i++) {
      if (await condition()) return;
      await Future<void>.delayed(interval);
    }
    fail(reason ?? 'Timed out waiting for condition');
  }

  group('Group edge cases and fault injection smoke tests', () {
    // ---------------------------------------------------------------
    // 1. Delivery failure — messages not delivered when network fails
    // ---------------------------------------------------------------
    test(
      'delivery failure — messages not delivered when network fails',
      () async {
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

        final groupId = 'grp-delivery-fail';
        await admin.createGroup(groupId: groupId, name: 'Fail Group');
        await admin.addMember(groupId: groupId, invitee: bob);

        admin.start();
        bob.start();

        // Enable delivery failure
        network.deliveryFails = true;
        await admin.sendGroupMessage(groupId: groupId, text: 'Lost message');
        await pump();

        // Admin saves outgoing locally
        final adminMsgs = await admin.loadGroupMessages(groupId);
        expect(adminMsgs.length, 1);
        expect(adminMsgs.first.text, 'Lost message');

        // Bob receives nothing (delivery was dropped)
        final bobMsgs = await bob.loadGroupMessages(groupId);
        expect(bobMsgs.length, 0);

        // Recover the network
        network.deliveryFails = false;
        await admin.sendGroupMessage(groupId: groupId, text: 'Recovered');
        await pump();

        // Bob now receives the recovered message
        final bobMsgsAfter = await bob.loadGroupMessages(groupId);
        expect(bobMsgsAfter.length, 1);
        expect(bobMsgsAfter.first.text, 'Recovered');

        admin.dispose();
        bob.dispose();
      },
    );

    // ---------------------------------------------------------------
    // 2. Duplicate delivery — GroupMessageListener handles idempotently
    // ---------------------------------------------------------------
    test(
      'duplicate delivery — GroupMessageListener handles idempotently',
      () async {
        // Dedup is now implemented: handleIncomingGroupMessage checks for
        // existing messages with the same (groupId, senderPeerId, text, timestamp)
        // before saving, so duplicate deliveries are silently dropped.
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

        final groupId = 'grp-duplicate';
        await admin.createGroup(groupId: groupId, name: 'Dupe Group');
        await admin.addMember(groupId: groupId, invitee: bob);

        admin.start();
        bob.start();

        // Enable duplicate delivery
        network.duplicateOnDeliver = true;
        await admin.sendGroupMessage(groupId: groupId, text: 'Duped');
        await pump();

        // Bob should have only 1 message — the duplicate is deduplicated.
        final bobMsgs = await bob.loadGroupMessages(groupId);
        expect(bobMsgs.length, 1);
        expect(bobMsgs[0].text, 'Duped');

        admin.dispose();
        bob.dispose();
      },
    );

    // ---------------------------------------------------------------
    // 3. Delivery delay — messages arrive after delay
    // ---------------------------------------------------------------
    test('delivery delay — messages arrive after delay', () async {
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

      final groupId = 'grp-delayed';
      await admin.createGroup(groupId: groupId, name: 'Delay Group');
      await admin.addMember(groupId: groupId, invitee: bob);

      admin.start();
      bob.start();

      // Set delivery delay
      network.deliveryDelay = const Duration(milliseconds: 100);
      // Do not await sendGroupMessage — publish is delayed internally
      admin.sendGroupMessage(groupId: groupId, text: 'Delayed');

      // After 20ms, Bob should not yet have the message
      await pump(const Duration(milliseconds: 20));
      final bobMsgsEarly = await bob.loadGroupMessages(groupId);
      expect(bobMsgsEarly.length, 0);

      // After 150ms more, the message should have arrived
      await pump(const Duration(milliseconds: 150));
      final bobMsgsLate = await bob.loadGroupMessages(groupId);
      expect(bobMsgsLate.length, 1);
      expect(bobMsgsLate.first.text, 'Delayed');

      admin.dispose();
      bob.dispose();
    });

    // ---------------------------------------------------------------
    // 4. 5 users simultaneous messaging — high fan-out
    // ---------------------------------------------------------------
    test('5 users simultaneous messaging — high fan-out', () async {
      final users = List.generate(
        5,
        (i) => GroupTestUser.create(
          peerId: 'peer-user-$i',
          username: 'User$i',
          network: network,
        ),
      );

      final groupId = 'grp-fanout';
      // User 0 is the admin — creates the group
      await users[0].createGroup(groupId: groupId, name: 'Fan-out Group');
      // Add remaining users
      for (var i = 1; i < users.length; i++) {
        await users[0].addMember(groupId: groupId, invitee: users[i]);
      }

      // Start all listeners
      for (final u in users) {
        u.start();
      }

      for (var i = 1; i < users.length; i++) {
        await users[0].broadcastMemberAdded(
          groupId: groupId,
          newMember: users[i],
        );
      }
      await pump();
      network.resetCounters();

      // Each user sends one message simultaneously (don't await between sends)
      final sends = <Future>[];
      for (var i = 0; i < users.length; i++) {
        sends.add(
          users[i].sendGroupMessage(
            groupId: groupId,
            text: 'Hello from User$i',
          ),
        );
      }
      await Future.wait(sends);
      await pump(const Duration(milliseconds: 100));

      // Each user should have 5 total messages: 1 outgoing + 4 incoming
      for (var i = 0; i < users.length; i++) {
        final msgs = (await users[i].loadGroupMessages(
          groupId,
        )).where((message) => !message.id.startsWith('sys-')).toList();
        expect(
          msgs.length,
          5,
          reason: 'User$i should have 5 messages (1 sent + 4 received)',
        );

        final outgoing = msgs.where((m) => !m.isIncoming).length;
        final incoming = msgs.where((m) => m.isIncoming).length;
        expect(outgoing, 1, reason: 'User$i should have 1 outgoing message');
        expect(incoming, 4, reason: 'User$i should have 4 incoming messages');
      }

      // Network counters: 5 publishes, 20 deliveries (5 msgs x 4 recipients)
      expect(network.publishCount, 5);
      expect(network.totalDeliveries, 20);

      for (final u in users) {
        u.dispose();
      }
    });

    // ---------------------------------------------------------------
    // 5. Leave group voluntarily — user stops receiving
    // ---------------------------------------------------------------
    test('leave group voluntarily — user stops receiving', () async {
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

      final groupId = 'grp-leave';
      await admin.createGroup(groupId: groupId, name: 'Leave Group');
      await admin.addMember(groupId: groupId, invitee: bob);
      await admin.addMember(groupId: groupId, invitee: charlie);

      admin.start();
      bob.start();
      charlie.start();

      // Bob leaves the group voluntarily
      await bob.leaveGroup(groupId);

      // Admin sends a message after Bob left
      await admin.sendGroupMessage(groupId: groupId, text: 'After Bob left');
      await pump();

      // Charlie sees the leave timeline plus the post-leave chat message.
      final charlieMsgs = await charlie.loadGroupMessages(groupId);
      expect(charlieMsgs, hasLength(2));
      expect(
        charlieMsgs.map((message) => message.text),
        containsAll(['Bob left the group', 'After Bob left']),
      );

      // Bob keeps the local leave timeline even after the group is removed.
      final bobMsgs = await bob.loadGroupMessages(groupId);
      expect(bobMsgs, hasLength(1));
      expect(bobMsgs.single.text, 'Bob left the group');

      // Bob's groupRepo should have no group
      final bobGroup = await bob.groupRepo.getGroup(groupId);
      expect(bobGroup, isNull);

      admin.dispose();
      bob.dispose();
      charlie.dispose();
    });

    // ---------------------------------------------------------------
    // 6. Rapid message burst — 20 messages from single sender
    // ---------------------------------------------------------------
    test('rapid message burst — 20 messages from single sender', () async {
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

      final groupId = 'grp-burst';
      await admin.createGroup(groupId: groupId, name: 'Burst Group');
      await admin.addMember(groupId: groupId, invitee: bob);

      admin.start();
      bob.start();

      // Admin sends 20 messages rapidly in a loop. We use sequential await
      // because GroupTestUser.sendGroupMessage generates message IDs from
      // peerId + millisecondsSinceEpoch — concurrent sends within the same
      // millisecond would collide in the in-memory repo. Sequential sends
      // are still fast (sub-millisecond each in-memory) and still test the
      // listener's ability to process a rapid burst.
      for (var i = 0; i < 20; i++) {
        await admin.sendGroupMessage(groupId: groupId, text: 'Burst $i');
      }
      await pump(const Duration(milliseconds: 200));

      // Bob should have exactly 20 incoming messages
      final bobCount = await bob.msgRepo.getMessageCount(groupId);
      final bobMsgs = await bob.loadGroupMessages(groupId);
      expect(bobCount, 20, reason: 'Bob msgRepo count should be 20');
      expect(bobMsgs.length, 20);
      expect(bobMsgs.every((m) => m.isIncoming), isTrue);

      // Admin outgoing messages may collide on ID (peerId + millisecond)
      // when sent within the same millisecond, so we only check that
      // at least 1 outgoing was saved (the last one per timestamp wins).
      final adminMsgs = await admin.loadGroupMessages(groupId);
      expect(adminMsgs.isNotEmpty, isTrue);
      expect(adminMsgs.every((m) => !m.isIncoming), isTrue);

      admin.dispose();
      bob.dispose();
    });

    test(
      'GP-028 high-volume burst keeps entitlement windows exact while adding and removing Diana',
      () async {
        const groupId = 'grp-gp028-burst-mutation';
        const totalMessages = 120;
        const addDianaAt = 30;
        const removeDianaAt = 90;
        final baseTime = DateTime.utc(2024, 1, 1);

        final alice = GroupTestUser.create(
          peerId: 'peer-gp028-alice',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-gp028-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-gp028-charlie',
          username: 'Charlie',
          network: network,
        );
        final diana = GroupTestUser.create(
          peerId: 'peer-gp028-diana',
          username: 'Diana',
          network: network,
        );

        alice.start();
        bob.start();
        charlie.start();
        diana.start();

        await alice.createGroup(groupId: groupId, name: 'GP-028 Burst Group');
        await alice.addMember(groupId: groupId, invitee: bob);
        await alice.addMember(groupId: groupId, invitee: charlie);

        String messageIdFor(int index) =>
            'gp028-burst-${index.toString().padLeft(3, '0')}';
        String messageTextFor(int index) =>
            'GP-028 burst ${index.toString().padLeft(3, '0')}';

        for (var i = 0; i < totalMessages; i++) {
          if (i == addDianaAt) {
            await alice.addMember(
              groupId: groupId,
              invitee: diana,
              joinedAt: baseTime.add(const Duration(seconds: addDianaAt)),
            );
            await alice.broadcastMemberAdded(
              groupId: groupId,
              newMember: diana,
            );
          }

          if (i == removeDianaAt) {
            await alice.removeMember(
              groupId: groupId,
              memberPeerId: diana.peerId,
              memberUsername: diana.username,
              removedAt: baseTime.add(const Duration(seconds: removeDianaAt)),
            );
          }

          await alice.sendGroupMessage(
            groupId: groupId,
            text: messageTextFor(i),
            messageId: messageIdFor(i),
            timestamp: baseTime.add(Duration(seconds: i, milliseconds: 1)),
          );
        }

        const burstPageLimit = totalMessages + 10;
        Future<List<GroupMessage>> loadBurstMessages(GroupTestUser user) async {
          final messages = await user.msgRepo.getMessagesPage(
            groupId,
            limit: burstPageLimit,
          );
          return messages
              .where((message) => message.id.startsWith('gp028-burst-'))
              .toList();
        }

        var bobBurstCount = 0;
        var charlieBurstCount = 0;
        var dianaBurstCount = 0;
        var settled = false;
        for (var tick = 0; tick < 400; tick++) {
          bobBurstCount = (await loadBurstMessages(bob)).length;
          charlieBurstCount = (await loadBurstMessages(charlie)).length;
          dianaBurstCount = (await loadBurstMessages(diana)).length;
          if (bobBurstCount == totalMessages &&
              charlieBurstCount == totalMessages &&
              dianaBurstCount == removeDianaAt - addDianaAt) {
            settled = true;
            break;
          }
          await pump(const Duration(milliseconds: 25));
        }
        expect(
          settled,
          isTrue,
          reason:
              'GP-028 burst deliveries did not settle: '
              'Bob=$bobBurstCount/$totalMessages, '
              'Charlie=$charlieBurstCount/$totalMessages, '
              'Diana=$dianaBurstCount/${removeDianaAt - addDianaAt}',
        );

        Future<void> expectBurstWindow(
          GroupTestUser user, {
          required Iterable<int> expectedIndexes,
          required bool incoming,
        }) async {
          final expectedIds = expectedIndexes.map(messageIdFor).toSet();
          final messages = await loadBurstMessages(user);
          final ids = messages.map((message) => message.id).toList();

          expect(
            ids,
            hasLength(expectedIds.length),
            reason: '${user.username} should have the expected burst count',
          );
          expect(
            ids.toSet(),
            expectedIds,
            reason: '${user.username} should have exactly the expected ids',
          );
          expect(
            ids.toSet(),
            hasLength(ids.length),
            reason: '${user.username} should not have duplicate burst ids',
          );
          expect(
            messages.every((message) => message.isIncoming == incoming),
            isTrue,
            reason: '${user.username} message direction should match role',
          );

          for (final index in expectedIndexes) {
            final matching = messages
                .where(
                  (message) =>
                      message.id == messageIdFor(index) &&
                      message.text == messageTextFor(index),
                )
                .toList();
            expect(
              matching,
              hasLength(1),
              reason:
                  '${user.username} should have ${messageIdFor(index)} exactly once',
            );
          }
        }

        final allIndexes = List<int>.generate(totalMessages, (i) => i);
        final dianaWindow = List<int>.generate(
          removeDianaAt - addDianaAt,
          (i) => addDianaAt + i,
        );

        await expectBurstWindow(
          alice,
          expectedIndexes: allIndexes,
          incoming: false,
        );
        await expectBurstWindow(
          bob,
          expectedIndexes: allIndexes,
          incoming: true,
        );
        await expectBurstWindow(
          charlie,
          expectedIndexes: allIndexes,
          incoming: true,
        );
        await expectBurstWindow(
          diana,
          expectedIndexes: dianaWindow,
          incoming: true,
        );

        final dianaMessages = await loadBurstMessages(diana);
        expect(
          dianaMessages.any(
            (message) =>
                message.id.startsWith('gp028-burst-') &&
                int.parse(message.id.substring('gp028-burst-'.length)) >=
                    removeDianaAt,
          ),
          isFalse,
          reason: 'Diana must not receive burst messages after removal cutoff',
        );
        expect(network.isSubscribed(groupId, diana.peerId), isFalse);

        alice.dispose();
        bob.dispose();
        charlie.dispose();
        diana.dispose();
      },
    );

    // ---------------------------------------------------------------
    // 7. Network counters track publish and delivery correctly
    // ---------------------------------------------------------------
    test('network counters track publish and delivery correctly', () async {
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

      final groupId = 'grp-counters';
      await admin.createGroup(groupId: groupId, name: 'Counter Group');
      await admin.addMember(groupId: groupId, invitee: bob);
      await admin.addMember(groupId: groupId, invitee: charlie);

      admin.start();
      bob.start();
      charlie.start();

      // Admin sends 2 messages
      await admin.sendGroupMessage(groupId: groupId, text: 'Admin msg 1');
      await admin.sendGroupMessage(groupId: groupId, text: 'Admin msg 2');

      // Bob sends 1 message
      await bob.sendGroupMessage(groupId: groupId, text: 'Bob msg 1');

      await pump();

      // 3 total publishes
      expect(network.publishCount, 3);

      // Delivery fan-out:
      //   Admin msg 1 → Bob + Charlie = 2 deliveries
      //   Admin msg 2 → Bob + Charlie = 2 deliveries
      //   Bob msg 1   → Admin + Charlie = 2 deliveries
      //   Total = 6 deliveries
      expect(network.totalDeliveries, 6);

      admin.dispose();
      bob.dispose();
      charlie.dispose();
    });
  });
}
