import 'dart:convert';

import 'package:flutter_app/features/groups/application/rejoin_group_topics_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/fake_group_pubsub_network.dart';
import '../../../shared/fakes/group_test_user.dart';

void main() {
  late FakeGroupPubSubNetwork network;

  setUp(() {
    network = FakeGroupPubSubNetwork();
  });

  /// Helper to let async listeners process delivered messages.
  Future<void> pump() => Future.delayed(const Duration(milliseconds: 50));

  group('Multi-user group messaging smoke tests', () {
    test(
      '3 users: basic fan-out — sender does not receive own message',
      () async {
        // -- arrange --
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

        const groupId = 'group-1';
        await alice.createGroup(groupId: groupId, name: 'Test Group');
        await alice.addMember(groupId: groupId, invitee: bob);

        // Existing members need the member_added system event to hydrate later
        // joins into their local member list before the row is fully proven.
        alice.start();
        bob.start();
        charlie.start();

        await alice.addMember(groupId: groupId, invitee: charlie);
        await alice.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await pump();

        Future<void> expectHydratedGroupState(
          GroupTestUser user,
          GroupRole expectedRole,
        ) async {
          final hydratedGroup = await user.groupRepo.getGroup(groupId);
          expect(hydratedGroup, isNotNull);
          expect(hydratedGroup!.id, groupId);
          expect(hydratedGroup.name, 'Test Group');
          expect(hydratedGroup.myRole, expectedRole);
          expect(hydratedGroup.createdBy, 'alice-peer');

          final members = await user.groupRepo.getMembers(groupId);
          expect(members.map((member) => member.peerId).toSet(), {
            'alice-peer',
            'bob-peer',
            'charlie-peer',
          });

          final rolesByPeerId = {
            for (final member in members) member.peerId: member.role,
          };
          expect(rolesByPeerId['alice-peer'], MemberRole.admin);
          expect(rolesByPeerId['bob-peer'], MemberRole.writer);
          expect(rolesByPeerId['charlie-peer'], MemberRole.writer);
        }

        await expectHydratedGroupState(alice, GroupRole.admin);
        await expectHydratedGroupState(bob, GroupRole.member);
        await expectHydratedGroupState(charlie, GroupRole.member);

        // -- act --
        await alice.sendGroupMessage(groupId: groupId, text: 'Hello group!');
        await pump();

        // -- assert --
        final bobMessages = await bob.loadGroupMessages(groupId);
        final bobRegular = bobMessages
            .where((message) => message.text == 'Hello group!')
            .toList();
        expect(bobRegular, hasLength(1));
        expect(bobRegular.first.isIncoming, isTrue);

        final charlieMessages = await charlie.loadGroupMessages(groupId);
        final charlieRegular = charlieMessages
            .where((message) => message.text == 'Hello group!')
            .toList();
        expect(charlieRegular, hasLength(1));
        expect(charlieRegular.first.isIncoming, isTrue);

        // Alice has 0 incoming (the network does not fan back to sender)
        final aliceIncoming = (await alice.loadGroupMessages(
          groupId,
        )).where((m) => m.isIncoming).toList();
        expect(aliceIncoming, isEmpty);

        // Alice has 1 total message (her own outgoing, saved locally by sendGroupMessage)
        final aliceAll = await alice.loadGroupMessages(groupId);
        expect(aliceAll, hasLength(1));
        expect(aliceAll.first.isIncoming, isFalse);

        // -- cleanup --
        alice.dispose();
        bob.dispose();
        charlie.dispose();
      },
    );

    test(
      '4 users: round-robin messaging — all receive from all others',
      () async {
        // -- arrange --
        final admin = GroupTestUser.create(
          peerId: 'admin-peer',
          username: 'Admin',
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
        final diana = GroupTestUser.create(
          peerId: 'diana-peer',
          username: 'Diana',
          network: network,
        );

        const groupId = 'group-roundrobin';
        await admin.createGroup(groupId: groupId, name: 'Round Robin');
        await admin.addMember(groupId: groupId, invitee: bob);
        await admin.addMember(groupId: groupId, invitee: charlie);
        await admin.addMember(groupId: groupId, invitee: diana);

        admin.start();
        bob.start();
        charlie.start();
        diana.start();

        // -- act: each user sends one message --
        await admin.sendGroupMessage(groupId: groupId, text: 'From Admin');
        await pump();
        await bob.sendGroupMessage(groupId: groupId, text: 'From Bob');
        await pump();
        await charlie.sendGroupMessage(groupId: groupId, text: 'From Charlie');
        await pump();
        await diana.sendGroupMessage(groupId: groupId, text: 'From Diana');
        await pump();

        // -- assert --
        // Each user should have 4 total messages: 1 outgoing + 3 incoming
        for (final user in [admin, bob, charlie, diana]) {
          final messages = await user.loadGroupMessages(groupId);
          expect(
            messages,
            hasLength(4),
            reason: '${user.username} should have 4 total messages',
          );

          final incoming = messages.where((m) => m.isIncoming).toList();
          final outgoing = messages.where((m) => !m.isIncoming).toList();
          expect(
            incoming,
            hasLength(3),
            reason: '${user.username} should have 3 incoming messages',
          );
          expect(
            outgoing,
            hasLength(1),
            reason: '${user.username} should have 1 outgoing message',
          );
        }

        // Verify specific texts for Admin's incoming
        final adminIncoming = (await admin.loadGroupMessages(
          groupId,
        )).where((m) => m.isIncoming).map((m) => m.text).toSet();
        expect(adminIncoming, {'From Bob', 'From Charlie', 'From Diana'});

        // Verify Bob's incoming
        final bobIncoming = (await bob.loadGroupMessages(
          groupId,
        )).where((m) => m.isIncoming).map((m) => m.text).toSet();
        expect(bobIncoming, {'From Admin', 'From Charlie', 'From Diana'});

        // -- cleanup --
        admin.dispose();
        bob.dispose();
        charlie.dispose();
        diana.dispose();
      },
    );

    test(
      'simultaneous sends fan out to the third member without loss',
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
        final charlie = GroupTestUser.create(
          peerId: 'charlie-peer',
          username: 'Charlie',
          network: network,
        );

        const groupId = 'group-simultaneous';
        await alice.createGroup(groupId: groupId, name: 'Simultaneous Group');
        await alice.addMember(groupId: groupId, invitee: bob);
        await alice.addMember(groupId: groupId, invitee: charlie);

        alice.start();
        bob.start();
        charlie.start();

        await Future.wait([
          alice.sendGroupMessage(groupId: groupId, text: 'From Alice'),
          bob.sendGroupMessage(groupId: groupId, text: 'From Bob'),
        ]);
        await pump();

        final charlieIncoming = (await charlie.loadGroupMessages(
          groupId,
        )).where((message) => message.isIncoming).toList();
        expect(charlieIncoming, hasLength(2));
        expect(charlieIncoming.map((message) => message.text).toSet(), {
          'From Alice',
          'From Bob',
        });
        expect(
          charlieIncoming.map((message) => message.id).toSet(),
          hasLength(2),
        );

        alice.dispose();
        bob.dispose();
        charlie.dispose();
      },
    );

    test(
      'same sender sequential messages stay ordered for both recipients',
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
        final charlie = GroupTestUser.create(
          peerId: 'charlie-peer',
          username: 'Charlie',
          network: network,
        );

        const groupId = 'group-same-sender-ordering';
        await alice.createGroup(groupId: groupId, name: 'Ordering Group');
        await alice.addMember(groupId: groupId, invitee: bob);
        await alice.addMember(groupId: groupId, invitee: charlie);

        alice.start();
        bob.start();
        charlie.start();

        await alice.sendGroupMessage(groupId: groupId, text: 'M1');
        await pump();

        // Keep timestamps distinct so the assertion matches the repo's
        // chronological ordering rule instead of same-millisecond luck.
        await Future<void>.delayed(const Duration(milliseconds: 2));

        await alice.sendGroupMessage(groupId: groupId, text: 'M2');
        await pump();

        Future<void> expectOrderedIncoming(GroupTestUser user) async {
          final incoming = (await user.loadGroupMessages(
            groupId,
          )).where((message) => message.isIncoming).toList();

          expect(
            incoming.map((message) => message.text).toList(),
            ['M1', 'M2'],
            reason:
                '${user.username} should display same-sender messages in chronological order',
          );
        }

        await expectOrderedIncoming(bob);
        await expectOrderedIncoming(charlie);

        alice.dispose();
        bob.dispose();
        charlie.dispose();
      },
    );

    test('message to unknown group is ignored', () async {
      // -- arrange --
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

      // Alice creates a group but does NOT add Bob
      const groupId = 'group-private';
      await alice.createGroup(groupId: groupId, name: 'Private Group');

      alice.start();
      bob.start();

      // -- act: manually inject a message with this groupId into Bob's stream --
      // Bob has no group in his repo, so handleIncomingGroupMessage should
      // return null and nothing should be saved.
      // We simulate this by subscribing Bob on the network (so he receives
      // the envelope) but NOT giving him the group in his repo.
      network.subscribe(groupId, bob.peerId);

      await alice.sendGroupMessage(groupId: groupId, text: 'Secret message');
      await pump();

      // -- assert --
      // Bob's listener received the envelope, but handleIncomingGroupMessage
      // returned null because Bob's groupRepo has no matching group.
      final bobMessages = await bob.loadGroupMessages(groupId);
      expect(
        bobMessages,
        isEmpty,
        reason: 'Bob should ignore messages to groups he does not know',
      );

      // Alice still has her outgoing
      final aliceMessages = await alice.loadGroupMessages(groupId);
      expect(aliceMessages, hasLength(1));

      // -- cleanup --
      network.unsubscribe(groupId, bob.peerId);
      alice.dispose();
      bob.dispose();
    });

    test('late joiner receives messages only after joining', () async {
      // -- arrange --
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

      const groupId = 'group-late';
      await alice.createGroup(groupId: groupId, name: 'Late Joiner Group');
      await alice.addMember(groupId: groupId, invitee: bob);

      alice.start();
      bob.start();
      charlie.start();

      // -- act: Alice sends BEFORE Charlie joins --
      await alice.sendGroupMessage(groupId: groupId, text: 'Before Charlie');
      await pump();

      // Now Alice adds Charlie
      await alice.addMember(groupId: groupId, invitee: charlie);

      // Alice sends AFTER Charlie joined
      await alice.sendGroupMessage(groupId: groupId, text: 'After Charlie');
      await pump();

      // -- assert --
      // Bob was a member the whole time — should have both incoming messages
      final bobMessages = (await bob.loadGroupMessages(
        groupId,
      )).where((m) => m.isIncoming).toList();
      expect(bobMessages, hasLength(2));
      expect(bobMessages.map((m) => m.text).toList(), [
        'Before Charlie',
        'After Charlie',
      ]);

      // Charlie joined late — should only have the message sent after joining
      final charlieMessages = (await charlie.loadGroupMessages(
        groupId,
      )).where((m) => m.isIncoming).toList();
      expect(charlieMessages, hasLength(1));
      expect(charlieMessages.first.text, 'After Charlie');

      // -- cleanup --
      alice.dispose();
      bob.dispose();
      charlie.dispose();
    });

    test('sender saves outgoing locally and others save incoming', () async {
      // -- arrange --
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

      const groupId = 'group-direction';
      await alice.createGroup(groupId: groupId, name: 'Direction Test');
      await alice.addMember(groupId: groupId, invitee: bob);

      alice.start();
      bob.start();

      // -- act --
      await alice.sendGroupMessage(groupId: groupId, text: 'Test');
      await pump();

      // -- assert --
      // Alice's message is outgoing with status 'sent'
      final aliceMessages = await alice.loadGroupMessages(groupId);
      expect(aliceMessages, hasLength(1));
      expect(aliceMessages.first.isIncoming, isFalse);
      expect(aliceMessages.first.status, 'sent');
      expect(aliceMessages.first.text, 'Test');
      expect(aliceMessages.first.senderPeerId, 'alice-peer');

      // Bob's message is incoming with status 'delivered'
      final bobMessages = await bob.loadGroupMessages(groupId);
      expect(bobMessages, hasLength(1));
      expect(bobMessages.first.isIncoming, isTrue);
      expect(bobMessages.first.status, 'delivered');
      expect(bobMessages.first.text, 'Test');
      expect(bobMessages.first.senderPeerId, 'alice-peer');
      expect(bobMessages.first.senderUsername, 'Alice');

      // -- cleanup --
      alice.dispose();
      bob.dispose();
    });

    test('quoted reply propagates to all recipients', () async {
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

      const groupId = 'group-quote';
      await alice.createGroup(groupId: groupId, name: 'Quote Group');
      await alice.addMember(groupId: groupId, invitee: bob);
      await alice.addMember(groupId: groupId, invitee: charlie);

      alice.start();
      bob.start();
      charlie.start();

      final parent = await alice.sendGroupMessage(
        groupId: groupId,
        text: 'Original group message',
      );
      await pump();

      await bob.sendGroupMessage(
        groupId: groupId,
        text: 'Quoted reply',
        quotedMessageId: parent!.id,
      );
      await pump();

      final aliceMessages = await alice.loadGroupMessages(groupId);
      final aliceReplies = aliceMessages
          .where((message) => message.text == 'Quoted reply')
          .toList();
      expect(aliceReplies, hasLength(1));
      final aliceReply = aliceReplies.single;
      expect(aliceReply.isIncoming, isTrue);
      expect(aliceReply.quotedMessageId, parent.id);

      final charlieMessages = await charlie.loadGroupMessages(groupId);
      final charlieReplies = charlieMessages
          .where((message) => message.text == 'Quoted reply')
          .toList();
      expect(charlieReplies, hasLength(1));
      final charlieReply = charlieReplies.single;
      expect(charlieReply.isIncoming, isTrue);
      expect(charlieReply.quotedMessageId, parent.id);

      final bobMessages = await bob.loadGroupMessages(groupId);
      final bobReplies = bobMessages
          .where((message) => message.text == 'Quoted reply')
          .toList();
      expect(bobReplies, hasLength(1));
      final bobReply = bobReplies.single;
      expect(bobReply.isIncoming, isFalse);
      expect(bobReply.quotedMessageId, parent.id);

      alice.dispose();
      bob.dispose();
      charlie.dispose();
    });

    test('message is received after app restart with rejoin', () async {
      // -- arrange --
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

      const groupId = 'group-post-restart';
      await alice.createGroup(groupId: groupId, name: 'Post Restart');
      await alice.addMember(groupId: groupId, invitee: bob);

      // Store a key for Bob (simulates invite acceptance)
      await bob.groupRepo.saveKey(
        GroupKeyInfo(
          groupId: groupId,
          keyGeneration: 1,
          encryptedKey: 'test-key',
          createdAt: DateTime.now().toUtc(),
        ),
      );

      alice.start();
      bob.start();

      // Pre-restart: send and verify
      await alice.sendGroupMessage(groupId: groupId, text: 'Before restart');
      await pump();
      expect(
        (await bob.loadGroupMessages(
          groupId,
        )).where((m) => m.isIncoming).length,
        1,
      );

      // -- simulate restart: unsubscribe Bob from network --
      network.unsubscribe(groupId, bob.peerId);

      // -- act: rejoin (calls bridge, re-subscribe on fake network) --
      await rejoinGroupTopics(bridge: bob.bridge, groupRepo: bob.groupRepo);

      // Verify bridge got the correct join command
      final joinCmds = bob.bridge.sentMessages
          .map((m) => jsonDecode(m) as Map<String, dynamic>)
          .where((m) => m['cmd'] == 'group:join')
          .toList();
      expect(joinCmds, hasLength(1));

      final payload = joinCmds.first['payload'] as Map<String, dynamic>;
      expect(payload['groupId'], groupId);
      expect(payload['groupKey'], 'test-key');

      // Verify config contains member publicKeys (critical for Go validator)
      final config = payload['groupConfig'] as Map<String, dynamic>;
      final members = config['members'] as List<dynamic>;
      for (final m in members) {
        expect(
          (m as Map)['publicKey'],
          isNotNull,
          reason: 'publicKey required for Go validator',
        );
      }

      // Re-subscribe on fake network (Go does this in production)
      network.subscribe(groupId, bob.peerId);

      // -- assert: Bob can receive messages after restart --
      await alice.sendGroupMessage(groupId: groupId, text: 'After restart');
      await pump();

      final bobIncoming = (await bob.loadGroupMessages(
        groupId,
      )).where((m) => m.isIncoming).toList();
      expect(bobIncoming, hasLength(2));
      expect(bobIncoming.map((m) => m.text).toSet(), {
        'Before restart',
        'After restart',
      });
      expect(await bob.msgRepo.getMessageCount(groupId), 2);
      expect(await bob.msgRepo.getUnreadCount(groupId), 2);

      final threadSummary = await bob.msgRepo.getGroupThreadSummary(groupId);
      expect(threadSummary.unreadCount, 2);
      expect(threadSummary.latestMessage?.text, 'After restart');

      // -- cleanup --
      alice.dispose();
      bob.dispose();
    });
  });
}
