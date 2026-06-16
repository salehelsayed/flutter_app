import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/push/application/group_missing_notification_feedback.dart';

// 04-P0 / QW-2 — an unrecoverable group push tap must not dead-end silently.
// The decision/feedback is extracted into a small helper because the inline
// branch lives in main.dart (not host-importable); these tests lock the
// SnackBar + Retry + route-home behavior.
void main() {
  testWidgets(
    'shows a SnackBar with Retry and routes back to the app root',
    (tester) async {
      final messengerKey = GlobalKey<ScaffoldMessengerState>();
      final navigatorKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: messengerKey,
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Center(child: Text('home'))),
        ),
      );

      // Push a deeper route so we can prove the helper routes back home.
      navigatorKey.currentState!.push(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Center(child: Text('deep'))),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('deep'), findsOneWidget);

      var retried = 0;
      showGroupMissingNotificationFeedback(
        messenger: messengerKey.currentState,
        navigator: navigatorKey.currentState,
        message: 'still catching up',
        retryLabel: 'Retry',
        onRetry: () => retried++,
      );
      await tester.pumpAndSettle();

      // Routed back to the first route.
      expect(find.text('deep'), findsNothing);
      expect(find.text('home'), findsOneWidget);

      // SnackBar shown with message + Retry action.
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('still catching up'), findsOneWidget);
      expect(find.widgetWithText(SnackBarAction, 'Retry'), findsOneWidget);

      // Tapping Retry re-invokes the handler exactly once (no unbounded loop).
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(retried, 1);
    },
  );

  testWidgets(
    'no Retry action when onRetry/retryLabel are omitted',
    (tester) async {
      final messengerKey = GlobalKey<ScaffoldMessengerState>();

      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: messengerKey,
          home: const Scaffold(body: Text('home')),
        ),
      );

      showGroupMissingNotificationFeedback(
        messenger: messengerKey.currentState,
        navigator: null,
        message: 'still catching up',
      );
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.byType(SnackBarAction), findsNothing);
    },
  );

  test('is safe (no throw) when messenger and navigator are both null', () {
    expect(
      () => showGroupMissingNotificationFeedback(
        messenger: null,
        navigator: null,
        message: 'x',
      ),
      returnsNormally,
    );
  });
}
