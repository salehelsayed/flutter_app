import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/posts/presentation/widgets/compose_post_sheet.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/audio_player_widget.dart';
import 'package:flutter_app/shared/widgets/media/recording_overlay.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

import '../../../shared/fakes/fake_audio_recorder_service.dart';
import '../../../shared/fakes/fake_just_audio.dart';

void main() {
  late FakeAudioRecorderService recorder;
  late List<ComposePostResult> shared;

  setUp(() {
    recorder = FakeAudioRecorderService()
      ..fakeOutputPath = '/tmp/thought.m4a'
      ..fakeDurationMs = 18000;
    shared = [];
  });

  Future<void> open(WidgetTester tester) async {
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
            onSubmitWithOutcome: (result) async {
              shared.add(result);
              return ComposePostSubmitOutcome.keepSheetOpen;
            },
          ),
        ),
      ),
    );
  }

  Finder card() => find.byKey(const ValueKey('thought-voice-recording'));
  Finder voice() => find.byKey(const ValueKey('thought-voice-card'));
  ElevatedButton share(WidgetTester tester) =>
      tester.widget(find.byKey(const ValueKey('thought-composer-share')));

  Future<void> record(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Voice'));
    await tester.pumpAndSettle();
  }

  testWidgets('the field invites a voice note', (tester) async {
    await open(tester);
    expect(find.text('say something, or just talk'), findsOneWidget);
  });

  testWidgets('the mic records in the sheet, not on the toolbar', (
    tester,
  ) async {
    await open(tester);
    await record(tester);

    expect(card(), findsOneWidget);
    expect(find.byType(RecordingOverlay), findsNothing);
    expect(
      find.descendant(of: card(), matching: find.text('recording')),
      findsOneWidget,
    );
    expect(find.text('up to 3 min · you can write after'), findsOneWidget);
    recorder.emitDuration(const Duration(seconds: 14));
    await tester.pump();
    expect(find.descendant(of: card(), matching: find.text('0:14')), findsOne);
    expect(share(tester).onPressed, isNull);
  });

  testWidgets('pause holds the recording and resume carries on', (
    tester,
  ) async {
    await open(tester);
    await record(tester);

    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    expect(recorder.pauseCallCount, 1);
    expect(recorder.isRecording, isTrue);

    await tester.tap(find.byTooltip('Resume'));
    await tester.pump();
    expect(recorder.resumeCallCount, 1);
    expect(find.byTooltip('Pause'), findsOneWidget);
  });

  testWidgets('cancel throws the recording away', (tester) async {
    await open(tester);
    await record(tester);

    await tester.tap(
      find.descendant(of: card(), matching: find.text('Cancel')),
    );
    await tester.pumpAndSettle();
    expect(recorder.cancelCallCount, 1);
    expect(card(), findsNothing);
    expect(voice(), findsNothing);
  });

  testWidgets('stop turns the recording into the card friends will see', (
    tester,
  ) async {
    await open(tester);
    await record(tester);
    recorder.emitAmplitude(.6);
    await tester.tap(find.byTooltip('Stop'));
    await tester.pumpAndSettle();

    expect(card(), findsNothing);
    expect(
      find.descendant(of: voice(), matching: find.byType(AudioPlayerWidget)),
      findsOneWidget,
    );
    expect(share(tester).onPressed, isNotNull, reason: 'voice only is fine');
    await tester.tap(find.byKey(const ValueKey('thought-composer-share')));
    await tester.pump();
    expect(shared.single.text, '');
    expect(shared.single.mediaDrafts.single.kind, 'voice');
    expect(shared.single.mediaDrafts.single.durationMs, 18000);
  });

  testWidgets('the X on the voice card discards it', (tester) async {
    await open(tester);
    await record(tester);
    await tester.tap(find.byTooltip('Stop'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Remove voice note'));
    await tester.pumpAndSettle();
    expect(voice(), findsNothing);
    expect(share(tester).onPressed, isNull);
  });

  testWidgets('a thought stops recording itself at 3:00', (tester) async {
    await open(tester);
    await record(tester);

    recorder.emitDuration(const Duration(minutes: 2, seconds: 59));
    await tester.pump();
    expect(recorder.stopCallCount, 0);
    recorder.emitDuration(const Duration(minutes: 3));
    await tester.pumpAndSettle();
    expect(recorder.stopCallCount, 1);
    expect(voice(), findsOneWidget);
  });
}
