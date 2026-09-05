import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/call/application/call_audio_controller.dart';
import 'package:flutter_app/features/call/application/foreground_call_capability.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/presentation/foreground_call_overlay.dart';
import 'package:flutter_app/features/call/presentation/screens/active_call_screen.dart';
import 'package:flutter_app/features/call/presentation/screens/incoming_call_screen.dart';
import 'package:flutter_app/features/call/presentation/screens/outgoing_call_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const fallbackName = 'Unknown contact';
  final now = DateTime.utc(2026, 8, 30, 12);

  Widget harness({
    required _FakeForegroundCallCapability capability,
    Future<String?> Function(String peerId)? loadContactDisplayName,
    double keyboardInset = 0,
    Widget child = const Scaffold(
      body: ColoredBox(
        color: Colors.black,
        child: Center(child: Text('retained child')),
      ),
    ),
  }) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(
      extensions: const <ThemeExtension<dynamic>>[
        BackgroundReadableColors.dark,
      ],
    ),
    home: Builder(
      builder: (context) {
        final overlay = ForegroundCallOverlay(
          capability: capability,
          loadContactDisplayName:
              loadContactDisplayName ?? (_) async => 'Local contact',
          now: () => now,
          child: child,
        );
        if (keyboardInset == 0) return overlay;
        // A software keyboard reports itself as the bottom view inset.
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(viewInsets: EdgeInsets.only(bottom: keyboardInset)),
          child: overlay,
        );
      },
    ),
  );

  group('ForegroundCallOverlay projection', () {
    testWidgets('maps only the canonical foreground call states', (
      tester,
    ) async {
      final capability = _FakeForegroundCallCapability();
      addTearDown(capability.dispose);

      await tester.pumpWidget(harness(capability: capability));
      expect(find.byType(IncomingCallScreen), findsNothing);
      expect(find.byType(OutgoingCallScreen), findsNothing);
      expect(find.byType(ActiveCallScreen), findsNothing);

      for (final state in <CallState>[
        CallState.incomingValidating,
        CallState.ringing,
      ]) {
        capability.emit(
          _projection(
            now: now,
            callId: _incomingId,
            peerId: 'incoming-peer',
            direction: CallDirection.incoming,
            state: state,
            incomingValidated: true,
          ),
        );
        await tester.pump();
        expect(find.byType(IncomingCallScreen), findsOneWidget);
        expect(find.byType(OutgoingCallScreen), findsNothing);
        expect(find.byType(ActiveCallScreen), findsNothing);
      }

      for (final state in <CallState>[
        CallState.preparing,
        CallState.inviting,
        CallState.ringing,
      ]) {
        capability.emit(
          _projection(
            now: now,
            callId: _outgoingId,
            peerId: 'outgoing-peer',
            direction: CallDirection.outgoing,
            state: state,
          ),
        );
        await tester.pump();
        expect(find.byType(IncomingCallScreen), findsNothing);
        expect(find.byType(OutgoingCallScreen), findsOneWidget);
        expect(find.byType(ActiveCallScreen), findsNothing);
      }

      for (final state in <CallState>[
        CallState.accepted,
        CallState.negotiating,
        CallState.connected,
        CallState.reconnecting,
        CallState.ending,
      ]) {
        capability.emit(
          _projection(
            now: now,
            callId: _outgoingId,
            peerId: 'outgoing-peer',
            direction: CallDirection.outgoing,
            state: state,
          ),
        );
        await tester.pump();
        expect(find.byType(IncomingCallScreen), findsNothing);
        expect(find.byType(OutgoingCallScreen), findsNothing);
        expect(find.byType(ActiveCallScreen), findsOneWidget);
      }

      capability.emit(
        ForegroundCallProjection(
          session: CallSessionSnapshot.idle(now: now),
          audio: CallAudioControlState.idle,
        ),
      );
      await tester.pump();
      expect(find.byType(ActiveCallScreen), findsNothing);

      capability.emit(
        _projection(
          now: now,
          callId: _outgoingId,
          peerId: 'outgoing-peer',
          direction: CallDirection.outgoing,
          state: CallState.ended,
        ),
      );
      await tester.pump();
      expect(find.byType(ActiveCallScreen), findsNothing);

      capability.emit(null);
      await tester.pump();
      expect(find.text('retained child'), findsOneWidget);
    });

    testWidgets('hides every unvalidated incoming projection', (tester) async {
      final capability = _FakeForegroundCallCapability();
      addTearDown(capability.dispose);
      await tester.pumpWidget(harness(capability: capability));

      for (final state in <CallState>[
        CallState.incomingValidating,
        CallState.ringing,
        CallState.accepted,
        CallState.connected,
      ]) {
        capability.emit(
          _projection(
            now: now,
            callId: _incomingId,
            peerId: 'private-peer-id',
            direction: CallDirection.incoming,
            state: state,
            incomingValidated: false,
          ),
        );
        await tester.pump();
        expect(find.byType(IncomingCallScreen), findsNothing);
        expect(find.byType(ActiveCallScreen), findsNothing);
        expect(find.text('private-peer-id'), findsNothing);
      }
    });
  });

  testWidgets(
    'root builder call controls do not require the Navigator overlay',
    (tester) async {
      final capability = _FakeForegroundCallCapability();
      addTearDown(capability.dispose);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            extensions: const <ThemeExtension<dynamic>>[
              BackgroundReadableColors.dark,
            ],
          ),
          builder: (context, child) => ForegroundCallOverlay(
            capability: capability,
            loadContactDisplayName: (_) async => 'Local contact',
            now: () => now,
            child: child ?? const SizedBox.shrink(),
          ),
          home: const Scaffold(body: Text('retained child')),
        ),
      );

      capability.emit(
        _projection(
          now: now,
          callId: _outgoingId,
          peerId: 'outgoing-peer',
          direction: CallDirection.outgoing,
          state: CallState.inviting,
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(Icons.call_end_rounded));
      await tester.pump();
      expect(capability.actions, <_RecordedAction>[
        _RecordedAction('cancel', _outgoingId),
      ]);

      capability.emit(
        _projection(
          now: now,
          callId: _incomingId,
          peerId: 'incoming-peer',
          direction: CallDirection.incoming,
          state: CallState.ringing,
          incomingValidated: true,
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Answer'), findsOneWidget);
      expect(find.byTooltip('Decline'), findsOneWidget);

      capability.emit(
        _projection(
          now: now,
          callId: _activeId,
          peerId: 'active-peer',
          direction: CallDirection.outgoing,
          state: CallState.connected,
          audio: _audio(
            muted: false,
            selectedRoute: CallAudioOutputRoute.systemDefault,
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Mute'), findsOneWidget);
      expect(find.byTooltip('Speaker'), findsOneWidget);
      expect(find.byTooltip('End call'), findsOneWidget);

      capability.emit(
        _projection(
          now: now,
          callId: _activeId,
          peerId: 'active-peer',
          direction: CallDirection.outgoing,
          state: CallState.ended,
          endReason: CallEndReason.callerCancelled,
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Dismiss call status'), findsOneWidget);
    },
  );

  testWidgets(
    'root builder active call text does not inherit debug fallback underlines',
    (tester) async {
      final capability = _FakeForegroundCallCapability();
      addTearDown(capability.dispose);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            extensions: const <ThemeExtension<dynamic>>[
              BackgroundReadableColors.dark,
            ],
          ),
          builder: (context, child) => ForegroundCallOverlay(
            capability: capability,
            loadContactDisplayName: (_) async => 'Local contact',
            now: () => now,
            child: child ?? const SizedBox.shrink(),
          ),
          home: const Scaffold(body: Text('retained child')),
        ),
      );

      capability.emit(
        _projection(
          now: now,
          callId: _activeId,
          peerId: 'active-peer',
          direction: CallDirection.outgoing,
          state: CallState.connected,
          audio: _audio(
            muted: false,
            selectedRoute: CallAudioOutputRoute.systemDefault,
          ),
        ),
      );
      await tester.pump();

      for (final label in const <String>[
        'Connected',
        'Audio output: System default',
        'Mute',
        'Speaker',
        'End',
      ]) {
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(label),
        );
        expect(
          paragraph.text.style?.decoration,
          isNot(TextDecoration.underline),
          reason: '$label must not use the WidgetsApp debug fallback style',
        );
        expect(
          paragraph.text.style?.decorationStyle,
          isNot(TextDecorationStyle.double),
          reason: '$label must not show debug fallback double lines',
        );
      }
    },
  );

  testWidgets('dispatches every action with the displayed call ID', (
    tester,
  ) async {
    final capability = _FakeForegroundCallCapability();
    addTearDown(capability.dispose);
    await tester.pumpWidget(harness(capability: capability));

    capability.emit(
      _projection(
        now: now,
        callId: _incomingId,
        peerId: 'incoming-peer',
        direction: CallDirection.incoming,
        state: CallState.ringing,
        incomingValidated: true,
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Answer'));
    await tester.tap(find.byTooltip('Decline'));

    capability.emit(
      _projection(
        now: now,
        callId: _outgoingId,
        peerId: 'outgoing-peer',
        direction: CallDirection.outgoing,
        state: CallState.inviting,
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Cancel call'));

    capability.emit(
      _projection(
        now: now,
        callId: _activeId,
        peerId: 'active-peer',
        direction: CallDirection.outgoing,
        state: CallState.connected,
        audio: _audio(
          muted: false,
          selectedRoute: CallAudioOutputRoute.systemDefault,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Mute'));
    await tester.tap(find.byTooltip('Speaker'));
    await tester.tap(find.byTooltip('End call'));

    expect(capability.actions, <_RecordedAction>[
      _RecordedAction('answer', _incomingId),
      _RecordedAction('decline', _incomingId),
      _RecordedAction('cancel', _outgoingId),
      _RecordedAction('setMuted', _activeId, value: true),
      _RecordedAction('setSpeakerEnabled', _activeId, value: true),
      _RecordedAction('end', _activeId),
    ]);
  });

  testWidgets('controls wait for actual emitted audio state', (tester) async {
    final capability = _FakeForegroundCallCapability();
    addTearDown(capability.dispose);
    await tester.pumpWidget(harness(capability: capability));

    capability.emit(
      _projection(
        now: now,
        callId: _activeId,
        peerId: 'active-peer',
        direction: CallDirection.outgoing,
        state: CallState.connected,
        audio: _audio(
          muted: false,
          selectedRoute: CallAudioOutputRoute.systemDefault,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Mute'));
    await tester.tap(find.byTooltip('Speaker'));
    await tester.pump();
    expect(find.byTooltip('Mute'), findsOneWidget);
    expect(find.byTooltip('Speaker'), findsOneWidget);
    expect(find.byTooltip('Unmute'), findsNothing);
    expect(find.byTooltip('Turn speaker off'), findsNothing);

    capability.emit(
      _projection(
        now: now,
        callId: _activeId,
        peerId: 'active-peer',
        direction: CallDirection.outgoing,
        state: CallState.connected,
        audio: _audio(muted: true, selectedRoute: CallAudioOutputRoute.speaker),
      ),
    );
    await tester.pump();
    expect(find.byTooltip('Unmute'), findsOneWidget);
    expect(find.byTooltip('Turn speaker off'), findsOneWidget);

    await tester.tap(find.byTooltip('Unmute'));
    await tester.tap(find.byTooltip('Turn speaker off'));
    await tester.pump();
    expect(find.byTooltip('Unmute'), findsOneWidget);
    expect(find.byTooltip('Turn speaker off'), findsOneWidget);
    expect(
      capability.actions.where((action) => action.name == 'setMuted').last,
      _RecordedAction('setMuted', _activeId, value: false),
    );
    expect(
      capability.actions
          .where((action) => action.name == 'setSpeakerEnabled')
          .last,
      _RecordedAction('setSpeakerEnabled', _activeId, value: false),
    );

    capability.emit(
      _projection(
        now: now,
        callId: _activeId,
        peerId: 'active-peer',
        direction: CallDirection.outgoing,
        state: CallState.connected,
        audio: _audio(
          muted: false,
          selectedRoute: CallAudioOutputRoute.systemDefault,
        ),
      ),
    );
    await tester.pump();
    expect(find.byTooltip('Mute'), findsOneWidget);
    expect(find.byTooltip('Speaker'), findsOneWidget);
  });

  testWidgets('speaker is available only from active supported audio truth', (
    tester,
  ) async {
    final capability = _FakeForegroundCallCapability();
    addTearDown(capability.dispose);
    await tester.pumpWidget(harness(capability: capability));

    for (final audio in <CallAudioControlState>[
      _audio(active: false, selectedRoute: CallAudioOutputRoute.systemDefault),
      _audio(
        selectedRoute: CallAudioOutputRoute.systemDefault,
        supportedRoutes: const <CallAudioOutputRoute>[
          CallAudioOutputRoute.systemDefault,
        ],
      ),
    ]) {
      capability.emit(
        _projection(
          now: now,
          callId: _activeId,
          peerId: 'active-peer',
          direction: CallDirection.outgoing,
          state: CallState.connected,
          audio: audio,
        ),
      );
      await tester.pump();
      await tester.tap(
        find.byTooltip('Speaker is unavailable for the current audio route'),
      );
      await tester.pump();
      expect(
        capability.actions.where(
          (action) => action.name == 'setSpeakerEnabled',
        ),
        isEmpty,
      );
    }
  });

  testWidgets('maps stable terminal reasons to finite privacy-safe notices', (
    tester,
  ) async {
    final capability = _FakeForegroundCallCapability();
    addTearDown(capability.dispose);
    await tester.pumpWidget(harness(capability: capability));

    const expectations = <CallEndReason, String>{
      CallEndReason.permissionDenied:
          'Microphone permission is needed to make calls.',
      CallEndReason.unsupported: 'Voice calling is unavailable on this device.',
      CallEndReason.busy: 'The contact is on another call.',
      CallEndReason.declined: 'Call declined.',
      CallEndReason.noAnswer: 'No answer.',
      CallEndReason.signalingFailed: 'Call could not connect.',
      CallEndReason.mediaFailed: 'Call audio could not start.',
      CallEndReason.reconnectFailed: 'Call could not reconnect.',
    };

    for (final entry in expectations.entries) {
      capability.emit(
        _projection(
          now: now,
          callId: _activeId,
          peerId: 'peer|192.0.2.1|candidate:host|sdp-offer',
          direction: CallDirection.outgoing,
          state: CallState.ended,
          endReason: entry.key,
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('foreground-call-terminal-notice')),
        findsOneWidget,
      );
      expect(find.text(entry.value), findsOneWidget);
      expect(find.textContaining('192.0.2.1'), findsNothing);
      expect(find.textContaining('candidate'), findsNothing);

      await tester.tap(find.byTooltip('Dismiss call status'));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('foreground-call-terminal-notice')),
        findsNothing,
      );

      capability.emit(null);
      await tester.pump();
    }
  });

  testWidgets('terminal notice expires without changing retained navigation', (
    tester,
  ) async {
    final capability = _FakeForegroundCallCapability();
    final navigatorKey = GlobalKey<NavigatorState>();
    addTearDown(capability.dispose);

    await tester.pumpWidget(
      harness(
        capability: capability,
        child: Navigator(
          key: navigatorKey,
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const Scaffold(body: Text('Retained route')),
          ),
        ),
      ),
    );
    capability.emit(
      _projection(
        now: now,
        callId: _activeId,
        peerId: 'active-peer',
        direction: CallDirection.outgoing,
        state: CallState.ended,
        endReason: CallEndReason.mediaFailed,
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('foreground-call-terminal-notice')),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 6));

    expect(
      find.byKey(const ValueKey('foreground-call-terminal-notice')),
      findsNothing,
    );
    expect(find.text('Retained route'), findsOneWidget);
  });

  testWidgets('speaker result reports unavailable and failed without detail', (
    tester,
  ) async {
    final capability = _FakeForegroundCallCapability();
    addTearDown(capability.dispose);
    await tester.pumpWidget(harness(capability: capability));
    capability.emit(
      _projection(
        now: now,
        callId: _activeId,
        peerId: 'active-peer',
        direction: CallDirection.outgoing,
        state: CallState.connected,
        audio: _audio(),
      ),
    );
    await tester.pump();

    capability.nextSpeakerResult = ForegroundCallActionResult.unavailable;
    await tester.tap(find.byTooltip('Speaker'));
    await tester.pump();
    expect(find.text('That audio output is unavailable'), findsOneWidget);

    capability.nextSpeakerResult = ForegroundCallActionResult.failed;
    await tester.tap(find.byTooltip('Speaker'));
    await tester.pump();
    expect(find.text('Audio output could not be changed'), findsOneWidget);
  });

  testWidgets('projected audio failures use fixed privacy-safe text', (
    tester,
  ) async {
    final capability = _FakeForegroundCallCapability();
    addTearDown(capability.dispose);
    await tester.pumpWidget(harness(capability: capability));

    for (final entry in const <CallAudioFailure, String>{
      CallAudioFailure.unsupportedRoute: 'That audio output is unavailable',
      CallAudioFailure.controlFailed: 'Audio controls could not be updated',
    }.entries) {
      capability.emit(
        _projection(
          now: now,
          callId: _activeId,
          peerId: 'active-peer',
          direction: CallDirection.outgoing,
          state: CallState.connected,
          audio: _audio(failure: entry.key),
        ),
      );
      await tester.pump();
      expect(find.text(entry.value), findsOneWidget);
    }
  });

  testWidgets('mute is unavailable until active audio truth is emitted', (
    tester,
  ) async {
    final capability = _FakeForegroundCallCapability();
    addTearDown(capability.dispose);
    await tester.pumpWidget(harness(capability: capability));

    capability.emit(
      _projection(
        now: now,
        callId: _activeId,
        peerId: 'active-peer',
        direction: CallDirection.outgoing,
        state: CallState.negotiating,
        audio: _audio(active: false),
      ),
    );
    await tester.pump();

    await tester.tap(
      find.byTooltip(
        'Microphone controls are unavailable until audio is ready',
      ),
    );
    await tester.pump();

    expect(
      capability.actions.where((action) => action.name == 'setMuted'),
      isEmpty,
    );
  });

  testWidgets('rejects a stale contact display-name completion', (
    tester,
  ) async {
    final capability = _FakeForegroundCallCapability();
    final firstName = Completer<String?>();
    final secondName = Completer<String?>();
    addTearDown(capability.dispose);

    await tester.pumpWidget(
      harness(
        capability: capability,
        loadContactDisplayName: (peerId) => switch (peerId) {
          'first-private-peer' => firstName.future,
          'second-private-peer' => secondName.future,
          _ => Future<String?>.value(null),
        },
      ),
    );

    capability.emit(
      _projection(
        now: now,
        callId: _incomingId,
        peerId: 'first-private-peer',
        direction: CallDirection.incoming,
        state: CallState.ringing,
        incomingValidated: true,
      ),
    );
    await tester.pump();
    expect(find.text(fallbackName), findsOneWidget);
    expect(find.text('first-private-peer'), findsNothing);

    capability.emit(
      _projection(
        now: now,
        callId: _outgoingId,
        peerId: 'second-private-peer',
        direction: CallDirection.outgoing,
        state: CallState.inviting,
      ),
    );
    await tester.pump();
    secondName.complete('Second contact');
    await tester.pump();
    await tester.pump();
    expect(find.text('Second contact'), findsOneWidget);

    firstName.complete('Stale first contact');
    await tester.pump();
    await tester.pump();
    expect(find.text('Second contact'), findsOneWidget);
    expect(find.text('Stale first contact'), findsNothing);
    expect(find.text('first-private-peer'), findsNothing);
    expect(find.text('second-private-peer'), findsNothing);
  });

  testWidgets(
    'terminal and withdrawn projections remove overlay without route loss',
    (tester) async {
      final capability = _FakeForegroundCallCapability();
      final navigatorKey = GlobalKey<NavigatorState>();
      addTearDown(capability.dispose);

      await tester.pumpWidget(
        harness(
          capability: capability,
          child: Navigator(
            key: navigatorKey,
            initialRoute: '/',
            onGenerateRoute: (settings) => MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => Scaffold(
                body: Center(
                  child: Text(
                    settings.name == '/second' ? 'Second route' : 'First route',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      navigatorKey.currentState!.pushNamed('/second');
      await tester.pumpAndSettle();
      expect(find.text('Second route'), findsOneWidget);

      capability.emit(
        _projection(
          now: now,
          callId: _activeId,
          peerId: 'active-peer',
          direction: CallDirection.outgoing,
          state: CallState.connected,
        ),
      );
      await tester.pump();
      expect(find.byType(ActiveCallScreen), findsOneWidget);

      capability.emit(
        _projection(
          now: now,
          callId: _activeId,
          peerId: 'active-peer',
          direction: CallDirection.outgoing,
          state: CallState.ended,
        ),
      );
      await tester.pump();
      expect(find.byType(ActiveCallScreen), findsNothing);
      expect(find.text('Second route'), findsOneWidget);

      capability.emit(
        _projection(
          now: now,
          callId: _outgoingId,
          peerId: 'outgoing-peer',
          direction: CallDirection.outgoing,
          state: CallState.inviting,
        ),
      );
      await tester.pump();
      expect(find.byType(OutgoingCallScreen), findsOneWidget);

      capability.emit(null);
      await tester.pump();
      expect(find.byType(OutgoingCallScreen), findsNothing);
      expect(find.text('Second route'), findsOneWidget);
      expect(navigatorKey.currentState!.canPop(), isTrue);
    },
  );
  testWidgets(
    'a visible call surface releases keyboard focus and blocks refocus until it hides',
    (tester) async {
      final capability = _FakeForegroundCallCapability();
      addTearDown(capability.dispose);
      final composerFocus = FocusNode(debugLabel: 'composer');
      addTearDown(composerFocus.dispose);
      await tester.pumpWidget(
        harness(
          capability: capability,
          child: Scaffold(
            body: Center(child: TextField(focusNode: composerFocus)),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(composerFocus.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);

      capability.emit(
        _projection(
          now: now,
          callId: _outgoingId,
          peerId: 'outgoing-peer',
          direction: CallDirection.outgoing,
          state: CallState.inviting,
        ),
      );
      await tester.pump();

      expect(find.byType(OutgoingCallScreen), findsOneWidget);
      expect(composerFocus.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);

      // Nothing underneath may bring the keyboard back over the call surface.
      composerFocus.requestFocus();
      await tester.pump();
      expect(composerFocus.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);

      capability.emit(null);
      await tester.pump();
      expect(find.byType(OutgoingCallScreen), findsNothing);
      composerFocus.requestFocus();
      await tester.pump();
      expect(composerFocus.hasFocus, isTrue);
    },
  );

  testWidgets('call controls stay above the keyboard inset', (tester) async {
    final capability = _FakeForegroundCallCapability();
    addTearDown(capability.dispose);
    // iPhone-class geometry (390x844 logical); a keyboard takes ~300 of it.
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    const keyboardInset = 300.0;
    await tester.pumpWidget(
      harness(capability: capability, keyboardInset: keyboardInset),
    );
    final logicalHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final visibleBottom = logicalHeight - keyboardInset;

    capability.emit(
      _projection(
        now: now,
        callId: _outgoingId,
        peerId: 'outgoing-peer',
        direction: CallDirection.outgoing,
        state: CallState.inviting,
      ),
    );
    await tester.pump();
    expect(
      tester.getRect(find.byTooltip('Cancel call')).bottom,
      lessThanOrEqualTo(visibleBottom),
    );

    capability.emit(
      _projection(
        now: now,
        callId: _activeId,
        peerId: 'active-peer',
        direction: CallDirection.outgoing,
        state: CallState.connected,
        audio: _audio(
          muted: false,
          selectedRoute: CallAudioOutputRoute.systemDefault,
        ),
      ),
    );
    await tester.pump();
    for (final tooltip in const <String>['Mute', 'Speaker', 'End call']) {
      expect(
        tester.getRect(find.byTooltip(tooltip)).bottom,
        lessThanOrEqualTo(visibleBottom),
        reason: tooltip,
      );
    }
  });
}

final _incomingId = CallId.parse('11111111-1111-4111-8111-111111111111');
final _outgoingId = CallId.parse('22222222-2222-4222-8222-222222222222');
final _activeId = CallId.parse('33333333-3333-4333-8333-333333333333');

ForegroundCallProjection _projection({
  required DateTime now,
  required CallId callId,
  required String peerId,
  required CallDirection direction,
  required CallState state,
  bool incomingValidated = false,
  CallEndReason? endReason,
  CallAudioControlState? audio,
}) => ForegroundCallProjection(
  session: CallSessionSnapshot.active(
    callId: callId,
    contactPeerId: peerId,
    direction: direction,
    state: state,
    callerAccountPeerId: direction == CallDirection.incoming
        ? peerId
        : 'local-peer',
    callerDeviceId: direction == CallDirection.incoming
        ? 'remote-device'
        : 'local-device',
    startedAt: now.subtract(const Duration(minutes: 1)),
    ringingAt: state.index >= CallState.ringing.index ? now : null,
    acceptedAt: state.index >= CallState.accepted.index ? now : null,
    connectedAt: state == CallState.connected || state == CallState.reconnecting
        ? now.subtract(const Duration(seconds: 30))
        : null,
    endedAt: state == CallState.ended ? now : null,
    endReason: state == CallState.ended
        ? endReason ?? CallEndReason.localHangup
        : null,
    incomingValidated: incomingValidated,
  ),
  audio: audio ?? CallAudioControlState.idle,
);

CallAudioControlState _audio({
  bool muted = false,
  CallAudioOutputRoute selectedRoute = CallAudioOutputRoute.systemDefault,
  List<CallAudioOutputRoute> supportedRoutes = const <CallAudioOutputRoute>[
    CallAudioOutputRoute.systemDefault,
    CallAudioOutputRoute.speaker,
  ],
  bool active = true,
  CallAudioFailure failure = CallAudioFailure.none,
}) => CallAudioControlState(
  muted: muted,
  selectedRoute: selectedRoute,
  supportedRoutes: supportedRoutes,
  active: active,
  failure: failure,
);

final class _FakeForegroundCallCapability implements ForegroundCallCapability {
  final StreamController<ForegroundCallProjection?> _changes =
      StreamController<ForegroundCallProjection?>.broadcast(sync: true);
  final List<_RecordedAction> actions = <_RecordedAction>[];

  ForegroundCallProjection? _current;
  ForegroundCallActionResult nextSpeakerResult =
      ForegroundCallActionResult.applied;

  @override
  ForegroundCallProjection? get current => _current;

  @override
  Stream<ForegroundCallProjection?> get changes => _changes.stream;

  void emit(ForegroundCallProjection? projection) {
    _current = projection;
    _changes.add(projection);
  }

  Future<void> dispose() => _changes.close();

  Future<ForegroundCallActionResult> _record(
    String name,
    CallId callId, {
    bool? value,
  }) async {
    actions.add(_RecordedAction(name, callId, value: value));
    return ForegroundCallActionResult.applied;
  }

  @override
  Future<ForegroundCallActionResult> answer(CallId callId) =>
      _record('answer', callId);

  @override
  Future<ForegroundCallActionResult> cancel(CallId callId) =>
      _record('cancel', callId);

  @override
  Future<ForegroundCallActionResult> decline(CallId callId) =>
      _record('decline', callId);

  @override
  Future<ForegroundCallActionResult> end(CallId callId) =>
      _record('end', callId);

  @override
  Future<ForegroundCallActionResult> setMuted(CallId callId, bool muted) =>
      _record('setMuted', callId, value: muted);

  @override
  Future<ForegroundCallActionResult> setSpeakerEnabled(
    CallId callId,
    bool enabled,
  ) async {
    actions.add(_RecordedAction('setSpeakerEnabled', callId, value: enabled));
    return nextSpeakerResult;
  }
}

final class _RecordedAction {
  const _RecordedAction(this.name, this.callId, {this.value});

  final String name;
  final CallId callId;
  final bool? value;

  @override
  bool operator ==(Object other) =>
      other is _RecordedAction &&
      other.name == name &&
      other.callId == callId &&
      other.value == value;

  @override
  int get hashCode => Object.hash(name, callId, value);

  @override
  String toString() => '_RecordedAction($name, $callId, $value)';
}
