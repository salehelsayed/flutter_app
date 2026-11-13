import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/call/application/call_audio_controller.dart';
import 'package:flutter_app/features/call/application/foreground_call_capability.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_media.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/application/call_video_presentation.dart';
import 'package:flutter_app/features/call/presentation/widgets/call_video_view_surface.dart';
import 'package:flutter_app/features/call/presentation/widgets/call_video_screen_layout.dart';
import 'package:flutter_app/features/call/presentation/widgets/call_video_controls.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

final _id = CallId.parse('11111111-1111-4111-8111-111111111111');
final _now = DateTime.utc(2026, 11, 13);
const _local = CallVideoView(textureId: 11, width: 640, height: 480);
const _remote = CallVideoView(textureId: 22, width: 1280, height: 720);

ForegroundCallProjection _projection({
  bool enabled = true,
  bool accepted = true,
  CallWireVersion wire = CallWireVersion.v2,
  CallMediaKind agreed = CallMediaKind.video,
  CallState state = CallState.connected,
  CallCameraState camera = CallCameraState.on,
  bool reconnecting = false,
  int generation = 7,
  CallVideoView? local = _local,
  CallVideoView? remote = _remote,
}) => ForegroundCallProjection(
  session: state == CallState.idle
      ? CallSessionSnapshot.idle(now: _now)
      : CallSessionSnapshot.active(
          callId: _id,
          contactPeerId: 'friend',
          direction: CallDirection.outgoing,
          state: state,
          callerAccountPeerId: 'caller',
          callerDeviceId: 'device',
          startedAt: _now,
          endedAt: state == CallState.ended ? _now : null,
          endReason: state == CallState.ended
              ? CallEndReason.localHangup
              : null,
        ),
  audio: CallAudioControlState(
    muted: false,
    selectedRoute: CallAudioOutputRoute.systemDefault,
    supportedRoutes: [CallAudioOutputRoute.systemDefault],
    active: true,
    failure: CallAudioFailure.none,
  ),
  video: ForegroundCallVideoProjection(
    generation: generation,
    localView: local,
    remoteView: remote,
    presentation: CallVideoPresentation.project(
      videoEnabled: enabled,
      wireVersion: wire,
      requestedMedia: CallMediaKind.video,
      acceptedMedia: accepted ? agreed : null,
      agreedMedia: agreed,
      localCamera: camera,
      remoteCamera: camera,
      isConnected: !reconnecting,
      isReconnecting: reconnecting,
    ),
  ),
);

Widget _app(
  ForegroundCallProjection projection,
  CallVideoRendererSlot slot, {
  Locale locale = const Locale('en'),
  double scale = 1,
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: ThemeData(extensions: const [BackgroundReadableColors.dark]),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(
    body: SizedBox(
      width: 320,
      child: CallVideoViewSurface(projection: projection, slot: slot),
    ),
  ),
);

Widget _layoutApp({Widget? videoViews, required VoidCallback onAudio}) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(extensions: const [BackgroundReadableColors.dark]),
      home: Scaffold(
        body: CallVideoScreenLayout(
          profile: const SizedBox(
            key: ValueKey('combined-profile'),
            height: 40,
            child: Text('Profile'),
          ),
          audioControls: SizedBox(
            key: const ValueKey('combined-audio'),
            height: 48,
            child: TextButton(onPressed: onAudio, child: const Text('Audio')),
          ),
          presentation: _projection().video!.presentation,
          onIntent: (_) =>
              throw StateError('Hidden video controls must not dispatch'),
          showVideoControls: false,
          videoViews: videoViews,
        ),
      ),
    );

