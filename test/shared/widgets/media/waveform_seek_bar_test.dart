import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
