import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/posts/presentation/widgets/compose_post_sheet.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

import '../../../shared/fakes/fake_audio_recorder_service.dart';
import '../../../shared/fakes/fake_just_audio.dart';

const _hint = 'From your voice. Check the words before you send.';

void main() {
  late FakeAudioRecorderService recorder;
  late List<ComposePostResult> shared;
  late List<String> transcribed;

  Future<void> open(
    WidgetTester tester, {
    Future<String?> Function(String path)? transcribe,
  }) async {
    recorder = FakeAudioRecorderService()
      ..fakeOutputPath = '/tmp/thought.m4a'
      ..fakeDurationMs = 9000;
    shared = [];
    transcribed = [];
    final original = JustAudioPlatform.instance;
    JustAudioPlatform.instance = FakeJustAudioPlatform();
    addTearDown(() => JustAudioPlatform.instance = original);
    addTearDown(recorder.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ComposePostSheet(
            thoughtsOnly: true,
            eligibleContacts: const [],
            audioRecorderService: recorder,
            transcribeVoice: transcribe == null
                ? null
                : (path) {
                    transcribed.add(path);
                    return transcribe(path);
                  },
            onSubmitWithOutcome: (result) async {
              shared.add(result);
              return ComposePostSubmitOutcome.keepSheetOpen;
            },
          ),
        ),
      ),
    );
  }

  Finder sendAsText() => find.byKey(const ValueKey('thought-voice-as-text'));
  Finder voiceCard() => find.byKey(const ValueKey('thought-voice-card'));
  String text(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const ValueKey('thought-composer-text')))
      .controller!
      .text;

  Future<void> record(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Voice'));
    await tester.pumpAndSettle();
  }

  testWidgets('without a transcriber there is no Send as text', (tester) async {
    await open(tester);
    await record(tester);
    expect(sendAsText(), findsNothing);
  });

  testWidgets('Send as text turns the recording into the Thought\'s words', (
    tester,
  ) async {
    await open(tester, transcribe: (_) async => 'what I think so far');
    await record(tester);

    final button = tester.getSize(sendAsText());
    expect(button.height, greaterThanOrEqualTo(44));
    expect(
      find.descendant(of: sendAsText(), matching: find.text('Send as text')),
      findsOneWidget,
    );
    await tester.tap(sendAsText());
    await tester.pumpAndSettle();

    expect(transcribed, ['/tmp/thought.m4a']);
    expect(text(tester), 'what I think so far');
    expect(voiceCard(), findsNothing, reason: 'the voice note is dropped');
    expect(find.text(_hint), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('thought-composer-share')));
    await tester.pump();
    expect(shared.single.text, 'what I think so far');
    expect(shared.single.mediaDrafts, isEmpty);
  });

  testWidgets('the words follow what was already written', (tester) async {
    await open(tester, transcribe: (_) async => 'and the reef is loud');
    await tester.enterText(
      find.byKey(const ValueKey('thought-composer-text')),
      'back in dahab',
    );
    await record(tester);
    await tester.tap(sendAsText());
    await tester.pumpAndSettle();
    expect(text(tester), 'back in dahab and the reef is loud');
  });

  testWidgets('while it works it says Transcribing…', (tester) async {
    final pending = Completer<String?>();
    await open(tester, transcribe: (_) => pending.future);
    await record(tester);
    await tester.tap(sendAsText());
    await tester.pump();
    await tester.pump();

    expect(find.text('Transcribing…'), findsOneWidget);
    pending.complete('done');
    await tester.pumpAndSettle();
    expect(text(tester), 'done');
  });

  testWidgets('the hint goes once the words are cleared', (tester) async {
    await open(tester, transcribe: (_) async => 'what I think');
    await record(tester);
    await tester.tap(sendAsText());
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('thought-composer-text')),
      '',
    );
    await tester.pump();
    expect(find.text(_hint), findsNothing);
  });

  testWidgets('a failure keeps the recording: Keep as voice or Try again', (
    tester,
  ) async {
    var calls = 0;
    await open(
      tester,
      transcribe: (_) async {
        calls++;
        if (calls == 1) throw StateError('model failed');
        return 'second try';
      },
    );
    await record(tester);
    await tester.tap(sendAsText());
    await tester.pumpAndSettle();

    expect(find.text("Couldn't transcribe"), findsOneWidget);
    expect(find.text('Your recording is still here.'), findsOneWidget);
    expect(find.text('Keep as voice'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(transcribed, ['/tmp/thought.m4a', '/tmp/thought.m4a']);
    expect(text(tester), 'second try');
    expect(find.text("Couldn't transcribe"), findsNothing);
  });

  testWidgets('Keep as voice turns the kept recording into the voice card', (
    tester,
  ) async {
    await open(tester, transcribe: (_) async => throw StateError('no'));
    await record(tester);
    await tester.tap(sendAsText());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep as voice'));
    await tester.pumpAndSettle();

    expect(voiceCard(), findsOneWidget);
    expect(find.text("Couldn't transcribe"), findsNothing);
    await tester.tap(find.byKey(const ValueKey('thought-composer-share')));
    await tester.pump();
    expect(shared.single.mediaDrafts.single.localFilePath, '/tmp/thought.m4a');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('no transcript yet (model not ready) keeps it as voice', (
    tester,
  ) async {
    await open(tester, transcribe: (_) async => null);
    await record(tester);
    await tester.tap(sendAsText());
    await tester.pumpAndSettle();
    expect(voiceCard(), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
