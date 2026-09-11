import 'dart:async';

import 'package:flutter_app/features/call/application/call_cleanup_coordinator.dart';
import 'package:flutter_app/features/call/application/call_coordinator.dart';
import 'package:flutter_app/features/call/application/call_history_projector.dart';
import 'package:flutter_app/features/call/application/call_negotiation_effect_executor.dart';
import 'package:flutter_app/features/call/application/call_negotiation_material_store.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_event.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_test/flutter_test.dart';

final _callId = CallId.parse('55555555-5555-4555-8555-555555555555');
final _otherCallId = CallId.parse('66666666-6666-4666-8666-666666666666');
final _now = DateTime.utc(2026, 8, 30, 12);
const _fingerprint =
    'sha-256 AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:'
    'AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA';

CallSessionSnapshot _snapshot(
  CallState state, {
  CallId? callId,
  CallDirection direction = CallDirection.outgoing,
  List<String> recentEventIds = const <String>['accepted-event'],
}) => CallSessionSnapshot.active(
  callId: callId ?? _callId,
  contactPeerId: 'contact-a',
  direction: direction,
  state: state,
  callerAccountPeerId: 'local-account',
  callerDeviceId: 'local-device',
  startedAt: _now,
  observedAt: _now,
  acceptedAt: _now,
  endedAt: state == CallState.ended ? _now : null,
  endReason: state == CallState.ended ? CallEndReason.localHangup : null,
  recentEventIds: recentEventIds,
);

const _configuration = CallConnectionConfiguration(
  transportPolicy: CallTransportPolicy.relayOnly,
  receiveAudio: true,
  receiveVideo: false,
  captureAudio: true,
  captureVideo: false,
);

CallNegotiationMaterial _material({
  required String eventId,
  required CallNegotiationMaterialType type,
  int generation = 0,
  required Map<String, Object?> payload,
}) => CallNegotiationMaterial(
  callId: _callId,
  eventId: eventId,
  type: type,
  iceGeneration: generation,
  payload: payload,
);

