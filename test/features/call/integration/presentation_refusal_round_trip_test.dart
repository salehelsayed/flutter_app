import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/call/application/call_audio_controller.dart';
import 'package:flutter_app/features/call/application/call_cleanup_coordinator.dart';
import 'package:flutter_app/features/call/application/call_control_effect_executor.dart';
import 'package:flutter_app/features/call/application/call_coordinator.dart';
import 'package:flutter_app/features/call/application/call_endpoint_resolver.dart';
import 'package:flutter_app/features/call/application/call_history_projector.dart';
import 'package:flutter_app/features/call/application/call_signaling_context_store.dart';
import 'package:flutter_app/features/call/application/foreground_call_capability.dart';
import 'package:flutter_app/features/call/application/handle_incoming_call_signal.dart';
import 'package:flutter_app/features/call/application/missed_call_notifier.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_event.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_signal.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/infrastructure/call_trusted_roster_provider.dart';
import 'package:flutter_app/features/call/infrastructure/secure_call_envelope_codec.dart';
import 'package:flutter_app/features/call/presentation/foreground_call_overlay.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two real coordinators joined by the real codec and control executor. The
/// callee's native call surface refuses to ring; the only fakes are the
/// crypto, the roster, the transport write and the notification post.
const _nowMs = 2_000_000;
final _now = DateTime.fromMillisecondsSinceEpoch(_nowMs, isUtc: true);
final _callId = CallId.parse('22222222-2222-4222-8222-222222222222');
const _calleeHandle = '33333333-3333-4333-8333-333333333333';
const _callerHandle = '44444444-4444-4444-8444-444444444444';
const _callerAccount = 'caller-account';
const _callerDevice = 'caller-device';
const _calleeAccount = 'callee-account';
const _calleeDevice = 'callee-device';

void main() {
  testWidgets(
    'a callee whose call surface refuses to ring leaves one missed call and the caller reads "No answer"',
    (tester) async {
      final trip = (await tester.runAsync(_refuseAndDeliver))!;

      // Wire: the callee's terminate names the shared reason.
      expect(trip.terminate.event, CallSignalType.terminate);
      expect(trip.terminate.payload['reason'], 'no_answer');
      expect(trip.terminate.recipientDevicePeerId, _callerDevice);

      // Callee: a missed row and exactly one missed-call notification.
      final row = trip.calleeHistory.entries[_callId];
      expect(row?.direction, CallDirection.incoming);
      expect(row?.status, CallHistoryStatus.missed);
      expect(row?.terminalReason, CallEndReason.noAnswer);
      expect(trip.posted, <(String, String, String)>[
        (_callerAccount, 'Caller', 'Missed voice call'),
      ]);

      // Caller: the received terminate ends the outgoing call as no answer.
      expect(trip.callerOutcome, IncomingCallSignalOutcome.accepted);
      expect(trip.callerEnded.state, CallState.ended);
      expect(trip.callerEnded.endReason, CallEndReason.noAnswer);

      // Caller UI: the English notice for that end reason.
      await _pumpCallerOverlay(tester, trip.callerEnded);

      expect(find.text('No answer.'), findsOneWidget);
      expect(find.text('The contact is on another call.'), findsNothing);
    },
  );

  testWidgets(
    'a caller whose callee denied the microphone reads "No answer", never "on another call"',
    (tester) async {
      // The wire keeps permission_denied, so older callees still send it.
      final terminate = CallSignal.create(
        callId: _callId,
        messageId: '55555555-5555-4555-8555-555555555555',
        event: CallSignalType.terminate,
        senderAccountPeerId: _calleeAccount,
        senderDevicePeerId: _calleeDevice,
        recipientAccountPeerId: _callerAccount,
        recipientDevicePeerId: _callerDevice,
        senderSequence: 1,
        iceGeneration: 0,
        createdAtMs: _nowMs,
        expiresAtMs: _nowMs + 45_000,
        payload: const <String, Object?>{'reason': 'permission_denied'},
      );
      final caller = (await tester.runAsync(
        () => _deliverToCaller(terminate),
      ))!;

      expect(caller.outcome, IncomingCallSignalOutcome.accepted);
      expect(caller.ended.state, CallState.ended);
      expect(caller.ended.endReason, CallEndReason.noAnswer);

      await _pumpCallerOverlay(tester, caller.ended);

      expect(find.text('No answer.'), findsOneWidget);
      expect(find.text('The contact is on another call.'), findsNothing);
    },
  );
}

