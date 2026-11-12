import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/call/domain/call_media.dart';
import 'package:flutter_app/features/call/presentation/call_video_presentation.dart';
import 'package:flutter_app/features/call/presentation/widgets/call_video_controls.dart';
import 'package:flutter_test/flutter_test.dart';

// Kayan approved wording m-e4759c69 / m-a1fb19fc. Test fixtures only:
// product bindings and ARB additions belong to the separate localization unit.
const english = <String, String>{
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
};

const german = <String, String>{
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
};

const arabic = <String, String>{
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
};

CallVideoPresentation view({
  bool audio = false,
  CallCameraState local = CallCameraState.off,
  CallCameraState remote = CallCameraState.off,
  bool busy = false,
  bool reconnecting = false,
  String? incoming,
  String? outgoing,
  bool mayTurnCameraOn = true,
}) => CallVideoPresentation.project(
  videoEnabled: true,
  wireVersion: CallWireVersion.v2,
  requestedMedia: audio ? CallMediaKind.audio : CallMediaKind.video,
  acceptedMedia: audio ? CallMediaKind.audio : CallMediaKind.video,
  agreedMedia: audio ? CallMediaKind.audio : CallMediaKind.video,
  localCamera: local,
  remoteCamera: remote,
  isConnected: true,
  isReconnecting: reconnecting,
  videoActionPending: busy,
  incomingUpgradeId: incoming,
  outgoingUpgradeId: outgoing,
  mayRequestVideo: true,
  mayTurnCameraOn: mayTurnCameraOn,
  maySwitchCamera: true,
);

Widget audioControls(List<int> calls) => Wrap(
  spacing: 8,
  children: [
    for (final entry in const [
      ('call_mute', 'Mute'),
      ('call_speaker', 'Audio output'),
      ('call_end', 'End call'),
    ].indexed)
      Semantics(
        identifier: entry.$2.$1,
        button: true,
        label: entry.$2.$2,
        onTap: () => calls[entry.$1]++,
        excludeSemantics: true,
        child: TextButton(
          key: ValueKey(entry.$2.$1),
          onPressed: () => calls[entry.$1]++,
          child: Text(entry.$2.$2),
        ),
      ),
  ],
);

String cameraLabel(
  Map<String, String> copy,
  CallCameraState state,
  bool local,
) {
  final suffix = switch (state) {
    CallCameraState.on => 'On',
    CallCameraState.off => 'Off',
    CallCameraState.paused => 'Paused',
  };
  return copy['${local ? 'local' : 'remote'}Camera$suffix']!;
}

Widget controls(
  CallVideoPresentation presentation,
  List<int> audio, {
  ValueChanged<CallVideoIntent>? onIntent,
  Map<String, String> copy = english,
}) => CallVideoControls(
  presentation: presentation,
  audioControls: audioControls(audio),
  onIntent: onIntent ?? (_) {},
  controlsLabel: copy['controlsLabel']!,
  statusLabel: (status) => copy[status.name]!,
  localCameraLabel: (state) => cameraLabel(copy, state, true),
  remoteCameraLabel: (state) => cameraLabel(copy, state, false),
  actionLabel: (action) => copy[action.name]!,
);

Widget wrap(
  Widget child, {
  TextDirection direction = TextDirection.ltr,
  double scale = 1,
  BackgroundReadableColors colors = BackgroundReadableColors.dark,
}) => MaterialApp(
  theme: ThemeData(
    scaffoldBackgroundColor: colors.surfaceSubtle,
    extensions: <ThemeExtension<dynamic>>[colors],
  ),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: Directionality(textDirection: direction, child: child!),
  ),
  home: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: child,
    ),
  ),
);

void compactView(WidgetTester tester, double width) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 780);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

