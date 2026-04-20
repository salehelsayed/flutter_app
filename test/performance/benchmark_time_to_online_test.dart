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

  group('Benchmark: Time-to-Sendable Badge', () {
    test(
      'M1: cold start emits sendable and dotted-badge metrics in one proof window',
      () async {
        bridge.phase = 'startup';

        final events = await harness.captureFlowEventsUntil(
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

        final sendable = _requirePhaseEvent(
          harness,
          events,
          'TIME_TO_SENDABLE_BADGE',
          phase: 'cold_start',
        );
        final relayReady = _requirePhaseEvent(
          harness,
          events,
          'TIME_TO_RELAY_READY_BADGE',
          phase: 'cold_start',
        );

        expect(sendable['proofWindowId'], relayReady['proofWindowId']);
        expect(sendable['totalMs'], isA<int>());
        expect(relayReady['totalMs'], isA<int>());
        expect(sendable['sendProofSource'], isA<String>());
        expect(sendable['inboxProofSource'], isA<String>());
      },
    );

    test(
      'M2: recovery can reach sendable before the relay-ready dotted upgrade',
      () async {
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

        bridge.simulateBackground();

        final events = await harness.captureFlowEventsUntil(
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
        expect(
          (sendable['totalMs'] as int),
          lessThanOrEqualTo(relayReady['totalMs'] as int),
        );
      },
    );

    test(
      'M3: hot restart emits sendable and dotted-badge metrics with phase=hot_restart',
      () async {
        bridge.simulateAlreadyStarted = true;
        bridge.phase = 'online';

        final events = await harness.captureFlowEventsUntil(
          () => service.startNode(testBase64Key, testPeerId),
          postActionTimeout: const Duration(milliseconds: 100),
          until: (captured) {
            return harness.firstEventDetails(
                  captured,
                  'TIME_TO_RELAY_READY_BADGE',
                  phase: 'hot_restart',
                ) !=
                null;
          },
        );

        final sendable = _requirePhaseEvent(
          harness,
          events,
          'TIME_TO_SENDABLE_BADGE',
          phase: 'hot_restart',
        );
        final relayReady = _requirePhaseEvent(
          harness,
          events,
          'TIME_TO_RELAY_READY_BADGE',
          phase: 'hot_restart',
        );

        expect(sendable['proofWindowId'], relayReady['proofWindowId']);
        expect(sendable['totalMs'], isA<int>());
        expect(relayReady['totalMs'], isA<int>());
      },
    );

    test('M4: sendable event keeps proof-source attribution', () async {
      bridge.phase = 'startup';

      final events = await harness.captureFlowEventsUntil(
        () => service.startNode(testBase64Key, testPeerId),
        postActionTimeout: const Duration(milliseconds: 100),
        until: (captured) {
          return harness.firstEventDetails(
                captured,
                'TIME_TO_SENDABLE_BADGE',
                phase: 'cold_start',
              ) !=
              null;
        },
      );

      final sendable = _requirePhaseEvent(
        harness,
        events,
        'TIME_TO_SENDABLE_BADGE',
        phase: 'cold_start',
      );
      expect(sendable['source'], isA<String>());
      expect(sendable['sendProofSource'], isA<String>());
      expect(sendable['inboxProofSource'], isA<String>());
    });

    test(
      'M5: relay-ready attribution stays distinct when a relay-state push wins later',
      () async {
        bridge.phase = 'degraded';

        final events = await harness.captureFlowEventsUntil(
          () async {
            await service.startNode(testBase64Key, testPeerId);
            await Future<void>.delayed(const Duration(milliseconds: 10));
            bridge.onRelayStateChanged?.call({
              'relayState': 'online',
              'healthyRelayCount': 1,
              'watchdogRestartCount': 0,
              'needsGroupRecovery': false,
              'reason': 'relay_connected',
            });
            await Future<void>.delayed(Duration.zero);
          },
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

        final sendable = _requirePhaseEvent(
          harness,
          events,
          'TIME_TO_SENDABLE_BADGE',
          phase: 'cold_start',
        );
        final relayReady = _requirePhaseEvent(
          harness,
          events,
          'TIME_TO_RELAY_READY_BADGE',
          phase: 'cold_start',
        );

        expect(relayReady['source'], 'relay_state_push');
        expect(relayReady['proofWindowId'], sendable['proofWindowId']);
        expect(relayReady['source'], isNot(equals(sendable['source'])));
      },
    );

    test('M6: cold-start sendable metric stays under the 6s budget', () async {
      bridge.phase = 'startup';

      final events = await harness.captureFlowEventsUntil(
        () => service.startNode(testBase64Key, testPeerId),
        postActionTimeout: const Duration(milliseconds: 100),
        until: (captured) {
          return harness.firstEventDetails(
                captured,
                'TIME_TO_SENDABLE_BADGE',
                phase: 'cold_start',
              ) !=
              null;
        },
      );

      final sendable = _requirePhaseEvent(
        harness,
        events,
        'TIME_TO_SENDABLE_BADGE',
        phase: 'cold_start',
      );
      final totalMs = sendable['totalMs'] as int;
      expect(
        totalMs,
        lessThan(6000),
        reason: 'Cold-start sendable badge should be under 6s',
      );

      final values = <int>[totalMs]..sort();
      final line = harness.formatBenchmarkLine(
        'time_to_sendable_cold_start',
        p50: harness.percentile(values, 50),
        p95: harness.percentile(values, 95),
        n: values.length,
      );
      // ignore: avoid_print
      print(line);
    });
  });
}
