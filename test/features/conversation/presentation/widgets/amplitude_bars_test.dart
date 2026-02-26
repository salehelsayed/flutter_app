import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/amplitude_bars.dart';

void main() {
  Widget buildTestWidget(List<double> values) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 200,
          height: 24,
          child: AmplitudeBars(values: values),
        ),
      ),
    );
  }

  group('AmplitudeBars', () {
    testWidgets('renders CustomPaint', (tester) async {
      await tester.pumpWidget(buildTestWidget([0.0, 0.5, 1.0]));
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('no errors with empty values', (tester) async {
      await tester.pumpWidget(buildTestWidget([]));
      expect(tester.takeException(), isNull);
    });

    testWidgets('no errors with all-zero values', (tester) async {
      await tester.pumpWidget(buildTestWidget(List.filled(25, 0.0)));
      expect(tester.takeException(), isNull);
    });

    testWidgets('no errors with mixed values', (tester) async {
      await tester.pumpWidget(
        buildTestWidget([0.0, 0.2, 0.5, 0.8, 1.0, 0.3]),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('no errors with all-max values', (tester) async {
      await tester.pumpWidget(buildTestWidget(List.filled(25, 1.0)));
      expect(tester.takeException(), isNull);
    });

    test('shouldRepaint returns true when values change', () {
      final painter1 = AmplitudeBarsPainter(values: [0.1, 0.2]);
      final painter2 = AmplitudeBarsPainter(values: [0.3, 0.4]);
      expect(painter1.shouldRepaint(painter2), true);
    });

    test('shouldRepaint returns false when values are identical reference', () {
      final values = [0.1, 0.2];
      final painter1 = AmplitudeBarsPainter(values: values);
      final painter2 = AmplitudeBarsPainter(values: values);
      expect(painter1.shouldRepaint(painter2), false);
    });
  });
}
