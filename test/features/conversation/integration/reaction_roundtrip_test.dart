/// 124 Phase 8 — end-to-end coverage: 1:1 reaction round-trip.
///
/// Closes the `reaction_roundtrip` audit gap with ONE focused end-to-end test
/// proving the full send -> transport -> receive -> apply pipeline:
///
///   Alice `sendReaction` (real SendReactionUseCase, v2 encrypt + P2P send)
///     -> FakeP2PNetwork transport
///       -> Bob `IncomingMessageRouter` -> `ReactionListener`
///         -> `handleIncomingReaction` (decrypt + sender/target validation)
///           -> Bob's `ReactionRepository`
///
/// The assertion that matters for the gap: the RECEIVER (Bob) shows the
/// reaction on the TARGET message — both via the live `incomingReactionStream`
/// and via the persisted repo keyed on the target message id.
///
/// Harness: reuses the `TestUser` + `FakeP2PNetwork` family (`withReactions:
/// true`), mirroring the passing sibling `emoji_reaction_exchange_test.dart`.
/// No new fakes.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_reaction_use_case.dart';

import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/test_user.dart';

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

    // Mutual contacts (simulates QR exchange) so v2 encryption resolves a
    // recipient ML-KEM key and the receiver does not reject an unknown sender.
    alice.addContact(bob);
    bob.addContact(alice);

    // Router -> chat + reaction listeners running on both ends.
    alice.start();
    bob.start();
  });

  tearDown(() {
    alice.dispose();
    bob.dispose();
  });

  test(
    'reaction round-trip: Alice reacts, receiver Bob shows it on the target message',
    () async {
      // Subscribe to Bob's live reaction stream BEFORE anything is sent so the
      // round-trip delivery is observable end-to-end (not just via the repo).
      final bobReactionFuture = bob.reactionListener!.incomingReactionStream.first;

      // Bob sends a 1:1 message to Alice; Alice will react to THIS message.
      final (sendResult, targetMsg) = await bob.sendMessage(
        alice.peerId,
        'A message worth reacting to',
      );
      expect(sendResult, SendChatMessageResult.success);
      expect(targetMsg, isNotNull);

      // Let Alice's receiver pipeline persist the target message so the
      // receiver-side target-existence validation in handleIncomingReaction
      // (on Bob's side it already exists as a sent message) is realistic.
      await Future.delayed(const Duration(milliseconds: 50));

      // --- SEND: Alice reacts via the real SendReactionUseCase. ---
      final (reactionResult, sentReaction) = await alice.sendReaction(
        bob.peerId,
        targetMsg!.id,
        '🔥',
      );
      expect(reactionResult, SendReactionResult.success);
      expect(sentReaction, isNotNull);
      expect(sentReaction!.emoji, '🔥');
      expect(sentReaction.messageId, targetMsg.id);
      expect(sentReaction.senderPeerId, alice.peerId);

      // --- RECEIVE: the reaction arrives live on Bob's listener stream. ---
      final received = await bobReactionFuture.timeout(
        const Duration(seconds: 2),
        onTimeout: () =>
            throw StateError('Bob never received the round-tripped reaction'),
      );
      expect(received.emoji, '🔥');
      expect(received.messageId, targetMsg.id);
      expect(received.senderPeerId, alice.peerId);

      // --- APPLY: the receiver SHOWS the reaction ON THE TARGET MESSAGE. ---
      // Queried by the target message id — this is the gap-closing assertion.
      final onTarget =
          await bob.reactionRepo!.getReactionsForMessage(targetMsg.id);
      expect(
        onTarget.length,
        1,
        reason: 'receiver should show exactly one reaction on the target message',
      );
      expect(onTarget.single.emoji, '🔥');
      expect(onTarget.single.senderPeerId, alice.peerId);
      expect(onTarget.single.messageId, targetMsg.id);
    },
  );
}
