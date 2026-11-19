import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:flutter_app/features/call/presentation/screens/active_call_screen.dart';
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
  _vui5aTests();
}

class _VUI5aCapability extends _Capability {
  _VUI5aCapability(super.initial) : _latest = initial;

  ForegroundCallProjection _latest;
  @override
  ForegroundCallProjection get current => _latest;

  void emit(ForegroundCallProjection projection) {
    _latest = projection;
    events.add(projection);
  }
}

ForegroundCallProjection _vui5aProjection({
  CallState state = CallState.connected,
  bool reconnecting = false,
  CallCameraState remote = CallCameraState.on,
  bool retainViews = true,
  int generation = 7,
  int localTexture = 11,
  int remoteTexture = 22,
}) {
  final base = _projection();
  return ForegroundCallProjection(
    session: base.session.copyWith(state: state),
    audio: base.audio,
    video: ForegroundCallVideoProjection(
      generation: generation,
      localView: retainViews
          ? CallVideoView(textureId: localTexture, width: 640, height: 480)
          : null,
      remoteView: retainViews
          ? CallVideoView(textureId: remoteTexture, width: 1280, height: 720)
          : null,
      presentation: CallVideoPresentation.project(
        videoEnabled: true,
        wireVersion: CallWireVersion.v2,
        requestedMedia: CallMediaKind.video,
        acceptedMedia: CallMediaKind.video,
        agreedMedia: CallMediaKind.video,
        localCamera: CallCameraState.on,
        remoteCamera: remote,
        isConnected: !reconnecting,
        isReconnecting: reconnecting,
        mayTurnCameraOn: true,
        maySwitchCamera: true,
      ),
    ),
  );
}

