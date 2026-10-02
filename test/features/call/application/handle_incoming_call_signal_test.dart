import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/call/application/call_cleanup_coordinator.dart';
import 'package:flutter_app/features/call/application/call_coordinator.dart';
import 'package:flutter_app/features/call/application/call_endpoint_resolver.dart';
import 'package:flutter_app/features/call/application/call_history_projector.dart';
import 'package:flutter_app/features/call/application/call_negotiation_material_store.dart';
import 'package:flutter_app/features/call/application/call_network_gate.dart';
import 'package:flutter_app/features/call/application/call_signaling_context_store.dart';
import 'package:flutter_app/features/call/application/handle_incoming_call_signal.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_event.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_signal.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/diagnostics/call_diagnostics.dart';
import 'package:flutter_app/features/call/infrastructure/call_trusted_roster_provider.dart';
import 'package:flutter_app/features/call/infrastructure/secure_call_envelope_codec.dart';
import 'package:flutter_test/flutter_test.dart';

const _nowMs = 2_000_000;
const _callHandle = '33333333-3333-4333-8333-333333333333';
final _callId = CallId.parse('22222222-2222-4222-8222-222222222222');

final class _Crypto implements CallEnvelopeCrypto {
  bool throwOnVerify = false;
  bool throwOnDecrypt = false;

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
  }) async {
    if (throwOnDecrypt) throw StateError('crypto bridge unavailable');
    return utf8.decode(base64Decode(ciphertext.ciphertext));
  }

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
  }) async {
    if (throwOnVerify) throw StateError('crypto bridge unavailable');
    return signature ==
        base64Encode(utf8.encode('$senderSigningPublicKey:$canonicalData'));
  }
}

final class _Roster implements CallTrustedRosterProvider {
  const _Roster();

  @override
  Future<CallTrustedRosterSnapshot> loadForContact(String peerId) async =>
      throw UnimplementedError();

  @override
  Future<TrustedCallDeviceAuthority?> resolveAuthenticatedTransport(
    String transportPeerId,
  ) async => transportPeerId == 'sender-device'
      ? const TrustedCallDeviceAuthority(
          accountPeerId: 'sender-account',
          devicePeerId: 'sender-device',
          linked: true,
          deviceKeyEpoch: 1,
          signingPublicKey: 'sender-signing-key',
          mlKemPublicKey: 'sender-mlkem-key',
        )
      : null;
}

final class _ThrowingRoster implements CallTrustedRosterProvider {
  const _ThrowingRoster();

  @override
  Future<CallTrustedRosterSnapshot> loadForContact(String peerId) async =>
      throw StateError('database temporarily unavailable');

  @override
  Future<TrustedCallDeviceAuthority?> resolveAuthenticatedTransport(
    String transportPeerId,
  ) async => throw StateError('database temporarily unavailable');
}

final class _History implements CallHistoryRepository {
  @override
  Future<CallHistoryEntry?> getByCallId(CallId callId) async => null;

  @override
  Future<List<CallHistoryEntry>> listForContact(String peerId) async =>
      const [];

  @override
  Future<void> upsertTerminal(CallHistoryEntry entry) async {}
}

final class _Effects implements CallEffectExecutor {
  _Effects({int throwCount = 0, this.onExecute})
    : _throwsRemaining = throwCount;

  int _throwsRemaining;
  final FutureOr<CallEvent?> Function(
    CallEffect effect,
    CallSessionSnapshot snapshot,
  )?
  onExecute;
  final List<CallEffectType> effects = <CallEffectType>[];

  @override
  Future<CallEvent?> execute(
    CallEffect effect,
    CallSessionSnapshot snapshot,
  ) async {
    effects.add(effect.type);
    if (_throwsRemaining > 0) {
      _throwsRemaining--;
      throw StateError('temporary effect failure');
    }
    return onExecute == null ? null : await onExecute!(effect, snapshot);
  }
}

final class _Presenter implements IncomingCallPresenter {
  _Presenter({
    this.succeeds = true,
    this.resultGate,
    this.throwOnPresent = false,
    this.unavailable = false,
  });

  final bool succeeds;
  final Completer<bool>? resultGate;
  final bool throwOnPresent;
  final bool unavailable;
  int calls = 0;
  int dismissCalls = 0;
  final Completer<void> started = Completer<void>();

  @override
  Future<bool> present(IncomingCallPresentation presentation) async {
    calls++;
    if (!started.isCompleted) started.complete();
    if (unavailable) throw const IncomingCallPresentationUnavailable();
    if (throwOnPresent) throw StateError('native call surface unavailable');
    return resultGate == null ? succeeds : resultGate!.future;
  }

  @override
  Future<void> dismiss(IncomingCallPresentation presentation) async {
    dismissCalls++;
  }
}

final class _ProvisionalLifecycle
    implements ProvisionalNativeIncomingCallLifecycle {
  _ProvisionalLifecycle({
    this.onCall,
    this.remoteCancelGate,
    this.contactUpdateAccepted,
  });

  final void Function(String call)? onCall;
  final Completer<void>? remoteCancelGate;

  /// Native accepts a verified display name only while a live descriptor for
  /// the call handle exists (a Dart-first presentation creates it in
  /// `present`). Null means always accepted.
  final bool Function()? contactUpdateAccepted;
  final List<String> calls = <String>[];

  void _record(String call) {
    calls.add(call);
    onCall?.call(call);
  }

  @override
  Future<void> authenticationFailed(String callHandle) async {
    _record('authenticationFailed:$callHandle');
  }

  @override
  Future<void> remoteCancel(String callHandle) async {
    _record('remoteCancel:$callHandle');
    final gate = remoteCancelGate;
    if (gate != null) await gate.future;
  }

  @override
  Future<void> expire(String callHandle) async {
    _record('expire:$callHandle');
  }

  @override
  Future<void> updateAuthenticatedContact({
    required String callHandle,
    required String displayName,
  }) async {
    if (contactUpdateAccepted?.call() == false) {
      _record('updateAuthenticatedContact:$callHandle:$displayName:rejected');
      throw StateError('no native descriptor for this call handle yet');
    }
    _record('updateAuthenticatedContact:$callHandle:$displayName');
  }

  @override
  Future<void> revokeOpaqueContact(String callHandle) async {
    calls.add('revokeOpaqueContact:$callHandle');
  }
}

CallCoordinator _coordinator(_Effects effects, {int Function()? nowMs}) =>
    CallCoordinator(
      reducer: const CallReducer(),
      cleanupCoordinator: CallCleanupCoordinator(const <CallCleanupStep>[]),
      historyProjector: CallHistoryProjector(_History()),
      effectExecutor: effects,
      clock: () => DateTime.fromMillisecondsSinceEpoch(
        nowMs?.call() ?? _nowMs,
        isUtc: true,
      ),
      idSource: () => _callId,
    );

CallSignal _invite({
  int createdAtMs = _nowMs,
  int expiresAtMs = _nowMs + 45_000,
  int senderSequence = 1,
  Map<String, Object?> payload = const <String, Object?>{},
}) => CallSignal.create(
  callId: _callId,
  messageId: '11111111-1111-4111-8111-111111111111',
  event: CallSignalType.invite,
  senderAccountPeerId: 'sender-account',
  senderDevicePeerId: 'sender-device',
  recipientAccountPeerId: 'recipient-account',
  recipientDevicePeerId: 'recipient-device',
  senderSequence: senderSequence,
  iceGeneration: 0,
  createdAtMs: createdAtMs,
  expiresAtMs: expiresAtMs,
  payload: payload,
);

CallSignal _negotiationSignal({
  required CallSignalType event,
  required String messageId,
  required int senderSequence,
  required int iceGeneration,
  required Map<String, Object?> payload,
}) => CallSignal.create(
  callId: _callId,
  messageId: messageId,
  event: event,
  senderAccountPeerId: 'sender-account',
  senderDevicePeerId: 'sender-device',
  recipientAccountPeerId: 'recipient-account',
  recipientDevicePeerId: 'recipient-device',
  senderSequence: senderSequence,
  iceGeneration: iceGeneration,
  createdAtMs: _nowMs,
  expiresAtMs: _nowMs + 45_000,
  payload: payload,
);

