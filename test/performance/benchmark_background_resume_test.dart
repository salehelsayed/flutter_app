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

  group('Benchmark: Background Resume Badge', () {
    test(
      'BR1: background_resume phase emitted after pause-resume-relay cycle',
      () async {
        // Start online (cold start fires)
        bridge.phase = 'startup';
        await service.startNodeCore(testBase64Key, testPeerId);

        // Simulate background: relay drops, circuit addresses disappear
        bridge.simulateBackground();
        await service.performImmediateHealthCheck();

        // Mark resume and capture events during recovery
        service.markResumeStarted();
        final events = await harness.captureFlowEvents(() async {
          bridge.simulateRecoveryComplete();
          await Future<void>.delayed(Duration.zero);
        });

        final badges = harness.filterEvents(events, 'TIME_TO_ONLINE_BADGE');
        expect(badges, isNotEmpty, reason: 'Should emit TIME_TO_ONLINE_BADGE');

        final details = badges.first['details'] as Map<String, dynamic>;
        expect(details['totalMs'], isA<int>());
        expect(details['totalMs'], greaterThanOrEqualTo(0));
        expect(details['phase'], 'background_resume');
        expect(
          details['source'],
          isA<String>(),
          reason: 'source should track delivery path',
        );
      },
    );

    test(
      'BR2: background_resume_already_online when relay stayed healthy',
      () async {
        // Start online
        bridge.phase = 'startup';
        await service.startNodeCore(testBase64Key, testPeerId);

        // Mark resume without simulating degradation (relay stayed healthy)
        service.markResumeStarted();

        final events = await harness.captureFlowEvents(() async {
          service.checkResumeAlreadyOnline();
          await Future<void>.delayed(Duration.zero);
        });

        final badges = harness.filterEvents(events, 'TIME_TO_ONLINE_BADGE');
        expect(
          badges,
          isNotEmpty,
          reason: 'Should emit TIME_TO_ONLINE_BADGE for already-online case',
        );

        final details = badges.first['details'] as Map<String, dynamic>;
        expect(details['totalMs'], isA<int>());
        expect(details['totalMs'], greaterThanOrEqualTo(0));
        expect(details['phase'], 'background_resume_already_online');
        expect(details['source'], 'resume_check');
      },
    );

    test(
      'BR3: totalMs reflects actual delay when relay reconnects during resume',
      () async {
        // Start online
        bridge.phase = 'startup';
        await service.startNodeCore(testBase64Key, testPeerId);

        // Simulate background
        bridge.simulateBackground();
        await service.performImmediateHealthCheck();

        // Mark resume start, then wait before recovery
        service.markResumeStarted();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final events = await harness.captureFlowEvents(() async {
          bridge.simulateRecoveryComplete();
          await Future<void>.delayed(Duration.zero);
        });

        final badges = harness.filterEvents(events, 'TIME_TO_ONLINE_BADGE');
        expect(badges, isNotEmpty);

        final totalMs =
            (badges.first['details'] as Map<String, dynamic>)['totalMs'] as int;
        expect(
          totalMs,
          greaterThanOrEqualTo(50),
          reason: 'totalMs should reflect the delay between resume and online',
        );
      },
    );

    test(
      'BR4: resume badge is distinct from cold-start badge (no double-emit)',
      () async {
        // Cold start
        bridge.phase = 'startup';
        final coldStartEvents = await harness.captureFlowEvents(() async {
          await service.startNodeCore(testBase64Key, testPeerId);
        });

        final coldStartBadges =
            harness.filterEvents(coldStartEvents, 'TIME_TO_ONLINE_BADGE');
        expect(coldStartBadges, isNotEmpty, reason: 'Should emit cold start');
        final coldStartDetails =
            coldStartBadges.first['details'] as Map<String, dynamic>;
        expect(coldStartDetails['phase'], 'cold_start');

        // Simulate background + resume + recovery
        bridge.simulateBackground();
        await service.performImmediateHealthCheck();

        service.markResumeStarted();
        final resumeEvents = await harness.captureFlowEvents(() async {
          bridge.simulateRecoveryComplete();
          await Future<void>.delayed(Duration.zero);
        });

        final resumeBadges =
            harness.filterEvents(resumeEvents, 'TIME_TO_ONLINE_BADGE');
        expect(resumeBadges, isNotEmpty, reason: 'Should emit resume badge');
        final resumeDetails =
            resumeBadges.first['details'] as Map<String, dynamic>;
        expect(resumeDetails['phase'], 'background_resume');

        // Verify they are distinct phases
        expect(
          coldStartDetails['phase'],
          isNot(equals(resumeDetails['phase'])),
          reason: 'Cold start and resume badges should have different phases',
        );
      },
    );
  });
}