Future<void> _flushAsync([int turns = 8]) async {
  for (var index = 0; index < turns; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  for (final replaced in [false, true]) {
    test(
      'restart credentials cannot mutate ${replaced ? 'a replacement' : 'an ended call'}',
      () async {
        final pending = Completer<List<CallIceServer>>();
        final h = _Harness(
          snapshot: _snapshot(CallState.reconnecting),
          stagedReader: (_) => pending.future,
        );
        addTearDown(h.executor.close);
        final result = h.executor.execute(
          const CallEffect(CallEffectType.restartIce),
          h.snapshot,
        );
        await _flushAsync();
        h.snapshot = replaced
            ? _snapshot(CallState.negotiating, callId: _otherCallId)
            : _snapshot(CallState.ended);
        pending.complete(h.stagedServers);
        expect(await result, isNull);
        expect(h.engine.restartCalls, 0);
        expect(h.signaling.restartGenerations, isEmpty);
      },
    );
  }

  test(
    'processed remote ICE does not exhaust capacity across restarts',
    () async {
      const reducer = CallReducer();
      final harness = _Harness(
        snapshot: _snapshot(
          CallState.accepted,
          direction: CallDirection.incoming,
        ),
      );
      addTearDown(harness.executor.close);

      Future<CallReduction> dispatch(CallEvent event) async {
        final reduction = reducer.reduce(harness.snapshot, event);
        harness.snapshot = reduction.snapshot;
        for (final effect in reduction.effects) {
          final followUp = await harness.executor.execute(
            effect,
            harness.snapshot,
          );
          if (followUp != null) await dispatch(followUp);
        }
        return reduction;
      }

      CallEvent event(CallEventType type, String id) => CallEvent(
        type: type,
        eventId: id,
        occurredAt: _now,
        callId: _callId,
        candidateId: type == CallEventType.remoteIce ? id : null,
      );

      for (var generation = 0; generation < 4; generation++) {
        if (generation > 0) {
          harness.engine.restartGeneration = generation;
          final restartId = 'restart-$generation';
          harness.materialStore.store(
            _material(
              eventId: restartId,
              type: CallNegotiationMaterialType.iceRestart,
              generation: generation,
              payload: const <String, Object?>{},
            ),
          );
          await dispatch(event(CallEventType.remoteIceRestart, restartId));
        }

        // Exercise both executor-buffered and immediately applied candidates.
        for (var index = 0; index < 24; index++) {
          if (index == 2) {
            final offerId = 'offer-$generation';
            harness.materialStore.store(
              _material(
                eventId: offerId,
                type: CallNegotiationMaterialType.offer,
                generation: generation,
                payload: <String, Object?>{
                  'description': 'offer-$generation',
                  'fingerprint': _fingerprint,
                },
              ),
            );
            await dispatch(event(CallEventType.remoteOffer, offerId));
          }
          final candidateId = 'candidate-$generation-$index';
          harness.materialStore.store(
            _material(
              eventId: candidateId,
              type: CallNegotiationMaterialType.ice,
              generation: generation,
              payload: <String, Object?>{
                'candidate': candidateId,
                'media_id': 'audio',
                'media_line_index': 0,
              },
            ),
          );
          final admitted = await dispatch(
            event(CallEventType.remoteIce, candidateId),
          );
          expect(
            admitted.decision,
            CallEventDecision.applied,
            reason: candidateId,
          );
        }
        await dispatch(
          event(CallEventType.mediaConnected, 'connected-$generation'),
        );
        expect(harness.snapshot.state, CallState.connected);
      }

      expect(
        harness.engine.addedCandidates.expand((batch) => batch),
        hasLength(96),
      );
      expect(harness.snapshot.pendingCandidateIds, isEmpty);
      final replay = await dispatch(
        event(CallEventType.remoteIce, 'candidate-3-23'),
      );
      expect(replay.reason, CallReductionReason.duplicateEvent);
      expect(
        harness.engine.addedCandidates.expand((batch) => batch),
        hasLength(96),
      );
    },
  );

  for (final incoming in <bool>[false, true]) {
    for (final pausePreparation in <bool>[false, true]) {
      test(
        '${incoming ? 'answer' : 'offer'} is not sent after close during ${pausePreparation ? 'preparation' : 'local description'}',
        () async {
          final harness = _Harness(
            snapshot: _snapshot(
              CallState.negotiating,
              direction: incoming
                  ? CallDirection.incoming
                  : CallDirection.outgoing,
            ),
          );
          final gate = Completer<void>();
          if (pausePreparation) {
            harness.preparer.gate = gate;
          } else {
            harness.engine.localDescriptionGate = gate;
          }
          if (incoming) {
            harness.materialStore.store(
              _material(
                eventId: 'accepted-event',
                type: CallNegotiationMaterialType.offer,
                payload: {
                  'description': 'remote-offer',
                  'fingerprint': _fingerprint,
                },
              ),
            );
          }
          final preparing = harness.executor.execute(
            CallEffect(
              incoming
                  ? CallEffectType.deliverOffer
                  : CallEffectType.startNegotiation,
            ),
            harness.snapshot,
          );
          await _flushAsync();
          expect(
            harness.calls,
            contains(pausePreparation ? 'media.prepare' : 'engine.local'),
          );
          await harness.executor.close();
          gate.complete();
          await preparing;
          expect(harness.signaling.descriptions, isEmpty);
          if (pausePreparation) {
            expect(harness.engine.descriptionWorkCount, 0);
          }
        },
      );
    }
  }

  test(
    'offer-first restart recovers twice and late announcements do not strand the receiver',
    () async {
      final harness = _Harness(
        snapshot: _snapshot(
          CallState.connected,
          direction: CallDirection.incoming,
        ),
      );
      addTearDown(harness.executor.close);
      const reducer = CallReducer();
      for (final generation in [1, 2]) {
        final offerId = 'restart-offer-$generation';
        harness.engine.restartGeneration = generation;
        harness.engine.connectionSnapshot = _connectionSnapshot(
          state: CallConnectionState.connecting,
          ready: false,
        );
        harness.materialStore.store(
          _material(
            eventId: offerId,
            type: CallNegotiationMaterialType.offer,
            generation: generation,
            payload: {
              'description': 'restart-sdp-$generation',
              'fingerprint': _fingerprint,
            },
          ),
        );
        final reduction = reducer.reduce(
          harness.snapshot,
          CallEvent(
            type: CallEventType.remoteOffer,
            eventId: offerId,
            occurredAt: _now,
            callId: _callId,
          ),
        );
        expect(reduction.decision, CallEventDecision.applied);
        expect(reduction.snapshot.state, CallState.reconnecting);
        harness.snapshot = reduction.snapshot;
        final effect = reduction.effects.singleWhere(
          (e) => e.type == CallEffectType.deliverOffer,
        );
        expect(
          await harness.executor.execute(effect, harness.snapshot),
          isNull,
        );
        expect(harness.engine.restartCalls, generation);
        expect(harness.signaling.descriptions.last.$3, generation);

        harness.engine.connectionSnapshot = _connectionSnapshot(
          state: CallConnectionState.connected,
          ready: true,
        );
        harness.engine.emitEvent(_engineEvent(CallConnectionState.connected));
        await _flushAsync();
        final recovered = harness.dispatched.last;
        expect(recovered.type, CallEventType.mediaRecovered);
        harness.snapshot = reducer.reduce(harness.snapshot, recovered).snapshot;
        expect(harness.snapshot.state, CallState.connected);

        final restartId = 'late-announcement-$generation';
        harness.materialStore.store(
          _material(
            eventId: restartId,
            type: CallNegotiationMaterialType.iceRestart,
            generation: generation,
            payload: {},
          ),
        );
        final late = reducer.reduce(
          harness.snapshot,
          CallEvent(
            type: CallEventType.remoteIceRestart,
            eventId: restartId,
            occurredAt: _now,
            callId: _callId,
          ),
        );
        harness.snapshot = late.snapshot;
        final followUp = await harness.executor.execute(
          const CallEffect(CallEffectType.restartIce),
          harness.snapshot,
        );
        expect(followUp?.type, CallEventType.mediaRecovered);
        harness.snapshot = reducer.reduce(harness.snapshot, followUp!).snapshot;
        expect(harness.snapshot.state, CallState.connected);
        expect(harness.engine.restartCalls, generation);
      }
    },
  );

  test('state gates prevent early SDP, ICE, restart, and media work', () async {
    final harness = _Harness(snapshot: _snapshot(CallState.ringing));
    addTearDown(harness.executor.close);
    final material = _material(
      eventId: 'accepted-event',
      type: CallNegotiationMaterialType.offer,
      payload: const <String, Object?>{
        'description': 'secret-early-offer',
        'fingerprint': _fingerprint,
      },
    );
    expect(
      harness.materialStore.store(material),
      CallNegotiationMaterialStoreDecision.stored,
    );

    for (final type in <CallEffectType>[
      CallEffectType.startNegotiation,
      CallEffectType.deliverOffer,
      CallEffectType.deliverAnswer,
      CallEffectType.queueIceCandidate,
      CallEffectType.restartIce,
    ]) {
      expect(
        await harness.executor.execute(CallEffect(type), harness.snapshot),
        isNull,
      );
    }

    expect(harness.preparer.calls, 0);
    expect(harness.engine.descriptionWorkCount, 0);
    expect(harness.engine.addCandidateCalls, 0);
    expect(harness.engine.restartCalls, 0);
    expect(harness.materialStore.entryCountFor(_callId), 1);
  });

  test(
    'start prepares accepted media then sets and sends one authenticated offer',
    () async {
      final calls = <String>[];
      final harness = _Harness(
        snapshot: _snapshot(CallState.accepted),
        calls: calls,
      );
      addTearDown(harness.executor.close);

      final followUp = await harness.executor.execute(
        const CallEffect(CallEffectType.startNegotiation),
        harness.snapshot,
      );

      expect(followUp?.type, CallEventType.negotiationReady);
      expect(followUp?.callId, _callId);
      expect(calls.take(4), <String>[
        'media.prepare',
        'engine.offer',
        'engine.local',
        'signal.sdp',
      ]);
      expect(harness.signaling.descriptions.single.$1, _callId);
      expect(
        harness.signaling.descriptions.single.$2,
        same(harness.engine.offer),
      );
      expect(
        harness.signaling.descriptions.single.$2.fingerprint,
        _fingerprint,
      );
      expect(harness.signaling.descriptions.single.$3, 0);

      harness.snapshot = _snapshot(CallState.negotiating);
      expect(
        await harness.executor.execute(
          const CallEffect(CallEffectType.startNegotiation),
          harness.snapshot,
        ),
        isNull,
      );
      expect(harness.preparer.calls, 1);
      expect(harness.engine.createOfferCalls, 1);
      expect(harness.signaling.descriptions, hasLength(1));
    },
  );

  test('accepted callee media preparation performs no SDP work', () async {
    final harness = _Harness(snapshot: _snapshot(CallState.accepted));
    addTearDown(harness.executor.close);

    expect(
      await harness.executor.execute(
        const CallEffect(CallEffectType.prepareAcceptedMedia),
        harness.snapshot,
      ),
      isNull,
    );

    expect(harness.preparer.calls, 1);
    expect(harness.engine.descriptionWorkCount, 0);
    expect(harness.signaling.descriptions, isEmpty);
  });

  test(
    'offer, answer, and ICE take authenticated material once and preserve bytes',
    () async {
      final calls = <String>[];
      final harness = _Harness(
        snapshot: _snapshot(
          CallState.negotiating,
          recentEventIds: const <String>['offer-event'],
        ),
        calls: calls,
      );
      addTearDown(harness.executor.close);
      expect(
        harness.materialStore.store(
          _material(
            eventId: 'offer-event',
            type: CallNegotiationMaterialType.offer,
            payload: const <String, Object?>{
              'description': 'secret-remote-offer',
              'fingerprint': _fingerprint,
            },
          ),
        ),
        CallNegotiationMaterialStoreDecision.stored,
      );

      expect(
        await harness.executor.execute(
          const CallEffect(CallEffectType.deliverOffer),
          harness.snapshot,
        ),
        isNull,
      );
      expect(calls.take(5), <String>[
        'media.prepare',
        'engine.remote',
        'engine.answer',
        'engine.local',
        'signal.sdp',
      ]);
      expect(
        harness.engine.remoteDescriptions.single.value,
        'secret-remote-offer',
      );
      expect(
        harness.engine.remoteDescriptions.single.fingerprint,
        _fingerprint,
      );
      expect(
        harness.signaling.descriptions.single.$2,
        same(harness.engine.answer),
      );
      expect(
        await harness.executor.execute(
          const CallEffect(CallEffectType.deliverOffer),
          harness.snapshot,
        ),
        isNull,
      );
      expect(harness.engine.createAnswerCalls, 1);

      expect(
        harness.materialStore.store(
          _material(
            eventId: 'answer-event',
            type: CallNegotiationMaterialType.answer,
            payload: const <String, Object?>{
              'description': 'secret-remote-answer',
              'fingerprint': _fingerprint,
            },
          ),
        ),
        CallNegotiationMaterialStoreDecision.stored,
      );
      harness.snapshot = _snapshot(
        CallState.negotiating,
        recentEventIds: const <String>['offer-event', 'answer-event'],
      );
      expect(
        await harness.executor.execute(
          const CallEffect(CallEffectType.deliverAnswer),
          harness.snapshot,
        ),
        isNull,
      );
      expect(
        harness.engine.remoteDescriptions.last.value,
        'secret-remote-answer',
      );

      expect(
        harness.materialStore.store(
          _material(
            eventId: 'ice-event',
            type: CallNegotiationMaterialType.ice,
            generation: 0,
            payload: const <String, Object?>{
              'candidate': 'candidate:secret exact payload typ relay',
              'media_id': 'audio',
              'media_line_index': 7,
            },
          ),
        ),
        CallNegotiationMaterialStoreDecision.stored,
      );
      harness.snapshot = _snapshot(
        CallState.negotiating,
        recentEventIds: const <String>['answer-event', 'ice-event'],
      );
      expect(
        await harness.executor.execute(
          const CallEffect(CallEffectType.queueIceCandidate),
          harness.snapshot,
        ),
        isNull,
      );
      final candidate = harness.engine.addedCandidates.single.single;
      expect(candidate.value, 'candidate:secret exact payload typ relay');
      expect(candidate.mediaId, 'audio');
      expect(candidate.mediaLineIndex, 7);
      expect(candidate.iceGeneration, 0);
      expect(
        await harness.executor.execute(
          const CallEffect(CallEffectType.queueIceCandidate),
          harness.snapshot,
        ),
        isNull,
      );
      expect(harness.engine.addCandidateCalls, 1);
      expect(harness.materialStore.entryCountFor(_callId), 0);
    },
  );

  test(
    'remote restart is attempted once without echoing restart signaling',
    () async {
      final expired = CallIceServer(
        urls: <String>['turns:expired.invalid'],
        username: 'expired-user',
        credential: 'expired-secret',
        expiresAt: _now.subtract(const Duration(seconds: 1)),
      );
      final current = CallIceServer(
        urls: <String>['turns:relay.invalid'],
        username: 'current-user',
        credential: 'current-secret',
        expiresAt: _now.add(const Duration(minutes: 5)),
      );
      // The callee mirrors the caller's announced generation and sends
      // nothing; the caller's fresh offer follows on its own.
      final harness = _Harness(
        snapshot: _snapshot(
          CallState.reconnecting,
          direction: CallDirection.incoming,
          recentEventIds: const <String>['restart-event'],
        ),
        stagedServers: <CallIceServer>[expired, current],
      );
      addTearDown(harness.executor.close);
      harness.engine.restartGeneration = 1;
      expect(
        harness.materialStore.store(
          _material(
            eventId: 'restart-event',
            type: CallNegotiationMaterialType.iceRestart,
            generation: 1,
            payload: const <String, Object?>{},
          ),
        ),
        CallNegotiationMaterialStoreDecision.stored,
      );

      expect(
        await harness.executor.execute(
          const CallEffect(CallEffectType.restartIce),
          harness.snapshot,
        ),
        isNull,
      );
      expect(harness.engine.restartCalls, 1);
      expect(harness.engine.lastRestartServers, <CallIceServer>[current]);
      expect(harness.signaling.restartGenerations, isEmpty);
      expect(harness.signaling.descriptions, isEmpty);
      expect(
        await harness.executor.execute(
          const CallEffect(CallEffectType.restartIce),
          harness.snapshot,
        ),
        isNull,
      );
      expect(harness.engine.restartCalls, 1);
    },
  );

  test(
    'callee media loss requests a caller restart without touching the engine',
    () async {
      final harness = _Harness(
        snapshot: _snapshot(
          CallState.reconnecting,
          direction: CallDirection.incoming,
        ),
      );
      addTearDown(harness.executor.close);

      expect(
        await harness.executor.execute(
          const CallEffect(CallEffectType.requestIceRestart),
          harness.snapshot,
        ),
        isNull,
      );
      expect(harness.engine.restartCalls, 0);
      expect(harness.signaling.restartGenerations, <int>[0]);
      expect(harness.signaling.descriptions, isEmpty);
    },
  );

  test(
    "caller answers the callee's restart request with a new generation",
    () async {
      final harness = _Harness(
        snapshot: _snapshot(
          CallState.reconnecting,
          recentEventIds: const <String>['restart-request'],
        ),
      );
      addTearDown(harness.executor.close);
      harness.engine.restartGeneration = 1;
      expect(
        harness.materialStore.store(
          _material(
            eventId: 'restart-request',
            type: CallNegotiationMaterialType.iceRestart,
            generation: 0,
            payload: const <String, Object?>{},
          ),
        ),
        CallNegotiationMaterialStoreDecision.stored,
      );

      expect(
        await harness.executor.execute(
          const CallEffect(CallEffectType.restartIce),
          harness.snapshot,
        ),
        isNull,
      );
      expect(harness.engine.restartCalls, 1);
      expect(harness.signaling.restartGenerations, <int>[1]);
      expect(harness.signaling.descriptions, hasLength(1));

      // A second request in the same episode does not restart again.
      expect(
        await harness.executor.execute(
          const CallEffect(CallEffectType.restartIce),
          harness.snapshot,
        ),
        isNull,
      );
      expect(harness.engine.restartCalls, 1);
    },
  );

  test(
    'local restart signals generation then sends a fresh authenticated offer',
    () async {
      final current = CallIceServer(
        urls: <String>['turns:relay.invalid'],
        username: 'current-user',
        credential: 'current-secret',
        expiresAt: _now.add(const Duration(minutes: 5)),
      );
      final harness = _Harness(
        snapshot: _snapshot(CallState.reconnecting),
        stagedServers: <CallIceServer>[current],
      );
      addTearDown(harness.executor.close);
      harness.engine.restartGeneration = 4;

      final result = await harness.executor.execute(
        const CallEffect(CallEffectType.restartIce),
        harness.snapshot,
      );

      expect(result, isNull);
      expect(harness.engine.restartCalls, 1);
      expect(harness.signaling.restartGenerations, <int>[4]);
      expect(harness.engine.createOfferCalls, 1);
      expect(harness.engine.localDescriptions, <CallSessionDescription>[
        harness.engine.offer,
      ]);
      expect(harness.signaling.descriptions, hasLength(1));
      expect(
        harness.signaling.descriptions.single.$2.type,
        CallSessionDescriptionType.offer,
      );
      expect(harness.signaling.descriptions.single.$3, 4);
      expect(
        harness.calls,
        containsAllInOrder(<String>[
          'engine.restart',
          'signal.restart',
          'engine.offer',
          'engine.local',
          'signal.sdp',
        ]),
      );
    },
  );

  test(
    'expected permission and media failures become negotiationFailed',
    () async {
      for (final code in <CallNegotiationPortErrorCode>[
        CallNegotiationPortErrorCode.permissionDenied,
        CallNegotiationPortErrorCode.mediaUnavailable,
      ]) {
        final harness = _Harness(snapshot: _snapshot(CallState.accepted));
        harness.preparer.error = CallNegotiationPortException(code);
        final result = await harness.executor.execute(
          const CallEffect(CallEffectType.startNegotiation),
          harness.snapshot,
        );
        expect(
          result?.type,
          CallEventType.negotiationFailed,
          reason: code.name,
        );
        final expectedReason =
            code == CallNegotiationPortErrorCode.permissionDenied
            ? CallEndReason.permissionDenied
            : null;
        expect(result?.endReason, expectedReason, reason: code.name);
        expect(
          const CallReducer()
              .reduce(harness.snapshot, result!)
              .snapshot
              .endReason,
          expectedReason ?? CallEndReason.mediaFailed,
          reason: code.name,
        );
        expect(harness.engine.createOfferCalls, 0);
        await harness.executor.close();
      }
    },
  );

  test(
    'fingerprint and candidate engine errors become negotiationFailed',
    () async {
      final fingerprintHarness = _Harness(
        snapshot: _snapshot(
          CallState.negotiating,
          recentEventIds: const <String>['bad-offer'],
        ),
      );
      addTearDown(fingerprintHarness.executor.close);
      fingerprintHarness.engine.remoteError =
          CallEngineErrorCode.fingerprintMismatch;
      fingerprintHarness.materialStore.store(
        _material(
          eventId: 'bad-offer',
          type: CallNegotiationMaterialType.offer,
          payload: const <String, Object?>{
            'description': 'secret-bad-offer',
            'fingerprint': 'secret-wrong-fingerprint',
          },
        ),
      );
      expect(
        (await fingerprintHarness.executor.execute(
          const CallEffect(CallEffectType.deliverOffer),
          fingerprintHarness.snapshot,
        ))?.type,
        CallEventType.negotiationFailed,
      );

      final candidateHarness = _Harness(
        snapshot: _snapshot(
          CallState.negotiating,
          recentEventIds: const <String>['candidate-offer'],
        ),
      );
      addTearDown(candidateHarness.executor.close);
      candidateHarness.materialStore.store(
        _material(
          eventId: 'candidate-offer',
          type: CallNegotiationMaterialType.offer,
          payload: const <String, Object?>{
            'description': 'secret-candidate-offer',
            'fingerprint': _fingerprint,
          },
        ),
      );
      await candidateHarness.executor.execute(
        const CallEffect(CallEffectType.deliverOffer),
        candidateHarness.snapshot,
      );
      candidateHarness.engine.candidateError =
          CallEngineErrorCode.candidateOverflow;
      candidateHarness.materialStore.store(
        _material(
          eventId: 'bad-candidate',
          type: CallNegotiationMaterialType.ice,
          payload: const <String, Object?>{
            'candidate': 'secret-overflow-candidate',
          },
        ),
      );
      candidateHarness.snapshot = _snapshot(
        CallState.negotiating,
        recentEventIds: const <String>['candidate-offer', 'bad-candidate'],
      );
      expect(
        (await candidateHarness.executor.execute(
          const CallEffect(CallEffectType.queueIceCandidate),
          candidateHarness.snapshot,
        ))?.type,
        CallEventType.negotiationFailed,
      );
      expect(candidateHarness.materialStore.entryCountFor(_callId), 0);
    },
  );

  test('SDP generation mismatch fails before media or peer mutation', () async {
    for (final type in <CallNegotiationMaterialType>[
      CallNegotiationMaterialType.offer,
      CallNegotiationMaterialType.answer,
    ]) {
      final eventId = 'mismatched-${type.name}';
      final harness = _Harness(
        snapshot: _snapshot(
          CallState.negotiating,
          recentEventIds: <String>[eventId],
        ),
      );
      addTearDown(harness.executor.close);
      harness.materialStore.store(
        _material(
          eventId: eventId,
          type: type,
          generation: 1,
          payload: <String, Object?>{
            'description': 'secret-${type.name}',
            'fingerprint': _fingerprint,
          },
        ),
      );

      final followUp = await harness.executor.execute(
        CallEffect(
          type == CallNegotiationMaterialType.offer
              ? CallEffectType.deliverOffer
              : CallEffectType.deliverAnswer,
        ),
        harness.snapshot,
      );

      expect(followUp?.type, CallEventType.negotiationFailed);
      expect(harness.preparer.calls, 0);
      expect(harness.engine.remoteDescriptions, isEmpty);
    }
  });

  test(
    'candidate egress preserves generation, is bounded, and fails closed',
    () async {
      final harness = _Harness(
        snapshot: _snapshot(CallState.accepted),
        maxPendingLocalCandidates: 2,
        maxLocalCandidateBatchSize: 1,
      );
      addTearDown(harness.executor.close);
      await harness.executor.execute(
        const CallEffect(CallEffectType.startNegotiation),
        harness.snapshot,
      );
      harness.snapshot = _snapshot(CallState.negotiating);
      harness.signaling.candidateGate = Completer<void>();

      harness.engine.emitCandidate(
        const CallIceCandidate(
          value: 'candidate:host-unfiltered',
          mediaId: 'audio',
          mediaLineIndex: 0,
          iceGeneration: 0,
        ),
      );
      await _flushAsync();
      harness.engine.emitCandidate(
        const CallIceCandidate(
          value: 'candidate:queued',
          mediaId: 'audio',
          mediaLineIndex: 0,
          iceGeneration: 0,
        ),
      );
      harness.engine.emitCandidate(
        const CallIceCandidate(
          value: 'candidate:overflow',
          mediaId: 'audio',
          mediaLineIndex: 0,
          iceGeneration: 0,
        ),
      );
      await _flushAsync();

      expect(harness.signaling.candidateBatches, hasLength(1));
      expect(harness.signaling.candidateBatches.single.$2, hasLength(1));
      final sent = harness.signaling.candidateBatches.single.$2.single;
      expect(sent.value, 'candidate:host-unfiltered');
      expect(sent.iceGeneration, 0);
      expect(
        harness.dispatched.map((event) => event.type),
        contains(CallEventType.negotiationFailed),
      );

      harness.signaling.candidateGate!.complete();
      await _flushAsync();
      harness.engine.emitCandidate(
        const CallIceCandidate(
          value: 'candidate:after-failure',
          mediaId: null,
          mediaLineIndex: null,
          iceGeneration: 0,
        ),
      );
      await _flushAsync();
      expect(harness.signaling.candidateBatches, hasLength(1));
    },
  );

  test('local ICE waits for authenticated SDP egress completion', () async {
    final harness = _Harness(snapshot: _snapshot(CallState.accepted));
    addTearDown(harness.executor.close);
    harness.signaling.descriptionGate = Completer<void>();
    harness.engine.candidateOnSetLocal = const CallIceCandidate(
      value: 'candidate:local-after-sdp',
      mediaId: 'audio',
      mediaLineIndex: 0,
      iceGeneration: 0,
    );

    final negotiation = harness.executor.execute(
      const CallEffect(CallEffectType.startNegotiation),
      harness.snapshot,
    );
    await _flushAsync();

    expect(harness.signaling.descriptions, hasLength(1));
    expect(harness.signaling.candidateBatches, isEmpty);

    harness.signaling.descriptionGate!.complete();
    await negotiation;
    harness.snapshot = _snapshot(CallState.negotiating);
    await _flushAsync();
    expect(harness.signaling.candidateBatches, hasLength(1));
    expect(
      harness.signaling.candidateBatches.single.$2.single.value,
      'candidate:local-after-sdp',
    );
  });

  test(
    'remote ICE received before SDP is bounded and applied after SDP',
    () async {
      final harness = _Harness(
        snapshot: _snapshot(
          CallState.accepted,
          recentEventIds: const <String>['early-ice'],
        ),
      );
      addTearDown(harness.executor.close);
      harness.materialStore.store(
        _material(
          eventId: 'early-ice',
          type: CallNegotiationMaterialType.ice,
          payload: const <String, Object?>{
            'candidate': 'candidate:remote-before-sdp',
            'media_id': 'audio',
            'media_line_index': 0,
          },
        ),
      );

      expect(
        await harness.executor.execute(
          const CallEffect(CallEffectType.queueIceCandidate),
          harness.snapshot,
        ),
        isNull,
      );
      expect(harness.engine.addedCandidates, isEmpty);

      harness.materialStore.store(
        _material(
          eventId: 'offer-after-ice',
          type: CallNegotiationMaterialType.offer,
          payload: const <String, Object?>{
            'description': 'secret-remote-offer',
            'fingerprint': _fingerprint,
          },
        ),
      );
      harness.snapshot = _snapshot(
        CallState.negotiating,
        recentEventIds: const <String>['early-ice', 'offer-after-ice'],
      );
      expect(
        await harness.executor.execute(
          const CallEffect(CallEffectType.deliverOffer),
          harness.snapshot,
        ),
        isNull,
      );
      expect(harness.engine.remoteDescriptions, hasLength(1));
      expect(harness.engine.addedCandidates, hasLength(1));
      expect(
        harness.engine.addedCandidates.single.single.value,
        'candidate:remote-before-sdp',
      );
    },
  );

  test('remote ICE before SDP fails closed at its fixed queue bound', () async {
    final harness = _Harness(
      snapshot: _snapshot(
        CallState.accepted,
        recentEventIds: const <String>['early-ice-1'],
      ),
      maxPendingRemoteCandidates: 1,
    );
    addTearDown(harness.executor.close);
    for (final eventId in <String>['early-ice-1', 'early-ice-2']) {
      harness.materialStore.store(
        _material(
          eventId: eventId,
          type: CallNegotiationMaterialType.ice,
          payload: <String, Object?>{
            'candidate': 'candidate:$eventId',
            'media_id': 'audio',
            'media_line_index': 0,
          },
        ),
      );
    }

    expect(
      await harness.executor.execute(
        const CallEffect(CallEffectType.queueIceCandidate),
        harness.snapshot,
      ),
      isNull,
    );
    harness.snapshot = _snapshot(
      CallState.accepted,
      recentEventIds: const <String>['early-ice-1', 'early-ice-2'],
    );
    expect(
      (await harness.executor.execute(
        const CallEffect(CallEffectType.queueIceCandidate),
        harness.snapshot,
      ))?.type,
      CallEventType.negotiationFailed,
    );
    expect(harness.engine.addedCandidates, isEmpty);
  });

  test(
    'one connected event resamples late readiness exactly once per phase',
    () async {
      for (final phase in <(CallState, CallEventType)>[
        (CallState.negotiating, CallEventType.mediaConnected),
        (CallState.reconnecting, CallEventType.mediaRecovered),
      ]) {
        final timers = _ReadinessTimerScheduler();
        final harness = _Harness(
          snapshot: _snapshot(phase.$1),
          mediaReadinessTimerScheduler: timers,
          mediaReadinessPollInterval: const Duration(milliseconds: 7),
          maxMediaReadinessSamples: 3,
        );
        try {
          harness.engine.connectionSnapshot = _connectionSnapshot(
            state: CallConnectionState.connected,
            ready: false,
            localAudioEnabled: false,
          );

          harness.engine.emitEvent(_engineEvent(CallConnectionState.connected));
          harness.engine.emitEvent(_engineEvent(CallConnectionState.connected));
          await _flushAsync();

          expect(harness.engine.snapshotCalls, 1);
          expect(timers.active, hasLength(1));
          expect(timers.scheduled, hasLength(1));

          harness.engine.connectionSnapshot = _connectionSnapshot(
            state: CallConnectionState.connected,
            ready: true,
            localAudioEnabled: false,
          );
          await timers.fireNext();
          await _flushAsync();

          expect(harness.dispatched.map((event) => event.type), <CallEventType>[
            phase.$2,
          ]);
          expect(harness.engine.snapshotCalls, 2);
          expect(timers.active, isEmpty);

          harness.engine.emitEvent(_engineEvent(CallConnectionState.connected));
          harness.engine.emitEvent(_engineEvent(CallConnectionState.connected));
          await _flushAsync();

          expect(harness.dispatched.map((event) => event.type), <CallEventType>[
            phase.$2,
          ]);
          expect(harness.engine.snapshotCalls, 2);
          expect(timers.scheduled, hasLength(1));
        } finally {
          await harness.executor.close();
        }
      }
    },
  );

  test(
    'default readiness observes strict media past the former cap exactly once',
    () async {
      const formerDefaultSampleCap = 100;
      final timers = _ReadinessTimerScheduler();
      final harness = _Harness(
        snapshot: _snapshot(CallState.negotiating),
        mediaReadinessTimerScheduler: timers,
      );
      addTearDown(harness.executor.close);
      harness.engine.connectionSnapshot = _connectionSnapshot(
        state: CallConnectionState.connected,
        ready: false,
      );

      harness.engine.emitEvent(_engineEvent(CallConnectionState.connected));
      await _flushAsync();
      for (var sample = 1; sample < formerDefaultSampleCap; sample++) {
        await timers.fireNext();
      }
      await _flushAsync();

      expect(harness.engine.snapshotCalls, formerDefaultSampleCap);
      expect(
        timers.active,
        hasLength(1),
        reason: 'the canonical negotiation deadline still owns termination',
      );
      final formerWindow = timers.scheduled.fold(
        Duration.zero,
        (elapsed, timer) => elapsed + timer.delay,
      );
      expect(formerWindow, const Duration(seconds: 10));
      expect(
        formerWindow,
        lessThan(const CallReducerPolicy().negotiationTimeout),
      );

      harness.engine.connectionSnapshot = _connectionSnapshot(
        state: CallConnectionState.connected,
        ready: true,
      );
      await timers.fireNext();
      await _flushAsync();

      expect(harness.engine.snapshotCalls, formerDefaultSampleCap + 1);
      expect(harness.dispatched.map((event) => event.type), <CallEventType>[
        CallEventType.mediaConnected,
      ]);
      expect(timers.active, isEmpty);

      harness.engine.emitEvent(_engineEvent(CallConnectionState.connected));
      harness.engine.emitEvent(_engineEvent(CallConnectionState.connected));
      await _flushAsync();

      expect(harness.engine.snapshotCalls, formerDefaultSampleCap + 1);
      expect(harness.dispatched.map((event) => event.type), <CallEventType>[
        CallEventType.mediaConnected,
      ]);
    },
  );

  test('disconnect cancels a pending readiness sample', () async {
    final timers = _ReadinessTimerScheduler();
    final harness = _Harness(
      snapshot: _snapshot(CallState.negotiating),
      mediaReadinessTimerScheduler: timers,
      maxMediaReadinessSamples: 3,
    );
    addTearDown(harness.executor.close);
    harness.engine.connectionSnapshot = _connectionSnapshot(
      state: CallConnectionState.connected,
      ready: false,
    );
    harness.engine.emitEvent(_engineEvent(CallConnectionState.connected));
    await _flushAsync();
    final staleTimer = timers.active.single;

    harness.engine.emitEvent(_engineEvent(CallConnectionState.disconnected));
    await _flushAsync();
    expect(staleTimer.canceled, isTrue);

    harness.engine.connectionSnapshot = _connectionSnapshot(
      state: CallConnectionState.connected,
      ready: true,
    );
    await staleTimer.invokeDespiteCancellation();
    await _flushAsync();

    expect(harness.engine.snapshotCalls, 1);
    expect(harness.dispatched, isEmpty);
    expect(timers.active, isEmpty);
  });

  test('disconnect supersedes a queued duplicate connected event', () async {
    final timers = _ReadinessTimerScheduler();
    final harness = _Harness(
      snapshot: _snapshot(CallState.negotiating),
      mediaReadinessTimerScheduler: timers,
      maxMediaReadinessSamples: 3,
    );
    addTearDown(harness.executor.close);
    harness.engine.connectionSnapshot = _connectionSnapshot(
      state: CallConnectionState.connected,
      ready: false,
    );

    harness.engine.emitEvent(_engineEvent(CallConnectionState.connected));
    harness.engine.emitEvent(_engineEvent(CallConnectionState.connected));
    harness.engine.emitEvent(_engineEvent(CallConnectionState.disconnected));
    await _flushAsync();

    expect(harness.engine.snapshotCalls, 1);
    expect(harness.dispatched, isEmpty);
    expect(timers.active, isEmpty);
  });

  test('failure cancels readiness and cannot later connect media', () async {
    final timers = _ReadinessTimerScheduler();
    final harness = _Harness(
      snapshot: _snapshot(CallState.negotiating),
      mediaReadinessTimerScheduler: timers,
      maxMediaReadinessSamples: 3,
    );
    addTearDown(harness.executor.close);
    harness.engine.connectionSnapshot = _connectionSnapshot(
      state: CallConnectionState.connected,
      ready: false,
    );
    harness.engine.emitEvent(_engineEvent(CallConnectionState.connected));
    await _flushAsync();
    final staleTimer = timers.active.single;

    harness.engine.emitEvent(
      _engineEvent(
        CallConnectionState.failed,
        failureReason: CallFailureReason.transportUnavailable,
      ),
    );
    await _flushAsync();
    expect(staleTimer.canceled, isTrue);

    harness.engine.connectionSnapshot = _connectionSnapshot(
      state: CallConnectionState.connected,
      ready: true,
    );
    await staleTimer.invokeDespiteCancellation();
    harness.engine.emitEvent(_engineEvent(CallConnectionState.connected));
    await _flushAsync();

    expect(harness.engine.snapshotCalls, 1);
    expect(harness.dispatched.map((event) => event.type), <CallEventType>[
      CallEventType.negotiationFailed,
    ]);
    expect(timers.active, isEmpty);
  });

  test(
    'terminal and call changes stop readiness before another sample',
    () async {
      for (final replacement in <CallSessionSnapshot>[
        _snapshot(CallState.ended),
        _snapshot(CallState.negotiating, callId: _otherCallId),
      ]) {
        final timers = _ReadinessTimerScheduler();
        final harness = _Harness(
          snapshot: _snapshot(CallState.negotiating),
          mediaReadinessTimerScheduler: timers,
          maxMediaReadinessSamples: 3,
        );
        try {
          harness.engine.connectionSnapshot = _connectionSnapshot(
            state: CallConnectionState.connected,
            ready: false,
          );
          harness.engine.emitEvent(_engineEvent(CallConnectionState.connected));
          await _flushAsync();

          final timer = timers.active.single;
          harness.snapshot = replacement;
          harness.engine.connectionSnapshot = _connectionSnapshot(
            state: CallConnectionState.connected,
            ready: true,
          );
          await timers.fireNext();
          await _flushAsync();

          expect(timer.canceled, isTrue);
          expect(harness.engine.snapshotCalls, 1);
          expect(harness.dispatched, isEmpty);
          expect(timers.active, isEmpty);
        } finally {
          await harness.executor.close();
        }
      }
    },
  );

  test('close cancels readiness and invalidates a stale callback', () async {
    final timers = _ReadinessTimerScheduler();
    final harness = _Harness(
      snapshot: _snapshot(CallState.negotiating),
      mediaReadinessTimerScheduler: timers,
      maxMediaReadinessSamples: 3,
    );
    harness.engine.connectionSnapshot = _connectionSnapshot(
      state: CallConnectionState.connected,
      ready: false,
    );
    harness.engine.emitEvent(_engineEvent(CallConnectionState.connected));
    await _flushAsync();
    final staleTimer = timers.active.single;

    await harness.executor.close();
    expect(staleTimer.canceled, isTrue);
    harness.engine.connectionSnapshot = _connectionSnapshot(
      state: CallConnectionState.connected,
      ready: true,
    );
    await staleTimer.invokeDespiteCancellation();
    await _flushAsync();

    expect(harness.engine.snapshotCalls, 1);
    expect(harness.dispatched, isEmpty);
    expect(timers.active, isEmpty);
    expect(harness.engine.closeCalls, 1);
  });

  test('never-ready sampling is configurable and strictly bounded', () async {
    final timers = _ReadinessTimerScheduler();
    final harness = _Harness(
      snapshot: _snapshot(CallState.negotiating),
      mediaReadinessTimerScheduler: timers,
      mediaReadinessPollInterval: const Duration(milliseconds: 7),
      maxMediaReadinessSamples: 3,
    );
    addTearDown(harness.executor.close);
    harness.engine.connectionSnapshot = _connectionSnapshot(
      state: CallConnectionState.connected,
      ready: false,
    );

    harness.engine.emitEvent(_engineEvent(CallConnectionState.connected));
    await _flushAsync();
    await timers.fireNext();
    await timers.fireNext();
    await _flushAsync();

    expect(harness.engine.snapshotCalls, 3);
    expect(harness.dispatched, isEmpty);
    expect(timers.active, isEmpty);
    expect(
      timers.scheduled.map((candidate) => candidate.delay),
      everyElement(const Duration(milliseconds: 7)),
    );

    harness.engine.emitEvent(_engineEvent(CallConnectionState.connected));
    await _flushAsync();
    expect(harness.engine.snapshotCalls, 3);
    expect(timers.scheduled, hasLength(2));
  });

  test('default readiness delegates its deadline to the coordinator', () async {
    final harness = _Harness(snapshot: _snapshot(CallState.negotiating));
    addTearDown(harness.executor.close);

    expect(harness.executor.mediaReadinessPollInterval, isNot(Duration.zero));
    expect(harness.executor.maxMediaReadinessSamples, isNull);
  });

  test(
    'media loss drives one real ICE restart then one reconnect cleanup',
    () async {
      final calls = <String>[];
      final materialStore = CallNegotiationMaterialStore();
      final engine = _FakeEngine(calls);
      final preparer = _FakePreparer(calls);
      final signaling = _FakeSignaling(calls);
      final timers = _CausalTimerScheduler();
      final history = _CausalHistoryRepository();
      final currentServer = CallIceServer(
        urls: <String>['turns:relay.invalid'],
        username: 'current-user',
        credential: 'current-secret',
        expiresAt: _now.add(const Duration(minutes: 5)),
      );
      var cleanupCalls = 0;
      late final CallCoordinator coordinator;
      final executor = CallNegotiationEffectExecutor(
        engine: engine,
        materialStore: materialStore,
        mediaPreparer: preparer,
        signaling: signaling,
        configuration: _configuration,
        dispatchEvent: (event) async {
          await coordinator.dispatch(event);
        },
        readActiveSnapshot: () => coordinator.activeSession,
        readStagedIceServers: (_) async => <CallIceServer>[currentServer],
        clock: () => _now,
      );
      coordinator = CallCoordinator(
        reducer: const CallReducer(),
        cleanupCoordinator: CallCleanupCoordinator(<CallCleanupStep>[
          CallCleanupStep('media', (_) async => cleanupCalls++),
        ]),
        historyProjector: CallHistoryProjector(history, clock: () => _now),
        effectExecutor: executor,
        clock: () => _now,
        idSource: () => _callId,
        timerScheduler: timers,
      );
      addTearDown(() async {
        await coordinator.dispose();
        await executor.close();
      });

      await coordinator.dispatch(_coordinatorEvent(CallEventType.place));
      await coordinator.dispatch(
        _coordinatorEvent(CallEventType.outgoingInviteReady),
      );
      await coordinator.dispatch(_coordinatorEvent(CallEventType.remoteAccept));
      expect(coordinator.activeSession?.state, CallState.negotiating);

      engine.connectionSnapshot = _connectionSnapshot(
        state: CallConnectionState.connected,
        ready: true,
      );
      engine.emitEvent(_engineEvent(CallConnectionState.connected));
      await _flushAsync();
      expect(coordinator.activeSession?.state, CallState.connected);

      engine.connectionSnapshot = _connectionSnapshot(
        state: CallConnectionState.disconnected,
        ready: false,
      );
      engine.emitEvent(_engineEvent(CallConnectionState.disconnected));
      await _flushAsync();

      expect(coordinator.activeSession?.state, CallState.reconnecting);
      expect(engine.restartCalls, 1);
      expect(signaling.restartGenerations, <int>[engine.restartGeneration]);
      final reconnectTimer = timers.active.single;
      expect(reconnectTimer.delay, const Duration(seconds: 15));

      engine.emitEvent(_engineEvent(CallConnectionState.disconnected));
      await _flushAsync();
      expect(engine.restartCalls, 1);
      expect(timers.active, <_CausalScheduled>[reconnectTimer]);

      await reconnectTimer.callback();
      await reconnectTimer.callback();
      expect(coordinator.activeSession, isNull);
      expect(
        coordinator.lastSnapshot?.endReason,
        CallEndReason.reconnectFailed,
      );
      expect(cleanupCalls, 1);
      expect(history.upsertCalls, 1);
      expect(history.rows, hasLength(1));
    },
  );

  test(
    'close cancels bridges, closes once, purges material, and redacts',
    () async {
      final harness = _Harness(snapshot: _snapshot(CallState.negotiating));
      harness.materialStore.store(
        _material(
          eventId: 'secret-material-id',
          type: CallNegotiationMaterialType.answer,
          payload: const <String, Object?>{
            'description': 'secret-description',
            'fingerprint': _fingerprint,
          },
        ),
      );
      final diagnostics = harness.executor.toString();
      expect(diagnostics, isNot(contains(_callId.value)));
      expect(diagnostics, isNot(contains('secret')));

      await harness.executor.close();
      await harness.executor.close();
      expect(harness.engine.closeCalls, 1);
      expect(harness.materialStore.entryCountFor(_callId), 0);

      harness.engine.emitEvent(_engineEvent(CallConnectionState.failed));
      harness.engine.emitCandidate(
        const CallIceCandidate(
          value: 'candidate:after-close',
          mediaId: null,
          mediaLineIndex: null,
        ),
      );
      await _flushAsync();
      expect(harness.dispatched, isEmpty);
      expect(harness.signaling.candidateBatches, isEmpty);
    },
  );

  test(
    'failed close retries the same engine once without reopening authority',
    () async {
      final harness = _Harness(snapshot: _snapshot(CallState.negotiating));
      harness.materialStore.store(
        _material(
          eventId: 'retry-secret-material-id',
          type: CallNegotiationMaterialType.answer,
          payload: const <String, Object?>{
            'description': 'retry-secret-description',
            'fingerprint': _fingerprint,
          },
        ),
      );
      harness.engine.failClose = true;

      await expectLater(
        harness.executor.close(),
        throwsA(isA<CallEngineException>()),
      );

      expect(harness.engine.closeCalls, 1);
      expect(harness.materialStore.entryCountFor(_callId), 0);
      expect(harness.executor.toDiagnosticMap()['closed'], isTrue);
      expect(
        await harness.executor.execute(
          const CallEffect(CallEffectType.startNegotiation),
          harness.snapshot,
        ),
        isNull,
      );

      harness.engine.failClose = false;
      final retryGate = Completer<void>();
      harness.engine.closeGate = retryGate;
      final retryA = harness.executor.close();
      final retryB = harness.executor.close();
      final retryResult = Future.wait(<Future<void>>[
        retryA,
        retryB,
      ]).then<Object?>((_) => null, onError: (Object error, _) => error);

      expect(identical(retryA, retryB), isTrue);
      await _flushAsync();
      final callsWhileRetryPending = harness.engine.closeCalls;
      retryGate.complete();
      final retryError = await retryResult;

      expect(callsWhileRetryPending, 2);
      expect(retryError, isNull);
      await harness.executor.close();
      expect(harness.engine.closeCalls, 2);
      expect(harness.materialStore.entryCountFor(_callId), 0);

      harness.engine.emitEvent(_engineEvent(CallConnectionState.failed));
      harness.engine.emitCandidate(
        const CallIceCandidate(
          value: 'candidate:after-failed-close-retry',
          mediaId: null,
          mediaLineIndex: null,
        ),
      );
      await _flushAsync();
      expect(harness.dispatched, isEmpty);
      expect(harness.signaling.candidateBatches, isEmpty);
    },
  );
}

CallConnectionSnapshot _connectionSnapshot({
  required CallConnectionState state,
  required bool ready,
  bool localAudioEnabled = true,
}) => CallConnectionSnapshot(
  state: state,
  transportPolicy: CallTransportPolicy.relayOnly,
  transport: CallTransportClass.relay,
  quality: CallQualityBand.good,
  localAudioCaptureTrackCount: 1,
  localVideoCaptureTrackCount: 0,
  audioReceiveTransceiverCount: 1,
  videoTransceiverCount: 0,
  selectedPairSucceeded: ready,
  selectedPairNominated: ready,
  dtlsReady: ready,
  audioSessionActive: ready,
  localAudioSenderAttached: ready,
  localAudioTrackLive: ready,
  remoteAudioReceiverAttached: ready,
  remoteAudioTrackLive: ready,
  localAudioEnabled: localAudioEnabled,
);

CallEngineEvent _engineEvent(
  CallConnectionState state, {
  CallFailureReason failureReason = CallFailureReason.none,
}) => CallEngineEvent(
  type: CallEngineEventType.state,
  connectionState: state,
  transport: CallTransportClass.relay,
  quality: CallQualityBand.good,
  failureReason: failureReason,
);

CallEvent _coordinatorEvent(CallEventType type) => CallEvent(
  type: type,
  eventId: 'causal-${type.name}',
  occurredAt: _now,
  callId: _callId,
  contactPeerId: 'contact-a',
  localAccountPeerId: 'local-account',
  localDeviceId: 'local-device',
  remoteAccountPeerId: 'contact-a',
  remoteDeviceId: 'contact-device',
  admission: IncomingCallAdmission.accepted,
);

final class _CausalHistoryRepository implements CallHistoryRepository {
  final Map<CallId, CallHistoryEntry> rows = <CallId, CallHistoryEntry>{};
  int upsertCalls = 0;

  @override
  Future<CallHistoryEntry?> getByCallId(CallId callId) async => rows[callId];

  @override
  Future<List<CallHistoryEntry>> listForContact(
    String contactAccountPeerId,
  ) async => rows.values
      .where((entry) => entry.contactAccountPeerId == contactAccountPeerId)
      .toList();

  @override
  Future<void> upsertTerminal(CallHistoryEntry entry) async {
    upsertCalls++;
    rows.putIfAbsent(entry.callId, () => entry);
  }
}

final class _CausalScheduled {
  _CausalScheduled(this.delay, this.callback);

  final Duration delay;
  final Future<void> Function() callback;
  bool canceled = false;
}

final class _CausalTimerHandle implements CallTimerHandle {
  _CausalTimerHandle(this.scheduled);

  final _CausalScheduled scheduled;

  @override
  bool get isActive => !scheduled.canceled;

  @override
  void cancel() => scheduled.canceled = true;
}

final class _CausalTimerScheduler implements CallTimerScheduler {
  final List<_CausalScheduled> scheduled = <_CausalScheduled>[];

  Iterable<_CausalScheduled> get active =>
      scheduled.where((candidate) => !candidate.canceled);

  @override
  CallTimerHandle schedule(Duration delay, Future<void> Function() callback) {
    final value = _CausalScheduled(delay, callback);
    scheduled.add(value);
    return _CausalTimerHandle(value);
  }
}

final class _ReadinessScheduled {
  _ReadinessScheduled(this.delay, this.callback);

  final Duration delay;
  final Future<void> Function() callback;
  bool canceled = false;
  bool fired = false;

  Future<void> invokeDespiteCancellation() async {
    fired = true;
    await callback();
  }
}

final class _ReadinessTimerHandle implements CallTimerHandle {
  _ReadinessTimerHandle(this.scheduled);

  final _ReadinessScheduled scheduled;

  @override
  bool get isActive => !scheduled.canceled && !scheduled.fired;

  @override
  void cancel() => scheduled.canceled = true;
}

final class _ReadinessTimerScheduler implements CallTimerScheduler {
  final List<_ReadinessScheduled> scheduled = <_ReadinessScheduled>[];

  List<_ReadinessScheduled> get active => scheduled
      .where((candidate) => !candidate.canceled && !candidate.fired)
      .toList(growable: false);

  Future<void> fireNext() async {
    final next = active.first;
    next.fired = true;
    await next.callback();
  }

  @override
  CallTimerHandle schedule(Duration delay, Future<void> Function() callback) {
    final value = _ReadinessScheduled(delay, callback);
    scheduled.add(value);
    return _ReadinessTimerHandle(value);
  }
}

final class _Harness {
  _Harness({
    required this.snapshot,
    List<String>? calls,
    List<CallIceServer>? stagedServers,
    CallStagedIceServerReader? stagedReader,
    int maxPendingLocalCandidates = 8,
    int maxPendingRemoteCandidates = 8,
    int maxLocalCandidateBatchSize = 2,
    CallTimerScheduler? mediaReadinessTimerScheduler,
    Duration mediaReadinessPollInterval = const Duration(milliseconds: 100),
    int? maxMediaReadinessSamples,
  }) : stagedServers =
           stagedServers ??
           <CallIceServer>[
             CallIceServer(
               urls: ['turn:relay.invalid:3478'],
               username: 'fixture',
               credential: 'fixture',
               expiresAt: _now.add(const Duration(minutes: 5)),
             ),
           ],
       calls = calls ?? <String>[],
       materialStore = CallNegotiationMaterialStore() {
    engine = _FakeEngine(this.calls);
    preparer = _FakePreparer(this.calls);
    signaling = _FakeSignaling(this.calls);
    executor = CallNegotiationEffectExecutor(
      engine: engine,
      materialStore: materialStore,
      mediaPreparer: preparer,
      signaling: signaling,
      configuration: _configuration,
      dispatchEvent: (event) async {
        dispatched.add(event);
      },
      readActiveSnapshot: () => snapshot,
      readStagedIceServers: stagedReader ?? (_) async => this.stagedServers,
      clock: () => _now,
      maxPendingLocalCandidates: maxPendingLocalCandidates,
      maxPendingRemoteCandidates: maxPendingRemoteCandidates,
      maxLocalCandidateBatchSize: maxLocalCandidateBatchSize,
      mediaReadinessTimerScheduler: mediaReadinessTimerScheduler,
      mediaReadinessPollInterval: mediaReadinessPollInterval,
      maxMediaReadinessSamples: maxMediaReadinessSamples,
    );
  }

  final List<String> calls;
  final CallNegotiationMaterialStore materialStore;
  final List<CallIceServer> stagedServers;
  final List<CallEvent> dispatched = <CallEvent>[];
  late CallSessionSnapshot snapshot;
  late final _FakeEngine engine;
  late final _FakePreparer preparer;
  late final _FakeSignaling signaling;
  late final CallNegotiationEffectExecutor executor;
}

final class _FakePreparer implements CallNegotiationMediaPreparer {
  _FakePreparer(this.log);

  final List<String> log;
  int calls = 0;
  CallNegotiationPortException? error;
  Completer<void>? gate;

  @override
  Future<void> prepareLocallyAcceptedMedia({
    required CallSessionSnapshot snapshot,
    required CallConnectionConfiguration configuration,
  }) async {
    calls++;
    log.add('media.prepare');
    if (gate != null) await gate!.future;
    if (error case final error?) throw error;
  }
}

final class _FakeSignaling implements CallNegotiationSignalingPort {
  _FakeSignaling(this.log);

  final List<String> log;
  final List<(CallId, CallSessionDescription, int)> descriptions =
      <(CallId, CallSessionDescription, int)>[];
  final List<(CallId, List<CallIceCandidate>)> candidateBatches =
      <(CallId, List<CallIceCandidate>)>[];
  final List<int> restartGenerations = <int>[];
  Completer<void>? candidateGate;
  Completer<void>? descriptionGate;
  CallNegotiationPortException? descriptionError;
  CallNegotiationPortException? candidateError;

  @override
  Future<void> sendIceRestart({
    required CallId callId,
    required int iceGeneration,
  }) async {
    log.add('signal.restart');
    restartGenerations.add(iceGeneration);
  }

  @override
  Future<void> sendDescription({
    required CallId callId,
    required CallSessionDescription description,
    required int iceGeneration,
  }) async {
    log.add('signal.sdp');
    descriptions.add((callId, description, iceGeneration));
    if (descriptionError case final error?) throw error;
    final gate = descriptionGate;
    if (gate != null) await gate.future;
  }

  @override
  Future<void> sendCandidates({
    required CallId callId,
    required List<CallIceCandidate> candidates,
  }) async {
    log.add('signal.ice');
    candidateBatches.add((callId, List<CallIceCandidate>.of(candidates)));
    if (candidateError case final error?) throw error;
    final gate = candidateGate;
    if (gate != null) await gate.future;
  }
}

final class _FakeEngine implements CallEngine {
  _FakeEngine(this.log);

  final List<String> log;
  final StreamController<CallEngineEvent> _events =
      StreamController<CallEngineEvent>.broadcast(sync: true);
  final StreamController<CallIceCandidate> _candidates =
      StreamController<CallIceCandidate>.broadcast(sync: true);
  final List<CallSessionDescription> localDescriptions =
      <CallSessionDescription>[];
  final List<CallSessionDescription> remoteDescriptions =
      <CallSessionDescription>[];
  final List<List<CallIceCandidate>> addedCandidates =
      <List<CallIceCandidate>>[];
  final CallSessionDescription offer = const CallSessionDescription(
    type: CallSessionDescriptionType.offer,
    value: 'secret-local-offer',
    fingerprint: _fingerprint,
  );
  final CallSessionDescription answer = const CallSessionDescription(
    type: CallSessionDescriptionType.answer,
    value: 'secret-local-answer',
    fingerprint: _fingerprint,
  );
  CallConnectionSnapshot connectionSnapshot = _connectionSnapshot(
    state: CallConnectionState.connecting,
    ready: false,
  );
  CallEngineErrorCode? offerError;
  CallEngineErrorCode? answerError;
  CallEngineErrorCode? localError;
  CallEngineErrorCode? remoteError;
  CallEngineErrorCode? candidateError;
  CallEngineErrorCode? restartError;
  CallEngineErrorCode? snapshotError;
  CallIceCandidate? candidateOnSetLocal;
  int createOfferCalls = 0;
  int createAnswerCalls = 0;
  int addCandidateCalls = 0;
  int restartCalls = 0;
  int closeCalls = 0;
  bool failClose = false;
  Completer<void>? closeGate;
  Completer<void>? localDescriptionGate;
  int snapshotCalls = 0;
  int restartGeneration = 1;
  int _iceGeneration = 0;
  List<CallIceServer> lastRestartServers = const <CallIceServer>[];

  int get descriptionWorkCount =>
      createOfferCalls +
      createAnswerCalls +
      localDescriptions.length +
      remoteDescriptions.length;

  void emitEvent(CallEngineEvent event) => _events.add(event);
  void emitCandidate(CallIceCandidate candidate) => _candidates.add(candidate);

  @override
  Stream<CallEngineEvent> get events => _events.stream;

  @override
  Stream<CallIceCandidate> get localCandidates => _candidates.stream;

  @override
  List<CallEngineEvent> get recentEvents => const <CallEngineEvent>[];

  @override
  bool get isClosed => closeCalls > 0;

  @override
  int get candidateBatchCapacity => 8;

  @override
  int get iceGeneration => _iceGeneration;

  @override
  Future<void> createConnection(
    CallConnectionConfiguration configuration,
  ) async {}

  @override
  Future<CallSessionDescription> createOffer() async {
    createOfferCalls++;
    log.add('engine.offer');
    if (offerError case final code?) throw CallEngineException(code);
    return offer;
  }

  @override
  Future<CallSessionDescription> createAnswer() async {
    createAnswerCalls++;
    log.add('engine.answer');
    if (answerError case final code?) throw CallEngineException(code);
    return answer;
  }

  @override
  Future<void> setLocalDescription(CallSessionDescription description) async {
    log.add('engine.local');
    if (localDescriptionGate != null) await localDescriptionGate!.future;
    localDescriptions.add(description);
    final candidate = candidateOnSetLocal;
    if (candidate != null) _candidates.add(candidate);
    if (localError case final code?) throw CallEngineException(code);
  }

  @override
  Future<void> setRemoteDescription(CallSessionDescription description) async {
    log.add('engine.remote');
    remoteDescriptions.add(description);
    if (remoteError case final code?) throw CallEngineException(code);
  }

  @override
  Future<void> addIceCandidates(List<CallIceCandidate> candidates) async {
    addCandidateCalls++;
    addedCandidates.add(List<CallIceCandidate>.of(candidates));
    if (candidateError case final code?) throw CallEngineException(code);
  }

  @override
  Future<int> restartIce({
    List<CallIceServer> iceServers = const <CallIceServer>[],
  }) async {
    restartCalls++;
    log.add('engine.restart');
    lastRestartServers = List<CallIceServer>.of(iceServers);
    if (restartError case final code?) throw CallEngineException(code);
    return _iceGeneration = restartGeneration;
  }

  @override
  Future<void> setLocalAudioEnabled(bool enabled) async {}

  @override
  Future<void> setAudioSessionActive(bool active) async {}

  @override
  Future<List<CallAudioOutputRoute>> supportedOutputRoutes() async =>
      const <CallAudioOutputRoute>[CallAudioOutputRoute.systemDefault];

  @override
  Future<void> selectOutputRoute(CallAudioOutputRoute route) async {}

  @override
  Future<CallConnectionSnapshot> snapshot() async {
    snapshotCalls++;
    if (snapshotError case final code?) throw CallEngineException(code);
    return connectionSnapshot;
  }

  @override
  Future<void> close() async {
    closeCalls++;
    final gate = closeGate;
    if (gate != null) await gate.future;
    if (failClose) {
      throw const CallEngineException(CallEngineErrorCode.other);
    }
  }
}
