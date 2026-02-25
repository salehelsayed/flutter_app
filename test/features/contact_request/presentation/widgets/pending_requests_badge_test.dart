import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contact_request/presentation/widgets/pending_requests_badge.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('PendingRequestsBadge', () {
    testWidgets('renders count text for positive count', (tester) async {
      await tester.pumpWidget(wrap(const PendingRequestsBadge(count: 5)));
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('renders SizedBox.shrink when count is 0', (tester) async {
      await tester.pumpWidget(wrap(const PendingRequestsBadge(count: 0)));
      expect(find.byType(SizedBox), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('renders "99+" when count exceeds 99', (tester) async {
      await tester.pumpWidget(wrap(const PendingRequestsBadge(count: 150)));
      expect(find.text('99+'), findsOneWidget);
    });

    testWidgets('respects custom size parameter', (tester) async {
      await tester.pumpWidget(wrap(const PendingRequestsBadge(count: 3, size: 30)));
      final container = tester.widgetList<Container>(find.byType(Container)).where(
        (c) => c.constraints?.maxWidth == 30,
      );
      expect(container, isNotEmpty);
    });
  });
}
