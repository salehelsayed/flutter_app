import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/presentation/widgets/connection_status_indicator.dart';

/// Minimal fake P2PService for widget tests.
class _FakeP2PService implements P2PService {
  final _stateController = StreamController<NodeState>.broadcast();
  NodeState _currentState;

  _FakeP2PService(this._currentState);

  @override
  NodeState get currentState => _currentState;

  @override
  Stream<NodeState> get stateStream => _stateController.stream;

  void pushState(NodeState state) {
    _currentState = state;
    _stateController.add(state);
  }

  void dispose() => _stateController.close();

  // Stubs — noSuchMethod covers all abstract members not used by the widget.
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Captures [FLOW] log lines emitted during [action] and returns parsed events.
Future<List<Map<String, dynamic>>> _captureFlowEvents(
  Future<void> Function() action,
) async {
  final printed = <String>[];
  final previousLogging = flowEventLoggingEnabled;
  final originalDebugPrint = debugPrint;
  flowEventLoggingEnabled = true;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) {
      printed.add(message);
    }
  };
  try {
    await action();
  } finally {
    debugPrint = originalDebugPrint;
    flowEventLoggingEnabled = previousLogging;
  }

  return printed
      .where((line) => line.startsWith('[FLOW] '))
      .map(
        (line) =>
            jsonDecode(line.substring('[FLOW] '.length))
                as Map<String, dynamic>,
      )
      .toList();
}

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

  group('§24 TIME_TO_ONLINE_BADGE_WIDGET', () {
    testWidgets('emits timing when widget transitions to online', (tester) async {
      final fakeService = _FakeP2PService(const NodeState(
        isStarted: true,
        circuitAddresses: [],
        relayState: 'starting',
      ));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConnectionStatusIndicator(p2pService: fakeService),
          ),
        ),
      );

      // Widget starts in degraded state
      expect(find.text('Connecting'), findsOneWidget);

      final events = await _captureFlowEvents(() async {
        // Push online state
        fakeService.pushState(const NodeState(
          isStarted: true,
          circuitAddresses: ['/p2p-circuit/relay1'],
          relayState: 'online',
        ));

        await tester.pump();
      });

      expect(find.text('Online'), findsOneWidget);

      final widgetBadge = events.where(
        (e) => e['event'] == 'TIME_TO_ONLINE_BADGE_WIDGET',
      ).toList();
      expect(widgetBadge, hasLength(1));
      final details = widgetBadge.first['details'] as Map<String, dynamic>;
      expect(details['widgetTransitionMs'], greaterThanOrEqualTo(0));
      expect(details['previousHealth'], 'degraded');

      fakeService.dispose();
    });

    testWidgets('does not emit timing when health unchanged', (tester) async {
      final fakeService = _FakeP2PService(const NodeState(
        isStarted: true,
        circuitAddresses: ['/p2p-circuit/relay1'],
        relayState: 'online',
      ));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConnectionStatusIndicator(p2pService: fakeService),
          ),
        ),
      );

      expect(find.text('Online'), findsOneWidget);

      final events = await _captureFlowEvents(() async {
        // Push same health state (still online)
        fakeService.pushState(const NodeState(
          isStarted: true,
          circuitAddresses: ['/p2p-circuit/relay1', '/p2p-circuit/relay2'],
          relayState: 'online',
        ));

        await tester.pump();
      });

      final widgetBadge = events.where(
        (e) => e['event'] == 'TIME_TO_ONLINE_BADGE_WIDGET',
      ).toList();
      expect(widgetBadge, isEmpty);

      fakeService.dispose();
    });
  });
}
