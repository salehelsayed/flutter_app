import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/call/application/call_audio_controller.dart';
import 'package:flutter_app/features/call/application/call_video_presentation.dart';
import 'package:flutter_app/features/call/application/foreground_call_capability.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_media.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/presentation/foreground_call_overlay.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

final _id = CallId.parse('11111111-1111-4111-8111-111111111111');
final _now = DateTime.utc(2026, 11, 14, 12);

ForegroundCallProjection _projection({
  CallCameraState local = CallCameraState.on,
  CallCameraState remote = CallCameraState.on,
  bool pending = false,
}) => ForegroundCallProjection(
  session: CallSessionSnapshot.active(
    callId: _id,
    contactPeerId: 'friend',
    direction: CallDirection.outgoing,
    state: CallState.connected,
    callerAccountPeerId: 'caller',
    callerDeviceId: 'device',
    startedAt: _now.subtract(const Duration(minutes: 2)),
    connectedAt: _now.subtract(const Duration(seconds: 65)),
  ),
  audio: CallAudioControlState(
    muted: false,
    selectedRoute: CallAudioOutputRoute.systemDefault,
    supportedRoutes: const [
      CallAudioOutputRoute.systemDefault,
      CallAudioOutputRoute.speaker,
    ],
    active: true,
    failure: CallAudioFailure.none,
  ),
  video: ForegroundCallVideoProjection(
    generation: 7,
    // Deliberately retain both views even when a camera is off: presentation
    // must gate pixels using current camera truth, not metadata presence.
    localView: const CallVideoView(textureId: 11, width: 640, height: 480),
    remoteView: const CallVideoView(textureId: 22, width: 1280, height: 720),
    presentation: CallVideoPresentation.project(
      videoEnabled: true,
      wireVersion: CallWireVersion.v2,
      requestedMedia: CallMediaKind.video,
      acceptedMedia: CallMediaKind.video,
      agreedMedia: CallMediaKind.video,
      localCamera: local,
      remoteCamera: remote,
      isConnected: true,
      videoActionPending: pending,
      mayTurnCameraOn: true,
      maySwitchCamera: true,
    ),
  ),
);

class _Capability
    implements ForegroundCallCapability, ForegroundCallVideoCapability {
  _Capability(this.current);

  @override
  final ForegroundCallProjection current;
  final events = StreamController<ForegroundCallProjection?>.broadcast();
  final audio = <String>[];
  final video = <CallVideoIntent>[];

  @override
  Stream<ForegroundCallProjection?> get changes => events.stream;
  Future<ForegroundCallActionResult> _record(String action) async {
    audio.add(action);
    return ForegroundCallActionResult.applied;
  }

  @override
  Future<ForegroundCallActionResult> answer(CallId id) => _record('answer');
  @override
  Future<ForegroundCallActionResult> decline(CallId id) => _record('decline');
  @override
  Future<ForegroundCallActionResult> cancel(CallId id) => _record('cancel');
  @override
  Future<ForegroundCallActionResult> end(CallId id) => _record('end');
  @override
  Future<ForegroundCallActionResult> setMuted(CallId id, bool value) =>
      _record('mute');
  @override
  Future<ForegroundCallActionResult> setSpeakerEnabled(CallId id, bool value) =>
      _record('speaker');
  @override
  Future<ForegroundCallActionResult> applyVideoIntent(
    CallId id, {
    required int generation,
    required CallVideoIntent intent,
  }) async {
    // Record every call; the fake does not mask an incorrect UI dispatch.
    video.add(intent);
    return ForegroundCallActionResult.applied;
  }
}

Future<void> _withCall(
  WidgetTester tester,
  _Capability capability,
  Future<void> Function() body, {
  Locale locale = const Locale('en'),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  final semantics = tester.ensureSemantics();
  try {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
          brightness: Brightness.dark,
          extensions: const [BackgroundReadableColors.dark],
        ),
        home: ForegroundCallOverlay(
          capability: capability,
          loadContactDisplayName: (_) async => 'Layla',
          now: () => _now,
          child: const Scaffold(body: Text('Chat')),
        ),
      ),
    );
    await tester.pump();
    await body();
    expect(tester.takeException(), isNull);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await capability.events.close();
    semantics.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

Finder _control(String id) => find.bySemanticsIdentifier(id);
Finder _view(String slot) => _control('call_video_view_$slot');

