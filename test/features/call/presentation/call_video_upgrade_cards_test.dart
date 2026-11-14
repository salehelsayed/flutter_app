import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/domain/call_media.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/presentation/call_video_presentation.dart';
import 'package:flutter_app/features/call/presentation/screens/active_call_screen.dart';
import 'package:flutter_app/features/call/presentation/widgets/call_controls.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

CallVideoPresentation _video({
  CallMediaKind? accepted = CallMediaKind.video,
  CallMediaKind agreed = CallMediaKind.audio,
  String? incoming,
  String? outgoing,
  CallMediaKind? switching,
  CallCameraState local = CallCameraState.off,
  CallCameraState remote = CallCameraState.off,
  bool pending = false,
  bool connected = true,
  bool reconnecting = false,
  bool visible = true,
}) => CallVideoPresentation.project(
  videoEnabled: visible,
  wireVersion: CallWireVersion.v2,
  requestedMedia: CallMediaKind.video,
  acceptedMedia: accepted,
  agreedMedia: agreed,
  incomingUpgradeId: incoming,
  outgoingUpgradeId: outgoing,
  switchingTo: switching,
  localCamera: local,
  remoteCamera: remote,
  videoActionPending: pending,
  isConnected: connected,
  isReconnecting: reconnecting,
  mayRequestVideo: true,
  mayTurnCameraOn: true,
  maySwitchCamera: true,
);

// Record all intents without fake ownership guards. Native capture and stale
// overlay-owner refusal remain covered by their existing causal suites.
class _Fixture {
  final intents = <CallVideoIntent>[];
  final audio = <String>[];

