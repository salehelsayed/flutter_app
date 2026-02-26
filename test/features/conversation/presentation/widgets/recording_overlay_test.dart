import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/recording_overlay.dart';

void main() {
  Widget buildTestWidget({
    Duration elapsed = Duration.zero,
    VoidCallback? onCancel,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: RecordingOverlay(
          elapsed: elapsed,
          onCancel: onCancel ?? () {},
        ),
      ),
    );
  }

  group('RecordingOverlay', () {
    testWidgets('shows red recording indicator', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      // Find the red dot container
      final redDot = find.byWidgetPredicate(
        (w) => w is Container && w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color == Colors.red,
      );
      expect(redDot, findsOneWidget);
    });

    testWidgets('shows formatted elapsed time', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        elapsed: const Duration(seconds: 3),
      ));

      expect(find.text('0:03'), findsOneWidget);
    });

    testWidgets('shows "Slide to cancel" hint text', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.text('Slide to cancel'), findsOneWidget);
    });

    testWidgets('timer updates as elapsed changes', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        elapsed: const Duration(seconds: 5),
      ));
      expect(find.text('0:05'), findsOneWidget);

      await tester.pumpWidget(buildTestWidget(
        elapsed: const Duration(seconds: 10),
      ));
      expect(find.text('0:10'), findsOneWidget);
    });

    testWidgets('shows 0:00 initially', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.text('0:00'), findsOneWidget);
    });

    testWidgets('formats minutes and seconds correctly', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        elapsed: const Duration(minutes: 2, seconds: 35),
      ));
      expect(find.text('2:35'), findsOneWidget);
    });
  });
}