void main() {
  testWidgets('VUI-1 remote video fills the call behind compact identity', (
    tester,
  ) async {
    await _withCall(tester, _Capability(_projection()), () async {
      final remote = tester.getRect(_view('remote'));
      expect(remote.left, closeTo(0, 1));
      expect(remote.top, closeTo(0, 1));
      expect(remote.width, closeTo(390, 1));
      expect(remote.height, closeTo(844, 1));
      expect(tester.getRect(find.text('Layla')).bottom, lessThan(100));
      expect(find.byType(UserAvatar), findsNothing);
      expect(find.text('01:05'), findsOneWidget);
    });
  });

  for (final language in ['en', 'ar']) {
    testWidgets('VUI-1 $language portrait preview stays at the top end', (
      tester,
    ) async {
      await _withCall(tester, _Capability(_projection()), () async {
        final local = tester.getRect(_view('local'));
        expect(local.height, greaterThan(local.width));
        expect(local.width, inInclusiveRange(96, 132));
        expect(local.top, inInclusiveRange(90, 150));
        if (language == 'ar') {
          expect(local.left, inInclusiveRange(12, 24));
        } else {
          expect(390 - local.right, inInclusiveRange(12, 24));
        }
      }, locale: Locale(language));
    });
  }

  testWidgets('VUI-1 camera and audio actions share one reachable row', (
    tester,
  ) async {
    final capability = _Capability(_projection());
    await _withCall(tester, capability, () async {
      const identifiers = [
        'call_video_switch_camera',
        'call_video_camera_off',
        'call_mute',
        'call_speaker',
        'call_end',
      ];
      final rects = identifiers
          .map((id) => tester.getRect(_control(id)))
          .toList();
      for (final rect in rects) {
        expect(rect.center.dy, closeTo(rects.last.center.dy, 2));
        expect(rect.width, greaterThanOrEqualTo(48));
        expect(rect.height, greaterThanOrEqualTo(48));
        expect(rect.bottom, lessThanOrEqualTo(844));
      }
      for (var i = 1; i < rects.length; i++) {
        expect(rects[i].left, greaterThanOrEqualTo(rects[i - 1].right));
      }
      expect(capability.video, isEmpty);
      await tester.tap(_control('call_video_camera_off'));
      await tester.pump();
      await tester.tap(_control('call_mute'));
      await tester.pump();
      await tester.tap(_control('call_end'));
      await tester.pump();
      expect(capability.video.map((intent) => intent.action), [
        CallVideoAction.turnCameraOff,
      ]);
      expect(capability.audio, ['mute', 'end']);
    });
  });

  for (final (local, remote) in [
    (CallCameraState.off, CallCameraState.on),
    (CallCameraState.on, CallCameraState.off),
    (CallCameraState.off, CallCameraState.off),
  ]) {
    testWidgets('VUI-1 local $local remote $remote keep independent pixels', (
      tester,
    ) async {
      final capability = _Capability(_projection(local: local, remote: remote));
      await _withCall(tester, capability, () async {
        final textures = tester.widgetList<Texture>(find.byType(Texture));
        expect(
          textures.map((texture) => texture.textureId),
          unorderedEquals([
            if (local == CallCameraState.on) 11,
            if (remote == CallCameraState.on) 22,
          ]),
        );
        final preview = tester.getRect(_view('local'));
        expect(preview.height, greaterThan(preview.width));
        if (remote == CallCameraState.off) {
          expect(find.byType(UserAvatar), findsOneWidget);
          expect(
            tester.getRect(find.byType(UserAvatar)).center.dy,
            inInclusiveRange(260, 500),
          );
        }
        if (local == CallCameraState.off) {
          expect(
            find.descendant(of: _view('local'), matching: find.byType(Text)),
            findsWidgets,
          );
        }
        expect(capability.video, isEmpty);
      });
    });
  }

  testWidgets('VUI-1 pending camera remains off while End stays reachable', (
    tester,
  ) async {
    final capability = _Capability(
      _projection(local: CallCameraState.off, pending: true),
    );
    await _withCall(tester, capability, () async {
      final camera = _control('call_video_camera_on');
      final flip = _control('call_video_switch_camera');
      expect(
        tester.getRect(camera).center.dy,
        closeTo(tester.getRect(_control('call_end')).center.dy, 2),
      );
      expect(
        tester
            .getSemantics(camera)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isFalse,
      );
      expect(
        tester
            .getSemantics(flip)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isFalse,
      );
      await tester.tap(camera);
      await tester.pump();
      expect(capability.video, isEmpty);
      await tester.tap(_control('call_end'));
      await tester.pump();
      expect(capability.audio, ['end']);
    });
  });
}
