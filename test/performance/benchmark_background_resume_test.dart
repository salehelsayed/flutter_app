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

  Future<List<Map<String, dynamic>>> captureBackgroundResumeEvents() {
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
              phase: 'background_resume',
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

  group('Benchmark: Background Resume Badge', () {
    test(
      'BR1: degraded resume records sendable, relay-ready, and proof-success timings',
      () async {
        await startReadyNode();

        bridge.simulateBackground();
        service.markResumeStarted();

        final events = await captureBackgroundResumeEvents();

        final sendable = _requirePhaseEvent(
          harness,
          events,
          'TIME_TO_SENDABLE_BADGE',
          phase: 'background_resume',
        );
        final relayReady = _requirePhaseEvent(
          harness,
          events,
          'TIME_TO_RELAY_READY_BADGE',
          phase: 'background_resume',
        );
        final firstSend = _requirePhaseEvent(
          harness,
          events,
          'FIRST_SEND_SUCCESS_IN_WINDOW',
          phase: 'background_resume',
        );
        final firstInbox = _requirePhaseEvent(
          harness,
          events,
          'FIRST_INBOX_SUCCESS_IN_WINDOW',
          phase: 'background_resume',
        );

        expect(sendable['proofWindowId'], relayReady['proofWindowId']);
        expect(sendable['proofWindowId'], firstSend['proofWindowId']);
        expect(sendable['proofWindowId'], firstInbox['proofWindowId']);
        expect(
          relayReady['totalMs'] as int,
          greaterThanOrEqualTo(sendable['totalMs'] as int),
        );
        expect(
          sendable['totalMs'] as int,
          greaterThanOrEqualTo(
            [
              firstSend['totalMs'] as int,
              firstInbox['totalMs'] as int,
            ].reduce((a, b) => a > b ? a : b),
          ),
        );
      },
    );

    test(
      'BR2: healthy resume keeps the already-online compatibility signal',
      () async {
        await startReadyNode();

        service.markResumeStarted();
        final events = await harness.captureFlowEvents(() async {
          service.checkResumeAlreadyOnline();
          await Future<void>.delayed(Duration.zero);
        });

        final badge = harness.firstEventDetails(
          events,
          'TIME_TO_ONLINE_BADGE',
          phase: 'background_resume_already_online',
        );
        expect(
          badge,
          isNotNull,
          reason: 'Healthy resume should emit background_resume_already_online',
        );
        expect(badge!['source'], 'resume_check');
      },
    );

    test(
      'BR3: sendable totalMs reflects the actual delay before resume recovery work',
      () async {
        await startReadyNode();

        bridge.simulateBackground();
        service.markResumeStarted();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final events = await captureBackgroundResumeEvents();
        final sendable = _requirePhaseEvent(
          harness,
          events,
          'TIME_TO_SENDABLE_BADGE',
          phase: 'background_resume',
        );
        expect(
          sendable['totalMs'] as int,
          greaterThanOrEqualTo(50),
          reason: 'Sendable timing should include the pre-recovery delay',
        );
      },
    );

    test(
      'BR4: background-resume sendable phase stays distinct from cold-start sendable phase',
      () async {
        bridge.phase = 'startup';
        final coldStartEvents = await harness.captureFlowEventsUntil(
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
        final coldStartSendable = _requirePhaseEvent(
          harness,
          coldStartEvents,
          'TIME_TO_SENDABLE_BADGE',
          phase: 'cold_start',
        );

        bridge.simulateBackground();
        service.markResumeStarted();
        final resumeEvents = await captureBackgroundResumeEvents();
        final resumeSendable = _requirePhaseEvent(
          harness,
          resumeEvents,
          'TIME_TO_SENDABLE_BADGE',
          phase: 'background_resume',
        );

        expect(coldStartSendable['phase'], isNot(resumeSendable['phase']));
      },
    );

    test(
      'BR5: degraded resume emits RELAY_RECOVERY_START with source=resume_trigger',
      () async {
        await startReadyNode();

        bridge.simulateBackground();
        service.markResumeStarted();

        final events = await harness.captureFlowEvents(() async {
          await service.performImmediateHealthCheck();
        });

        final start = harness.firstEventDetails(events, 'RELAY_RECOVERY_START');
        expect(start, isNotNull, reason: 'Should emit RELAY_RECOVERY_START');
        expect(start!['recoverySource'], 'resume_trigger');
        expect(start['resumeToRecoveryStartMs'], isA<int>());
        expect(start['resumeToRecoveryStartMs'], greaterThanOrEqualTo(0));
      },
    );

    test('BR6: healthy resume does not emit RELAY_RECOVERY_START', () async {
      await startReadyNode();

      service.markResumeStarted();
      final events = await harness.captureFlowEvents(() async {
        service.checkResumeAlreadyOnline();
        await Future<void>.delayed(Duration.zero);
      });

      expect(
        harness.filterEvents(events, 'RELAY_RECOVERY_START'),
        isEmpty,
        reason: 'Healthy resume should not start recovery',
      );
    });

    test(
      'BR7: sendable and relay-ready attribution stay distinct from recovery-start source',
      () async {
        await startReadyNode();

        bridge.simulateBackground();
        service.markResumeStarted();

        final events = await captureBackgroundResumeEvents();

        final start = harness.firstEventDetails(events, 'RELAY_RECOVERY_START');
        final sendable = _requirePhaseEvent(
          harness,
          events,
          'TIME_TO_SENDABLE_BADGE',
          phase: 'background_resume',
        );
        final relayReady = _requirePhaseEvent(
          harness,
          events,
          'TIME_TO_RELAY_READY_BADGE',
          phase: 'background_resume',
        );

        expect(start, isNotNull, reason: 'Should emit RELAY_RECOVERY_START');
        expect(start!['recoverySource'], 'resume_trigger');
        expect(sendable['source'], isNot(equals(start['recoverySource'])));
        expect(relayReady['source'], 'relay_state_push');
      },
    );

    test(
      'BR8: degraded resume recovered event exposes Phase 3b foreground attribution',
      () async {
        bridge.useStructuredRecoveryResponse = true;
        bridge.structuredRelayWarmParallelism = 2;
        bridge.structuredForegroundRecoveryPath = 'background_fallback';
        bridge.structuredForegroundRelayDialTimeoutMs = 3000;
        bridge.structuredAutorelayRetryCadenceMs = 1000;

        await startReadyNode();

        bridge.simulateBackground();
        service.markResumeStarted();

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

        expect(recovered, isNotEmpty, reason: 'Should emit recovered outage');
        final details = recovered.first['details'] as Map<String, dynamic>;
        expect(details['relayWarmParallelism'], 2);
        expect(details['foregroundRecoveryPath'], 'background_fallback');
        expect(details['foregroundRelayDialTimeoutMs'], 3000);
        expect(details['autorelayRetryCadenceMs'], 1000);
        expect(details['circuitAddressWaitMs'], isA<int>());
      },
    );
  });
}
