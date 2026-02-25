import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/feed/presentation/widgets/checkmark_burst_animation.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('CheckmarkBurstAnimation', () {
    testWidgets('renders check icon after animation delay', (tester) async {
      await tester.pumpWidget(wrap(const CheckmarkBurstAnimation()));
      // Advance past the 180ms Future.delayed so the timer completes.
      await tester.pump(const Duration(milliseconds: 200));
      // Pump a bit more to advance the icon animation.
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      // Dispose the widget tree to stop the repeating animation.
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('renders with default size 84', (tester) async {
      await tester.pumpWidget(wrap(const CheckmarkBurstAnimation()));
      // Advance past the 180ms delayed timer to prevent pending timer errors.
      await tester.pump(const Duration(milliseconds: 200));
      final sizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox));
      final match = sizedBoxes.where((s) => s.width == 84 && s.height == 84);
      expect(match, isNotEmpty);
      // Dispose widget tree to stop repeating animation controller.
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('renders with custom size', (tester) async {
      await tester.pumpWidget(wrap(const CheckmarkBurstAnimation(size: 120)));
      await tester.pump(const Duration(milliseconds: 200));
      final sizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox));
      final match = sizedBoxes.where((s) => s.width == 120 && s.height == 120);
      expect(match, isNotEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('uses ScaleTransition for icon animation', (tester) async {
      await tester.pumpWidget(wrap(const CheckmarkBurstAnimation()));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.descendant(
        of: find.byType(CheckmarkBurstAnimation),
        matching: find.byType(ScaleTransition),
      ), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
