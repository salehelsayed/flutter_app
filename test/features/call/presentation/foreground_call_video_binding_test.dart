import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/call/application/call_audio_controller.dart';
import 'package:flutter_app/features/call/application/foreground_call_capability.dart';
import 'package:flutter_app/features/call/application/locked_call_presentation.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart'
    show CallAudioOutputRoute;
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_media.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/presentation/call_video_presentation.dart';
import 'package:flutter_app/features/call/presentation/foreground_call_overlay.dart';
import 'package:flutter_app/features/call/presentation/locked_call_projection.dart';
import 'package:flutter_app/features/call/presentation/screens/active_call_screen.dart';
import 'package:flutter_app/features/call/presentation/screens/incoming_call_screen.dart';
import 'package:flutter_app/features/call/presentation/screens/outgoing_call_screen.dart';
import 'package:flutter_app/features/call/presentation/widgets/call_controls.dart';
import 'package:flutter_app/features/call/presentation/widgets/call_return_bar.dart';
import 'package:flutter_app/features/call/presentation/widgets/call_video_controls.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

enum _Phase { incoming, outgoing, active }

final _callA = CallId.parse('11111111-1111-4111-8111-111111111111');
final _callB = CallId.parse('22222222-2222-4222-8222-222222222222');
final _now = DateTime.utc(2026, 11, 12, 12);

CallVideoPresentation _video({
  bool enabled = true,
  CallWireVersion wire = CallWireVersion.v2,
  CallCameraState camera = CallCameraState.on,
  bool pending = false,
  bool reconnecting = false,
}) => CallVideoPresentation.project(
  videoEnabled: enabled,
  wireVersion: wire,
  requestedMedia: CallMediaKind.video,
  acceptedMedia: CallMediaKind.video,
  agreedMedia: CallMediaKind.video,
  localCamera: camera,
  remoteCamera: CallCameraState.paused,
  isConnected: !reconnecting,
  isReconnecting: reconnecting,
  videoActionPending: pending,
  mayTurnCameraOn: true,
  maySwitchCamera: true,
);

CallVideoPresentation _audioVideo({
  String? incoming,
  String? outgoing,
  bool pending = false,
  bool enabled = true,
}) => CallVideoPresentation.project(
  videoEnabled: enabled,
  wireVersion: CallWireVersion.v2,
  acceptedMedia: CallMediaKind.audio,
  isConnected: true,
  mayRequestVideo: true,
  incomingUpgradeId: incoming,
  outgoingUpgradeId: outgoing,
  videoActionPending: pending,
);

ForegroundCallProjection _projection({
  _Phase phase = _Phase.active,
  CallId? callId,
  int generation = 7,
  bool enabled = true,
  CallWireVersion wire = CallWireVersion.v2,
  CallState? state,
  CallVideoPresentation? media,
  bool muted = false,
}) {
  final callState =
      state ??
      switch (phase) {
        _Phase.incoming => CallState.ringing,
        _Phase.outgoing => CallState.inviting,
        _Phase.active => CallState.connected,
      };
  return ForegroundCallProjection(
    session: CallSessionSnapshot.active(
      callId: callId ?? _callA,
      contactPeerId: 'friend-peer',
      direction: phase == _Phase.incoming
          ? CallDirection.incoming
          : CallDirection.outgoing,
      state: callState,
      callerAccountPeerId: 'caller-account',
      callerDeviceId: 'caller-device',
      startedAt: _now.subtract(const Duration(minutes: 1)),
      connectedAt: phase == _Phase.active
          ? _now.subtract(const Duration(seconds: 30))
          : null,
      endedAt: callState == CallState.ended ? _now : null,
      endReason: callState == CallState.ended
          ? CallEndReason.remoteHangup
          : null,
      incomingValidated: callState != CallState.incomingValidating,
    ),
    audio: CallAudioControlState(
      muted: muted,
      selectedRoute: CallAudioOutputRoute.systemDefault,
      supportedRoutes: const [
        CallAudioOutputRoute.systemDefault,
        CallAudioOutputRoute.speaker,
      ],
      active: true,
      failure: CallAudioFailure.none,
    ),
    video: ForegroundCallVideoProjection(
      generation: generation,
      presentation:
          media ??
          (phase == _Phase.active
              ? _video(enabled: enabled, wire: wire)
              : CallVideoPresentation.project(
                  videoEnabled: enabled,
                  wireVersion: wire,
                  requestedMedia: CallMediaKind.video,
                )),
    ),
  );
}

