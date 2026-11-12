import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/call/domain/call_media.dart';
import 'package:flutter_app/features/call/presentation/call_video_localizations.dart';
import 'package:flutter_app/features/call/presentation/call_video_presentation.dart';
import 'package:flutter_app/features/call/presentation/widgets/call_video_controls.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// Exact approved wording: m-e4759c69, m-a1fb19fc; 23-key count m-c578935a.
const approved = <String, Map<String, String>>{
  "en": {
    "videoRequested": "Video requested",
    "audioOnly": "Audio only",
    "video": "Video call",
    "incomingUpgrade": "They want to turn on video",
    "outgoingUpgrade": "Waiting for them to accept",
    "switchingToVideo": "Switching to video",
    "switchingToAudio": "Switching to audio",
    "reconnecting": "Reconnecting",
    "localCameraOn": "Your camera is on",
    "localCameraOff": "Your camera is off",
    "localCameraPaused": "Your camera is paused",
    "remoteCameraOn": "Their camera is on",
    "remoteCameraOff": "Their camera is off",
    "remoteCameraPaused": "Their camera is paused",
    "requestVideo": "Request video",
    "acceptUpgrade": "Accept video",
    "declineUpgrade": "Keep audio",
    "cancelUpgrade": "Cancel request",
    "turnCameraOn": "Turn camera on",
    "turnCameraOff": "Turn camera off",
    "switchCamera": "Switch camera",
    "useAudioOnly": "Use audio only",
    "controlsLabel": "Video controls",
  },
  "de": {
    "videoRequested": "Video angefragt",
    "audioOnly": "Nur Audio",
    "video": "Videoanruf",
    "incomingUpgrade": "Dein Gegenüber möchte Video einschalten",
    "outgoingUpgrade": "Warten, bis dein Gegenüber zustimmt",
    "switchingToVideo": "Wechsel zu Video",
    "switchingToAudio": "Wechsel zu Audio",
    "reconnecting": "Verbindung wird wiederhergestellt",
    "localCameraOn": "Deine Kamera ist an",
    "localCameraOff": "Deine Kamera ist aus",
    "localCameraPaused": "Deine Kamera ist pausiert",
    "remoteCameraOn": "Die Kamera deines Gegenübers ist an",
    "remoteCameraOff": "Die Kamera deines Gegenübers ist aus",
    "remoteCameraPaused": "Die Kamera deines Gegenübers ist pausiert",
    "requestVideo": "Video anfragen",
    "acceptUpgrade": "Video annehmen",
    "declineUpgrade": "Bei Audio bleiben",
    "cancelUpgrade": "Anfrage abbrechen",
    "turnCameraOn": "Kamera einschalten",
    "turnCameraOff": "Kamera ausschalten",
    "switchCamera": "Kamera wechseln",
    "useAudioOnly": "Nur Audio verwenden",
    "controlsLabel": "Videosteuerung",
  },
  "ar": {
    "videoRequested": "تم طلب الفيديو",
    "audioOnly": "صوت فقط",
    "video": "مكالمة فيديو",
    "incomingUpgrade": "الطرف الآخر يريد تشغيل الفيديو",
    "outgoingUpgrade": "بانتظار قبول الطرف الآخر",
    "switchingToVideo": "جارٍ التبديل إلى الفيديو",
    "switchingToAudio": "جارٍ التبديل إلى الصوت",
    "reconnecting": "جارٍ إعادة الاتصال",
    "localCameraOn": "كاميرتك قيد التشغيل",
    "localCameraOff": "كاميرتك متوقفة",
    "localCameraPaused": "كاميرتك متوقفة مؤقتًا",
    "remoteCameraOn": "كاميرا الطرف الآخر قيد التشغيل",
    "remoteCameraOff": "كاميرا الطرف الآخر متوقفة",
    "remoteCameraPaused": "كاميرا الطرف الآخر متوقفة مؤقتًا",
    "requestVideo": "طلب الفيديو",
    "acceptUpgrade": "قبول الفيديو",
    "declineUpgrade": "الاستمرار بالصوت فقط",
    "cancelUpgrade": "إلغاء الطلب",
    "turnCameraOn": "تشغيل الكاميرا",
    "turnCameraOff": "إيقاف الكاميرا",
    "switchCamera": "تبديل الكاميرا",
    "useAudioOnly": "استخدام الصوت فقط",
    "controlsLabel": "عناصر التحكم بالفيديو",
  },
};

