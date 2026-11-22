import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/attachment_preview_strip.dart';
import 'package:flutter_app/features/posts/application/attach_post_media_use_case.dart';
import 'package:flutter_app/features/posts/presentation/widgets/compose_post_sheet.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../shared/fakes/fake_audio_recorder_service.dart';

void main() {
  testWidgets('a picked Thought video has a localized accessibility label', (
    tester,
  ) async {
    const bound = Duration(seconds: 3);
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);

    await tester
        .pumpWidget(
          MaterialApp(
            locale: const Locale('ar'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ComposePostSheet(
                thoughtsOnly: true,
                eligibleContacts: const [],
                onSubmit: (_) async {},
                onPickMedia: () async => (
                  drafts: const [
                    PostMediaDraft(
                      localFilePath: '/picked/selected.mp4',
                      mime: 'video/mp4',
                    ),
                  ],
                  leftOut: false,
                ),
              ),
            ),
          ),
        )
        .timeout(bound);

    final video = find.bySemanticsLabel('فيديو');
    expect(video, findsNothing);
    await tester
        .tap(find.byKey(const ValueKey('thought-composer-media')).hitTestable())
        .timeout(bound);
    await tester.pump().timeout(bound);

    expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
    expect(video, findsOneWidget);
  });

  testWidgets('allows media-only submit after attaching image drafts', (
    tester,
  ) async {
    ComposePostResult? submitted;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
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

    expect(
      tester
          .widget<AttachmentPreviewStrip>(find.byType(AttachmentPreviewStrip))
          .attachments,
      hasLength(2),
    );

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
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
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
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
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

    expect(find.text('Cancel'), findsOneWidget);

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
