import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/voice_record_button.dart';

void main() {
  Widget buildTestWidget({
    VoidCallback? onTapDown,
    VoidCallback? onTapUp,
    VoidCallback? onTapCancel,
    bool isRecording = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: VoiceRecordButton(
            onTapDown: onTapDown ?? () {},
            onTapUp: onTapUp ?? () {},
            onTapCancel: onTapCancel ?? () {},
            isRecording: isRecording,
          ),
        ),
      ),
    );
  }

  group('VoiceRecordButton', () {
    testWidgets('renders mic icon when not recording', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
    });

    testWidgets('renders stop icon when recording', (tester) async {
      await tester.pumpWidget(buildTestWidget(isRecording: true));
      expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
    });

    testWidgets('onTapDown called on long press start', (tester) async {
      var called = false;
      await tester.pumpWidget(buildTestWidget(onTapDown: () => called = true));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(VoiceRecordButton)),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(called, true);
      await gesture.up();
    });

    testWidgets('onTapUp called on long press end', (tester) async {
      var downCalled = false;
      var upCalled = false;
      var cancelCalled = false;
      await tester.pumpWidget(
        buildTestWidget(
          onTapDown: () => downCalled = true,
          onTapUp: () => upCalled = true,
          onTapCancel: () => cancelCalled = true,
        ),
      );

      // Start long press
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(VoiceRecordButton)),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(downCalled, true);

      // End long press
      await gesture.up();
      await tester.pump();
      expect(upCalled, true);
      expect(cancelCalled, false);
    });

    testWidgets('drag-left cancel prevents send on release', (tester) async {
      var downCalled = false;
      var upCalled = false;
      var cancelCalled = false;
      await tester.pumpWidget(
        buildTestWidget(
          onTapDown: () => downCalled = true,
          onTapUp: () => upCalled = true,
          onTapCancel: () => cancelCalled = true,
        ),
      );

      final center = tester.getCenter(find.byType(VoiceRecordButton));
      final gesture = await tester.startGesture(center);
      await tester.pump(const Duration(milliseconds: 500));
      expect(downCalled, true);

      // Exceed cancel threshold.
      await gesture.moveBy(const Offset(-120, 0));
      await tester.pump();
      expect(cancelCalled, true);

      // Releasing should not send after cancel.
      await gesture.up();
      await tester.pump();
      expect(upCalled, false);
    });

    testWidgets('onTapCancel called when drag exits button bounds', (
      tester,
    ) async {
      var cancelCalled = false;
      await tester.pumpWidget(
        buildTestWidget(onTapCancel: () => cancelCalled = true),
      );

      final center = tester.getCenter(find.byType(VoiceRecordButton));
      final gesture = await tester.startGesture(center);
      await tester.pump(const Duration(milliseconds: 500));

      // Drag far away from button
      await gesture.moveBy(const Offset(-300, 0));
      await tester.pump();
      // Cancel is triggered by the long press cancel
      await gesture.cancel();
      await tester.pump();

      expect(cancelCalled, true);
    });

    testWidgets('has teal accent color', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      final icon = tester.widget<Icon>(find.byIcon(Icons.mic_rounded));
      expect(icon.color, const Color(0xFF1DB954));
    });
  });
}
