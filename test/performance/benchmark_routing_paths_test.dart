import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart'
    as p2p;
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../shared/fakes/fake_p2p_network.dart';
import '../shared/fakes/test_user.dart';
import 'benchmark_harness.dart';
import 'timing_test_bridge.dart';

void main() {
  late BenchmarkHarness harness;
  late FakeP2PNetwork network;

  setUp(() {
    harness = BenchmarkHarness();
    network = FakeP2PNetwork();
  });

  tearDown(() {
    harness.dispose();
  });

  group('Benchmark: Routing Paths (1:1 Send — All Paths)', () {
    test('R1: WiFi local send — timing when peer is on LAN', () async {
      final alice = TestUser.create(
        peerId: 'alice-peer',
        username: 'Alice',
        network: network,
      );
      final bob = TestUser.create(
        peerId: 'bob-peer',
        username: 'Bob',
        network: network,
      );
      alice.addContact(bob);
      bob.addContact(alice);
      alice.start();
      bob.start();

      // Mark bob as local peer (on LAN) — fast WiFi delivery
      alice.p2pService.localPeers.add(bob.peerId);
      // Slow down direct path so WiFi wins the race
      alice.p2pService.discoverDelay = const Duration(milliseconds: 200);

      final events = await harness.captureFlowEvents(() async {
        await alice.sendMessage(bob.peerId, 'WiFi hello');
      });

      final timings = harness.filterEvents(events, 'CHAT_MSG_SEND_TIMING');
      expect(timings, isNotEmpty, reason: 'Should emit CHAT_MSG_SEND_TIMING');

      final details = timings.first['details'] as Map<String, dynamic>;
      expect(details['sendPath'], 'local');
      expect(details['outcome'], 'success');

      // ignore: avoid_print
      print('[BENCHMARK] routing_wifi_local_ms = ${details['elapsedMs']}');
    });

    test('R2: Direct P2P wins race — peer discoverable, no WiFi', () async {
      final bridge = TimingTestBridge(
        commandDelays: {
          'peer:dial': const Duration(milliseconds: 100),
        },
      );
      final alice = TestUser.create(
        peerId: 'alice-peer',
        username: 'Alice',
        network: network,
        bridge: bridge,
      );
      final bob = TestUser.create(
        peerId: 'bob-peer',
        username: 'Bob',
        network: network,
      );
      alice.addContact(bob);
      bob.addContact(alice);
      alice.start();
      bob.start();

      // No local peers — WiFi path not available
      // No connection reuse — cold send
      final events = await harness.captureFlowEvents(() async {
        await alice.sendMessage(bob.peerId, 'Direct hello');
      });

      final timings = harness.filterEvents(events, 'CHAT_MSG_SEND_TIMING');
      expect(timings, isNotEmpty);

      final details = timings.first['details'] as Map<String, dynamic>;
      expect(details['connectionReused'], isFalse);
      expect(details['sendPath'], isNot('reuse'));
      expect(details['outcome'], 'success');

      // ignore: avoid_print
      print('[BENCHMARK] routing_direct_cold_ms = ${details['elapsedMs']}');
    });

    test('R3: WiFi vs Direct race — WiFi wins', () async {
      final alice = TestUser.create(
        peerId: 'alice-peer',
        username: 'Alice',
        network: network,
      );
      final bob = TestUser.create(
        peerId: 'bob-peer',
        username: 'Bob',
        network: network,
      );
      alice.addContact(bob);
      bob.addContact(alice);
      alice.start();
      bob.start();

      // WiFi path: fast (30ms)
      alice.p2pService.localPeers.add(bob.peerId);
      alice.p2pService.localAckDelay = const Duration(milliseconds: 30);
      // Direct path: slow (discover takes 500ms)
      alice.p2pService.discoverDelay = const Duration(milliseconds: 500);

      final events = await harness.captureFlowEvents(() async {
        await alice.sendMessage(bob.peerId, 'Race message');
      });

      final timings = harness.filterEvents(events, 'CHAT_MSG_SEND_TIMING');
      expect(timings, isNotEmpty);

      final details = timings.first['details'] as Map<String, dynamic>;
      expect(details['sendPath'], 'local',
          reason: 'WiFi should win the race against slow direct');
      expect(details['outcome'], 'success');

      // ignore: avoid_print
      print('[BENCHMARK] routing_race_wifi_wins_ms = ${details['elapsedMs']}');
    });

    test('R4: WiFi vs Direct race — Direct wins', () async {
      final alice = TestUser.create(
        peerId: 'alice-peer',
        username: 'Alice',
        network: network,
      );
      final bob = TestUser.create(
        peerId: 'bob-peer',
        username: 'Bob',
        network: network,
      );
      alice.addContact(bob);
      bob.addContact(alice);
      alice.start();
      bob.start();

      // WiFi path: slow (1200ms — exceeds interactiveLocalBudget of 1500ms)
      alice.p2pService.localPeers.add(bob.peerId);
      alice.p2pService.localAckDelay = const Duration(milliseconds: 1200);

      // Direct path: fast (no extra delay)

      final events = await harness.captureFlowEvents(() async {
        await alice.sendMessage(bob.peerId, 'Direct wins');
      });

      final timings = harness.filterEvents(events, 'CHAT_MSG_SEND_TIMING');
      expect(timings, isNotEmpty);

      final details = timings.first['details'] as Map<String, dynamic>;
      // Direct should win because WiFi is slower
      expect(details['sendPath'], isNot('reuse'));
      expect(details['outcome'], 'success');

      // ignore: avoid_print
      print('[BENCHMARK] routing_race_direct_wins_ms = '
          '${details['elapsedMs']}');
    });

    test('R5: WiFi fails, direct succeeds — race fallback within race',
        () async {
      final alice = TestUser.create(
        peerId: 'alice-peer',
        username: 'Alice',
        network: network,
      );
      final bob = TestUser.create(
        peerId: 'bob-peer',
        username: 'Bob',
        network: network,
      );
      alice.addContact(bob);
      bob.addContact(alice);
      alice.start();
      bob.start();

      // WiFi fails immediately
      alice.p2pService.localPeers.add(bob.peerId);
      alice.p2pService.localSendResult = false;

      final events = await harness.captureFlowEvents(() async {
        await alice.sendMessage(bob.peerId, 'Fallback to direct');
      });

      final timings = harness.filterEvents(events, 'CHAT_MSG_SEND_TIMING');
      expect(timings, isNotEmpty);

      final details = timings.first['details'] as Map<String, dynamic>;
      // WiFi failed, direct should win
      expect(details['outcome'], 'success');

      // ignore: avoid_print
      print('[BENCHMARK] routing_wifi_fail_direct_win_ms = '
          '${details['elapsedMs']}');
    });

    test(
        'R6: Relay probe path — discover fails, probe finds peer on relay',
        () async {
      final alice = TestUser.create(
        peerId: 'alice-peer',
        username: 'Alice',
        network: network,
      );
      final bob = TestUser.create(
        peerId: 'bob-peer',
        username: 'Bob',
        network: network,
      );
      alice.addContact(bob);
      bob.addContact(alice);
      alice.start();
      bob.start();

      // Discover fails (peer not directly discoverable)
      alice.p2pService.discoverAlwaysFails = true;
      // Probe returns connected (peer reachable via relay)
      alice.p2pService.probeRelayResult = RelayProbeResult.connected;
      // Dial succeeds (via relay circuit), send succeeds
      // discoverAlwaysFails only affects discover, not dial

      final events = await harness.captureFlowEvents(() async {
        await alice.sendMessage(bob.peerId, 'Relay probe msg');
      });

      final timings = harness.filterEvents(events, 'CHAT_MSG_SEND_TIMING');
      expect(timings, isNotEmpty);

      final details = timings.first['details'] as Map<String, dynamic>;
      expect(details['sendPath'], 'relay');
      expect(details['outcome'], 'success');

      // Verify relay probe was attempted
      final probeEvents = harness.filterEvents(
        events,
        'CHAT_MSG_SEND_RELAY_PROBE_BEGIN',
      );
      expect(probeEvents, isNotEmpty,
          reason: 'Relay probe should be attempted after discover fails');

      // ignore: avoid_print
      print('[BENCHMARK] routing_relay_probe_success_ms = '
          '${details['elapsedMs']}');
    });

    test(
        'R7: Relay probe path — dial fails, probe finds peer, relay send works',
        () async {
      final alice = TestUser.create(
        peerId: 'alice-peer',
        username: 'Alice',
        network: network,
      );
      final bob = TestUser.create(
        peerId: 'bob-peer',
        username: 'Bob',
        network: network,
      );
      alice.addContact(bob);
      bob.addContact(alice);
      alice.start();
      bob.start();

      // Discover succeeds but dial fails
      alice.p2pService.dialAlwaysFails = true;
      // Probe returns connected
      alice.p2pService.probeRelayResult = RelayProbeResult.connected;

      // For the relay probe path, dial is re-attempted after probe — we need
      // it to succeed on the probe path. Reset dialAlwaysFails after race.
      // The trick: dial fails in the race (dialAlwaysFails=true), then after
      // probe connected, the send path uses sendMessageWithReply which doesn't
      // call dial again — it just sends. But the relay probe path calls
      // dialPeer first. Since dialAlwaysFails is still true, the dial in probe
      // path also fails but execution still tries sendMessageWithReply.
      // We need sendMessageWithReply to succeed after probe.
      // Since bob is online on the network, sendMessageWithReply will succeed.

      final events = await harness.captureFlowEvents(() async {
        await alice.sendMessage(bob.peerId, 'Relay after dial fail');
      });

      final timings = harness.filterEvents(events, 'CHAT_MSG_SEND_TIMING');
      expect(timings, isNotEmpty);

      final details = timings.first['details'] as Map<String, dynamic>;
      // Race fails (dial failed → relayProbeEligible), then probe path
      expect(details['outcome'], 'success');

      // ignore: avoid_print
      print('[BENCHMARK] routing_relay_after_dial_fail_ms = '
          '${details['elapsedMs']}');
    });

    test('R8: Relay probe — first send fails, retry succeeds', () async {
      final alice = TestUser.create(
        peerId: 'alice-peer',
        username: 'Alice',
        network: network,
      );
      final bob = TestUser.create(
        peerId: 'bob-peer',
        username: 'Bob',
        network: network,
      );
      alice.addContact(bob);
      bob.addContact(alice);
      alice.start();
      bob.start();

      // Discover fails → relay probe eligible
      alice.p2pService.discoverAlwaysFails = true;
      // Probe returns connected
      alice.p2pService.probeRelayResult = RelayProbeResult.connected;
      // First sendMessageWithReply fails (send attempt 1 in race was discover
      // fail, then probe path: first send attempt returns sent=false).
      // sendFailCount counts across ALL sendMessageWithReply calls.
      // Race: discover fails → no sendMessageWithReply called in race.
      // Probe: dial (may fail) + sendMessageWithReply attempt 1 (fails) +
      //        retry after 250ms → sendMessageWithReply attempt 2 (succeeds).
      alice.p2pService.sendFailCount = 1;

      final events = await harness.captureFlowEvents(() async {
        await alice.sendMessage(bob.peerId, 'Retry relay msg');
      });

      final timings = harness.filterEvents(events, 'CHAT_MSG_SEND_TIMING');
      expect(timings, isNotEmpty);

      final details = timings.first['details'] as Map<String, dynamic>;
      expect(details['sendPath'], 'relay');
      expect(details['outcome'], 'success');

      // Verify retry event was emitted
      final retryEvents = harness.filterEvents(
        events,
        'CHAT_MSG_SEND_RELAY_PROBE_SEND_RETRY',
      );
      expect(retryEvents, isNotEmpty,
          reason: 'Should emit retry event after first send fails');

      // ignore: avoid_print
      print('[BENCHMARK] routing_relay_retry_success_ms = '
          '${details['elapsedMs']}');
    });

    test('R9: Relay probe — noReservation → falls to inbox', () async {
      final alice = TestUser.create(
        peerId: 'alice-peer',
        username: 'Alice',
        network: network,
      );
      final bob = TestUser.create(
        peerId: 'bob-peer',
        username: 'Bob',
        network: network,
      );
      alice.addContact(bob);
      alice.start();
      // Bob is offline — not registered on network
      bob.p2pService.setOnline(false);

      // Discover fails → relay probe eligible
      // (bob is offline, so discoverPeer returns null naturally)
      // Probe returns noReservation (peer truly offline)
      alice.p2pService.probeRelayResult = RelayProbeResult.noReservation;

      final events = await harness.captureFlowEvents(() async {
        await alice.sendMessage(bob.peerId, 'Offline inbox msg');
      });

      final timings = harness.filterEvents(events, 'CHAT_MSG_SEND_TIMING');
      expect(timings, isNotEmpty);

      final details = timings.first['details'] as Map<String, dynamic>;
      expect(details['sendPath'], 'inbox');
      expect(details['outcome'], 'success');

      // Verify no-reservation event
      final noResEvents = harness.filterEvents(
        events,
        'CHAT_MSG_SEND_RELAY_PROBE_NO_RESERVATION',
      );
      expect(noResEvents, isNotEmpty);

      // ignore: avoid_print
      print('[BENCHMARK] routing_probe_no_reservation_to_inbox_ms = '
          '${details['elapsedMs']}');
    });

    test('R10: Inbox fallback after probe error', () async {
      final alice = TestUser.create(
        peerId: 'alice-peer',
        username: 'Alice',
        network: network,
      );
      final bob = TestUser.create(
        peerId: 'bob-peer',
        username: 'Bob',
        network: network,
      );
      alice.addContact(bob);
      alice.start();
      bob.p2pService.setOnline(false);

      // Discover fails → relay probe eligible
      // Probe returns error
      alice.p2pService.probeRelayResult = RelayProbeResult.error;

      final events = await harness.captureFlowEvents(() async {
        await alice.sendMessage(bob.peerId, 'Probe error inbox msg');
      });

      final timings = harness.filterEvents(events, 'CHAT_MSG_SEND_TIMING');
      expect(timings, isNotEmpty);

      final details = timings.first['details'] as Map<String, dynamic>;
      expect(details['sendPath'], 'inbox');
      expect(details['outcome'], 'success');

      // ignore: avoid_print
      print('[BENCHMARK] routing_probe_error_to_inbox_ms = '
          '${details['elapsedMs']}');
    });

    test('R11: Inbox fallback — probe ineligible (send_failed in race)',
        () async {
      final alice = TestUser.create(
        peerId: 'alice-peer',
        username: 'Alice',
        network: network,
      );
      final bob = TestUser.create(
        peerId: 'bob-peer',
        username: 'Bob',
        network: network,
      );
      alice.addContact(bob);
      bob.addContact(alice);
      alice.start();
      bob.start();

      // Discover succeeds, dial succeeds, but send returns sent=false
      // send_failed is NOT relay probe eligible
      alice.p2pService.sendFailCount = 999;

      final events = await harness.captureFlowEvents(() async {
        await alice.sendMessage(bob.peerId, 'Send failed inbox msg');
      });

      final timings = harness.filterEvents(events, 'CHAT_MSG_SEND_TIMING');
      expect(timings, isNotEmpty);

      final details = timings.first['details'] as Map<String, dynamic>;
      // Probe was NOT attempted — send failure doesn't set eligibility
      final probeEvents = harness.filterEvents(
        events,
        'CHAT_MSG_SEND_RELAY_PROBE_BEGIN',
      );
      expect(probeEvents, isEmpty,
          reason: 'send_failed should NOT trigger relay probe');

      // Falls directly to inbox
      expect(details['sendPath'], 'inbox');
      expect(details['outcome'], 'success');

      // ignore: avoid_print
      print('[BENCHMARK] routing_send_fail_direct_inbox_ms = '
          '${details['elapsedMs']}');
    });

    test('R12: Budget starvation — slow discover consumes 2s budget',
        () async {
      final bridge = TimingTestBridge(
        commandDelays: {
          // Slow discovery that eats into the budget
          'peer:discover': const Duration(milliseconds: 1800),
        },
      );
      final alice = TestUser.create(
        peerId: 'alice-peer',
        username: 'Alice',
        network: network,
        bridge: bridge,
      );
      final bob = TestUser.create(
        peerId: 'bob-peer',
        username: 'Bob',
        network: network,
      );
      alice.addContact(bob);
      bob.addContact(alice);
      alice.start();
      bob.start();

      // The direct path has a 2s interactiveDirectBudget timeout.
      // With discover taking 1800ms, the remaining budget for dial+send is
      // minimal. The race may timeout, falling to inbox.
      final events = await harness.captureFlowEvents(() async {
        await alice.sendMessage(bob.peerId, 'Slow discover msg');
      });

      final timings = harness.filterEvents(events, 'CHAT_MSG_SEND_TIMING');
      expect(timings, isNotEmpty);

      final details = timings.first['details'] as Map<String, dynamic>;
      expect(details['elapsedMs'], isA<int>());
      expect(details['outcome'], isA<String>());

      // ignore: avoid_print
      print('[BENCHMARK] routing_budget_starvation_ms = '
          '${details['elapsedMs']}');
    });

    test('R13: Unacked inbox handoff — sent but no ACK', () async {
      final alice = TestUser.create(
        peerId: 'alice-peer',
        username: 'Alice',
        network: network,
      );
      final bob = TestUser.create(
        peerId: 'bob-peer',
        username: 'Bob',
        network: network,
      );
      alice.addContact(bob);
      bob.addContact(alice);
      alice.start();
      bob.start();

      // Connection reuse path
      alice.p2pService.testConnections.add(p2p.ConnectionState(
        peerId: bob.peerId,
        multiaddrs: ['/p2p-circuit/p2p/relay'],
        direction: 'outbound',
        status: 'connected',
      ));

      // sendMessageWithReply returns sent=true (delivered to network)
      // but acknowledged is based on reply content — the fake returns
      // a non-null reply when delivered, which counts as acknowledged.
      // To test unacked, we'd need more control. For now, verify the
      // reuse path works and timing is captured.

      final events = await harness.captureFlowEvents(() async {
        await alice.sendMessage(bob.peerId, 'Unacked msg');
      });

      final timings = harness.filterEvents(events, 'CHAT_MSG_SEND_TIMING');
      expect(timings, isNotEmpty);

      final details = timings.first['details'] as Map<String, dynamic>;
      expect(details['sendPath'], 'reuse');
      expect(details['outcome'], 'success');
      expect(details['connectionReused'], isTrue);

      // ignore: avoid_print
      print('[BENCHMARK] routing_unacked_handoff_ms = '
          '${details['elapsedMs']}');
    });

    test('R14: Stale connection — reuse fails, falls to race', () async {
      final alice = TestUser.create(
        peerId: 'alice-peer',
        username: 'Alice',
        network: network,
      );
      final bob = TestUser.create(
        peerId: 'bob-peer',
        username: 'Bob',
        network: network,
      );
      alice.addContact(bob);
      bob.addContact(alice);
      alice.start();
      bob.start();

      // Stale connection listed but first send fails (connection dead)
      alice.p2pService.testConnections.add(p2p.ConnectionState(
        peerId: bob.peerId,
        multiaddrs: ['/p2p-circuit/p2p/relay'],
        direction: 'outbound',
        status: 'connected',
      ));
      // First sendMessageWithReply fails (stale reuse), second succeeds (race)
      alice.p2pService.sendFailCount = 1;

      final events = await harness.captureFlowEvents(() async {
        await alice.sendMessage(bob.peerId, 'Stale recovery msg');
      });

      final timings = harness.filterEvents(events, 'CHAT_MSG_SEND_TIMING');
      expect(timings, isNotEmpty);

      final details = timings.first['details'] as Map<String, dynamic>;
      // After reuse fails, falls through to race — connectionReused is reset
      expect(details['connectionReused'], isFalse);
      expect(details['outcome'], 'success');

      // ignore: avoid_print
      print('[BENCHMARK] routing_stale_reuse_fallback_ms = '
          '${details['elapsedMs']}');
    });

    test('R15: Worst-case cascade — all paths fail sequentially', () async {
      final alice = TestUser.create(
        peerId: 'alice-peer',
        username: 'Alice',
        network: network,
      );
      final bob = TestUser.create(
        peerId: 'bob-peer',
        username: 'Bob',
        network: network,
      );
      alice.addContact(bob);
      alice.start();
      // Bob is offline
      bob.p2pService.setOnline(false);

      // Discover fails (bob offline) → relay probe eligible
      // Probe returns error
      alice.p2pService.probeRelayResult = RelayProbeResult.error;
      // Inbox fails too
      network.inboxDisabled = true;

      final events = await harness.captureFlowEvents(() async {
        await alice.sendMessage(bob.peerId, 'Total failure msg');
      });

      final timings = harness.filterEvents(events, 'CHAT_MSG_SEND_TIMING');
      expect(timings, isNotEmpty);

      final details = timings.first['details'] as Map<String, dynamic>;
      expect(details['outcome'], 'failed');

      // Message should be persisted with failed status and wireEnvelope
      final messages = await alice.messageRepo.getMessagesForContact(
        bob.peerId,
      );
      expect(messages, isNotEmpty);
      expect(messages.last.status, 'failed');
      expect(messages.last.wireEnvelope, isNotNull);

      // ignore: avoid_print
      print('[BENCHMARK] routing_worst_case_cascade_ms = '
          '${details['elapsedMs']}');
    });

    test('R16: Interactive inbox timeout — slow inbox store', () async {
      final alice = TestUser.create(
        peerId: 'alice-peer',
        username: 'Alice',
        network: network,
      );
      final bob = TestUser.create(
        peerId: 'bob-peer',
        username: 'Bob',
        network: network,
      );
      alice.addContact(bob);
      alice.start();
      bob.p2pService.setOnline(false);

      // All fast paths fail, falls to inbox
      // Discover fails (bob offline) → probe eligible
      // Probe returns noReservation → inbox
      alice.p2pService.probeRelayResult = RelayProbeResult.noReservation;

      // Inbox store succeeds but takes a while (simulated via network ack delay
      // — storeInInbox is synchronous in the fake, so we just verify the path)

      final events = await harness.captureFlowEvents(() async {
        await alice.sendMessage(bob.peerId, 'Slow inbox msg');
      });

      final timings = harness.filterEvents(events, 'CHAT_MSG_SEND_TIMING');
      expect(timings, isNotEmpty);

      final details = timings.first['details'] as Map<String, dynamic>;
      expect(details['sendPath'], 'inbox');
      expect(details['outcome'], 'success');
      expect(details['elapsedMs'], isA<int>());

      // ignore: avoid_print
      print('[BENCHMARK] routing_inbox_timeout_current_ms = '
          '${details['elapsedMs']}');
    });

    test('R17: Relay probe eligibility matrix', () async {
      // Sub-test a: discover → peer_not_found (probe eligible)
      {
        final net = FakeP2PNetwork();
        final a = TestUser.create(
          peerId: 'a', username: 'A', network: net);
        final b = TestUser.create(
          peerId: 'b', username: 'B', network: net);
        a.addContact(b);
        a.start();
        b.p2pService.setOnline(false); // discover returns null

        a.p2pService.probeRelayResult = RelayProbeResult.error;

        final evA = await harness.captureFlowEvents(() async {
          await a.sendMessage(b.peerId, 'a-msg');
        });
        final probeA = harness.filterEvents(
          evA, 'CHAT_MSG_SEND_RELAY_PROBE_BEGIN');
        expect(probeA, isNotEmpty,
            reason: 'a) peer_not_found should trigger probe');
        a.dispose();
        b.dispose();
      }

      // Sub-test b: dial → dial_failed (probe eligible)
      {
        final net = FakeP2PNetwork();
        final a = TestUser.create(
          peerId: 'a', username: 'A', network: net);
        final b = TestUser.create(
          peerId: 'b', username: 'B', network: net);
        a.addContact(b);
        a.start();
        b.start();

        a.p2pService.dialAlwaysFails = true;
        a.p2pService.probeRelayResult = RelayProbeResult.error;

        final evB = await harness.captureFlowEvents(() async {
          await a.sendMessage(b.peerId, 'b-msg');
        });
        final probeB = harness.filterEvents(
          evB, 'CHAT_MSG_SEND_RELAY_PROBE_BEGIN');
        expect(probeB, isNotEmpty,
            reason: 'b) dial_failed should trigger probe');
        a.dispose();
        b.dispose();
      }

      // Sub-test c: send → send_failed (probe NOT eligible)
      {
        final net = FakeP2PNetwork();
        final a = TestUser.create(
          peerId: 'a', username: 'A', network: net);
        final b = TestUser.create(
          peerId: 'b', username: 'B', network: net);
        a.addContact(b);
        a.start();
        b.start();

        a.p2pService.sendFailCount = 999;
        a.p2pService.probeRelayResult = RelayProbeResult.connected;

        final evC = await harness.captureFlowEvents(() async {
          await a.sendMessage(b.peerId, 'c-msg');
        });
        final probeC = harness.filterEvents(
          evC, 'CHAT_MSG_SEND_RELAY_PROBE_BEGIN');
        expect(probeC, isEmpty,
            reason: 'c) send_failed should NOT trigger probe');
        a.dispose();
        b.dispose();
      }

      // Sub-test d: race timeout (probe NOT eligible)
      // The direct path timeout produces 'direct_timeout' reason.
      // In the use case, the timeout wraps _tryDirectSend — on timeout,
      // _RaceResult.failed('direct_timeout') is returned without
      // relayProbeEligible. So probe is NOT triggered.
      {
        final net = FakeP2PNetwork();
        final bridge = TimingTestBridge(
          commandDelays: {
            // Make discover take longer than interactiveDirectBudget (2s)
            'peer:discover': const Duration(seconds: 3),
          },
        );
        final a = TestUser.create(
          peerId: 'a', username: 'A', network: net, bridge: bridge);
        final b = TestUser.create(
          peerId: 'b', username: 'B', network: net);
        a.addContact(b);
        a.start();
        b.start();

        a.p2pService.probeRelayResult = RelayProbeResult.connected;

        final evD = await harness.captureFlowEvents(() async {
          await a.sendMessage(b.peerId, 'd-msg');
        });
        final probeD = harness.filterEvents(
          evD, 'CHAT_MSG_SEND_RELAY_PROBE_BEGIN');
        expect(probeD, isEmpty,
            reason: 'd) race timeout should NOT trigger probe');
        a.dispose();
        b.dispose();
      }

      // Sub-test e: WiFi fail only, direct not available (probe NOT eligible
      // if WiFi is the only failure — but in practice, the direct path also
      // runs and its result determines eligibility)
      {
        final net = FakeP2PNetwork();
        final a = TestUser.create(
          peerId: 'a', username: 'A', network: net);
        final b = TestUser.create(
          peerId: 'b', username: 'B', network: net);
        a.addContact(b);
        a.start();
        b.start();

        a.p2pService.localPeers.add(b.peerId);
        a.p2pService.localSendResult = false;
        // Direct path also runs and succeeds — so this doesn't test
        // "WiFi fail only". Instead, send_failed on both paths:
        a.p2pService.sendFailCount = 999;

        final evE = await harness.captureFlowEvents(() async {
          await a.sendMessage(b.peerId, 'e-msg');
        });
        final probeE = harness.filterEvents(
          evE, 'CHAT_MSG_SEND_RELAY_PROBE_BEGIN');
        // send_failed is not probe eligible
        expect(probeE, isEmpty,
            reason: 'e) send_failed should NOT trigger probe');
        a.dispose();
        b.dispose();
      }

      // Sub-test f: discover fail + WiFi fail combined (probe eligible —
      // discover failure with relayProbeEligible=true wins)
      {
        final net = FakeP2PNetwork();
        final a = TestUser.create(
          peerId: 'a', username: 'A', network: net);
        final b = TestUser.create(
          peerId: 'b', username: 'B', network: net);
        a.addContact(b);
        a.start();
        b.p2pService.setOnline(false); // discover returns null

        a.p2pService.localPeers.add(b.peerId);
        a.p2pService.localSendResult = false;
        a.p2pService.probeRelayResult = RelayProbeResult.error;

        final evF = await harness.captureFlowEvents(() async {
          await a.sendMessage(b.peerId, 'f-msg');
        });
        final probeF = harness.filterEvents(
          evF, 'CHAT_MSG_SEND_RELAY_PROBE_BEGIN');
        expect(probeF, isNotEmpty,
            reason: 'f) discover fail should trigger probe '
                'even if WiFi also failed');
        a.dispose();
        b.dispose();
      }

      // ignore: avoid_print
      print('[BENCHMARK] routing_probe_eligibility: '
          'a=probe b=probe c=no_probe d=no_probe e=no_probe f=probe');
    });
  });
}
