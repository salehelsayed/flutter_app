import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/feed/presentation/widgets/view_earlier_link.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('ViewEarlierLink', () {
    testWidgets('renders "View earlier messages" text', (tester) async {
      await tester.pumpWidget(wrap(const ViewEarlierLink()));
      expect(find.text('View earlier messages'), findsOneWidget);
    });

    testWidgets('fires onTap callback', (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(ViewEarlierLink(onTap: () => tapped = true)));
      await tester.tap(find.text('View earlier messages'));
      expect(tapped, isTrue);
    });
  });
}
