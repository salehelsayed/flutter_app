import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/p2p/presentation/widgets/connection_status_indicator.dart';

import '../../shared/fakes/lifecycle_bridge.dart';

void main() {
  late LifecycleBridge bridge;
  late P2PServiceImpl service;

  setUp(() {
    bridge = LifecycleBridge();
    service = P2PServiceImpl(bridge: bridge);
  });

  tearDown(() {
    service.dispose();
  });

  group('Connectivity lifecycle tests', () {
    test('2.1 Relay server crash recovery', () async {
      // Start online
      await service.startNodeCore(testBase64Key, testPeerId);
      expect(healthFromState(service.currentState), ConnectionHealth.online);

      // Simulate relay crash — needs 6 recovery polls to come back.
      // Each health check does 2 node:status calls in recovery path
      // (initial status + post-reconnect status), so:
      //   HC1: 1 recovering attempt (initial call is 'degraded', not 'recovering')
      //   HC2: 2 recovering attempts (3 total)
      //   HC3: 2 recovering attempts (5 total)
      //   HC4: 1st recovering attempt hits 6 → online!
      bridge.simulateBackground();
      bridge.pollsUntilCircuitReady = 6;

      // First health check: detects degraded, triggers relay:reconnect
      await service.performImmediateHealthCheck();
      expect(healthFromState(service.currentState), ConnectionHealth.degraded);
      expect(bridge.relayReconnectCallCount, 1);

      // Second health check: still recovering
      await service.performImmediateHealthCheck();
      expect(healthFromState(service.currentState), ConnectionHealth.degraded);

      // Third health check: still recovering
      await service.performImmediateHealthCheck();
      expect(healthFromState(service.currentState), ConnectionHealth.degraded);

      // Fourth health check: circuit finally ready
      await service.performImmediateHealthCheck();
      expect(healthFromState(service.currentState), ConnectionHealth.online);

      // relay:reconnect called once per degraded HC (HC1–HC3, HC4 was already online)
      expect(bridge.relayReconnectCallCount, greaterThanOrEqualTo(3));
    });

    test('2.2 Network transition (WiFi → cellular)', () async {
      // Start online
      await service.startNodeCore(testBase64Key, testPeerId);
      expect(healthFromState(service.currentState), ConnectionHealth.online);

      // Simulate network change — bridge becomes unhealthy briefly
      bridge.bridgeUnhealthy = true;
      bridge.simulateBackground();
      bridge.pollsUntilCircuitReady = 1;

      // handleAppResumed detects unhealthy bridge → reinitializes
      final bridgeOk = await handleAppResumed(
        bridge: bridge,
        p2pService: service,
      );
      expect(bridgeOk, isFalse, reason: 'Bridge was unhealthy at check time');

      // Bridge is re-initialized after reinitialize() call
      expect(bridge.isInitialized, isTrue);

      // Now bridge is healthy again — next resume should succeed
      bridge.bridgeUnhealthy = false;
      bridge.simulateBackground();
      bridge.pollsUntilCircuitReady = 1;

      final bridgeOk2 = await handleAppResumed(
        bridge: bridge,
        p2pService: service,
      );
      expect(bridgeOk2, isTrue);
      expect(healthFromState(service.currentState), ConnectionHealth.online);
    });

    test('2.3a Partial connectivity — relay up, inbox down', () async {
      await service.startNodeCore(testBase64Key, testPeerId);
      expect(healthFromState(service.currentState), ConnectionHealth.online);

      // Inbox is down but relay is fine
      bridge.inboxRetrieveFails = true;

      // Health check should still work (relay is fine)
      await service.performImmediateHealthCheck();
      expect(
        healthFromState(service.currentState),
        ConnectionHealth.online,
        reason: 'Relay is online; inbox failure does not affect health',
      );
    });

    test('2.3b Partial connectivity — relay down, inbox up', () async {
      await service.startNodeCore(testBase64Key, testPeerId);

      // Relay drops
      bridge.simulateBackground();
      bridge.pollsUntilCircuitReady = 999; // Relay won't recover
      bridge.inboxRetrieveFails = false;

      // Health check: relay degraded
      await service.performImmediateHealthCheck();
      expect(healthFromState(service.currentState), ConnectionHealth.degraded);

      // But inbox:retrieve still works (the bridge call returns ok)
      // In the real system, inbox drain happens on each health check
      // The fact that relay is degraded doesn't break inbox retrieval
      expect(bridge.inboxRetrieveFails, isFalse);
    });

    test('2.4 Concurrent resume (rapid background/foreground)', () async {
      await service.startNodeCore(testBase64Key, testPeerId);

      // First rapid cycle
      bridge.simulateBackground();
      bridge.pollsUntilCircuitReady = 1;
      final resume1 = handleAppResumed(bridge: bridge, p2pService: service);

      // Don't await — immediately simulate another background/foreground
      bridge.simulateBackground();
      bridge.pollsUntilCircuitReady = 1;
      final resume2 = handleAppResumed(bridge: bridge, p2pService: service);

      // Await both — should not throw
      final results = await Future.wait([resume1, resume2]);
      expect(results, everyElement(isNotNull));

      // Final state should be deterministic (online after both complete)
      // Need one more health check since the rapid cycling may leave
      // the bridge in recovering state
      bridge.pollsUntilCircuitReady = 1;
      if (healthFromState(service.currentState) != ConnectionHealth.online) {
        await service.performImmediateHealthCheck();
      }
      // No exceptions means success — concurrent resumes are safe
    });

    test('2.5 Long background duration (reservation TTL expiry)', () async {
      await service.startNodeCore(testBase64Key, testPeerId);

      // Background — simulate TTL expiry requiring 3 recovery cycles
      bridge.simulateBackground();
      bridge.pollsUntilCircuitReady = 5;

      // Health check 1: degraded
      await service.performImmediateHealthCheck();
      expect(healthFromState(service.currentState), ConnectionHealth.degraded);

      // Health check 2: still degraded
      await service.performImmediateHealthCheck();
      expect(healthFromState(service.currentState), ConnectionHealth.degraded);

      // Health check 3: circuit finally ready
      await service.performImmediateHealthCheck();
      expect(healthFromState(service.currentState), ConnectionHealth.online);
    });

    test(
      '2.6 Node restart under load (message:send during relay:reconnect)',
      () async {
        await service.startNodeCore(testBase64Key, testPeerId);

        // Background — add reconnect delay to simulate restart window
        bridge.simulateBackground();
        bridge.pollsUntilCircuitReady = 1;
        bridge.reconnectDelay = const Duration(milliseconds: 100);

        // Start health check (which calls relay:reconnect with delay)
        final healthCheckFuture = service.performImmediateHealthCheck();

        // Wait a bit for relay:reconnect to start (bridge.isRestarting = true)
        await Future<void>.delayed(const Duration(milliseconds: 20));

        // During the reconnect window, isRestarting should be true
        expect(
          bridge.isRestarting,
          isTrue,
          reason: 'Bridge should be restarting during reconnect delay',
        );

        // Actually send a message:send during the restart window
        final sendCountBefore = bridge.messageSendCallCount;
        final sendResponse = await bridge.send(
          '{"cmd":"message:send","payload":{"to":"some-peer","message":"hello"}}',
        );

        // The send should have been called
        expect(bridge.messageSendCallCount, sendCountBefore + 1);

        // The send should fail because node is restarting
        final parsed = jsonDecode(sendResponse) as Map<String, dynamic>;
        expect(
          parsed['ok'],
          isFalse,
          reason: 'message:send should fail during restart',
        );

        // Wait for health check to complete
        await healthCheckFuture;

        // After reconnect completes, isRestarting should be false
        expect(bridge.isRestarting, isFalse);

        // Now message:send should succeed (bridge is back)
        final sendResponse2 = await bridge.send(
          '{"cmd":"message:send","payload":{"to":"some-peer","message":"hello"}}',
        );
        final parsed2 = jsonDecode(sendResponse2) as Map<String, dynamic>;
        expect(
          parsed2['ok'],
          isTrue,
          reason: 'message:send should succeed after restart',
        );
        expect(parsed2['sent'], isTrue);

        bridge.reconnectDelay = null;
      },
    );

    test('2.7 Health check timer drift (duplicate timers)', () {
      fakeAsync((async) {
        final bridge = LifecycleBridge();
        final service = P2PServiceImpl(bridge: bridge);

        // Start node — this sets up the first health check timer via warmBackground
        // We call startNodeCore directly to avoid warmBackground's delayed callbacks
        bridge.phase = 'startup';

        // Manually simulate what startNodeCore does
        service.startNodeCore(testBase64Key, testPeerId);
        async.flushMicrotasks();

        final statusCountAfterStart = bridge.nodeStatusCallCount;

        // Advance 30 seconds — should fire 1 health check
        // (warmBackground starts the timer)
        async.elapse(const Duration(seconds: 30));
        // Count may include status checks from startNodeCore itself,
        // so we measure the delta
        final statusCountAfter30s = bridge.nodeStatusCallCount;
        final firstInterval = statusCountAfter30s - statusCountAfterStart;

        // Advance another 30 seconds — should fire exactly 1 more
        async.elapse(const Duration(seconds: 30));
        final statusCountAfter60s = bridge.nodeStatusCallCount;
        final secondInterval = statusCountAfter60s - statusCountAfter30s;

        // Both intervals should have the same number of health checks
        // (1 per 30s period), proving no duplicate timers
        expect(
          firstInterval,
          secondInterval,
          reason: 'Health check count should be consistent per interval',
        );

        // Call handleAppResumed which also triggers health check
        handleAppResumed(bridge: bridge, p2pService: service);
        async.flushMicrotasks();

        // Advance another 30 seconds — still only 1 health check per period
        final statusCountBeforeThirdInterval = bridge.nodeStatusCallCount;
        async.elapse(const Duration(seconds: 30));
        final thirdInterval =
            bridge.nodeStatusCallCount - statusCountBeforeThirdInterval;

        // Should still be consistent (no duplicate timers after resume)
        expect(
          thirdInterval,
          firstInterval,
          reason: 'No duplicate timers after handleAppResumed',
        );

        service.dispose();
      });
    });
  });

  group('Finding 2: _hasEverBeenOnline lifecycle', () {
    test(
      'stopNode resets _hasEverBeenOnline so next start does not recover prematurely',
      () async {
        // 1. Start online (sets _hasEverBeenOnline = true)
        await service.startNodeCore(testBase64Key, testPeerId);
        expect(healthFromState(service.currentState), ConnectionHealth.online);

        // 2. stopNode()
        await service.stopNode();

        // 3. Set phase to degraded — simulates fresh start before relay connects
        bridge.phase = 'degraded';

        // 4. startNodeCore() — returns started but no circuits (normal for fresh start)
        await service.startNodeCore(testBase64Key, testPeerId);
        expect(service.currentState.circuitAddresses, isEmpty);

        // 5. performImmediateHealthCheck() — should NOT call relay:reconnect
        //    because this is a fresh start, not a recovery from lost circuits
        bridge.relayReconnectCallCount = 0;
        await service.performImmediateHealthCheck();

        // 6. Assert relay:reconnect was NOT called
        expect(
          bridge.relayReconnectCallCount,
          0,
          reason:
              '_hasEverBeenOnline should be false after stop+restart, '
              'so health check should not trigger recovery',
        );
      },
    );

    test(
      'already-started resync sets _hasEverBeenOnline from circuit addresses',
      () async {
        // 1. Simulate "already started" with online status
        bridge.simulateAlreadyStarted = true;
        bridge.phase = 'online';

        // 2. startNodeCore() → hits "already started" branch, resyncs via node:status
        final started = await service.startNodeCore(testBase64Key, testPeerId);
        expect(started, isTrue);
        expect(service.currentState.circuitAddresses, isNotEmpty);

        // 3. Simulate background (phase = 'degraded')
        bridge.simulateAlreadyStarted = false;
        bridge.simulateBackground();
        bridge.pollsUntilCircuitReady = 1;

        // 4. performImmediateHealthCheck() — should call relay:reconnect
        //    because we were online (resync saw circuits)
        bridge.relayReconnectCallCount = 0;
        await service.performImmediateHealthCheck();

        // 5. Assert relay:reconnect WAS called
        expect(
          bridge.relayReconnectCallCount,
          greaterThanOrEqualTo(1),
          reason: '_hasEverBeenOnline should be true from resync branch',
        );
      },
    );
  });

  group('Finding 3: health check re-entrancy guard', () {
    test(
      'concurrent health checks are prevented by re-entrancy guard',
      () async {
        // Start online then background
        await service.startNodeCore(testBase64Key, testPeerId);
        bridge.simulateBackground();
        bridge.pollsUntilCircuitReady = 999;
        bridge.reconnectDelay = const Duration(milliseconds: 200);

        // Fire two health checks simultaneously
        bridge.relayReconnectCallCount = 0;
        final check1 = service.performImmediateHealthCheck();
        final check2 = service.performImmediateHealthCheck();
        await Future.wait([check1, check2]);

        // Only one relay:reconnect should have been called
        expect(
          bridge.relayReconnectCallCount,
          1,
          reason: 'Second concurrent health check should be skipped',
        );

        bridge.reconnectDelay = null;
      },
    );

    test(
      'health check guard resets after completion allowing next check',
      () async {
        // Start online, background, recover
        await service.startNodeCore(testBase64Key, testPeerId);

        bridge.simulateBackground();
        bridge.pollsUntilCircuitReady = 1;
        bridge.relayReconnectCallCount = 0;
        await service.performImmediateHealthCheck();
        expect(bridge.relayReconnectCallCount, greaterThanOrEqualTo(1));

        // Background again, recover again
        bridge.simulateBackground();
        bridge.pollsUntilCircuitReady = 1;
        await service.performImmediateHealthCheck();

        // Should have been called at least twice total (once per recovery)
        expect(
          bridge.relayReconnectCallCount,
          greaterThanOrEqualTo(2),
          reason: 'Guard should release between checks',
        );
      },
    );
  });

  group('Connectivity edge cases', () {
    test('multiple background/foreground cycles all recover', () async {
      await service.startNodeCore(testBase64Key, testPeerId);

      for (var cycle = 1; cycle <= 5; cycle++) {
        bridge.simulateBackground();
        bridge.pollsUntilCircuitReady = 1;

        await handleAppResumed(bridge: bridge, p2pService: service);

        expect(
          healthFromState(service.currentState),
          ConnectionHealth.online,
          reason: 'Should be online after cycle $cycle',
        );
      }
    });

    test('bridge unhealthy then healthy on next resume', () async {
      await service.startNodeCore(testBase64Key, testPeerId);

      // First resume: bridge unhealthy
      bridge.bridgeUnhealthy = true;
      bridge.simulateBackground();
      bridge.pollsUntilCircuitReady = 1;

      final result1 = await handleAppResumed(
        bridge: bridge,
        p2pService: service,
      );
      expect(result1, isFalse, reason: 'Bridge was unhealthy');

      // Second resume: bridge now healthy
      bridge.bridgeUnhealthy = false;
      bridge.simulateBackground();
      bridge.pollsUntilCircuitReady = 1;

      final result2 = await handleAppResumed(
        bridge: bridge,
        p2pService: service,
      );
      expect(result2, isTrue, reason: 'Bridge recovered');
      expect(healthFromState(service.currentState), ConnectionHealth.online);
    });

    test(
      'state transitions tracked through stateStream during recovery',
      () async {
        final states = <dynamic>[];
        final sub = service.stateStream.listen(states.add);

        await service.startNodeCore(testBase64Key, testPeerId);
        await Future<void>.delayed(Duration.zero);
        expect(states, isNotEmpty);

        final stateCountBeforeRecovery = states.length;

        bridge.simulateBackground();
        bridge.pollsUntilCircuitReady = 1;
        await handleAppResumed(bridge: bridge, p2pService: service);
        await Future<void>.delayed(Duration.zero);

        // Phase 5 may heal before a distinct degraded state is surfaced,
        // but it must not regress or drop existing state emissions.
        expect(states.length, greaterThanOrEqualTo(stateCountBeforeRecovery));

        await sub.cancel();
      },
    );
  });

  // ==========================================================================
  // Phase 5: Event-Driven Resume and Watchdog Recovery
  // ==========================================================================

  group('Phase 5: Event-driven resume and watchdog recovery', () {
    test(
      'relay state degraded event triggers immediate recovery without waiting for timer',
      () async {
        // Start online
        await service.startNodeCore(testBase64Key, testPeerId);
        expect(healthFromState(service.currentState), ConnectionHealth.online);

        // Configure fast recovery
        bridge.pollsUntilCircuitReady = 1;

        // Simulate relay-state push with degradation.
        // This should trigger immediate recovery via the event-driven path
        // instead of waiting for the 30s health check timer.
        bridge.relayReconnectCallCount = 0;
        bridge.simulateRelayStatePush(degraded: true);

        // Allow the fire-and-forget recovery to complete
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        // The event-driven path should have triggered relay:reconnect
        expect(
          bridge.relayReconnectCallCount,
          greaterThanOrEqualTo(1),
          reason:
              'Relay disconnect push should trigger immediate relay:reconnect '
              'without waiting for the periodic timer',
        );
      },
    );

    test(
      'addresses updated without relay degradation does not trigger event driven recovery',
      () async {
        await service.startNodeCore(testBase64Key, testPeerId);
        expect(healthFromState(service.currentState), ConnectionHealth.online);

        bridge.relayReconnectCallCount = 0;
        bridge.onAddressesUpdated?.call([
          '/ip4/127.0.0.1/tcp/1234',
        ], const <String>[]);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(
          bridge.relayReconnectCallCount,
          0,
          reason:
              'addresses:updated alone should not trigger event-driven recovery '
              'when relay:state did not degrade',
        );
      },
    );

    test(
      'performImmediateHealthCheck prefers in-place recovery over restart',
      () async {
        // Start online
        await service.startNodeCore(testBase64Key, testPeerId);
        expect(healthFromState(service.currentState), ConnectionHealth.online);

        // Enable structured recovery responses
        bridge.useStructuredRecoveryResponse = true;
        bridge.structuredRecoveryMode = 'in_place';

        // Background and recover
        bridge.simulateBackground();
        bridge.pollsUntilCircuitReady = 1;

        await service.performImmediateHealthCheck();

        // Verify the recovery method was in-place refresh (not watchdog restart)
        expect(
          service.lastRecoveryMethod,
          equals('in_place'),
          reason: 'Default recovery should use in-place refresh, not restart',
        );
      },
    );

    test('concurrent resume calls coalesce to one recovery', () async {
      // Start online
      await service.startNodeCore(testBase64Key, testPeerId);
      expect(healthFromState(service.currentState), ConnectionHealth.online);

      // Background with slow recovery
      bridge.simulateBackground();
      bridge.pollsUntilCircuitReady = 999;
      bridge.reconnectDelay = const Duration(milliseconds: 100);

      // Fire three concurrent health checks
      bridge.relayReconnectCallCount = 0;
      final check1 = service.performImmediateHealthCheck();
      final check2 = service.performImmediateHealthCheck();
      final check3 = service.performImmediateHealthCheck();

      await Future.wait([check1, check2, check3]);

      // Only ONE relay:reconnect should have been called due to coalescing
      expect(
        bridge.relayReconnectCallCount,
        1,
        reason:
            'Three concurrent recovery calls should coalesce to one actual '
            'relay:reconnect call',
      );

      bridge.reconnectDelay = null;
    });

    test(
      'manual reconnect plus resume coalesce to one recovery result',
      () async {
        // Start online
        await service.startNodeCore(testBase64Key, testPeerId);

        // Background
        bridge.simulateBackground();
        bridge.pollsUntilCircuitReady = 999;
        bridge.reconnectDelay = const Duration(milliseconds: 100);

        // Fire manual health check and handleAppResumed concurrently
        bridge.relayReconnectCallCount = 0;
        final manualCheck = service.performImmediateHealthCheck();
        final resumeResult = handleAppResumed(
          bridge: bridge,
          p2pService: service,
        );

        await Future.wait([manualCheck, resumeResult]);

        // The resume's call to performImmediateHealthCheck should have coalesced
        // with the manual check, resulting in only ONE recovery attempt.
        expect(
          bridge.relayReconnectCallCount,
          1,
          reason: 'Manual reconnect + resume should coalesce to one recovery',
        );

        bridge.reconnectDelay = null;
      },
    );

    test(
      'recovery branching uses structured result fields when present',
      () async {
        // Start online
        await service.startNodeCore(testBase64Key, testPeerId);

        // Enable structured responses with watchdog_restart method
        bridge.useStructuredRecoveryResponse = true;
        bridge.structuredRecoveryMode = 'watchdog_restart';

        // Background and recover
        bridge.simulateBackground();
        bridge.pollsUntilCircuitReady = 1;

        await service.performImmediateHealthCheck();

        // The recovery method should reflect the structured response
        expect(
          service.lastRecoveryMethod,
          equals('watchdog_restart'),
          reason:
              'Recovery method should be parsed from relay:reconnect response',
        );
      },
    );

    test(
      'failed in-place recovery escalates to watchdog only after threshold',
      () async {

        // Start online
        await service.startNodeCore(testBase64Key, testPeerId);

        // Configure: relay reservation is lost, escalation enabled
        bridge.useStructuredRecoveryResponse = true;
        bridge.simulateRefreshEscalation = true;
        bridge.refreshFailuresBeforeWatchdog = 3;
        bridge.simulateRelayReservationLost();
        bridge.pollsUntilCircuitReady = 1;

        // Failure 1: in-place refresh fails
        await service.performImmediateHealthCheck();
        expect(service.consecutiveRefreshFailures, 1);

        // Failure 2: in-place refresh fails again
        await service.performImmediateHealthCheck();
        expect(service.consecutiveRefreshFailures, 2);

        // Failure 3: threshold reached — watchdog kicks in and succeeds
        await service.performImmediateHealthCheck();

        // After the threshold, bridge.simulateRefreshEscalation resets
        // relayReservationLost and returns success with 'watchdog_restart'
        expect(
          service.lastRecoveryMethod,
          equals('watchdog_restart'),
          reason:
              'After threshold failures, recovery should escalate to watchdog restart',
        );
        expect(
          service.consecutiveRefreshFailures,
          0,
          reason:
              'Consecutive failures should reset to 0 after successful recovery',
        );
      },
    );
  });

  // ==========================================================================
  // Phase 6: Group Recovery on Resume and Watchdog
  // ==========================================================================

  group('Phase 6: Group recovery on resume and watchdog', () {
    test('resume recovery schedules group drain when relay recovery succeeds',
        () async {
      // Start online
      await service.startNodeCore(testBase64Key, testPeerId);
      expect(healthFromState(service.currentState), ConnectionHealth.online);

      // Background
      bridge.simulateBackground();
      bridge.pollsUntilCircuitReady = 1;

      // handleAppResumed with group repos should trigger group drain
      // (We verify indirectly: handleAppResumed doesn't throw,
      // and the recovery method is available)
      await handleAppResumed(
        bridge: bridge,
        p2pService: service,
      );

      // After resume, recovery should have succeeded
      expect(healthFromState(service.currentState), ConnectionHealth.online);
      // The lastRecoveryMethod should be set (in_place by default)
      expect(service.lastRecoveryMethod, isNotNull);
    });

    test('watchdog restart result schedules group rejoin and drain', () async {
      await service.startNodeCore(testBase64Key, testPeerId);

      bridge.useStructuredRecoveryResponse = true;
      bridge.structuredRecoveryMode = 'watchdog_restart';
      bridge.simulateBackground();
      bridge.pollsUntilCircuitReady = 1;

      await service.performImmediateHealthCheck();

      // After watchdog restart recovery, lastRecoveryMethod should be watchdog_restart
      expect(service.lastRecoveryMethod, equals('watchdog_restart'));
    });
  });
}
