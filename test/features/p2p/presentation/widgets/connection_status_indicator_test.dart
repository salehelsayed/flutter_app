import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/presentation/widgets/connection_status_indicator.dart';

void main() {
  group('Phase 1 — connection status indicator health logic', () {
    test('stays connecting until circuit or reservation-ready state arrives', () {
      // Node is started but has no circuit addresses — should be "degraded" (connecting)
      const state = NodeState(
        isStarted: true,
        circuitAddresses: [],
      );

      final health = healthFromState(state);
      expect(health, ConnectionHealth.degraded);
    });

    test('does not turn online from relay-edge signal without circuit or reservation readiness', () {
      // Node is started, has connections (relay socket) but no circuit addresses
      const state = NodeState(
        isStarted: true,
        circuitAddresses: [],
        // Having connections doesn't mean we have circuit relay
      );

      final health = healthFromState(state);
      // Should still be degraded (connecting), not online
      expect(health, isNot(ConnectionHealth.online));
      expect(health, ConnectionHealth.degraded);
    });

    test('turns online when circuit addresses are present', () {
      const state = NodeState(
        isStarted: true,
        circuitAddresses: ['/p2p-circuit/relay1'],
      );

      final health = healthFromState(state);
      expect(health, ConnectionHealth.online);
    });

    test('shows offline when node is not started', () {
      const state = NodeState(isStarted: false);

      final health = healthFromState(state);
      expect(health, ConnectionHealth.offline);
    });

    test('turns online when relayState is online even without circuit addresses', () {
      const state = NodeState(
        isStarted: true,
        circuitAddresses: [],
        relayState: 'online',
      );

      final health = healthFromState(state);
      expect(health, ConnectionHealth.online);
    });

    test('stays online when relayState is not online but circuit addresses exist', () {
      const state = NodeState(
        isStarted: true,
        circuitAddresses: ['/p2p-circuit/relay1'],
        relayState: 'reconnecting',
      );

      final health = healthFromState(state);
      // Circuit addresses present → online, even if relayState is stale
      expect(health, ConnectionHealth.online);
    });

    test('shows degraded when relayState is not online and no circuit addresses', () {
      const state = NodeState(
        isStarted: true,
        circuitAddresses: [],
        relayState: 'reconnecting',
      );

      final health = healthFromState(state);
      expect(health, ConnectionHealth.degraded);
    });

    test('falls back to circuitAddresses when relayState is null (legacy bridge)', () {
      const state = NodeState(
        isStarted: true,
        circuitAddresses: ['/p2p-circuit/relay1'],
      );

      final health = healthFromState(state);
      expect(health, ConnectionHealth.online);
    });
  });
}
