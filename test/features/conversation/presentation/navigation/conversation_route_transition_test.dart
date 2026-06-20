// Host coverage for the 1:1 conversation route helper.
//
// The 1:1 conversation screen historically pushed via a `PageRouteBuilder`
// slide-up, which silently dropped iOS' platform edge-swipe-back gesture (the
// group conversation screen, pushed via `MaterialPageRoute`, kept it). The fix
// (Test-Flight-Improv/1to1-swipe-back-navigation-tdd-plan.md, Option A) makes
// the helper return a `MaterialPageRoute` so iOS supplies the back gesture for
// free, at parity with groups.
//
// T0.1 (route type) is the deterministic RED->GREEN anchor. T1.1/T1.2 drive the
// real Cupertino back gesture through flutter_test's gesture arena under an iOS
// platform override; the authoritative behavioral guarantee is the Phase 3
// device proof (integration_test/conversation_swipe_back_proof_test.dart).
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/presentation/navigation/conversation_route_transition.dart';

void main() {
  group('buildConversationRoute — route type & settings', () {
    // T0.1 — route-type lock (INV-1/INV-2). On iOS, MaterialPageRoute supplies
    // the Cupertino edge-swipe-back gesture; PageRouteBuilder does not.
    test('1:1 conversation route is a MaterialPageRoute (iOS edge-swipe-back '
        'capable)', () {
      final route = buildConversationRoute<void>(builder: (_) => const SizedBox());
      expect(route, isA<MaterialPageRoute>());
    });

    // T0.2 — settings forwarded (INV-4): analytics / named routes unaffected.
    test('forwards RouteSettings', () {
      final route = buildConversationRoute<void>(
        builder: (_) => const SizedBox(),
        settings: const RouteSettings(name: 'conversation'),
      );
      expect(route.settings.name, 'conversation');
    });
  });

  group('buildConversationRoute — iOS edge-swipe-back behavior', () {
    // T1.1 — left-edge swipe pops the 1:1 route (INV-1).
    testWidgets(
      'iOS left-edge swipe pops the 1:1 conversation back to the previous '
      'screen',
      (tester) async {
        // Reset in finally (not addTearDown): the binding's foundation-var
        // invariant check runs at the end of the test body, before tearDowns.
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        try {
          final nav = GlobalKey<NavigatorState>();
          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: nav,
              home: const Scaffold(body: Center(child: Text('PREVIOUS'))),
            ),
          );

          nav.currentState!.push(
            buildConversationRoute<void>(
              builder: (_) => const Scaffold(body: Center(child: Text('CHAT'))),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('CHAT'), findsOneWidget);
          expect(find.text('PREVIOUS'), findsNothing);

          // iOS back gesture: start inside the left-edge zone and drag across
          // the screen, sampling intermediate frames so the drag recogniser
          // builds up the displacement/velocity it pops on.
          final gesture = await tester.startGesture(const Offset(5, 300));
          for (var i = 0; i < 10; i++) {
            await gesture.moveBy(const Offset(60, 0)); // 600px total, past mid
            await tester.pump();
          }
          await gesture.up();
          await tester.pumpAndSettle();

          expect(find.text('PREVIOUS'), findsOneWidget); // popped
          expect(find.text('CHAT'), findsNothing);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    // T1.2 — the active-upload guard wins (INV-3): while a PopScope(canPop:
    // false) is registered the route reports doNotPop, which disables the
    // Cupertino back gesture; the swipe must not bypass the guard.
    testWidgets(
      'edge-swipe is suppressed while a PopScope blocks pop (active-upload '
      'guard)',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        try {
          final nav = GlobalKey<NavigatorState>();
          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: nav,
              home: const Scaffold(body: Center(child: Text('PREVIOUS'))),
            ),
          );
          nav.currentState!.push(
            buildConversationRoute<void>(
              builder: (_) => const PopScope(
                canPop: false,
                child: Scaffold(body: Center(child: Text('CHAT'))),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final gesture = await tester.startGesture(const Offset(5, 300));
          for (var i = 0; i < 10; i++) {
            await gesture.moveBy(const Offset(60, 0));
            await tester.pump();
          }
          await gesture.up();
          await tester.pumpAndSettle();

          expect(find.text('CHAT'), findsOneWidget); // guard held — no pop
          expect(find.text('PREVIOUS'), findsNothing);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  });
}
