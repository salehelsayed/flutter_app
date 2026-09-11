import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/features/call/application/call_cleanup_coordinator.dart';
import 'package:flutter_app/features/call/application/call_coordinator.dart';
import 'package:flutter_app/features/call/application/call_endpoint_resolver.dart';
import 'package:flutter_app/features/call/application/call_history_projector.dart';
import 'package:flutter_app/features/call/application/call_negotiation_effect_executor.dart';
import 'package:flutter_app/features/call/application/call_negotiation_material_store.dart';
import 'package:flutter_app/features/call/application/handle_incoming_call_signal.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_event.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_signal.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/infrastructure/call_trusted_roster_provider.dart';
import 'package:flutter_app/features/call/infrastructure/flutter_webrtc_call_engine.dart';
import 'package:flutter_app/features/call/infrastructure/secure_call_envelope_codec.dart';
import 'package:flutter_app/features/call/infrastructure/webrtc_types.dart';
import 'package:flutter_test/flutter_test.dart';

final _callId = CallId.parse('55555555-5555-4555-8555-555555555555');
final _now = DateTime.utc(2026, 9, 11, 12);
const _fingerprint =
    'sha-256 00:01:02:03:04:05:06:07:08:09:0A:0B:0C:0D:0E:0F:'
    '10:11:12:13:14:15:16:17:18:19:1A:1B:1C:1D:1E:1F';
const _configuration = CallConnectionConfiguration(
  transportPolicy: CallTransportPolicy.relayOnly,
  receiveAudio: true,
  receiveVideo: false,
  captureAudio: true,
  captureVideo: false,
);

CallSessionDescription _description(CallSessionDescriptionType type) =>
    CallSessionDescription(
      type: type,
      value: <String>[
        'v=0',
        'o=- 0 0 IN IP4 127.0.0.1',
        's=-',
        't=0 0',
        'm=audio 9 UDP/TLS/RTP/SAVPF 111',
        'a=mid:0',
        'a=fingerprint:$_fingerprint',
        'a=sendrecv',
      ].join('\r\n'),
      fingerprint: _fingerprint,
    );

CallIceCandidate _candidate(int index, {int generation = 0}) =>
    CallIceCandidate(
      value: 'candidate:$index 1 UDP 1 192.0.2.1 ${10000 + index} typ relay',
      mediaId: '0',
      mediaLineIndex: 0,
      iceGeneration: generation,
    );

Map<String, Object?> _payload(CallIceCandidate candidate) => <String, Object?>{
  'candidate': candidate.value,
  'media_id': candidate.mediaId,
  'media_line_index': candidate.mediaLineIndex,
};