Future<void> _pumpCallerOverlay(
  WidgetTester tester,
  CallSessionSnapshot ended,
) async {
  final capability = _Capability();
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
      home: ForegroundCallOverlay(
        capability: capability,
        loadContactDisplayName: (_) async => 'Callee',
        now: () => _now,
        child: const SizedBox.expand(),
      ),
    ),
  );
  capability.emit(
    ForegroundCallProjection(session: ended, audio: CallAudioControlState.idle),
  );
  await tester.pump();
}

final class _RoundTrip {
  const _RoundTrip({
    required this.terminate,
    required this.calleeHistory,
    required this.posted,
    required this.callerOutcome,
    required this.callerEnded,
  });

  final CallSignal terminate;
  final _History calleeHistory;
  final List<(String, String, String)> posted;
  final IncomingCallSignalOutcome callerOutcome;
  final CallSessionSnapshot callerEnded;
}

Future<_RoundTrip> _refuseAndDeliver() async {
  final calleeHistory = _History();
  final posted = <(String, String, String)>[];
  final notifier = MissedCallNotifier(
    post:
        ({
          required String contactAccountPeerId,
          required String title,
          required String body,
        }) async {
          posted.add((contactAccountPeerId, title, body));
        },
    resolveContactName: (_) async => 'Caller',
    isSuppressed: (_) async => false,
    missedBody: 'Missed voice call',
    unknownCallerTitle: 'Someone',
  );
  final contextStore = CallSignalingContextStore();
  final port = _Port();
  final callee = CallCoordinator(
    reducer: const CallReducer(),
    cleanupCoordinator: CallCleanupCoordinator(const <CallCleanupStep>[]),
    historyProjector: CallHistoryProjector(
      calleeHistory,
      clock: () => _now,
      onTerminalProjected: (entry, inserted) =>
          unawaited(notifier.notifyTerminal(entry, inserted: inserted)),
    ),
    effectExecutor: CallControlEffectExecutor(
      contextStore: contextStore,
      signalingPort: port,
      clock: () => _now,
      idSource: _MessageIds().next,
    ),
    clock: () => _now,
    idSource: () => _callId,
  );
  final calleeCodec = SecureCallEnvelopeCodec(
    crypto: _Crypto(),
    nowMs: () => _nowMs,
  );
  final calleeHandler = HandleIncomingCallSignal(
    codec: calleeCodec,
    coordinator: callee,
    trustedRosterProvider: const _Roster(),
    localAuthorityProvider: () async => const CallLocalDeviceAuthority(
      accountPeerId: _calleeAccount,
      devicePeerId: _calleeDevice,
      mlKemSecretKey: 'callee-mlkem-secret',
    ),
    incomingCallPresenter: _RefusingPresenter(),
    networkEffectsAllowed: () => true,
    signalingContextObserver: contextStore,
  );
  final invite = CallSignal.create(
    callId: _callId,
    messageId: '11111111-1111-4111-8111-111111111111',
    event: CallSignalType.invite,
    senderAccountPeerId: _callerAccount,
    senderDevicePeerId: _callerDevice,
    recipientAccountPeerId: _calleeAccount,
    recipientDevicePeerId: _calleeDevice,
    senderSequence: 1,
    iceGeneration: 0,
    createdAtMs: _nowMs,
    expiresAtMs: _nowMs + 45_000,
  );
  final calleeOutcome = await calleeHandler.handle(
    IncomingCallSignalFrame(
      envelopeJson: await calleeCodec.encode(
        signal: invite,
        callHandle: _calleeHandle,
        recipientMlKemPublicKey: 'callee-mlkem-key',
        senderSigningPrivateKey: 'caller-signing-key',
      ),
      authenticatedTransportPeerId: _callerDevice,
      route: CallRouteClass.direct,
    ),
  );
  expect(calleeOutcome, IncomingCallSignalOutcome.rejected);
  await pumpEventQueue();
  final terminate = port.signals.single;

  await callee.dispose();
  final caller = await _deliverToCaller(terminate);
  return _RoundTrip(
    terminate: terminate,
    calleeHistory: calleeHistory,
    posted: posted,
    callerOutcome: caller.outcome,
    callerEnded: caller.ended,
  );
}

