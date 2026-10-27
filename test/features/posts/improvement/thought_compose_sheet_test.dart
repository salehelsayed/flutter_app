import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/attachment_preview_strip.dart';
import 'package:flutter_app/features/posts/application/post_media_draft.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/features/posts/presentation/pick_post_media_drafts.dart';
import 'package:flutter_app/features/posts/presentation/widgets/compose_post_sheet.dart';
import 'package:flutter_app/features/posts/presentation/widgets/thought_photo_draft_preview.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../shared/fakes/fake_audio_recorder_service.dart';
import '../../../shared/bidi_layout_checks.dart';

void main() {
  Widget scene({
    required Future<ComposePostSubmitOutcome> Function(ComposePostResult)
    submit,
    Future<List<PostMediaDraft>> Function()? media,
    Future<PostMediaPick> Function()? pick,
    FakeAudioRecorderService? recorder,
    Locale locale = const Locale('en'),
    Key? key,
    ComposePostResult? initialDraft,
    ValueChanged<ComposePostResult?>? onClosed,
    bool replacesCurrentThought = false,
  }) => MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: ComposePostSheet(
        key: key,
        thoughtsOnly: true,
        replacesCurrentThought: replacesCurrentThought,
        eligibleContacts: const [],
        onSubmitWithOutcome: submit,
        onAttachMedia: media,
        onPickMedia: pick,
        audioRecorderService: recorder,
        initialDraft: initialDraft,
        onClosed: onClosed,
      ),
    ),
  );

  /// The sheet scrolls; a control below the fold is scrolled to, then tapped.
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
  }

  /// Photos show inside the sheet; nothing opens over it.
  Future<void> finishPick(WidgetTester tester) async {
    await tester.pumpAndSettle();
    expect(find.byType(ComposePostSheet), findsOneWidget);
  }

  /// What the sheet shows for the picked media: photos inline, otherwise the
  /// attachment strip.
  List<String> shownPaths(WidgetTester tester) {
    final photos = find.byType(ThoughtPhotoDraftPreview);
    if (photos.evaluate().isNotEmpty) {
      return tester.widget<ThoughtPhotoDraftPreview>(photos).paths;
    }
    return tester
        .widget<AttachmentPreviewStrip>(find.byType(AttachmentPreviewStrip))
        .attachments
        .map((file) => file.path)
        .toList();
  }

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
    expect(find.text('All your friends see this for 24 hours'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('thought-composer-replaces')),
      findsNothing,
    );
    expect(submissions, 0);
  });

  testWidgets('with a thought already up the sheet says sharing replaces it', (
    tester,
  ) async {
    await tester.pumpWidget(
      scene(
        submit: (_) async => ComposePostSubmitOutcome.keepSheetOpen,
        replacesCurrentThought: true,
      ),
    );
    expect(find.text('All your friends see this for 24 hours'), findsOneWidget);
    expect(
      find.text('Sharing replaces the thought you have up now'),
      findsOneWidget,
    );
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
      await tapVisible(
        tester,
        find.byKey(const ValueKey('thought-composer-share')),
      );
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
        await tester.tap(find.byTooltip('Media'));
        await finishPick(tester);
        expect(share(tester).onPressed, isNotNull);
        await tapVisible(
          tester,
          find.byKey(const ValueKey('thought-composer-share')),
        );
        await tester.pump();
        expect(submitted!.text, isEmpty);
        expect(submitted!.audience.kind, PostAudienceKind.allFriends);
        expect(submitted!.mediaDrafts.single, same(draft));
        await tapVisible(tester, find.byIcon(Icons.close));
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
    await tester.tap(find.byTooltip('Media'));
    await finishPick(tester);
    expect(shownPaths(tester), ['/tmp/one.jpg', '/tmp/two.jpg']);
    await tapVisible(
      tester,
      find.byKey(const ValueKey('thought-photo-draft-remove')).first,
    );
    await tester.pump();
    expect(shownPaths(tester), ['/tmp/two.jpg']);
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
    await tapVisible(
      tester,
      find.byKey(const ValueKey('thought-composer-share')),
    );
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
      await tester.tap(find.byTooltip('Voice'));
      await tester.pump();
      expect(share(tester).onPressed, isNull);
      recorder.emitAmplitude(0.5);
      await tester.tap(find.text('Stop'));
      await tester.pump();
      await tapVisible(
        tester,
        find.byKey(const ValueKey('thought-composer-share')),
      );
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
    await tapVisible(
      tester,
      find.byKey(const ValueKey('thought-composer-share')),
    );
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
      expect(
        find.text('يرى جميع أصدقائك هذه الخاطرة لمدة 24 ساعة'),
        findsOneWidget,
      );
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

  testWidgets(
    'a picked photo shows whole inside the composer and the X takes it out',
    (tester) async {
      await tester.pumpWidget(
        scene(
          pick: () async => (drafts: const [photoOne], leftOut: false),
          submit: (_) async => ComposePostSubmitOutcome.keepSheetOpen,
        ),
      );
      await tester.enterText(find.byType(TextField), 'Lake at dusk');
      await tester.tap(find.byTooltip('Media'));
      await finishPick(tester);

      expect(shownPaths(tester), ['/tmp/one.jpg']);
      expect(find.text('Fit'), findsNothing);
      final photo = find.descendant(
        of: find.byKey(const ValueKey('thought-photo-draft-0')),
        matching: find.byType(Image),
      );
      expect(tester.widgetList<Image>(photo).map((image) => image.fit), [
        BoxFit.contain,
      ]);
      expect(find.byType(ImageFiltered), findsNothing);

      await tapVisible(
        tester,
        find.byKey(const ValueKey('thought-photo-draft-remove')),
      );
      await tester.pump();
      expect(find.byType(ThoughtPhotoDraftPreview), findsNothing);
      expect(find.text('Lake at dusk'), findsOneWidget);
      expect(share(tester).onPressed, isNotNull);
    },
  );

  testWidgets('on a small phone with the keyboard up, Share and the toolbar '
      'stay in view', (tester) async {
    tester.view.physicalSize = const Size(320, 568) * 3;
    tester.view.devicePixelRatio = 3;
    tester.view.viewInsets = const FakeViewPadding(bottom: 260 * 3);
    addTearDown(tester.view.reset);
    const keyboardTop = 568.0 - 260;
    var shared = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Material(
          color: Colors.black,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ComposePostSheet(
              thoughtsOnly: true,
              eligibleContacts: const [],
              onSubmitWithOutcome: (_) async {
                shared++;
                return ComposePostSubmitOutcome.keepSheetOpen;
              },
              onPickMedia: () async =>
                  (drafts: const [photoOne], leftOut: false),
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Lake at dusk');
    await tester.tap(find.byTooltip('Media'));
    await finishPick(tester);
    expect(shownPaths(tester), ['/tmp/one.jpg']);

    final shareButton = find.byKey(const ValueKey('thought-composer-share'));
    final shareRect = tester.getRect(shareButton);
    expect(shareRect.top, greaterThanOrEqualTo(0));
    expect(shareRect.bottom, lessThanOrEqualTo(keyboardTop));
    expect(
      tester
          .getRect(find.byKey(const ValueKey('thought-composer-toolbar')))
          .bottom,
      moreOrLessEquals(keyboardTop, epsilon: 1),
    );
    expect(
      tester.getRect(find.byTooltip('Voice')).bottom,
      lessThanOrEqualTo(keyboardTop),
    );

    await tester.tap(shareButton);
    await tester.pump();
    expect(shared, 1);
  });

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
    await tester.tap(find.byTooltip('Media'));
    await finishPick(tester);
    expect(shownPaths(tester), ['/tmp/one.jpg']);
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
    await tester.tap(find.byTooltip('Media'));
    await finishPick(tester);
    expect(shownPaths(tester), ['/tmp/one.jpg']);
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
    await tester.tap(find.byTooltip('Media'));
    await finishPick(tester);
    await tester.tap(find.byTooltip('Media'));
    await finishPick(tester);
    expect(shownPaths(tester), ['/tmp/one.jpg', '/tmp/two.jpg']);
    expect(find.text(leftOutLine), findsNothing);
    await tester.tap(find.byTooltip('Media'));
    await finishPick(tester);
    expect(shownPaths(tester), ['/tmp/clip.mp4']);
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
    await tester.tap(find.byTooltip('Media'));
    await finishPick(tester);
    expect(find.text("Couldn't add your media. Try again."), findsOneWidget);
    expect(find.text('Send failed'), findsNothing);
    expect(find.text('Still here'), findsOneWidget);
    expect(find.byTooltip('Media'), findsOneWidget);
  });

  testWidgets('a failed share is explained inside the sheet, keeps text', (
    tester,
  ) async {
    await tester.pumpWidget(
      scene(submit: (_) async => ComposePostSubmitOutcome.shareFailed),
    );
    await tester.enterText(find.byType(TextField), 'Try me');
    await tester.pump();
    await tapVisible(
      tester,
      find.byKey(const ValueKey('thought-composer-share')),
    );
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
    await tester.tap(find.byTooltip('Voice'));
    await tester.pump();
    recorder.emitAmplitude(0.4);
    await recorder.triggerAutoStop();
    await tester.pump();
    expect(find.text('Voice attached'), findsOneWidget);
    await tapVisible(
      tester,
      find.byKey(const ValueKey('thought-composer-share')),
    );
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
    await tester.tap(find.byTooltip('Voice'));
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
    await tester.tap(find.byTooltip('Voice'));
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
    await tester.tap(find.byTooltip('Voice'));
    await tester.pump();
    expect(find.text(busyLine), findsOneWidget);
  });

  testWidgets(
    'closing without sharing hands back text and picked photos; reopening restores them',
    (tester) async {
      const photo = PostMediaDraft(
        localFilePath: '/tmp/kept.jpg',
        mime: 'image/jpeg',
      );
      final closed = <ComposePostResult?>[];
      Future<ComposePostSubmitOutcome> keep(ComposePostResult _) async =>
          ComposePostSubmitOutcome.keepSheetOpen;
      await tester.pumpWidget(
        scene(submit: keep, media: () async => [photo], onClosed: closed.add),
      );
      await tester.enterText(find.byType(TextField), 'Half a thought');
      await tester.tap(find.byTooltip('Media'));
      await finishPick(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(closed, hasLength(1));
      expect(closed.single!.text, 'Half a thought');
      expect(closed.single!.mediaDrafts.single, same(photo));
      await tester.pumpWidget(scene(submit: keep, initialDraft: closed.single));
      expect(find.text('Half a thought'), findsOneWidget);
      expect(find.byType(ThoughtPhotoDraftPreview), findsOneWidget);
      expect(share(tester).onPressed, isNotNull);
    },
  );

  testWidgets('a stopped voice note survives a close and comes back', (
    tester,
  ) async {
    const voice = PostMediaDraft(
      localFilePath: '/tmp/kept.m4a',
      mime: 'audio/mp4',
      durationMs: 3000,
    );
    final closed = <ComposePostResult?>[];
    Future<ComposePostSubmitOutcome> keep(ComposePostResult _) async =>
        ComposePostSubmitOutcome.keepSheetOpen;
    await tester.pumpWidget(
      scene(
        submit: keep,
        initialDraft: ComposePostResult(
          text: '',
          audience: PostAudience.allFriends(),
          mediaDrafts: const [voice],
        ),
        onClosed: closed.add,
      ),
    );
    expect(find.text('Voice attached'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(closed.single!.mediaDrafts.single, same(voice));
  });

  testWidgets('an emptied draft is not kept', (tester) async {
    final closed = <ComposePostResult?>[];
    await tester.pumpWidget(
      scene(
        submit: (_) async => ComposePostSubmitOutcome.keepSheetOpen,
        onClosed: closed.add,
      ),
    );
    await tester.enterText(find.byType(TextField), 'Gone');
    await tester.enterText(find.byType(TextField), '  ');
    await tester.pumpWidget(const SizedBox.shrink());
    expect(closed, [null]);
  });

  for (final c in bidiCases) {
    testWidgets('the composer lays out mixed text: ${c.label}', (tester) async {
      await tester.pumpWidget(
        scene(submit: (_) async => ComposePostSubmitOutcome.keepSheetOpen),
      );
      await tester.enterText(find.byType(TextField), c.text);
      await tester.pump();
      final editable = tester
          .state<EditableTextState>(find.byType(EditableText))
          .renderEditable;
      expectBidiLayout(
        c,
        direction: editable.textDirection,
        boxes: editable.getBoxesForSelection,
        area: Offset.zero & editable.size,
        // The field keeps room for the cursor at the line end.
        tolerance: 4,
      );
    });
  }

  testWidgets('emoji count as one character each on the toolbar', (
    tester,
  ) async {
    await tester.pumpWidget(
      scene(submit: (_) async => ComposePostSubmitOutcome.keepSheetOpen),
    );
    await tester.enterText(find.byType(TextField), '😀' * 449);
    await tester.pump();
    expect(find.text('449/500'), findsNothing);
    expect(find.text('898/500'), findsNothing);
    await tester.enterText(find.byType(TextField), '😀' * 460);
    await tester.pump();
    expect(find.text('460/500'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '😀' * 500);
    await tester.pump();
    expect(find.text('500/500'), findsOneWidget);
    expect(share(tester).onPressed, isNotNull);
  });

  testWidgets(
    'a thought stops at 500 characters, counts only near the end, and Share refuses more',
    (tester) async {
      await tester.pumpWidget(
        scene(submit: (_) async => ComposePostSubmitOutcome.keepSheetOpen),
      );
      await tester.enterText(find.byType(TextField), 'a' * 449);
      await tester.pump();
      expect(find.text('449/500'), findsNothing);
      await tester.enterText(find.byType(TextField), 'a' * 460);
      await tester.pump();
      expect(find.text('460/500'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'a' * 790);
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'a' * 500,
      );
      await tester.pumpWidget(
        scene(
          submit: (_) async => ComposePostSubmitOutcome.keepSheetOpen,
          initialDraft: ComposePostResult(
            text: 'b' * 520,
            audience: PostAudience.allFriends(),
          ),
          key: const ValueKey('over-limit'),
        ),
      );
      expect(share(tester).onPressed, isNull);
    },
  );
}
