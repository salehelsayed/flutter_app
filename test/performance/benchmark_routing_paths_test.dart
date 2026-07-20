import 'package:flutter_app/features/p2p/domain/models/connection_state.dart'
    as p2p;
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
        commandDelays: {'peer:dial': const Duration(milliseconds: 100)},
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
      expect(
        details['sendPath'],
        'local',
        reason: 'WiFi should win the race against slow direct',
      );
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
      print(
        '[BENCHMARK] routing_race_direct_wins_ms = '
        '${details['elapsedMs']}',
      );
    });

    test(
      'R5: WiFi fails, direct succeeds — race fallback within race',
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
        print(
          '[BENCHMARK] routing_wifi_fail_direct_win_ms = '
          '${details['elapsedMs']}',
        );
      },
    );

    test('R6: Discover miss — concurrent durable inbox custody', () async {
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

      // FDC-03 removed the serial relay-probe tail. With no in-race live
      // carrier, a discovery miss settles through the concurrent inbox copy.
      alice.p2pService.discoverAlwaysFails = true;

      final events = await harness.captureFlowEvents(() async {
        await alice.sendMessage(bob.peerId, 'Discover miss custody msg');
      });

      final timings = harness.filterEvents(events, 'CHAT_MSG_SEND_TIMING');
      expect(timings, isNotEmpty);

      final details = timings.first['details'] as Map<String, dynamic>;
      expect(details['sendPath'], 'inbox');
      expect(details['outcome'], 'success');

      final custodyEvents = harness.filterEvents(
        events,
        'CHAT_MSG_SEND_CONCURRENT_INBOX_CUSTODY',
      );
      expect(
        custodyEvents,
        isNotEmpty,
        reason: 'A discovery miss should retain durable inbox custody',
      );

      // ignore: avoid_print
      print(
        '[BENCHMARK] routing_discover_miss_inbox_custody_ms = '
        '${details['elapsedMs']}',
      );
    });

    test('R7: Dial failure — concurrent durable inbox custody', () async {
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

      // Discovery succeeds, but a failed dial leaves no live carrier. FDC-03
      // settles through the already-started concurrent inbox copy.
      alice.p2pService.dialAlwaysFails = true;

      final events = await harness.captureFlowEvents(() async {
        await alice.sendMessage(bob.peerId, 'Inbox after dial fail');
      });

      final timings = harness.filterEvents(events, 'CHAT_MSG_SEND_TIMING');
      expect(timings, isNotEmpty);

      final details = timings.first['details'] as Map<String, dynamic>;
      expect(details['sendPath'], 'inbox');
      expect(details['outcome'], 'success');

      // ignore: avoid_print
      print(
        '[BENCHMARK] routing_dial_fail_inbox_custody_ms = '
        '${details['elapsedMs']}',
      );
    });

    test('R9: Offline peer — concurrent durable inbox custody', () async {
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

      // Bob is undiscoverable, so the concurrent durable copy takes custody
      // without waiting for a serial relay-probe phase.

      final events = await harness.captureFlowEvents(() async {
        await alice.sendMessage(bob.peerId, 'Offline inbox msg');
      });

      final timings = harness.filterEvents(events, 'CHAT_MSG_SEND_TIMING');
      expect(timings, isNotEmpty);

      final details = timings.first['details'] as Map<String, dynamic>;
      expect(details['sendPath'], 'inbox');
      expect(details['outcome'], 'success');

      final custodyEvents = harness.filterEvents(
        events,
        'CHAT_MSG_SEND_CONCURRENT_INBOX_CUSTODY',
      );
      expect(custodyEvents, isNotEmpty);

      // ignore: avoid_print
      print(
        '[BENCHMARK] routing_offline_inbox_custody_ms = '
        '${details['elapsedMs']}',
      );
    });

    test('R11: Live send failure — durable inbox custody', () async {
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

      // Discovery and dial succeed, but every live send fails. The concurrent
      // durable copy remains the successful custody tier.
      alice.p2pService.sendFailCount = 999;

      final events = await harness.captureFlowEvents(() async {
        await alice.sendMessage(bob.peerId, 'Send failed inbox msg');
      });

      final timings = harness.filterEvents(events, 'CHAT_MSG_SEND_TIMING');
      expect(timings, isNotEmpty);

      final details = timings.first['details'] as Map<String, dynamic>;
      expect(details['sendPath'], 'inbox');
      expect(details['outcome'], 'success');

      // ignore: avoid_print
      print(
        '[BENCHMARK] routing_send_fail_direct_inbox_ms = '
        '${details['elapsedMs']}',
      );
    });

    test('R12: Budget starvation — slow discover consumes 2s budget', () async {
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
      print(
        '[BENCHMARK] routing_budget_starvation_ms = '
        '${details['elapsedMs']}',
      );
    });

    test('R13: Warm direct connection reuse timing', () async {
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

      // A warm direct connection is eligible for the reuse fast path.
      alice.p2pService.testConnections.add(
        p2p.ConnectionState(
          peerId: bob.peerId,
          multiaddrs: ['/ip4/10.0.0.2/tcp/4001'],
          direction: 'outbound',
          status: 'connected',
        ),
      );

      final events = await harness.captureFlowEvents(() async {
        await alice.sendMessage(bob.peerId, 'Warm reuse msg');
      });

      final timings = harness.filterEvents(events, 'CHAT_MSG_SEND_TIMING');
      expect(timings, isNotEmpty);

      final details = timings.first['details'] as Map<String, dynamic>;
      expect(details['sendPath'], 'reuse');
      expect(details['outcome'], 'success');
      expect(details['connectionReused'], isTrue);

      // ignore: avoid_print
      print(
        '[BENCHMARK] routing_direct_reuse_ms = '
        '${details['elapsedMs']}',
      );
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

      // A stale warm direct connection is listed, but its first send fails.
      alice.p2pService.testConnections.add(
        p2p.ConnectionState(
          peerId: bob.peerId,
          multiaddrs: ['/ip4/10.0.0.2/tcp/4001'],
          direction: 'outbound',
          status: 'connected',
        ),
      );
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
      print(
        '[BENCHMARK] routing_stale_reuse_fallback_ms = '
        '${details['elapsedMs']}',
      );
    });

    test('R15: Live race and durable inbox both fail', () async {
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

      // Bob is undiscoverable and the concurrent inbox deposit also fails.
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
      print(
        '[BENCHMARK] routing_live_and_inbox_failure_ms = '
        '${details['elapsedMs']}',
      );
    });
  });
}
