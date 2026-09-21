import 'dart:ui' as ui;
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

  testWidgets('UI25 dragging off recording stop must not send', (tester) async {
    var stops = 0;
    await tester.pumpWidget(buildTestWidget(
      isRecording: true, onTapDown: () {}, onTapUp: () => stops++, onTapCancel: () {},
    ));
    final gesture = await tester.startGesture(tester.getCenter(find.byType(VoiceRecordButton)));
    await gesture.moveBy(const Offset(100, 0));
    await gesture.up();
    await tester.pump();
    expect(stops, 0);
    await tester.tap(find.byType(VoiceRecordButton));
    expect(stops, 1);
  });

  testWidgets('UI25 second pointer cannot turn a recording start into send', (tester) async {
    var recording = false;
    var starts = 0;
    var stops = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(
      child: StatefulBuilder(builder: (context, setState) => VoiceRecordButton(
        isRecording: recording,
        onTapDown: () { starts++; setState(() => recording = true); },
        onTapUp: () => stops++, onTapCancel: () {},
      )),
    ))));
    final point = tester.getCenter(find.byType(VoiceRecordButton));
    final first = await tester.startGesture(point, pointer: 1);
    await tester.pump();
    final second = await tester.startGesture(point, pointer: 2);
    await second.up();
    await first.up();
    await tester.pump();
    expect(starts, 1);
    expect(stops, 0);
  });

  testWidgets('UI25 fast drag aborts provisional start and never stops or sends', (tester) async {
    var starts = 0;
    var stops = 0;
    var cancels = 0;
    await tester.pumpWidget(buildTestWidget(
      isRecording: false, onTapDown: () => starts++, onTapUp: () => stops++, onTapCancel: () => cancels++,
    ));
    final gesture = await tester.startGesture(tester.getCenter(find.byType(VoiceRecordButton)));
    await gesture.moveBy(const Offset(0, 100));
    await gesture.up();
    await tester.pump();
    expect([starts, stops, cancels], [1, 0, 1]);
  });

  testWidgets('UI25 recording stop cancel and removal cannot send', (tester) async {
    var stops = 0;
    await tester.pumpWidget(buildTestWidget(
      isRecording: true, onTapDown: () {}, onTapUp: () => stops++, onTapCancel: () {},
    ));
    final point = tester.getCenter(find.byType(VoiceRecordButton));
    final cancelled = await tester.startGesture(point);
    await tester.pump(const Duration(milliseconds: 200));
    await cancelled.cancel();
    final removed = await tester.startGesture(point);
    await tester.pumpWidget(const SizedBox());
    await removed.up();
    await tester.pump();
    expect(stops, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('UI25 pending idle start teardown cancels without framework errors', (
    tester,
  ) async {
    var starts = 0;
    var stops = 0;
    var cancels = 0;
    await tester.pumpWidget(buildTestWidget(
      isRecording: false,
      onTapDown: () => starts++,
      onTapUp: () => stops++,
      onTapCancel: () => cancels++,
    ));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(VoiceRecordButton)),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect([starts, stops, cancels], [1, 0, 0]);

    await tester.pumpWidget(const SizedBox());
    await gesture.up();
    await tester.pump();

    expect([starts, stops, cancels], [1, 0, 1]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('UI25 pending start teardown after recording rebuild cancels once', (
    tester,
  ) async {
    var recording = false;
    var starts = 0;
    var stops = 0;
    var cancels = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(
      child: StatefulBuilder(builder: (context, setState) => VoiceRecordButton(
        isRecording: recording,
        onTapDown: () { starts++; setState(() => recording = true); },
        onTapUp: () => stops++,
        onTapCancel: () => cancels++,
      )),
    ))));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(VoiceRecordButton)),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await gesture.up();
    await tester.pump();
    expect([starts, stops, cancels], [1, 0, 1]);
    expect(tester.takeException(), isNull);
  });

  for (final recording in [false, true]) {
    testWidgets('UI25 scrolling from mic with recording=$recording never sends', (
      tester,
    ) async {
      var starts = 0;
      var stops = 0;
      var cancels = 0;
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ListView(
        controller: scroll,
        children: [
          const SizedBox(height: 160),
          Center(child: VoiceRecordButton(
            isRecording: recording,
            onTapDown: () => starts++,
            onTapUp: () => stops++,
            onTapCancel: () => cancels++,
          )),
          const SizedBox(height: 1600),
        ],
      ))));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(VoiceRecordButton)),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.moveBy(const Offset(0, -30));
      await gesture.moveBy(const Offset(0, -80));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));
      expect([starts, stops, cancels], recording ? [0, 0, 0] : [1, 0, 1]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('UI25 held active recording stops once on primary release', (
    tester,
  ) async {
    var stops = 0;
    var cancels = 0;
    await tester.pumpWidget(buildTestWidget(
      isRecording: true,
      onTapDown: () => fail('An active recording must not start again'),
      onTapUp: () => stops++,
      onTapCancel: () => cancels++,
    ));
    final point = tester.getCenter(find.byType(VoiceRecordButton));
    final first = await tester.startGesture(point, pointer: 1);
    await tester.pump(const Duration(milliseconds: 600));
    final second = await tester.startGesture(point, pointer: 2);
    await second.up();
    await tester.pump();
    expect([stops, cancels], [0, 0]);
    await first.up();
    await tester.pump();
    expect([stops, cancels], [1, 0]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('UI25 recording button cardinal halo and outside probes', (tester) async {
    var stops = 0;
    await tester.pumpWidget(buildTestWidget(
      isRecording: true, onTapDown: () {}, onTapUp: () => stops++, onTapCancel: () {},
    ));
    final center = tester.getCenter(find.byType(VoiceRecordButton));
    for (final offset in [Offset.zero, Offset(23,0), Offset(-23,0), Offset(0,23), Offset(0,-23)]) {
      final before = stops;
      await tester.tapAt(center + offset);
      await tester.pumpAndSettle();
      expect(stops, before + 1);
    }
    await tester.tapAt(center + const Offset(25,0));
    expect(stops, 5);
  });

  testWidgets('UI25 semantic activation preserves start and stop actions', (tester) async {
    final semantics = tester.ensureSemantics();
    var starts = 0;
    var stops = 0;
    for (final recording in [false, true]) {
      await tester.pumpWidget(buildTestWidget(
        isRecording: recording, onTapDown: () => starts++, onTapUp: () => stops++, onTapCancel: () {},
      ));
      final node = tester.getSemantics(find.bySemanticsLabel(recording ? 'Stop and send voice message' : 'Record voice message'));
      tester.binding.renderViews.single.owner!.semanticsOwner!.performAction(node.id, ui.SemanticsAction.tap);
      await tester.pump();
    }
    semantics.dispose();
    expect([starts, stops], [1, 1]);
  });

  testWidgets('UI25 held recording start survives tooltip timing and release', (tester) async {
    var recording = false;
    var starts = 0;
    var stops = 0;
    var cancels = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(
      child: StatefulBuilder(builder: (context, setState) => VoiceRecordButton(
        isRecording: recording,
        onTapDown: () { starts++; setState(() => recording = true); },
        onTapUp: () => stops++, onTapCancel: () => cancels++,
      )),
    ))));
    final gesture = await tester.startGesture(tester.getCenter(find.byType(VoiceRecordButton)));
    await tester.pump(const Duration(milliseconds: 600));
    expect([starts, stops, cancels], [1, 0, 0]);
    await gesture.up();
    await tester.pump();
    expect([starts, stops, cancels], [1, 0, 0]);
  });

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
      expect(find.bySemanticsLabel('Record voice message'), findsOneWidget);
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
        expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);

        await gesture.up();
        await tester.pump();

        expect(downCount, 1);
        expect(upCount, 0);
        expect(cancelCount, 0);
        expect(isRecording, true);
        expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
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

    testWidgets('shows the recording state with the send icon and semantics', (
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

      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
      expect(find.bySemanticsLabel('Stop and send voice message'), findsOneWidget);
    });
  });
}