void main() {
  for (final incoming in <bool>[true, false]) {
    for (final count in <int>[0, 1, 8, 9, 64]) {
      test('${incoming ? 'offer' : 'answer'} drains $count authenticated '
          'pre-SDP candidates through the real engine', () async {
        final h = _Harness(incoming: incoming);
        addTearDown(h.close);
        await h.start();
        // SDP is signed first; independent authenticated streams deliver the
        // later ICE ahead of it, within the protocol's 64-sequence window.
        final description = await h.remoteDescriptionFrame();
        final expected = List.generate(count, _candidate);
        for (final candidate in expected) {
          expect(await h.ice(candidate), IncomingCallSignalOutcome.accepted);
          expect(h.coordinator.activeSession!.pendingCandidateIds, isEmpty);
          expect(h.materials.entryCountFor(_callId), 0);
        }
        expect(h.pending, count);
        expect(h.native.batches, isEmpty);

        expect(
          await h.receiver.handle(description),
          IncomingCallSignalOutcome.accepted,
        );
        await h.settle();

        expect(h.coordinator.activeSession?.state, CallState.negotiating);
        expect(
          h.native.applied.map((c) => c.value),
          expected.map((c) => c.value),
        );
        expect(
          h.native.batches.map((b) => b.length),
          everyElement(inInclusiveRange(1, 8)),
        );
        expect(h.pending, 0);
        expect(h.history.entries, isEmpty);

        final late = _candidate(100);
        expect(await h.ice(late), IncomingCallSignalOutcome.accepted);
        expect(h.native.applied.last.value, late.value);
        expect(h.native.applied, hasLength(count + 1));
      });
    }
  }

  test(
    'the integration engine rejects nine candidates before native mutation',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      await h.start();
      await h.remoteDescription();
      await h.settle();
      await expectLater(
        h.engine.addIceCandidates(List.generate(9, _candidate)),
        throwsA(
          isA<CallEngineException>().having(
            (error) => error.code,
            'code',
            CallEngineErrorCode.candidateOverflow,
          ),
        ),
      );
      expect(h.native.batches, isEmpty);
    },
  );

  test('drain honors a configured engine batch capacity of two', () async {
    final h = _Harness(batchCapacity: 2);
    addTearDown(h.close);
    await h.start();
    for (var i = 0; i < 9; i++) {
      await h.ice(_candidate(i));
    }
    await h.remoteDescription();
    await h.settle();
    expect(h.native.batches.map((batch) => batch.length), <int>[2, 2, 2, 2, 1]);
    expect(
      h.native.applied.map((c) => c.value),
      List.generate(9, _candidate).map((c) => c.value),
    );
    expect(h.coordinator.activeSession?.state, CallState.negotiating);
  });

  test(
    'the 65th pre-SDP candidate triggers bounded terminal cleanup',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      await h.start();
      for (var i = 0; i < 64; i++) {
        expect(await h.ice(_candidate(i)), IncomingCallSignalOutcome.accepted);
      }
      expect(h.pending, 64);
      expect(h.native.applied, isEmpty);
      await h.ice(_candidate(64));
      expect(h.coordinator.lastSnapshot?.endReason, CallEndReason.mediaFailed);
      expect(h.coordinator.activeSession, isNull);
      expect(h.pending, 0);
      expect(h.materials.entryCountFor(_callId), 0);
      expect(h.native.batches, isEmpty);
      expect(h.cleanupCount, 1);
      expect(h.native.closeCalls, 1);
    },
  );

  test(
    'authenticated replay and reducer candidate IDs remain deduplicated',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      await h.start();
      final frames = <IncomingCallSignalFrame>[];
      for (var i = 0; i < 9; i++) {
        final frame = await h.frame(
          CallSignalType.ice,
          payload: _payload(_candidate(i)),
        );
        frames.add(frame);
        expect(
          await h.receiver.handle(frame),
          IncomingCallSignalOutcome.accepted,
        );
        expect(
          await h.receiver.handle(frame),
          IncomingCallSignalOutcome.duplicate,
        );
      }
      expect(h.pending, 9);
      await h.remoteDescription();
      await h.settle();
      for (final frame in frames) {
        expect(
          await h.receiver.handle(frame),
          IncomingCallSignalOutcome.duplicate,
        );
      }
      final replay = await h.coordinator.dispatch(
        CallEvent(
          type: CallEventType.remoteIce,
          eventId: 'different-event-same-candidate',
          candidateId: frames.last.expectedMessageId,
          callId: _callId,
          occurredAt: _now,
        ),
      );
      expect(replay.reason, CallReductionReason.duplicateEvent);
      expect(h.native.applied, hasLength(9));
      expect(h.native.applied.map((c) => c.value).toSet(), hasLength(9));
    },
  );

  test(
    'unauthenticated ICE never enters the material store or pending queue',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      await h.start();
      final frame = await h.frame(
        CallSignalType.ice,
        payload: _payload(_candidate(0)),
      );
      expect(
        await h.receiver.handle(
          IncomingCallSignalFrame(
            envelopeJson: frame.envelopeJson,
            authenticatedTransportPeerId: 'untrusted-device',
            route: frame.route,
          ),
        ),
        IncomingCallSignalOutcome.rejected,
      );
      expect(h.materials.entryCountFor(_callId), 0);
      expect(h.pending, 0);
      expect(h.native.batches, isEmpty);
      expect(
        await h.receiver.handle(frame),
        IncomingCallSignalOutcome.accepted,
      );
    },
  );

  test(
    'malformed material and non-relay candidates still fail closed',
    () async {
      for (final malformed in <bool>[true, false]) {
        final h = _Harness();
        addTearDown(h.close);
        await h.start();
        await h.remoteDescription();
        await h.settle();
        if (malformed) {
          // Exercise the executor's validation independently of the wire schema.
          final result = await h.deliverMaterial(const <String, Object?>{
            'candidate': 42,
          });
          expect(result?.type, CallEventType.negotiationFailed);
          await h.coordinator.dispatch(result!);
        } else {
          await h.ice(
            const CallIceCandidate(
              value: 'candidate:1 1 UDP 1 192.0.2.1 10000 typ host',
              mediaId: '0',
              mediaLineIndex: 0,
              iceGeneration: 0,
            ),
          );
        }
        expect(h.native.batches, isEmpty);
        expect(
          h.coordinator.lastSnapshot?.endReason,
          CallEndReason.mediaFailed,
        );
        expect(h.cleanupCount, 1);
      }
    },
  );

  test(
    'restart drops buffered stale ICE and drains current generation in order',
    () async {
      final h = _Harness(incoming: false);
      addTearDown(h.close);
      await h.start();
      for (var i = 0; i < 9; i++) {
        await h.ice(_candidate(i));
      }
      expect(
        await h.send(CallSignalType.iceRestart, generation: 1),
        IncomingCallSignalOutcome.accepted,
      );
      expect(h.engine.iceGeneration, 1);
      final current = List.generate(
        9,
        (i) => _candidate(i + 20, generation: 1),
      );
      for (final candidate in current) {
        await h.ice(candidate);
      }
      expect(h.pending, 18);
      expect(await h.ice(_candidate(99)), IncomingCallSignalOutcome.rejected);
      await h.remoteDescription(generation: 1);
      await h.settle();
      expect(h.pending, 0);
      expect(h.native.applied.map((c) => c.value), current.map((c) => c.value));
      expect(h.native.applied.map((c) => c.iceGeneration), everyElement(1));
    },
  );

  test('permitted future ICE waits for the mirrored restart offer', () async {
    final h = _Harness();
    addTearDown(h.close);
    await h.start();
    await h.remoteDescription();
    await h.settle();
    await h.coordinator.dispatch(h.event(CallEventType.mediaConnected));
    final future = List.generate(9, (i) => _candidate(i, generation: 1));
    for (final candidate in future) {
      expect(await h.ice(candidate), IncomingCallSignalOutcome.accepted);
    }
    expect(h.engine.iceGeneration, 0);
    expect(h.pending, 9);
    expect(h.native.applied, isEmpty);
    await h.remoteDescription(generation: 1);
    await h.settle();
    expect(h.engine.iceGeneration, 1);
    expect(h.pending, 0);
    expect(h.native.applied.map((c) => c.value), future.map((c) => c.value));
    expect(h.native.applied.map((c) => c.iceGeneration), everyElement(1));
    expect(
      await h.ice(_candidate(20, generation: 1)),
      IncomingCallSignalOutcome.accepted,
    );
    expect(h.native.applied, hasLength(10));
  });

  test('a current drain retains candidates for a future description', () async {
    final h = _Harness();
    addTearDown(h.close);
    await h.start();
    for (var i = 0; i < 9; i++) {
      await h.ice(_candidate(i));
    }
    final gate = h.native.descriptionGate = Completer<void>();
    final description = h.remoteDescription();
    await h.native.descriptionEntered.future;
    // Stress the executor boundary during the SDP await. Ordinary coordinator
    // dispatch serializes these effects; no permissive engine fake is involved.
    for (var i = 20; i < 29; i++) {
      await h.deliverMaterial(
        _payload(_candidate(i, generation: 1)),
        generation: 1,
      );
    }
    gate.complete();
    await description;
    await h.settle();
    expect(h.native.applied, hasLength(9));
    expect(h.native.applied.map((c) => c.iceGeneration), everyElement(0));
    expect(h.pending, 9);
    await h.coordinator.dispatch(h.event(CallEventType.mediaConnected));
    await h.remoteDescription(generation: 1);
    await h.settle();
    expect(h.pending, 0);
    expect(
      h.native.applied.skip(9).map((c) => c.value),
      List.generate(9, (i) => _candidate(i + 20, generation: 1).value),
    );
  });

  test(
    'a later partially applied batch fails once and cleans up without replay',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      await h.start();
      h.native.failBatch = 2;
      for (var i = 0; i < 17; i++) {
        await h.ice(_candidate(i));
      }
      await h.remoteDescription();
      await h.settle();
      expect(h.native.batches.map((b) => b.length), <int>[8, 8]);
      expect(
        h.native.applied.map((c) => c.value),
        List.generate(9, _candidate).map((c) => c.value),
      );
      expect(h.coordinator.lastSnapshot?.endReason, CallEndReason.mediaFailed);
      expect(h.cleanupCount, 1);
      expect(h.history.entries, hasLength(1));
      expect(h.pending, 0);
      expect(h.engine.isClosed, isTrue);
      await h.remoteDescription();
      await h.settle();
      expect(h.native.batches, hasLength(2));
      expect(h.cleanupCount, 1);
    },
  );

  for (final incoming in <bool>[true, false]) {
    for (final duringDescription in <bool>[false, true]) {
      test(
        '${incoming ? 'offer' : 'answer'} hangup during '
        '${duringDescription ? 'SDP' : 'drain'} fences late work and a subsequent call',
        () async {
          final h = _Harness(incoming: incoming);
          addTearDown(h.close);
          await h.start();
          for (var i = 0; i < 17; i++) {
            await h.ice(_candidate(i));
          }
          final gate = Completer<void>();
          if (duringDescription) {
            h.native.descriptionGate = gate;
          } else {
            h.native.batchGate = gate;
          }
          final descriptionsBefore = h.signaling.descriptions.length;
          final delivery = h.remoteDescription();
          await (duringDescription
              ? h.native.descriptionEntered.future
              : h.native.batchEntered.future);
          await h.coordinator.dispatch(h.event(CallEventType.end));
          expect(
            h.coordinator.lastSnapshot?.endReason,
            CallEndReason.localHangup,
          );
          expect(h.engine.isClosed, isTrue);
          expect(h.cleanupCount, 1);
          final nextId = CallId.parse('66666666-6666-4666-8666-666666666666');
          await h.coordinator.dispatch(
            CallEvent(
              type: CallEventType.place,
              eventId: 'next-call',
              callId: nextId,
              contactPeerId: 'remote-account',
              localAccountPeerId: 'local-account',
              localDeviceId: 'local-device',
              occurredAt: _now,
            ),
          );
          gate.complete();
          await delivery;
          await Future.wait(List.of(h.effects.executions));
          expect(h.native.batches, hasLength(duringDescription ? 0 : 1));
          expect(h.signaling.descriptions, hasLength(descriptionsBefore));
          expect(h.pending, 0);
          expect(h.coordinator.activeSession?.callId, nextId);
        },
      );
    }
  }

  test(
    'a generation change across a native batch await stops the old drain',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      await h.start();
      for (var i = 0; i < 17; i++) {
        await h.ice(_candidate(i));
      }
      final gate = h.native.batchGate = Completer<void>();
      final delivery = h.remoteDescription();
      await h.native.batchEntered.future;
      await h.engine.restartIce();
      gate.complete();
      await delivery;
      await h.settle();
      expect(h.engine.iceGeneration, 1);
      expect(h.native.batches, hasLength(1));
      expect(h.signaling.descriptions, isEmpty);
    },
  );
}

