import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/call/application/call_video_presentation.dart';
import 'package:flutter_app/features/call/domain/call_media.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/presentation/screens/incoming_call_screen.dart';
import 'package:flutter_app/features/call/presentation/screens/outgoing_call_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _video = CallVideoPresentation.project(
  videoEnabled: true,
  wireVersion: CallWireVersion.v2,
  requestedMedia: CallMediaKind.video,
);

Future<void> _withScreen(
  WidgetTester tester,
  Widget screen,
  Future<void> Function() body, {
  String language = 'en',
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 640);
  final semantics = tester.ensureSemantics();
  try {
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
          brightness: Brightness.light,
          extensions: const [BackgroundReadableColors.representativeLight],
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
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

void _dark(WidgetTester tester, Type screenType) {
  final name = find.text('Layla');
  expect(
    tester.widget<Text>(name).style!.color,
    BackgroundReadableColors.dark.textPrimary,
  );
  expect(Theme.of(tester.element(name)).brightness, Brightness.dark);
  final box = find
      .descendant(
        of: find.byType(screenType),
        matching: find.byType(ColoredBox),
      )
      .first;
  expect(
    tester.widget<ColoredBox>(box).color,
    BackgroundReadableColors.dark.surfaceBase,
  );
}

Future<void> _tap(WidgetTester tester, String id) async {
  final target = find.bySemanticsIdentifier(id);
  await tester.ensureVisible(target);
  await tester.pump();
  final rect = tester.getRect(target);
  expect(rect.width, greaterThanOrEqualTo(48));
  expect(rect.height, greaterThanOrEqualTo(48));
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(320));
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.bottom, lessThanOrEqualTo(640));
  await tester.tap(target);
}

void main() {
  for (final language in ['en', 'ar']) {
    testWidgets('VUI2 incoming $language dark colors and 2x targets', (
      tester,
    ) async {
      final calls = <String>[];
      await _withScreen(
        tester,
        IncomingCallScreen(
          contactPeerId: 'friend',
          contactUsername: 'Layla',
          state: CallState.ringing,
          onAnswer: () => calls.add('ordinary'),
          onDecline: () => calls.add('decline'),
          onAcceptVideo: () => calls.add('video'),
          onUseAudioOnly: () => calls.add('audio'),
          videoPresentation: _video,
          onVideoIntent: (_) => calls.add('unexpected'),
        ),
        () async {
          _dark(tester, IncomingCallScreen);
          expect(calls, isEmpty);
          await _tap(tester, 'call_decline');
          await _tap(tester, 'call_accept_audio');
          await _tap(tester, 'call_accept_video');
          expect(calls, ['decline', 'audio', 'video']);
        },
        language: language,
      );
    });
    testWidgets('VUI2 outgoing $language dark colors and 2x targets', (
      tester,
    ) async {
      final calls = <String>[];
      await _withScreen(
        tester,
        OutgoingCallScreen(
          contactPeerId: 'friend',
          contactUsername: 'Layla',
          state: CallState.ringing,
          onCancel: () => calls.add('cancel'),
          videoPresentation: _video,
          onVideoIntent: (intent) => calls.add(intent.action.name),
        ),
        () async {
          _dark(tester, OutgoingCallScreen);
          expect(calls, isEmpty);
          await _tap(tester, 'call_video_audio_only');
          await _tap(tester, 'call_cancel');
          expect(calls, ['useAudioOnly', 'cancel']);
        },
        language: language,
      );
    });
  }
  for (final validating in [true, false]) {
    testWidgets(
      'VUI2 incoming retains ${validating ? 'validation' : 'inflight'} guard',
      (tester) async {
        final calls = <String>[];
        await _withScreen(
          tester,
          IncomingCallScreen(
            contactPeerId: 'friend',
            contactUsername: 'Layla',
            state: validating
                ? CallState.incomingValidating
                : CallState.ringing,
            mediaChoiceInFlight: !validating,
            onAnswer: () => calls.add('ordinary'),
            onDecline: () => calls.add('decline'),
            onAcceptVideo: () => calls.add('video'),
            onUseAudioOnly: () => calls.add('audio'),
            videoPresentation: _video,
            onVideoIntent: (_) => calls.add('unexpected'),
          ),
          () async {
            for (final id in ['call_accept_audio', 'call_accept_video']) {
              final target = find.bySemanticsIdentifier(id);
              expect(
                tester.getSemantics(target).hasFlag(SemanticsFlag.isEnabled),
                isFalse,
              );
              await _tap(tester, id);
            }
            expect(calls, isEmpty);
          },
        );
      },
    );
  }
}