  Future<void> pump(
    WidgetTester tester,
    CallVideoPresentation video, {
    String name = 'Layla',
    String locale = 'en',
    double scale = 1,
  }) async {
    await tester.pumpWidget(
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
        home: Scaffold(
          body: ActiveCallScreen(
            contactPeerId: 'peer-layla',
            contactUsername: name,
            state: video.isReconnecting
                ? CallState.reconnecting
                : CallState.connected,
            connectedAt: null,
            now: () => DateTime.utc(2026, 11, 14),
            videoPresentation: video,
            onVideoIntent: intents.add,
            controls: CallControls(
              constrainLabels: true,
              isMuted: false,
              isMuteAvailable: true,
              isSpeakerOn: false,
              isSpeakerAvailable: true,
              selectedRoute: CallAudioOutputRoute.systemDefault,
              audioStatusMessage: null,
              muteUnavailableMessage: '',
              speakerUnavailableMessage: '',
              onMute: () => audio.add('mute'),
              onSpeaker: () => audio.add('speaker'),
              onEnd: () => audio.add('end'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}

void _prepare(WidgetTester tester, {double width = 400}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> _captionTap(WidgetTester tester, String caption) async {
  final finder = find.text(caption);
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.pump();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pump();
}

void _expectIntents(
  _Fixture fixture,
  List<(CallVideoAction, String?)> expected,
) {
  expect(
    fixture.intents.map((intent) => (intent.action, intent.upgradeId)).toList(),
    expected,
  );
}

String _heading(String locale, String name) => switch (locale) {
  'de' => '$name möchte das Video einschalten',
  'ar' => 'طلب تشغيل الفيديو من $name',
  _ => '$name wants to turn on video',
};

void main() {
  for (final locale in ['en', 'de', 'ar']) {
    testWidgets(
      'incoming named consent $locale preserves current request identity',
      (tester) async {
        _prepare(tester);
        final fixture = _Fixture();
        final l10n = lookupAppLocalizations(Locale(locale));
        // Answer history was video; current agreement is audio.
        await fixture.pump(tester, _video(incoming: 'in-1'), locale: locale);
        expect(find.text(_heading(locale, 'Layla')), findsOneWidget);
        await _captionTap(tester, l10n.call_video_action_accept_upgrade);
        _expectIntents(fixture, [(CallVideoAction.acceptUpgrade, 'in-1')]);
        await fixture.pump(
          tester,
          _video(accepted: CallMediaKind.audio, incoming: 'in-2'),
          locale: locale,
        );
        expect(find.text(_heading(locale, 'Layla')), findsOneWidget);
        await _captionTap(tester, l10n.mic_perm_not_now);
        _expectIntents(fixture, [
          (CallVideoAction.acceptUpgrade, 'in-1'),
          (CallVideoAction.declineUpgrade, 'in-2'),
        ]);
      },
    );
  }

  testWidgets('outgoing named waiting cancels the current outgoing ID', (
    tester,
  ) async {
    _prepare(tester);
    final fixture = _Fixture();
    final l10n = lookupAppLocalizations(const Locale('en'));
    await fixture.pump(tester, _video(outgoing: 'out-1'));
    expect(
      find.text(l10n.call_video_waiting_for_acceptance('Layla')),
      findsOneWidget,
    );
    await _captionTap(tester, l10n.call_video_action_cancel_upgrade);
    await fixture.pump(tester, _video(outgoing: 'out-2'), name: 'Sam');
    expect(
      find.text(l10n.call_video_waiting_for_acceptance('Sam')),
      findsOneWidget,
    );
    await _captionTap(tester, l10n.call_video_action_cancel_upgrade);
    _expectIntents(fixture, [
      (CallVideoAction.cancelUpgrade, 'out-1'),
      (CallVideoAction.cancelUpgrade, 'out-2'),
    ]);
  });

  testWidgets(
    'incoming wins simultaneous IDs and pending disables acceptance',
    (tester) async {
      _prepare(tester);
      final fixture = _Fixture();
      final l10n = lookupAppLocalizations(const Locale('en'));
      await fixture.pump(tester, _video(incoming: 'in-1', outgoing: 'out-1'));
      expect(find.text(_heading('en', 'Layla')), findsOneWidget);
      expect(
        find.text(l10n.call_video_waiting_for_acceptance('Layla')),
        findsNothing,
      );
      expect(find.text(l10n.call_video_action_cancel_upgrade), findsNothing);
      await _captionTap(tester, l10n.call_video_action_accept_upgrade);
      _expectIntents(fixture, [(CallVideoAction.acceptUpgrade, 'in-1')]);
      await fixture.pump(tester, _video(incoming: 'in-2', pending: true));
      expect(find.text(_heading('en', 'Layla')), findsOneWidget);
      await _captionTap(tester, l10n.call_video_action_accept_upgrade);
      _expectIntents(fixture, [(CallVideoAction.acceptUpgrade, 'in-1')]);
    },
  );

  testWidgets('acceptance emits agreement only and later Camera is separate', (
    tester,
  ) async {
    _prepare(tester);
    final fixture = _Fixture();
    final l10n = lookupAppLocalizations(const Locale('en'));
    await fixture.pump(tester, _video(incoming: 'in-1'));
    expect(find.text(_heading('en', 'Layla')), findsOneWidget);
    await _captionTap(tester, l10n.call_video_action_accept_upgrade);
    await fixture.pump(tester, _video(agreed: CallMediaKind.video));
    _expectIntents(fixture, [(CallVideoAction.acceptUpgrade, 'in-1')]);
    await _captionTap(tester, l10n.call_video_camera_caption);
    _expectIntents(fixture, [
      (CallVideoAction.acceptUpgrade, 'in-1'),
      (CallVideoAction.turnCameraOn, null),
    ]);
  });

  for (final pending in [false, true]) {
    testWidgets('agreement switching pending=$pending is not camera startup', (
      tester,
    ) async {
      _prepare(tester);
      final fixture = _Fixture();
      final l10n = lookupAppLocalizations(const Locale('en'));
      await fixture.pump(
        tester,
        _video(switching: CallMediaKind.video, pending: pending),
      );
      expect(find.text(l10n.call_video_switching), findsOneWidget);
      expect(find.text(l10n.call_video_camera_starting), findsNothing);
      expect(fixture.intents, isEmpty);
    });
  }

  for (final local in [CallCameraState.off, CallCameraState.paused]) {
    testWidgets('settled video $local pending shows generic camera work', (
      tester,
    ) async {
      _prepare(tester);
      final fixture = _Fixture();
      final l10n = lookupAppLocalizations(const Locale('en'));
      await fixture.pump(
        tester,
        _video(agreed: CallMediaKind.video, local: local, pending: true),
      );
      expect(find.text(l10n.call_video_camera_starting), findsOneWidget);
      expect(find.text(l10n.call_video_switching), findsNothing);
      expect(fixture.intents, isEmpty);
    });
  }

  final exclusions = <String, CallVideoPresentation>{
    'already on': _video(
      agreed: CallMediaKind.video,
      local: CallCameraState.on,
      pending: true,
    ),
    'not pending': _video(agreed: CallMediaKind.video),
    'disconnected': _video(
      agreed: CallMediaKind.video,
      pending: true,
      connected: false,
    ),
    'reconnecting': _video(
      agreed: CallMediaKind.video,
      pending: true,
      reconnecting: true,
    ),
    'switching audio': _video(
      agreed: CallMediaKind.video,
      pending: true,
      switching: CallMediaKind.audio,
    ),
    'pre-answer': _video(
      accepted: null,
      agreed: CallMediaKind.video,
      pending: true,
    ),
    'invisible': _video(
      agreed: CallMediaKind.video,
      pending: true,
      visible: false,
    ),
    'audio agreement': _video(pending: true),
  };
  for (final row in exclusions.entries) {
    testWidgets('camera progress excluded when ${row.key}', (tester) async {
      _prepare(tester);
      final fixture = _Fixture();
      await fixture.pump(tester, row.value);
      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(find.text(l10n.call_video_camera_starting), findsNothing);
      expect(fixture.intents, isEmpty);
    });
  }

  for (final remote in [CallCameraState.off, CallCameraState.paused]) {
    testWidgets('remote $remote keeps truthful fallback without waiting copy', (
      tester,
    ) async {
      _prepare(tester);
      final fixture = _Fixture();
      final l10n = lookupAppLocalizations(const Locale('en'));
      await fixture.pump(
        tester,
        _video(agreed: CallMediaKind.video, remote: remote),
      );
      expect(
        find.text(
          remote == CallCameraState.off
              ? l10n.call_video_remote_camera_off
              : l10n.call_video_remote_camera_paused,
        ),
        findsWidgets,
      );
      expect(
        find.text(l10n.call_video_waiting_for_remote('Layla')),
        findsNothing,
      );
    });
  }

  testWidgets(
    'Arabic incoming 320px 2x keeps full captions and audio reachable',
    (tester) async {
      _prepare(tester, width: 320);
      final fixture = _Fixture();
      final l10n = lookupAppLocalizations(const Locale('ar'));
      const name = 'ليلى صاحبة الاسم الطويل للاختبار';
      await fixture.pump(
        tester,
        _video(incoming: 'rtl-1'),
        name: name,
        locale: 'ar',
        scale: 2,
      );
      expect(find.text(_heading('ar', name)), findsOneWidget);
      for (final text in [
        _heading('ar', name),
        l10n.call_video_action_accept_upgrade,
        l10n.mic_perm_not_now,
      ]) {
        final finder = find.text(text);
        expect(finder, findsOneWidget);
        await tester.ensureVisible(finder);
        await tester.pump();
        final paragraph = tester.renderObject<RenderParagraph>(finder);
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(paragraph.textDirection, TextDirection.rtl);
        final rect = tester.getRect(finder);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(320));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.bottom, lessThanOrEqualTo(900));
      }
      await _captionTap(tester, l10n.call_video_action_accept_upgrade);
      _expectIntents(fixture, [(CallVideoAction.acceptUpgrade, 'rtl-1')]);
      final acceptNode = find.semantics.byPredicate(
        (node) =>
            node.getSemanticsData().identifier == 'call_video_accept_upgrade',
      );
      expect(acceptNode, findsOneWidget);
      tester.semantics.tap(acceptNode);
      await tester.pump();
      _expectIntents(fixture, [
        (CallVideoAction.acceptUpgrade, 'rtl-1'),
        (CallVideoAction.acceptUpgrade, 'rtl-1'),
      ]);
      for (final action in ['mute', 'speaker', 'end']) {
        final finder = find.bySemanticsIdentifier('call_$action');
        expect(finder, findsOneWidget);
        await tester.ensureVisible(finder);
        await tester.pump();
        tester.semantics.tap(
          find.semantics.byPredicate(
            (node) => node.getSemanticsData().identifier == 'call_$action',
          ),
        );
        await tester.pump();
      }
      expect(fixture.audio, ['mute', 'speaker', 'end']);
      expect(tester.takeException(), isNull);
    },
  );
}