/// Production admission, reducer, material storage, executor and engine. Only
/// external crypto primitives, signaling/media ports and native WebRTC are fake.
final class _Harness {
  _Harness({this.incoming = true, int? batchCapacity}) {
    engine = batchCapacity == null
        ? FlutterWebRtcCallEngine(adapter: native)
        : FlutterWebRtcCallEngine(
            adapter: native,
            candidateBatchCapacity: batchCapacity,
          );
    executor = CallNegotiationEffectExecutor(
      engine: engine,
      materialStore: materials,
      mediaPreparer: _Preparer(engine),
      signaling: signaling,
      configuration: _configuration,
      dispatchEvent: (event) async {
        await coordinator.dispatch(event);
      },
      readActiveSnapshot: () => coordinator.activeSession,
      readStagedIceServers: (_) async => const <CallIceServer>[],
      clock: () => _now,
    );
    effects = _Effects(executor);
    coordinator = CallCoordinator(
      reducer: const CallReducer(),
      cleanupCoordinator: CallCleanupCoordinator(<CallCleanupStep>[
        CallCleanupStep('media', (_) async {
          cleanupCount++;
          await executor.close();
        }, requiredForTerminalAck: true),
      ]),
      historyProjector: CallHistoryProjector(history),
      effectExecutor: effects,
      clock: () => _now,
      idSource: () => _callId,
    );
    receiver = HandleIncomingCallSignal(
      codec: codec,
      coordinator: coordinator,
      trustedRosterProvider: const _Roster(),
      localAuthorityProvider: () async => const CallLocalDeviceAuthority(
        accountPeerId: 'local-account',
        devicePeerId: 'local-device',
        mlKemSecretKey: 'synthetic-local-secret',
      ),
      incomingCallPresenter: _Presenter(),
      networkEffectsAllowed: () => true,
      negotiationMaterialStore: materials,
    );
  }

