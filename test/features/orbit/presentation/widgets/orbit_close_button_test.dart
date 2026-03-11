import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_close_button.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('OrbitCloseButton', () {
    testWidgets('renders a 36px circle container', (tester) async {
      await tester.pumpWidget(wrap(OrbitCloseButton(onTap: () {})));
      final container = tester.widgetList<Container>(find.byType(Container)).where(
        (c) {
          final decoration = c.decoration;
          if (decoration is BoxDecoration) {
            return decoration.shape == BoxShape.circle;
          }
          return false;
        },
      ).first;
      expect(container.constraints?.maxWidth, 36);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(OrbitCloseButton(onTap: () => tapped = true)));
      await tester.tap(find.byType(OrbitCloseButton));
      expect(tapped, isTrue);
    });

    testWidgets('renders CustomPaint (X painter)', (tester) async {
      await tester.pumpWidget(wrap(OrbitCloseButton(onTap: () {})));
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });
}
