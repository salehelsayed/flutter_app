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
/// true`) with TestUser's narrow authored-reaction custody adapter and explicit
/// typed inbox-store delegate. Receiver-only reaction fakes remain incapable.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_reaction_use_case.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';

import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/test_user.dart';

/// FDC-18 Prerequisite P0: capture the flow events emitted while [action] runs.
Future<List<Map<String, dynamic>>> _captureFlowEvents(
  Future<void> Function() action,
) async {
  final events = <Map<String, dynamic>>[];
  debugSetFlowEventSink((payload) => events.add(payload));
  try {
    await action();
  } finally {
    debugSetFlowEventSink(null);
  }
  return events;
}

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
    'TC-343-06d required roundtrip uses an explicit custody-capable TestUser adapter',
    () async {
      // Subscribe to Bob's live reaction stream BEFORE anything is sent so the
      // round-trip delivery is observable end-to-end (not just via the repo).
      final bobReactionFuture =
          bob.reactionListener!.incomingReactionStream.first;

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
      expect(
        alice.reactionRepo,
        isA<OutgoingDirectReactionInboxCustodyRepository>(),
      );
      final authoredCustody =
          alice.reactionRepo! as OutgoingDirectReactionInboxCustodyRepository;
      expect(authoredCustody.supportsDirectReactionInboxCustody, isTrue);
      expect(
        await authoredCustody.loadDirectReactionInboxCustodyForEvent(
          recipientPeerId: bob.peerId,
          eventId: sentReaction.id,
        ),
        isNull,
        reason:
            'the explicit TestUser typed-inbox delegate accepted the exact '
            'event, so sender custody must converge after the live roundtrip',
      );

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
      final onTarget = await bob.reactionRepo!.getReactionsForMessage(
        targetMsg.id,
      );
      expect(
        onTarget.length,
        1,
        reason:
            'receiver should show exactly one reaction on the target message',
      );
      expect(onTarget.single.emoji, '🔥');
      expect(onTarget.single.senderPeerId, alice.peerId);
      expect(onTarget.single.messageId, targetMsg.id);
    },
  );

  test('FDC-18-06b first-ever offline reaction deposits concurrently and '
      'round-trips to exactly one reaction after drain', () async {
    // Observe Bob's receive end-to-end.
    final bobReactionFuture =
        bob.reactionListener!.incomingReactionStream.first;

    // Bob sends a message to Alice; the reaction targets THIS message (so the
    // target exists on Bob's side for the receive-time validation).
    final (sendResult, targetMsg) = await bob.sendMessage(
      alice.peerId,
      'React to me while Bob is offline',
    );
    expect(sendResult, SendChatMessageResult.success);
    expect(targetMsg, isNotNull);
    final targetId = targetMsg!.id;
    await Future.delayed(const Duration(milliseconds: 50));

    // Bob goes offline: Alice's live reaction send will miss, so the
    // concurrent durable inbox copy is the delivery tier.
    bob.setOnline(false);

    late SendReactionResult reactionResult;
    final events = await _captureFlowEvents(() async {
      final (r, _) = await alice.sendReaction(bob.peerId, targetId, '🔥');
      reactionResult = r;
    });

    // Offline peer's reaction still takes custody, via the CONCURRENT arm.
    expect(reactionResult, SendReactionResult.success);
    expect(
      events.map((e) => e['event']),
      contains('REACTION_SEND_CONCURRENT_INBOX_BEGIN'),
    );

    // Bob comes back and drains: the inbox copy replays to him.
    bob.setOnline(true);
    await bob.drainOfflineInbox();

    final received = await bobReactionFuture.timeout(
      const Duration(seconds: 2),
      onTimeout: () =>
          throw StateError('Bob never received the drained offline reaction'),
    );
    expect(received.emoji, '🔥');
    expect(received.messageId, targetId);

    // Exactly one reaction row after drain (byte-identical dedup => no dupes).
    final onTarget = await bob.reactionRepo!.getReactionsForMessage(targetId);
    expect(
      onTarget.length,
      1,
      reason: 'drained offline reaction must produce exactly one row',
    );
    expect(onTarget.single.emoji, '🔥');
    expect(onTarget.single.senderPeerId, alice.peerId);
  });
}