  final bool incoming;
  final native = _Native();
  final materials = CallNegotiationMaterialStore();
  final history = _History();
  final signaling = _Signaling();
  final codec = SecureCallEnvelopeCodec(
    crypto: _Crypto(),
    nowMs: () => _now.millisecondsSinceEpoch,
  );
  late final FlutterWebRtcCallEngine engine;
  late final CallNegotiationEffectExecutor executor;
  late final CallCoordinator coordinator;
  late final HandleIncomingCallSignal receiver;
  late final _Effects effects;
  int sequence = 0;
  int cleanupCount = 0;

  int get pending =>
      executor.toDiagnosticMap()['pendingRemoteCandidateCount']! as int;

  CallEvent event(CallEventType type) => CallEvent(
    type: type,
    eventId: 'local-${sequence++}',
    occurredAt: _now,
    callId: _callId,
  );

  Future<void> start() async {
    if (incoming) {
      expect(
        await send(CallSignalType.invite),
        IncomingCallSignalOutcome.accepted,
      );
      expect(
        (await coordinator.dispatch(event(CallEventType.answer))).decision,
        CallEventDecision.applied,
      );
    } else {
      await coordinator.placeCall(
        contactPeerId: 'remote-account',
        localAccountPeerId: 'local-account',
        localDeviceId: 'local-device',
      );
      await coordinator.dispatch(event(CallEventType.outgoingInviteReady));
      await send(CallSignalType.ringing);
      expect(
        await send(CallSignalType.accept),
        IncomingCallSignalOutcome.accepted,
      );
      await settle();
    }
    expect(
      coordinator.activeSession?.state,
      incoming ? CallState.accepted : CallState.negotiating,
    );
  }