// These fakes are canonical-owner fixtures. Video dispatch deliberately records
// every call: a fake guard must not hide a missing presentation-side fence.
class _AudioCapability implements ForegroundCallCapability {
  _AudioCapability(this._current);

  ForegroundCallProjection? _current;
  final _changes = StreamController<ForegroundCallProjection?>.broadcast(
    sync: true,
  );
  final audioCalls = <(String, CallId)>[];

  @override
  ForegroundCallProjection? get current => _current;
  @override
  Stream<ForegroundCallProjection?> get changes => _changes.stream;

  void emit(ForegroundCallProjection? value, {bool notify = true}) {
    _current = value;
    if (notify) _changes.add(value);
  }

  Future<void> close() async {
    if (!_changes.isClosed) await _changes.close();
  }

  Future<ForegroundCallActionResult> _record(String name, CallId id) async {
    audioCalls.add((name, id));
    return ForegroundCallActionResult.applied;
  }

  @override
  Future<ForegroundCallActionResult> answer(CallId id) => _record('answer', id);
  @override
  Future<ForegroundCallActionResult> decline(CallId id) =>
      _record('decline', id);
  @override
  Future<ForegroundCallActionResult> cancel(CallId id) => _record('cancel', id);
  @override
  Future<ForegroundCallActionResult> end(CallId id) => _record('end', id);
  @override
  Future<ForegroundCallActionResult> setMuted(CallId id, bool value) =>
      _record('mute', id);
  @override
  Future<ForegroundCallActionResult> setSpeakerEnabled(CallId id, bool value) =>
      _record('speaker', id);
}

class _VideoCapability extends _AudioCapability
    implements ForegroundCallVideoCapability {
  _VideoCapability(super.current);

  final videoCalls =
      <({CallId callId, int generation, CallVideoIntent intent})>[];
  VoidCallback? afterVideo;

  @override
  Future<ForegroundCallActionResult> applyVideoIntent(
    CallId callId, {
    required int generation,
    required CallVideoIntent intent,
  }) async {
    videoCalls.add((callId: callId, generation: generation, intent: intent));
    afterVideo?.call();
    return ForegroundCallActionResult.applied;
  }
}

final class _LockedVideoCapability extends _VideoCapability
    implements LockedCallPresentationPort {
  _LockedVideoCapability(super.current);
  final presentations = <LockedCallPresentation>[];

  @override
  Future<void> updateLockedPresentation(
    CallId callId,
    LockedCallPresentation presentation,
  ) async => presentations.add(presentation);
}

