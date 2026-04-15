import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_test/flutter_test.dart';

import '../shared/fakes/in_memory_inbox_staging_repository.dart';
import '../shared/fakes/lifecycle_bridge.dart';
import 'benchmark_harness.dart';

void main() {
  late BenchmarkHarness harness;

  setUp(() {
    harness = BenchmarkHarness();
  });

  tearDown(() {
    harness.dispose();
  });

  group('Benchmark: Node Startup Timing', () {
    test('B1: Cold start emits TIME_TO_ONLINE_BADGE', () async {
      final bridge = LifecycleBridge();
      final service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: InMemoryInboxStagingRepository(),
      );

      bridge.phase = 'startup';

      final events = await harness.captureFlowEvents(() async {
        await service.startNodeCore(testBase64Key, testPeerId);
      });

      final badge = harness.filterEvents(events, 'TIME_TO_ONLINE_BADGE');
      expect(badge, isNotEmpty);
      final details = badge.first['details'] as Map<String, dynamic>;
      expect(details['totalMs'], isA<int>());
      expect(details['totalMs'], greaterThanOrEqualTo(0));
      expect(details['phase'], 'cold_start');
      expect(details['source'], isA<String>());

      service.dispose();
    });

    test('B2: Cold start with nodeStatusDelay reflects actual wait', () async {
      final bridge = LifecycleBridge();
      bridge.phase = 'degraded'; // Start without relay
      bridge.nodeStatusDelay = const Duration(milliseconds: 50);

      final service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: InMemoryInboxStagingRepository(),
      );

      await service.startNodeCore(testBase64Key, testPeerId);

      // The start response will be degraded, then relay push comes
      final events = await harness.captureFlowEvents(() async {
        bridge.onRelayStateChanged?.call({
          'relayState': 'online',
          'healthyRelayCount': 1,
          'watchdogRestartCount': 0,
          'needsGroupRecovery': false,
        });
        await Future<void>.delayed(Duration.zero);
      });

      final badge = harness.filterEvents(events, 'TIME_TO_ONLINE_BADGE');
      expect(badge, isNotEmpty);
      final details = badge.first['details'] as Map<String, dynamic>;
      expect(details['totalMs'], isA<int>());

      service.dispose();
    });

    test('B3: Cold start respects 6s budget', () async {
      final bridge = LifecycleBridge();
      final service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: InMemoryInboxStagingRepository(),
      );

      bridge.phase = 'startup';

      final events = await harness.captureFlowEvents(() async {
        await service.startNodeCore(testBase64Key, testPeerId);
      });

      final badge = harness.filterEvents(events, 'TIME_TO_ONLINE_BADGE');
      expect(badge, isNotEmpty);

      final totalMs =
          (badge.first['details'] as Map<String, dynamic>)['totalMs'] as int;
      expect(totalMs, lessThan(6000));

      service.dispose();
    });

    test('B4: Hot restart emits with phase=hot_restart', () async {
      final bridge = LifecycleBridge();
      bridge.simulateAlreadyStarted = true;
      bridge.phase = 'online';

      final service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: InMemoryInboxStagingRepository(),
      );

      final events = await harness.captureFlowEvents(() async {
        await service.startNodeCore(testBase64Key, testPeerId);
      });

      final badge = harness.filterEvents(events, 'TIME_TO_ONLINE_BADGE');
      expect(badge, isNotEmpty);
      final details = badge.first['details'] as Map<String, dynamic>;
      expect(details['phase'], 'hot_restart');

      service.dispose();
    });

    test('B5: Source is start_response when start includes relay online',
        () async {
      final bridge = LifecycleBridge();
      final service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: InMemoryInboxStagingRepository(),
      );

      bridge.phase = 'startup';

      final events = await harness.captureFlowEvents(() async {
        await service.startNodeCore(testBase64Key, testPeerId);
      });

      final badge = harness.filterEvents(events, 'TIME_TO_ONLINE_BADGE');
      expect(badge, isNotEmpty);
      final details = badge.first['details'] as Map<String, dynamic>;
      expect(details['source'], 'start_response');

      service.dispose();
    });

    test('B6: Source is relay_state_push when push event wins', () async {
      final bridge = LifecycleBridge();
      bridge.phase = 'degraded'; // Start returns degraded

      final service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: InMemoryInboxStagingRepository(),
      );

      await service.startNodeCore(testBase64Key, testPeerId);

      // Now relay comes online via push
      final events = await harness.captureFlowEvents(() async {
        bridge.onRelayStateChanged?.call({
          'relayState': 'online',
          'healthyRelayCount': 1,
          'watchdogRestartCount': 0,
          'needsGroupRecovery': false,
        });
        await Future<void>.delayed(Duration.zero);
      });

      final badge = harness.filterEvents(events, 'TIME_TO_ONLINE_BADGE');
      expect(badge, isNotEmpty);
      final details = badge.first['details'] as Map<String, dynamic>;
      expect(details['source'], 'relay_state_push');

      service.dispose();
    });
  });
}