  Future<IncomingCallSignalFrame> frame(
    CallSignalType type, {
    int generation = 0,
    Map<String, Object?> payload = const <String, Object?>{},
  }) async {
    final next = ++sequence;
    final signal = CallSignal.create(
      callId: _callId,
      messageId: '11111111-1111-4111-8111-${next.toString().padLeft(12, '0')}',
      event: type,
      senderAccountPeerId: 'remote-account',
      senderDevicePeerId: 'remote-device',
      recipientAccountPeerId: 'local-account',
      recipientDevicePeerId: 'local-device',
      senderSequence: next,
      iceGeneration: generation,
      createdAtMs: _now.millisecondsSinceEpoch,
      expiresAtMs: _now.millisecondsSinceEpoch + 45000,
      payload: payload,
    );
    return IncomingCallSignalFrame(
      envelopeJson: await codec.encode(
        signal: signal,
        callHandle: _callId.value,
        recipientMlKemPublicKey: 'synthetic-local-public',
        senderSigningPrivateKey: 'synthetic-remote-signing',
      ),
      authenticatedTransportPeerId: 'remote-device',
      route: CallRouteClass.direct,
      expectedMessageId: signal.messageId,
    );
  }

  Future<IncomingCallSignalOutcome> send(
    CallSignalType type, {
    int generation = 0,
    Map<String, Object?> payload = const <String, Object?>{},
  }) async => receiver.handle(
    await frame(type, generation: generation, payload: payload),
  );