/// Delivers [terminate] to a real caller coordinator that is inviting.
Future<({IncomingCallSignalOutcome outcome, CallSessionSnapshot ended})>
_deliverToCaller(CallSignal terminate) async {
  final caller = CallCoordinator(
    reducer: const CallReducer(),
    cleanupCoordinator: CallCleanupCoordinator(const <CallCleanupStep>[]),
    historyProjector: CallHistoryProjector(_History(), clock: () => _now),
    effectExecutor: const NoopCallEffectExecutor(),
    clock: () => _now,
    idSource: () => _callId,
  );
  await caller.dispatch(
    CallEvent(
      type: CallEventType.place,
      eventId: 'caller-place',
      occurredAt: _now,
      callId: _callId,
      contactPeerId: _calleeAccount,
      localAccountPeerId: _callerAccount,
      localDeviceId: _callerDevice,
      remoteAccountPeerId: _calleeAccount,
      remoteDeviceId: _calleeDevice,
    ),
  );
  await caller.dispatch(
    CallEvent(
      type: CallEventType.outgoingInviteReady,
      eventId: 'caller-invite-ready',
      occurredAt: _now,
      callId: _callId,
      contactPeerId: _calleeAccount,
    ),
  );
  expect(caller.activeSession?.state, CallState.inviting);
  final callerCodec = SecureCallEnvelopeCodec(
    crypto: _Crypto(),
    nowMs: () => _nowMs,
  );
  final callerHandler = HandleIncomingCallSignal(
    codec: callerCodec,
    coordinator: caller,
    trustedRosterProvider: const _Roster(),
    localAuthorityProvider: () async => const CallLocalDeviceAuthority(
      accountPeerId: _callerAccount,
      devicePeerId: _callerDevice,
      mlKemSecretKey: 'caller-mlkem-secret',
    ),
    incomingCallPresenter: _RefusingPresenter(),
    networkEffectsAllowed: () => true,
  );
  final callerOutcome = await callerHandler.handle(
    IncomingCallSignalFrame(
      envelopeJson: await callerCodec.encode(
        signal: terminate,
        callHandle: _callerHandle,
        recipientMlKemPublicKey: 'caller-mlkem-key',
        senderSigningPrivateKey: 'callee-signing-key',
      ),
      authenticatedTransportPeerId: _calleeDevice,
      route: CallRouteClass.direct,
    ),
  );
  final ended = caller.lastSnapshot!;
  await caller.dispose();
  return (outcome: callerOutcome, ended: ended);
}

final class _RefusingPresenter implements IncomingCallPresenter {
  @override
  Future<bool> present(IncomingCallPresentation presentation) async => false;

  @override
  Future<void> dismiss(IncomingCallPresentation presentation) async {}
}

final class _Port implements CallControlSignalingPort {
  final List<CallSignal> signals = <CallSignal>[];

  @override
  Future<OutgoingCallSignalingPreparation> prepareOutgoingInvite(
    CallSessionSnapshot snapshot,
  ) async => throw UnimplementedError('the callee places no call here');

  @override
  Future<CallControlSendResult> send({
    required CallSignal signal,
    required String callHandle,
  }) async {
    signals.add(signal);
    return CallControlSendResult(
      directAccepted: true,
      mailboxStored: false,
      directRoute: CallRouteClass.direct,
      mailboxStoreSettled: Future<void>.value(),
    );
  }
}

final class _MessageIds {
  int _next = 0;

  CallId next() => CallId.parse(
    '99999999-9999-4999-8999-${(++_next).toRadixString(16).padLeft(12, '0')}',
  );
}

