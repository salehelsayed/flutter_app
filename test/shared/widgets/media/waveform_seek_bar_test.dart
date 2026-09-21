import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/feed/presentation/widgets/swipe_to_quote_bubble.dart';
import 'package:flutter_app/shared/widgets/media/waveform_seek_bar.dart';

void main() {
  Widget buildApp({
    List<double>? waveform,
    double progress = 0.0,
    ValueChanged<double>? onSeek,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 200,
          height: 40,
          child: WaveformSeekBar(
            waveform: waveform,
            progress: progress,
            onSeek: onSeek,
          ),
        ),
      ),
    );
  }

  testWidgets('UI25 cancelled press must not seek before recognition', (tester) async {
    final seeks = <double>[];
    await tester.pumpWidget(buildApp(onSeek: seeks.add));
    final gesture = await tester.startGesture(tester.getCenter(find.byType(WaveformSeekBar)));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.cancel();
    await tester.pump();
    expect(seeks, isEmpty);
    await tester.tapAt(tester.getTopLeft(find.byType(WaveformSeekBar)) + const Offset(50, 20));
    expect(seeks, [0.25]);
  });

  testWidgets('UI25 scrolling from a waveform does not seek', (tester) async {
    final seeks = <double>[];
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ListView(
      controller: scroll,
      children: [SizedBox(height: 40, child: WaveformSeekBar(waveform: null, progress: 0, onSeek: seeks.add)),
        const SizedBox(height: 2000)],
    ))));
    final gesture = await tester.startGesture(tester.getCenter(find.byType(WaveformSeekBar)));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.moveBy(const Offset(0, -30)); // Win the scroll arena.
    await gesture.moveBy(const Offset(0, -120));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));
    expect(seeks, isEmpty);
  });

  testWidgets('UI25 nested waveform has exclusive seek reply and scroll outcomes', (
    tester,
  ) async {
    final seeks = <double>[];
    var replies = 0;
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ListView(
      controller: scroll,
      children: [
        const SizedBox(height: 160),
        SwipeToQuoteBubble(
          onQuoteTriggered: () => replies++,
          child: SizedBox(height: 40, child: WaveformSeekBar(
            waveform: null, progress: 0, onSeek: seeks.add,
          )),
        ),
        const SizedBox(height: 1600),
      ],
    ))));
    final bar = find.byType(WaveformSeekBar);
    await tester.tapAt(tester.getCenter(bar));
    await tester.pumpAndSettle();
    expect(seeks, [0.5]);
    expect(replies, 0);
    expect(scroll.offset, 0);

    seeks.clear();
    final reply = await tester.startGesture(tester.getCenter(bar));
    await tester.pump(const Duration(milliseconds: 200));
    await reply.moveBy(const Offset(30, 0));
    for (var i = 0; i < 12; i++) {
      await reply.moveBy(const Offset(4, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await reply.up();
    await tester.pumpAndSettle();
    expect(seeks, isEmpty);
    expect(replies, 1);
    expect(scroll.offset, 0);

    final vertical = await tester.startGesture(tester.getCenter(bar));
    await tester.pump(const Duration(milliseconds: 200));
    await vertical.moveBy(const Offset(0, -30));
    await vertical.moveBy(const Offset(0, -80));
    await vertical.up();
    await tester.pumpAndSettle();
    expect(seeks, isEmpty);
    expect(replies, 1);
    expect(scroll.offset, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  group('WaveformSeekBar', () {
    testWidgets('renders CustomPaint with waveform data', (tester) async {
      await tester.pumpWidget(buildApp(
        waveform: [0.1, 0.5, 0.8, 0.3, 0.6],
        progress: 0.5,
      ));

      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('no errors with null waveform', (tester) async {
      await tester.pumpWidget(buildApp(waveform: null, progress: 0.0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('no errors with empty waveform', (tester) async {
      await tester.pumpWidget(buildApp(waveform: [], progress: 0.0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('no errors with all-zero waveform', (tester) async {
      await tester.pumpWidget(buildApp(
        waveform: List.filled(50, 0.0),
        progress: 0.5,
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('onSeek callback fires with 0.0–1.0 value on tap',
        (tester) async {
      double? seekValue;

      await tester.pumpWidget(buildApp(
        waveform: List.filled(50, 0.5),
        progress: 0.0,
        onSeek: (v) => seekValue = v,
      ));

      // Tap roughly in the center of the 200px-wide widget
      final bar = find.byType(WaveformSeekBar);
      final center = tester.getCenter(bar);
      await tester.tapAt(center);
      await tester.pump();

      expect(seekValue, isNotNull);
      expect(seekValue!, greaterThanOrEqualTo(0.0));
      expect(seekValue!, lessThanOrEqualTo(1.0));
      // Center tap should be roughly 0.5
      expect(seekValue!, closeTo(0.5, 0.15));
    });

    testWidgets('progress visually accepted at boundaries', (tester) async {
      // progress 0.0 — all unplayed
      await tester.pumpWidget(buildApp(
        waveform: [0.5, 0.5, 0.5],
        progress: 0.0,
      ));
      expect(tester.takeException(), isNull);

      // progress 1.0 — all played
      await tester.pumpWidget(buildApp(
        waveform: [0.5, 0.5, 0.5],
        progress: 1.0,
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders GestureDetector for seek interaction', (tester) async {
      await tester.pumpWidget(buildApp(
        waveform: [0.5],
        progress: 0.0,
        onSeek: (_) {},
      ));

      expect(find.byType(GestureDetector), findsWidgets);
    });
  });
}
