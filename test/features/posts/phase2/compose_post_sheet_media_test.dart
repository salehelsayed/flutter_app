import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/posts/application/attach_post_media_use_case.dart';
import 'package:flutter_app/features/posts/presentation/widgets/compose_post_sheet.dart';

import '../../../shared/fakes/fake_audio_recorder_service.dart';

void main() {
  testWidgets('allows media-only submit after attaching image drafts', (
    tester,
  ) async {
    ComposePostResult? submitted;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ComposePostSheet(
            eligibleContacts: const [],
            onAttachMedia: () async => const [
              PostMediaDraft(localFilePath: '/tmp/one.jpg', mime: 'image/jpeg'),
              PostMediaDraft(localFilePath: '/tmp/two.jpg', mime: 'image/jpeg'),
            ],
            onSubmit: (result) async {
              submitted = result;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Media'));
    await tester.pumpAndSettle();

    expect(find.text('2 attachments'), findsOneWidget);

    await tester.tap(find.text('Post'));
    await tester.pumpAndSettle();

    expect(submitted, isNotNull);
    expect(submitted!.text, isEmpty);
    expect(submitted!.mediaDrafts, hasLength(2));
  });

  testWidgets('allows voice-only submit after attaching a voice draft', (
    tester,
  ) async {
    ComposePostResult? submitted;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ComposePostSheet(
            eligibleContacts: const [],
            onAttachVoice: () async => const PostMediaDraft(
              localFilePath: '/tmp/voice.m4a',
              mime: 'audio/mp4',
              durationMs: 5000,
              waveform: [0.1, 0.4, 0.8],
            ),
            onSubmit: (result) async {
              submitted = result;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Voice'));
    await tester.pumpAndSettle();

    expect(find.text('Voice attached'), findsOneWidget);

    await tester.tap(find.text('Post'));
    await tester.pumpAndSettle();

    expect(submitted, isNotNull);
    expect(submitted!.mediaDrafts.single.mime, 'audio/mp4');
  });

  testWidgets('records voice inline and persists a waveform draft before post', (
    tester,
  ) async {
    ComposePostResult? submitted;
    final recorder = FakeAudioRecorderService()
      ..fakeOutputPath = '/tmp/post-voice.m4a'
      ..fakeDurationMs = 6400;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ComposePostSheet(
            eligibleContacts: const [],
            audioRecorderService: recorder,
            onSubmit: (result) async {
              submitted = result;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Voice'));
    await tester.pump();

    expect(find.text('Slide to cancel'), findsOneWidget);

    recorder.emitDuration(const Duration(seconds: 4));
    recorder.emitAmplitude(0.2);
    recorder.emitAmplitude(0.6);
    recorder.emitAmplitude(1.0);
    await tester.pump();

    expect(find.text('0:04'), findsOneWidget);

    final stopButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Stop'),
    );
    stopButton.onPressed!.call();
    await tester.pumpAndSettle();

    expect(recorder.isRecording, isFalse);
    expect(find.text('Voice attached'), findsOneWidget);

    await tester.tap(find.text('Post'));
    await tester.pumpAndSettle();

    expect(submitted, isNotNull);
    expect(submitted!.mediaDrafts.single.mime, 'audio/mp4');
    expect(submitted!.mediaDrafts.single.waveform, isNotNull);
    expect(submitted!.mediaDrafts.single.waveform, hasLength(50));
  });
}
