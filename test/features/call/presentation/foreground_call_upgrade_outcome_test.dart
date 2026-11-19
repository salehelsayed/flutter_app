import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/call/application/call_audio_controller.dart';
import 'package:flutter_app/features/call/application/foreground_call_capability.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_media.dart';
import 'package:flutter_app/features/call/domain/call_media_switch.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/presentation/call_video_presentation.dart';
import 'package:flutter_app/features/call/presentation/foreground_call_overlay.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

final _callA = CallId.parse('11111111-1111-4111-8111-111111111111');
final _callB = CallId.parse('22222222-2222-4222-8222-222222222222');
final _now = DateTime.utc(2026, 11, 14);

MediaSwitchOutcome _outcome(
  MediaSwitchOutcomeKind kind, {
  String id = 'upgrade-1',
  int revision = 0,
}) => MediaSwitchOutcome(switchId: id, baseRevision: revision, kind: kind);

ForegroundCallProjection _projection({
  MediaSwitchOutcome? outcome,
  CallId? callId,
  int generation = 7,
  CallState state = CallState.connected,
  bool visible = true,
  bool videoPresent = true,
  String? incoming,
  String? outgoing,
  CallMediaKind agreed = CallMediaKind.audio,
}) => ForegroundCallProjection(
  session: CallSessionSnapshot.active(
    callId: callId ?? _callA,
    contactPeerId: 'friend-peer',
    direction: CallDirection.outgoing,
    state: state,
    callerAccountPeerId: 'local-account',
    callerDeviceId: 'local-device',
    startedAt: _now.subtract(const Duration(minutes: 1)),
    connectedAt: _now.subtract(const Duration(seconds: 30)),
    endedAt: state == CallState.ended ? _now : null,
    endReason: state == CallState.ended ? CallEndReason.remoteHangup : null,
    incomingValidated: true,
  ),
  audio: CallAudioControlState(
    muted: false,
    selectedRoute: CallAudioOutputRoute.systemDefault,
    supportedRoutes: const [
      CallAudioOutputRoute.systemDefault,
      CallAudioOutputRoute.speaker,
    ],
    active: state == CallState.connected,
    failure: CallAudioFailure.none,
  ),
  video: videoPresent
      ? ForegroundCallVideoProjection(
          generation: generation,
          upgradeOutcome: outcome,
          presentation: CallVideoPresentation.project(
            videoEnabled: visible,
            wireVersion: CallWireVersion.v2,
            acceptedMedia: CallMediaKind.audio,
            agreedMedia: agreed,
            isConnected: state == CallState.connected,
            incomingUpgradeId: incoming,
            outgoingUpgradeId: outgoing,
            mayRequestVideo: true,
          ),
        )
      : null,
);

// Record every dispatch. These fixtures do not hide missing presentation guards.
class _Capability
    implements ForegroundCallCapability, ForegroundCallVideoCapability {
  _Capability(this._current);
  ForegroundCallProjection? _current;
  final _changes = StreamController<ForegroundCallProjection?>.broadcast(
    sync: true,
  );
  final audioCalls = <String>[];
  final videoCalls = <CallVideoIntent>[];
  @override
  ForegroundCallProjection? get current => _current;
  @override
  Stream<ForegroundCallProjection?> get changes => _changes.stream;
  void emit(ForegroundCallProjection? value) {
    _current = value;
    _changes.add(value);
  }

  Future<void> close() => _changes.close();
  Future<ForegroundCallActionResult> _record(String action) async {
    audioCalls.add(action);
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
  Future<ForegroundCallActionResult> setMuted(CallId id, bool muted) =>
      _record('mute');
  @override
  Future<ForegroundCallActionResult> setSpeakerEnabled(
    CallId id,
    bool enabled,
  ) => _record('speaker');
  @override
  Future<ForegroundCallActionResult> applyVideoIntent(
    CallId id, {
    required int generation,
    required CallVideoIntent intent,
  }) async {
    videoCalls.add(intent);
    return ForegroundCallActionResult.applied;
  }
}

Widget _app(_Capability capability, {String locale = 'en', double scale = 1}) =>
    MaterialApp(
      locale: Locale(locale),
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
        loadContactDisplayName: (_) async => 'ليلى صاحبة الاسم الطويل',
        now: () => _now,
        child: const Scaffold(),
      ),
    );

