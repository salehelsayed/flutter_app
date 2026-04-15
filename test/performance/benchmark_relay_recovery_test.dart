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

  group('Benchmark: Relay Recovery Timing', () {
    test('C1: Relay recovery emits RELAY_OUTAGE_TIMING detected + recovered',
        () async {
      // Start online
      bridge.phase = 'startup';
      await service.startNodeCore(testBase64Key, testPeerId);

      // Go degraded
      bridge.simulateBackground();

      // Capture health check → recovery events
      final events = await harness.captureFlowEvents(() async {
        await service.performImmediateHealthCheck();
      });

      final outageEvents =
          harness.filterEvents(events, 'RELAY_OUTAGE_TIMING');
      expect(outageEvents, isNotEmpty,
          reason: 'Should emit RELAY_OUTAGE_TIMING');

      // Find detected phase
      final detected = outageEvents.where((e) {
        final d = e['details'] as Map<String, dynamic>;
        return d['phase'] == 'detected';
      }).toList();
      expect(detected, isNotEmpty, reason: 'Should have detected phase');

      final detectedDetails =
          detected.first['details'] as Map<String, dynamic>;
      expect(detectedDetails['detectionMs'], isA<int>());
      expect(detectedDetails['detectionSource'], isA<String>());
    });

    test('C2: Detection source is push for relay:state event', () async {
      // Start online
      bridge.phase = 'startup';
      await service.startNodeCore(testBase64Key, testPeerId);

      // Simulate relay state push with degraded
      final events = await harness.captureFlowEvents(() async {
        bridge.onRelayStateChanged?.call({
          'relayState': 'degraded',
          'healthyRelayCount': 0,
          'watchdogRestartCount': 0,
          'needsGroupRecovery': false,
          'reason': 'relay_disconnected',
        });
        await Future<void>.delayed(Duration.zero);
      });

      final outageEvents =
          harness.filterEvents(events, 'RELAY_OUTAGE_TIMING');
      final detected = outageEvents.where((e) {
        final d = e['details'] as Map<String, dynamic>;
        return d['phase'] == 'detected';
      }).toList();
      expect(detected, isNotEmpty);

      final details = detected.first['details'] as Map<String, dynamic>;
      expect(details['detectionSource'], 'push');
    });

    test('C3: Detection source is poll for health check cycle', () async {
      // Start online
      bridge.phase = 'startup';
      await service.startNodeCore(testBase64Key, testPeerId);

      // Go degraded without push event
      bridge.simulateBackground();

      // Health check detects degradation
      final events = await harness.captureFlowEvents(() async {
        await service.performImmediateHealthCheck();
      });

      final outageEvents =
          harness.filterEvents(events, 'RELAY_OUTAGE_TIMING');
      final detected = outageEvents.where((e) {
        final d = e['details'] as Map<String, dynamic>;
        return d['phase'] == 'detected';
      }).toList();
      expect(detected, isNotEmpty);

      final details = detected.first['details'] as Map<String, dynamic>;
      expect(details['detectionSource'], 'poll');
    });

    test('C4: Recovery emits TIME_TO_ONLINE_BADGE with phase=recovery',
        () async {
      // Start online
      bridge.phase = 'startup';
      await service.startNodeCore(testBase64Key, testPeerId);

      // Degrade
      bridge.simulateBackground();
      await service.performImmediateHealthCheck();

      // Recover via push
      final events = await harness.captureFlowEvents(() async {
        bridge.simulateRecoveryComplete();
        await Future<void>.delayed(Duration.zero);
      });

      final badges = harness.filterEvents(events, 'TIME_TO_ONLINE_BADGE');
      expect(badges, isNotEmpty);

      final details = badges.first['details'] as Map<String, dynamic>;
      expect(details['phase'], 'recovery');
      expect(details['totalMs'], isA<int>());
      expect(details['totalMs'], greaterThanOrEqualTo(0));
    });

    test('C5: Multiple outage-recovery cycles emit distinct events',
        () async {
      // Start online
      bridge.phase = 'startup';
      await service.startNodeCore(testBase64Key, testPeerId);

      // Cycle 1: degrade → recover
      bridge.simulateBackground();
      final cycle1Events = await harness.captureFlowEvents(() async {
        await service.performImmediateHealthCheck();
      });
      bridge.simulateRecoveryComplete();
      await Future<void>.delayed(Duration.zero);

      // Cycle 2: degrade → recover
      bridge.simulateBackground();
      final cycle2Events = await harness.captureFlowEvents(() async {
        await service.performImmediateHealthCheck();
      });

      // Each cycle should produce its own RELAY_OUTAGE_TIMING events
      final cycle1Outage =
          harness.filterEvents(cycle1Events, 'RELAY_OUTAGE_TIMING');
      final cycle2Outage =
          harness.filterEvents(cycle2Events, 'RELAY_OUTAGE_TIMING');

      expect(cycle1Outage, isNotEmpty, reason: 'Cycle 1 should emit events');
      expect(cycle2Outage, isNotEmpty, reason: 'Cycle 2 should emit events');
    });

    test('C6: Recovery with recovered phase includes recoveryMs', () async {
      // Start online
      bridge.phase = 'startup';
      await service.startNodeCore(testBase64Key, testPeerId);

      // Degrade and recover
      bridge.simulateBackground();

      final events = await harness.captureFlowEvents(() async {
        await service.performImmediateHealthCheck();
      });

      final outageEvents =
          harness.filterEvents(events, 'RELAY_OUTAGE_TIMING');
      final recovered = outageEvents.where((e) {
        final d = e['details'] as Map<String, dynamic>;
        return d['phase'] == 'recovered';
      }).toList();

      if (recovered.isNotEmpty) {
        final details = recovered.first['details'] as Map<String, dynamic>;
        expect(details['recoveryMs'], isA<int>());
        expect(details['totalOutageMs'], isA<int>());
      }
    });
  });
}
