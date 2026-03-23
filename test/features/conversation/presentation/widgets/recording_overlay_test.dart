import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/recording_overlay.dart';
import 'package:flutter_app/shared/widgets/media/amplitude_bars.dart';

void main() {
  Widget buildTestWidget({
    Duration elapsed = Duration.zero,
    VoidCallback? onCancel,
    List<double> amplitudeValues = const [],
  }) {
    return MaterialApp(
      home: Scaffold(
        body: RecordingOverlay(
          elapsed: elapsed,
          onCancel: onCancel ?? () {},
          amplitudeValues: amplitudeValues,
        ),
      ),
    );
  }

  group('RecordingOverlay', () {
    testWidgets('shows red recording indicator', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      final redDot = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color == Colors.red,
      );
      expect(redDot, findsOneWidget);
    });

    testWidgets('shows formatted elapsed time', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(elapsed: const Duration(seconds: 3)),
      );

      expect(find.text('0:03'), findsOneWidget);
    });

    testWidgets('shows an explicit cancel button instead of slide copy', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('Cancel'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      expect(find.text('Slide to cancel'), findsNothing);
      expect(find.bySemanticsLabel('Cancel'), findsWidgets);
    });

    testWidgets('tapping cancel invokes the callback', (tester) async {
      var cancelled = false;

      await tester.pumpWidget(
        buildTestWidget(onCancel: () => cancelled = true),
      );

      await tester.tap(find.text('Cancel'));
      await tester.pump();

      expect(cancelled, true);
    });

    testWidgets('timer updates as elapsed changes', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(elapsed: const Duration(seconds: 5)),
      );
      expect(find.text('0:05'), findsOneWidget);

      await tester.pumpWidget(
        buildTestWidget(elapsed: const Duration(seconds: 10)),
      );
      expect(find.text('0:10'), findsOneWidget);
    });

    testWidgets('shows 0:00 initially', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.text('0:00'), findsOneWidget);
    });

    testWidgets('formats minutes and seconds correctly', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(elapsed: const Duration(minutes: 2, seconds: 35)),
      );
      expect(find.text('2:35'), findsOneWidget);
    });

    testWidgets('renders AmplitudeBars when amplitudeValues provided', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(amplitudeValues: [0.1, 0.5, 0.8, 0.3]),
      );
      expect(find.byType(AmplitudeBars), findsOneWidget);
    });

    testWidgets('renders AmplitudeBars even with empty values', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.byType(AmplitudeBars), findsOneWidget);
    });

    testWidgets('red dot and cancel button still present with amplitude bars', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(
          elapsed: const Duration(seconds: 7),
          amplitudeValues: [0.2, 0.4, 0.6],
        ),
      );

      final redDot = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color == Colors.red,
      );
      expect(redDot, findsOneWidget);
      expect(find.text('0:07'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });
  });
}
