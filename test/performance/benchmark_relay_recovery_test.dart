import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_test/flutter_test.dart';

import '../shared/fakes/in_memory_inbox_staging_repository.dart';
import '../shared/fakes/lifecycle_bridge.dart';
import 'benchmark_harness.dart';

Map<String, dynamic> _requirePhaseEvent(
  BenchmarkHarness harness,
  List<Map<String, dynamic>> events,
  String eventName, {
  required String phase,
}) {
  final details = harness.firstEventDetails(events, eventName, phase: phase);
  expect(details, isNotNull, reason: 'Missing $eventName for phase=$phase');
  return details!;
}

void main() {
  late BenchmarkHarness harness;
  late LifecycleBridge bridge;
  late P2PServiceImpl service;

  Future<void> startReadyNode() async {
    bridge.phase = 'startup';
    await harness.captureFlowEventsUntil(
      () => service.startNode(testBase64Key, testPeerId),
      postActionTimeout: const Duration(milliseconds: 100),
      until: (captured) {
        return harness.firstEventDetails(
              captured,
              'TIME_TO_RELAY_READY_BADGE',
              phase: 'cold_start',
            ) !=
            null;
      },
    );
  }

  Future<List<Map<String, dynamic>>> captureRelayRecoveryEvents() {
    return harness.captureFlowEventsUntil(
      () async {
        await service.performImmediateHealthCheck();
        await service.drainOfflineInbox();
        bridge.simulateRecoveryComplete();
        await Future<void>.delayed(Duration.zero);
      },
      postActionTimeout: const Duration(milliseconds: 100),
      until: (captured) {
        return harness.firstEventDetails(
              captured,
              'TIME_TO_RELAY_READY_BADGE',
              phase: 'recovery',
            ) !=
            null;
      },
    );
  }

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
    test(
      'C1: relay recovery emits both detected and recovered outage phases',
      () async {
        await startReadyNode();

        bridge.simulateBackground();
        final events = await captureRelayRecoveryEvents();

        final outageEvents = harness.filterEvents(
          events,
          'RELAY_OUTAGE_TIMING',
        );
        expect(outageEvents, isNotEmpty, reason: 'Should emit outage timing');

        final detected = outageEvents.where((event) {
          final details = event['details'] as Map<String, dynamic>;
          return details['phase'] == 'detected';
        }).toList();
        final recovered = outageEvents.where((event) {
          final details = event['details'] as Map<String, dynamic>;
          return details['phase'] == 'recovered';
        }).toList();

        expect(detected, isNotEmpty, reason: 'Should emit detected outage');
        expect(recovered, isNotEmpty, reason: 'Should emit recovered outage');
      },
    );

    test('C2: detection source is push for relay:state event', () async {
      await startReadyNode();

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

      final outageEvents = harness.filterEvents(events, 'RELAY_OUTAGE_TIMING');
      final detected = outageEvents.where((event) {
        final details = event['details'] as Map<String, dynamic>;
        return details['phase'] == 'detected';
      }).toList();
      expect(detected, isNotEmpty);

      final details = detected.first['details'] as Map<String, dynamic>;
      expect(details['detectionSource'], 'push');
    });

    test('C3: detection source is poll for health-check recovery', () async {
      await startReadyNode();

      bridge.simulateBackground();
      final events = await harness.captureFlowEvents(() async {
        await service.performImmediateHealthCheck();
      });

      final outageEvents = harness.filterEvents(events, 'RELAY_OUTAGE_TIMING');
      final detected = outageEvents.where((event) {
        final details = event['details'] as Map<String, dynamic>;
        return details['phase'] == 'detected';
      }).toList();
      expect(detected, isNotEmpty);

      final details = detected.first['details'] as Map<String, dynamic>;
      expect(details['detectionSource'], 'poll');
    });

    test(
      'C4: recovery emits sendable and dotted-badge metrics with phase=recovery',
      () async {
        await startReadyNode();

        bridge.simulateBackground();
        final events = await captureRelayRecoveryEvents();

        final sendable = _requirePhaseEvent(
          harness,
          events,
          'TIME_TO_SENDABLE_BADGE',
          phase: 'recovery',
        );
        final relayReady = _requirePhaseEvent(
          harness,
          events,
          'TIME_TO_RELAY_READY_BADGE',
          phase: 'recovery',
        );

        expect(sendable['proofWindowId'], relayReady['proofWindowId']);
        expect(sendable['totalMs'], isA<int>());
        expect(relayReady['totalMs'], isA<int>());
      },
    );

    test('C5: repeated recovery cycles use distinct proof windows', () async {
      await startReadyNode();

      bridge.simulateBackground();
      final cycle1Events = await captureRelayRecoveryEvents();
      final cycle1Sendable = _requirePhaseEvent(
        harness,
        cycle1Events,
        'TIME_TO_SENDABLE_BADGE',
        phase: 'recovery',
      );

      bridge.simulateBackground();
      final cycle2Events = await captureRelayRecoveryEvents();
      final cycle2Sendable = _requirePhaseEvent(
        harness,
        cycle2Events,
        'TIME_TO_SENDABLE_BADGE',
        phase: 'recovery',
      );

      expect(
        cycle1Sendable['proofWindowId'],
        isNot(equals(cycle2Sendable['proofWindowId'])),
      );
    });

    test(
      'C6: recovery exposes a non-negative sendable-to-relay-ready gap',
      () async {
        await startReadyNode();

        bridge.simulateBackground();
        final events = await captureRelayRecoveryEvents();

        final sendable = _requirePhaseEvent(
          harness,
          events,
          'TIME_TO_SENDABLE_BADGE',
          phase: 'recovery',
        );
        final relayReady = _requirePhaseEvent(
          harness,
          events,
          'TIME_TO_RELAY_READY_BADGE',
          phase: 'recovery',
        );

        final gapMs =
            (relayReady['totalMs'] as int) - (sendable['totalMs'] as int);
        expect(gapMs, greaterThanOrEqualTo(0));
      },
    );

    test(
      'C7: recovered outage exposes Phase 3b foreground attribution',
      () async {
        bridge.useStructuredRecoveryResponse = true;
        bridge.structuredRelayWarmParallelism = 2;
        bridge.structuredForegroundRecoveryPath = 'foreground_success';
        bridge.structuredForegroundRelayDialTimeoutMs = 3000;
        bridge.structuredAutorelayRetryCadenceMs = 1000;

        await startReadyNode();

        bridge.simulateBackground();
        final events = await harness.captureFlowEvents(() async {
          await service.performImmediateHealthCheck();
        });

        final outageEvents = harness.filterEvents(
          events,
          'RELAY_OUTAGE_TIMING',
        );
        final recovered = outageEvents.where((event) {
          final details = event['details'] as Map<String, dynamic>;
          return details['phase'] == 'recovered';
        }).toList();

        expect(
          recovered,
          isNotEmpty,
          reason: 'Should emit recovered outage event',
        );
        final details = recovered.first['details'] as Map<String, dynamic>;
        expect(details['relayWarmParallelism'], 2);
        expect(details['foregroundRecoveryPath'], 'foreground_success');
        expect(details['foregroundRelayDialTimeoutMs'], 3000);
        expect(details['autorelayRetryCadenceMs'], 1000);
        expect(details['circuitAddressWaitMs'], isA<int>());
      },
    );
  });
}
