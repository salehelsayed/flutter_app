import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart'
    as p2p_conn;
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/presentation/widgets/connection_status_indicator.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../shared/helpers/readability_test_helpers.dart';

class _FakeP2PService implements P2PService {
  final _stateController = StreamController<NodeState>.broadcast();

  _FakeP2PService(this._currentState);

  final NodeState _currentState;

  @override
  NodeState get currentState => _currentState;

  @override
  Stream<NodeState> get stateStream => _stateController.stream;

  @override
  void dispose() => _stateController.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  testWidgets('online pill renders legibly with Signal light values', (
    tester,
  ) async {
    final service = _FakeP2PService(
      const NodeState(
        isStarted: true,
        relayState: 'degraded',
        sendCapabilityReady: true,
        inboxCapabilityReady: true,
      ),
    );
    addTearDown(service.dispose);
    const colors = BackgroundReadableColors.representativeLight;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [colors]),
        home: Scaffold(body: ConnectionStatusIndicator(p2pService: service)),
      ),
    );

    final label = tester.widget<Text>(find.text('Online'));
    expect(label.style!.color, colors.connectedHeading);

    final dotContainer = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(ConnectionStatusIndicator),
            matching: find.byType(Container),
          ),
        )
        .firstWhere((container) {
          final decoration = container.decoration;
          return decoration is BoxDecoration &&
              decoration.shape == BoxShape.circle;
        });
    expect(
      (dotContainer.decoration as BoxDecoration).color,
      colors.connectedHeading,
    );
  });

  testWidgets(
    'Signal online label and debug count meet AA on rendered light pill',
    (tester) async {
      // Ready state with >0 connections so the 11px debug count renders.
      final service = _FakeP2PService(
        const NodeState(
          isStarted: true,
          relayState: 'degraded',
          sendCapabilityReady: true,
          inboxCapabilityReady: true,
          connections: [
            p2p_conn.ConnectionState(
              peerId: 'peer-1',
              multiaddrs: [],
              direction: 'inbound',
              status: 'connected',
            ),
          ],
        ),
      );
      addTearDown(service.dispose);
      const colors = BackgroundReadableColors.representativeLight;
      const canvas = Color(0xFFECE8E1);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [colors]),
          home: Scaffold(
            backgroundColor: canvas,
            body: ConnectionStatusIndicator(p2pService: service),
          ),
        ),
      );

      // 12px "Online" label + 11px "(1)" debug count are BOTH full-opacity
      // #236143 — the count is never alpha-faded.
      final label = tester.widget<Text>(find.text('Online'));
      expect(label.style!.color, const Color(0xFF236143));
      final count = tester.widget<Text>(find.text('(1)'));
      expect(count.style!.color, const Color(0xFF236143));

      // Rendered effective-surface contrast ≥4.5 for both, computed from the
      // pill decoration after alpha blending over the warm canvas.
      final pill = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(ConnectionStatusIndicator),
              matching: find.byType(Container),
            ),
          )
          .firstWhere((c) {
            final d = c.decoration;
            return d is BoxDecoration &&
                d.borderRadius == BorderRadius.circular(16);
          });
      final pillFill = (pill.decoration as BoxDecoration).color!;
      final effectiveSurface = Color.alphaBlend(pillFill, canvas);
      expectTextContrast(label.style!.color!, effectiveSurface);
      expectTextContrast(count.style!.color!, effectiveSurface);
    },
  );
}
