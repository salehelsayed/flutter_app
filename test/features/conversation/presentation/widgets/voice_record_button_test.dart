import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/voice_record_button.dart';

void main() {
  Widget buildTestWidget({
    required bool isRecording,
    required VoidCallback onTapDown,
    required VoidCallback onTapUp,
    required VoidCallback onTapCancel,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: VoiceRecordButton(
            onTapDown: onTapDown,
            onTapUp: onTapUp,
            onTapCancel: onTapCancel,
            isRecording: isRecording,
          ),
        ),
      ),
    );
  }

  group('VoiceRecordButton', () {
    testWidgets('renders a larger accessible tap target', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          isRecording: false,
          onTapDown: () {},
          onTapUp: () {},
          onTapCancel: () {},
        ),
      );

      expect(
        tester.getSize(find.byType(VoiceRecordButton)),
        const Size(48, 48),
      );
      expect(find.bySemanticsLabel('Start voice recording'), findsOneWidget);
    });

    testWidgets(
      'starts recording immediately on tap down and does not stop on the same tap',
      (tester) async {
        var isRecording = false;
        var downCount = 0;
        var upCount = 0;
        var cancelCount = 0;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: StatefulBuilder(
                  builder: (context, setState) {
                    return VoiceRecordButton(
                      isRecording: isRecording,
                      onTapDown: () {
                        downCount++;
                        setState(() => isRecording = true);
                      },
                      onTapUp: () {
                        upCount++;
                        setState(() => isRecording = false);
                      },
                      onTapCancel: () {
                        cancelCount++;
                        setState(() => isRecording = false);
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        );

        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(VoiceRecordButton)),
        );
        await tester.pump();

        expect(downCount, 1);
        expect(upCount, 0);
        expect(cancelCount, 0);
        expect(isRecording, true);
        expect(find.byIcon(Icons.stop_rounded), findsOneWidget);

        await gesture.up();
        await tester.pump();

        expect(downCount, 1);
        expect(upCount, 0);
        expect(cancelCount, 0);
        expect(isRecording, true);
        expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
      },
    );

    testWidgets('stops recording on a second tap when already recording', (
      tester,
    ) async {
      var isRecording = false;
      var downCount = 0;
      var upCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: StatefulBuilder(
                builder: (context, setState) {
                  return VoiceRecordButton(
                    isRecording: isRecording,
                    onTapDown: () {
                      downCount++;
                      setState(() => isRecording = true);
                    },
                    onTapUp: () {
                      upCount++;
                      setState(() => isRecording = false);
                    },
                    onTapCancel: () {},
                  );
                },
              ),
            ),
          ),
        ),
      );

      final firstGesture = await tester.startGesture(
        tester.getCenter(find.byType(VoiceRecordButton)),
      );
      await tester.pump();
      await firstGesture.up();
      await tester.pump();
      expect(isRecording, true);

      await tester.tap(find.byType(VoiceRecordButton));
      await tester.pump();

      expect(downCount, 1);
      expect(upCount, 1);
      expect(isRecording, false);
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
    });

    testWidgets(
      'calls onTapCancel when a recording start gesture is cancelled',
      (tester) async {
        var isRecording = false;
        var cancelCount = 0;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: StatefulBuilder(
                  builder: (context, setState) {
                    return VoiceRecordButton(
                      isRecording: isRecording,
                      onTapDown: () {
                        setState(() => isRecording = true);
                      },
                      onTapUp: () {},
                      onTapCancel: () {
                        cancelCount++;
                        setState(() => isRecording = false);
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        );

        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(VoiceRecordButton)),
        );
        await tester.pump();

        await gesture.cancel();
        await tester.pump();

        expect(cancelCount, 1);
        expect(isRecording, false);
        expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      },
    );

    testWidgets('shows the recording state with the stop icon and semantics', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(
          isRecording: true,
          onTapDown: () {},
          onTapUp: () {},
          onTapCancel: () {},
        ),
      );

      expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
      expect(find.bySemanticsLabel('Stop recording'), findsOneWidget);
    });
  });
}
