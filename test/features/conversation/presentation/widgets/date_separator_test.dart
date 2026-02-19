import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/date_separator.dart';

void main() {
  Widget buildTestWidget({String label = 'Today'}) {
    return MaterialApp(
      home: Scaffold(
        body: DateSeparator(label: label),
      ),
    );
  }

  group('DateSeparator', () {
    testWidgets('displays uppercase label', (tester) async {
      await tester.pumpWidget(buildTestWidget(label: 'Today'));
      expect(find.text('TODAY'), findsOneWidget);
    });

    testWidgets('uppercases multi-word label', (tester) async {
      await tester.pumpWidget(buildTestWidget(label: 'February 9'));
      expect(find.text('FEBRUARY 9'), findsOneWidget);
    });

    testWidgets('has two gradient divider containers', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      // There should be 2 gradient dividers (Expanded > Container with BoxDecoration)
      final containers = tester.widgetList<Container>(find.byType(Container));
      final gradientContainers = containers.where((c) {
        final decoration = c.decoration;
        return decoration is BoxDecoration && decoration.gradient != null;
      });
      expect(gradientContainers.length, greaterThanOrEqualTo(2));
    });

    testWidgets('label has letter spacing of 1', (tester) async {
      await tester.pumpWidget(buildTestWidget(label: 'Today'));

      final textWidget = tester.widget<Text>(find.text('TODAY'));
      expect(textWidget.style?.letterSpacing, 1);
    });
  });
}