  Future<IncomingCallSignalOutcome> ice(CallIceCandidate candidate) => send(
    CallSignalType.ice,
    generation: candidate.iceGeneration,
    payload: _payload(candidate),
  );

  Future<IncomingCallSignalFrame> remoteDescriptionFrame({
    int generation = 0,
  }) => frame(
    incoming ? CallSignalType.offer : CallSignalType.answer,
    generation: generation,
    payload: <String, Object?>{
      'description': _description(
        incoming
            ? CallSessionDescriptionType.offer
            : CallSessionDescriptionType.answer,
      ).value,
      'fingerprint': _fingerprint,
    },
  );

  Future<IncomingCallSignalOutcome> remoteDescription({
    int generation = 0,
  }) async =>
      receiver.handle(await remoteDescriptionFrame(generation: generation));

  // An invalid local action is a queue barrier with no effects. Inbound offers
  // acknowledge admission before the coordinator finishes their media effects.
  Future<void> settle() async {
    await coordinator.dispatch(event(CallEventType.nativeAction));
  }

  Future<CallEvent?> deliverMaterial(
    Map<String, Object?> payload, {
    int generation = 0,
  }) {
    final eventId = 'executor-material-${sequence++}';
    expect(
      materials.store(
        CallNegotiationMaterial(
          callId: _callId,
          eventId: eventId,
          type: CallNegotiationMaterialType.ice,
          iceGeneration: generation,
          payload: payload,
        ),
      ),
      CallNegotiationMaterialStoreDecision.stored,
    );
    return executor.execute(
      const CallEffect(CallEffectType.queueIceCandidate),
      coordinator.activeSession!.copyWith(recentEventIds: <String>[eventId]),
    );
  }

  Future<void> close() async {
    await executor.close();
    await coordinator.dispose();
    await native.eventsController.close();
  }
}

final class _Effects implements CallEffectExecutor {
  _Effects(this.executor);
  final CallNegotiationEffectExecutor executor;
  final List<Future<CallEvent?>> executions = <Future<CallEvent?>>[];

  @override
  Future<CallEvent?> execute(CallEffect effect, CallSessionSnapshot snapshot) {
    final future = executor.execute(effect, snapshot);
    executions.add(future);
    return future;
  }
}

final class _Preparer implements CallNegotiationMediaPreparer {
  _Preparer(this.engine);
  final CallEngine engine;
  @override
  Future<void> prepareLocallyAcceptedMedia({
    required CallSessionSnapshot snapshot,
    required CallConnectionConfiguration configuration,
  }) => engine.createConnection(configuration);
}

final class _Signaling implements CallNegotiationSignalingPort {
  final descriptions = <CallSessionDescription>[];
  @override
  Future<void> sendDescription({
    required CallId callId,
    required CallSessionDescription description,
    required int iceGeneration,
  }) async {
    descriptions.add(description);
  }

  @override
  Future<void> sendCandidates({
    required CallId callId,
    required List<CallIceCandidate> candidates,
  }) async {}
  @override
  Future<void> sendIceRestart({
    required CallId callId,
    required int iceGeneration,
  }) async {}
}

