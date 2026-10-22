import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/posts/application/post_media_draft.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/presentation/widgets/compose_post_sheet.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../shared/fakes/fake_audio_recorder_service.dart';

void main() {
  Widget scene({
    required Future<ComposePostSubmitOutcome> Function(ComposePostResult)
    submit,
    Future<List<PostMediaDraft>> Function()? media,
    FakeAudioRecorderService? recorder,
    Locale locale = const Locale('en'),
  }) => MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: ComposePostSheet(
        thoughtsOnly: true,
        eligibleContacts: const [],
        onSubmitWithOutcome: submit,
        onAttachMedia: media,
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
        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pump();
        expect(share(tester).onPressed, isNull);
      },
    );
  }

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
}
