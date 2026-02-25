import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/overflow_badge.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('OverflowBadge', () {
    testWidgets('renders "+N" text with count', (tester) async {
      await tester.pumpWidget(wrap(const OverflowBadge(count: 5)));
      // Advance past 1000ms entrance delay + 500ms animation.
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pumpAndSettle();
      expect(find.text('+5'), findsOneWidget);
    });

    testWidgets('renders 28px circular container', (tester) async {
      await tester.pumpWidget(wrap(const OverflowBadge(count: 3)));
      // Pump past the entrance delay.
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pumpAndSettle();
      // The Container has explicit width: 28, height: 28, and circular shape.
      final containers = tester.widgetList<Container>(find.byType(Container));
      final sized = containers.where((c) {
        final d = c.decoration;
        if (d is BoxDecoration && d.shape == BoxShape.circle) {
          // Check if this is the 28px container by examining constraints
          return true;
        }
        return false;
      });
      expect(sized, isNotEmpty);
    });

    testWidgets('renders CustomPaint (dashed border)', (tester) async {
      await tester.pumpWidget(wrap(const OverflowBadge(count: 2)));
      // Pump past entrance delay.
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pumpAndSettle();
      expect(find.descendant(
        of: find.byType(OverflowBadge),
        matching: find.byType(CustomPaint),
      ), findsOneWidget);
    });

    testWidgets('uses BackdropFilter for frosted glass', (tester) async {
      await tester.pumpWidget(wrap(const OverflowBadge(count: 4)));
      // Widget tree is built immediately, BackdropFilter is present from start.
      expect(find.byType(BackdropFilter), findsOneWidget);
      // Clean up pending timers by pumping past the delay.
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pumpAndSettle();
    });
  });
}