final class _Native implements WebRtcPeerConnectionAdapter {
  final eventsController =
      StreamController<WebRtcPeerConnectionEvent>.broadcast(sync: true);
  final batches = <List<CallIceCandidate>>[];
  final applied = <CallIceCandidate>[];
  final batchEntered = Completer<void>();
  Completer<void>? batchGate;
  Completer<void>? descriptionGate;
  final descriptionEntered = Completer<void>();
  int? failBatch;
  int closeCalls = 0;
  @override
  bool isClosed = false;
  @override
  Stream<WebRtcPeerConnectionEvent> get events => eventsController.stream;
  @override
  Future<void> create(WebRtcPeerConnectionConfiguration configuration) async {}
  @override
  Future<CallSessionDescription> createOffer() async =>
      _description(CallSessionDescriptionType.offer);
  @override
  Future<CallSessionDescription> createAnswer() async =>
      _description(CallSessionDescriptionType.answer);
  @override
  Future<void> setLocalDescription(CallSessionDescription description) async {
    expect(isClosed, isFalse);
  }

  @override
  Future<void> setRemoteDescription(CallSessionDescription description) async {
    expect(isClosed, isFalse);
    if (!descriptionEntered.isCompleted) descriptionEntered.complete();
    if (descriptionGate case final gate?) await gate.future;
  }

  @override
  Future<void> addIceCandidates(List<CallIceCandidate> candidates) async {
    expect(
      isClosed,
      isFalse,
      reason: 'no delivery may start on a closed native engine',
    );
    batches.add(List.of(candidates));
    if (!batchEntered.isCompleted) batchEntered.complete();
    if (batchGate case final gate?) await gate.future;
    if (batches.length == failBatch) {
      // Native loops may have applied part of a failed batch. Retrying it is
      // unsafe; cleanup must own the failure, including these partial effects.
      applied.add(candidates.first);
      throw const WebRtcAdapterException(WebRtcFailureReason.other);
    }
    applied.addAll(candidates);
  }

  @override
  Future<void> restartIce() async {}
  @override
  Future<void> setLocalAudioEnabled(bool enabled) async {}
  @override
  Future<WebRtcPeerConnectionSnapshot> snapshot() async =>
      WebRtcPeerConnectionSnapshot(
        isClosed: isClosed,
        iceTransportPolicy: WebRtcIceTransportPolicy.relayOnly,
        localAudioCaptureTrackCount: 1,
        localVideoCaptureTrackCount: 0,
        audioReceiveTransceiverCount: 1,
        videoTransceiverCount: 0,
      );
  @override
  Future<void> close() async {
    closeCalls++;
    isClosed = true;
  }
}

final class _History implements CallHistoryRepository {
  final entries = <CallHistoryEntry>[];
  @override
  Future<CallHistoryEntry?> getByCallId(CallId callId) async => null;
  @override
  Future<List<CallHistoryEntry>> listForContact(String peerId) async =>
      const [];
  @override
  Future<void> upsertTerminal(CallHistoryEntry entry) async {
    entries.add(entry);
  }
}

final class _Presenter implements IncomingCallPresenter {
  @override
  Future<bool> present(IncomingCallPresentation presentation) async => true;
  @override
  Future<void> dismiss(IncomingCallPresentation presentation) async {}
}

final class _Roster implements CallTrustedRosterProvider {
  const _Roster();
  @override
  Future<CallTrustedRosterSnapshot> loadForContact(String peerId) async =>
      throw UnimplementedError();
  @override
  Future<TrustedCallDeviceAuthority?> resolveAuthenticatedTransport(
    String transportPeerId,
  ) async => transportPeerId == 'remote-device'
      ? const TrustedCallDeviceAuthority(
          accountPeerId: 'remote-account',
          devicePeerId: 'remote-device',
          linked: true,
          deviceKeyEpoch: 1,
          signingPublicKey: 'synthetic-remote-signing',
          mlKemPublicKey: 'synthetic-remote-mlkem',
        )
      : null;
}

final class _Crypto implements CallEnvelopeCrypto {
  @override
  Future<CallCiphertext> encrypt({
    required String recipientMlKemPublicKey,
    required String plaintext,
  }) async => CallCiphertext(
    kem: base64Encode([1]),
    ciphertext: base64Encode(utf8.encode(plaintext)),
    nonce: base64Encode([2]),
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