Future<void> _withOverlay(
  WidgetTester tester,
  _Capability capability,
  Future<void> Function() body, {
  String locale = 'en',
  double scale = 1,
}) async {
  try {
    await tester.pumpWidget(_app(capability, locale: locale, scale: scale));
    await tester.pump();
    await body();
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await capability.close();
    await tester.pump();
  }
}

String _copy(AppLocalizations l10n, MediaSwitchOutcomeKind kind) =>
    switch (kind) {
      MediaSwitchOutcomeKind.declined => l10n.call_video_request_declined,
      MediaSwitchOutcomeKind.expired => l10n.call_video_request_expired,
      MediaSwitchOutcomeKind.cancelled => l10n.call_video_request_cancelled,
    };

Future<void> _show(
  WidgetTester tester,
  _Capability capability,
  MediaSwitchOutcome outcome, {
  String locale = 'en',
}) async {
  capability.emit(_projection(outcome: outcome));
  await tester.pump();
  expect(
    find.text(_copy(lookupAppLocalizations(Locale(locale)), outcome.kind)),
    findsOneWidget,
  );
}

void main() {
  for (final locale in ['en', 'de', 'ar']) {
    for (final kind in MediaSwitchOutcomeKind.values) {
      testWidgets(
        'VUI3b $locale $kind announces a fresh notice for three seconds',
        (tester) async {
          final capability = _Capability(_projection());
          await _withOverlay(tester, capability, () async {
            final outcome = _outcome(kind);
            await _show(tester, capability, outcome, locale: locale);
            final finder = find.text(
              _copy(lookupAppLocalizations(Locale(locale)), kind),
            );
            expect(
              tester
                  .getSemantics(finder)
                  .getSemanticsData()
                  .flagsCollection.isLiveRegion,
              isTrue,
            );
            expect(capability.audioCalls, isEmpty);
            expect(capability.videoCalls, isEmpty);
            await tester.pump(const Duration(milliseconds: 2999));
            expect(finder, findsOneWidget);
            await tester.pump(const Duration(milliseconds: 1));
            expect(finder, findsNothing);
          }, locale: locale);
        },
        timeout: const Timeout.factor(1),
      );
    }
  }

  testWidgets('VUI3b duplicate refresh does not renew or revive a notice', (
    tester,
  ) async {
    final capability = _Capability(_projection());
    await _withOverlay(tester, capability, () async {
      final outcome = _outcome(MediaSwitchOutcomeKind.declined);
      await _show(tester, capability, outcome);
      final text = _copy(
        lookupAppLocalizations(const Locale('en')),
        outcome.kind,
      );
      await tester.pump(const Duration(milliseconds: 2500));
      capability.emit(_projection(outcome: _outcome(outcome.kind)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text(text), findsNothing);
      capability.emit(_projection(outcome: outcome));
      await tester.pump();
      expect(find.text(text), findsNothing);
    });
  }, timeout: const Timeout.factor(1));

  testWidgets('VUI3b an outcome present at mount is consumed, not replayed', (
    tester,
  ) async {
    final retained = _outcome(MediaSwitchOutcomeKind.declined);
    final capability = _Capability(_projection(outcome: retained));
    await _withOverlay(tester, capability, () async {
      final text = _copy(
        lookupAppLocalizations(const Locale('en')),
        retained.kind,
      );
      expect(find.text(text), findsNothing);
      capability.emit(_projection(outcome: retained));
      await tester.pump();
      expect(find.text(text), findsNothing);
      await _show(
        tester,
        capability,
        _outcome(MediaSwitchOutcomeKind.cancelled, id: 'upgrade-2'),
      );
    });
  }, timeout: const Timeout.factor(1));

  for (final withdrawal in ['null', 'no video', 'disabled']) {
    testWidgets(
      'VUI3b $withdrawal withdrawal clears and consumes retained outcome',
      (tester) async {
        final capability = _Capability(_projection());
        await _withOverlay(tester, capability, () async {
          final outcome = _outcome(MediaSwitchOutcomeKind.declined);
          await _show(tester, capability, outcome);
          capability.emit(switch (withdrawal) {
            'null' => null,
            'no video' => _projection(videoPresent: false),
            _ => _projection(outcome: outcome, visible: false),
          });
          await tester.pump();
          final text = _copy(
            lookupAppLocalizations(const Locale('en')),
            outcome.kind,
          );
          expect(find.text(text), findsNothing);
          capability.emit(_projection(outcome: outcome));
          await tester.pump();
          expect(find.text(text), findsNothing);
        });
      },
      timeout: const Timeout.factor(1),
    );
  }

  testWidgets('VUI3b an unseen outcome on return is consumed as a baseline', (
    tester,
  ) async {
    final capability = _Capability(_projection());
    await _withOverlay(tester, capability, () async {
      await _show(
        tester,
        capability,
        _outcome(MediaSwitchOutcomeKind.declined),
      );
      capability.emit(null);
      await tester.pump();
      capability.emit(
        _projection(
          outcome: _outcome(
            MediaSwitchOutcomeKind.expired,
            id: 'while-withdrawn',
          ),
        ),
      );
      await tester.pump();
      final text = lookupAppLocalizations(const Locale('en'))
          .call_video_request_expired;
      expect(find.text(text), findsNothing);
      await _show(
        tester,
        capability,
        _outcome(MediaSwitchOutcomeKind.cancelled, id: 'after-return'),
      );
    });
  }, timeout: const Timeout.factor(1));

  for (final clear in [
    'incoming request',
    'outgoing request',
    'success',
    'End',
    'successor',
    'generation',
  ]) {
    testWidgets('VUI3b $clear clears the current notice', (tester) async {
      final capability = _Capability(_projection());
      await _withOverlay(tester, capability, () async {
        final outcome = _outcome(MediaSwitchOutcomeKind.declined);
        await _show(tester, capability, outcome);
        capability.emit(switch (clear) {
          'incoming request' => _projection(incoming: 'upgrade-2'),
          'outgoing request' => _projection(outgoing: 'upgrade-2'),
          'success' => _projection(agreed: CallMediaKind.video),
          'End' => _projection(state: CallState.ended),
          'successor' => _projection(callId: _callB, outcome: outcome),
          _ => _projection(generation: 8, outcome: outcome),
        });
        await tester.pump();
        expect(
          find.text(
            _copy(lookupAppLocalizations(const Locale('en')), outcome.kind),
          ),
          findsNothing,
        );
      });
    }, timeout: const Timeout.factor(1));
  }

  testWidgets('VUI3b capability replacement suppresses its retained outcome', (
    tester,
  ) async {
    final first = _Capability(_projection());
    final second = _Capability(
      _projection(outcome: _outcome(MediaSwitchOutcomeKind.expired)),
    );
    try {
      await _withOverlay(tester, first, () async {
        await _show(tester, first, _outcome(MediaSwitchOutcomeKind.declined));
        await tester.pumpWidget(_app(second));
        await tester.pump();
        final l10n = lookupAppLocalizations(const Locale('en'));
        expect(find.text(l10n.call_video_request_declined), findsNothing);
        expect(find.text(l10n.call_video_request_expired), findsNothing);
        first.emit(
          _projection(
            outcome: _outcome(MediaSwitchOutcomeKind.declined, id: 'late-old'),
          ),
        );
        await tester.pump();
        expect(find.text(l10n.call_video_request_declined), findsNothing);
        await _show(
          tester,
          second,
          _outcome(MediaSwitchOutcomeKind.cancelled, id: 'new-owner'),
        );
      });
    } finally {
      await second.close();
    }
  }, timeout: const Timeout.factor(1));

  testWidgets('VUI3b a later base revision has a distinct notice identity', (
    tester,
  ) async {
    final capability = _Capability(_projection());
    await _withOverlay(tester, capability, () async {
      await _show(
        tester,
        capability,
        _outcome(MediaSwitchOutcomeKind.declined),
      );
      await tester.pump(const Duration(seconds: 3));
      await _show(
        tester,
        capability,
        _outcome(MediaSwitchOutcomeKind.cancelled, revision: 1),
      );
    });
  }, timeout: const Timeout.factor(1));

  testWidgets('VUI3b locale rebuild translates without extending the notice', (
    tester,
  ) async {
    final capability = _Capability(_projection());
    await _withOverlay(tester, capability, () async {
      await _show(
        tester,
        capability,
        _outcome(MediaSwitchOutcomeKind.declined),
      );
      await tester.pump(const Duration(milliseconds: 2500));
      await tester.pumpWidget(_app(capability, locale: 'ar'));
      await tester.pump();
      final text = lookupAppLocalizations(const Locale('ar'))
          .call_video_request_declined;
      expect(find.text(text), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text(text), findsNothing);
    });
  }, timeout: const Timeout.factor(1));

  testWidgets('VUI3b an old expiry cannot clear a newer outcome', (
    tester,
  ) async {
    final capability = _Capability(_projection());
    await _withOverlay(tester, capability, () async {
      await _show(
        tester,
        capability,
        _outcome(MediaSwitchOutcomeKind.declined),
      );
      await tester.pump(const Duration(milliseconds: 2500));
      capability.emit(_projection(outgoing: 'upgrade-2'));
      await tester.pump();
      await _show(
        tester,
        capability,
        _outcome(MediaSwitchOutcomeKind.cancelled, id: 'upgrade-2'),
      );
      final text = lookupAppLocalizations(const Locale('en'))
          .call_video_request_cancelled;
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text(text), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 2499));
      expect(find.text(text), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text(text), findsNothing);
    });
  }, timeout: const Timeout.factor(1));

  testWidgets(
    'VUI3b Arabic 320px 2x notice preserves full text and audio actions',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final capability = _Capability(_projection());
      await _withOverlay(
        tester,
        capability,
        () async {
          final outcome = _outcome(MediaSwitchOutcomeKind.cancelled);
          await _show(tester, capability, outcome, locale: 'ar');
          final finder = find.text(
            lookupAppLocalizations(const Locale('ar'))
                .call_video_request_cancelled,
          );
          await tester.ensureVisible(finder);
          await tester.pump();
          final paragraph = tester.renderObject<RenderParagraph>(finder);
          expect(paragraph.didExceedMaxLines, isFalse);
          expect(paragraph.textDirection, TextDirection.rtl);
          final bounds = tester.getRect(finder);
          expect(bounds.left, greaterThanOrEqualTo(0));
          expect(bounds.right, lessThanOrEqualTo(320));
          for (final action in ['mute', 'speaker', 'end']) {
            final control = find.bySemanticsIdentifier('call_$action');
            expect(control, findsOneWidget);
            await tester.ensureVisible(control);
            await tester.pump();
            tester.semantics.tap(
              find.semantics.byPredicate(
                (node) => node.getSemanticsData().identifier == 'call_$action',
              ),
            );
            await tester.pump();
          }
          expect(capability.audioCalls, ['mute', 'speaker', 'end']);
          expect(capability.videoCalls, isEmpty);
          expect(tester.takeException(), isNull);
        },
        locale: 'ar',
        scale: 2,
      );
    },
    timeout: const Timeout.factor(1),
  );
}
