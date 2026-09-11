import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/presentation/navigation/conversation_route_transition.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/letter_card.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

typedef _HistorySnapshot = ({
  List<ConversationMessage> messages,
  bool initialLoadDone,
});

const _history = <ConversationMessage>[
  ConversationMessage(
    id: 'historical-newest',
    contactPeerId: 'friend',
    senderPeerId: 'friend',
    text: 'Already in the conversation',
    timestamp: '2026-09-10T10:00:00.000Z',
    status: 'delivered',
    isIncoming: true,
    createdAt: '2026-09-10T10:00:00.000Z',
  ),
];

Widget _host(GlobalKey<NavigatorState> navigatorKey) => MaterialApp(
  navigatorKey: navigatorKey,
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: const Scaffold(body: Center(child: Text('Orbit'))),
);

PageRoute<void> _openChat(
  GlobalKey<NavigatorState> navigatorKey,
  ValueNotifier<_HistorySnapshot> history,
) {
  final route =
      buildConversationRoute<void>(
            builder: (_) => Scaffold(
              body: ValueListenableBuilder<_HistorySnapshot>(
                valueListenable: history,
                builder: (_, snapshot, _) => ConversationScreen(
                  contactPeerId: 'friend',
                  contactUsername: 'Alice',
                  connectionDate: 'September 2026',
                  ownPeerId: 'self',
                  messages: snapshot.messages,
                  initialLoadDone: snapshot.initialLoadDone,
                  onSend: (_) {},
                  onBack: () => navigatorKey.currentState!.pop(),
                ),
              ),
            ),
          )
          as PageRoute<void>;
  navigatorKey.currentState!.push(route);
  return route;
}

void _expectHistoryStaticInsideMovingRoute(
  WidgetTester tester,
  PageRoute<void> route,
) {
  expect(route.animation!.status, AnimationStatus.forward);
  expect(route.animation!.value, inExclusiveRange(0.0, 1.0));
  _expectRowStatic(tester, 'historical-newest');
}

void _expectRowStatic(WidgetTester tester, String messageId) {
  final rowKey = ValueKey('msg-$messageId');
  final row = find.byKey(rowKey);
  expect(row, findsOneWidget);
  final card = tester.element(
    find.descendant(of: row, matching: find.byType(LetterCard)),
  );
  var reachedRow = false;
  // Examine only transforms between the message and its row. The route's
  // iOS slide is deliberately still active outside this boundary.
  card.visitAncestorElements((element) {
    final widget = element.widget;
    if (widget.key == rowKey) {
      reachedRow = true;
      return false;
    }
    if (widget is Opacity) {
      expect(widget.opacity, 1.0, reason: 'history must not fade in again');
    }
    if (widget is Transform) {
      expect(
        widget.transform.isIdentity(),
        isTrue,
        reason: 'history must not translate or scale inside the route slide',
      );
    }
    return true;
  });
  expect(reachedRow, isTrue);
}

void main() {
  testWidgets(
    'iOS chat opening reveals delayed history immediately during the route slide',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final navigatorKey = GlobalKey<NavigatorState>();
      final history = ValueNotifier<_HistorySnapshot>((
        messages: const [],
        initialLoadDone: false,
      ));
      try {
        await tester.pumpWidget(_host(navigatorKey));
        final route = _openChat(navigatorKey, history);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          find.byKey(const ValueKey('conversation-loading-shell')),
          findsOneWidget,
        );

        // The wired screen publishes its page before reactions complete and
        // before the post-frame initialLoadDone latch advances.
        history.value = (messages: _history, initialLoadDone: false);
        await tester.pump();

        _expectHistoryStaticInsideMovingRoute(tester, route);
        expect(
          find.byKey(const ValueKey('conversation-loading-shell')),
          findsNothing,
          reason: 'loading must not remain in an overlapping body crossfade',
        );
        final firstRoutePosition = tester.getTopLeft(
          find.text('Already in the conversation'),
        );
        history.value = (messages: _history, initialLoadDone: true);
        await tester.pump(const Duration(milliseconds: 16));
        _expectHistoryStaticInsideMovingRoute(tester, route);
        expect(
          tester.getTopLeft(find.text('Already in the conversation')).dx,
          lessThan(firstRoutePosition.dx),
          reason: 'the platform route keeps sliding while history stays static',
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
        history.dispose();
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'iOS chat opening and reopening keep cached history static during the slide',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final navigatorKey = GlobalKey<NavigatorState>();
      final history = ValueNotifier<_HistorySnapshot>((
        messages: _history,
        initialLoadDone: true,
      ));
      try {
        await tester.pumpWidget(_host(navigatorKey));
        for (var opening = 0; opening < 2; opening++) {
          final route = _openChat(navigatorKey, history);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          _expectHistoryStaticInsideMovingRoute(tester, route);
          expect(
            find.byKey(const ValueKey('conversation-loading-shell')),
            findsNothing,
          );
          await tester.pump(const Duration(milliseconds: 500));
          navigatorKey.currentState!.pop();
          for (var frame = 0; frame < 25; frame++) {
            await tester.pump(const Duration(milliseconds: 30));
          }
          expect(find.text('Orbit'), findsOneWidget);
          expect(find.byType(ConversationScreen), findsNothing);
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
        history.dispose();
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  for (final covered in <bool>[false, true]) {
    testWidgets(
      covered
          ? 'message arrivals stay static while another iOS route covers the chat'
          : 'message arrivals stay static while the iOS chat route is entering',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        final navigatorKey = GlobalKey<NavigatorState>();
        final history = ValueNotifier<_HistorySnapshot>((
          messages: _history,
          initialLoadDone: true,
        ));
        try {
          await tester.pumpWidget(_host(navigatorKey));
          final route = _openChat(navigatorKey, history);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          if (covered) {
            await tester.pump(const Duration(milliseconds: 500));
            expect(route.animation!.status, AnimationStatus.completed);
            navigatorKey.currentState!.push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('Cover')),
              ),
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 100));
            expect(route.isCurrent, isFalse);
          } else {
            expect(route.animation!.status, AnimationStatus.forward);
            expect(route.animation!.value, inExclusiveRange(0.0, 1.0));
          }

          history.value = (
            messages: [
              ..._history,
              _history.single.copyWith(
                id: 'live-during-transition',
                text: 'Arrived while the chat was not ready',
                timestamp: '2026-09-10T10:01:00.000Z',
              ),
            ],
            initialLoadDone: true,
          );
          await tester.pump();
          _expectRowStatic(tester, 'live-during-transition');
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 1));
          history.dispose();
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }
}
