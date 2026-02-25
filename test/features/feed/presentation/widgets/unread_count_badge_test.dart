import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/feed/presentation/widgets/unread_count_badge.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('UnreadCountBadge', () {
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
