import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/presentation/widgets/connection_status_indicator.dart';

import '../../shared/fakes/lifecycle_bridge.dart';

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

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

  group('Background → Foreground reconnect smoke test', () {
    test('Phase 1: fresh start reaches Online', () async {
      bridge.phase = 'startup';

      final result = await service.startNodeCore(testBase64Key, testPeerId);

      expect(result, isTrue);
      expect(service.currentState.isStarted, isTrue);
      expect(service.currentState.circuitAddresses, isNotEmpty,
          reason: 'Should have circuit addresses after fresh start');
      expect(healthFromState(service.currentState), ConnectionHealth.online);
    });

    test('Phase 2: after background, state is degraded (Connecting)', () async {
      // Start online
      await service.startNodeCore(testBase64Key, testPeerId);
      expect(healthFromState(service.currentState), ConnectionHealth.online);

      // Simulate going to background — relay drops
      bridge.simulateBackground();

      // Health check should detect degraded state
      // Call performImmediateHealthCheck which runs _performHealthCheck
      await service.performImmediateHealthCheck();

      // After the first health check, the recovery tries a dial then
      // immediately polls status. With pollsUntilCircuitReady=2, the
      // first poll post-dial still shows degraded.
      expect(
        service.currentState.circuitAddresses,
        isEmpty,
        reason: 'Circuit addresses should be empty right after background '
            '(relay reservation not yet complete)',
      );
      expect(healthFromState(service.currentState), ConnectionHealth.degraded);
    });

    test('Phase 3: resume recovery eventually restores Online', () async {
      // Start online
      await service.startNodeCore(testBase64Key, testPeerId);
      expect(healthFromState(service.currentState), ConnectionHealth.online);

      // Background — relay drops
      bridge.simulateBackground();

      // First health check: dials relay, polls immediately, still degraded
      await service.performImmediateHealthCheck();
      expect(healthFromState(service.currentState), ConnectionHealth.degraded,
          reason: 'Immediately after resume health check: still degraded');

      // Second health check: circuit reservation has completed
      await service.performImmediateHealthCheck();
      expect(healthFromState(service.currentState), ConnectionHealth.online,
          reason: 'After second health check: circuit ready → online');
    });

    test('Full lifecycle: start → background → handleAppResumed → online',
        () async {
      // 1. Start the node
      await service.startNodeCore(testBase64Key, testPeerId);
      expect(healthFromState(service.currentState), ConnectionHealth.online);

      final initialCircuit =
          List<String>.from(service.currentState.circuitAddresses);

      // 2. Go to background — relay drops
      bridge.simulateBackground();
      // Circuit reservation needs only 1 poll this time (faster recovery)
      bridge.pollsUntilCircuitReady = 1;

      // 3. Come back — run handleAppResumed (same as real lifecycle)
      final bridgeOk = await handleAppResumed(
        bridge: bridge,
        p2pService: service,
      );

      expect(bridgeOk, isTrue, reason: 'Bridge should be healthy');

      // 4. After handleAppResumed, the immediate health check re-dialed
      //    the relay and (with pollsUntilCircuitReady=1) the status poll
      //    returns circuit addresses.
      expect(healthFromState(service.currentState), ConnectionHealth.online,
          reason: 'Should be back online after handleAppResumed');
      expect(service.currentState.circuitAddresses, isNotEmpty);
    });

    test(
        'Slow recovery: circuit takes multiple health checks to come back',
        () async {
      // Start online
      await service.startNodeCore(testBase64Key, testPeerId);

      // Background
      bridge.simulateBackground();
      // Require enough recovery polls that it spans 3 health check cycles.
      // Each HC in recovery does: initial-status (recovering) + dial + post-dial-status (recovering)
      // HC1: 'degraded' status → dial → phase='recovering' → post-dial: attempt 1 (< 5)
      // HC2: 'recovering' status: attempt 2 → still empty → dial → post-dial: attempt 3 (< 5)
      // HC3: 'recovering' status: attempt 4 → still empty → dial → post-dial: attempt 5 (>= 5) → online!
      bridge.pollsUntilCircuitReady = 5;

      // Health check 1
      await service.performImmediateHealthCheck();
      expect(healthFromState(service.currentState), ConnectionHealth.degraded);
      expect(bridge.relayReconnectCallCount, 1);

      // Health check 2
      await service.performImmediateHealthCheck();
      expect(healthFromState(service.currentState), ConnectionHealth.degraded);

      // Health check 3: circuit finally ready
      await service.performImmediateHealthCheck();
      expect(healthFromState(service.currentState), ConnectionHealth.online);
    });

    test('addresses:updated push event restores Online even without polling',
        () async {
      // Start online
      await service.startNodeCore(testBase64Key, testPeerId);

      // Background — set a very high poll count so polling alone won't help
      bridge.simulateBackground();
      bridge.pollsUntilCircuitReady = 999;

      // Health check: dials relay, polls → still degraded
      await service.performImmediateHealthCheck();
      expect(healthFromState(service.currentState), ConnectionHealth.degraded);

      // Simulate Go pushing addresses:updated directly (the fast path)
      bridge.onAddressesUpdated?.call(
        ['/ip4/127.0.0.1/tcp/1234'],
        ['/p2p-circuit/p2p/$relayPeerId'],
      );

      // The push event handler should update state immediately
      expect(service.currentState.circuitAddresses, isNotEmpty);
      expect(healthFromState(service.currentState), ConnectionHealth.online);
    });

    test('dead EventChannel: recovery relies only on health check polling',
        () async {
      bridge.eventChannelDead = true;

      // Start online
      await service.startNodeCore(testBase64Key, testPeerId);

      // Background
      bridge.simulateBackground();
      bridge.pollsUntilCircuitReady = 2;

      // Health check 1: degraded
      await service.performImmediateHealthCheck();
      expect(healthFromState(service.currentState), ConnectionHealth.degraded);
      expect(bridge.addressesPushFired, isFalse,
          reason: 'Push should NOT fire when EventChannel is dead');

      // Health check 2: circuit ready (via polling)
      await service.performImmediateHealthCheck();
      expect(healthFromState(service.currentState), ConnectionHealth.online);
    });

    test('tracks state transitions through stateStream', () async {
      final states = <NodeState>[];
      final sub = service.stateStream.listen(states.add);

      // Start online
      await service.startNodeCore(testBase64Key, testPeerId);
      // Allow microtasks to flush
      await Future<void>.delayed(Duration.zero);
      expect(states, isNotEmpty, reason: 'Should have at least one state emission');
      expect(states.first.circuitAddresses, isNotEmpty);

      // Background
      bridge.simulateBackground();
      bridge.pollsUntilCircuitReady = 1;
      final stateCountBefore = states.length;

      // Resume → degraded → online
      await handleAppResumed(bridge: bridge, p2pService: service);
      await Future<void>.delayed(Duration.zero);

      // Should have additional state emissions from the recovery
      expect(states.length, greaterThan(stateCountBefore),
          reason: 'Resume recovery should emit state changes');

      // Last state should be online
      expect(healthFromState(states.last), ConnectionHealth.online,
          reason: 'Final state should be online after recovery');

      await sub.cancel();
    });

    test('multiple background/foreground cycles recover each time', () async {
      await service.startNodeCore(testBase64Key, testPeerId);

      for (var cycle = 1; cycle <= 3; cycle++) {
        // Background
        bridge.simulateBackground();
        bridge.pollsUntilCircuitReady = 1;

        // Resume
        await handleAppResumed(bridge: bridge, p2pService: service);

        expect(healthFromState(service.currentState), ConnectionHealth.online,
            reason: 'Should be online after cycle $cycle');
      }
    });

    test('handleAppResumed calls bridge checkHealth, health check, and drain',
        () async {
      await service.startNodeCore(testBase64Key, testPeerId);
      bridge.simulateBackground();
      bridge.pollsUntilCircuitReady = 1;

      final statusBefore = bridge.nodeStatusCallCount;
      final reconnectBefore = bridge.relayReconnectCallCount;

      await handleAppResumed(bridge: bridge, p2pService: service);

      // checkHealth calls node:status (1) +
      // performImmediateHealthCheck calls node:status (2: initial + post-reconnect) +
      // drainOfflineInbox may call inbox:retrieve
      expect(bridge.nodeStatusCallCount, greaterThan(statusBefore));
      expect(bridge.relayReconnectCallCount, greaterThan(reconnectBefore),
          reason: 'Should call relay:reconnect when degraded');
    });
  });
}
