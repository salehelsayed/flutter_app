import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/presentation/widgets/compose_post_sheet.dart';

import '../../../shared/fakes/fake_audio_recorder_service.dart';

void main() {
  testWidgets('pick-people flow excludes blocked and archived contacts', (
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
            eligibleContacts: <ContactModel>[
              _contact('peer-a', 'Alice'),
              _contact('peer-b', 'Blocked', isBlocked: true),
              _contact('peer-c', 'Archived', isArchived: true),
            ],
            onSubmit: (result) async {
              submitted = result;
            },
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'hello posts');
    await tester.tap(find.text('Pick People'));
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Blocked'), findsNothing);
    expect(find.text('Archived'), findsNothing);

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Post'));
    await tester.pumpAndSettle();

    expect(submitted, isNotNull);
    expect(submitted!.text, 'hello posts');
    expect(submitted!.audience.kind, PostAudienceKind.pickPeople);
    expect(submitted!.audience.selectedPeerIds, <String>['peer-a']);
  });

  testWidgets('keeps the sheet open while onSubmit is still pending', (
    tester,
  ) async {
    final submitCompleter = Completer<void>();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () {
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => ComposePostSheet(
                    eligibleContacts: const <ContactModel>[],
                    onSubmit: (_) => submitCompleter.future,
                  ),
                );
              },
              child: const Text('Compose'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Compose'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'hello posts');
    await tester.pump();
    await tester.tap(find.text('Post'));
    await tester.pump();

    expect(find.byType(ComposePostSheet), findsOneWidget);

    submitCompleter.complete();
    await tester.pump();
  });

  testWidgets(
    'tap voice starts recording immediately and stop produces a voice draft',
    (tester) async {
      ComposePostResult? submitted;
      final recorder = FakeAudioRecorderService()
        ..fakeDurationMs = 6400
        ..fakeOutputPath = '/tmp/post_voice.m4a';
      addTearDown(() async {
        await recorder.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ComposePostSheet(
              eligibleContacts: const <ContactModel>[],
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
      expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);

      recorder.emitDuration(const Duration(seconds: 4));
      recorder.emitAmplitude(0.2);
      recorder.emitAmplitude(0.6);
      recorder.emitAmplitude(1.0);
      await tester.pump();

      expect(find.text('0:04'), findsOneWidget);

      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();

      expect(find.text('Voice attached'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'post draft');
      await tester.pump();
      await tester.tap(find.text('Post'));
      await tester.pumpAndSettle();

      expect(submitted, isNotNull);
      expect(submitted!.text, 'post draft');
      expect(submitted!.mediaDrafts, hasLength(1));
      expect(submitted!.mediaDrafts.single.mime, 'audio/mp4');
    },
  );

  test(
    'fake recorder cancels a delayed voice start when stop is requested',
    () async {
      final recorder = FakeAudioRecorderService()
        ..fakeDurationMs = 6400
        ..startGate = Completer<void>();

      addTearDown(() async {
        await recorder.dispose();
      });

      final startFuture = recorder.start(outputPath: '/tmp/delayed_voice.m4a');
      expect(recorder.startCallCount, 1);
      expect(recorder.isRecording, false);

      final stopFuture = recorder.stop();
      expect(recorder.stopCallCount, 1);
      expect(recorder.isRecording, false);

      recorder.startGate!.complete();
      await startFuture;

      expect(await stopFuture, isNull);
      expect(recorder.isRecording, false);
    },
  );

  testWidgets('closes the sheet once submit outcome says to close', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () {
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => ComposePostSheet(
                    eligibleContacts: const <ContactModel>[],
                    onSubmitWithOutcome: (_) async =>
                        ComposePostSubmitOutcome.closeSheet,
                  ),
                );
              },
              child: const Text('Compose'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Compose'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'hello posts');
    await tester.pump();
    await tester.tap(find.text('Post'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(ComposePostSheet), findsNothing);
  });

  testWidgets('keeps the sheet open when submit outcome says to retry', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () {
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => ComposePostSheet(
                    eligibleContacts: const <ContactModel>[],
                    onSubmitWithOutcome: (_) async =>
                        ComposePostSubmitOutcome.keepSheetOpen,
                  ),
                );
              },
              child: const Text('Compose'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Compose'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'hello posts');
    await tester.pump();
    await tester.tap(find.text('Post'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(ComposePostSheet), findsOneWidget);
    final postButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Post'),
    );
    expect(postButton.onPressed, isNotNull);
  });
}

ContactModel _contact(
  String peerId,
  String username, {
  bool isArchived = false,
  bool isBlocked = false,
}) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/relay/tcp/443/p2p/relay',
    username: username,
    signature: 'sig-$peerId',
    scannedAt: '2026-03-15T10:00:00.000Z',
    isArchived: isArchived,
    archivedAt: isArchived ? '2026-03-15T10:00:00.000Z' : null,
    isBlocked: isBlocked,
    blockedAt: isBlocked ? '2026-03-15T10:00:00.000Z' : null,
  );
}