Widget _app(
  _AudioCapability capability, {
  Locale locale = const Locale('en'),
  double scale = 1,
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: ThemeData(
    brightness: Brightness.dark,
    extensions: const <ThemeExtension<dynamic>>[BackgroundReadableColors.dark],
  ),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: ForegroundCallOverlay(
    capability: capability,
    loadContactDisplayName: (_) async => locale.languageCode == 'ar'
        ? 'اسم صديق تجريبي طويل للغاية'
        : 'Alexandria Very Long Synthetic Contact Name',
    now: () => _now,
    child: const Scaffold(body: Center(child: Text('retained route'))),
  ),
);

Future<void> _withOverlay(
  WidgetTester tester,
  _AudioCapability capability,
  Future<void> Function(AppLocalizations l10n) body, {
  Locale locale = const Locale('en'),
  double scale = 1,
}) async {
  final semantics = tester.ensureSemantics();
  try {
    await tester.pumpWidget(_app(capability, locale: locale, scale: scale));
    await tester.pumpAndSettle();
    await body(lookupAppLocalizations(locale));
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    semantics.dispose();
    await capability.close();
  }
}

void _viewport(WidgetTester tester, double width, double height) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

String _audioAction(_Phase phase) => switch (phase) {
  _Phase.incoming => 'answer',
  _Phase.outgoing => 'cancel',
  _Phase.active => 'end',
};

Type _screen(_Phase phase) => switch (phase) {
  _Phase.incoming => IncomingCallScreen,
  _Phase.outgoing => OutgoingCallScreen,
  _Phase.active => ActiveCallScreen,
};

Future<void> _audioTap(WidgetTester tester, _Phase phase) async {
  final action = _audioAction(phase);
  final finder = find.bySemanticsIdentifier('call_$action');
  await tester.ensureVisible(finder);
  await tester.pump();
  final activeNode = find.semantics.byPredicate(
    (node) => node.getSemanticsData().identifier == 'call_$action',
  );
  expect(activeNode, findsOneWidget);
  tester.semantics.tap(activeNode);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('U6R causal default-off keeps real incoming audio Answer', (
    tester,
  ) async {
    final cap = _VideoCapability(
      _projection(phase: _Phase.incoming, enabled: false),
    );
    await _withOverlay(tester, cap, (_) async {
      expect(find.byType(IncomingCallScreen), findsOneWidget);
      expect(find.byType(CallVideoControls), findsNothing);
      expect(tester.takeException(), isNull);
      await _audioTap(tester, _Phase.incoming);
      expect(cap.audioCalls, [('answer', _callA)]);
      expect(cap.videoCalls, isEmpty);
    });
  });

  testWidgets('U6R causal real active screen binds enabled video intent', (
    tester,
  ) async {
    final cap = _VideoCapability(_projection());
    await _withOverlay(tester, cap, (_) async {
      expect(find.byType(ActiveCallScreen), findsOneWidget);
      expect(find.bySemanticsIdentifier('call_end'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(find.byType(CallVideoControls), findsOneWidget);
      final button = find.byKey(const ValueKey('call_video_camera_off'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      expect(cap.videoCalls, hasLength(1));
      expect(cap.videoCalls.single.callId, _callA);
      expect(cap.videoCalls.single.generation, 7);
      expect(
        cap.videoCalls.single.intent.action,
        CallVideoAction.turnCameraOff,
      );
    });
  });

  for (final phase in _Phase.values) {
    for (final gate in ['off', 'v1']) {
      testWidgets('U6R ${phase.name} $gate preserves audio branch', (
        tester,
      ) async {
        final cap = _VideoCapability(
          _projection(
            phase: phase,
            enabled: gate != 'off',
            wire: gate == 'v1' ? CallWireVersion.v1 : CallWireVersion.v2,
          ),
        );
        await _withOverlay(tester, cap, (_) async {
          expect(find.byType(_screen(phase)), findsOneWidget);
          expect(find.byType(CallVideoControls), findsNothing);
          await _audioTap(tester, phase);
          expect(cap.audioCalls, [(_audioAction(phase), _callA)]);
          expect(cap.videoCalls, isEmpty);
          expect(tester.takeException(), isNull);
        });
      });
    }

    testWidgets('U6R ${phase.name} optional interface absent stays audio', (
      tester,
    ) async {
      final cap = _AudioCapability(_projection(phase: phase));
      await _withOverlay(tester, cap, (_) async {
        expect(find.byType(_screen(phase)), findsOneWidget);
        expect(find.byType(CallVideoControls), findsNothing);
        await _audioTap(tester, phase);
        expect(cap.audioCalls, [(_audioAction(phase), _callA)]);
      });
    });

    for (final language in ['en', 'de', 'ar']) {
      for (final width in [320.0, 360.0]) {
        testWidgets(
          'U6R ${phase.name} $language $width real screen 2x geometry and semantics',
          (tester) async {
            _viewport(tester, width, 640);
            final cap = _VideoCapability(_projection(phase: phase));
            await _withOverlay(
              tester,
              cap,
              (l10n) async {
                expect(find.byType(_screen(phase)), findsOneWidget);
                expect(find.byType(CallVideoControls), findsOneWidget);
                expect(tester.takeException(), isNull);
                final status = phase == _Phase.active
                    ? l10n.call_video_status_video
                    : l10n.call_video_status_video_requested;
                final statusNode = tester.getSemantics(
                  find.bySemanticsIdentifier('call_video_status'),
                );
                expect(statusNode.label, status);
                expect(find.semantics.byLabel(status), findsOneWidget);
                expect(find.semantics.byLabel('retained route'), findsNothing);
                final action = phase == _Phase.active
                    ? CallVideoAction.turnCameraOff
                    : CallVideoAction.useAudioOnly;
                final button = find.byKey(ValueKey(action.identifier));
                await tester.ensureVisible(button);
                await tester.pump();
                final rect = tester.getRect(button);
                expect(rect.width, greaterThanOrEqualTo(48));
                expect(rect.height, greaterThanOrEqualTo(48));
                expect(rect.left, greaterThanOrEqualTo(15.99));
                expect(rect.right, lessThanOrEqualTo(width - 15.99));
                expect(rect.top, greaterThanOrEqualTo(0));
                expect(rect.bottom, lessThanOrEqualTo(640));
                expect(
                  Directionality.of(tester.element(button)),
                  language == 'ar' ? TextDirection.rtl : TextDirection.ltr,
                );
                final text = phase == _Phase.active
                    ? l10n.call_video_action_turn_camera_off
                    : l10n.call_video_action_use_audio_only;
                final paragraph = tester.renderObject<RenderParagraph>(
                  find.text(text),
                );
                if (paragraph.didExceedMaxLines) {
                  expect(paragraph.overflow, TextOverflow.ellipsis);
                }
                await tester.tap(button);
                expect(cap.videoCalls.single.intent.action, action);
                expect(cap.videoCalls.single.callId, _callA);
                expect(cap.videoCalls.single.generation, 7);
                await _audioTap(tester, phase);
                expect(cap.audioCalls, [(_audioAction(phase), _callA)]);
                expect(tester.takeException(), isNull);
              },
              locale: Locale(language),
              scale: 2,
            );
          },
        );
      }
    }

    testWidgets('U6R ${phase.name} compact landscape reaches video and audio', (
      tester,
    ) async {
      _viewport(tester, 600, 320);
      final cap = _VideoCapability(_projection(phase: phase));
      await _withOverlay(
        tester,
        cap,
        (_) async {
          expect(find.byType(CallVideoControls), findsOneWidget);
          final action = phase == _Phase.active
              ? CallVideoAction.turnCameraOff
              : CallVideoAction.useAudioOnly;
          final button = find.byKey(ValueKey(action.identifier));
          await tester.ensureVisible(button);
          await tester.pump();
          expect(tester.getRect(button).height, greaterThanOrEqualTo(48));
          await tester.tap(button);
          await _audioTap(tester, phase);
          expect(cap.videoCalls, hasLength(1));
          expect(cap.audioCalls, [(_audioAction(phase), _callA)]);
          expect(tester.takeException(), isNull);
        },
        locale: const Locale('ar'),
        scale: 2,
      );
    });
  }

  for (final change in ['call', 'generation', 'ended', 'gone', 'gate']) {
    testWidgets('U6R stale $change refuses a retained video callback', (
      tester,
    ) async {
      final cap = _VideoCapability(_projection(media: _audioVideo()));
      await _withOverlay(tester, cap, (_) async {
        final send = tester
            .widget<CallVideoControls>(find.byType(CallVideoControls))
            .onIntent;
        cap.emit(switch (change) {
          'call' => _projection(callId: _callB, media: _audioVideo()),
          'generation' => _projection(generation: 8, media: _audioVideo()),
          'ended' => _projection(state: CallState.ended, media: _audioVideo()),
          'gone' => null,
          _ => _projection(media: _audioVideo(enabled: false)),
        }, notify: false);
        send(const CallVideoIntent(CallVideoAction.requestVideo));
        await tester.pump();
        expect(cap.videoCalls, isEmpty);
        expect(cap.audioCalls, isEmpty);
      });
    });
  }

  testWidgets(
    'U6R replaced capability refuses old callback with matching tokens',
    (tester) async {
      final first = _VideoCapability(_projection(media: _audioVideo()));
      final next = _VideoCapability(_projection(media: _audioVideo()));
      addTearDown(next.close);
      await _withOverlay(tester, first, (_) async {
        final send = tester
            .widget<CallVideoControls>(find.byType(CallVideoControls))
            .onIntent;
        await tester.pumpWidget(_app(next));
        await tester.pumpAndSettle();
        send(const CallVideoIntent(CallVideoAction.requestVideo));
        await tester.pump();
        expect(first.videoCalls, isEmpty);
        expect(next.videoCalls, isEmpty);
      });
    },
  );

  testWidgets(
    'U6R current incoming upgrade binds accept and rejects replaced ID',
    (tester) async {
      final cap = _VideoCapability(
        _projection(
          media: _audioVideo(incoming: 'incoming-A', outgoing: 'abandoned-X'),
        ),
      );
      await _withOverlay(tester, cap, (_) async {
        final send = tester
            .widget<CallVideoControls>(find.byType(CallVideoControls))
            .onIntent;
        final accept = find.byKey(const ValueKey('call_video_accept_upgrade'));
        await tester.ensureVisible(accept);
        await tester.tap(accept);
        expect(cap.videoCalls.single.intent.upgradeId, 'incoming-A');
        cap.videoCalls.clear();
        cap.emit(
          _projection(media: _audioVideo(incoming: 'incoming-B')),
          notify: false,
        );
        send(
          const CallVideoIntent(
            CallVideoAction.acceptUpgrade,
            upgradeId: 'incoming-A',
          ),
        );
        await tester.pump();
        expect(cap.videoCalls, isEmpty);
      });
    },
  );

  testWidgets('U6R video intent never optimistically changes camera truth', (
    tester,
  ) async {
    final initial = _projection(media: _video(camera: CallCameraState.off));
    final cap = _VideoCapability(initial);
    await _withOverlay(tester, cap, (l10n) async {
      final button = find.byKey(const ValueKey('call_video_camera_on'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      expect(cap.videoCalls.single.intent.action, CallVideoAction.turnCameraOn);
      expect(cap.current, same(initial));
      expect(
        tester
            .widget<CallVideoControls>(find.byType(CallVideoControls))
            .presentation,
        same(initial.video!.presentation),
      );
      expect(find.text(l10n.call_video_local_camera_off), findsOneWidget);
      cap.emit(_projection());
      await tester.pump();
      expect(find.text(l10n.call_video_local_camera_on), findsOneWidget);
    });
  });

  testWidgets('U6R canonical pending prevents duplicate video requests', (
    tester,
  ) async {
    final cap = _VideoCapability(_projection(media: _audioVideo()));
    cap.afterVideo = () =>
        cap.emit(_projection(media: _audioVideo(pending: true)), notify: false);
    await _withOverlay(tester, cap, (_) async {
      final send = tester
          .widget<CallVideoControls>(find.byType(CallVideoControls))
          .onIntent;
      send(const CallVideoIntent(CallVideoAction.requestVideo));
      send(const CallVideoIntent(CallVideoAction.requestVideo));
      await tester.pump();
      expect(cap.videoCalls, hasLength(1));
      expect(
        tester
            .widget<CallVideoControls>(find.byType(CallVideoControls))
            .presentation
            .videoActionPending,
        isFalse,
        reason: 'Only a canonical stream update changes the view.',
      );
    });
  });

  testWidgets(
    'U6R reconnecting pending video preserves safe off and audio End',
    (tester) async {
      final cap = _VideoCapability(
        _projection(
          state: CallState.reconnecting,
          media: _video(pending: true, reconnecting: true),
        ),
      );
      await _withOverlay(tester, cap, (_) async {
        final off = find.byKey(const ValueKey('call_video_camera_off'));
        await tester.ensureVisible(off);
        await tester.tap(off);
        expect(
          cap.videoCalls.single.intent.action,
          CallVideoAction.turnCameraOff,
        );
        final flip = find.descendant(
          of: find.byKey(const ValueKey('call_video_switch_camera')),
          matching: find.byType(OutlinedButton),
        );
        expect(tester.widget<OutlinedButton>(flip).onPressed, isNull);
        await _audioTap(tester, _Phase.active);
        expect(cap.audioCalls, [('end', _callA)]);
      });
    },
  );

  testWidgets(
    'U6R incoming validation exposes no video action; Answer stays audio',
    (tester) async {
      final cap = _VideoCapability(
        _projection(
          phase: _Phase.incoming,
          state: CallState.incomingValidating,
        ),
      );
      await _withOverlay(tester, cap, (_) async {
        expect(find.byType(CallVideoControls), findsNothing);
        cap.emit(_projection(phase: _Phase.incoming));
        await tester.pumpAndSettle();
        expect(find.byType(CallVideoControls), findsOneWidget);
        await _audioTap(tester, _Phase.incoming);
        expect(cap.audioCalls, [('answer', _callA)]);
        expect(cap.videoCalls, isEmpty);
        expect(
          cap.current!.video!.presentation.localCamera,
          CallCameraState.off,
        );
        expect(cap.current!.video!.presentation.acceptedMedia, isNull);
      });
    },
  );

  testWidgets(
    'U6R minimize and return retain owners and invalidate disposed UI',
    (tester) async {
      final cap = _VideoCapability(_projection());
      await _withOverlay(tester, cap, (_) async {
        final navigator = tester.state<NavigatorState>(
          find.byType(Navigator).first,
        );
        final send = tester
            .widget<CallVideoControls>(find.byType(CallVideoControls))
            .onIntent;
        await tester.tap(find.byKey(const ValueKey('call-minimize')));
        await tester.pumpAndSettle();
        expect(find.byType(CallReturnBar), findsOneWidget);
        expect(find.byType(CallVideoControls), findsNothing);
        expect(find.semantics.byLabel('retained route'), findsOneWidget);
        send(const CallVideoIntent(CallVideoAction.turnCameraOff));
        cap.emit(_projection(generation: 8, muted: true));
        await tester.pump();
        await tester.tap(find.byType(CallReturnBar));
        await tester.pumpAndSettle();
        expect(
          tester.state<NavigatorState>(find.byType(Navigator).first),
          same(navigator),
        );
        expect(
          tester.widget<CallControls>(find.byType(CallControls)).isMuted,
          isTrue,
        );
        expect(find.byType(CallVideoControls), findsOneWidget);
        send(const CallVideoIntent(CallVideoAction.turnCameraOff));
        await tester.pump();
        expect(cap.videoCalls, isEmpty);
        expect(cap.audioCalls, isEmpty);
      });
    },
  );

  test(
    'U6R locked presentation remains exactly audio-only with video metadata',
    () async {
      final video = _projection();
      final cap = _LockedVideoCapability(video);
      final projection = LockedCallProjection(
        avatarRenderer: (_, _) async => null,
      );
      addTearDown(cap.close);
      addTearDown(projection.dispose);
      final l10n = lookupAppLocalizations(const Locale('en'));
      await projection.update(
        capability: cap,
        projection: ForegroundCallProjection(
          session: video.session,
          audio: video.audio,
        ),
        displayName: 'Mira',
        light: false,
        l10n: l10n,
      );
      final audioOnly = cap.presentations.last.toMap();
      await projection.update(
        capability: cap,
        projection: video,
        displayName: 'Mira',
        light: false,
        l10n: l10n,
      );
      expect(cap.presentations.last.toMap(), audioOnly);
      expect(cap.videoCalls, isEmpty);
    },
  );
}
