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

NodeState _stateForBadgeState(BadgeReadinessState state) {
  return switch (state) {
    BadgeReadinessState.offline => const NodeState(isStarted: false),
    BadgeReadinessState.connecting => const NodeState(
      isStarted: true,
      relayState: 'degraded',
    ),
    BadgeReadinessState.online => const NodeState(
      isStarted: true,
      relayState: 'degraded',
      sendCapabilityReady: true,
      inboxCapabilityReady: true,
    ),
    BadgeReadinessState.onlineDotted => const NodeState(
      isStarted: true,
      relayState: 'online',
      circuitAddresses: ['/p2p-circuit/relay1'],
      sendCapabilityReady: true,
      inboxCapabilityReady: true,
    ),
  };
}

Future<_FakeP2PService> _pumpIndicator(
  WidgetTester tester,
  NodeState initialState,
) async {
  final fakeService = _FakeP2PService(initialState);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: ConnectionStatusIndicator(p2pService: fakeService)),
    ),
  );
  return fakeService;
}

void main() {
  group('Legacy relay health helper', () {
    test('stays connecting until circuit or reservation-ready state arrives', () {
      // Node is started but has no circuit addresses — should be "degraded" (connecting)
      const state = NodeState(isStarted: true, circuitAddresses: []);

      final health = healthFromState(state);
      expect(health, ConnectionHealth.degraded);
    });

    test(
      'does not turn online from relay-edge signal without circuit or reservation readiness',
      () {
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
      },
    );

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

    test(
      'turns online when relayState is online even without circuit addresses',
      () {
        const state = NodeState(
          isStarted: true,
          circuitAddresses: [],
          relayState: 'online',
        );

        final health = healthFromState(state);
        expect(health, ConnectionHealth.online);
      },
    );

    test(
      'stays online when relayState is not online but circuit addresses exist',
      () {
        const state = NodeState(
          isStarted: true,
          circuitAddresses: ['/p2p-circuit/relay1'],
          relayState: 'reconnecting',
        );

        final health = healthFromState(state);
        // Circuit addresses present → online, even if relayState is stale
        expect(health, ConnectionHealth.online);
      },
    );

    test(
      'shows degraded when relayState is not online and no circuit addresses',
      () {
        const state = NodeState(
          isStarted: true,
          circuitAddresses: [],
          relayState: 'reconnecting',
        );

        final health = healthFromState(state);
        expect(health, ConnectionHealth.degraded);
      },
    );

    test(
      'falls back to circuitAddresses when relayState is null (legacy bridge)',
      () {
        const state = NodeState(
          isStarted: true,
          circuitAddresses: ['/p2p-circuit/relay1'],
        );

        final health = healthFromState(state);
        expect(health, ConnectionHealth.online);
      },
    );
  });

  group('Phase 6 badge rendering', () {
    testWidgets('renders the exact visible text for all four badge states', (
      tester,
    ) async {
      final fakeService = await _pumpIndicator(
        tester,
        _stateForBadgeState(BadgeReadinessState.offline),
      );

      expect(find.text('Offline'), findsOneWidget);

      fakeService.pushState(
        _stateForBadgeState(BadgeReadinessState.connecting),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Connecting'), findsOneWidget);

      fakeService.pushState(_stateForBadgeState(BadgeReadinessState.online));
      await tester.pump();
      await tester.pump();
      expect(find.text('Online'), findsOneWidget);

      fakeService.pushState(
        _stateForBadgeState(BadgeReadinessState.onlineDotted),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Online.'), findsOneWidget);

      fakeService.dispose();
    });

    testWidgets('Online and Online. expose distinct semantics labels', (
      tester,
    ) async {
      final fakeService = await _pumpIndicator(
        tester,
        _stateForBadgeState(BadgeReadinessState.online),
      );
      final semanticsHandle = tester.ensureSemantics();

      expect(
        tester.getSemantics(find.byType(ConnectionStatusIndicator)).label,
        'online, send and inbox ready, relay reservation pending',
      );

      fakeService.pushState(
        _stateForBadgeState(BadgeReadinessState.onlineDotted),
      );
      await tester.pump();
      await tester.pump();

      expect(
        tester.getSemantics(find.byType(ConnectionStatusIndicator)).label,
        'online, send and inbox ready, relay reservation ready',
      );

      semanticsHandle.dispose();
      fakeService.dispose();
    });

    testWidgets('Online and Online. keep the same green text styling', (
      tester,
    ) async {
      final fakeService = await _pumpIndicator(
        tester,
        _stateForBadgeState(BadgeReadinessState.online),
      );
      final onlineText = tester.widget<Text>(find.text('Online'));
      final onlineColor = onlineText.style?.color;

      fakeService.pushState(
        _stateForBadgeState(BadgeReadinessState.onlineDotted),
      );
      await tester.pump();

      final dottedText = tester.widget<Text>(find.text('Online.'));
      expect(dottedText.style?.color, onlineColor);

      fakeService.dispose();
    });
  });

  group('§24 TIME_TO_ONLINE_BADGE_WIDGET', () {
    testWidgets('emits timing when widget first transitions to Online', (
      tester,
    ) async {
      final fakeService = await _pumpIndicator(
        tester,
        _stateForBadgeState(BadgeReadinessState.connecting),
      );

      final events = await _captureFlowEvents(() async {
        fakeService.pushState(_stateForBadgeState(BadgeReadinessState.online));
        await tester.pump();
        await tester.pump();
      });

      final widgetBadge = events
          .where((e) => e['event'] == 'TIME_TO_ONLINE_BADGE_WIDGET')
          .toList();
      expect(widgetBadge, hasLength(1));
      final details = widgetBadge.first['details'] as Map<String, dynamic>;
      expect(details['widgetTransitionMs'], greaterThanOrEqualTo(0));
      expect(details['previousHealth'], 'degraded');
      expect(find.text('Online'), findsOneWidget);

      fakeService.dispose();
    });

    testWidgets('emits timing when widget goes directly to Online.', (
      tester,
    ) async {
      final fakeService = await _pumpIndicator(
        tester,
        _stateForBadgeState(BadgeReadinessState.connecting),
      );

      final events = await _captureFlowEvents(() async {
        fakeService.pushState(
          _stateForBadgeState(BadgeReadinessState.onlineDotted),
        );
        await tester.pump();
        await tester.pump();
      });

      final widgetBadge = events
          .where((e) => e['event'] == 'TIME_TO_ONLINE_BADGE_WIDGET')
          .toList();
      expect(widgetBadge, hasLength(1));
      expect(find.text('Online.'), findsOneWidget);

      fakeService.dispose();
    });

    testWidgets('does not emit timing when moving between Online and Online.', (
      tester,
    ) async {
      final fakeService = await _pumpIndicator(
        tester,
        _stateForBadgeState(BadgeReadinessState.online),
      );

      final events = await _captureFlowEvents(() async {
        fakeService.pushState(
          _stateForBadgeState(BadgeReadinessState.onlineDotted),
        );
        await tester.pump();
        await tester.pump();
      });

      final widgetBadge = events
          .where((e) => e['event'] == 'TIME_TO_ONLINE_BADGE_WIDGET')
          .toList();
      expect(widgetBadge, isEmpty);
      expect(find.text('Online.'), findsOneWidget);

      fakeService.dispose();
    });

    testWidgets('applies ready-state downgrades immediately', (tester) async {
      final fakeService = await _pumpIndicator(
        tester,
        _stateForBadgeState(BadgeReadinessState.onlineDotted),
      );

      fakeService.pushState(_stateForBadgeState(BadgeReadinessState.online));
      await tester.pump();
      await tester.pump();
      expect(find.text('Online'), findsOneWidget);

      fakeService.pushState(
        _stateForBadgeState(BadgeReadinessState.connecting),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Connecting'), findsOneWidget);

      fakeService.dispose();
    });
  });
}
