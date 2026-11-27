import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/date_separator.dart';

import '../../../../shared/helpers/readability_test_helpers.dart';

void main() {
  Widget buildTestWidget({
    String label = 'Today',
    BackgroundReadableColors? colors,
  }) {
    return MaterialApp(
      theme: colors == null ? null : ThemeData(extensions: [colors]),
      home: Scaffold(
        body: DateSeparator(label: label),
      ),
    );
  }

  Color gradientPeakColor(WidgetTester tester) {
    final containers = tester.widgetList<Container>(find.byType(Container));
    final gradient = containers
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .map((d) => d.gradient)
        .whereType<LinearGradient>()
        .first;
    return gradient.colors[1];
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

    testWidgets('dark date label meets text contrast with its existing lines', (
      tester,
    ) async {
      await tester
          .pumpWidget(buildTestWidget(colors: BackgroundReadableColors.dark))
          .timeout(const Duration(seconds: 3));

      expect(
        gradientPeakColor(tester),
        const Color.fromRGBO(255, 255, 255, 0.12),
      );
      final textWidget = tester.widget<Text>(find.text('TODAY'));
      final labelColor = textWidget.style!.color!;
      expect(labelColor, const Color.fromRGBO(255, 255, 255, 0.60));
      expectTextContrast(labelColor, Colors.black);
    });

    testWidgets('light tone uses opaque mineral roles, not white', (
      tester,
    ) async {
      const colors = BackgroundReadableColors.representativeLight;
      await tester.pumpWidget(buildTestWidget(colors: colors));

      expect(gradientPeakColor(tester), colors.emptyDivider);
      final textWidget = tester.widget<Text>(find.text('TODAY'));
      expect(textWidget.style?.color, colors.emptyDate);
    });
  });
}