final class _Roster implements CallTrustedRosterProvider {
  const _Roster();

  @override
  Future<CallTrustedRosterSnapshot> loadForContact(String peerId) async =>
      throw UnimplementedError();

  @override
  Future<TrustedCallDeviceAuthority?> resolveAuthenticatedTransport(
    String transportPeerId,
  ) async => switch (transportPeerId) {
    _callerDevice => const TrustedCallDeviceAuthority(
      accountPeerId: _callerAccount,
      devicePeerId: _callerDevice,
      linked: true,
      deviceKeyEpoch: 1,
      signingPublicKey: 'caller-signing-key',
      mlKemPublicKey: 'caller-mlkem-key',
    ),
    _calleeDevice => const TrustedCallDeviceAuthority(
      accountPeerId: _calleeAccount,
      devicePeerId: _calleeDevice,
      linked: true,
      deviceKeyEpoch: 1,
      signingPublicKey: 'callee-signing-key',
      mlKemPublicKey: 'callee-mlkem-key',
    ),
    _ => null,
  };
}

/// Signatures are `base64(key:data)`, so a signing key verifies itself.
final class _Crypto implements CallEnvelopeCrypto {
  @override
  Future<CallCiphertext> encrypt({
    required String recipientMlKemPublicKey,
    required String plaintext,
  }) async => CallCiphertext(
    kem: base64Encode(utf8.encode('kem')),
    ciphertext: base64Encode(utf8.encode(plaintext)),
    nonce: base64Encode(utf8.encode('nonce')),
  );

  @override
  Future<String> decrypt({
    required String ownMlKemSecretKey,
    required CallCiphertext ciphertext,
  }) async => utf8.decode(base64Decode(ciphertext.ciphertext));

  @override
  Future<String> sign({
    required String senderSigningPrivateKey,
    required String canonicalData,
  }) async =>
      base64Encode(utf8.encode('$senderSigningPrivateKey:$canonicalData'));

  @override
  Future<bool> verify({
    required String senderSigningPublicKey,
    required String canonicalData,
    required String signature,
  }) async =>
      signature ==
      base64Encode(utf8.encode('$senderSigningPublicKey:$canonicalData'));
}

final class _History implements CallHistoryRepository {
  final Map<CallId, CallHistoryEntry> entries = <CallId, CallHistoryEntry>{};

  @override
  Future<CallHistoryEntry?> getByCallId(CallId callId) async => entries[callId];

  @override
  Future<List<CallHistoryEntry>> listForContact(String peerId) async =>
      entries.values.toList(growable: false);

  @override
  Future<void> upsertTerminal(CallHistoryEntry entry) async {
    entries.putIfAbsent(entry.callId, () => entry);
  }
}

final class _Capability implements ForegroundCallCapability {
  final StreamController<ForegroundCallProjection?> _changes =
      StreamController<ForegroundCallProjection?>.broadcast(sync: true);
  ForegroundCallProjection? _current;

  @override
  ForegroundCallProjection? get current => _current;

  @override
  Stream<ForegroundCallProjection?> get changes => _changes.stream;

  void emit(ForegroundCallProjection? projection) {
    _current = projection;
    _changes.add(projection);
  }

  Future<void> dispose() => _changes.close();

  @override
  Future<ForegroundCallActionResult> answer(CallId callId) async =>
      ForegroundCallActionResult.unavailable;

  @override
  Future<ForegroundCallActionResult> decline(CallId callId) async =>
      ForegroundCallActionResult.unavailable;

  @override
  Future<ForegroundCallActionResult> cancel(CallId callId) async =>
      ForegroundCallActionResult.unavailable;

  @override
  Future<ForegroundCallActionResult> end(CallId callId) async =>
      ForegroundCallActionResult.unavailable;

  @override
  Future<ForegroundCallActionResult> setMuted(
    CallId callId,
    bool muted,
  ) async => ForegroundCallActionResult.unavailable;

  @override
  Future<ForegroundCallActionResult> setSpeakerEnabled(
    CallId callId,
    bool enabled,
  ) async => ForegroundCallActionResult.unavailable;
}
