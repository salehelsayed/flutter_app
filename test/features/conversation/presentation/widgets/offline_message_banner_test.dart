import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/offline_message_banner.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _StateP2PService implements P2PService {
  final StreamController<NodeState> _states =
      StreamController<NodeState>.broadcast();
  NodeState _currentState;

  _StateP2PService(this._currentState);

  @override
  NodeState get currentState => _currentState;

  @override
  Stream<NodeState> get stateStream => _states.stream;

  void emit(NodeState state) {
    _currentState = state;
    _states.add(state);
  }

  @override
  void dispose() {
    _states.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _online = NodeState(
  isStarted: true,
  sendCapabilityReady: true,
  inboxCapabilityReady: true,
);

Widget _app(P2PService service) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: OfflineMessageBanner(p2pService: service)),
);

void main() {
  testWidgets(
    'seeds offline synchronously and follows online-offline stream edges',
    (tester) async {
      final service = _StateP2PService(NodeState.stopped);
      addTearDown(service.dispose);

      await tester.pumpWidget(_app(service));

      expect(
        find.byKey(const ValueKey('offline-message-banner')),
        findsOneWidget,
      );
      expect(find.text("You're offline"), findsOneWidget);
      expect(
        find.text("Messages and media will send when you're back online."),
        findsOneWidget,
      );

      service.emit(_online);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('offline-message-banner')),
        findsNothing,
      );

      service.emit(NodeState.stopped);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('offline-message-banner')),
        findsOneWidget,
      );
    },
  );

  testWidgets('connecting is not presented as offline', (tester) async {
    final service = _StateP2PService(const NodeState(isStarted: true));
    addTearDown(service.dispose);

    await tester.pumpWidget(_app(service));

    expect(find.byKey(const ValueKey('offline-message-banner')), findsNothing);
  });
}
