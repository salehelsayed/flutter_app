import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/call/application/call_video_presentation.dart';
import 'package:flutter_app/features/call/domain/call_media.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/presentation/screens/incoming_call_screen.dart';
import 'package:flutter_app/features/call/presentation/screens/outgoing_call_screen.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/identity/presentation/widgets/cosmic_background.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _video = CallVideoPresentation.project(
  videoEnabled: true,
  wireVersion: CallWireVersion.v2,
  requestedMedia: CallMediaKind.video,
);

Future<void> _screen(
  WidgetTester tester,
  Widget screen,
  String language,
  Future<void> Function() body,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  final semantics = tester.ensureSemantics();
  try {
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // A light app must still render the agreed dark video entry stage.
        theme: ThemeData(
          extensions: const [BackgroundReadableColors.representativeLight],
        ),
        home: Scaffold(body: screen),
      ),
    );
    await tester.pump();
    await body();
    expect(tester.takeException(), isNull);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    semantics.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

void _entryStage(WidgetTester tester) {
  expect(find.byType(CosmicBackground), findsOneWidget);
  expect(
    tester.widget<CosmicBackground>(find.byType(CosmicBackground)).paused,
    isTrue,
  );
  expect(find.byType(UserAvatar), findsOneWidget);
  expect(find.byType(Texture), findsNothing);
  final avatar = tester.getRect(find.byType(UserAvatar));
  expect(avatar.top, greaterThanOrEqualTo(90));
  expect(avatar.bottom, lessThan(300));
  expect(find.text('Layla'), findsOneWidget);
}

void main() {
  for (final language in ['en', 'de', 'ar']) {
    testWidgets(
      'VUI2 incoming $language keeps dark avatar and ordered answers',
      (tester) async {
        final actions = <String>[];
        final video = <CallVideoIntent>[];
        await _screen(
          tester,
          IncomingCallScreen(
            contactPeerId: 'friend',
            contactUsername: 'Layla',
            state: CallState.ringing,
            onAnswer: () => actions.add('ordinary-answer'),
            onAcceptVideo: () => actions.add('video-answer'),
            onUseAudioOnly: () => actions.add('audio-answer'),
            onDecline: () => actions.add('decline'),
            videoPresentation: _video,
            onVideoIntent: video.add,
          ),
          language,
          () async {
            _entryStage(tester);
            expect(actions, isEmpty);
            expect(video, isEmpty);
            final decline = find.bySemanticsIdentifier('call_decline');
            final audio = find.bySemanticsIdentifier('call_accept_audio');
            final answer = find.bySemanticsIdentifier('call_accept_video');
            final a = tester.getRect(decline);
            final b = tester.getRect(audio);
            final c = tester.getRect(answer);
            expect(a.top, greaterThan(600));
            expect(a.center.dy, closeTo(b.center.dy, 2));
            expect(b.center.dy, closeTo(c.center.dy, 2));
            expect(
              language == 'ar'
                  ? a.center.dx > b.center.dx
                  : a.center.dx < b.center.dx,
              isTrue,
            );
            expect(
              language == 'ar'
                  ? b.center.dx > c.center.dx
                  : b.center.dx < c.center.dx,
              isTrue,
            );
            await tester.tap(audio);
            await tester.tap(answer);
            await tester.tap(decline);
            expect(actions, ['audio-answer', 'video-answer', 'decline']);
            expect(video, isEmpty);
          },
        );
      },
    );
    testWidgets(
      'VUI2 outgoing $language keeps only existing preanswer actions',
      (tester) async {
        var cancelled = 0;
        final video = <CallVideoIntent>[];
        await _screen(
          tester,
          OutgoingCallScreen(
            contactPeerId: 'friend',
            contactUsername: 'Layla',
            state: CallState.ringing,
            onCancel: () => cancelled++,
            videoPresentation: _video,
            onVideoIntent: video.add,
          ),
          language,
          () async {
            _entryStage(tester);
            expect(cancelled, 0);
            expect(video, isEmpty);
            final cancel = find.bySemanticsIdentifier('call_cancel');
            final audio = find.bySemanticsIdentifier('call_video_audio_only');
            expect(tester.getRect(cancel).top, greaterThan(600));
            expect(tester.getRect(audio).top, greaterThan(600));
            for (final id in [
              'call_video_switch_camera',
              'call_video_camera_on',
              'call_mute',
              'call_speaker',
            ]) {
              expect(find.bySemanticsIdentifier(id), findsNothing);
            }
            await tester.tap(audio);
            await tester.tap(cancel);
            expect(video.map((e) => e.action), [CallVideoAction.useAudioOnly]);
            expect(cancelled, 1);
          },
        );
      },
    );
  }
}
