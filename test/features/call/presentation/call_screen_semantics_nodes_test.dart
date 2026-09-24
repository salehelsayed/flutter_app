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

/// Beta 2026-09-24: iOS read the whole outgoing call screen as one element,
/// "Beta Pixel\nRinging\nCancel". The name, the status and each control must
/// be separate accessibility elements, and each control carries a stable
/// identifier for UI automation.
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
      // The foreground call overlay hosts these screens in a Stack above the
      // app, outside any route's explicit-child-nodes scope. A plain container
      // ancestor reproduces that host: without explicit boundaries, plain
      // texts merge into it, which is what iOS showed on device.
      child: Scaffold(body: Semantics(container: true, child: child)),
    ),
  );

  CallControls controls({
    VoidCallback? onMute,
    VoidCallback? onSpeaker,
    VoidCallback? onEnd,
  }) => CallControls(
    isMuted: false,
    isMuteAvailable: true,
    isSpeakerOn: false,
    isSpeakerAvailable: true,
    selectedRoute: CallAudioOutputRoute.systemDefault,
    audioStatusMessage: null,
    muteUnavailableMessage: 'Microphone unavailable',
    speakerUnavailableMessage: 'Speaker unavailable',
    onMute: onMute ?? () {},
    onSpeaker: onSpeaker ?? () {},
    onEnd: onEnd ?? () {},
  );

  SemanticsData nodeWithIdentifier(WidgetTester tester, String identifier) {
    final finder = find.bySemanticsIdentifier(identifier);
    expect(finder, findsOneWidget, reason: 'missing identifier $identifier');
    final node = tester.getSemantics(finder);
    expect(node.identifier, identifier);
    return node.getSemanticsData();
  }

  void expectTappableButton(
    WidgetTester tester,
    String identifier,
    String label, {
    bool announcedAsTooltip = false,
  }) {
    final data = nodeWithIdentifier(tester, identifier);
    // The call screen buttons keep the announcement their IconButton had
    // (its tooltip); the in-call controls announce a label.
    expect(announcedAsTooltip ? data.tooltip : data.label, label);
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue);
  }

  void expectNoMergedNode(String name, String status) {
    expect(
      find.semantics.byPredicate(
        (node) => node.label.contains(name) && node.label.contains(status),
      ),
      findsNothing,
      reason: 'name and status must be separate accessibility elements',
    );
  }

  testWidgets('BETA-0924-40 outgoing screen splits name, status and cancel', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      var cancelled = 0;
      await tester.pumpWidget(
        wrap(
          OutgoingCallScreen(
            contactPeerId: 'alice-peer',
            contactUsername: 'Beta Pixel',
            state: CallState.ringing,
            onCancel: () => cancelled += 1,
          ),
        ),
      );

      expectNoMergedNode('Beta Pixel', 'Ringing');
      expect(
        find.semantics.byPredicate(
          (node) =>
              node.label.contains('Ringing') && node.label.contains('Cancel'),
        ),
        findsNothing,
      );
      expect(find.semantics.byLabel('Beta Pixel'), findsOne);
      expect(nodeWithIdentifier(tester, 'call_status').label, 'Ringing');
      expectTappableButton(
        tester,
        'call_cancel',
        'Cancel call',
        announcedAsTooltip: true,
      );

      tester.semantics.performAction(
        find.semantics.byPredicate((node) => node.identifier == 'call_cancel'),
        SemanticsAction.tap,
      );
      await tester.pump();
      expect(cancelled, 1);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('BETA-0924-41 incoming screen splits name, status, answer and '
      'decline', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      var answered = 0;
      var declined = 0;
      await tester.pumpWidget(
        wrap(
          IncomingCallScreen(
            contactPeerId: 'alice-peer',
            contactUsername: 'Beta iPhone',
            state: CallState.ringing,
            onAnswer: () => answered += 1,
            onDecline: () => declined += 1,
          ),
        ),
      );

      expectNoMergedNode('Beta iPhone', 'Incoming call');
      expect(find.semantics.byLabel('Beta iPhone'), findsOne);
      expect(nodeWithIdentifier(tester, 'call_status').label, 'Incoming call');
      expectTappableButton(
        tester,
        'call_answer',
        'Answer',
        announcedAsTooltip: true,
      );
      expectTappableButton(
        tester,
        'call_decline',
        'Decline',
        announcedAsTooltip: true,
      );

      for (final id in const <String>['call_answer', 'call_decline']) {
        tester.semantics.performAction(
          find.semantics.byPredicate((node) => node.identifier == id),
          SemanticsAction.tap,
        );
        await tester.pump();
      }
      expect((answered, declined), (1, 1));
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('BETA-0924-42 active screen exposes status and control '
      'identifiers', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final now = DateTime.utc(2026, 9, 24, 23);
      await tester.pumpWidget(
        wrap(
          ActiveCallScreen(
            contactPeerId: 'alice-peer',
            contactUsername: 'Beta iPhone',
            state: CallState.connected,
            connectedAt: now.subtract(const Duration(seconds: 65)),
            now: () => now,
            controls: controls(),
          ),
        ),
      );

      expectNoMergedNode('Beta iPhone', 'Connected');
      expect(find.semantics.byLabel('Beta iPhone'), findsOne);
      expect(nodeWithIdentifier(tester, 'call_status').label, 'Connected');
      expectTappableButton(tester, 'call_mute', 'Mute');
      expectTappableButton(tester, 'call_speaker', 'Speaker');
      expectTappableButton(tester, 'call_end', 'End');
    } finally {
      semantics.dispose();
    }
  });
}