void main() {
  for (final slot in CallVideoRendererSlot.values) {
    testWidgets('U6-view API $slot shows only its current owner texture', (
      tester,
    ) async {
      await tester.pumpWidget(_app(_projection(), slot));
      expect(find.byType(Texture), findsOneWidget);
      expect(
        tester.widget<Texture>(find.byType(Texture)).textureId,
        slot == CallVideoRendererSlot.local ? 11 : 22,
      );
      expect(
        find.bySemanticsIdentifier('call_video_view_${slot.name}'),
        findsOneWidget,
      );
    });

    for (final camera in [CallCameraState.off, CallCameraState.paused]) {
      testWidgets(
        'U6-view API $slot $camera removes live pixels but keeps status',
        (tester) async {
          await tester.pumpWidget(_app(_projection(camera: camera), slot));
          expect(find.byType(Texture), findsNothing);
          expect(
            find.bySemanticsIdentifier('call_video_view_${slot.name}'),
            findsOneWidget,
          );
        },
      );
    }

    for (final invalid in <CallVideoView?>[
      null,
      const CallVideoView(textureId: -1, width: 640, height: 480),
      const CallVideoView(textureId: 90, width: 0, height: 480),
      const CallVideoView(textureId: 90, width: 640, height: -1),
    ]) {
      testWidgets(
        'U6-view API $slot unavailable metadata ${invalid?.textureId}/${invalid?.width}/${invalid?.height} has safe placeholder',
        (tester) async {
          await tester.pumpWidget(
            _app(_projection(local: invalid, remote: invalid), slot),
          );
          expect(find.byType(Texture), findsNothing);
          expect(
            find.bySemanticsIdentifier('call_video_view_${slot.name}'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final control in [
    'gate',
    'legacy',
    'audio',
    'initial',
    'idle',
    'ending',
    'terminal',
  ]) {
    testWidgets('U6-view API $control never exposes an owner texture', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          _projection(
            enabled: control != 'gate',
            accepted: control != 'initial',
            wire: control == 'legacy' ? CallWireVersion.v1 : CallWireVersion.v2,
            agreed: control == 'audio'
                ? CallMediaKind.audio
                : CallMediaKind.video,
            state: control == 'idle'
                ? CallState.idle
                : control == 'ending'
                ? CallState.ending
                : control == 'terminal'
                ? CallState.ended
                : CallState.connected,
          ),
          CallVideoRendererSlot.remote,
        ),
      );
      expect(find.byType(Texture), findsNothing);
      expect(
        find.bySemanticsIdentifier('call_video_view_remote'),
        findsNothing,
      );
    });
  }

  testWidgets(
    'U6-view API reconnect removes texture until current agreement recovers',
    (tester) async {
      await tester.pumpWidget(
        _app(_projection(reconnecting: true), CallVideoRendererSlot.remote),
      );
      expect(find.byType(Texture), findsNothing);
      expect(
        find.bySemanticsIdentifier('call_video_view_remote'),
        findsOneWidget,
      );
      await tester.pumpWidget(
        _app(_projection(generation: 8), CallVideoRendererSlot.remote),
      );
      expect(tester.widget<Texture>(find.byType(Texture)).textureId, 22);
    },
  );

  testWidgets(
    'U6-view API replacement and null retirement drop prior texture metadata',
    (tester) async {
      await tester.pumpWidget(
        _app(_projection(), CallVideoRendererSlot.remote),
      );
      expect(find.byType(Texture), findsOneWidget);
      await tester.pumpWidget(
        _app(
          _projection(
            generation: 8,
            remote: const CallVideoView(textureId: 33, width: 480, height: 640),
          ),
          CallVideoRendererSlot.remote,
        ),
      );
      expect(tester.widget<Texture>(find.byType(Texture)).textureId, 33);
      await tester.pumpWidget(
        _app(
          _projection(generation: 8, remote: null),
          CallVideoRendererSlot.remote,
        ),
      );
      expect(find.byType(Texture), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(
        find.bySemanticsIdentifier('call_video_view_remote'),
        findsNothing,
      );
    },
  );

  for (final (language, localLabel, remoteLabel) in [
    ('en', 'Your camera is paused', 'Their camera is paused'),
    ('ar', 'كاميرتك متوقفة مؤقتًا', 'كاميرا الطرف الآخر متوقفة مؤقتًا'),
    (
      'de',
      'Deine Kamera ist pausiert',
      'Die Kamera deines Gegenübers ist pausiert',
    ),
  ]) {
    for (final slot in CallVideoRendererSlot.values) {
      testWidgets('U6-view API $language $slot 320px2x camera semantics', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            _app(
              _projection(camera: CallCameraState.paused),
              slot,
              locale: Locale(language),
              scale: 2,
            ),
          );
          final node = tester.getSemantics(
            find.bySemanticsIdentifier('call_video_view_${slot.name}'),
          );
          expect(
            node.label,
            slot == CallVideoRendererSlot.local ? localLabel : remoteLabel,
          );
          expect(
            tester.getSize(find.byType(CallVideoViewSurface)).width,
            lessThanOrEqualTo(320),
          );
          expect(
            Directionality.of(
              tester.element(find.byType(CallVideoViewSurface)),
            ),
            language == 'ar' ? TextDirection.rtl : TextDirection.ltr,
          );
          expect(find.byType(Texture), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          semantics.dispose();
        }
      });
    }
  }

  testWidgets(
    'U6 combined controls off still renders current owner video tiles',
    (tester) async {
      var audioActions = 0;
      final current = _projection();
      await tester.pumpWidget(
        _layoutApp(
          onAudio: () => audioActions++,
          videoViews: Row(
            children: [
              Expanded(
                child: CallVideoViewSurface(
                  projection: current,
                  slot: CallVideoRendererSlot.remote,
                ),
              ),
              Expanded(
                child: CallVideoViewSurface(
                  projection: current,
                  slot: CallVideoRendererSlot.local,
                ),
              ),
            ],
          ),
        ),
      );
      expect(find.byType(CallVideoControls), findsNothing);
      expect(
        tester
            .widgetList<Texture>(find.byType(Texture))
            .map((texture) => texture.textureId),
        unorderedEquals([11, 22]),
      );
      expect(
        find.bySemanticsIdentifier('call_video_view_local'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier('call_video_view_remote'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('combined-profile')), findsOneWidget);
      await tester.tap(find.text('Audio'));
      expect(audioActions, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'U6 combined controls off with no views keeps audio-only layout',
    (tester) async {
      var audioActions = 0;
      await tester.pumpWidget(_layoutApp(onAudio: () => audioActions++));
      expect(find.byType(CallVideoControls), findsNothing);
      expect(find.byType(CallVideoViewSurface), findsNothing);
      expect(find.byType(Texture), findsNothing);
      final profile = tester.getRect(
        find.byKey(const ValueKey('combined-profile')),
      );
      final audio = tester.getRect(
        find.byKey(const ValueKey('combined-audio')),
      );
      expect(audio.top - profile.bottom, 16);
      await tester.tap(find.text('Audio'));
      expect(audioActions, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
