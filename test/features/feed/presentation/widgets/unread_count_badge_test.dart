import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/feed/presentation/widgets/unread_count_badge.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('UnreadCountBadge', () {
    testWidgets('badge enters from 0.9 with an ease-out fade over 200 ms', (
      tester,
    ) async {
      const deadline = Duration(seconds: 3);
      await tester
          .pumpWidget(wrap(const UnreadCountBadge(count: 5)))
          .timeout(deadline);
      await tester.pump().timeout(deadline);
      final badge = find.byType(UnreadCountBadge);
      final scale = find.descendant(
        of: badge,
        matching: find.byType(ScaleTransition),
      );
      final fade = find.descendant(
        of: badge,
        matching: find.byType(FadeTransition),
      );
      double currentScale() => tester.widget<ScaleTransition>(scale).scale.value;
      double currentOpacity() =>
          tester.widget<FadeTransition>(fade).opacity.value;

      expect(currentScale(), closeTo(0.9, 0.001));
      expect(currentOpacity(), 0);
      await tester.pump(const Duration(milliseconds: 100)).timeout(deadline);
      final halfway = Curves.easeOut.transform(0.5);
      expect(currentScale(), closeTo(0.9 + 0.1 * halfway, 0.001));
      expect(currentOpacity(), closeTo(halfway, 0.001));
      await tester.pump(const Duration(milliseconds: 100)).timeout(deadline);
      expect(currentScale(), closeTo(1, 0.001));
      expect(currentOpacity(), 1);
    });

    testWidgets('reduce motion shows the badge at full size immediately', (
      tester,
    ) async {
      const deadline = Duration(seconds: 3);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: const Scaffold(body: UnreadCountBadge(count: 5)),
        ),
      ).timeout(deadline);
      final transition = find.descendant(
        of: find.byType(UnreadCountBadge),
        matching: find.byType(ScaleTransition),
      );
      expect(tester.widget<ScaleTransition>(transition).scale.value, 1);
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('renders count text for positive count', (tester) async {
      await tester.pumpWidget(wrap(const UnreadCountBadge(count: 5)));
      await tester.pumpAndSettle();
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('renders SizedBox.shrink when count is 0', (tester) async {
      await tester.pumpWidget(wrap(const UnreadCountBadge(count: 0)));
      expect(find.byType(SizedBox), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('renders "99+" when count exceeds 99', (tester) async {
      await tester.pumpWidget(wrap(const UnreadCountBadge(count: 200)));
      await tester.pumpAndSettle();
      expect(find.text('99+'), findsOneWidget);
    });

    testWidgets('uses ScaleTransition for animation', (tester) async {
      await tester.pumpWidget(wrap(const UnreadCountBadge(count: 3)));
      expect(find.descendant(
        of: find.byType(UnreadCountBadge),
        matching: find.byType(ScaleTransition),
      ), findsOneWidget);
    });

    testWidgets('updates display when count changes', (tester) async {
      await tester.pumpWidget(wrap(const UnreadCountBadge(count: 3)));
      await tester.pumpAndSettle();
      expect(find.text('3'), findsOneWidget);

      await tester.pumpWidget(wrap(const UnreadCountBadge(count: 7)));
      await tester.pumpAndSettle();
      expect(find.text('7'), findsOneWidget);
    });
  });
}
