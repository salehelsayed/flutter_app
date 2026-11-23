import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/call/application/call_audio_controller.dart';
import 'package:flutter_app/features/call/application/foreground_call_capability.dart';
import 'package:flutter_app/features/call/application/outgoing_call_capability.dart';
import 'package:flutter_app/features/call/domain/call_media.dart';
import 'package:flutter_app/features/call/application/locked_call_presentation.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_event.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/domain/call_audio_output_device.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/presentation/foreground_call_back_guard.dart';
import 'package:flutter_app/features/call/presentation/foreground_call_overlay.dart';
import 'package:flutter_app/features/call/presentation/screens/active_call_screen.dart';
import 'package:flutter_app/features/call/presentation/screens/incoming_call_screen.dart';
import 'package:flutter_app/features/call/presentation/screens/outgoing_call_screen.dart';
import 'package:flutter_app/features/call/presentation/widgets/call_controls.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/push/application/push_registration_health_notifier.dart';
import 'package:flutter_app/features/push/domain/push_registration_health.dart';
import 'package:flutter_app/features/push/presentation/widgets/push_registration_health_surface.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/permissions/mic_permission_gateway.dart';

import '../../../shared/fakes/fake_mic_permission_gateway.dart';

void main() {
  _bl61OutcomeTests();
  _vui7Tests();
  const fallbackName = 'Unknown contact';
  final now = DateTime.utc(2026, 8, 30, 12);

  Widget harness({
    required _FakeForegroundCallCapability capability,
    Locale locale = const Locale('en'),
    MicPermissionGateway? micPermission,
    VoidCallback? onAttached,
    Future<String?> Function(String peerId)? loadContactDisplayName,
    double keyboardInset = 0,
    Widget child = const Scaffold(
      body: ColoredBox(
        color: Colors.black,
        child: Center(child: Text('retained child')),
      ),
    ),
  }) => MaterialApp(
    locale: locale,
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
          micPermission: micPermission,
          onAttached: onAttached,
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

  CallSessionSnapshot outgoingProgress(List<CallEventType> events) {
    const reducer = CallReducer();
    var snapshot = CallSessionSnapshot.idle(now: now);
    for (var index = 0; index < events.length; index++) {
      snapshot = reducer
          .reduce(
            snapshot,
            CallEvent(
              type: events[index],
              eventId: 'progress-$index',
              occurredAt: now,
              callId: _outgoingId,
              contactPeerId: 'outgoing-peer',
              localAccountPeerId: 'local-peer',
              localDeviceId: 'local-device',
              remoteAccountPeerId: 'outgoing-peer',
              remoteDeviceId: 'remote-device',
              timeoutKind: events[index] == CallEventType.timeout
                  ? CallTimeoutKind.noAnswer
                  : null,
            ),
          )
          .snapshot;
    }
    return snapshot;
  }

  for (final (locale, calling) in <(Locale, String)>[
    (const Locale('en'), 'Calling'),
    (const Locale('de'), 'Wird angerufen…'),
    (const Locale('ar'), 'جارٍ الاتصال'),
  ]) {
    testWidgets('CALL-PROGRESS ${locale.languageCode} labels preparation and '
        'invitation as Calling', (tester) async {
      final capability = _FakeForegroundCallCapability();
      addTearDown(capability.dispose);
      await tester.pumpWidget(harness(capability: capability, locale: locale));
      for (final events in <List<CallEventType>>[
        [CallEventType.place],
        [CallEventType.place, CallEventType.outgoingInviteReady],
      ]) {
        capability.emit(
          ForegroundCallProjection(
            session: outgoingProgress(events),
            audio: CallAudioControlState.idle,
          ),
        );
        await tester.pump();
        expect(find.text(calling), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('CALL-PROGRESS Arabic accepted and negotiating labels differ '
      'from Calling', (tester) async {
    final capability = _FakeForegroundCallCapability();
    addTearDown(capability.dispose);
    await tester.pumpWidget(
      harness(capability: capability, locale: const Locale('ar')),
    );
    final events = <CallEventType>[
      CallEventType.place,
      CallEventType.outgoingInviteReady,
      CallEventType.remoteAccept,
    ];
    for (final event in <CallEventType?>[
      null,
      CallEventType.negotiationReady,
    ]) {
      if (event != null) events.add(event);
      capability.emit(
        ForegroundCallProjection(
          session: outgoingProgress(events),
          audio: CallAudioControlState.idle,
        ),
      );
      await tester.pump();
      expect(find.text('جارٍ التوصيل…'), findsOneWidget);
      expect(find.text('جارٍ الاتصال'), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('CALL-PROGRESS confirmed alerting and accepted audio setup keep '
      'distinct labels and connected duration', (tester) async {
    final capability = _FakeForegroundCallCapability();
    addTearDown(capability.dispose);
    await tester.pumpWidget(harness(capability: capability));
    final events = <CallEventType>[
      CallEventType.place,
      CallEventType.outgoingInviteReady,
      CallEventType.remoteRinging,
    ];
    for (final (event, label) in <(CallEventType?, String)>[
      (null, 'Ringing'),
      (CallEventType.remoteAccept, 'Connecting'),
      (CallEventType.negotiationReady, 'Connecting'),
      (CallEventType.mediaConnected, 'Connected'),
    ]) {
      if (event != null) events.add(event);
      capability.emit(
        ForegroundCallProjection(
          session: outgoingProgress(events),
          audio: CallAudioControlState.idle,
        ),
      );
      await tester.pump();
      expect(find.text(label), findsOneWidget);
      expect(find.text('Calling'), findsNothing);
    }
    expect(find.text('00:00'), findsOneWidget);
  });

  for (final alerted in [false, true]) {
    testWidgets(
      'CALL-PROGRESS ${alerted ? 'confirmed ringing' : 'no alerting acknowledgement'} '
      'timeout has truthful wording',
      (tester) async {
        final capability = _FakeForegroundCallCapability();
        addTearDown(capability.dispose);
        await tester.pumpWidget(harness(capability: capability));
        capability.emit(
          ForegroundCallProjection(
            session: outgoingProgress([
              CallEventType.place,
              CallEventType.outgoingInviteReady,
              if (alerted) CallEventType.remoteRinging,
              CallEventType.timeout,
            ]),
            audio: CallAudioControlState.idle,
          ),
        );
        await tester.pump();
        expect(
          find.text(alerted ? 'No answer' : 'Call could not connect.'),
          findsOneWidget,
        );
        expect(
          find.text(alerted ? 'Call could not connect.' : 'No answer'),
          findsNothing,
        );
      },
    );
  }

  testWidgets('CALL-PROGRESS answer before ringing remains Connecting and '
      'preserves a later remote no-answer reason', (tester) async {
    final capability = _FakeForegroundCallCapability();
    addTearDown(capability.dispose);
    await tester.pumpWidget(harness(capability: capability));
    final accepted = outgoingProgress([
      CallEventType.place,
      CallEventType.outgoingInviteReady,
      CallEventType.remoteAccept,
    ]);
    expect(accepted.ringingAt, isNull);
    expect(accepted.acceptedAt, isNotNull);
    capability.emit(
      ForegroundCallProjection(
        session: accepted,
        audio: CallAudioControlState.idle,
      ),
    );
    await tester.pump();
    expect(find.text('Connecting'), findsOneWidget);
    expect(find.text('Ringing'), findsNothing);
    capability.emit(
      ForegroundCallProjection(
        session: const CallReducer()
            .reduce(
              accepted,
              CallEvent(
                type: CallEventType.remoteTerminate,
                eventId: 'remote-no-answer',
                occurredAt: now,
                callId: _outgoingId,
                endReason: CallEndReason.noAnswer,
              ),
            )
            .snapshot,
        audio: CallAudioControlState.idle,
      ),
    );
    await tester.pump();
    expect(find.text('No answer'), findsOneWidget);
  });

  for (final (event, reason, label) in [
    (CallEventType.remoteReject, CallEndReason.declined, 'Call declined'),
    (CallEventType.remoteReject, CallEndReason.busy, 'On another call'),
    (
      CallEventType.remoteTerminate,
      CallEndReason.permissionDenied,
      "Local contact can't take calls right now. Their microphone is off.",
    ),
  ]) {
    testWidgets('CALL-PROGRESS ${reason.name} before alerting keeps its '
        'explicit notice', (tester) async {
      final capability = _FakeForegroundCallCapability();
      addTearDown(capability.dispose);
      await tester.pumpWidget(harness(capability: capability));
      final inviting = outgoingProgress([
        CallEventType.place,
        CallEventType.outgoingInviteReady,
      ]);
      capability.emit(
        ForegroundCallProjection(
          session: inviting,
          audio: CallAudioControlState.idle,
        ),
      );
      await tester.pump();
      await tester.pump();
      capability.emit(
        ForegroundCallProjection(
          session: const CallReducer()
              .reduce(
                inviting,
                CallEvent(
                  type: event,
                  eventId: 'explicit-${reason.name}',
                  occurredAt: now,
                  callId: _outgoingId,
                  endReason: reason,
                ),
              )
              .snapshot,
          audio: CallAudioControlState.idle,
        ),
      );
      await tester.pump();
      expect(find.text(label), findsOneWidget);
      expect(find.text('No answer'), findsNothing);
      expect(find.text('Call could not connect.'), findsNothing);
    });
  }

  testWidgets(
    'call projection attaches and signals readiness without a frame',
    (tester) async {
      final capability = _FakeForegroundCallCapability();
      addTearDown(capability.dispose);
      var attachmentCount = 0;
      var subscribedAtAttachment = false;
      tester.binding.attachRootWidget(
        tester.binding.wrapWithDefaultView(
          harness(
            capability: capability,
            onAttached: () {
              subscribedAtAttachment = capability._changes.hasListener;
              attachmentCount += 1;
            },
          ),
        ),
      );
      tester.binding.buildOwner!.buildScope(tester.binding.rootElement!);
      expect(attachmentCount, 0);
      // No pump/pumpWidget: the projection owner attaches while Android can
      // still be withholding frames behind keyguard.
      await tester.idle();
      expect(attachmentCount, 1);
      expect(subscribedAtAttachment, isTrue);
      expect(capability._changes.hasListener, isTrue);
      await tester.pump();
      await tester.pump();
      expect(attachmentCount, 1);
      expect(capability.actions, isEmpty);
    },
  );

  group('ForegroundCallOverlay projection', () {
    for (final direction in CallDirection.values) {
      for (final emptyName in [true, false]) {
        testWidgets('${direction.name} ${emptyName ? 'empty' : 'peer-ID'} '
            'username uses readable labels and never publishes ID metadata', (
          tester,
        ) async {
          final capability = _FakeLockedForegroundCallCapability();
          addTearDown(capability.dispose);
          const peerId = 'synthetic-contact-account';
          await tester.pumpWidget(
            harness(
              capability: capability,
              loadContactDisplayName: (_) async => emptyName ? '  ' : peerId,
            ),
          );
          void emit(CallState state) => capability.emit(
            _projection(
              now: now,
              callId: _activeId,
              peerId: peerId,
              direction: direction,
              state: state,
              incomingValidated: true,
            ),
          );
          emit(
            direction == CallDirection.incoming
                ? CallState.ringing
                : CallState.inviting,
          );
          await tester.pump();
          await tester.pump();
          expect(find.text(fallbackName), findsOneWidget);
          expect(find.text(peerId), findsNothing);
          expect(capability.locked, isEmpty);

          emit(CallState.connected);
          await tester.pumpAndSettle();
          expect(find.byType(ActiveCallScreen), findsOneWidget);
          expect(find.text(fallbackName), findsOneWidget);
          expect(find.text(peerId), findsNothing);
          await tester.tap(find.byKey(const ValueKey('call-minimize')));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('call-return-bar')), findsOneWidget);
          expect(find.textContaining(fallbackName), findsOneWidget);
          expect(find.textContaining(peerId), findsNothing);
          // CallKit keeps its readable native default. A placeholder or peer
          // identifier must never become authenticated caller metadata.
          expect(capability.locked, isEmpty);
        });
      }
    }

    testWidgets('unresolved UI fallback never becomes native caller metadata', (
      tester,
    ) async {
      final capability = _FakeLockedForegroundCallCapability();
      final resolvedName = Completer<String?>();
      addTearDown(capability.dispose);
      await tester.pumpWidget(
        harness(
          capability: capability,
          loadContactDisplayName: (_) => resolvedName.future,
        ),
      );
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
      expect(find.text(fallbackName), findsOneWidget);
      expect(capability.locked, isEmpty);

      resolvedName.complete('Beta iPhone');
      await tester.pump();
      await tester.pump();
      expect(capability.locked.first.displayName, 'Beta iPhone');
    });

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
      CallEndReason.busy: 'On another call',
      CallEndReason.declined: 'Call declined',
      CallEndReason.noAnswer: 'No answer',
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

  testWidgets('a callee whose microphone is off is named, not shown as no '
      'answer or as the caller\'s own permission problem', (tester) async {
    final capability = _FakeForegroundCallCapability();
    addTearDown(capability.dispose);
    await tester.pumpWidget(
      harness(
        capability: capability,
        loadContactDisplayName: (_) async => 'Layla',
      ),
    );
    capability.emit(
      _projection(
        now: now,
        callId: _activeId,
        peerId: 'callee-peer',
        direction: CallDirection.outgoing,
        state: CallState.ringing,
      ),
    );
    await tester.pump();
    await tester.pump();
    capability.emit(
      _projection(
        now: now,
        callId: _activeId,
        peerId: 'callee-peer',
        direction: CallDirection.outgoing,
        state: CallState.ended,
        endReason: CallEndReason.remotePermissionDenied,
      ),
    );
    await tester.pump();

    expect(
      find.text("Layla can't take calls right now. Their microphone is off."),
      findsOneWidget,
    );
    expect(find.text('No answer'), findsNothing);
    expect(
      find.text('Microphone permission is needed to make calls.'),
      findsNothing,
    );
  });

  group('microphone denial notice', () {
    Future<void> endWithPermissionDenied(
      WidgetTester tester,
      _FakeForegroundCallCapability capability,
    ) async {
      capability.emit(
        _projection(
          now: now,
          callId: _activeId,
          peerId: 'active-peer',
          direction: CallDirection.outgoing,
          state: CallState.ended,
          endReason: CallEndReason.permissionDenied,
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets(
      'a permanently denied mic offers Settings instead of failing silently',
      (tester) async {
        final capability = _FakeForegroundCallCapability();
        addTearDown(capability.dispose);
        final gateway = FakeMicPermissionGateway()
          ..currentStatus = MicPermissionStatus.permanentlyDenied;
        await tester.pumpWidget(
          harness(capability: capability, micPermission: gateway),
        );

        await endWithPermissionDenied(tester, capability);

        expect(
          find.text(
            'Microphone access is off for MKnoon. Turn it on in Settings to '
            'make and answer calls.',
          ),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey('foreground-call-open-settings')),
        );
        await tester.pump();
        expect(gateway.openAppSettingsCallCount, 1);
        expect(gateway.requestCallCount, 0);
      },
    );

    testWidgets(
      'an answered incoming call with a permanently denied mic offers Settings',
      (tester) async {
        final capability = _FakeForegroundCallCapability();
        addTearDown(capability.dispose);
        final gateway = FakeMicPermissionGateway()
          ..currentStatus = MicPermissionStatus.permanentlyDenied;
        await tester.pumpWidget(
          harness(capability: capability, micPermission: gateway),
        );
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
        await tester.pump();
        expect(capability.actions, <_RecordedAction>[
          _RecordedAction('answer', _incomingId),
        ]);

        capability.emit(
          _projection(
            now: now,
            callId: _incomingId,
            peerId: 'incoming-peer',
            direction: CallDirection.incoming,
            state: CallState.ended,
            incomingValidated: true,
            endReason: CallEndReason.permissionDenied,
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(
          find.text(
            'Microphone access is off for MKnoon. Turn it on in Settings to '
            'make and answer calls.',
          ),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey('foreground-call-open-settings')),
        );
        await tester.pump();
        expect(gateway.openAppSettingsCallCount, 1);
      },
    );

    testWidgets('a mic that can still be asked keeps the plain notice', (
      tester,
    ) async {
      final capability = _FakeForegroundCallCapability();
      addTearDown(capability.dispose);
      final gateway = FakeMicPermissionGateway()
        ..currentStatus = MicPermissionStatus.denied;
      await tester.pumpWidget(
        harness(capability: capability, micPermission: gateway),
      );

      await endWithPermissionDenied(tester, capability);

      expect(
        find.text('Microphone permission is needed to make calls.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('foreground-call-open-settings')),
        findsNothing,
      );
      expect(gateway.requestCallCount, 0);
    });

    testWidgets('a mic granted in Settings meanwhile keeps the plain notice', (
      tester,
    ) async {
      final capability = _FakeForegroundCallCapability();
      addTearDown(capability.dispose);
      final gateway = FakeMicPermissionGateway()
        ..currentStatus = MicPermissionStatus.granted;
      await tester.pumpWidget(
        harness(capability: capability, micPermission: gateway),
      );

      await endWithPermissionDenied(tester, capability);

      expect(
        find.byKey(const ValueKey('foreground-call-open-settings')),
        findsNothing,
      );
    });
  });

  testWidgets('media failure notice distinguishes a dropped connected call', (
    tester,
  ) async {
    final capability = _FakeForegroundCallCapability();
    addTearDown(capability.dispose);
    await tester.pumpWidget(harness(capability: capability));

    // Terminal projection may be the first one observed after returning to the
    // app. The canonical connection timestamp, not widget history, owns this.
    capability.emit(
      _projection(
        now: now,
        callId: _activeId,
        peerId: 'active-peer',
        direction: CallDirection.outgoing,
        state: CallState.ended,
        connectedAt: now.subtract(const Duration(seconds: 30)),
        endReason: CallEndReason.mediaFailed,
      ),
    );
    await tester.pump();

    expect(find.text('Call dropped · 00:30'), findsOneWidget);
    expect(find.text('Call audio could not start.'), findsNothing);
  });

  // VUI7 owner-approved persistence supersedes the six-second expiry only.
  testWidgets('terminal notice persists without changing retained navigation', (
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
      findsOneWidget,
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
    'modal call semantics hide background actions until terminal dismissal',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final capability = _FakeForegroundCallCapability();
        addTearDown(capability.dispose);
        var backgroundActions = 0;
        var retryCalls = 0;
        final health = PushRegistrationHealthNotifier();
        addTearDown(health.dispose);
        health.publish(
          PushRegistrationHealthRecord.retrying(
            reason: PushRegistrationHealthReason.registrationFailed,
            consecutiveFailures: 3,
            firstFailureAt: now,
            lastAttemptAt: now,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => ForegroundCallOverlay(
              capability: capability,
              now: () => now,
              loadContactDisplayName: (_) async => 'Local contact',
              child: PushRegistrationHealthSurface(
                healthListenable: health,
                onRetry: () => retryCalls++,
                onOpenNotificationSettings: () {},
                child: child!,
              ),
            ),
            home: Scaffold(
              body: Column(
                children: [
                  TextButton(
                    onPressed: () => backgroundActions++,
                    child: const Text('Start voice call'),
                  ),
                  TextButton(
                    onPressed: () => backgroundActions++,
                    child: const Text('Start voice recording'),
                  ),
                  const Text('Private conversation history'),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        const backgroundLabels = [
          'Start voice call',
          'Start voice recording',
          'Private conversation history',
          'Retry',
        ];
        for (final label in backgroundLabels) {
          expect(find.semantics.byLabel(label), findsOneWidget);
        }
        final warning = find.semantics.byLabel(
          RegExp('Notifications need attention'),
        );
        expect(warning, findsOneWidget);

        capability.emit(
          _projection(
            now: now,
            callId: _activeId,
            peerId: 'active-peer',
            direction: CallDirection.incoming,
            incomingValidated: true,
            state: CallState.connected,
            audio: _audio(),
          ),
        );
        await tester.pump();
        for (final label in backgroundLabels) {
          expect(find.semantics.byLabel(label), findsNothing);
          expect(find.text(label), findsOneWidget);
        }
        expect(warning, findsNothing);
        for (final label in ['Mute', 'Speaker', 'End']) {
          final node = find.semantics.byLabel(label).evaluate().single;
          expect(
            node.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
          );
        }
        tester.semantics.tap(find.semantics.byLabel('Mute'));
        await tester.pump();
        expect(capability.actions, [
          _RecordedAction('setMuted', _activeId, value: true),
        ]);
        expect(backgroundActions, 0);
        expect(retryCalls, 0);

        capability.emit(
          _projection(
            now: now,
            callId: _activeId,
            peerId: 'active-peer',
            direction: CallDirection.incoming,
            incomingValidated: true,
            state: CallState.ended,
          ),
        );
        await tester.pump();
        for (final label in backgroundLabels) {
          expect(find.semantics.byLabel(label), findsNothing);
        }
        expect(warning, findsNothing);
        await tester.tap(find.byTooltip('Dismiss call status'));
        await tester.pump();
        for (final label in backgroundLabels) {
          expect(find.semantics.byLabel(label), findsOneWidget);
        }
        expect(warning, findsOneWidget);
        tester.semantics.tap(find.semantics.byLabel('Retry'));
        await tester.pump();
        expect(retryCalls, 1);
        tester.semantics.tap(find.semantics.byLabel('Start voice recording'));
        await tester.pump();
        expect(backgroundActions, 1);
      } finally {
        semantics.dispose();
      }
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

  testWidgets(
    'covered route animations pause during calls and resume without losing route state',
    (tester) async {
      final capability = _FakeForegroundCallCapability();
      addTearDown(capability.dispose);
      final retainedKey = GlobalKey<_RetainedAnimationState>();
      await tester.pumpWidget(
        harness(
          capability: capability,
          child: _RetainedAnimation(key: retainedKey),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final retained = retainedKey.currentState!;
      expect(retained.ticks, greaterThan(0));

      for (final state in [
        CallState.ringing,
        CallState.connected,
        CallState.ended,
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
        final ticksWhileCovered = retained.ticks;
        await tester.pump(const Duration(milliseconds: 250));
        expect(retained.ticks, ticksWhileCovered, reason: state.name);
        expect(retainedKey.currentState, same(retained));
      }

      await tester.tap(find.byTooltip('Dismiss call status'));
      await tester.pump();
      final ticksAfterDismiss = retained.ticks;
      await tester.pump(const Duration(milliseconds: 100));
      expect(retained.ticks, greaterThan(ticksAfterDismiss));
      expect(retainedKey.currentState, same(retained));
      expect(capability.actions, isEmpty);
    },
  );

  testWidgets('minimized bar removes its consumed top inset from the route', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.padding = FakeViewPadding(top: 44);
    tester.view.viewPadding = FakeViewPadding(top: 44);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    final capability = _FakeForegroundCallCapability();
    addTearDown(capability.dispose);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      harness(
        capability: capability,
        child: Navigator(
          key: navigator,
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('Chat')),
              body: const Text('Retained chat'),
            ),
          ),
        ),
      ),
    );
    final retainedNavigator = navigator.currentState;
    capability.emit(
      _projection(
        now: now,
        callId: _outgoingId,
        peerId: 'outgoing-peer',
        direction: CallDirection.outgoing,
        state: CallState.connected,
        audio: _audio(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('call-minimize')));
    await tester.pumpAndSettle();
    final bar = find.byKey(const ValueKey('call-return-bar'));
    final toolbar = find.descendant(
      of: find.byType(AppBar),
      matching: find.byType(NavigationToolbar),
    );
    expect(tester.getTopLeft(toolbar).dy, tester.getBottomLeft(bar).dy);
    expect(tester.getSize(find.byType(AppBar)).height, kToolbarHeight);
    expect(navigator.currentState, same(retainedNavigator));
    capability.emit(null);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(toolbar).dy, 44);
    expect(navigator.currentState, same(retainedNavigator));
  });

  testWidgets(
    'minimize permits text and restores modal focus on return; reconnect and end keep canonical state',
    (tester) async {
      final capability = _FakeForegroundCallCapability();
      addTearDown(capability.dispose);
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        harness(
          capability: capability,
          child: Scaffold(
            body: TextField(
              focusNode: focus,
              decoration: const InputDecoration(labelText: 'Chat text'),
            ),
          ),
        ),
      );
      void emit(CallState state) => capability.emit(
        _projection(
          now: now,
          callId: _outgoingId,
          peerId: 'outgoing-peer',
          direction: CallDirection.outgoing,
          state: state,
          audio: _audio(muted: true),
        ),
      );
      emit(CallState.connected);
      await tester.pumpAndSettle();
      expect(find.semantics.byLabel('Chat text'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('call-minimize')));
      await tester.pumpAndSettle();
      expect(find.byType(ActiveCallScreen), findsNothing);
      expect(find.byKey(const ValueKey('call-return-bar')), findsOneWidget);
      expect(find.semantics.byLabel('Chat text'), findsOneWidget);
      // Accessibility tools tap the centre of the node bounds. The node must
      // be the bar itself, not the whole screen.
      final barRect = tester.getRect(
        find.byKey(const ValueKey('call-return-bar')),
      );
      final barNode = tester.getSemantics(
        find.bySemanticsLabel(RegExp('^Return to call,')),
      );
      expect(_globalSemanticsRect(tester, barNode), barRect);
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'Synthetic address');
      expect(focus.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      emit(CallState.reconnecting);
      await tester.pump();
      expect(find.byKey(const ValueKey('call-return-bar')), findsOneWidget);
      expect(find.textContaining('00:30'), findsOneWidget);
      tester.semantics.tap(find.semantics.byLabel(RegExp('^Return to call,')));
      await tester.pumpAndSettle();
      expect(find.byType(ActiveCallScreen), findsOneWidget);
      expect(find.text('Synthetic address'), findsOneWidget);
      expect(focus.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(find.byTooltip('Unmute'), findsOneWidget);
      expect(capability.actions, isEmpty);
      await tester.tap(find.byKey(const ValueKey('call-minimize')));
      emit(CallState.ended);
      await tester.pump();
      expect(find.byKey(const ValueKey('call-return-bar')), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets(
    'active output picker shows distinct same-class devices through the canonical capability',
    (tester) async {
      final capability = _PickerCapability();
      addTearDown(capability.dispose);
      await tester.pumpWidget(harness(capability: capability));
      capability.emit(
        _projection(
          now: now,
          callId: _outgoingId,
          peerId: 'outgoing-peer',
          direction: CallDirection.outgoing,
          state: CallState.connected,
          audio: _audio(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('call-audio-output')));
      await tester.pumpAndSettle();
      expect(find.text('Synthetic headset A'), findsOneWidget);
      expect(find.text('Synthetic headset B'), findsOneWidget);
      await tester.tap(find.text('Synthetic headset B'));
      await tester.pumpAndSettle();
      expect(capability.selectedIds, ['synthetic-b']);
      expect(capability.actions, isEmpty);
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

class _RetainedAnimation extends StatefulWidget {
  const _RetainedAnimation({super.key});

  @override
  State<_RetainedAnimation> createState() => _RetainedAnimationState();
}

class _RetainedAnimationState extends State<_RetainedAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;
  int ticks = 0;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(() => ticks += 1);
    _animation.repeat();
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
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
  DateTime? connectedAt,
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
    connectedAt:
        connectedAt ??
        (state == CallState.connected || state == CallState.reconnecting
            ? now.subtract(const Duration(seconds: 30))
            : null),
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

class _FakeForegroundCallCapability implements ForegroundCallCapability {
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

final class _FakeLockedForegroundCallCapability
    extends _FakeForegroundCallCapability
    implements LockedCallPresentationPort {
  final locked = <LockedCallPresentation>[];

  @override
  Future<void> updateLockedPresentation(
    CallId callId,
    LockedCallPresentation presentation,
  ) async {
    locked.add(presentation);
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

class _PickerCapability extends _FakeForegroundCallCapability
    implements ForegroundCallAudioPickerCapability {
  final selectedIds = <String>[];
  @override
  Future<List<CallAudioOutputDevice>> outputDevices(CallId callId) async => [
    const CallAudioOutputDevice(
      id: 'synthetic-a',
      name: 'Synthetic headset A',
      route: CallAudioOutputRoute.bluetooth,
      selected: true,
    ),
    const CallAudioOutputDevice(
      id: 'synthetic-b',
      name: 'Synthetic headset B',
      route: CallAudioOutputRoute.bluetooth,
      selected: false,
    ),
  ];
  @override
  Future<ForegroundCallActionResult> selectOutputDevice(
    CallId callId,
    String id,
  ) async {
    selectedIds.add(id);
    return ForegroundCallActionResult.applied;
  }
}

Rect _globalSemanticsRect(WidgetTester tester, SemanticsNode node) {
  var rect = node.rect;
  for (SemanticsNode? n = node; n != null; n = n.parent) {
    final transform = n.transform;
    if (transform != null) rect = MatrixUtils.transformRect(transform, rect);
  }
  final ratio = tester.view.devicePixelRatio;
  return Rect.fromLTRB(
    rect.left / ratio,
    rect.top / ratio,
    rect.right / ratio,
    rect.bottom / ratio,
  );
}

final _vui7Now = DateTime.utc(2026, 11, 15, 12);

ForegroundCallProjection _vui7Terminal({
  CallMediaKind? media = CallMediaKind.video,
  CallId? id,
  bool connected = true,
  CallEndReason reason = CallEndReason.remoteHangup,
  CallDirection direction = CallDirection.outgoing,
}) => ForegroundCallProjection(
  session: CallSessionSnapshot.active(
    callId: id ?? _activeId,
    contactPeerId: 'vui7-peer',
    direction: direction,
    state: CallState.ended,
    callerAccountPeerId: direction == CallDirection.incoming
        ? 'vui7-peer'
        : 'local',
    callerDeviceId: direction == CallDirection.incoming ? 'remote' : 'device',
    startedAt: _vui7Now.subtract(const Duration(minutes: 3)),
    ringingAt: _vui7Now.subtract(const Duration(minutes: 2)),
    connectedAt: connected
        ? _vui7Now.subtract(const Duration(seconds: 65))
        : null,
    endedAt: _vui7Now,
    endReason: reason,
    incomingValidated: direction == CallDirection.incoming,
  ),
  audio: CallAudioControlState.idle,
  terminalMedia: media,
);

class _Vui7Foreground extends _FakeForegroundCallCapability {
  // Production emits terminal once while current is already null.
  void terminal(ForegroundCallProjection value) {
    _current = null;
    _changes.add(value);
  }

  void setWithoutStream(ForegroundCallProjection? value) => _current = value;
}

class _Vui7Retry {
  final calls = <(String, CallMediaKind)>[];
  final fences = <bool Function()>[];
  Completer<OutgoingCallStartResult>? held;
  OutgoingCallStartResult result = OutgoingCallStartResult.unavailable;

  Future<OutgoingCallStartResult> call(
    String peerId, {
    required CallMediaKind media,
    required bool Function() isCurrent,
  }) {
    // Record every dispatch: this fake does not hide absent UI ownership guards.
    calls.add((peerId, media));
    fences.add(isCurrent);
    return held?.future.timeout(const Duration(seconds: 5)) ??
        Future.value(result);
  }
}

Widget _vui7App(
  _Vui7Foreground capability,
  _Vui7Retry retry, {
  String language = 'en',
  double scale = 1,
  ForegroundCallBackGuard? backGuard,
  MicPermissionGateway? micPermission,
  Future<void> Function(String peerId)? onMessage,
}) => MaterialApp(
  locale: Locale(language),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: ThemeData(extensions: const [BackgroundReadableColors.dark]),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: ForegroundCallOverlay(
    capability: capability,
    onCallAgain: retry.call,
    onMessage: onMessage ?? (_) async {},
    backGuard: backGuard,
    micPermission: micPermission,
    loadContactDisplayName: (_) async => 'Layla',
    now: () => _vui7Now,
    child: const Scaffold(body: Text('VUI7 retained route')),
  ),
);

Future<void> _vui7Draw(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

Future<void> _vui7With(
  WidgetTester tester,
  Future<void> Function(_Vui7Foreground, _Vui7Retry, AppLocalizations) body, {
  String language = 'en',
  double scale = 1,
  ForegroundCallBackGuard? backGuard,
  MicPermissionGateway? micPermission,
  Future<void> Function(String peerId)? onMessage,
}) async {
  final cap = _Vui7Foreground();
  final retry = _Vui7Retry();
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 844);
  backGuard?.attach();
  try {
    await tester.pumpWidget(
      _vui7App(
        cap,
        retry,
        language: language,
        scale: scale,
        backGuard: backGuard,
        micPermission: micPermission,
        onMessage: onMessage,
      ),
    );
    await _vui7Draw(tester);
    await body(cap, retry, lookupAppLocalizations(Locale(language)));
    expect(tester.takeException(), isNull);
  } finally {
    if (retry.held != null && !retry.held!.isCompleted) {
      retry.held!.complete(OutgoingCallStartResult.canceled);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    backGuard?.detach();
    await tester.runAsync(
      () => cap.dispose().timeout(const Duration(seconds: 5)),
    );
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }
}

CallControlButton _vui7Button(WidgetTester tester, String label) {
  final text = find.text(label);
  expect(text, findsOneWidget);
  final button = find.ancestor(
    of: text,
    matching: find.byType(CallControlButton),
  );
  expect(button, findsOneWidget);
  return tester.widget<CallControlButton>(button);
}

void _bl61OutcomeTests() {
  final terminalNotice = find.byKey(
    const ValueKey('foreground-call-terminal-notice'),
  );

  for (final media in CallMediaKind.values) {
    testWidgets(
      'BL61 ${media.name} end uses the call profile and same-type retry',
      (tester) async {
        await _vui7With(tester, (cap, retry, l10n) async {
          cap.terminal(_vui7Terminal(media: media));
          await _vui7Draw(tester);

          final status = l10n.call_row_with_duration(l10n.call_ended, '01:05');
          expect(find.text(status), findsOneWidget);
          expect(find.text(l10n.call_ended), findsNothing);
          expect(find.text(l10n.call_end_ended), findsNothing);
          expect(find.text('01:05'), findsNothing);
          final avatar = find.descendant(
            of: terminalNotice,
            matching: find.byType(UserAvatar),
          );
          expect(tester.widget<UserAvatar>(avatar).peerId, 'vui7-peer');
          expect(tester.getSize(avatar), const Size.square(112));
          expect(find.byType(Texture), findsNothing);
          if (media == CallMediaKind.video) {
            expect(
              Theme.of(tester.element(avatar)).brightness,
              Brightness.dark,
            );
          }

          final again = find.text(l10n.call_video_call_again).hitTestable();
          expect(again, findsOneWidget);
          await tester.tap(again);
          await _vui7Draw(tester);
          expect(retry.calls, [('vui7-peer', media)]);
          expect(cap.actions, isEmpty);
        });
      },
    );
  }

  testWidgets('BL61 normal end closes in four seconds on the retained route', (
    tester,
  ) async {
    await _vui7With(tester, (cap, _, _) async {
      cap.terminal(_vui7Terminal());
      await _vui7Draw(tester);
      expect(terminalNotice, findsOneWidget);

      await tester.pump(const Duration(milliseconds: 3999));
      expect(terminalNotice, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      expect(terminalNotice, findsNothing);
      expect(find.text('VUI7 retained route').hitTestable(), findsOneWidget);
      expect(cap.actions, isEmpty);
    });
  });

  testWidgets('BL61 screen reader pauses the remaining normal end countdown', (
    tester,
  ) async {
    final dispatcher = tester.platformDispatcher;
    addTearDown(dispatcher.clearAccessibilityFeaturesTestValue);
    await _vui7With(tester, (cap, _, _) async {
      cap.terminal(_vui7Terminal());
      await _vui7Draw(tester);
      await tester.pump(const Duration(seconds: 1));

      dispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(accessibleNavigation: true);
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      expect(terminalNotice, findsOneWidget);

      dispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 2999));
      expect(terminalNotice, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      expect(terminalNotice, findsNothing);
    });
  });

  testWidgets('BL61 Back dismisses the end screen inside the app', (
    tester,
  ) async {
    var backgrounds = 0;
    final backGuard = ForegroundCallBackGuard(
      moveAppToBackground: () async {
        backgrounds++;
      },
      publishCallOwnsBack: (_) async {},
    );
    await _vui7With(tester, (cap, _, _) async {
      cap.terminal(_vui7Terminal());
      await _vui7Draw(tester);
      expect(terminalNotice, findsOneWidget);

      expect(
        await tester.binding.handlePopRoute().timeout(
          const Duration(seconds: 3),
        ),
        isTrue,
      );
      await _vui7Draw(tester);
      expect(terminalNotice, findsNothing);
      expect(find.text('VUI7 retained route').hitTestable(), findsOneWidget);
      expect(backgrounds, 0);
    }, backGuard: backGuard);
  });

  for (final (reason, connected, status, actions) in [
    (
      CallEndReason.noAnswer,
      false,
      'No answer',
      ['Call again', 'Message', 'Close'],
    ),
    (
      CallEndReason.busy,
      false,
      'On another call',
      ['Message', 'Call again', 'Close'],
    ),
    (CallEndReason.declined, false, 'Call declined', ['Message', 'Close']),
    (
      CallEndReason.mediaFailed,
      true,
      'Call dropped · 01:05',
      ['Call again', 'Message', 'Close'],
    ),
    (
      CallEndReason.signalingFailed,
      false,
      'Call could not connect.',
      ['Call again', 'Close'],
    ),
  ]) {
    testWidgets('BL61 ${reason.name} stays and offers the approved actions', (
      tester,
    ) async {
      await _vui7With(tester, (cap, _, l10n) async {
        cap.terminal(_vui7Terminal(reason: reason, connected: connected));
        await _vui7Draw(tester);
        await tester.pump(const Duration(seconds: 5));
        expect(terminalNotice, findsOneWidget);
        expect(find.text(status), findsOneWidget);
        expect(find.text(l10n.call_ended), findsNothing);

        for (final label in ['Call again', 'Message', 'Close']) {
          final action = find
              .descendant(of: terminalNotice, matching: find.text(label))
              .hitTestable();
          expect(
            action,
            actions.contains(label) ? findsOneWidget : findsNothing,
          );
        }

        for (var index = 1; index < actions.length; index++) {
          final previous = tester.getCenter(find.text(actions[index - 1]));
          final current = tester.getCenter(find.text(actions[index]));
          expect(current.dx, greaterThan(previous.dx));
        }

        await tester.tap(find.text(l10n.call_video_close));
        await _vui7Draw(tester);
        expect(terminalNotice, findsNothing);
      });
    });
  }

  testWidgets('BL61 a missed incoming call quietly dismisses its ring screen', (
    tester,
  ) async {
    const bound = Duration(seconds: 3);
    await _vui7With(tester, (cap, _, l10n) async {
      cap.emit(
        _projection(
          now: _vui7Now,
          callId: _incomingId,
          peerId: 'vui7-peer',
          direction: CallDirection.incoming,
          state: CallState.ringing,
          incomingValidated: true,
        ),
      );
      await _vui7Draw(tester).timeout(bound);
      expect(find.text(l10n.call_answer), findsOneWidget);

      cap.terminal(
        _vui7Terminal(
          id: _incomingId,
          media: CallMediaKind.audio,
          connected: false,
          reason: CallEndReason.noAnswer,
          direction: CallDirection.incoming,
        ),
      );
      await _vui7Draw(tester).timeout(bound);
      expect(find.text(l10n.call_answer), findsNothing);
      expect(terminalNotice, findsNothing);
      expect(find.text('VUI7 retained route').hitTestable(), findsOneWidget);
    }).timeout(bound);
  });

  testWidgets('BL61 in-flight retry pauses the normal end countdown', (
    tester,
  ) async {
    await _vui7With(tester, (cap, retry, l10n) async {
      retry.held = Completer<OutgoingCallStartResult>();
      cap.terminal(_vui7Terminal());
      await _vui7Draw(tester);
      expect(find.text(l10n.call_end_closes_in(4)), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.text(l10n.call_video_call_again));
      await _vui7Draw(tester);
      await tester.pump(const Duration(seconds: 4));
      expect(terminalNotice, findsOneWidget);
      expect(retry.fences.single(), isTrue);

      retry.held!.complete(OutgoingCallStartResult.unavailable);
      await _vui7Draw(tester);
      expect(find.text(l10n.call_end_closes_in(3)), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 2999));
      expect(terminalNotice, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      expect(terminalNotice, findsNothing);
    });
  });

  testWidgets(
    'BL61 Message closes before navigation and rejects duplicate taps',
    (tester) async {
      final opened = <String>[];
      final navigation = Completer<void>();
      try {
        await _vui7With(
          tester,
          (cap, retry, l10n) async {
            cap.terminal(
              _vui7Terminal(reason: CallEndReason.busy, connected: false),
            );
            await _vui7Draw(tester);
            final open = _vui7Button(
              tester,
              l10n.contact_profile_message_button,
            ).onPressed!;
            open();
            open();
            await _vui7Draw(tester);
            expect(opened, ['vui7-peer']);
            expect(terminalNotice, findsNothing);
            expect(
              find.text('VUI7 retained route').hitTestable(),
              findsOneWidget,
            );
            expect(retry.calls, isEmpty);
            expect(cap.actions, isEmpty);
            navigation.complete();
            await _vui7Draw(tester);
          },
          onMessage: (peer) {
            opened.add(peer);
            return navigation.future.timeout(const Duration(seconds: 3));
          },
        );
      } finally {
        if (!navigation.isCompleted) navigation.complete();
      }
    },
  );

  testWidgets('BL61 permanently denied local mic offers Settings and Close', (
    tester,
  ) async {
    final gateway = FakeMicPermissionGateway()
      ..currentStatus = MicPermissionStatus.permanentlyDenied;
    await _vui7With(tester, (cap, retry, l10n) async {
      cap.terminal(
        _vui7Terminal(connected: false, reason: CallEndReason.permissionDenied),
      );
      await _vui7Draw(tester);
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('Microphone is off'), findsOneWidget);
      expect(find.text(l10n.call_end_permission_settings), findsOneWidget);
      final settings = find.text(l10n.call_video_open_settings).hitTestable();
      expect(settings, findsOneWidget);
      expect(find.text(l10n.call_video_call_again), findsNothing);
      expect(
        tester.getCenter(settings).dx,
        lessThan(tester.getCenter(find.text(l10n.call_video_close)).dx),
      );
      await tester.tap(settings);
      await _vui7Draw(tester);
      expect(gateway.openAppSettingsCallCount, 1);
      expect(gateway.requestCallCount, 0);
      expect(retry.calls, isEmpty);
    }, micPermission: gateway);
  });

  testWidgets('BL61 minimized end shows a four-second banner without a modal', (
    tester,
  ) async {
    await _vui7With(tester, (cap, _, l10n) async {
      cap.emit(
        _projection(
          now: _vui7Now,
          callId: _activeId,
          peerId: 'vui7-peer',
          direction: CallDirection.outgoing,
          state: CallState.connected,
          connectedAt: _vui7Now.subtract(const Duration(seconds: 65)),
          audio: _audio(),
        ),
      );
      await _vui7Draw(tester);
      await tester.tap(find.byKey(const ValueKey('call-minimize')));
      await _vui7Draw(tester);
      final liveBar = find.byKey(const ValueKey('call-return-bar'));
      expect(liveBar, findsOneWidget);
      final liveBarRect = tester.getRect(liveBar);

      cap.terminal(_vui7Terminal());
      await _vui7Draw(tester);
      final status = l10n.call_row_with_duration(l10n.call_ended, '01:05');
      final banner = find.text('Layla · $status');
      expect(banner, findsOneWidget);
      expect(
        tester.getRect(banner).center.dy,
        closeTo(liveBarRect.center.dy, 1),
      );
      expect(terminalNotice, findsNothing);
      expect(find.text('VUI7 retained route').hitTestable(), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 3999));
      expect(banner, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      expect(banner, findsNothing);
      expect(cap.actions, isEmpty);
    });
  });

  testWidgets('BL61 an older end timer cannot dismiss a successor outcome', (
    tester,
  ) async {
    await _vui7With(tester, (cap, _, l10n) async {
      cap.terminal(_vui7Terminal());
      await _vui7Draw(tester);
      await tester.pump(const Duration(seconds: 2));

      cap.terminal(
        _vui7Terminal(
          id: _incomingId,
          connected: false,
          reason: CallEndReason.noAnswer,
        ),
      );
      await _vui7Draw(tester);
      await tester.pump(const Duration(seconds: 3));
      expect(terminalNotice, findsOneWidget);
      expect(find.text(l10n.call_row_no_answer), findsOneWidget);
    });
  });
}

void _vui7Tests() {
  for (final media in CallMediaKind.values) {
    testWidgets(
      'VUI7 persistent ${media.name} dropped call has fixed identity and fresh retry input',
      (tester) async {
        await _vui7With(tester, (cap, retry, l10n) async {
          cap.terminal(
            _vui7Terminal(media: media, reason: CallEndReason.mediaFailed),
          );
          await _vui7Draw(tester);
          final again = _vui7Button(tester, l10n.call_video_call_again);
          expect(again.onPressed, isNotNull);
          expect(cap.current, isNull);
          expect(find.text('Layla'), findsOneWidget);
          final status = l10n.call_row_with_duration(
            l10n.call_outcome_dropped,
            '01:05',
          );
          expect(find.text(status), findsOneWidget);
          expect(find.byType(Texture), findsNothing);
          await tester.pump(const Duration(seconds: 61));
          expect(find.text(status), findsOneWidget);
          expect(find.text(l10n.call_video_call_again), findsOneWidget);
          again.onPressed!();
          await _vui7Draw(tester);
          expect(retry.calls, [('vui7-peer', media)]);
          expect(cap.actions, isEmpty);
          expect(find.text(status), findsOneWidget);
          _vui7Button(tester, l10n.call_video_close).onPressed!();
          await _vui7Draw(tester);
          expect(
            find.byKey(const ValueKey('foreground-call-terminal-notice')),
            findsNothing,
          );
          expect(
            find.text('VUI7 retained route').hitTestable(),
            findsOneWidget,
          );
        });
      },
      timeout: const Timeout.factor(1),
    );
  }

  testWidgets(
    'VUI7 never connected omits duration and unknown media cannot retry',
    (tester) async {
      await _vui7With(tester, (cap, retry, l10n) async {
        cap.terminal(
          _vui7Terminal(
            connected: false,
            media: null,
            reason: CallEndReason.noAnswer,
          ),
        );
        await _vui7Draw(tester);
        _vui7Button(tester, l10n.call_video_close);
        expect(find.text(l10n.call_row_no_answer), findsOneWidget);
        expect(find.text('00:00'), findsNothing);
        expect(find.text('01:05'), findsNothing);
        final again = find.text(l10n.call_video_call_again);
        if (again.evaluate().isNotEmpty) {
          expect(
            _vui7Button(tester, l10n.call_video_call_again).onPressed,
            isNull,
          );
        }
        expect(retry.calls, isEmpty);
      });
    },
    timeout: const Timeout.factor(1),
  );

  for (final invalidation in [
    'successor before stream',
    'successor then null',
    'withdrawal',
    'replacement',
    'dispose',
  ]) {
    testWidgets('VUI7 retained terminal actions reject $invalidation', (
      tester,
    ) async {
      await _vui7With(tester, (cap, retry, l10n) async {
        cap.terminal(_vui7Terminal());
        await _vui7Draw(tester);
        final again = _vui7Button(
          tester,
          l10n.call_video_call_again,
        ).onPressed!;
        final close = _vui7Button(tester, l10n.call_video_close).onPressed!;
        final successor = _vui7Terminal(id: _incomingId);
        _Vui7Foreground? replacement;
        try {
          switch (invalidation) {
            case 'successor before stream':
            case 'successor then null':
              cap.setWithoutStream(_projection(
                now: _vui7Now,
                callId: _incomingId,
                peerId: 'successor-peer',
                direction: CallDirection.incoming,
                state: CallState.connected,
              ));
              again(); // Detect the latest owner before stream delivery.
              expect(retry.calls, isEmpty);
              if (invalidation == 'successor then null') {
                cap.setWithoutStream(null);
              }
            case 'withdrawal':
              cap.emit(null);
              await _vui7Draw(tester);
            case 'replacement':
              replacement = _Vui7Foreground();
              await tester.pumpWidget(_vui7App(replacement, retry));
              replacement.terminal(successor);
              await _vui7Draw(tester);
            case 'dispose':
              await tester.pumpWidget(const SizedBox.shrink());
          }
          again();
          close();
          await _vui7Draw(tester);
          expect(retry.calls, isEmpty);
          expect(cap.actions, isEmpty);
          if (replacement != null) {
            expect(find.text(l10n.call_video_call_again), findsOneWidget);
          }
        } finally {
          if (replacement != null) {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.runAsync(
              () => replacement!.dispose().timeout(const Duration(seconds: 5)),
            );
          }
        }
      });
    }, timeout: const Timeout.factor(1));
  }

  for (final invalidation in ['Close', 'successor', 'background withdrawal']) {
    testWidgets('VUI7 duplicate and held retry fence survives $invalidation', (
      tester,
    ) async {
      await _vui7With(tester, (cap, retry, l10n) async {
        retry.held = Completer<OutgoingCallStartResult>();
        cap.terminal(_vui7Terminal());
        await _vui7Draw(tester);
        final again = _vui7Button(
          tester,
          l10n.call_video_call_again,
        ).onPressed!;
        again();
        again();
        await _vui7Draw(tester);
        expect(retry.calls, [('vui7-peer', CallMediaKind.video)]);
        expect(retry.fences.single(), isTrue);
        expect(
          _vui7Button(tester, l10n.call_video_call_again).onPressed,
          isNull,
        );
        if (invalidation == 'Close') {
          _vui7Button(tester, l10n.call_video_close).onPressed!();
        } else if (invalidation == 'successor') {
          cap.emit(_vui7Terminal(id: _incomingId));
        } else {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          cap.emit(null); // Canonical composition withdrawal on background.
        }
        await _vui7Draw(tester);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        expect(retry.fences.single(), isFalse);
        retry.held!.complete(OutgoingCallStartResult.started);
        await _vui7Draw(tester);
        expect(
          cap.actions,
          isEmpty,
        ); // Old completion never ends the successor.
        if (invalidation == 'successor') {
          expect(find.text(l10n.call_video_call_again), findsOneWidget);
        } else {
          expect(
            find.byKey(const ValueKey('foreground-call-terminal-notice')),
            findsNothing,
          );
        }
      });
    }, timeout: const Timeout.factor(1));
  }

  for (final language in ['en', 'de', 'ar']) {
    testWidgets('VUI7 $language 320px2x reason and actions remain reachable', (
      tester,
    ) async {
      await _vui7With(
        tester,
        (cap, retry, l10n) async {
          cap.terminal(_vui7Terminal(reason: CallEndReason.mediaFailed));
          await _vui7Draw(tester);
          _vui7Button(tester, l10n.call_video_call_again);
          final status = l10n.call_row_with_duration(
            l10n.call_outcome_dropped,
            '01:05',
          );
          for (final text in [
            status,
            l10n.call_video_close,
            l10n.call_video_call_again,
          ]) {
            final finder = find.text(text);
            expect(finder, findsOneWidget);
            await tester.ensureVisible(finder);
            await _vui7Draw(tester);
            final paragraph = tester.renderObject<RenderParagraph>(finder);
            expect(paragraph.didExceedMaxLines, isFalse);
            expect(
              paragraph.textDirection,
              language == 'ar' ? TextDirection.rtl : TextDirection.ltr,
            );
            final rect = tester.getRect(finder);
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(320));
            expect(rect.top, greaterThanOrEqualTo(0));
            expect(rect.bottom, lessThanOrEqualTo(844));
          }
          for (final label in [
            l10n.call_video_close,
            l10n.call_video_call_again,
          ]) {
            final finder = find.ancestor(
              of: find.text(label),
              matching: find.byType(CallControlButton),
            );
            await tester.ensureVisible(finder);
            await _vui7Draw(tester);
            final rect = tester.getRect(finder);
            expect(rect.width, greaterThanOrEqualTo(48));
            expect(rect.height, greaterThanOrEqualTo(48));
            expect(finder.hitTestable(), findsOneWidget);
          }
          final reasonNodes = find.semantics.byPredicate(
            (node) => node.label == status,
          );
          expect(reasonNodes, findsOneWidget);
          final reasonData = tester
              .getSemantics(find.text(status))
              .getSemanticsData();
          expect(reasonData.flagsCollection.isLiveRegion, isTrue);
          expect(find.byType(Texture), findsNothing);
        },
        language: language,
        scale: 2,
      );
    }, timeout: const Timeout.factor(1));
  }
}