final getters = <String, String Function(AppLocalizations)>{
  "videoRequested": (l10n) => l10n.call_video_status_video_requested,
  "audioOnly": (l10n) => l10n.call_video_status_audio_only,
  "video": (l10n) => l10n.call_video_status_video,
  "incomingUpgrade": (l10n) => l10n.call_video_status_incoming_upgrade,
  "outgoingUpgrade": (l10n) => l10n.call_video_status_outgoing_upgrade,
  "switchingToVideo": (l10n) => l10n.call_video_status_switching_to_video,
  "switchingToAudio": (l10n) => l10n.call_video_status_switching_to_audio,
  "reconnecting": (l10n) => l10n.call_video_status_reconnecting,
  "localCameraOn": (l10n) => l10n.call_video_local_camera_on,
  "localCameraOff": (l10n) => l10n.call_video_local_camera_off,
  "localCameraPaused": (l10n) => l10n.call_video_local_camera_paused,
  "remoteCameraOn": (l10n) => l10n.call_video_remote_camera_on,
  "remoteCameraOff": (l10n) => l10n.call_video_remote_camera_off,
  "remoteCameraPaused": (l10n) => l10n.call_video_remote_camera_paused,
  "requestVideo": (l10n) => l10n.call_video_action_request_video,
  "acceptUpgrade": (l10n) => l10n.call_video_action_accept_upgrade,
  "declineUpgrade": (l10n) => l10n.call_video_action_decline_upgrade,
  "cancelUpgrade": (l10n) => l10n.call_video_action_cancel_upgrade,
  "turnCameraOn": (l10n) => l10n.call_video_action_turn_camera_on,
  "turnCameraOff": (l10n) => l10n.call_video_action_turn_camera_off,
  "switchCamera": (l10n) => l10n.call_video_action_switch_camera,
  "useAudioOnly": (l10n) => l10n.call_video_action_use_audio_only,
  "controlsLabel": (l10n) => l10n.call_video_controls_label,
};

Map<String, String> mapped(CallVideoLocalizations copy) => {
  'controlsLabel': copy.controlsLabel,
  for (final status in CallVideoStatus.values)
    status.name: copy.statusLabel(status),
  for (final action in CallVideoAction.values)
    action.name: copy.actionLabel(action),
  'localCameraOn': copy.localCameraLabel(CallCameraState.on),
  'localCameraOff': copy.localCameraLabel(CallCameraState.off),
  'localCameraPaused': copy.localCameraLabel(CallCameraState.paused),
  'remoteCameraOn': copy.remoteCameraLabel(CallCameraState.on),
  'remoteCameraOff': copy.remoteCameraLabel(CallCameraState.off),
  'remoteCameraPaused': copy.remoteCameraLabel(CallCameraState.paused),
};

Widget localizedControls(
  String locale, {
  required List<CallVideoIntent> intents,
  required VoidCallback onEnd,
  bool enabled = true,
}) => MaterialApp(
  locale: Locale(locale),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: BackgroundReadableColors.dark.surfaceSubtle,
    extensions: const <ThemeExtension<dynamic>>[BackgroundReadableColors.dark],
  ),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)),
    child: child!,
  ),
  home: Builder(
    builder: (context) {
      final l10n = AppLocalizations.of(context)!;
      final copy = CallVideoLocalizations(l10n);
      return Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: CallVideoControls(
            presentation: CallVideoPresentation.project(
              videoEnabled: enabled,
              wireVersion: CallWireVersion.v2,
              requestedMedia: CallMediaKind.video,
              acceptedMedia: CallMediaKind.video,
              agreedMedia: CallMediaKind.video,
              localCamera: CallCameraState.on,
              remoteCamera: CallCameraState.paused,
              isConnected: true,
              maySwitchCamera: true,
            ),
            controlsLabel: copy.controlsLabel,
            statusLabel: copy.statusLabel,
            localCameraLabel: copy.localCameraLabel,
            remoteCameraLabel: copy.remoteCameraLabel,
            actionLabel: copy.actionLabel,
            onIntent: intents.add,
            audioControls: Wrap(
              children: [
                TextButton(
                  key: const ValueKey('localized-audio-end'),
                  onPressed: onEnd,
                  child: Text(l10n.call_end_action),
                ),
              ],
            ),
          ),
        ),
      );
    },
  ),
);

