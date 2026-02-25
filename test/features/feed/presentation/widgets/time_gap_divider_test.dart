import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/feed/presentation/widgets/time_gap_divider.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('TimeGapDivider', () {
    testWidgets('renders timeLabel text', (tester) async {
      await tester.pumpWidget(wrap(const TimeGapDivider(timeLabel: '2 hours ago')));
      expect(find.text('2 hours ago'), findsOneWidget);
    });

    testWidgets('text has 25% opacity white color', (tester) async {
      await tester.pumpWidget(wrap(const TimeGapDivider(timeLabel: 'Yesterday')));
      final text = tester.widget<Text>(find.text('Yesterday'));
      expect(text.style?.color, const Color.fromRGBO(255, 255, 255, 0.25));
    });

    testWidgets('renders two horizontal divider lines', (tester) async {
      await tester.pumpWidget(wrap(const TimeGapDivider(timeLabel: 'Test')));
      // Two Expanded containers with height 0.5
      final containers = tester.widgetList<Container>(find.byType(Container)).where(
        (c) => c.constraints == null && c.decoration == null,
      );
      // The divider lines are Container widgets with height 0.5
      expect(find.byType(Expanded), findsNWidgets(2));
    });

    testWidgets('works with long time label text', (tester) async {
      const longLabel = 'A very long time label that should still render properly';
      await tester.pumpWidget(wrap(const TimeGapDivider(timeLabel: longLabel)));
      expect(find.text(longLabel), findsOneWidget);
    });
  });
}
