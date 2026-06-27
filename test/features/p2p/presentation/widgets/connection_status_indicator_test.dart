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
    // FDC-14: directReady on top of usabilityReady promotes to onlineDirect.
    BadgeReadinessState.onlineDirect => const NodeState(
      isStarted: true,
      relayState: 'online',
      circuitAddresses: ['/p2p-circuit/relay1'],
      sendCapabilityReady: true,
      inboxCapabilityReady: true,
      directReady: true,
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

/// Reads the single label [Text] inside the indicator without hard-coding the
/// onlineDirect glyph (the plan locks distinctness, not a literal). Relies on
/// the test states carrying no connections, so the debug count Text is absent.
Text _labelTextWidget(WidgetTester tester) {
  return tester.widget<Text>(
    find.descendant(
      of: find.byType(ConnectionStatusIndicator),
      matching: find.byType(Text),
    ),
  );
}

/// Reads the status-dot colour (the small circle [Container]'s baseColor) — the
/// outer badge box uses a borderRadius, the dot uses [BoxShape.circle], so the
/// circle decoration uniquely identifies the dot.
Color? _dotColor(WidgetTester tester) {
  final containers = tester.widgetList<Container>(
    find.descendant(
      of: find.byType(ConnectionStatusIndicator),
      matching: find.byType(Container),
    ),
  );
  for (final c in containers) {
    final deco = c.decoration;
    if (deco is BoxDecoration && deco.shape == BoxShape.circle) {
      return deco.color;
    }
  }
  return null;
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

  // FDC-14 — the onlineDirect tier: a distinct visible + semantics label, a
  // ready state for timing/colour, above onlineDotted.
  group('FDC-14 onlineDirect rendering', () {
    // T6 — distinct visible label (NOT the onlineDotted 'Online.').
    testWidgets('renders the onlineDirect tier with a distinct visible label', (
      tester,
    ) async {
      final fakeService = await _pumpIndicator(
        tester,
        _stateForBadgeState(BadgeReadinessState.onlineDotted),
      );
      expect(find.text('Online.'), findsOneWidget);

      fakeService.pushState(
        _stateForBadgeState(BadgeReadinessState.onlineDirect),
      );
      await tester.pump();
      await tester.pump();

      final directLabel = _labelTextWidget(tester).data;
      expect(directLabel, isNotNull);
      expect(directLabel, isNotEmpty);
      // Headline acceptance: the onlineDirect label is distinct from BOTH
      // neighbouring ready tiers — onlineDotted's 'Online.' and plain 'Online'.
      expect(directLabel, isNot('Online.'));
      expect(directLabel, isNot('Online'));
      expect(find.text('Online.'), findsNothing);
      expect(find.text(directLabel!), findsOneWidget);

      fakeService.dispose();
    });

    // T7 — distinct "directly reachable" semantics label.
    testWidgets(
      'onlineDirect exposes a distinct directly-reachable semantics label',
      (tester) async {
        final fakeService = await _pumpIndicator(
          tester,
          _stateForBadgeState(BadgeReadinessState.onlineDotted),
        );
        final semanticsHandle = tester.ensureSemantics();
        final dottedLabel = tester
            .getSemantics(find.byType(ConnectionStatusIndicator))
            .label;

        fakeService.pushState(
          _stateForBadgeState(BadgeReadinessState.onlineDirect),
        );
        await tester.pump();
        await tester.pump();

        final directLabel = tester
            .getSemantics(find.byType(ConnectionStatusIndicator))
            .label;

        expect(directLabel, isNot(dottedLabel));
        expect(directLabel, contains('directly reachable'));
        expect(directLabel, isNot(contains('relay reservation')));

        semanticsHandle.dispose();
        fakeService.dispose();
      },
    );

    // T8 — onlineDirect is a ready state: no TIME_TO_ONLINE_BADGE re-emit on
    // dotted→direct, but exactly one on connecting→direct (first reach ready).
    testWidgets(
      'no badge timing re-emit moving between Online. and onlineDirect',
      (tester) async {
        // Sub-case A: dotted → direct is a ready-tier reshuffle → no emit.
        final fakeService = await _pumpIndicator(
          tester,
          _stateForBadgeState(BadgeReadinessState.onlineDotted),
        );
        final reshuffleEvents = await _captureFlowEvents(() async {
          fakeService.pushState(
            _stateForBadgeState(BadgeReadinessState.onlineDirect),
          );
          await tester.pump();
          await tester.pump();
        });
        expect(
          reshuffleEvents
              .where((e) => e['event'] == 'TIME_TO_ONLINE_BADGE_WIDGET')
              .toList(),
          isEmpty,
        );
        fakeService.dispose();

        // Unmount the indicator so the next _pumpIndicator builds a FRESH State
        // (same widget type with no key would otherwise reuse the State and skip
        // initState — leaving it subscribed to the disposed stream above).
        await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
        await tester.pump();

        // Sub-case B (LOAD-BEARING): connecting → direct is the first-reach-ready
        // transition → exactly one emit. This is the assertion that re-reds when
        // onlineDirect is omitted from _isReadyBadgeState.
        final fakeService2 = await _pumpIndicator(
          tester,
          _stateForBadgeState(BadgeReadinessState.connecting),
        );
        final reachEvents = await _captureFlowEvents(() async {
          fakeService2.pushState(
            _stateForBadgeState(BadgeReadinessState.onlineDirect),
          );
          await tester.pump();
          await tester.pump();
        });
        expect(
          reachEvents
              .where((e) => e['event'] == 'TIME_TO_ONLINE_BADGE_WIDGET')
              .toList(),
          hasLength(1),
        );
        fakeService2.dispose();
      },
    );

    // T9 — onlineDirect keeps the green ready styling: BOTH the label text
    // colour AND the status-dot (baseColor) match the plain-online green.
    testWidgets('onlineDirect keeps the green ready styling', (tester) async {
      final fakeService = await _pumpIndicator(
        tester,
        _stateForBadgeState(BadgeReadinessState.online),
      );
      final onlineColor = tester.widget<Text>(find.text('Online')).style?.color;
      final onlineDotColor = _dotColor(tester);

      fakeService.pushState(
        _stateForBadgeState(BadgeReadinessState.onlineDirect),
      );
      await tester.pump();
      await tester.pump();

      final directColor = _labelTextWidget(tester).style?.color;
      final directDotColor = _dotColor(tester);
      expect(directColor, onlineColor);
      // Lock the visible dot colour too, so a dot-only colour mutation (base
      // non-green, text green) cannot slip past a text-only assertion.
      expect(directDotColor, onlineDotColor);
      expect(directDotColor, Colors.green);

      fakeService.dispose();
    });
  });
}