Future<void> _vui5aWithCall(
  WidgetTester tester,
  _VUI5aCapability capability,
  Future<void> Function() body, {
  String language = 'en',
  Size size = const Size(390, 844),
  double scale = 1,
  DateTime Function()? now,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  try {
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
          brightness: Brightness.dark,
          extensions: const [BackgroundReadableColors.dark],
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: ForegroundCallOverlay(
          capability: capability,
          loadContactDisplayName: (_) async => 'Layla',
          now: now ?? () => _now,
          child: const Scaffold(body: Text('Chat')),
        ),
      ),
    );
    await tester.pump();
    await body();
    expect(tester.takeException(), isNull);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(
      () => capability.events.close().timeout(const Duration(seconds: 5)),
    );
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

Future<void> _vui5aPumpProjection(
  WidgetTester tester,
  _VUI5aCapability capability,
) async {
  // Async broadcast delivery can schedule the frame only at the first pump's
  // final microtask flush. Draw that frame before checking presentation.
  await tester.pump();
  await tester.pump();
  final screen = tester.widget<ActiveCallScreen>(find.byType(ActiveCallScreen));
  final emitted = capability.current;
  expect(screen.state, emitted.session.state);
  expect(screen.videoPresentation, same(emitted.video!.presentation));
}

Finder _vui5aExpectFallback(WidgetTester tester) {
  final avatar = find.byType(UserAvatar);
  // Positive presentation assertions precede safety checks that already pass.
  expect(avatar, findsOneWidget);
  final l10n = AppLocalizations.of(tester.element(avatar))!;
  final pill = find.text(l10n.call_video_status_reconnecting);
  expect(pill, findsOneWidget);
  expect(
    find.ancestor(
      of: pill,
      matching: find.byWidgetPredicate(
        (widget) => switch (widget) {
          DecoratedBox(decoration: BoxDecoration(:final borderRadius)) =>
            borderRadius != null && borderRadius != BorderRadius.zero,
          Material(:final borderRadius, :final shape) =>
            (borderRadius != null && borderRadius != BorderRadius.zero) ||
                shape is RoundedRectangleBorder ||
                shape is StadiumBorder,
          ClipRRect(:final borderRadius) => borderRadius != BorderRadius.zero,
          _ => false,
        },
      ),
    ),
    findsWidgets,
  );
  expect(find.byKey(const ValueKey('call-video-views')), findsNothing);
  expect(_view('remote'), findsNothing);
  expect(_view('local'), findsNothing);
  expect(find.byKey(const ValueKey('call-video-preview-flip')), findsNothing);
  expect(find.byType(Texture), findsNothing);
  expect(find.text(l10n.call_video_remote_camera_on), findsNothing);
  expect(find.text(l10n.call_video_waiting_for_remote('Layla')), findsNothing);
  expect(find.text('Layla'), findsOneWidget);
  final bounds =
      Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);
  final avatarRect = tester.getRect(avatar);
  final pillRect = tester.getRect(pill);
  final nameRect = tester.getRect(find.text('Layla'));
  expect(find.text('01:05'), findsOneWidget);
  final durationRect = tester.getRect(find.text('01:05'));
  for (final rect in [avatarRect, pillRect, nameRect, durationRect]) {
    expect(rect.left, greaterThanOrEqualTo(bounds.left));
    expect(rect.right, lessThanOrEqualTo(bounds.right));
    expect(rect.top, greaterThanOrEqualTo(bounds.top));
    expect(rect.bottom, lessThanOrEqualTo(bounds.bottom));
  }
  expect(avatarRect.overlaps(pillRect), isFalse);
  expect(avatarRect.overlaps(nameRect), isFalse);
  expect(pillRect.overlaps(nameRect), isFalse);
  expect(durationRect.overlaps(avatarRect), isFalse);
  expect(durationRect.overlaps(pillRect), isFalse);
  for (final action in ['mute', 'speaker', 'end']) {
    final control = _control('call_$action');
    expect(control, findsOneWidget);
    final rect = tester.getRect(control);
    expect(rect.width, greaterThanOrEqualTo(48));
    expect(rect.height, greaterThanOrEqualTo(48));
    expect(rect.left, greaterThanOrEqualTo(bounds.left));
    expect(rect.right, lessThanOrEqualTo(bounds.right));
    expect(rect.top, greaterThanOrEqualTo(bounds.top));
    expect(rect.bottom, lessThanOrEqualTo(bounds.bottom));
    expect(rect.overlaps(avatarRect), isFalse);
    expect(rect.overlaps(pillRect), isFalse);
    expect(control.hitTestable(), findsOneWidget);
  }
  final reconnect = l10n.call_video_status_reconnecting;
  expect(
    find.semantics.byPredicate(
      (node) => node.getSemanticsData().label.contains(reconnect),
    ),
    findsOneWidget,
  );
  final status = tester
      .getSemantics(_control('call_video_status'))
      .getSemanticsData();
  expect(status.label, reconnect);
  expect(status.flagsCollection.isLiveRegion, isTrue);
  expect(status.flagsCollection.isButton, isFalse);
  expect(status.hasAction(SemanticsAction.tap), isFalse);
  return pill;
}

