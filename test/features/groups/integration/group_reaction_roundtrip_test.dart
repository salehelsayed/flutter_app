import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/dissolve_group_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_reaction_use_case.dart';

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
