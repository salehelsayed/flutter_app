import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/dissolve_group_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_reaction_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';

import '../../conversation/domain/repositories/fake_reaction_repository.dart';
import '../../../shared/fakes/fake_group_pubsub_network.dart';
import '../../../shared/fakes/group_test_user.dart';

void main() {
  late FakeGroupPubSubNetwork network;

  setUp(() {
    network = FakeGroupPubSubNetwork();
  });

  Future<void> pump([Duration d = const Duration(milliseconds: 50)]) =>
      Future.delayed(d);

  test(
    'chat-group reaction roundtrip reaches the original sender through the live listener stream',
    () async {
      final admin = GroupTestUser.create(
        peerId: 'peer-admin',
        username: 'Admin',
        network: network,
        reactionRepo: FakeReactionRepository(),
      );
      final bob = GroupTestUser.create(
        peerId: 'peer-bob',
        username: 'Bob',
        network: network,
        reactionRepo: FakeReactionRepository(),
      );
      addTearDown(() {
        admin.dispose();
        bob.dispose();
      });

      const groupId = 'group-chat-reaction-roundtrip';
      final group = await admin.createGroup(groupId: groupId, name: 'Chat');
      await admin.addMember(groupId: groupId, invitee: bob);
      for (final user in [admin, bob]) {
        await user.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'group-key-1',
            createdAt: DateTime.now().toUtc(),
          ),
        );
      }

      admin.start();
      bob.start();

      final (sendResult, sentMessage) = await admin.sendGroupMessageViaBridge(
        groupId: group.id,
        text: 'hello group',
      );
      expect(sendResult, SendGroupMessageResult.success);
      expect(sentMessage, isNotNull);

      await pump();

      final bobMessages = await bob.loadGroupMessages(group.id);
      expect(bobMessages, hasLength(1));
      final received = bobMessages.single;
      expect(received.id, sentMessage!.id);
      expect(received.text, 'hello group');
      expect(received.isIncoming, isTrue);

      final reactionChangeFuture =
          admin.groupMessageListener.groupReactionChangeStream.first;

      final (reactionResult, reaction) = await bob.sendGroupReactionViaBridge(
        groupId: group.id,
        messageId: received.id,
        emoji: '🔥',
      );
      expect(reactionResult, SendGroupReactionResult.success);
      expect(reaction, isNotNull);

      final change = await reactionChangeFuture;
      expect(change.messageId, received.id);
      expect(change.senderPeerId, bob.peerId);
      expect(change.reaction, isNotNull);
      expect(change.reaction!.emoji, '🔥');

      final adminReactions = await admin.reactionRepo!.getReactionsForMessage(
        received.id,
      );
      expect(adminReactions, hasLength(1));
      expect(adminReactions.single.emoji, '🔥');
      expect(adminReactions.single.senderPeerId, bob.peerId);

      expect(network.reactionPublishCallCount, 1);
      expect(network.totalReactionDeliveries, 1);
    },
  );

  test(
    'PL-009 media-free active member reaction reaches Alice and Charlie exactly once',
    () async {
      final alice = GroupTestUser.create(
        peerId: 'peer-alice',
        username: 'Alice',
        network: network,
        reactionRepo: FakeReactionRepository(),
      );
      final bob = GroupTestUser.create(
        peerId: 'peer-bob',
        username: 'Bob',
        network: network,
        reactionRepo: FakeReactionRepository(),
      );
      final charlie = GroupTestUser.create(
        peerId: 'peer-charlie',
        username: 'Charlie',
        network: network,
        reactionRepo: FakeReactionRepository(),
      );
      addTearDown(() {
        alice.dispose();
        bob.dispose();
        charlie.dispose();
      });

      const groupId = 'group-pl009-reaction-roundtrip';
      final group = await alice.createGroup(groupId: groupId, name: 'Chat');
      await alice.addMember(groupId: groupId, invitee: bob);
      await alice.addMember(groupId: groupId, invitee: charlie);
      for (final user in [alice, bob, charlie]) {
        await user.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'group-key-1',
            createdAt: DateTime.now().toUtc(),
          ),
        );
      }

      alice.start();
      bob.start();
      charlie.start();

      final (sendResult, sentMessage) = await alice.sendGroupMessageViaBridge(
        groupId: group.id,
        text: 'PL-009 target message',
      );
      expect(sendResult, SendGroupMessageResult.success);
      expect(sentMessage, isNotNull);

      await pump();

      final bobMessages = await bob.loadGroupMessages(group.id);
      final charlieMessages = await charlie.loadGroupMessages(group.id);
      expect(bobMessages, hasLength(1));
      expect(charlieMessages, hasLength(1));
      expect(bobMessages.single.id, sentMessage!.id);
      expect(charlieMessages.single.id, sentMessage.id);

      final aliceReactionFuture =
          alice.groupMessageListener.groupReactionChangeStream.first;
      final charlieReactionFuture =
          charlie.groupMessageListener.groupReactionChangeStream.first;

      final (reactionResult, reaction) = await bob.sendGroupReactionViaBridge(
        groupId: group.id,
        messageId: bobMessages.single.id,
        emoji: '🔥',
      );
      expect(reactionResult, SendGroupReactionResult.success);
      expect(reaction, isNotNull);

      final aliceChange = await aliceReactionFuture;
      final charlieChange = await charlieReactionFuture;
      expect(aliceChange.messageId, sentMessage.id);
      expect(charlieChange.messageId, sentMessage.id);
      expect(aliceChange.senderPeerId, bob.peerId);
      expect(charlieChange.senderPeerId, bob.peerId);

      for (final user in [alice, bob, charlie]) {
        final reactions = await user.reactionRepo!.getReactionsForMessage(
          sentMessage.id,
        );
        expect(reactions, hasLength(1), reason: user.peerId);
        expect(reactions.single.senderPeerId, bob.peerId);
        expect(reactions.single.emoji, '🔥');
      }

      expect(network.reactionPublishCallCount, 1);
      expect(network.totalReactionDeliveries, 2);
    },
  );

  test(
    'PL-010 removed member reaction is ignored by Alice and Bob without visible mutation',
    () async {
      final alice = GroupTestUser.create(
        peerId: 'peer-alice',
        username: 'Alice',
        network: network,
        reactionRepo: FakeReactionRepository(),
      );
      final bob = GroupTestUser.create(
        peerId: 'peer-bob',
        username: 'Bob',
        network: network,
        reactionRepo: FakeReactionRepository(),
      );
      final charlie = GroupTestUser.create(
        peerId: 'peer-charlie',
        username: 'Charlie',
        network: network,
        reactionRepo: FakeReactionRepository(),
      );
      addTearDown(() {
        alice.dispose();
        bob.dispose();
        charlie.dispose();
      });

      const groupId = 'group-pl010-removed-reaction';
      final group = await alice.createGroup(groupId: groupId, name: 'Chat');
      await alice.addMember(groupId: groupId, invitee: bob);
      await alice.addMember(groupId: groupId, invitee: charlie);
      for (final user in [alice, bob, charlie]) {
        await user.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'group-key-1',
            createdAt: DateTime.now().toUtc(),
          ),
        );
      }

      alice.start();
      bob.start();
      charlie.start();

      final (sendResult, sentMessage) = await alice.sendGroupMessageViaBridge(
        groupId: group.id,
        text: 'PL-010 target message',
      );
      expect(sendResult, SendGroupMessageResult.success);
      expect(sentMessage, isNotNull);

      await pump();
      final charlieMessages = await charlie.loadGroupMessages(group.id);
      expect(charlieMessages, hasLength(1));
      expect(charlieMessages.single.id, sentMessage!.id);

      charlie.groupMessageListener.stop();
      await alice.removeMember(
        groupId: group.id,
        memberPeerId: charlie.peerId,
        memberUsername: charlie.username,
      );
      await pump();
      expect(await alice.groupRepo.getMember(group.id, charlie.peerId), isNull);
      expect(await bob.groupRepo.getMember(group.id, charlie.peerId), isNull);

      final (reactionResult, reaction) = await charlie
          .sendGroupReactionViaBridge(
            groupId: group.id,
            messageId: sentMessage.id,
            emoji: '🔥',
          );
      expect(reactionResult, SendGroupReactionResult.success);
      expect(reaction, isNotNull);

      await pump(const Duration(milliseconds: 150));
      expect(
        await alice.reactionRepo!.getReactionsForMessage(sentMessage.id),
        isEmpty,
      );
      expect(
        await bob.reactionRepo!.getReactionsForMessage(sentMessage.id),
        isEmpty,
      );
      expect(
        await charlie.reactionRepo!.getReactionsForMessage(sentMessage.id),
        hasLength(1),
      );
      expect(network.reactionPublishCallCount, 1);
      expect(network.totalReactionDeliveries, 2);
    },
  );

  test(
    'PL-011 re-added member reaction reaches Alice and Bob exactly once',
    () async {
      final alice = GroupTestUser.create(
        peerId: 'peer-alice',
        username: 'Alice',
        network: network,
        reactionRepo: FakeReactionRepository(),
      );
      final bob = GroupTestUser.create(
        peerId: 'peer-bob',
        username: 'Bob',
        network: network,
        reactionRepo: FakeReactionRepository(),
      );
      final charlie = GroupTestUser.create(
        peerId: 'peer-charlie',
        username: 'Charlie',
        network: network,
        reactionRepo: FakeReactionRepository(),
      );
      addTearDown(() {
        alice.dispose();
        bob.dispose();
        charlie.dispose();
      });

      const groupId = 'group-pl011-readd-reaction';
      final group = await alice.createGroup(groupId: groupId, name: 'Chat');
      await alice.addMember(groupId: groupId, invitee: bob);
      await alice.addMember(groupId: groupId, invitee: charlie);
      for (final user in [alice, bob, charlie]) {
        await user.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'group-key-1',
            createdAt: DateTime.now().toUtc(),
          ),
        );
      }

      alice.start();
      bob.start();
      charlie.start();

      await alice.removeMember(
        groupId: group.id,
        memberPeerId: charlie.peerId,
        memberUsername: charlie.username,
      );
      await pump(const Duration(milliseconds: 150));
      expect(await alice.groupRepo.getMember(group.id, charlie.peerId), isNull);
      expect(await bob.groupRepo.getMember(group.id, charlie.peerId), isNull);

      await alice.addMember(groupId: group.id, invitee: charlie);
      await alice.broadcastMemberAdded(groupId: group.id, newMember: charlie);
      for (final user in [alice, bob, charlie]) {
        await user.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 2,
            encryptedKey: 'group-key-2',
            createdAt: DateTime.now().toUtc(),
          ),
        );
      }
      await pump(const Duration(milliseconds: 150));
      for (final user in [alice, bob, charlie]) {
        final member = await user.groupRepo.getMember(group.id, charlie.peerId);
        expect(member, isNotNull, reason: user.peerId);
        final latestKey = await user.groupRepo.getLatestKey(group.id);
        expect(latestKey?.keyGeneration, 2, reason: user.peerId);
      }

      final (sendResult, sentMessage) = await alice.sendGroupMessageViaBridge(
        groupId: group.id,
        text: 'PL-011 post-readd target message',
      );
      expect(sendResult, SendGroupMessageResult.success);
      expect(sentMessage, isNotNull);
      expect(sentMessage!.keyGeneration, 2);

      await pump();
      final bobMessages = await bob.loadGroupMessages(group.id);
      final charlieMessages = await charlie.loadGroupMessages(group.id);
      final bobTarget = bobMessages.singleWhere(
        (message) => message.id == sentMessage.id,
      );
      final charlieTarget = charlieMessages.singleWhere(
        (message) => message.id == sentMessage.id,
      );
      expect(bobTarget.keyGeneration, 2);
      expect(charlieTarget.keyGeneration, 2);

      final aliceReactionFuture =
          alice.groupMessageListener.groupReactionChangeStream.first;
      final bobReactionFuture =
          bob.groupMessageListener.groupReactionChangeStream.first;

      final (reactionResult, reaction) = await charlie
          .sendGroupReactionViaBridge(
            groupId: group.id,
            messageId: charlieTarget.id,
            emoji: '✅',
          );
      expect(reactionResult, SendGroupReactionResult.success);
      expect(reaction, isNotNull);

      final aliceChange = await aliceReactionFuture;
      final bobChange = await bobReactionFuture;
      expect(aliceChange.messageId, sentMessage.id);
      expect(bobChange.messageId, sentMessage.id);
      expect(aliceChange.senderPeerId, charlie.peerId);
      expect(bobChange.senderPeerId, charlie.peerId);
      expect(aliceChange.reaction?.emoji, '✅');
      expect(bobChange.reaction?.emoji, '✅');

      for (final user in [alice, bob, charlie]) {
        final reactions = await user.reactionRepo!.getReactionsForMessage(
          sentMessage.id,
        );
        expect(reactions, hasLength(1), reason: user.peerId);
        expect(reactions.single.senderPeerId, charlie.peerId);
        expect(reactions.single.emoji, '✅');
      }

      expect(network.reactionPublishCallCount, 1);
      expect(network.totalReactionDeliveries, 2);
    },
  );

  test(
    'dissolved chat group blocks later reaction send and does not roundtrip',
    () async {
      final admin = GroupTestUser.create(
        peerId: 'peer-admin',
        username: 'Admin',
        network: network,
        reactionRepo: FakeReactionRepository(),
      );
      final bob = GroupTestUser.create(
        peerId: 'peer-bob',
        username: 'Bob',
        network: network,
        reactionRepo: FakeReactionRepository(),
      );
      addTearDown(() {
        admin.dispose();
        bob.dispose();
      });

      const groupId = 'group-chat-reaction-dissolved';
      final group = await admin.createGroup(groupId: groupId, name: 'Chat');
      await admin.addMember(groupId: groupId, invitee: bob);
      for (final user in [admin, bob]) {
        await user.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'group-key-1',
            createdAt: DateTime.now().toUtc(),
          ),
        );
      }

      admin.start();
      bob.start();

      final (sendResult, sentMessage) = await admin.sendGroupMessageViaBridge(
        groupId: group.id,
        text: 'ended thread',
      );
      expect(sendResult, SendGroupMessageResult.success);
      expect(sentMessage, isNotNull);

      await pump();

      final (dissolveResult, dissolvedGroup) = await admin
          .dissolveGroupViaBridge(groupId: group.id);
      expect(
        dissolveResult,
        anyOf(DissolveGroupResult.success, DissolveGroupResult.bridgeError),
      );
      expect(dissolvedGroup, isNotNull);

      await pump();

      final bobGroup = await bob.groupRepo.getGroup(group.id);
      expect(bobGroup, isNotNull);
      expect(bobGroup!.isDissolved, isTrue);

      final (reactionResult, reaction) = await bob.sendGroupReactionViaBridge(
        groupId: group.id,
        messageId: sentMessage!.id,
        emoji: '🔥',
      );
      expect(reactionResult, SendGroupReactionResult.groupDissolved);
      expect(reaction, isNull);
      expect(
        await bob.reactionRepo!.getReactionsForMessage(sentMessage.id),
        isEmpty,
      );
      expect(
        await admin.reactionRepo!.getReactionsForMessage(sentMessage.id),
        isEmpty,
      );
      expect(network.reactionPublishCallCount, 0);
      expect(network.totalReactionDeliveries, 0);
    },
  );
}