void main() {
  testWidgets(
    'default-off presentation keeps only independent audio controls',
    (tester) async {
      final audio = [0, 0, 0];
      await tester.pumpWidget(
        wrap(
          controls(
            const CallVideoPresentation.project(
              wireVersion: CallWireVersion.v2,
              requestedMedia: CallMediaKind.video,
              acceptedMedia: CallMediaKind.video,
              agreedMedia: CallMediaKind.video,
              localCamera: CallCameraState.on,
              isConnected: true,
              mayTurnCameraOn: true,
            ),
            audio,
          ),
        ),
      );
      expect(find.byKey(const ValueKey('call_video_status')), findsNothing);
      for (final action in CallVideoAction.values) {
        expect(find.byKey(ValueKey(action.identifier)), findsNothing);
      }
      for (final id in ['call_mute', 'call_speaker', 'call_end']) {
        await tester.tap(find.byKey(ValueKey(id)));
      }
      expect(audio, [1, 1, 1]);
    },
  );

  testWidgets(
    'U6 causal enabled request emits intent without changing agreement',
    (tester) async {
      final model = view(audio: true);
      final events = <CallVideoIntent>[];
      await tester.pumpWidget(
        wrap(controls(model, [0, 0, 0], onIntent: events.add)),
      );
      expect(find.byKey(const ValueKey('call_mute')), findsOneWidget);
      final button = find.byKey(const ValueKey('call_video_request_video'));
      expect(button, findsOneWidget);
      await tester.tap(button);
      expect(events, hasLength(1));
      expect(events.single.action, CallVideoAction.requestVideo);
      expect(events.single.upgradeId, isNull);
      expect(model.agreedMedia, CallMediaKind.audio);
      expect(model.localCamera, CallCameraState.off);
    },
  );

  testWidgets('camera-on is only an intent, never optimistic capture', (
    tester,
  ) async {
    final model = view();
    final events = <CallVideoIntent>[];
    await tester.pumpWidget(
      wrap(controls(model, [0, 0, 0], onIntent: events.add)),
    );
    await tester.tap(find.byKey(const ValueKey('call_video_camera_on')));
    expect(events, hasLength(1));
    expect(events.single.action, CallVideoAction.turnCameraOn);
    expect(model.localCamera, CallCameraState.off);
    expect(find.text('Your camera is off'), findsOneWidget);
  });

  testWidgets(
    'incoming decision targets current request, not outgoing history',
    (tester) async {
      final model = view(
        audio: true,
        incoming: 'incoming-current',
        outgoing: 'abandoned-outgoing',
      );
      final events = <CallVideoIntent>[];
      await tester.pumpWidget(
        wrap(controls(model, [0, 0, 0], onIntent: events.add)),
      );
      expect(find.text('They want to turn on video'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('call_video_cancel_upgrade')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('call_video_accept_upgrade')));
      expect(events, hasLength(1));
      expect(events.single.action, CallVideoAction.acceptUpgrade);
      expect(events.single.upgradeId, 'incoming-current');
      expect(model.agreedMedia, CallMediaKind.audio);
      expect(model.localCamera, CallCameraState.off);
    },
  );

  testWidgets('parent pending projection disables a repeated request', (
    tester,
  ) async {
    var busy = false;
    var requests = 0;
    await tester.pumpWidget(
      wrap(
        StatefulBuilder(
          builder: (context, setState) {
            return controls(
              view(audio: true, busy: busy),
              [0, 0, 0],
              onIntent: (_) => setState(() {
                requests++;
                busy = true;
              }),
            );
          },
        ),
      ),
    );
    final request = find.byKey(const ValueKey('call_video_request_video'));
    await tester.tap(request);
    await tester.pump();
    await tester.tap(request);
    expect(requests, 1);
  });

  testWidgets(
    'busy reconnect retains safety controls and all audio callbacks',
    (tester) async {
      final audio = [0, 0, 0];
      final events = <CallVideoIntent>[];
      await tester.pumpWidget(
        wrap(
          controls(
            view(local: CallCameraState.on, busy: true, reconnecting: true),
            audio,
            onIntent: events.add,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('call_video_switch_camera')));
      expect(events, isEmpty);
      await tester.tap(find.byKey(const ValueKey('call_video_camera_off')));
      await tester.tap(find.byKey(const ValueKey('call_video_audio_only')));
      expect(events.map((event) => event.action), [
        CallVideoAction.turnCameraOff,
        CallVideoAction.useAudioOnly,
      ]);
      for (final id in ['call_mute', 'call_speaker', 'call_end']) {
        await tester.tap(find.byKey(ValueKey(id)));
      }
      expect(audio, [1, 1, 1]);
    },
  );

  testWidgets('unavailable camera does not disable audio or hang-up', (
    tester,
  ) async {
    final audio = [0, 0, 0];
    final events = <CallVideoIntent>[];
    await tester.pumpWidget(
      wrap(controls(view(mayTurnCameraOn: false), audio, onIntent: events.add)),
    );
    await tester.tap(find.byKey(const ValueKey('call_video_camera_on')));
    expect(events, isEmpty);
    for (final id in ['call_mute', 'call_speaker', 'call_end']) {
      await tester.tap(find.byKey(ValueKey(id)));
    }
    expect(audio, [1, 1, 1]);
  });

  testWidgets('status and both camera states are separate accessible nodes', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final events = <CallVideoIntent>[];
      await tester.pumpWidget(
        wrap(
          controls(
            view(local: CallCameraState.paused, remote: CallCameraState.on),
            [0, 0, 0],
            onIntent: events.add,
          ),
        ),
      );
      for (final entry in const {
        'call_video_status': 'Video call',
        'call_video_local_camera': 'Your camera is paused',
        'call_video_remote_camera': 'Their camera is on',
      }.entries) {
        final finder = find.bySemanticsIdentifier(entry.key);
        expect(finder, findsOneWidget);
        final node = tester.getSemantics(finder);
        expect(node.identifier, entry.key);
        expect(node.label, entry.value);
      }
      final off = find.bySemanticsIdentifier('call_video_camera_off');
      expect(
        tester.getSemantics(off).getSemanticsData().flagsCollection.isButton,
        isTrue,
      );
      tester.semantics.performAction(
        find.semantics.byPredicate(
          (node) => node.identifier == 'call_video_camera_off',
        ),
        SemanticsAction.tap,
      );
      expect(events.single.action, CallVideoAction.turnCameraOff);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('sending a decision removes accessible repeat actions only', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        wrap(
          controls(view(audio: true, incoming: 'current', busy: true), [
            0,
            0,
            0,
          ]),
        ),
      );
      for (final id in [
        'call_video_accept_upgrade',
        'call_video_decline_upgrade',
      ]) {
        final node = tester.getSemantics(find.bySemanticsIdentifier(id));
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      }
      for (final id in [
        'call_video_audio_only',
        'call_mute',
        'call_speaker',
        'call_end',
      ]) {
        final node = tester.getSemantics(find.bySemanticsIdentifier(id));
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      }
    } finally {
      semantics.dispose();
    }
  });

  for (final action in [
    CallVideoAction.cancelUpgrade,
    CallVideoAction.declineUpgrade,
    CallVideoAction.switchCamera,
  ]) {
    testWidgets('${action.name} emits only its projected intent', (
      tester,
    ) async {
      final events = <CallVideoIntent>[];
      final model = switch (action) {
        CallVideoAction.cancelUpgrade => view(audio: true, outgoing: 'current'),
        CallVideoAction.declineUpgrade => view(
          audio: true,
          incoming: 'current',
        ),
        _ => view(local: CallCameraState.on),
      };
      await tester.pumpWidget(
        wrap(controls(model, [0, 0, 0], onIntent: events.add)),
      );
      await tester.tap(find.byKey(ValueKey(action.identifier)));
      expect(events, hasLength(1));
      expect(events.single.action, action);
      expect(
        events.single.upgradeId,
        action == CallVideoAction.switchCamera ? null : 'current',
      );
    });
  }

  for (final language in ['en', 'de', 'ar']) {
    for (final width in [320.0, 360.0]) {
      testWidgets('$language $width compact controls fit at 2x text', (
        tester,
      ) async {
        compactView(tester, width);
        final copy = switch (language) {
          'ar' => arabic,
          'de' => german,
          _ => english,
        };
        final audio = [0, 0, 0];
        await tester.pumpWidget(
          wrap(
            controls(
              view(local: CallCameraState.on, remote: CallCameraState.paused),
              audio,
              copy: copy,
            ),
            scale: 2,
            direction: language == 'ar' ? TextDirection.rtl : TextDirection.ltr,
            colors: language == 'de'
                ? BackgroundReadableColors.representativeLight
                : BackgroundReadableColors.dark,
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text(copy['video']!), findsOneWidget);
        for (final action in [
          CallVideoAction.turnCameraOff,
          CallVideoAction.switchCamera,
          CallVideoAction.useAudioOnly,
        ]) {
          final button = find.byKey(ValueKey(action.identifier));
          await tester.ensureVisible(button);
          await tester.pump();
          final bounds = tester.getRect(button);
          expect(bounds.width, greaterThanOrEqualTo(48));
          expect(bounds.height, greaterThanOrEqualTo(48));
          expect(bounds.left, greaterThanOrEqualTo(12));
          expect(bounds.right, lessThanOrEqualTo(width - 12));
          final label = find.text(copy[action.name]!);
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
        final end = find.byKey(const ValueKey('call_end'));
        await tester.ensureVisible(end);
        await tester.tap(end);
        expect(audio[2], 1);
      });
    }
  }

  testWidgets('all visible wording comes from the injected labels', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        CallVideoControls(
          presentation: view(audio: true),
          audioControls: const Text('Audio slot'),
          onIntent: (_) {},
          controlsLabel: 'Injected group',
          statusLabel: (_) => 'Injected status',
          localCameraLabel: (_) => 'Injected local state',
          remoteCameraLabel: (_) => 'Injected remote state',
          actionLabel: (_) => 'Injected action',
        ),
      ),
    );
    expect(find.text('Injected status'), findsOneWidget);
    expect(find.text('Injected local state'), findsOneWidget);
    expect(find.text('Injected remote state'), findsOneWidget);
    expect(find.text('Injected action'), findsOneWidget);
    expect(find.text('Request video'), findsNothing);
    expect(find.text('Audio slot'), findsOneWidget);
  });
}
