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

  group('Benchmark: Connection Reuse Hit Rate', () {
    test('J1: Scripted workload — first send cold, subsequent warm', () async {
      final alice = TestUser.create(
        peerId: 'alice-peer',
        username: 'Alice',
        network: network,
        bridge: TimingTestBridge(
          commandDelays: {'peer:dial': const Duration(milliseconds: 200)},
        ),
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

      final allTimings = <Map<String, dynamic>>[];

      // First send: cold (no connection)
      final firstEvents = await harness.captureFlowEvents(() async {
        await alice.sendMessage(bob.peerId, 'Message 1');
      });
      allTimings.addAll(
        harness.filterEvents(firstEvents, 'CHAT_MSG_SEND_TIMING'),
      );

      // Simulate connection established via currentState.connections
      alice.p2pService.testConnections.add(p2p.ConnectionState(
        peerId: bob.peerId,
        multiaddrs: ['/p2p-circuit/p2p/relay'],
        direction: 'outbound',
        status: 'connected',
      ));

      // Send 9 more: warm (connected)
      for (var i = 2; i <= 10; i++) {
        final events = await harness.captureFlowEvents(() async {
          await alice.sendMessage(bob.peerId, 'Message $i');
        });
        allTimings.addAll(
          harness.filterEvents(events, 'CHAT_MSG_SEND_TIMING'),
        );
      }

      expect(allTimings, hasLength(10));

      var reuseCount = 0;
      for (final t in allTimings) {
        if ((t['details'] as Map<String, dynamic>)['connectionReused'] ==
            true) {
          reuseCount++;
        }
      }

      final hitRate = (reuseCount / allTimings.length * 100).round();
      expect(hitRate, 90, reason: 'Expected 9/10 = 90% reuse rate');

      // ignore: avoid_print
      print('[BENCHMARK] connection_reuse_hit_rate = $hitRate%');
    });

    test('J2: Resume scenario — cold → warm → disconnect → cold → warm',
        () async {
      final alice = TestUser.create(
        peerId: 'alice-peer',
        username: 'Alice',
        network: network,
        bridge: TimingTestBridge(
          commandDelays: {'peer:dial': const Duration(milliseconds: 200)},
        ),
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

      final allTimings = <Map<String, dynamic>>[];

      // Phase 1: cold send
      var events = await harness.captureFlowEvents(() async {
        await alice.sendMessage(bob.peerId, 'P1-cold');
      });
      allTimings
          .addAll(harness.filterEvents(events, 'CHAT_MSG_SEND_TIMING'));

      // Connect, 2 warm sends
      alice.p2pService.testConnections.add(p2p.ConnectionState(
        peerId: bob.peerId,
        multiaddrs: ['/p2p-circuit/p2p/relay'],
        direction: 'outbound',
        status: 'connected',
      ));
      for (var i = 0; i < 2; i++) {
        events = await harness.captureFlowEvents(() async {
          await alice.sendMessage(bob.peerId, 'P1-warm-$i');
        });
        allTimings
            .addAll(harness.filterEvents(events, 'CHAT_MSG_SEND_TIMING'));
      }

      // Phase 2: disconnect
      alice.p2pService.testConnections.clear();

      // Cold send after disconnect
      events = await harness.captureFlowEvents(() async {
        await alice.sendMessage(bob.peerId, 'P2-cold');
      });
      allTimings
          .addAll(harness.filterEvents(events, 'CHAT_MSG_SEND_TIMING'));

      // Reconnect, 2 warm sends
      alice.p2pService.testConnections.add(p2p.ConnectionState(
        peerId: bob.peerId,
        multiaddrs: ['/p2p-circuit/p2p/relay'],
        direction: 'outbound',
        status: 'connected',
      ));
      for (var i = 0; i < 2; i++) {
        events = await harness.captureFlowEvents(() async {
          await alice.sendMessage(bob.peerId, 'P2-warm-$i');
        });
        allTimings
            .addAll(harness.filterEvents(events, 'CHAT_MSG_SEND_TIMING'));
      }

      expect(allTimings, hasLength(6));

      // Cold sends: events[0] and events[3]
      expect(
        (allTimings[0]['details'] as Map<String, dynamic>)['connectionReused'],
        isFalse,
      );
      expect(
        (allTimings[3]['details'] as Map<String, dynamic>)['connectionReused'],
        isFalse,
      );
      // Warm sends: events[1,2,4,5]
      for (final idx in [1, 2, 4, 5]) {
        expect(
          (allTimings[idx]['details']
              as Map<String, dynamic>)['connectionReused'],
          isTrue,
        );
      }

      final hitRate =
          (4 / 6 * 100).round(); // 4 warm out of 6 total = 67%
      // ignore: avoid_print
      print('[BENCHMARK] connection_reuse_resume_hit_rate = $hitRate%');
    });

    test('J3: Latency comparison — reused vs cold', () async {
      final bridge = TimingTestBridge(
        commandDelays: {'peer:dial': const Duration(milliseconds: 200)},
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

      final coldTimings = <int>[];
      final warmTimings = <int>[];

      // 5 cold sends (clear connection between each)
      for (var i = 0; i < 5; i++) {
        alice.p2pService.testConnections.clear();
        final events = await harness.captureFlowEvents(() async {
          await alice.sendMessage(bob.peerId, 'Cold-$i');
        });
        final timing =
            harness.filterEvents(events, 'CHAT_MSG_SEND_TIMING');
        if (timing.isNotEmpty) {
          coldTimings.add(
            (timing.first['details'] as Map<String, dynamic>)['elapsedMs']
                as int,
          );
        }
      }

      // 5 warm sends (keep connection)
      alice.p2pService.testConnections.add(p2p.ConnectionState(
        peerId: bob.peerId,
        multiaddrs: ['/p2p-circuit/p2p/relay'],
        direction: 'outbound',
        status: 'connected',
      ));
      for (var i = 0; i < 5; i++) {
        final events = await harness.captureFlowEvents(() async {
          await alice.sendMessage(bob.peerId, 'Warm-$i');
        });
        final timing =
            harness.filterEvents(events, 'CHAT_MSG_SEND_TIMING');
        if (timing.isNotEmpty) {
          warmTimings.add(
            (timing.first['details'] as Map<String, dynamic>)['elapsedMs']
                as int,
          );
        }
      }

      coldTimings.sort();
      warmTimings.sort();

      final coldP50 = harness.percentile(coldTimings, 50);
      final warmP50 = harness.percentile(warmTimings, 50);

      expect(
        coldP50,
        greaterThanOrEqualTo(warmP50),
        reason: 'Cold sends should be >= warm (dial overhead)',
      );

      // ignore: avoid_print
      print('[BENCHMARK] reuse_cold_send_ms p50=${coldP50}ms '
          '(n=${coldTimings.length})');
      // ignore: avoid_print
      print('[BENCHMARK] reuse_warm_send_ms p50=${warmP50}ms '
          '(n=${warmTimings.length})');
    });
  });
}
