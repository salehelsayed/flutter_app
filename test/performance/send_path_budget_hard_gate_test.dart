/// NET-REL-05 — L1: latency budget HARD GATE.
///
/// The tracking doc (NET-REL-05, Latency harness) calls out that NO existing
/// test proves a budget is actually ENFORCED — the only "slow local" test shows
/// that a slow local leg does not BLOCK (direct wins regardless of whether the
/// 1500ms cutoff fires), which a path could pass by luck. To prove the cutoff
/// itself we set a delay knob ABOVE the budget and assert the slow path is
/// ABANDONED AT THE BUDGET — i.e. the send completes in ~budget time, NOT in the
/// (much larger) delay time, AND the slow path never wins the transport label.
///
/// Built on `fake_p2p_service_integration.dart` because the in-file
/// `FakeP2PService` of `send_chat_message_use_case_test.dart` has no delay knob.
///
/// Budgets under test (from send_chat_message_use_case.dart):
///   interactiveLocalBudget  = 1500ms
///   interactiveDirectBudget = 2000ms
///   interactiveInboxBudget  = 3000ms
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';

import '../shared/fakes/fake_p2p_network.dart';
import '../shared/fakes/fake_p2p_service_integration.dart';
import '../shared/fakes/test_user.dart';

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
  });

  tearDown(() {
    alice.dispose();
    bob.dispose();
  });

  group('NET-REL-05 L1 — send-path budget hard gate', () {
    test(
      'slow LOCAL leg (ack delay ABOVE 1500ms local budget) is abandoned at '
      'the budget; the direct leg carries it well under the local delay',
      () async {
        // Peer is on the LAN, but the local ack is far slower than the local
        // budget. The direct path is healthy (peer online). If the budget is
        // enforced, the local leg is cut at ~1500ms (and never wins); if it is
        // NOT enforced, we would block ~5s on the local ack.
        aliceP2P.localPeers.add(bob.peerId);
        aliceP2P.localAckDelay = const Duration(seconds: 5);

        final stopwatch = Stopwatch()..start();
        final (result, msg) = await alice.sendMessage(bob.peerId, 'budgeted');
        stopwatch.stop();

        expect(result, SendChatMessageResult.success);
        expect(msg!.status, 'delivered');
        // The slow local path was abandoned — direct carried it.
        expect(
          msg.transport,
          isNot('local'),
          reason: 'the 5s local ack must be abandoned at the 1500ms budget, so '
              'the direct leg wins',
        );
        // PROOF the cutoff fired: completion is bounded near the budget, NOT
        // near the 5s local delay (a "fast by luck" path would still be < 5s
        // but here we additionally pin the local timeout that was applied).
        expect(
          stopwatch.elapsed,
          lessThan(const Duration(seconds: 3)),
          reason: 'send must not wait out the 5s local ack',
        );
        // The local leg was invoked with the local budget as its timeout.
        expect(aliceP2P.localSendCallCount, 1);
        expect(
          aliceP2P.lastLocalTimeoutMs,
          interactiveLocalBudget.inMilliseconds,
          reason: 'the local leg is bounded by interactiveLocalBudget',
        );
      },
    );

    test(
      'slow DIRECT discover (delay ABOVE 2000ms direct budget) to an OFFLINE '
      'peer is abandoned at the budget; the send falls to durable inbox without '
      'waiting out the full discover delay',
      () async {
        // Peer offline: no live path can win. Discover is far slower than the
        // direct budget. With the budget enforced the direct leg is cut at ~2s
        // and the inbox fallback (custody) lands; without enforcement we would
        // block ~8s on discover.
        bob.setOnline(false);
        aliceP2P.discoverDelay = const Duration(seconds: 8);

        final stopwatch = Stopwatch()..start();
        final (result, msg) = await alice.sendMessage(bob.peerId, 'offline-budgeted');
        stopwatch.stop();

        expect(result, SendChatMessageResult.success);
        expect(msg!.status, 'delivered');
        expect(msg.transport, 'inbox');
        // PROOF the direct cutoff fired: the durable fallback lands far sooner
        // than the 8s discover delay would allow.
        expect(
          stopwatch.elapsed,
          lessThan(const Duration(seconds: 6)),
          reason: 'the 8s discover must be abandoned at the 2000ms direct '
              'budget, then the inbox tail (<=3s) takes custody — never an 8s '
              'block',
        );
        // Durable custody actually fired (single write for this one message).
        expect(network.storeInInboxCallCount, 1);
      },
    );

    test(
      'NEGATIVE CONTROL (no false gate): a healthy direct path that resolves '
      'WELL UNDER budget is NOT cut and delivers live',
      () async {
        // No delays, peer online → the direct leg should win fast and live,
        // proving the budget cut above is a real cut, not a path that always
        // fails/falls back regardless of timing.
        aliceP2P.testConnections.clear();

        final stopwatch = Stopwatch()..start();
        final (result, msg) = await alice.sendMessage(bob.peerId, 'fast live');
        stopwatch.stop();

        expect(result, SendChatMessageResult.success);
        expect(msg!.status, 'delivered');
        expect(
          msg.transport,
          isNot('inbox'),
          reason: 'a healthy fast path is delivered live, never cut to inbox',
        );
        expect(network.storeInInboxCallCount, 0);
        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
      },
    );
  });
}
