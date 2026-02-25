import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/home/presentation/widgets/empty_circle_state.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(size: Size(400, 800)),
            child: child,
          ),
        ),
      );

  group('EmptyCircleState', () {
    testWidgets('renders "Your circle is waiting to be filled" text',
        (tester) async {
      await tester.pumpWidget(wrap(const EmptyCircleState()));
      await tester.pump();
      expect(
          find.text('Your circle is waiting to be filled'), findsOneWidget);
    });

    testWidgets('renders subtitle text', (tester) async {
      await tester.pumpWidget(wrap(const EmptyCircleState()));
      await tester.pump();
      expect(find.textContaining('Scan a friend'), findsOneWidget);
    });

    testWidgets('renders CustomPaint for dashed circles', (tester) async {
      await tester.pumpWidget(wrap(const EmptyCircleState()));
      await tester.pump();
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('renders constellation dots painter', (tester) async {
      await tester.pumpWidget(wrap(const EmptyCircleState()));
      await tester.pump();
      // The center icon container has a CustomPaint with constellation dots
      final customPaints =
          tester.widgetList<CustomPaint>(find.byType(CustomPaint));
      expect(customPaints.length, greaterThanOrEqualTo(2));
    });
  });
}
