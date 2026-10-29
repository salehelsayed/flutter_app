import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/features/translate_preview/model_delivery_contract.dart';
import 'package:flutter_app/features/translate_preview/on_device_ai.dart';
import 'package:flutter_app/features/translate_preview/translate_preview_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_model_delivery_controller.dart';

const _total = 2600000000;
const _arabicThought = 'الجو جميل اليوم، مين جاي البحر؟';

class _RecordingAi implements OnDeviceAi {
  final calls = <String>[];
  final next = Completer<String>();

  @override
  Future<String> translate(String text, {required String languageName}) {
    calls.add('translate($languageName)');
    return next.future;
  }

  @override
  Future<String> transcribe(String audioPath) {
    calls.add('transcribe');
    return next.future;
  }
}

Future<(FakeModelDeliveryController, _RecordingAi)> _pumpLinks(
  WidgetTester tester,
  ModelDeliveryState state,
) async {
  final controller = FakeModelDeliveryController(state);
  final ai = _RecordingAi();
  await tester.pumpWidget(
    localizedApp(
      Scaffold(
        body: Column(
          children: [
            TranslatePreview(
              text: _arabicThought,
              ai: ai,
              delivery: controller,
            ),
            TranscribePreview(
              audioPath: '/tmp/voice.m4a',
              ai: ai,
              delivery: controller,
            ),
          ],
        ),
      ),
    ),
  );
  return (controller, ai);
}

void main() {
  testWidgets('6a unsupported phone: no link at all', (tester) async {
    await _pumpLinks(tester, const ModelUnsupported());
    expect(find.text('See translation'), findsNothing);
    expect(find.text('Transcribe'), findsNothing);
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('1a/1b not downloaded: both links open the one offer sheet and '
      'run nothing', (tester) async {
    final (controller, ai) = await _pumpLinks(
      tester,
      const ModelNotDownloaded(
        totalBytes: _total,
        freeBytes: 18400000000,
        onWifi: true,
      ),
    );
    await tester.tap(find.text('See translation'));
    await tester.pumpAndSettle();
    expect(find.text('Your private translator'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Transcribe'));
    await tester.pumpAndSettle();
    expect(find.text('Your private translator'), findsOneWidget);
    expect(ai.calls, isEmpty);
    expect(controller.calls, isEmpty);
  });

  testWidgets('not enough space: the link opens the greyed offer', (
    tester,
  ) async {
    await _pumpLinks(
      tester,
      const ModelNotEnoughSpace(
        totalBytes: _total,
        neededBytes: 2800000000,
        freeBytes: 1100000000,
      ),
    );
    await tester.tap(find.text('See translation'));
    await tester.pumpAndSettle();
    expect(find.text('Needs 2.8 GB'), findsOneWidget);
    expect(find.text('Free up space'), findsOneWidget);
  });

  testWidgets('3b downloading: every link reads the progress and reopens the '
      'progress sheet', (tester) async {
    await _pumpLinks(
      tester,
      const ModelDownloading(receivedBytes: 1100000000, totalBytes: _total),
    );
    expect(find.text('Getting translation ready · 42%'), findsNWidgets(2));
    expect(find.text('See translation'), findsNothing);
    expect(find.text('Transcribe'), findsNothing);

    await tester.tap(find.text('Getting translation ready · 42%').first);
    await tester.pumpAndSettle();
    expect(find.text('Getting translation ready'), findsOneWidget);
    expect(find.text('1.1 of 2.6 GB'), findsOneWidget);
  });

  for (final (name, state) in [
    (
      'waiting for Wi-Fi',
      const ModelWaitingForWifi(receivedBytes: 1100000000, totalBytes: _total),
    ),
    (
      'paused',
      const ModelPaused(receivedBytes: 1100000000, totalBytes: _total),
    ),
  ]) {
    testWidgets('$name: links read Translation paused and open 3c', (
      tester,
    ) async {
      await _pumpLinks(tester, state);
      expect(find.text('Translation paused · 42%'), findsNWidgets(2));
      await tester.tap(find.text('Translation paused · 42%').first);
      await tester.pumpAndSettle();
      expect(find.text('Waiting for Wi-Fi'), findsOneWidget);
    });
  }

  testWidgets("failed: links read Translation didn't download, Try again "
      'retries', (tester) async {
    final (controller, _) = await _pumpLinks(tester, const ModelFailed());
    expect(find.text("Translation didn't download"), findsNWidgets(2));
    await tester.tap(find.text('Try again').first);
    expect(controller.calls, ['retry']);
  });

  testWidgets('4a ready: the link the user tapped just works, into the Mknoon '
      'language', (tester) async {
    final (controller, ai) = await _pumpLinks(
      tester,
      const ModelDownloading(receivedBytes: 2500000000, totalBytes: _total),
    );
    expect(find.text('Getting translation ready · 96%'), findsNWidgets(2));

    controller.state.value = const ModelReady(sizeBytes: _total);
    await tester.pump();
    expect(find.text('See translation'), findsOneWidget);
    expect(find.text('Transcribe'), findsOneWidget);

    await tester.tap(find.text('See translation'));
    await tester.pump();
    expect(ai.calls, ['translate(English)']);
    ai.next.complete("The weather is lovely today, who's coming to the beach?");
    await tester.pump();
    expect(
      find.text("The weather is lovely today, who's coming to the beach?"),
      findsOneWidget,
    );
    expect(find.text('BETA'), findsOneWidget);
    expect(find.text('Only on your phone'), findsOneWidget);
    expect(find.text('Hide'), findsOneWidget);
    expect(controller.calls, isEmpty);
  });
}
