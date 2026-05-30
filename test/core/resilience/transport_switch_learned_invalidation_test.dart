/// NET-REL-05 — I2: transport switch mid-conversation, against NEW code
/// (the P3 sticky/learned-transport layer). Unlike the legacy
/// `f2_transport_switch_recovery_test.dart` — which only sends twice and checks
/// both are fast, never simulating a switch — this exercises a REAL LAN->relay
/// switch via the shared integration fake's `simulateTransportSwitch`, and
/// asserts BOTH:
///   1. delivery continues across the switch, AND
///   2. the learned (P3) transport INVALIDATES — a stale LAN preference is
///      never trusted after the peer leaves WiFi.
///
/// The sticky memory is opt-in on the fake (`stickyTransportEnabled = true`) so
/// the legacy resilience suite, written before P3, is unaffected.
///
/// NEGATIVE CONTROL (N-no-stale-local): after the LAN->relay switch, the next
/// send must NOT be labelled 'local' (the departed LAN peer's learned 'local'
/// must self-invalidate) — proving the test isn't merely re-asserting a frozen
/// transport.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';

import '../../shared/fakes/fake_p2p_network.dart';
import '../../shared/fakes/fake_p2p_service_integration.dart';
import '../../shared/fakes/test_user.dart';

void main() {
  late FakeP2PNetwork network;
  late TestUser alice;
  late TestUser bob;
  late FakeP2PService aliceP2P;

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

    aliceP2P = alice.p2pService;
    // Exercise the P3 sticky/learned layer (opt-in; default-off elsewhere).
    aliceP2P.stickyTransportEnabled = true;
    // Drive the resolved direct-vs-relay label deterministically.
    aliceP2P.reportTransportMode = true;
  });

  tearDown(() {
    alice.dispose();
    bob.dispose();
  });

  Future<void> waitForReceipt(Future<void> Function() send) async {
    final received = Completer<void>();
    final sub = bob.chatListener.incomingMessageStream.listen((_) {
      if (!received.isCompleted) received.complete();
    });
    await send();
    await received.future.timeout(const Duration(seconds: 2));
    await sub.cancel();
  }

  group('NET-REL-05 I2 — transport switch + learned-transport invalidation', () {
    test(
      'LAN->relay switch: delivery continues and the learned LAN transport '
      'invalidates (not trusted after the peer leaves WiFi)',
      () async {
        // --- Phase 1: peer on the same LAN. First send wins via local. ---
        aliceP2P.localPeers.add(bob.peerId);
        aliceP2P.transportMode = 'wifi';

        late dynamic m1;
        await waitForReceipt(() async {
          final (r1, msg1) = await alice.sendMessage(bob.peerId, 'On wifi');
          expect(r1, SendChatMessageResult.success);
          m1 = msg1;
        });
        expect(m1!.transport, 'local');
        // The live local delivery is now the learned-good transport.
        expect(aliceP2P.lastKnownGoodTransport(bob.peerId), 'local');

        // --- Phase 2: the real switch. Peer leaves WiFi, route is now relay. ---
        aliceP2P.simulateTransportSwitch('relay');

        // The learned 'local' must INVALIDATE: the peer is no longer LAN-visible,
        // so a stale LAN preference is never returned.
        expect(
          aliceP2P.lastKnownGoodTransport(bob.peerId),
          isNull,
          reason: 'learned LAN transport must invalidate once the peer leaves '
              'WiFi (never trust a stale-by-departure local preference)',
        );

        // --- Phase 3: delivery continues over the new transport. ---
        late dynamic m2;
        await waitForReceipt(() async {
          final (r2, msg2) = await alice.sendMessage(bob.peerId, 'After switch');
          expect(r2, SendChatMessageResult.success);
          m2 = msg2;
        });
        expect(m2!.status, 'delivered');
        // NEGATIVE CONTROL (N-no-stale-local): the post-switch send is NOT local.
        expect(
          m2.transport,
          isNot('local'),
          reason: 'after the peer leaves WiFi the send must ride the new '
              'transport, never the stale LAN path',
        );
        expect(m2.transport, 'relay');
        // The new live delivery is learned for next time.
        expect(aliceP2P.lastKnownGoodTransport(bob.peerId), 'relay');

        // Both messages delivered, none duplicated.
        final bobConvo = await bob.loadConversationWith(alice.peerId);
        expect(bobConvo, hasLength(2));
        expect(
          bobConvo.map((m) => m.text).toList(),
          ['On wifi', 'After switch'],
        );
      },
    );

    test(
      'relay->relay re-send across a network change invalidates the non-local '
      'learned preference and re-learns on the next live delivery',
      () async {
        aliceP2P.transportMode = 'relay';

        late dynamic m1;
        await waitForReceipt(() async {
          final (r1, msg1) = await alice.sendMessage(bob.peerId, 'Relay one');
          expect(r1, SendChatMessageResult.success);
          m1 = msg1;
        });
        expect(m1!.transport, 'relay');
        expect(aliceP2P.lastKnownGoodTransport(bob.peerId), 'relay');

        // A network change (still relay, but route shifted) must drop the
        // non-'local' learned preference so the next send re-races rather than
        // trusting a possibly-dead route.
        aliceP2P.simulateTransportSwitch('relay');
        expect(
          aliceP2P.lastKnownGoodTransport(bob.peerId),
          isNull,
          reason: 'a relay-health/network transition clears non-local learned '
              'transports',
        );

        late dynamic m2;
        await waitForReceipt(() async {
          final (r2, msg2) = await alice.sendMessage(bob.peerId, 'Relay two');
          expect(r2, SendChatMessageResult.success);
          m2 = msg2;
        });
        expect(m2!.status, 'delivered');
        // Re-learned after the next live delivery.
        expect(aliceP2P.lastKnownGoodTransport(bob.peerId), 'relay');
      },
    );
  });
}
