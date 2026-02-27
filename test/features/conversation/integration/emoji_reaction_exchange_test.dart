/// Integration test: Two users exchange emoji reactions.
///
/// Simulates full bidirectional reaction exchange:
///   Alice reacts to Bob's message → P2P network → Bob receives & persists
///   Both users toggle, replace, and co-react on the same messages.
///
/// This test wires up the full stack per user:
///   FakeP2PService → IncomingMessageRouter → ReactionListener → ReactionRepository
///   (chat messages also routed through IncomingMessageRouter → ChatMessageListener)

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_reaction_use_case.dart';
import 'package:flutter_app/features/conversation/application/remove_reaction_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';

import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/test_user.dart';

// ─── Tests ──────────────────────────────────────────────────────────
void main() {
  late FakeP2PNetwork network;
  late TestUser alice;
  late TestUser bob;

  setUp(() {
    network = FakeP2PNetwork();

    alice = TestUser.create(
      peerId: '12D3KooWAlicePeerId00000000001',
      username: 'Alice',
      network: network,
      withReactions: true,
    );

    bob = TestUser.create(
      peerId: '12D3KooWBobPeerIdxxx00000000002',
      username: 'Bob',
      network: network,
      withReactions: true,
    );

    // Both users add each other as contacts (simulating QR exchange)
    alice.addContact(bob);
    bob.addContact(alice);

    // Start listeners (router → chat listener + reaction listener)
    alice.start();
    bob.start();
  });

  tearDown(() {
    alice.dispose();
    bob.dispose();
  });

  group('Two-user emoji reaction exchange', () {
    test('Alice reacts to Bob\'s message, Bob sees it', () async {
      // Subscribe to Bob's incoming reaction stream before sending
      final bobReactionFuture =
          bob.reactionListener!.incomingReactionStream.first;

      // Bob sends a message to Alice
      final (sendResult, sentMsg) = await bob.sendMessage(
        alice.peerId,
        'Hello Alice!',
      );
      expect(sendResult, SendChatMessageResult.success);
      expect(sentMsg, isNotNull);

      // Wait for Alice to receive the message
      await Future.delayed(const Duration(milliseconds: 50));

      // Alice reacts with 👍 to the message
      final (reactionResult, reaction) = await alice.sendReaction(
        bob.peerId,
        sentMsg!.id,
        '👍',
      );

      expect(reactionResult, SendReactionResult.success);
      expect(reaction, isNotNull);
      expect(reaction!.emoji, '👍');
      expect(reaction.messageId, sentMsg.id);
      expect(reaction.senderPeerId, alice.peerId);

      // Wait for Bob's reaction listener to process
      final received = await bobReactionFuture.timeout(
        const Duration(seconds: 2),
        onTimeout: () =>
            throw StateError('Bob never received the reaction'),
      );

      expect(received.emoji, '👍');
      expect(received.messageId, sentMsg.id);
      expect(received.senderPeerId, alice.peerId);

      // Verify Bob's repo has the reaction persisted
      final bobReactions = await bob.reactionRepo!.getReactionsForMessage(
        sentMsg.id,
      );
      expect(bobReactions.length, 1);
      expect(bobReactions.first.emoji, '👍');
      expect(bobReactions.first.senderPeerId, alice.peerId);

      // Verify Alice's repo also has the reaction (persisted locally on send)
      final aliceReactions = await alice.reactionRepo!.getReactionsForMessage(
        sentMsg.id,
      );
      expect(aliceReactions.length, 1);
      expect(aliceReactions.first.emoji, '👍');
    });

    test('Toggle reaction: add then remove', () async {
      // Bob sends a message to Alice
      final (_, sentMsg) = await bob.sendMessage(
        alice.peerId,
        'Toggle this!',
      );
      await Future.delayed(const Duration(milliseconds: 50));

      // Alice adds reaction 👍
      final (addResult, _) = await alice.sendReaction(
        bob.peerId,
        sentMsg!.id,
        '👍',
      );
      expect(addResult, SendReactionResult.success);

      // Wait for Bob to receive the add
      await Future.delayed(const Duration(milliseconds: 50));

      // Verify Bob has the reaction
      var bobReactions = await bob.reactionRepo!.getReactionsForMessage(
        sentMsg.id,
      );
      expect(bobReactions.length, 1);
      expect(bobReactions.first.emoji, '👍');

      // Alice removes the reaction
      final removeResult = await alice.removeReaction(
        bob.peerId,
        sentMsg.id,
        '👍',
      );
      expect(removeResult, RemoveReactionResult.success);

      // Wait for Bob to receive the remove
      await Future.delayed(const Duration(milliseconds: 50));

      // Verify Bob no longer has the reaction
      bobReactions = await bob.reactionRepo!.getReactionsForMessage(
        sentMsg.id,
      );
      expect(bobReactions.length, 0);

      // Alice's local store also removed
      final aliceReactions = await alice.reactionRepo!.getReactionsForMessage(
        sentMsg.id,
      );
      expect(aliceReactions.length, 0);
    });

    test('Replace reaction: 👍 → ❤️', () async {
      // Bob sends a message to Alice
      final (_, sentMsg) = await bob.sendMessage(
        alice.peerId,
        'React to this!',
      );
      await Future.delayed(const Duration(milliseconds: 50));

      // Alice reacts with 👍
      final (r1, _) = await alice.sendReaction(
        bob.peerId,
        sentMsg!.id,
        '👍',
      );
      expect(r1, SendReactionResult.success);
      await Future.delayed(const Duration(milliseconds: 50));

      // Alice changes to ❤️ (upserts due to same message+sender)
      final (r2, reaction2) = await alice.sendReaction(
        bob.peerId,
        sentMsg.id,
        '❤️',
      );
      expect(r2, SendReactionResult.success);
      expect(reaction2!.emoji, '❤️');
      await Future.delayed(const Duration(milliseconds: 50));

      // Bob should have only ❤️ (upsert replaced 👍)
      final bobReactions = await bob.reactionRepo!.getReactionsForMessage(
        sentMsg.id,
      );
      expect(bobReactions.length, 1);
      expect(bobReactions.first.emoji, '❤️');
      expect(bobReactions.first.senderPeerId, alice.peerId);

      // Alice should have only ❤️ locally
      final aliceReactions = await alice.reactionRepo!.getReactionsForMessage(
        sentMsg.id,
      );
      expect(aliceReactions.length, 1);
      expect(aliceReactions.first.emoji, '❤️');
    });

    test('Both users react to the same message', () async {
      // Alice sends a message to Bob
      final (_, sentMsg) = await alice.sendMessage(
        bob.peerId,
        'Look at this!',
      );
      await Future.delayed(const Duration(milliseconds: 50));

      // Alice reacts to her own sent message with 😂
      final (r1, _) = await alice.sendReaction(
        bob.peerId,
        sentMsg!.id,
        '😂',
      );
      expect(r1, SendReactionResult.success);
      await Future.delayed(const Duration(milliseconds: 50));

      // Bob reacts to the same message with ❤️
      final (r2, _) = await bob.sendReaction(
        alice.peerId,
        sentMsg.id,
        '❤️',
      );
      expect(r2, SendReactionResult.success);
      await Future.delayed(const Duration(milliseconds: 50));

      // Alice should see both reactions:
      //   her own 😂 (persisted locally on send)
      //   Bob's ❤️ (received via P2P)
      final aliceReactions = await alice.reactionRepo!.getReactionsForMessage(
        sentMsg.id,
      );
      expect(aliceReactions.length, 2);
      final aliceEmojis = aliceReactions.map((r) => r.emoji).toSet();
      expect(aliceEmojis, containsAll(['😂', '❤️']));

      // Bob should also see both reactions:
      //   Alice's 😂 (received via P2P)
      //   his own ❤️ (persisted locally on send)
      final bobReactions = await bob.reactionRepo!.getReactionsForMessage(
        sentMsg.id,
      );
      expect(bobReactions.length, 2);
      final bobEmojis = bobReactions.map((r) => r.emoji).toSet();
      expect(bobEmojis, containsAll(['😂', '❤️']));
    });

    test('Reactions from unknown senders are rejected', () async {
      // Create a stranger not in Bob's contacts
      final stranger = TestUser.create(
        peerId: '12D3KooWStranger00000000000003',
        username: 'Stranger',
        network: network,
        withReactions: true,
      );
      // Stranger has Bob as contact (so V2 encryption works)
      // but Bob does NOT have stranger
      stranger.addContact(bob);
      stranger.start();

      // Bob sends a message (stranger somehow knows the ID)
      final (_, sentMsg) = await bob.sendMessage(
        alice.peerId,
        'Hello!',
      );
      await Future.delayed(const Duration(milliseconds: 50));

      // Stranger tries to react
      final (result, _) = await stranger.sendReaction(
        bob.peerId,
        sentMsg!.id,
        '👍',
      );
      // Sender side succeeds (fire-and-forget)
      expect(result, SendReactionResult.success);

      await Future.delayed(const Duration(milliseconds: 100));

      // Bob should have NO reactions (stranger is not a contact)
      final bobReactions = await bob.reactionRepo!.getReactionsForMessage(
        sentMsg.id,
      );
      expect(bobReactions.length, 0);

      stranger.dispose();
    });

    test('Chat messages still work with reaction routing enabled', () async {
      // Verify that withReactions: true doesn't break normal chat
      final bobReceived = bob.chatListener.incomingMessageStream.first;

      final (result, sentMsg) = await alice.sendMessage(
        bob.peerId,
        'Hello Bob via router!',
      );

      expect(result, SendChatMessageResult.success);
      expect(sentMsg!.text, 'Hello Bob via router!');

      final received = await bobReceived.timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw StateError('Bob never received the message'),
      );

      expect(received.text, 'Hello Bob via router!');
      expect(received.isIncoming, true);
      expect(received.senderPeerId, alice.peerId);
    });
  });
}
