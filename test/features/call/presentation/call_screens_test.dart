import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/presentation/screens/active_call_screen.dart';
import 'package:flutter_app/features/call/presentation/screens/incoming_call_screen.dart';
import 'package:flutter_app/features/call/presentation/screens/outgoing_call_screen.dart';
import 'package:flutter_app/features/call/presentation/widgets/call_controls.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Theme(
      data: ThemeData(
        extensions: const <ThemeExtension<dynamic>>[
          BackgroundReadableColors.dark,
        ],
      ),
      child: Scaffold(body: child),
    ),
  );

  CallControls controls({
    bool isMuted = false,
    bool isMuteAvailable = true,
    bool isSpeakerOn = false,
    bool isSpeakerAvailable = true,
    CallAudioOutputRoute selectedRoute = CallAudioOutputRoute.systemDefault,
    String? audioStatusMessage,
    String speakerUnavailableMessage =
        'Speaker is unavailable for the current audio route',
    VoidCallback? onMute,
    VoidCallback? onSpeaker,
    VoidCallback? onEnd,
  }) => CallControls(
    isMuted: isMuted,
    isMuteAvailable: isMuteAvailable,
    isSpeakerOn: isSpeakerOn,
    isSpeakerAvailable: isSpeakerAvailable,
    selectedRoute: selectedRoute,
    audioStatusMessage: audioStatusMessage,
    muteUnavailableMessage:
        'Microphone controls are unavailable until audio is ready',
    speakerUnavailableMessage: speakerUnavailableMessage,
    onMute: onMute ?? () {},
    onSpeaker: onSpeaker ?? () {},
    onEnd: onEnd ?? () {},
  );

  group('foreground call screens', () {
    testWidgets('outgoing call distinguishes Calling from remote Ringing', (
      tester,
    ) async {
      var cancelCount = 0;

      await tester.pumpWidget(
        wrap(
          OutgoingCallScreen(
            contactPeerId: 'alice-peer',
            contactUsername: 'Alice',
            state: CallState.inviting,
            onCancel: () => cancelCount += 1,
          ),
        ),
      );

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Calling'), findsOneWidget);
      expect(find.text('Ringing'), findsNothing);
      await tester.tap(find.byTooltip('Cancel call'));
      expect(cancelCount, 1);

      // CallState.ringing is reached only after the authenticated remote
      // ringing event has been reduced by the canonical call reducer.
      await tester.pumpWidget(
        wrap(
          OutgoingCallScreen(
            contactPeerId: 'alice-peer',
            contactUsername: 'Alice',
            state: CallState.ringing,
            onCancel: () => cancelCount += 1,
          ),
        ),
      );

      expect(find.text('Calling'), findsNothing);
      expect(find.text('Ringing'), findsOneWidget);
      await tester.tap(find.byTooltip('Cancel call'));
      expect(cancelCount, 2);
    });

    testWidgets('incoming call exposes answer and decline actions', (
      tester,
    ) async {
      var answerCount = 0;
      var declineCount = 0;

      await tester.pumpWidget(
        wrap(
          IncomingCallScreen(
            contactPeerId: 'alice-peer',
            contactUsername: 'Alice',
            state: CallState.ringing,
            onAnswer: () => answerCount += 1,
            onDecline: () => declineCount += 1,
          ),
        ),
      );

      expect(find.text('Incoming call'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);

      await tester.tap(find.byTooltip('Answer'));
      expect(answerCount, 1);
      expect(declineCount, 0);

      await tester.tap(find.byTooltip('Decline'));
      expect(answerCount, 1);
      expect(declineCount, 1);
    });

    testWidgets('active call renders canonical connection states', (
      tester,
    ) async {
      final now = DateTime.utc(2026, 8, 30, 12);

      await tester.pumpWidget(
        wrap(
          ActiveCallScreen(
            contactPeerId: 'alice-peer',
            contactUsername: 'Alice',
            state: CallState.negotiating,
            connectedAt: null,
            now: () => now,
            controls: controls(),
          ),
        ),
      );
      expect(find.text('Connecting'), findsOneWidget);
      expect(find.text('00:00'), findsNothing);

      await tester.pumpWidget(
        wrap(
          ActiveCallScreen(
            contactPeerId: 'alice-peer',
            contactUsername: 'Alice',
            state: CallState.reconnecting,
            connectedAt: now.subtract(const Duration(seconds: 65)),
            now: () => now,
            controls: controls(),
          ),
        ),
      );
      expect(find.text('Reconnecting'), findsOneWidget);
      expect(find.text('Connecting'), findsNothing);

      await tester.pumpWidget(
        wrap(
          ActiveCallScreen(
            contactPeerId: 'alice-peer',
            contactUsername: 'Alice',
            state: CallState.connected,
            connectedAt: now.subtract(const Duration(seconds: 65)),
            now: () => now,
            controls: controls(),
          ),
        ),
      );
      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('01:05'), findsOneWidget);
    });

    testWidgets('active call keeps End call reachable in short landscape', (
      tester,
    ) async {
      final originalPhysicalSize = tester.view.physicalSize;
      final originalDevicePixelRatio = tester.view.devicePixelRatio;
      addTearDown(() {
        tester.view.physicalSize = originalPhysicalSize;
        tester.view.devicePixelRatio = originalDevicePixelRatio;
      });
      tester.view.physicalSize = const Size(2400, 1080);
      tester.view.devicePixelRatio = 2.625;

      var endCount = 0;
      final now = DateTime.utc(2026, 8, 30, 12);
      await tester.pumpWidget(
        wrap(
          ActiveCallScreen(
            contactPeerId: 'alice-peer',
            contactUsername: 'Alice',
            state: CallState.connected,
            connectedAt: now,
            now: () => now,
            controls: controls(
              audioStatusMessage: 'Audio output could not be changed',
              onEnd: () => endCount += 1,
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final endCall = find.byTooltip('End call').hitTestable();
      expect(endCall, findsOneWidget);
      await tester.tap(endCall);
      expect(endCount, 1);
    });

    testWidgets('active call exposes exact platform accessibility boundaries', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        final now = DateTime.utc(2026, 8, 30, 12);

        await tester.pumpWidget(
          wrap(
            ActiveCallScreen(
              contactPeerId: 'alice-peer',
              contactUsername: 'Alice',
              state: CallState.connected,
              connectedAt: now,
              now: () => now,
              controls: controls(),
            ),
          ),
        );

        final connectedBoundary = tester.widget<Semantics>(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.label == 'Connected',
          ),
        );
        final controlsBoundary = tester.widget<Semantics>(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.label == 'Call controls',
          ),
        );

        expect(connectedBoundary.container, isTrue);
        expect(controlsBoundary.container, isTrue);
        expect(controlsBoundary.explicitChildNodes, isTrue);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('normal call UI does not expose technical connection data', (
      tester,
    ) async {
      final now = DateTime.utc(2026, 8, 30, 12);

      await tester.pumpWidget(
        wrap(
          ActiveCallScreen(
            contactPeerId: 'peer|192.0.2.1|candidate:host|sdp-offer',
            contactUsername: 'Alice',
            state: CallState.connected,
            connectedAt: now,
            now: () => now,
            controls: controls(),
          ),
        ),
      );

      final renderedText = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
          .join(' ')
          .toLowerCase();
      expect(renderedText, isNot(contains('192.0.2.1')));
      expect(
        RegExp(r'\b(?:sdp|ice|candidate)\b').hasMatch(renderedText),
        isFalse,
      );
    });
  });

  group('CallControls', () {
    testWidgets('exact semantic actions dispatch each enabled control once', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        var muteCount = 0;
        var speakerCount = 0;
        var endCount = 0;
        await tester.pumpWidget(
          wrap(
            controls(
              onMute: () => muteCount += 1,
              onSpeaker: () => speakerCount += 1,
              onEnd: () => endCount += 1,
            ),
          ),
        );

        for (final label in const <String>['Mute', 'Speaker', 'End']) {
          final action = find.byWidgetPredicate(
            (widget) => widget is Semantics && widget.properties.label == label,
          );
          expect(action, findsOneWidget);
          final boundary = tester.widget<Semantics>(action);
          final data = tester.getSemantics(action).getSemanticsData();
          expect(boundary.container, isTrue);
          expect(data.flagsCollection.isButton, isTrue);
          expect(data.hasAction(SemanticsAction.tap), isTrue);
          expect(find.semantics.byLabel(label), findsOne);
          tester.semantics.performAction(
            find.semantics.byPredicate(
              (node) =>
                  node.label == label &&
                  node.getSemanticsData().hasAction(SemanticsAction.tap),
            ),
            SemanticsAction.tap,
          );
          await tester.pump();
        }

        expect((muteCount, speakerCount, endCount), (1, 1, 1));
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('dispatches mute, supported speaker, and end actions', (
      tester,
    ) async {
      var muteCount = 0;
      var speakerCount = 0;
      var endCount = 0;

      await tester.pumpWidget(
        wrap(
          controls(
            onMute: () => muteCount += 1,
            onSpeaker: () => speakerCount += 1,
            onEnd: () => endCount += 1,
          ),
        ),
      );

      await tester.tap(find.byTooltip('Mute'));
      await tester.tap(find.byTooltip('Speaker'));
      await tester.tap(find.byTooltip('End call'));

      expect(muteCount, 1);
      expect(speakerCount, 1);
      expect(endCount, 1);
    });

    testWidgets('labels reflect actual mute and speaker state', (tester) async {
      await tester.pumpWidget(wrap(controls(isMuted: true, isSpeakerOn: true)));

      expect(find.byTooltip('Unmute'), findsOneWidget);
      expect(find.byTooltip('Turn speaker off'), findsOneWidget);
      expect(find.byTooltip('Mute'), findsNothing);
    });

    testWidgets('unavailable speaker route explains and does not dispatch', (
      tester,
    ) async {
      const reason = 'Speaker is unavailable for the current audio route';
      var speakerCount = 0;

      await tester.pumpWidget(
        wrap(
          controls(
            isSpeakerAvailable: false,
            speakerUnavailableMessage: reason,
            onSpeaker: () => speakerCount += 1,
          ),
        ),
      );

      await tester.tap(find.byTooltip(reason));
      await tester.pump();

      expect(speakerCount, 0);
      expect(find.text(reason), findsOneWidget);
    });

    testWidgets('surfaces every actual coarse audio output route', (
      tester,
    ) async {
      const expectations = <CallAudioOutputRoute, String>{
        CallAudioOutputRoute.systemDefault: 'Audio output: System default',
        CallAudioOutputRoute.earpiece: 'Audio output: Earpiece',
        CallAudioOutputRoute.speaker: 'Audio output: Speaker',
        CallAudioOutputRoute.wiredHeadset: 'Audio output: Wired headset',
        CallAudioOutputRoute.bluetooth: 'Audio output: Bluetooth',
      };

      for (final entry in expectations.entries) {
        await tester.pumpWidget(wrap(controls(selectedRoute: entry.key)));

        expect(find.text(entry.value), findsOneWidget);
      }
    });

    testWidgets('surfaces a privacy-safe audio route failure', (tester) async {
      const message = 'Audio output could not be changed';

      await tester.pumpWidget(
        wrap(
          controls(
            selectedRoute: CallAudioOutputRoute.bluetooth,
            audioStatusMessage: message,
          ),
        ),
      );

      expect(find.text('Audio output: Bluetooth'), findsOneWidget);
      expect(find.text(message), findsOneWidget);
      expect(find.textContaining('device'), findsNothing);
      expect(find.textContaining('route id'), findsNothing);
    });
  });
}
