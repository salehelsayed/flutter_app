import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/presentation/widgets/connection_status_indicator.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