void _vui5aTests() {
  for (final (label, state, reconnecting, remote, retainViews) in [
    (
      'retained on metadata',
      CallState.reconnecting,
      true,
      CallCameraState.on,
      true,
    ),
    ('null metadata', CallState.reconnecting, true, CallCameraState.on, false),
    ('remote off', CallState.reconnecting, true, CallCameraState.off, true),
    (
      'remote paused',
      CallState.reconnecting,
      true,
      CallCameraState.paused,
      true,
    ),
    (
      'session-only reconnect',
      CallState.reconnecting,
      false,
      CallCameraState.on,
      true,
    ),
    (
      'presentation-only reconnect',
      CallState.connected,
      true,
      CallCameraState.on,
      true,
    ),
  ]) {
    testWidgets('VUI5a $label shows an unobscured passive fallback', (
      tester,
    ) async {
      final capability = _VUI5aCapability(_vui5aProjection());
      await _vui5aWithCall(tester, capability, () async {
        expect(
          tester
              .widgetList<Texture>(find.byType(Texture))
              .map((texture) => texture.textureId),
          unorderedEquals([11, 22]),
        );
        capability.emit(
          _vui5aProjection(
            state: state,
            reconnecting: reconnecting,
            remote: remote,
            retainViews: retainViews,
          ),
        );
        await _vui5aPumpProjection(tester, capability);
        final pill = _vui5aExpectFallback(tester);
        expect(find.text('01:05'), findsOneWidget);
        expect(
          tester
              .getRect(find.text('01:05'))
              .overlaps(tester.getRect(find.byType(UserAvatar))),
          isFalse,
        );
        await tester.tap(pill);
        await tester.pump();
        expect(capability.video, isEmpty);
        expect(capability.audio, isEmpty);
      });
    }, timeout: const Timeout.factor(1));
  }

  testWidgets(
    'VUI5a recovery renders only new views and retains call duration',
    (tester) async {
      var now = _now;
      final capability = _VUI5aCapability(_vui5aProjection());
      await _vui5aWithCall(tester, capability, () async {
        capability.emit(
          _vui5aProjection(state: CallState.reconnecting, reconnecting: true),
        );
        await _vui5aPumpProjection(tester, capability);
        _vui5aExpectFallback(tester);
        now = now.add(const Duration(seconds: 2));
        await tester.pump(const Duration(seconds: 2));
        expect(find.text('01:07'), findsOneWidget);
        capability.emit(
          _vui5aProjection(generation: 8, localTexture: 33, remoteTexture: 44),
        );
        await _vui5aPumpProjection(tester, capability);
        expect(find.byType(UserAvatar), findsNothing);
        final l10n = AppLocalizations.of(tester.element(_control('call_end')))!;
        expect(find.text(l10n.call_video_status_reconnecting), findsNothing);
        expect(
          tester
              .widgetList<Texture>(find.byType(Texture))
              .map((texture) => texture.textureId),
          unorderedEquals([33, 44]),
        );
        expect(find.text('01:07'), findsOneWidget);
        now = now.add(const Duration(seconds: 3));
        await tester.pump(const Duration(seconds: 3));
        expect(find.text('01:10'), findsOneWidget);
        expect(capability.video, isEmpty);
        expect(capability.audio, isEmpty);
      }, now: () => now);
    },
    timeout: const Timeout.factor(1),
  );

  for (final language in ['en', 'de', 'ar']) {
    testWidgets(
      'VUI5a $language 320px2x reconnect preserves text and actions',
      (tester) async {
        final capability = _VUI5aCapability(_vui5aProjection());
        await _vui5aWithCall(
          tester,
          capability,
          () async {
            capability.emit(
              _vui5aProjection(
                state: CallState.reconnecting,
                reconnecting: true,
              ),
            );
            await _vui5aPumpProjection(tester, capability);
            final pill = _vui5aExpectFallback(tester);
            final paragraph = tester.renderObject<RenderParagraph>(pill);
            expect(paragraph.didExceedMaxLines, isFalse);
            expect(
              paragraph.textDirection,
              language == 'ar' ? TextDirection.rtl : TextDirection.ltr,
            );
            expect(find.text('01:05'), findsOneWidget);
            final duration = tester.getRect(find.text('01:05'));
            expect(duration.overlaps(tester.getRect(pill)), isFalse);
            expect(
              duration.overlaps(tester.getRect(find.byType(UserAvatar))),
              isFalse,
            );
            await tester.tap(pill);
            await tester.pump();
            expect(capability.audio, isEmpty);
            expect(capability.video, isEmpty);
            for (final action in ['mute', 'speaker', 'end']) {
              final control = _control('call_$action');
              tester.semantics.tap(
                find.semantics.byPredicate(
                  (node) =>
                      node.getSemanticsData().identifier == 'call_$action',
                ),
              );
              await tester.pump();
              expect(control, findsOneWidget);
            }
            expect(capability.audio, ['mute', 'speaker', 'end']);
            expect(capability.video, isEmpty);
          },
          language: language,
          size: const Size(320, 844),
          scale: 2,
        );
      },
      timeout: const Timeout.factor(1),
    );
  }
}