Future<void> _prepareOutgoing(
  CallCoordinator coordinator, {
  required bool accepted,
}) async {
  await coordinator.dispatch(
    CallEvent(
      type: CallEventType.place,
      eventId: 'local-place',
      occurredAt: DateTime.fromMillisecondsSinceEpoch(_nowMs, isUtc: true),
      callId: _callId,
      contactPeerId: 'sender-account',
      localAccountPeerId: 'recipient-account',
      localDeviceId: 'recipient-device',
      remoteAccountPeerId: 'sender-account',
      remoteDeviceId: 'sender-device',
    ),
  );
  await coordinator.dispatch(
    CallEvent(
      type: CallEventType.outgoingInviteReady,
      eventId: 'outgoing-invite-ready',
      occurredAt: DateTime.fromMillisecondsSinceEpoch(_nowMs, isUtc: true),
      callId: _callId,
      contactPeerId: 'sender-account',
    ),
  );
  if (!accepted) return;
  await coordinator.dispatch(
    CallEvent(
      type: CallEventType.remoteAccept,
      eventId: 'remote-accept',
      occurredAt: DateTime.fromMillisecondsSinceEpoch(_nowMs, isUtc: true),
      callId: _callId,
      contactPeerId: 'sender-account',
      remoteAccountPeerId: 'sender-account',
      remoteDeviceId: 'sender-device',
    ),
  );
}

Future<
  ({
    SecureCallEnvelopeCodec codec,
    HandleIncomingCallSignal handler,
    String envelope,
  })
>
_build(
  CallCoordinator coordinator,
  _Presenter presenter, {
  CallTrustedRosterProvider trustedRosterProvider = const _Roster(),
  CallLocalAuthorityProvider? localAuthorityProvider,
  _Crypto? crypto,
  int Function()? nowMs,
  CallSignal? signal,
  CallNegotiationMaterialStore? negotiationMaterialStore,
  AuthenticatedCallSignalingContextObserver? signalingContextObserver,
  ProvisionalNativeIncomingCallLifecycle? provisionalNativeLifecycle,
  AuthenticatedCallDisplayNameResolver? authenticatedDisplayNameResolver,
  AndroidAuthenticatedContactPresenter? androidAuthenticatedContactPresenter,
  Duration provisionalNativeTerminalTimeout = const Duration(seconds: 2),
  CallNetworkEffectsAllowed? networkEffectsAllowed,
}) async {
  final selectedCrypto = crypto ?? _Crypto();
  final selectedSignal = signal ?? _invite();
  final codec = SecureCallEnvelopeCodec(
    crypto: selectedCrypto,
    nowMs: nowMs ?? () => _nowMs,
  );
  final envelope = await codec.encode(
    signal: selectedSignal,
    callHandle: _callHandle,
    recipientMlKemPublicKey: 'recipient-mlkem-key',
    senderSigningPrivateKey: 'sender-signing-key',
  );
  return (
    codec: codec,
    handler: HandleIncomingCallSignal(
      codec: codec,
      coordinator: coordinator,
      trustedRosterProvider: trustedRosterProvider,
      localAuthorityProvider:
          localAuthorityProvider ??
          () async => const CallLocalDeviceAuthority(
            accountPeerId: 'recipient-account',
            devicePeerId: 'recipient-device',
            mlKemSecretKey: 'recipient-mlkem-secret-key',
          ),
      incomingCallPresenter: presenter,
      networkEffectsAllowed: networkEffectsAllowed ?? () => true,
      negotiationMaterialStore: negotiationMaterialStore,
      signalingContextObserver: signalingContextObserver,
      provisionalNativeLifecycle: provisionalNativeLifecycle,
      authenticatedDisplayNameResolver: authenticatedDisplayNameResolver,
      androidAuthenticatedContactPresenter:
          androidAuthenticatedContactPresenter,
      provisionalNativeTerminalTimeout: provisionalNativeTerminalTimeout,
    ),
    envelope: envelope,
  );
}