void setViewport(WidgetTester tester, double width) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 780);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

void main() {
  for (final language in ['en', 'de', 'ar']) {
    for (final entry in getters.entries) {
      test('U6L $language ${entry.key} exact approved text', () {
        final l10n = lookupAppLocalizations(Locale(language));
        expect(entry.value(l10n), approved[language]![entry.key]);
      });
    }

    test('U6L $language maps every injected presentation label', () {
      final l10n = lookupAppLocalizations(Locale(language));
      expect(getters.keys, unorderedEquals(approved[language]!.keys));
      expect(mapped(CallVideoLocalizations(l10n)), approved[language]);
    });

    for (final width in [320.0, 360.0]) {
      testWidgets('U6L $language $width real localized controls at 2x', (
        tester,
      ) async {
        setViewport(tester, width);
        final semantics = tester.ensureSemantics();
        try {
          var ended = 0;
          final intents = <CallVideoIntent>[];
          await tester.pumpWidget(
            localizedControls(language, intents: intents, onEnd: () => ended++),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final expected = approved[language]!;
          expect(find.text(expected['video']!), findsOneWidget);
          for (final entry in {
            'call_video_status': expected['video']!,
            'call_video_local_camera': expected['localCameraOn']!,
            'call_video_remote_camera': expected['remoteCameraPaused']!,
          }.entries) {
            final node = tester.getSemantics(
              find.bySemanticsIdentifier(entry.key),
            );
            expect(node.label, entry.value);
          }
          for (final action in [
            CallVideoAction.turnCameraOff,
            CallVideoAction.switchCamera,
            CallVideoAction.useAudioOnly,
          ]) {
            final button = find.byKey(ValueKey(action.identifier));
            await tester.ensureVisible(button);
            await tester.pump();
            final bounds = tester.getRect(button);
            expect(bounds.left, greaterThanOrEqualTo(12));
            expect(bounds.right, lessThanOrEqualTo(width - 12));
            expect(bounds.width, greaterThanOrEqualTo(48));
            expect(bounds.height, greaterThanOrEqualTo(48));
            final label = find.text(expected[action.name]!);
            final labelBounds = tester.getRect(label);
            expect(labelBounds.width, greaterThan(0));
            expect(labelBounds.left, greaterThanOrEqualTo(bounds.left));
            expect(labelBounds.right, lessThanOrEqualTo(bounds.right));
            final paragraph = tester.renderObject<RenderParagraph>(label);
            if (paragraph.didExceedMaxLines) {
              expect(paragraph.overflow, TextOverflow.ellipsis);
            }
            expect(
              Directionality.of(tester.element(button)),
              language == 'ar' ? TextDirection.rtl : TextDirection.ltr,
            );
            expect(tester.takeException(), isNull);
          }
          final off = find.byKey(const ValueKey('call_video_camera_off'));
          await tester.ensureVisible(off);
          await tester.tap(off);
          expect(intents.single.action, CallVideoAction.turnCameraOff);
          final end = find.byKey(const ValueKey('localized-audio-end'));
          await tester.ensureVisible(end);
          await tester.tap(end);
          expect(ended, 1);
        } finally {
          semantics.dispose();
        }
      });
    }
  }

  testWidgets(
    'U6L default-off preserves audio with no localized video surface',
    (tester) async {
      var ended = 0;
      final intents = <CallVideoIntent>[];
      await tester.pumpWidget(
        localizedControls(
          'en',
          enabled: false,
          intents: intents,
          onEnd: () => ended++,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('call_video_status')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('localized-audio-end')));
      expect(ended, 1);
      expect(intents, isEmpty);
    },
  );

  testWidgets('U6L live locale changes refresh labels without screen wiring', (
    tester,
  ) async {
    for (final language in ['en', 'de', 'ar']) {
      await tester.pumpWidget(
        localizedControls(language, intents: <CallVideoIntent>[], onEnd: () {}),
      );
      await tester.pumpAndSettle();
      expect(find.text(approved[language]!['video']!), findsOneWidget);
      expect(find.text(approved[language]!['localCameraOn']!), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
