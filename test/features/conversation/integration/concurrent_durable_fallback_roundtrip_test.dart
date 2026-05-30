/// NET-REL-05 — I1: concurrent durable fallback (P1/P4) offline round-trip
/// integration tests, built on the shared integration fake
/// (`test/shared/fakes/fake_p2p_service_integration.dart`) — the ONLY fake with
/// the online/offline + delay knobs and a real `storeInInboxCallCount` (via
/// [FakeP2PNetwork]) needed to prove the durable-fallback contract.
///
/// I1 (happy, offline round-trip): a low-confidence send (the peer's prior
/// outgoing message terminally landed in the inbox within the 30s window, and
/// the peer is offline now) fires the inbox store CONCURRENTLY with the live
/// race. While the peer is offline the durable copy takes custody, the row
/// settles `delivered`/`inbox`, and a later `drainOfflineInbox` surfaces the
/// message on the recipient EXACTLY ONCE.
///
/// NEGATIVE CONTROLS (guard the false positives the tracking doc names):
///  - N-online: a high-confidence send to an ONLINE recipient is delivered LIVE
///    and NEVER touches the inbox (`storeInInboxCallCount == 0`) — proves the
///    durable copy is not fired on every send (P4 is low-confidence-only).
///  - N-no-double-write: a low-confidence send whose live race SUCCEEDS keeps
///    the LIVE transport label and fires the inbox store at most ONCE — the
///    concurrent copy is reconciled, never a second sequential `storeInInbox`
///    (R1 one-message-two-writes guard).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';

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
    );
    bob = TestUser.create(
      peerId: '12D3KooWBobPeerIdxxx00000000002',
      username: 'Bob',
      network: network,
    );
    alice.addContact(bob);
    bob.addContact(alice);
    alice.start();
    bob.start();
  });

  tearDown(() {
    alice.dispose();
    bob.dispose();
  });

  group('NET-REL-05 I1 — concurrent durable fallback round-trip', () {
    test(
      'low-confidence send to offline peer takes inbox custody and surfaces '
      'exactly once on drain',
      () async {
        // Prior attempt: peer offline → message terminally lands in the inbox.
        // This seeds the "recently offline" signal that makes the NEXT send
        // low-confidence.
        bob.setOnline(false);
        final (firstResult, firstMsg) = await alice.sendMessage(
          bob.peerId,
          'Recent prior (offline)',
        );
        expect(firstResult, SendChatMessageResult.success);
        expect(firstMsg!.transport, 'inbox');
        // Sequential tail stored once for the first (high-confidence) send.
        expect(network.storeInInboxCallCount, 1);

        // Second send while still offline: now LOW confidence (prior outgoing
        // message transport == 'inbox' within 30s, peer not connected/local).
        // The concurrent inbox copy is fired in parallel; the live race fails
        // (peer offline) and the durable copy takes custody.
        final (secondResult, secondMsg) = await alice.sendMessage(
          bob.peerId,
          'Low-confidence durable',
        );
        expect(secondResult, SendChatMessageResult.success);
        expect(secondMsg!.status, 'delivered');
        expect(secondMsg.transport, 'inbox');

        // Both messages durably stored; the second send must NOT have produced
        // two inbox writes for one message (concurrent copy reconciled, no
        // redundant sequential store).
        expect(
          network.storeInInboxCallCount,
          2,
          reason: 'one inbox write per message; no double-write on the '
              'concurrent low-confidence send',
        );
        expect(network.inboxCount(bob.peerId), 2);

        // Recipient comes back and drains: each message surfaces exactly once.
        final received = <String>[];
        final sub = bob.chatListener.incomingMessageStream.listen(
          (m) => received.add(m.text),
        );
        bob.setOnline(true);
        final drained = await bob.drainOfflineInbox();
        expect(drained, 2);
        await Future.delayed(const Duration(milliseconds: 100));

        final bobConvo = await bob.loadConversationWith(alice.peerId);
        expect(bobConvo, hasLength(2));
        expect(
          bobConvo.map((m) => m.text).toSet(),
          {'Recent prior (offline)', 'Low-confidence durable'},
        );
        // No duplicate surfaced (receive-side messageId dedup holds).
        expect(received.length, 2);
        await sub.cancel();
      },
    );

    test(
      'NEGATIVE CONTROL (N-online): high-confidence send to online recipient '
      'delivers live and never touches the inbox',
      () async {
        // Peer is online; no prior failure → high confidence. Single live path.
        final (result, msg) = await alice.sendMessage(
          bob.peerId,
          'Live and single-path',
        );
        expect(result, SendChatMessageResult.success);
        expect(msg!.status, 'delivered');
        expect(
          msg.transport,
          isNot('inbox'),
          reason: 'live transport wins; durable copy not used',
        );
        expect(
          network.storeInInboxCallCount,
          0,
          reason: 'a high-confidence send is strictly single-path — the '
              'concurrent durable copy must NOT fire on every send',
        );
      },
    );

    test(
      'NEGATIVE CONTROL (N-no-double-write): low-confidence send whose live '
      'race SUCCEEDS keeps the live label and writes the inbox at most once',
      () async {
        // Seed a recent terminal inbox failure so the next send is low-confidence.
        bob.setOnline(false);
        final (priorResult, priorMsg) = await alice.sendMessage(
          bob.peerId,
          'Prior offline',
        );
        expect(priorResult, SendChatMessageResult.success);
        expect(priorMsg!.transport, 'inbox');
        expect(network.storeInInboxCallCount, 1);

        // Peer is back online: the live race will SUCCEED. The send is still
        // low-confidence (prior inbox within 30s), so the concurrent copy is
        // fired, but the live success must own the transport label and the
        // concurrent copy must be reconciled (no second sequential store).
        bob.setOnline(true);
        final (result, msg) = await alice.sendMessage(
          bob.peerId,
          'Now reachable live',
        );
        expect(result, SendChatMessageResult.success);
        expect(msg!.status, 'delivered');
        expect(
          msg.transport,
          isNot('inbox'),
          reason: 'live race won; live transport label retained',
        );
        // The concurrent fallback copy may fire (low-confidence), but never a
        // SECOND store for this one message. Total writes across both sends is
        // at most 2 (1 prior sequential + at most 1 concurrent), never 3.
        expect(
          network.storeInInboxCallCount,
          lessThanOrEqualTo(2),
          reason: 'one message must never trigger two inbox writes (R1 guard)',
        );
      },
    );
  });
}
