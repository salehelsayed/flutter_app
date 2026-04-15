import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_test/flutter_test.dart';

import '../shared/fakes/in_memory_inbox_staging_repository.dart';
import '../shared/fakes/lifecycle_bridge.dart';
import 'benchmark_harness.dart';

void main() {
  late BenchmarkHarness harness;
  late LifecycleBridge bridge;
  late P2PServiceImpl service;

  setUp(() {
    harness = BenchmarkHarness();
    bridge = LifecycleBridge();
    service = P2PServiceImpl(
      bridge: bridge,
      inboxStagingRepository: InMemoryInboxStagingRepository(),
    );
  });

  tearDown(() {
    service.dispose();
    harness.dispose();
  });

  group('Benchmark: Time-to-Online Badge', () {
    test('M1: Cold start emits TIME_TO_ONLINE_BADGE with phase=cold_start',
        () async {
      bridge.phase = 'startup';

      final events = await harness.captureFlowEvents(() async {
        await service.startNodeCore(testBase64Key, testPeerId);
      });

      final badge = harness.filterEvents(events, 'TIME_TO_ONLINE_BADGE');
      expect(badge, isNotEmpty, reason: 'Should emit TIME_TO_ONLINE_BADGE');

      final details = badge.first['details'] as Map<String, dynamic>;
      expect(details['totalMs'], isA<int>());
      expect(details['totalMs'], greaterThanOrEqualTo(0));
      expect(details['phase'], 'cold_start');
      expect(
        details['source'],
        isA<String>(),
        reason: 'source should track delivery path',
      );
    });

    test('M2: Recovery emits TIME_TO_ONLINE_BADGE with phase=recovery',
        () async {
      // Start online first
      bridge.phase = 'startup';
      await service.startNodeCore(testBase64Key, testPeerId);

      // Go degraded
      bridge.simulateBackground();
      await service.performImmediateHealthCheck();

      // Now capture recovery events
      final events = await harness.captureFlowEvents(() async {
        bridge.simulateRecoveryComplete();
        // Allow microtasks to settle
        await Future<void>.delayed(Duration.zero);
      });

      final badges = harness.filterEvents(events, 'TIME_TO_ONLINE_BADGE');
      expect(badges, isNotEmpty, reason: 'Should emit recovery badge');

      final details = badges.first['details'] as Map<String, dynamic>;
      expect(details['totalMs'], isA<int>());
      expect(details['totalMs'], greaterThanOrEqualTo(0));
      expect(details['phase'], 'recovery');
    });

    test('M3: Hot restart emits TIME_TO_ONLINE_BADGE with phase=hot_restart',
        () async {
      bridge.simulateAlreadyStarted = true;
      bridge.phase = 'online';

      final events = await harness.captureFlowEvents(() async {
        await service.startNodeCore(testBase64Key, testPeerId);
      });

      final badge = harness.filterEvents(events, 'TIME_TO_ONLINE_BADGE');
      expect(badge, isNotEmpty, reason: 'Should emit hot restart badge');

      final details = badge.first['details'] as Map<String, dynamic>;
      expect(details['totalMs'], isA<int>());
      expect(details['totalMs'], greaterThanOrEqualTo(0));
      expect(details['phase'], 'hot_restart');
    });

    test('M4: Source field tracks which delivery path won', () async {
      // When start response itself includes relayState='online',
      // source should be 'start_response'
      bridge.phase = 'startup';

      final events = await harness.captureFlowEvents(() async {
        await service.startNodeCore(testBase64Key, testPeerId);
      });

      final badge = harness.filterEvents(events, 'TIME_TO_ONLINE_BADGE');
      expect(badge, isNotEmpty);
      final details = badge.first['details'] as Map<String, dynamic>;
      expect(details['source'], 'start_response');
    });

    test('M5: Source tracks relay_state_push when push event wins', () async {
      // Start with degraded (no relay yet)
      bridge.phase = 'degraded';

      // Start will return degraded - no TIME_TO_ONLINE_BADGE yet
      await service.startNodeCore(testBase64Key, testPeerId);

      // Now simulate relay coming online via push
      final events = await harness.captureFlowEvents(() async {
        bridge.onRelayStateChanged?.call({
          'relayState': 'online',
          'healthyRelayCount': 1,
          'watchdogRestartCount': 0,
          'needsGroupRecovery': false,
          'reason': 'relay_connected',
        });
        await Future<void>.delayed(Duration.zero);
      });

      final badge = harness.filterEvents(events, 'TIME_TO_ONLINE_BADGE');
      expect(badge, isNotEmpty);
      final details = badge.first['details'] as Map<String, dynamic>;
      expect(details['source'], 'relay_state_push');
    });

    test('M6: Total user-perceived < 6s budget on cold start', () async {
      bridge.phase = 'startup';

      final events = await harness.captureFlowEvents(() async {
        await service.startNodeCore(testBase64Key, testPeerId);
      });

      final badge = harness.filterEvents(events, 'TIME_TO_ONLINE_BADGE');
      expect(badge, isNotEmpty);

      final totalMs =
          (badge.first['details'] as Map<String, dynamic>)['totalMs'] as int;
      expect(
        totalMs,
        lessThan(6000),
        reason: 'Cold start should be under 6s budget',
      );

      // TIME_TO_ONLINE_BADGE uses 'totalMs' not 'elapsedMs'
      final values = badge
          .map(
            (e) =>
                (e['details'] as Map<String, dynamic>)['totalMs'] as int,
          )
          .toList()
        ..sort();
      final line = harness.formatBenchmarkLine(
        'time_to_online_cold_start',
        p50: harness.percentile(values, 50),
        p95: harness.percentile(values, 95),
        n: values.length,
      );
      // ignore: avoid_print
      print(line);
    });
  });
}