void main() {
  test(
    'signaling context is captured only after authentication and purged on rejection',
    () async {
      final unauthenticatedStore = CallSignalingContextStore();
      final unauthenticatedEffects = _Effects();
      final unauthenticatedCoordinator = _coordinator(unauthenticatedEffects);
      addTearDown(unauthenticatedCoordinator.dispose);
      final crypto = _Crypto();
      final unauthenticated = await _build(
        unauthenticatedCoordinator,
        _Presenter(),
        crypto: crypto,
        signalingContextObserver: unauthenticatedStore,
      );
      crypto.throwOnVerify = true;

      expect(
        await unauthenticated.handler.handle(
          IncomingCallSignalFrame(
            envelopeJson: unauthenticated.envelope,
            authenticatedTransportPeerId: 'sender-device',
            route: CallRouteClass.direct,
          ),
        ),
        IncomingCallSignalOutcome.deferred,
      );
      expect(unauthenticatedStore.length, 0);

      final rejectedStore = CallSignalingContextStore();
      final rejectedEffects = _Effects();
      final rejectedCoordinator = _coordinator(rejectedEffects);
      addTearDown(rejectedCoordinator.dispose);
      final rejected = await _build(
        rejectedCoordinator,
        _Presenter(succeeds: false),
        signalingContextObserver: rejectedStore,
      );

      expect(
        await rejected.handler.handle(
          IncomingCallSignalFrame(
            envelopeJson: rejected.envelope,
            authenticatedTransportPeerId: 'sender-device',
            route: CallRouteClass.direct,
          ),
        ),
        IncomingCallSignalOutcome.rejected,
      );
      expect(rejectedStore.length, 0);
    },
  );

  test(
    'accepted context survives ringing then terminal signal purges it',
    () async {
      final store = CallSignalingContextStore();
      final effects = _Effects();
      final coordinator = _coordinator(effects);
      addTearDown(coordinator.dispose);
      final built = await _build(
        coordinator,
        _Presenter(),
        signalingContextObserver: store,
      );

      expect(
        await built.handler.handle(
          IncomingCallSignalFrame(
            envelopeJson: built.envelope,
            authenticatedTransportPeerId: 'sender-device',
            route: CallRouteClass.direct,
          ),
        ),
        IncomingCallSignalOutcome.accepted,
      );
      expect(store.read(_callId)?.callHandle, _callHandle);

      final terminate = _negotiationSignal(
        event: CallSignalType.terminate,
        messageId: '99999999-9999-4999-8999-999999999999',
        senderSequence: 2,
        iceGeneration: 0,
        payload: <String, Object?>{
          'reason': CallEndReason.remoteHangup.wireName,
        },
      );
      final terminalEnvelope = await built.codec.encode(
        signal: terminate,
        callHandle: _callHandle,
        recipientMlKemPublicKey: 'recipient-mlkem-key',
        senderSigningPrivateKey: 'sender-signing-key',
      );
      expect(
        await built.handler.handle(
          IncomingCallSignalFrame(
            envelopeJson: terminalEnvelope,
            authenticatedTransportPeerId: 'sender-device',
            route: CallRouteClass.direct,
          ),
        ),
        IncomingCallSignalOutcome.accepted,
      );
      expect(store.length, 0);
    },
  );

  test(
    'authenticated offer answer ICE and restart exist before canonical effects',
    () async {
      final store = CallNegotiationMaterialStore();
      final observed = <CallNegotiationMaterial>[];
      final effects = _Effects(
        onExecute: (effect, snapshot) {
          if (<CallEffectType>{
            CallEffectType.deliverOffer,
            CallEffectType.deliverAnswer,
            CallEffectType.queueIceCandidate,
            CallEffectType.restartIce,
          }.contains(effect.type)) {
            final eventId = snapshot.recentEventIds.last;
            final material = store.take(snapshot.callId!, eventId);
            expect(material, isNotNull, reason: effect.type.name);
            observed.add(material!);
          }
          return null;
        },
      );
      final coordinator = _coordinator(effects);
      addTearDown(coordinator.dispose);
      await _prepareOutgoing(coordinator, accepted: true);
      final signals = <CallSignal>[
        _negotiationSignal(
          event: CallSignalType.offer,
          messageId: '44444444-4444-4444-8444-444444444441',
          senderSequence: 2,
          iceGeneration: 0,
          payload: const <String, Object?>{
            'description': 'secret-offer-sdp',
            'fingerprint': 'secret-offer-fingerprint',
          },
        ),
        _negotiationSignal(
          event: CallSignalType.answer,
          messageId: '44444444-4444-4444-8444-444444444442',
          senderSequence: 3,
          iceGeneration: 0,
          payload: const <String, Object?>{
            'description': 'secret-answer-sdp',
            'fingerprint': 'secret-answer-fingerprint',
          },
        ),
        _negotiationSignal(
          event: CallSignalType.ice,
          messageId: '44444444-4444-4444-8444-444444444443',
          senderSequence: 4,
          iceGeneration: 0,
          payload: const <String, Object?>{
            'candidate': 'secret-ice-candidate',
            'media_id': 'audio',
            'media_line_index': 0,
          },
        ),
        _negotiationSignal(
          event: CallSignalType.iceRestart,
          messageId: '44444444-4444-4444-8444-444444444444',
          senderSequence: 5,
          iceGeneration: 1,
          payload: const <String, Object?>{},
        ),
      ];

      for (final signal in signals) {
        final built = await _build(
          coordinator,
          _Presenter(),
          signal: signal,
          negotiationMaterialStore: store,
        );
        expect(
          await built.handler.handle(
            IncomingCallSignalFrame(
              envelopeJson: built.envelope,
              authenticatedTransportPeerId: 'sender-device',
              route: CallRouteClass.direct,
            ),
          ),
          IncomingCallSignalOutcome.accepted,
          reason: signal.event.wireName,
        );
      }

      expect(
        observed.map((material) => material.type),
        <CallNegotiationMaterialType>[
          CallNegotiationMaterialType.offer,
          CallNegotiationMaterialType.answer,
          CallNegotiationMaterialType.ice,
          CallNegotiationMaterialType.iceRestart,
        ],
      );
      expect(observed.last.iceGeneration, 1);
      expect(store.entryCountFor(_callId), 0);
      expect(
        coordinator.activeSession.toString(),
        isNot(contains('secret-ice-candidate')),
      );
    },
  );

  test(
    'authenticated offer answer and ICE before acceptance are purged',
    () async {
      final cases =
          <
            ({
              CallSignalType type,
              String messageId,
              Map<String, Object?> payload,
            })
          >[
            (
              type: CallSignalType.offer,
              messageId: '55555555-5555-4555-8555-555555555551',
              payload: const <String, Object?>{
                'description': 'early-secret-offer',
                'fingerprint': 'early-secret-offer-fingerprint',
              },
            ),
            (
              type: CallSignalType.answer,
              messageId: '55555555-5555-4555-8555-555555555552',
              payload: const <String, Object?>{
                'description': 'early-secret-answer',
                'fingerprint': 'early-secret-answer-fingerprint',
              },
            ),
            (
              type: CallSignalType.ice,
              messageId: '55555555-5555-4555-8555-555555555553',
              payload: const <String, Object?>{
                'candidate': 'early-secret-candidate',
                'media_id': 'audio',
                'media_line_index': 0,
              },
            ),
          ];

      for (final value in cases) {
        final store = CallNegotiationMaterialStore();
        final effects = _Effects();
        final coordinator = _coordinator(effects);
        try {
          await _prepareOutgoing(coordinator, accepted: false);
          final before = coordinator.activeSession;
          final effectsBefore = List<CallEffectType>.of(effects.effects);
          final signal = _negotiationSignal(
            event: value.type,
            messageId: value.messageId,
            senderSequence: 2,
            iceGeneration: 0,
            payload: value.payload,
          );
          final built = await _build(
            coordinator,
            _Presenter(),
            signal: signal,
            negotiationMaterialStore: store,
          );

          expect(
            await built.handler.handle(
              IncomingCallSignalFrame(
                envelopeJson: built.envelope,
                authenticatedTransportPeerId: 'sender-device',
                route: CallRouteClass.direct,
              ),
            ),
            IncomingCallSignalOutcome.rejected,
            reason: value.type.wireName,
          );
          expect(coordinator.activeSession, same(before));
          expect(coordinator.activeSession?.state, CallState.inviting);
          expect(store.entryCountFor(_callId), 0);
          expect(effects.effects, effectsBefore, reason: value.type.wireName);
        } finally {
          await coordinator.dispose();
        }
      }
    },
  );

  test('terminal signal purges retained negotiation material', () async {
    final store = CallNegotiationMaterialStore();
    final effects = _Effects();
    final coordinator = _coordinator(effects);
    addTearDown(coordinator.dispose);
    await _prepareOutgoing(coordinator, accepted: true);
    expect(
      store.store(
        CallNegotiationMaterial(
          callId: _callId,
          eventId: 'retained-candidate',
          type: CallNegotiationMaterialType.ice,
          iceGeneration: 0,
          payload: const <String, Object?>{'candidate': 'retained-secret'},
        ),
      ),
      CallNegotiationMaterialStoreDecision.stored,
    );
    final signal = _negotiationSignal(
      event: CallSignalType.terminate,
      messageId: '66666666-6666-4666-8666-666666666666',
      senderSequence: 2,
      iceGeneration: 0,
      payload: const <String, Object?>{'reason': 'remote_hangup'},
    );
    final provisional = _ProvisionalLifecycle();
    final built = await _build(
      coordinator,
      _Presenter(),
      signal: signal,
      negotiationMaterialStore: store,
      provisionalNativeLifecycle: provisional,
    );

    expect(
      await built.handler.handle(
        IncomingCallSignalFrame(
          envelopeJson: built.envelope,
          authenticatedTransportPeerId: 'sender-device',
          route: CallRouteClass.direct,
        ),
      ),
      IncomingCallSignalOutcome.accepted,
    );
    expect(coordinator.activeSession, isNull);
    expect(coordinator.lastSnapshot?.state, CallState.ended);
    expect(store.entryCountFor(_callId), 0);
    expect(store.callCount, 0);
    expect(provisional.calls, <String>['remoteCancel:$_callHandle']);
  });

  test(
    'authenticated remote terminate reaches native before terminal projection',
    () async {
      final timeline = <String>[];
      final effects = _Effects();
      final coordinator = _coordinator(effects);
      addTearDown(coordinator.dispose);
      final snapshotSubscription = coordinator.snapshots.listen((snapshot) {
        if (snapshot.isTerminal) timeline.add('terminalSnapshot');
      });
      addTearDown(snapshotSubscription.cancel);
      await _prepareOutgoing(coordinator, accepted: true);
      final signal = _negotiationSignal(
        event: CallSignalType.terminate,
        messageId: '77777777-7777-4777-8777-777777777777',
        senderSequence: 2,
        iceGeneration: 0,
        payload: const <String, Object?>{'reason': 'remote_hangup'},
      );
      final provisional = _ProvisionalLifecycle(onCall: timeline.add);
      final built = await _build(
        coordinator,
        _Presenter(),
        signal: signal,
        provisionalNativeLifecycle: provisional,
      );

      expect(
        await built.handler.handle(
          IncomingCallSignalFrame(
            envelopeJson: built.envelope,
            authenticatedTransportPeerId: 'sender-device',
            route: CallRouteClass.direct,
          ),
        ),
        IncomingCallSignalOutcome.accepted,
      );
      expect(timeline, <String>[
        'remoteCancel:$_callHandle',
        'terminalSnapshot',
      ]);
    },
  );

  test(
    'stalled native remote cancel cannot block canonical terminalization',
    () async {
      final effects = _Effects();
      final coordinator = _coordinator(effects);
      addTearDown(coordinator.dispose);
      await _prepareOutgoing(coordinator, accepted: true);
      final signal = _negotiationSignal(
        event: CallSignalType.terminate,
        messageId: '88888888-8888-4888-8888-888888888888',
        senderSequence: 2,
        iceGeneration: 0,
        payload: const <String, Object?>{'reason': 'remote_hangup'},
      );
      final provisional = _ProvisionalLifecycle(
        remoteCancelGate: Completer<void>(),
      );
      final built = await _build(
        coordinator,
        _Presenter(),
        signal: signal,
        provisionalNativeLifecycle: provisional,
        provisionalNativeTerminalTimeout: const Duration(milliseconds: 10),
      );

      expect(
        await built.handler.handle(
          IncomingCallSignalFrame(
            envelopeJson: built.envelope,
            authenticatedTransportPeerId: 'sender-device',
            route: CallRouteClass.direct,
          ),
        ),
        IncomingCallSignalOutcome.accepted,
      );
      expect(coordinator.activeSession, isNull);
      expect(coordinator.lastSnapshot?.endReason, CallEndReason.remoteHangup);
    },
  );

  test(
    'validated invite rings only after platform presentation succeeds',
    () async {
      final effects = _Effects();
      final coordinator = _coordinator(effects);
      addTearDown(coordinator.dispose);
      final presenter = _Presenter();
      final provisional = _ProvisionalLifecycle();
      final built = await _build(
        coordinator,
        presenter,
        provisionalNativeLifecycle: provisional,
        authenticatedDisplayNameResolver: (_) async => 'Alice',
      );

      final outcome = await built.handler.handle(
        IncomingCallSignalFrame(
          envelopeJson: built.envelope,
          authenticatedTransportPeerId: 'sender-device',
          route: CallRouteClass.direct,
        ),
      );

      expect(outcome, IncomingCallSignalOutcome.accepted);
      expect(presenter.calls, 1);
      expect(coordinator.activeSession?.incomingValidated, isTrue);
      expect(coordinator.activeSession?.state, CallState.ringing);
      expect(effects.effects, contains(CallEffectType.sendRinging));
      expect(provisional.calls, <String>[
        'updateAuthenticatedContact:$_callHandle:Alice',
      ]);
    },
  );

  test(
    'verified caller name is applied after a Dart-first presentation creates '
    'the native descriptor',
    () async {
      final effects = _Effects();
      final coordinator = _coordinator(effects);
      addTearDown(coordinator.dispose);
      final presenter = _Presenter();
      // Before `present`, native has no descriptor for the call handle, so the
      // pre-presentation update is refused; after it the update must land or
      // CallKit keeps showing the generic "Mknoon call" label.
      final provisional = _ProvisionalLifecycle(
        contactUpdateAccepted: () => presenter.calls > 0,
      );
      final built = await _build(
        coordinator,
        presenter,
        provisionalNativeLifecycle: provisional,
        authenticatedDisplayNameResolver: (_) async => 'Alice',
      );

      final outcome = await built.handler.handle(
        IncomingCallSignalFrame(
          envelopeJson: built.envelope,
          authenticatedTransportPeerId: 'sender-device',
          route: CallRouteClass.direct,
        ),
      );

      expect(outcome, IncomingCallSignalOutcome.accepted);
      expect(coordinator.activeSession?.state, CallState.ringing);
      expect(provisional.calls, <String>[
        'updateAuthenticatedContact:$_callHandle:Alice:rejected',
        'updateAuthenticatedContact:$_callHandle:Alice',
      ]);
    },
  );

  test(
    'Android background presentation receives the verified local name',
    () async {
      final coordinator = _coordinator(_Effects());
      addTearDown(coordinator.dispose);
      final presenter = _Presenter();
      final updates = <String>[];
      final built = await _build(
        coordinator,
        presenter,
        authenticatedDisplayNameResolver: (peerId) async {
          expect(peerId, 'sender-account');
          return '  Alice  ';
        },
        androidAuthenticatedContactPresenter: (callId, displayName) async {
          expect(presenter.calls, 1);
          expect(callId, _callId);
          updates.add(displayName);
          return true;
        },
      );

      final outcome = await built.handler.handle(
        IncomingCallSignalFrame(
          envelopeJson: built.envelope,
          authenticatedTransportPeerId: 'sender-device',
          route: CallRouteClass.direct,
        ),
      );

      expect(outcome, IncomingCallSignalOutcome.accepted);
      expect(updates, <String>['Alice']);
    },
  );

  test(
    'duplicate direct/mailbox delivery converges before coordinator',
    () async {
      final effects = _Effects();
      final coordinator = _coordinator(effects);
      addTearDown(coordinator.dispose);
      final presenter = _Presenter();
      final built = await _build(coordinator, presenter);
      final directFrame = IncomingCallSignalFrame(
        envelopeJson: built.envelope,
        authenticatedTransportPeerId: 'sender-device',
        route: CallRouteClass.direct,
      );
      final mailboxFrame = IncomingCallSignalFrame(
        envelopeJson: built.envelope,
        authenticatedTransportPeerId: 'sender-device',
        route: CallRouteClass.ephemeralMailbox,
        expectedCallHandle: _callHandle,
        expectedMessageId: _invite().messageId,
        expectedExpiresAtMs: _invite().expiresAtMs,
      );

      expect(
        await built.handler.handle(directFrame),
        IncomingCallSignalOutcome.accepted,
      );
      expect(
        await built.handler.handle(mailboxFrame),
        IncomingCallSignalOutcome.duplicate,
      );
      expect(presenter.calls, 1);
    },
  );

  test('duplicate push-triggered mailbox retrieval presents one UI', () async {
    final effects = _Effects();
    final coordinator = _coordinator(effects);
    addTearDown(coordinator.dispose);
    final presenter = _Presenter();
    final built = await _build(coordinator, presenter);
    final retrievedFrame = IncomingCallSignalFrame(
      envelopeJson: built.envelope,
      authenticatedTransportPeerId: 'sender-device',
      route: CallRouteClass.ephemeralMailbox,
      expectedCallHandle: _callHandle,
      expectedMessageId: _invite().messageId,
      expectedExpiresAtMs: _invite().expiresAtMs,
    );

    // A duplicate native wake may trigger the same mailbox item again. The
    // wake itself carries no call data, so both attempts enter through this
    // authenticated retrieval frame.
    expect(
      await built.handler.handle(retrievedFrame),
      IncomingCallSignalOutcome.accepted,
    );
    expect(
      await built.handler.handle(retrievedFrame),
      IncomingCallSignalOutcome.duplicate,
    );
    expect(presenter.calls, 1);
  });

  test(
    'changed authenticated bytes under a committed message ID reject',
    () async {
      final effects = _Effects();
      final coordinator = _coordinator(effects);
      addTearDown(coordinator.dispose);
      final presenter = _Presenter();
      final built = await _build(coordinator, presenter);
      final frame = IncomingCallSignalFrame(
        envelopeJson: built.envelope,
        authenticatedTransportPeerId: 'sender-device',
        route: CallRouteClass.ephemeralMailbox,
      );

      expect(
        await built.handler.handle(frame),
        IncomingCallSignalOutcome.accepted,
      );
      final changedEnvelope = await built.codec.encode(
        signal: _invite(
          senderSequence: 2,
          payload: const <String, Object?>{
            'metadata': <String, Object?>{'changed': true},
          },
        ),
        callHandle: _callHandle,
        recipientMlKemPublicKey: 'recipient-mlkem-key',
        senderSigningPrivateKey: 'sender-signing-key',
      );
      expect(changedEnvelope, isNot(built.envelope));

      expect(
        await built.handler.handle(
          IncomingCallSignalFrame(
            envelopeJson: changedEnvelope,
            authenticatedTransportPeerId: 'sender-device',
            route: CallRouteClass.ephemeralMailbox,
          ),
        ),
        IncomingCallSignalOutcome.rejected,
      );
      expect(presenter.calls, 1);
      expect(coordinator.activeSession?.state, CallState.ringing);
    },
  );

  test('platform presentation failure terminates without ringing', () async {
    final diagnostics = await CallDiagnostics.installForTesting();
    addTearDown(() async {
      await diagnostics.setEnabled(false);
      await diagnostics.dispose();
    });
    final effects = _Effects();
    final coordinator = _coordinator(effects);
    addTearDown(coordinator.dispose);
    final presenter = _Presenter(succeeds: false);
    final provisional = _ProvisionalLifecycle();
    final built = await _build(
      coordinator,
      presenter,
      provisionalNativeLifecycle: provisional,
    );

    expect(
      await built.handler.handle(
        IncomingCallSignalFrame(
          envelopeJson: built.envelope,
          authenticatedTransportPeerId: 'sender-device',
          route: CallRouteClass.direct,
        ),
      ),
      IncomingCallSignalOutcome.rejected,
    );
    expect(coordinator.activeSession, isNull);
    expect(coordinator.lastSnapshot?.state, CallState.ended);
    expect(coordinator.lastSnapshot?.endReason, CallEndReason.signalingFailed);
    expect(effects.effects, contains(CallEffectType.sendTerminate));
    expect(effects.effects, isNot(contains(CallEffectType.sendRinging)));
    expect(
      effects.effects,
      isNot(contains(CallEffectType.prepareAcceptedMedia)),
    );
    expect(provisional.calls, <String>['authenticationFailed:$_callHandle']);
    final records = (await diagnostics.eventsForTesting())
        .where(
          (event) =>
              event['stage'] == 'presentation' && event['action'] == 'present',
        )
        .toList();
    final trace = diagnostics.traceForCall(callId: _callId.value);
    expect(trace, isNotNull);
    expect(records.map((event) => event['outcome']), ['started', 'failed']);
    expect(records.last['reason'], 'native_lifecycle_failed');
    expect(records, everyElement(containsPair('traceId', trace)));
    expect(jsonEncode(records), isNot(contains(_callHandle)));
    expect(records.any((event) => event['reason'] == 'no_answer'), isFalse);
  });

  test('platform presentation exception is a signaling failure', () async {
    final effects = _Effects();
    final coordinator = _coordinator(effects);
    addTearDown(coordinator.dispose);
    final presenter = _Presenter(throwOnPresent: true);
    final built = await _build(coordinator, presenter);

    expect(
      await built.handler.handle(
        IncomingCallSignalFrame(
          envelopeJson: built.envelope,
          authenticatedTransportPeerId: 'sender-device',
          route: CallRouteClass.direct,
        ),
      ),
      IncomingCallSignalOutcome.rejected,
    );
    expect(coordinator.activeSession, isNull);
    expect(coordinator.lastSnapshot?.endReason, CallEndReason.signalingFailed);
    expect(effects.effects, contains(CallEffectType.sendTerminate));
    expect(effects.effects, isNot(contains(CallEffectType.sendRinging)));
    expect(
      effects.effects,
      isNot(contains(CallEffectType.prepareAcceptedMedia)),
    );
  });

  test('foreground-only background presentation reports unsupported', () async {
    final effects = _Effects();
    final coordinator = _coordinator(effects);
    addTearDown(coordinator.dispose);
    final built = await _build(coordinator, _Presenter(unavailable: true));
    expect(
      await built.handler.handle(
        IncomingCallSignalFrame(
          envelopeJson: built.envelope,
          authenticatedTransportPeerId: 'sender-device',
          route: CallRouteClass.direct,
        ),
      ),
      IncomingCallSignalOutcome.rejected,
    );
    expect(coordinator.activeSession, isNull);
    expect(coordinator.lastSnapshot?.endReason, CallEndReason.unsupported);
    expect(effects.effects, contains(CallEffectType.sendTerminate));
    expect(effects.effects, isNot(contains(CallEffectType.sendRinging)));
  });

  test('native decline survives a late presentation refusal', () async {
    final effects = _Effects();
    final coordinator = _coordinator(effects);
    addTearDown(coordinator.dispose);
    final resultGate = Completer<bool>();
    final presenter = _Presenter(resultGate: resultGate);
    final provisional = _ProvisionalLifecycle();
    final built = await _build(
      coordinator,
      presenter,
      provisionalNativeLifecycle: provisional,
    );

    final handling = built.handler.handle(
      IncomingCallSignalFrame(
        envelopeJson: built.envelope,
        authenticatedTransportPeerId: 'sender-device',
        route: CallRouteClass.ephemeralMailbox,
      ),
    );
    await presenter.started.future;
    await coordinator.dispatch(
      CallEvent(
        type: CallEventType.nativeAction,
        eventId: 'native-decline-during-presentation',
        occurredAt: DateTime.fromMillisecondsSinceEpoch(_nowMs, isUtc: true),
        callId: _callId,
        nativeAction: CallNativeAction.decline,
      ),
    );
    expect(coordinator.lastSnapshot?.endReason, CallEndReason.declined);
    resultGate.complete(false);

    expect(await handling, IncomingCallSignalOutcome.rejected);
    expect(coordinator.activeSession, isNull);
    expect(coordinator.lastSnapshot?.endReason, CallEndReason.declined);
    expect(provisional.calls, <String>['remoteCancel:$_callHandle']);
    expect(effects.effects, isNot(contains(CallEffectType.sendTerminate)));
    expect(effects.effects, isNot(contains(CallEffectType.sendRinging)));
  });

  test('microphone denial after answer remains permission denied', () async {
    final effects = _Effects(
      onExecute: (effect, snapshot) =>
          effect.type == CallEffectType.prepareAcceptedMedia
          ? CallEvent(
              type: CallEventType.negotiationFailed,
              eventId: 'microphone-denied-after-answer',
              occurredAt: snapshot.observedAt,
              callId: snapshot.callId,
              endReason: CallEndReason.permissionDenied,
            )
          : null,
    );
    final coordinator = _coordinator(effects);
    addTearDown(coordinator.dispose);
    final built = await _build(coordinator, _Presenter());
    expect(
      await built.handler.handle(
        IncomingCallSignalFrame(
          envelopeJson: built.envelope,
          authenticatedTransportPeerId: 'sender-device',
          route: CallRouteClass.direct,
        ),
      ),
      IncomingCallSignalOutcome.accepted,
    );
    await coordinator.dispatch(
      CallEvent(
        type: CallEventType.answer,
        eventId: 'answer-before-microphone-denial',
        occurredAt: DateTime.fromMillisecondsSinceEpoch(_nowMs, isUtc: true),
        callId: _callId,
      ),
    );

    expect(effects.effects, contains(CallEffectType.prepareAcceptedMedia));
    expect(coordinator.activeSession, isNull);
    expect(coordinator.lastSnapshot?.endReason, CallEndReason.permissionDenied);
    expect(effects.effects, isNot(contains(CallEffectType.sendAccept)));
  });

  test('expired native wake is retired before authentication or UI', () async {
    final effects = _Effects();
    final coordinator = _coordinator(effects);
    addTearDown(coordinator.dispose);
    final presenter = _Presenter();
    final provisional = _ProvisionalLifecycle();
    final built = await _build(
      coordinator,
      presenter,
      provisionalNativeLifecycle: provisional,
    );

    expect(
      await built.handler.handle(
        IncomingCallSignalFrame(
          envelopeJson: built.envelope,
          authenticatedTransportPeerId: 'sender-device',
          route: CallRouteClass.ephemeralMailbox,
          expectedCallHandle: _callHandle,
          expectedExpiresAtMs: _nowMs,
        ),
      ),
      IncomingCallSignalOutcome.rejected,
    );
    expect(provisional.calls, <String>['expire:$_callHandle']);
    expect(presenter.calls, 0);
    expect(coordinator.activeSession, isNull);
    expect(effects.effects, isEmpty);
  });

  test(
    'unknown native caller revokes contact and fails authentication before UI',
    () async {
      final effects = _Effects();
      final coordinator = _coordinator(effects);
      addTearDown(coordinator.dispose);
      final presenter = _Presenter();
      final provisional = _ProvisionalLifecycle();
      final built = await _build(
        coordinator,
        presenter,
        provisionalNativeLifecycle: provisional,
      );

      expect(
        await built.handler.handle(
          IncomingCallSignalFrame(
            envelopeJson: built.envelope,
            authenticatedTransportPeerId: 'unknown-device',
            route: CallRouteClass.ephemeralMailbox,
            expectedCallHandle: _callHandle,
          ),
        ),
        IncomingCallSignalOutcome.rejected,
      );
      expect(provisional.calls, <String>[
        'revokeOpaqueContact:$_callHandle',
        'authenticationFailed:$_callHandle',
      ]);
      expect(presenter.calls, 0);
      expect(coordinator.activeSession, isNull);
      expect(effects.effects, isEmpty);
    },
  );

  test(
    'slow presentation is dismissed and never adopted after expiry cleanup',
    () async {
      var nowMs = _nowMs;
      final effects = _Effects();
      final coordinator = _coordinator(effects, nowMs: () => nowMs);
      addTearDown(coordinator.dispose);
      final resultGate = Completer<bool>();
      final presenter = _Presenter(resultGate: resultGate);
      final built = await _build(coordinator, presenter, nowMs: () => nowMs);

      final handling = built.handler.handle(
        IncomingCallSignalFrame(
          envelopeJson: built.envelope,
          authenticatedTransportPeerId: 'sender-device',
          route: CallRouteClass.ephemeralMailbox,
        ),
      );
      await presenter.started.future;
      nowMs += 45_000;
      await coordinator.dispatch(
        CallEvent(
          type: CallEventType.timeout,
          eventId: 'expiry-during-presentation',
          occurredAt: DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true),
          callId: _callId,
          contactPeerId: 'sender-account',
          remoteAccountPeerId: 'sender-account',
          remoteDeviceId: 'sender-device',
          timeoutKind: CallTimeoutKind.inviteExpiry,
        ),
      );
      resultGate.complete(true);

      expect(await handling, IncomingCallSignalOutcome.rejected);
      expect(presenter.dismissCalls, 1);
      expect(coordinator.activeSession, isNull);
      expect(coordinator.lastSnapshot?.endReason, CallEndReason.expired);
      expect(effects.effects, isNot(contains(CallEffectType.sendRinging)));
    },
  );

  test(
    'unknown transport and mailbox binding mismatch fail before UI',
    () async {
      for (final mutate in <IncomingCallSignalFrame Function(String)>[
        (envelope) => IncomingCallSignalFrame(
          envelopeJson: envelope,
          authenticatedTransportPeerId: 'unknown-device',
          route: CallRouteClass.direct,
        ),
        (envelope) => IncomingCallSignalFrame(
          envelopeJson: envelope,
          authenticatedTransportPeerId: 'sender-device',
          route: CallRouteClass.ephemeralMailbox,
          expectedCallHandle: '44444444-4444-4444-8444-444444444444',
        ),
      ]) {
        final effects = _Effects();
        final coordinator = _coordinator(effects);
        final presenter = _Presenter();
        final built = await _build(coordinator, presenter);

        expect(
          await built.handler.handle(mutate(built.envelope)),
          IncomingCallSignalOutcome.rejected,
        );
        expect(coordinator.activeSession, isNull);
        expect(presenter.calls, 0);
        await coordinator.dispose();
      }
    },
  );

  test(
    'coordinator effect failure terminalizes and replay cannot reopen',
    () async {
      final effects = _Effects(throwCount: 1);
      final coordinator = _coordinator(effects);
      addTearDown(coordinator.dispose);
      final presenter = _Presenter();
      final signalingContexts = CallSignalingContextStore();
      final built = await _build(
        coordinator,
        presenter,
        signalingContextObserver: signalingContexts,
      );
      final frame = IncomingCallSignalFrame(
        envelopeJson: built.envelope,
        authenticatedTransportPeerId: 'sender-device',
        route: CallRouteClass.ephemeralMailbox,
      );

      expect(
        await built.handler.handle(frame),
        IncomingCallSignalOutcome.deferred,
      );
      expect(coordinator.activeSession, isNull);
      expect(coordinator.lastSnapshot?.state, CallState.ended);
      expect(
        coordinator.lastSnapshot?.endReason,
        CallEndReason.signalingFailed,
      );
      expect(presenter.calls, 0);
      expect(signalingContexts.read(_callId), isNull);

      expect(
        await built.handler.handle(frame),
        IncomingCallSignalOutcome.duplicate,
      );
      expect(coordinator.activeSession, isNull);
      expect(coordinator.lastSnapshot?.state, CallState.ended);
      expect(presenter.calls, 0);
      expect(signalingContexts.read(_callId), isNull);

      expect(
        await built.handler.handle(frame),
        IncomingCallSignalOutcome.duplicate,
      );
      expect(coordinator.activeSession, isNull);
      expect(presenter.calls, 0);
    },
  );

  test('roster and incomplete local authority failures are deferred', () async {
    final coordinator = _coordinator(_Effects());
    addTearDown(coordinator.dispose);

    final rosterFailure = await _build(
      coordinator,
      _Presenter(),
      trustedRosterProvider: const _ThrowingRoster(),
    );
    expect(
      await rosterFailure.handler.handle(
        IncomingCallSignalFrame(
          envelopeJson: rosterFailure.envelope,
          authenticatedTransportPeerId: 'sender-device',
          route: CallRouteClass.ephemeralMailbox,
        ),
      ),
      IncomingCallSignalOutcome.deferred,
    );

    final localNotReady = await _build(
      coordinator,
      _Presenter(),
      localAuthorityProvider: () async => const CallLocalDeviceAuthority(
        accountPeerId: '',
        devicePeerId: '',
        mlKemSecretKey: '',
      ),
    );
    expect(
      await localNotReady.handler.handle(
        IncomingCallSignalFrame(
          envelopeJson: localNotReady.envelope,
          authenticatedTransportPeerId: 'sender-device',
          route: CallRouteClass.ephemeralMailbox,
        ),
      ),
      IncomingCallSignalOutcome.deferred,
    );
  });

  test('transient verify and decrypt exceptions remain retryable', () async {
    for (final phase in <String>['verify', 'decrypt']) {
      final effects = _Effects();
      final coordinator = _coordinator(effects);
      final presenter = _Presenter();
      final crypto = _Crypto();
      final built = await _build(coordinator, presenter, crypto: crypto);
      if (phase == 'verify') {
        crypto.throwOnVerify = true;
      } else {
        crypto.throwOnDecrypt = true;
      }
      final frame = IncomingCallSignalFrame(
        envelopeJson: built.envelope,
        authenticatedTransportPeerId: 'sender-device',
        route: CallRouteClass.ephemeralMailbox,
      );

      expect(
        await built.handler.handle(frame),
        IncomingCallSignalOutcome.deferred,
        reason: phase,
      );
      expect(coordinator.activeSession, isNull, reason: phase);

      crypto.throwOnVerify = false;
      crypto.throwOnDecrypt = false;
      expect(
        await built.handler.handle(frame),
        IncomingCallSignalOutcome.accepted,
        reason: phase,
      );
      expect(presenter.calls, 1, reason: phase);
      await coordinator.dispose();
    }
  });

  test(
    'an invite whose terminal follows in the same page is superseded without '
    'presentation or dispatch',
    () async {
      final effects = _Effects();
      final coordinator = _coordinator(effects);
      addTearDown(coordinator.dispose);
      final built = await _build(coordinator, _Presenter());

      expect(
        await built.handler.handle(
          IncomingCallSignalFrame(
            envelopeJson: built.envelope,
            authenticatedTransportPeerId: 'sender-device',
            route: CallRouteClass.ephemeralMailbox,
            terminalFollows: true,
          ),
        ),
        IncomingCallSignalOutcome.superseded,
      );
      expect(coordinator.activeSession, isNull);
    },
  );

  test(
    'peek reads the call and event without consuming the envelope',
    () async {
      final effects = _Effects();
      final coordinator = _coordinator(effects);
      addTearDown(coordinator.dispose);
      final built = await _build(coordinator, _Presenter());
      final frame = IncomingCallSignalFrame(
        envelopeJson: built.envelope,
        authenticatedTransportPeerId: 'sender-device',
        route: CallRouteClass.ephemeralMailbox,
      );

      final peek = await built.handler.peek(frame);
      expect(peek?.event, CallSignalType.invite);
      expect(peek?.isTerminal, isFalse);
      expect(peek?.callId, isNotNull);
      expect(coordinator.activeSession, isNull);

      expect(
        await built.handler.handle(frame),
        IncomingCallSignalOutcome.accepted,
      );
      expect(coordinator.activeSession?.callId, peek?.callId);
    },
  );

  test('peek returns null for an envelope that fails authentication', () async {
    final effects = _Effects();
    final coordinator = _coordinator(effects);
    addTearDown(coordinator.dispose);
    final crypto = _Crypto();
    final built = await _build(coordinator, _Presenter(), crypto: crypto);
    crypto.throwOnVerify = true;

    expect(
      await built.handler.peek(
        IncomingCallSignalFrame(
          envelopeJson: built.envelope,
          authenticatedTransportPeerId: 'sender-device',
          route: CallRouteClass.ephemeralMailbox,
        ),
      ),
      isNull,
    );
  });
  // Beta 2026-09-25 (run-20260925-221131, 22:19:25.470): a direct invite that
  // arrived in time was routed and then left no trace, because every gate
  // below returned without a flow event. Each non-accepted outcome now leaves
  // exactly one identity-free CALL_INCOMING_SIGNAL_NOT_ACCEPTED record naming
  // the gate that refused it.
  group('CALL_INCOMING_SIGNAL_NOT_ACCEPTED', () {
    IncomingCallSignalFrame direct(String envelope) => IncomingCallSignalFrame(
      envelopeJson: envelope,
      authenticatedTransportPeerId: 'sender-device',
      route: CallRouteClass.direct,
    );

    IncomingCallSignalFrame mailbox(
      String envelope, {
      String? expectedCallHandle,
      int? expectedExpiresAtMs,
      String sender = 'sender-device',
      bool terminalFollows = false,
    }) => IncomingCallSignalFrame(
      envelopeJson: envelope,
      authenticatedTransportPeerId: sender,
      route: CallRouteClass.ephemeralMailbox,
      expectedCallHandle: expectedCallHandle,
      expectedExpiresAtMs: expectedExpiresAtMs,
      terminalFollows: terminalFollows,
    );

    Map<String, Object?> record({
      required String route,
      required String outcome,
      required String reason,
      String signal = 'unknown',
      String? reduction,
    }) => <String, Object?>{
      'route': route,
      'signal': signal,
      'outcome': outcome,
      'reason': reason,
      'reduction': ?reduction,
    };

    test('network gate refusals are recorded', () async {
      for (final gate in <CallNetworkEffectsAllowed>[
        () => false,
        () => throw StateError('migration authority unavailable'),
      ]) {
        final events = _captureNotAccepted();
        final coordinator = _coordinator(_Effects());
        addTearDown(coordinator.dispose);
        final built = await _build(
          coordinator,
          _Presenter(),
          networkEffectsAllowed: gate,
        );

        expect(
          await built.handler.handle(direct(built.envelope)),
          IncomingCallSignalOutcome.deferred,
        );
        expect(events, <Map<String, Object?>>[
          record(
            route: 'direct',
            outcome: 'deferred',
            reason: 'network_effects_blocked',
          ),
        ]);
      }
    });

    test('an expired mailbox wake is recorded before authentication', () async {
      final events = _captureNotAccepted();
      final coordinator = _coordinator(_Effects());
      addTearDown(coordinator.dispose);
      final built = await _build(coordinator, _Presenter());

      expect(
        await built.handler.handle(
          mailbox(
            built.envelope,
            expectedCallHandle: _callHandle,
            expectedExpiresAtMs: _nowMs,
          ),
        ),
        IncomingCallSignalOutcome.rejected,
      );
      expect(events, <Map<String, Object?>>[
        record(
          route: 'mailbox',
          outcome: 'rejected',
          reason: 'expired_before_authentication',
        ),
      ]);
    });

    test('sender and local authority gates are recorded', () async {
      final cases =
          <
            ({
              String reason,
              String outcome,
              CallTrustedRosterProvider roster,
              CallLocalAuthorityProvider? local,
              String sender,
            })
          >[
            (
              reason: 'roster_unavailable',
              outcome: 'deferred',
              roster: const _ThrowingRoster(),
              local: null,
              sender: 'sender-device',
            ),
            (
              reason: 'sender_unknown',
              outcome: 'rejected',
              roster: const _Roster(),
              local: null,
              sender: 'unknown-device',
            ),
            (
              reason: 'local_authority_unavailable',
              outcome: 'deferred',
              roster: const _Roster(),
              local: () async => const CallLocalDeviceAuthority(
                accountPeerId: '',
                devicePeerId: '',
                mlKemSecretKey: '',
              ),
              sender: 'sender-device',
            ),
            (
              reason: 'local_authority_unavailable',
              outcome: 'deferred',
              roster: const _Roster(),
              local: () async => throw StateError('identity store locked'),
              sender: 'sender-device',
            ),
          ];
      for (final value in cases) {
        final events = _captureNotAccepted();
        final coordinator = _coordinator(_Effects());
        addTearDown(coordinator.dispose);
        final built = await _build(
          coordinator,
          _Presenter(),
          trustedRosterProvider: value.roster,
          localAuthorityProvider: value.local,
        );

        await built.handler.handle(
          mailbox(built.envelope, sender: value.sender),
        );
        expect(events, <Map<String, Object?>>[
          record(
            route: 'mailbox',
            outcome: value.outcome,
            reason: value.reason,
          ),
        ], reason: value.reason);
      }
    });

    test('envelope refusals carry the envelope error code', () async {
      // Stale: the invite already expired on this device's clock.
      var clockMs = _nowMs;
      final staleEvents = _captureNotAccepted();
      final staleCoordinator = _coordinator(_Effects());
      addTearDown(staleCoordinator.dispose);
      final stale = await _build(
        staleCoordinator,
        _Presenter(),
        nowMs: () => clockMs,
      );
      clockMs = _nowMs + 46_000;
      expect(
        await stale.handler.handle(direct(stale.envelope)),
        IncomingCallSignalOutcome.rejected,
      );
      expect(staleEvents, <Map<String, Object?>>[
        record(
          route: 'direct',
          outcome: 'rejected',
          reason: 'envelope_expired',
        ),
      ]);

      // Skewed: the caller's clock runs 31 s ahead of this device.
      clockMs = _nowMs + 31_000;
      final skewEvents = _captureNotAccepted();
      final skewCoordinator = _coordinator(_Effects());
      addTearDown(skewCoordinator.dispose);
      final skewed = await _build(
        skewCoordinator,
        _Presenter(),
        nowMs: () => clockMs,
        signal: _invite(
          createdAtMs: _nowMs + 31_000,
          expiresAtMs: _nowMs + 31_000 + 45_000,
        ),
      );
      clockMs = _nowMs;
      expect(
        await skewed.handler.handle(direct(skewed.envelope)),
        IncomingCallSignalOutcome.rejected,
      );
      expect(skewEvents, <Map<String, Object?>>[
        record(
          route: 'direct',
          outcome: 'rejected',
          reason: 'envelope_excessiveClockSkew',
        ),
      ]);

      // Replayed: the mailbox copy of a direct invite that already rang.
      final replayEvents = _captureNotAccepted();
      final replayCoordinator = _coordinator(_Effects());
      addTearDown(replayCoordinator.dispose);
      final replayed = await _build(replayCoordinator, _Presenter());
      expect(
        await replayed.handler.handle(direct(replayed.envelope)),
        IncomingCallSignalOutcome.accepted,
      );
      expect(replayEvents, isEmpty, reason: 'an accepted signal is silent');
      expect(
        await replayed.handler.handle(mailbox(replayed.envelope)),
        IncomingCallSignalOutcome.duplicate,
      );
      expect(replayEvents, <Map<String, Object?>>[
        record(
          route: 'mailbox',
          outcome: 'duplicate',
          reason: 'envelope_replay',
        ),
      ]);
    });

    test('a mailbox binding mismatch is recorded', () async {
      final events = _captureNotAccepted();
      final coordinator = _coordinator(_Effects());
      addTearDown(coordinator.dispose);
      final built = await _build(coordinator, _Presenter());

      expect(
        await built.handler.handle(
          mailbox(
            built.envelope,
            expectedCallHandle: '44444444-4444-4444-8444-444444444444',
          ),
        ),
        IncomingCallSignalOutcome.rejected,
      );
      expect(events, <Map<String, Object?>>[
        record(
          route: 'mailbox',
          outcome: 'rejected',
          reason: 'expectation_mismatch',
        ),
      ]);
    });

    test('a superseded invite is recorded', () async {
      final events = _captureNotAccepted();
      final coordinator = _coordinator(_Effects());
      addTearDown(coordinator.dispose);
      final built = await _build(coordinator, _Presenter());

      expect(
        await built.handler.handle(
          mailbox(built.envelope, terminalFollows: true),
        ),
        IncomingCallSignalOutcome.superseded,
      );
      expect(events, <Map<String, Object?>>[
        record(
          route: 'mailbox',
          signal: 'invite',
          outcome: 'superseded',
          reason: 'superseded',
        ),
      ]);
    });

    test('negotiation material refusals are recorded', () async {
      final ice = _negotiationSignal(
        event: CallSignalType.ice,
        messageId: '77777777-7777-4777-8777-777777777777',
        senderSequence: 2,
        iceGeneration: 0,
        payload: const <String, Object?>{
          'candidate': 'secret-ice-candidate',
          'media_id': 'audio',
          'media_line_index': 0,
        },
      );
      final otherCall = CallSignal.create(
        callId: CallId.parse('88888888-8888-4888-8888-888888888888'),
        messageId: '99999999-9999-4999-8999-999999999999',
        event: CallSignalType.ice,
        senderAccountPeerId: 'sender-account',
        senderDevicePeerId: 'sender-device',
        recipientAccountPeerId: 'recipient-account',
        recipientDevicePeerId: 'recipient-device',
        senderSequence: 2,
        iceGeneration: 0,
        createdAtMs: _nowMs,
        expiresAtMs: _nowMs + 45_000,
        payload: const <String, Object?>{
          'candidate': 'other-ice-candidate',
          'media_id': 'audio',
          'media_line_index': 0,
        },
      );
      for (final value
          in <
            (String, IncomingCallSignalOutcome, CallNegotiationMaterialStore)
          >[
            (
              'negotiation_material_duplicate',
              IncomingCallSignalOutcome.duplicate,
              CallNegotiationMaterialStore()
                ..store(CallNegotiationMaterial.fromSignal(ice)),
            ),
            (
              'negotiation_material_capacityExceeded',
              IncomingCallSignalOutcome.rejected,
              CallNegotiationMaterialStore(maxCalls: 1)
                ..store(CallNegotiationMaterial.fromSignal(otherCall)),
            ),
          ]) {
        final events = _captureNotAccepted();
        final coordinator = _coordinator(_Effects());
        addTearDown(coordinator.dispose);
        final built = await _build(
          coordinator,
          _Presenter(),
          signal: ice,
          negotiationMaterialStore: value.$3,
        );

        expect(await built.handler.handle(direct(built.envelope)), value.$2);
        expect(events, <Map<String, Object?>>[
          record(
            route: 'direct',
            signal: 'ice',
            outcome: value.$2.name,
            reason: value.$1,
          ),
        ]);
      }
    });

    test(
      'a coordinator refusal names the decision and reducer reason',
      () async {
        final events = _captureNotAccepted();
        final coordinator = _coordinator(_Effects());
        addTearDown(coordinator.dispose);
        final built = await _build(
          coordinator,
          _Presenter(),
          signal: _negotiationSignal(
            event: CallSignalType.ice,
            messageId: '77777777-7777-4777-8777-777777777777',
            senderSequence: 2,
            iceGeneration: 0,
            payload: const <String, Object?>{
              'candidate': 'secret-ice-candidate',
              'media_id': 'audio',
              'media_line_index': 0,
            },
          ),
        );

        // No call is active: the candidate has nothing to join.
        expect(
          await built.handler.handle(direct(built.envelope)),
          IncomingCallSignalOutcome.rejected,
        );
        expect(events, <Map<String, Object?>>[
          record(
            route: 'direct',
            signal: 'ice',
            outcome: 'rejected',
            reason: 'coordinator_rejected',
            reduction: 'stateMismatch',
          ),
        ]);
      },
    );

    test('a validation refusal after the invite is recorded', () async {
      final events = _captureNotAccepted();
      late final CallCoordinator coordinator;
      // The invite's own validation effect ends the call before Dart marks
      // it validated.
      coordinator = _coordinator(
        _Effects(
          onExecute: (effect, snapshot) =>
              effect.type == CallEffectType.validateIncomingInvite
              ? CallEvent(
                  type: CallEventType.remoteTerminate,
                  eventId: 'terminate-during-validation',
                  occurredAt: DateTime.fromMillisecondsSinceEpoch(
                    _nowMs,
                    isUtc: true,
                  ),
                  callId: _callId,
                  contactPeerId: 'sender-account',
                )
              : null,
        ),
      );
      addTearDown(coordinator.dispose);
      final presenter = _Presenter();
      final built = await _build(coordinator, presenter);

      final outcome = await built.handler.handle(direct(built.envelope));
      expect(outcome, isNot(IncomingCallSignalOutcome.accepted));
      expect(presenter.calls, 0);
      expect(events, hasLength(1));
      expect(events.single['route'], 'direct');
      expect(events.single['signal'], 'invite');
      expect(events.single['outcome'], outcome.name);
      expect(events.single['reason'], startsWith('validation_'));
      expect(events.single['reduction'], isA<String>());
    });

    test('presentation gates are recorded', () async {
      // The native surface refuses the call.
      final refusedEvents = _captureNotAccepted();
      final refusedCoordinator = _coordinator(_Effects());
      addTearDown(refusedCoordinator.dispose);
      final refused = await _build(
        refusedCoordinator,
        _Presenter(succeeds: false),
      );
      expect(
        await refused.handler.handle(direct(refused.envelope)),
        IncomingCallSignalOutcome.rejected,
      );
      expect(refusedEvents, <Map<String, Object?>>[
        record(
          route: 'direct',
          signal: 'invite',
          outcome: 'rejected',
          reason: 'presentation_failed',
        ),
      ]);

      // The native surface throws.
      final threwEvents = _captureNotAccepted();
      final threwCoordinator = _coordinator(_Effects());
      addTearDown(threwCoordinator.dispose);
      final threw = await _build(
        threwCoordinator,
        _Presenter(throwOnPresent: true),
      );
      expect(
        await threw.handler.handle(direct(threw.envelope)),
        IncomingCallSignalOutcome.rejected,
      );
      expect(threwEvents.single['reason'], 'presentation_failed');

      // The invite expires while the native surface is still presenting.
      var nowMs = _nowMs;
      final expiredEvents = _captureNotAccepted();
      final expiredCoordinator = _coordinator(_Effects(), nowMs: () => nowMs);
      addTearDown(expiredCoordinator.dispose);
      final expiredGate = Completer<bool>();
      final expiredPresenter = _Presenter(resultGate: expiredGate);
      final expired = await _build(
        expiredCoordinator,
        expiredPresenter,
        nowMs: () => nowMs,
      );
      final expiring = expired.handler.handle(mailbox(expired.envelope));
      await expiredPresenter.started.future;
      nowMs += 45_000;
      expiredGate.complete(true);
      expect(await expiring, IncomingCallSignalOutcome.rejected);
      expect(expiredEvents, <Map<String, Object?>>[
        record(
          route: 'mailbox',
          signal: 'invite',
          outcome: 'rejected',
          reason: 'expired_during_presentation',
        ),
      ]);

      // The user declines natively while the surface is still presenting.
      final declinedEvents = _captureNotAccepted();
      final declinedCoordinator = _coordinator(_Effects());
      addTearDown(declinedCoordinator.dispose);
      final declineGate = Completer<bool>();
      final declinePresenter = _Presenter(resultGate: declineGate);
      final declined = await _build(declinedCoordinator, declinePresenter);
      final declining = declined.handler.handle(mailbox(declined.envelope));
      await declinePresenter.started.future;
      await declinedCoordinator.dispatch(
        CallEvent(
          type: CallEventType.nativeAction,
          eventId: 'native-decline-during-presentation',
          occurredAt: DateTime.fromMillisecondsSinceEpoch(_nowMs, isUtc: true),
          callId: _callId,
          nativeAction: CallNativeAction.decline,
        ),
      );
      declineGate.complete(true);
      expect(await declining, IncomingCallSignalOutcome.rejected);
      expect(declinedEvents, <Map<String, Object?>>[
        record(
          route: 'mailbox',
          signal: 'invite',
          outcome: 'rejected',
          reason: 'session_changed_during_presentation',
        ),
      ]);
    });

    test('a system UI refusal after presentation is recorded', () async {
      final events = _captureNotAccepted();
      final coordinator = _coordinator(_Effects());
      addTearDown(coordinator.dispose);
      final presenter = _Presenter();
      final lifecycle = _ProvisionalLifecycle(
        // The verified name lands only once the surface exists.
        contactUpdateAccepted: () => presenter.calls > 0,
        onCall: (call) {
          if (call == 'updateAuthenticatedContact:$_callHandle:Sender') {
            // The caller hangs up just after the surface appeared.
            unawaited(
              coordinator.dispatch(
                CallEvent(
                  type: CallEventType.remoteTerminate,
                  eventId: 'terminate-after-presentation',
                  occurredAt: DateTime.fromMillisecondsSinceEpoch(
                    _nowMs,
                    isUtc: true,
                  ),
                  callId: _callId,
                  contactPeerId: 'sender-account',
                ),
              ),
            );
          }
        },
      );
      final built = await _build(
        coordinator,
        presenter,
        provisionalNativeLifecycle: lifecycle,
        authenticatedDisplayNameResolver: (_) async => 'Sender',
      );

      expect(
        await built.handler.handle(direct(built.envelope)),
        IncomingCallSignalOutcome.rejected,
      );
      expect(presenter.calls, 1);
      expect(events, hasLength(1));
      expect(
        events.single,
        allOf(
          containsPair('route', 'direct'),
          containsPair('signal', 'invite'),
          containsPair('outcome', 'rejected'),
          containsPair('reason', 'system_ui_rejected'),
        ),
      );
    });

    test('a handler exception is recorded as deferred', () async {
      final events = _captureNotAccepted();
      final coordinator = _coordinator(_Effects(throwCount: 1));
      addTearDown(coordinator.dispose);
      final built = await _build(coordinator, _Presenter());

      expect(
        await built.handler.handle(mailbox(built.envelope)),
        IncomingCallSignalOutcome.deferred,
      );
      expect(events, <Map<String, Object?>>[
        record(
          route: 'mailbox',
          signal: 'invite',
          outcome: 'deferred',
          reason: 'handler_exception',
        ),
      ]);
    });

    test(
      'records carry only fixed codes, never call or peer identity',
      () async {
        final events = _captureNotAccepted();
        final coordinator = _coordinator(_Effects());
        addTearDown(coordinator.dispose);
        final built = await _build(coordinator, _Presenter(succeeds: false));
        await built.handler.handle(direct(built.envelope));
        await built.handler.handle(mailbox(built.envelope));
        await built.handler.handle(
          mailbox(built.envelope, sender: 'unknown-device'),
        );

        expect(events, hasLength(3));
        for (final event in events) {
          expect(
            event.keys.toSet().difference(<String>{
              'route',
              'signal',
              'outcome',
              'reason',
              'reduction',
            }),
            isEmpty,
          );
        }
        final encoded = jsonEncode(events);
        for (final secret in <String>[
          _callHandle,
          _callId.value,
          '11111111-1111-4111-8111-111111111111',
          'sender-account',
          'sender-device',
          'unknown-device',
          'recipient-account',
          'recipient-device',
        ]) {
          expect(encoded, isNot(contains(secret)));
        }
      },
    );
  });
}

List<Map<String, Object?>> _captureNotAccepted() {
  final events = <Map<String, Object?>>[];
  debugSetFlowEventSink((payload) {
    if (payload['event'] == 'CALL_INCOMING_SIGNAL_NOT_ACCEPTED') {
      events.add(Map<String, Object?>.from(payload['details'] as Map));
    }
  });
  addTearDown(() => debugSetFlowEventSink(null));
  return events;
}
