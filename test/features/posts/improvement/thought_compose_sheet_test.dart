import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/attachment_preview_strip.dart';
import 'package:flutter_app/features/posts/application/post_media_draft.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/features/posts/presentation/pick_post_media_drafts.dart';
import 'package:flutter_app/features/posts/presentation/widgets/compose_post_sheet.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../shared/fakes/fake_audio_recorder_service.dart';

void main() {
  Widget scene({
    required Future<ComposePostSubmitOutcome> Function(ComposePostResult)
    submit,
    Future<List<PostMediaDraft>> Function()? media,
    Future<PostMediaPick> Function()? pick,
    FakeAudioRecorderService? recorder,
    Locale locale = const Locale('en'),
    Key? key,
  }) => MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: ComposePostSheet(
        key: key,
        thoughtsOnly: true,
        eligibleContacts: const [],
        onSubmitWithOutcome: submit,
        onAttachMedia: media,
        onPickMedia: pick,
        audioRecorderService: recorder,
      ),
    ),
  );

  ElevatedButton share(WidgetTester tester) =>
      tester.widget(find.byKey(const ValueKey('thought-composer-share')));

  testWidgets('empty and whitespace thoughts cannot share; no audience UI', (
    tester,
  ) async {
    var submissions = 0;
    await tester.pumpWidget(
      scene(
        submit: (_) async {
          submissions++;
          return ComposePostSubmitOutcome.keepSheetOpen;
        },
      ),
    );
    expect(share(tester).onPressed, isNull);
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(share(tester).onPressed, isNull);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.text('People Nearby'), findsNothing);
    expect(find.text('Pick People'), findsNothing);
    expect(find.text('Your friends see this for 24 hours'), findsOneWidget);
    expect(submissions, 0);
  });

  testWidgets(
    'shares trimmed text with all friends and keeps draft on failure',
    (tester) async {
      final drafts = <ComposePostResult>[];
      await tester.pumpWidget(
        scene(
          submit: (draft) async {
            drafts.add(draft);
            return ComposePostSubmitOutcome.keepSheetOpen;
          },
        ),
      );
      await tester.enterText(find.byType(TextField), '  A new thought  ');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('thought-composer-share')));
      await tester.pump();
      expect(drafts.single.text, 'A new thought');
      expect(drafts.single.audience.kind, PostAudienceKind.allFriends);
      expect(drafts.single.audience.selectedPeerIds, isEmpty);
      expect(find.text('  A new thought  '), findsOneWidget);
      expect(share(tester).onPressed, isNotNull);
    },
  );

  for (final draft in const [
    PostMediaDraft(localFilePath: '/tmp/thought.jpg', mime: 'image/jpeg'),
    PostMediaDraft(localFilePath: '/tmp/thought.mp4', mime: 'video/mp4'),
  ]) {
    testWidgets(
      '${draft.kind} can share without text through existing media drafts',
      (tester) async {
        ComposePostResult? submitted;
        await tester.pumpWidget(
          scene(
            media: () async => [draft],
            submit: (value) async {
              submitted = value;
              return ComposePostSubmitOutcome.keepSheetOpen;
            },
          ),
        );
        await tester.tap(find.text('Media'));
        await tester.pump();
        expect(share(tester).onPressed, isNotNull);
        await tester.tap(find.byKey(const ValueKey('thought-composer-share')));
        await tester.pump();
        expect(submitted!.text, isEmpty);
        expect(submitted!.audience.kind, PostAudienceKind.allFriends);
        expect(submitted!.mediaDrafts.single, same(draft));
        await tester.tap(find.byIcon(Icons.close));
        await tester.pump();
        expect(share(tester).onPressed, isNull);
      },
    );
  }

  testWidgets('picked photos show as thumbnails that remove one by one', (
    tester,
  ) async {
    await tester.pumpWidget(
      scene(
        media: () async => const [
          PostMediaDraft(localFilePath: '/tmp/one.jpg', mime: 'image/jpeg'),
          PostMediaDraft(localFilePath: '/tmp/two.jpg', mime: 'image/jpeg'),
        ],
        submit: (_) async => ComposePostSubmitOutcome.keepSheetOpen,
      ),
    );
    await tester.tap(find.text('Media'));
    await tester.pump();
    AttachmentPreviewStrip strip() =>
        tester.widget(find.byType(AttachmentPreviewStrip));
    expect(strip().attachments.map((file) => file.path), [
      '/tmp/one.jpg',
      '/tmp/two.jpg',
    ]);
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pump();
    expect(strip().attachments.map((file) => file.path), ['/tmp/two.jpg']);
  });

  testWidgets('nobody to share with explains inside the sheet, keeps text', (
    tester,
  ) async {
    await tester.pumpWidget(
      scene(submit: (_) async => ComposePostSubmitOutcome.nobodyToShareWith),
    );
    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.pump();
    expect(find.text('Add a friend to share your thoughts'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('thought-composer-share')));
    await tester.pump();
    expect(find.text('Add a friend to share your thoughts'), findsOneWidget);
    expect(find.text('Hello'), findsOneWidget);
  });

  testWidgets(
    'voice uses the shared recorder and preserves its waveform draft',
    (tester) async {
      final recorder = FakeAudioRecorderService()
        ..fakeOutputPath = '/tmp/thought.m4a'
        ..fakeDurationMs = 6400;
      addTearDown(recorder.dispose);
      ComposePostResult? submitted;
      await tester.pumpWidget(
        scene(
          recorder: recorder,
          submit: (draft) async {
            submitted = draft;
            return ComposePostSubmitOutcome.keepSheetOpen;
          },
        ),
      );
      await tester.tap(find.text('Voice'));
      await tester.pump();
      expect(share(tester).onPressed, isNull);
      recorder.emitAmplitude(0.5);
      await tester.tap(find.text('Stop'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('thought-composer-share')));
      await tester.pump();
      expect(submitted!.audience.kind, PostAudienceKind.allFriends);
      expect(submitted!.mediaDrafts.single.kind, 'voice');
      expect(submitted!.mediaDrafts.single.durationMs, 6400);
      expect(submitted!.mediaDrafts.single.waveform, hasLength(50));
      expect(recorder.isRecording, isFalse);
    },
  );

  testWidgets('pending submission blocks a second share', (tester) async {
    final pending = Completer<ComposePostSubmitOutcome>();
    var count = 0;
    await tester.pumpWidget(
      scene(
        submit: (_) {
          count++;
          return pending.future;
        },
      ),
    );
    await tester.enterText(find.byType(TextField), 'One share');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('thought-composer-share')));
    await tester.pump();
    expect(share(tester).onPressed, isNull);
    expect(count, 1);
    pending.complete(ComposePostSubmitOutcome.keepSheetOpen);
    await tester.pump();
    expect(share(tester).onPressed, isNotNull);
  });

  testWidgets(
    'Arabic composer explains its lifetime without audience choices',
    (tester) async {
      await tester.pumpWidget(
        scene(
          locale: const Locale('ar'),
          submit: (_) async => ComposePostSubmitOutcome.keepSheetOpen,
        ),
      );
      expect(find.text('يرى أصدقاؤك هذه الخاطرة لمدة 24 ساعة'), findsOneWidget);
      expect(find.text('مشاركة'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
    },
  );

  const leftOutLine =
      'A thought can have photos, or one video. Some items were left out.';
  const photoOne = PostMediaDraft(
    localFilePath: '/tmp/one.jpg',
    mime: 'image/jpeg',
  );
  const photoTwo = PostMediaDraft(
    localFilePath: '/tmp/two.jpg',
    mime: 'image/jpeg',
  );
  const clip = PostMediaDraft(
    localFilePath: '/tmp/clip.mp4',
    mime: 'video/mp4',
  );

  List<String> stripPaths(WidgetTester tester) => tester
      .widget<AttachmentPreviewStrip>(find.byType(AttachmentPreviewStrip))
      .attachments
      .map((file) => file.path)
      .toList();

  testWidgets('a mixed photo and video pick keeps photos and says so', (
    tester,
  ) async {
    await tester.pumpWidget(
      scene(
        pick: () async => (drafts: const [photoOne, clip], leftOut: false),
        submit: (_) async => ComposePostSubmitOutcome.keepSheetOpen,
      ),
    );
    expect(find.text(leftOutLine), findsNothing);
    await tester.tap(find.text('Media'));
    await tester.pump();
    expect(stripPaths(tester), ['/tmp/one.jpg']);
    expect(find.text(leftOutLine), findsOneWidget);
  });

  testWidgets('an unsupported file left out by the picker is explained', (
    tester,
  ) async {
    await tester.pumpWidget(
      scene(
        pick: () async => (drafts: const [photoOne], leftOut: true),
        submit: (_) async => ComposePostSubmitOutcome.keepSheetOpen,
      ),
    );
    await tester.tap(find.text('Media'));
    await tester.pump();
    expect(stripPaths(tester), ['/tmp/one.jpg']);
    expect(find.text(leftOutLine), findsOneWidget);
  });

  testWidgets('a second photo pick adds photos; a video then replaces them', (
    tester,
  ) async {
    final picks = <PostMediaPick>[
      (drafts: const [photoOne], leftOut: false),
      (drafts: const [photoTwo], leftOut: false),
      (drafts: const [clip], leftOut: false),
    ];
    await tester.pumpWidget(
      scene(
        pick: () async => picks.removeAt(0),
        submit: (_) async => ComposePostSubmitOutcome.keepSheetOpen,
      ),
    );
    await tester.tap(find.text('Media'));
    await tester.pump();
    await tester.tap(find.text('Media'));
    await tester.pump();
    expect(stripPaths(tester), ['/tmp/one.jpg', '/tmp/two.jpg']);
    expect(find.text(leftOutLine), findsNothing);
    await tester.tap(find.text('Media'));
    await tester.pump();
    expect(stripPaths(tester), ['/tmp/clip.mp4']);
  });

  testWidgets('a media picker failure is explained inside the sheet', (
    tester,
  ) async {
    await tester.pumpWidget(
      scene(
        pick: () async => throw StateError('picker crashed'),
        submit: (_) async => ComposePostSubmitOutcome.keepSheetOpen,
      ),
    );
    await tester.enterText(find.byType(TextField), 'Still here');
    await tester.pump();
    await tester.tap(find.text('Media'));
    await tester.pump();
    expect(find.text("Couldn't add your media. Try again."), findsOneWidget);
    expect(find.text('Send failed'), findsNothing);
    expect(find.text('Still here'), findsOneWidget);
    expect(find.text('Media'), findsOneWidget);
  });

  testWidgets('a failed share is explained inside the sheet, keeps text', (
    tester,
  ) async {
    await tester.pumpWidget(
      scene(submit: (_) async => ComposePostSubmitOutcome.shareFailed),
    );
    await tester.enterText(find.byType(TextField), 'Try me');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('thought-composer-share')));
    await tester.pump();
    expect(
      find.text('Not shared yet. Your thought is still here.'),
      findsOneWidget,
    );
    expect(find.text('Try me'), findsOneWidget);
    expect(share(tester).onPressed, isNotNull);
  });

  testWidgets('a voice note that reaches the time limit stays attached', (
    tester,
  ) async {
    final recorder = FakeAudioRecorderService()
      ..fakeOutputPath = '/tmp/long.m4a'
      ..fakeDurationMs = 300000;
    addTearDown(recorder.dispose);
    ComposePostResult? submitted;
    await tester.pumpWidget(
      scene(
        recorder: recorder,
        submit: (draft) async {
          submitted = draft;
          return ComposePostSubmitOutcome.keepSheetOpen;
        },
      ),
    );
    await tester.tap(find.text('Voice'));
    await tester.pump();
    recorder.emitAmplitude(0.4);
    await recorder.triggerAutoStop();
    await tester.pump();
    expect(find.text('Voice attached'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('thought-composer-share')));
    await tester.pump();
    expect(submitted!.mediaDrafts.single.localFilePath, '/tmp/long.m4a');
    expect(submitted!.mediaDrafts.single.durationMs, 300000);
    expect(submitted!.mediaDrafts.single.waveform, hasLength(50));
    expect(recorder.onAutoStopped, isNull);
  });

  testWidgets('a denied microphone says how to turn it on', (tester) async {
    final recorder = FakeAudioRecorderService()..permissionGranted = false;
    addTearDown(recorder.dispose);
    await tester.pumpWidget(
      scene(
        recorder: recorder,
        submit: (_) async => ComposePostSubmitOutcome.keepSheetOpen,
      ),
    );
    await tester.tap(find.text('Voice'));
    await tester.pump();
    expect(
      find.text(
        "To record voice messages, turn it on in your phone's settings.",
      ),
      findsOneWidget,
    );
    expect(recorder.startCallCount, 0);
  });

  testWidgets('a busy microphone says to try again', (tester) async {
    final recorder = FakeAudioRecorderService();
    addTearDown(recorder.dispose);
    final callLease = microphoneCaptureLeasesFor(recorder).acquire();
    await tester.pumpWidget(
      scene(
        recorder: recorder,
        submit: (_) async => ComposePostSubmitOutcome.keepSheetOpen,
      ),
    );
    const busyLine = 'The microphone is busy right now. Try again in a moment.';
    await tester.tap(find.text('Voice'));
    await tester.pump();
    expect(find.text(busyLine), findsOneWidget);
    callLease.release();

    recorder.shouldFailStart = true;
    await tester.pumpWidget(
      scene(
        key: const ValueKey('second-sheet'),
        recorder: recorder,
        submit: (_) async => ComposePostSubmitOutcome.keepSheetOpen,
      ),
    );
    expect(find.text(busyLine), findsNothing);
    await tester.tap(find.text('Voice'));
    await tester.pump();
    expect(find.text(busyLine), findsOneWidget);
  });
}
