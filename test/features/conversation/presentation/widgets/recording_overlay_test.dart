import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/amplitude_bars.dart';
import 'package:flutter_app/shared/widgets/media/recording_overlay.dart';

Future<void> _loadRecordingLayoutFonts() async {
  final config = File('.dart_tool/package_config.json').absolute;
  final packages =
      (jsonDecode(await config.readAsString())
              as Map<String, dynamic>)['packages']
          as List<dynamic>;
  final flutter = packages.cast<Map<String, dynamic>>().singleWhere(
    (package) => package['name'] == 'flutter',
  );
  final sdk = Directory.fromUri(
    config.uri.resolve(flutter['rootUri'] as String),
  ).parent.parent;
  for (final font in [
    (
      family: 'RecordingRoboto',
      path: 'bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
    ),
    (
      family: 'RecordingArabic',
      path:
          'engine/src/flutter/txt/third_party/fonts/NotoNaskhArabic-Regular.ttf',
    ),
  ]) {
    await (FontLoader(font.family)..addFont(
          File(
            '${sdk.path}/${font.path}',
          ).readAsBytes().then(ByteData.sublistView),
        ))
        .load();
  }
}

// Inspect actual drawLine ink, including round caps and the render tree's
// rectangular clips. CustomPaint's layout bounds alone miss escaping bars.
List<Rect> _waveformInkRects(RenderBox overlay) {
  final canvas = TestRecordingCanvas();
  final context = TestRecordingPaintingContext(canvas);
  overlay.paint(context, Offset.zero);
  context.dispose();

  var offset = Offset.zero;
  var clip = Rect.largest;
  final saved = <({Offset offset, Rect clip})>[];
  final inkRects = <Rect>[];
  for (final recorded in canvas.invocations) {
    final call = recorded.invocation;
    final arguments = call.positionalArguments;
    switch (call.memberName) {
      case #save:
      case #saveLayer:
        saved.add((offset: offset, clip: clip));
      case #restore:
        final state = saved.removeLast();
        offset = state.offset;
        clip = state.clip;
      case #translate:
        offset += Offset(arguments[0] as double, arguments[1] as double);
      case #clipRect:
        clip = clip.intersect((arguments[0] as Rect).shift(offset));
      case #clipRRect:
        clip = clip.intersect((arguments[0] as RRect).outerRect.shift(offset));
      case #drawLine:
        final paint = arguments[2] as Paint;
        final ink = Rect.fromPoints(
          arguments[0] as Offset,
          arguments[1] as Offset,
        ).inflate(paint.strokeWidth / 2).shift(offset).intersect(clip);
        if (!ink.isEmpty) {
          inkRects.add(ink);
        }
    }
  }
  return inkRects;
}

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

  group('recording waveform timer separation', () {
    setUpAll(_loadRecordingLayoutFonts);

    for (final locale in const [Locale('en'), Locale('ar')]) {
      for (final composer in [
        // At 390px, chat reserves 32px padding, two 48px controls and 16px gaps.
        (name: 'chat', width: 246.0, seconds: 7, samples: 25),
        // Thought reserves 24px padding, two 44px controls and 20px gaps.
        (name: 'Thought', width: 258.0, seconds: 14, samples: 24),
      ]) {
        testWidgets('${composer.name} at 390px in ${locale.languageCode}', (
          tester,
        ) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(390, 844);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            MaterialApp(
              locale: locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: ThemeData(
                fontFamily: 'RecordingRoboto',
                fontFamilyFallback: const ['RecordingArabic'],
              ),
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: composer.width,
                    child: RecordingOverlay(
                      elapsed: Duration(seconds: composer.seconds),
                      onCancel: () {},
                      amplitudeValues: List.generate(
                        composer.samples,
                        (index) => 0.2 + (index % 5) * 0.15,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );

          final overlay = tester.renderObject<RenderBox>(
            find.byType(RecordingOverlay),
          );
          final timer = tester
              .getRect(
                find.text('0:${composer.seconds.toString().padLeft(2, '0')}'),
              )
              .shift(-overlay.localToGlobal(Offset.zero));
          final waveformInk = _waveformInkRects(overlay);

          expect(waveformInk, isNotEmpty);
          expect(
            waveformInk.where((ink) => ink.overlaps(timer)),
            isEmpty,
            reason: 'Live waveform strokes must leave the elapsed timer clear.',
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
