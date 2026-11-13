import 'dart:async';

import 'package:flutter_app/features/call/application/call_coordinator.dart';
import 'package:flutter_app/features/call/application/call_endpoint_resolver.dart';
import 'package:flutter_app/features/call/application/call_negotiation_effect_executor.dart';
import 'package:flutter_app/features/call/application/call_negotiation_material_store.dart';
import 'package:flutter_app/features/call/application/call_signaling_context_store.dart';
import 'package:flutter_app/features/call/application/call_v2_negotiation_effect_executor.dart';
import 'package:flutter_app/features/call/application/handle_incoming_call_signal.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_event.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_media.dart';
import 'package:flutter_app/features/call/domain/call_media_switch.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_signal_v2.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/infrastructure/call_authority_client.dart';
import 'package:flutter_test/flutter_test.dart';

final _call = CallId.parse('11111111-1111-4111-8111-111111111111');
const _handle = '22222222-2222-4222-8222-222222222222';
const _remoteNegotiation = '33333333-3333-4333-8333-333333333333';
const _otherNegotiation = '44444444-4444-4444-8444-444444444444';
const _authority = (fingerprint: 'friend-authority', relationshipRevision: 1);
const _configuration = CallConnectionConfiguration(
  transportPolicy: CallTransportPolicy.relayOnly,
  receiveAudio: true,
  receiveVideo: false,
  captureAudio: true,
  captureVideo: false,
);

void main() {
  test(
    'U3j-R settled switch revision survives recovery without reviving its grant',
    () async {
      final h = _Rig(recovery: true, media: CallMediaKind.audio);
      addTearDown(h.close);
      await h.connect();
      final request = h.switchRequest;
      h.owner.mediaSwitch!.request(
        MediaSwitchRequest(
          id: request.id,
          baseRevision: request.baseRevision,
          target: request.target,
          requesterIsCaller: request.requesterIsCaller,
          createdAtMs: request.createdAtMs,
          deadlineMs: request.deadlineMs,
          camera: CallCameraState.on,
        ),
        localGrant: CallLocalCameraGrant(
          foregroundConsent: true,
          permissionGranted: true,
          videoAgreed: true,
          isCurrent: () => true,
        ),
      );
      await h.owner.workSettled;
      h.admit(
        h.switchWire('media_response', {
          'switch_id': _otherNegotiation,
          'base_revision': 0,
          'decision': 'accept',
          'camera': 'off',
        }),
      );
      await h.owner.workSettled;
      h.admit(
        h.switchWire('answer', {
          'switch_id': _otherNegotiation,
          'negotiation_id': h.owner.negotiation!.negotiationId,
          'purpose': 'media_switch',
          'media_revision': 1,
          'media': 'video',
          'description': 'settled-answer',
          'fingerprint': 'fingerprint',
        }),
      );
      await h.owner.workSettled;
      h.admit(
        h.switchWire('media_commit_ack', {
          'switch_id': _otherNegotiation,
          'media_revision': 1,
          'media': 'video',
        }),
      );
      await h.owner.workSettled;
      expect(h.engine.video.cameraStarts, 1);
      expect(h.owner.mediaSwitch!.machine.settledRevision, 1);
      await h.loseMedia();
      await h.owner.workSettled;
      expect(h.engine.restartCalls, 1);
      final offer = h.sent.lastWhere((s) => s.event == CallSignalV2Type.offer);
      expect(offer.payload['purpose'], 'ice_restart');
      expect(offer.payload['media_revision'], 1);
      expect(offer.payload['media'], 'video');
      expect(h.engine.video.retired, greaterThan(0));
      h.engine.mediaReady = true;
      h.admit(
        h.remote(
          'answer',
          negotiation: offer.payload['negotiation_id']! as String,
          generation: 1,
          revision: 1,
          media: CallMediaKind.video,
          purpose: 'ice_restart',
        ),
      );
      await h.owner.workSettled;
      await _turn();
      expect(h.snapshot.state, CallState.connected);
      expect(h.owner.mediaSwitch!.machine.settledRevision, 1);
      expect(h.engine.video.cameraStarts, 1);
    },
  );

  for (final pendingKind in ['repair', 'grant']) {
    test(
      'U3j-R pending $pendingKind closes capture and blocks recovery takeover',
      () async {
        final h = _Rig(recovery: true, media: CallMediaKind.audio);
        addTearDown(h.close);
        await h.connect();
        final switches = h.owner.mediaSwitch!;
        final request = h.switchRequest;
        switches.request(
          MediaSwitchRequest(
            id: request.id,
            baseRevision: request.baseRevision,
            target: request.target,
            requesterIsCaller: request.requesterIsCaller,
            createdAtMs: request.createdAtMs,
            deadlineMs: request.deadlineMs,
            camera: CallCameraState.on,
          ),
          localGrant: CallLocalCameraGrant(
            foregroundConsent: true,
            permissionGranted: true,
            videoAgreed: true,
            isCurrent: () => true,
          ),
        );
        await h.owner.workSettled;
        h.admit(
          h.switchWire('media_response', {
            'switch_id': _otherNegotiation,
            'base_revision': 0,
            'decision': 'accept',
            'camera': 'off',
          }),
        );
        await h.owner.workSettled;
        final commit = Completer<void>();
        final reconcile = Completer<CallVideoSdpReconciliationOutcome>();
        if (pendingKind == 'repair') {
          h.engine.video.reconcileGate = reconcile;
          switches.abort(id: _otherNegotiation, baseRevision: 0, revision: 1);
        } else {
          h.admit(
            h.switchWire('answer', {
              'switch_id': _otherNegotiation,
              'negotiation_id': h.owner.negotiation!.negotiationId,
              'purpose': 'media_switch',
              'media_revision': 1,
              'media': 'video',
              'description': 'agreed-answer',
              'fingerprint': 'fingerprint',
            }),
          );
          await h.owner.workSettled;
          h.engine.video.commitGate = commit;
          h.admit(
            h.switchWire('media_commit_ack', {
              'switch_id': _otherNegotiation,
              'media_revision': 1,
              'media': 'video',
            }),
          );
        }
        await _turn();
        final tokens = h.engine.video.tokens.length;
        final retired = h.engine.video.retired;
        final loss = h.loseMedia();
        await _turn();
        try {
          expect(h.engine.video.retired, greaterThan(retired));
          expect(h.engine.restartCalls, 0);
          expect(h.engine.video.tokens, hasLength(tokens));
          expect(h.engine.video.cameraStarts, 0);
          expect(h.reconnectTimers, 1);
        } finally {
          if (pendingKind == 'repair') {
            reconcile.complete(CallVideoSdpReconciliationOutcome.alreadyStable);
          } else {
            commit.complete();
          }
          await loss;
          await h.owner.workSettled;
        }
        expect(h.engine.restartCalls, 0);
        expect(h.engine.video.tokens, hasLength(tokens));
        expect(h.engine.video.cameraStarts, 0);
        expect(h.snapshot.state, CallState.reconnecting);
      },
    );
  }

  test(
    'U3j-R caller handles peer request and completes from post-answer readiness',
    () async {
      final h = _Rig(recovery: true);
      addTearDown(h.close);
      await h.connect();
      final oldId = h.owner.negotiation!.negotiationId;
      expect(
        h.admit(h.remote('ice_restart', negotiation: oldId)),
        IncomingCallSignalOutcome.accepted,
      );
      await h.owner.workSettled;
      expect(h.engine.restartCalls, 1);
      final offer = h.sent.lastWhere((s) => s.event == CallSignalV2Type.offer);
      h.engine.mediaReady = true;
      expect(
        h.admit(
          h.remote(
            'answer',
            negotiation: offer.payload['negotiation_id']! as String,
            generation: 1,
            purpose: 'ice_restart',
          ),
        ),
        IncomingCallSignalOutcome.accepted,
      );
      await h.owner.workSettled;
      await _turn();
      expect(h.snapshot.state, CallState.connected);
      expect(
        h.events.where((e) => e.type == CallEventType.mediaRecovered),
        hasLength(1),
      );
      h.admit(h.remote('ice_restart', negotiation: oldId));
      await h.owner.workSettled;
      expect(h.engine.restartCalls, 1);
      expect(h.engine.video.cameraStarts, 0);
    },
  );

  test(
    'U3j-R revoked call during credential lookup cannot restart native ICE',
    () async {
      final h = _Rig(recovery: true);
      addTearDown(h.close);
      await h.connect();
      final staged = Completer<List<CallIceServer>>();
      h.serversGate = staged;
      final pending = h.loseMedia();
      await _turn();
      final retired = h.engine.video.retired;
      await h.end();
      staged.complete([
        CallIceServer(
          urls: ['turn:relay.invalid:3478'],
          expiresAt: DateTime.fromMillisecondsSinceEpoch(90000, isUtc: true),
        ),
      ]);
      await pending;
      await h.owner.workSettled;
      expect(retired, greaterThan(0));
      expect(h.engine.restartCalls, 0);
      expect(h.engine.video.offers, 1);
      expect(h.engine.video.cameraStarts, 0);
    },
  );

  test(
    'U3j-R caller restarts once per episode on the existing queue',
    () async {
      final h = _Rig(recovery: true);
      addTearDown(h.close);
      await h.connect();
      await h.loseMedia();
      final deadline = h.reconnectDeadline;
      await h.owner.execute(
        const CallEffect(CallEffectType.restartIce),
        h.snapshot,
      );
      await h.owner.execute(
        const CallEffect(CallEffectType.restartIce),
        h.snapshot,
      );
      await h.owner.workSettled;
      expect(h.engine.restartCalls, 1);
      expect(h.engine.video.offers, 2);
      expect(
        h.sent.where((s) => s.event == CallSignalV2Type.iceRestart),
        hasLength(1),
      );
      final offer = h.sent.lastWhere((s) => s.event == CallSignalV2Type.offer);
      expect(offer.payload['purpose'], 'ice_restart');
      expect(offer.payload['media_revision'], 0);
      expect(offer.payload['media'], 'video');
      expect(offer.iceGeneration, 1);
      expect(h.reconnectDeadline, same(deadline));
      expect(h.reconnectTimers, 1);
      expect(h.engine.eventListeners, 1);
      expect(h.engine.candidateListeners, 1);
      expect(h.engine.legacyOffers, 0);
      expect(h.engine.video.cameraStarts, 0);
    },
  );

  test(
    'U3j-R callee requests current generation without creating an offer',
    () async {
      final h = _Rig(recovery: true, incoming: true);
      addTearDown(h.close);
      await h.connect();
      final token = h.owner.negotiation!;
      await h.loseMedia();
      await h.owner.execute(
        const CallEffect(CallEffectType.requestIceRestart),
        h.snapshot,
      );
      await h.owner.workSettled;
      final request = h.sent.singleWhere(
        (s) => s.event == CallSignalV2Type.iceRestart,
      );
      expect(request.iceGeneration, 0);
      expect(request.payload['negotiation_id'], token.negotiationId);
      expect(request.payload['media_revision'], token.mediaRevision);
      expect(h.engine.restartCalls, 0);
      expect(h.engine.video.offers, 0);
      expect(h.engine.legacyOffers, 0);
    },
  );

  for (final offerFirst in [false, true]) {
    test(
      'U3j-R callee adopts one next generation with offerFirst=$offerFirst',
      () async {
        final h = _Rig(recovery: true, incoming: true);
        addTearDown(h.close);
        await h.connect();
        h.engine.mediaReady = true;
        final announce = h.remote(
          'ice_restart',
          negotiation: _otherNegotiation,
          generation: 1,
        );
        if (!offerFirst) {
          expect(h.admit(announce), IncomingCallSignalOutcome.accepted);
          await h.owner.workSettled;
          expect(h.engine.restartCalls, 1);
          expect(h.engine.video.answers, 1);
        }
        expect(
          h.admit(
            h.remote(
              'offer',
              negotiation: _otherNegotiation,
              generation: 1,
              purpose: 'ice_restart',
            ),
          ),
          IncomingCallSignalOutcome.accepted,
        );
        await h.owner.workSettled;
        await _turn();
        expect(h.snapshot.state, CallState.connected);
        expect(h.engine.restartCalls, 1);
        expect(h.engine.video.answers, 2);
        expect(h.engine.video.offers, 0);
        expect(
          h.sent
              .lastWhere((s) => s.event == CallSignalV2Type.answer)
              .payload['purpose'],
          'ice_restart',
        );
        h.admit(announce);
        await h.owner.workSettled;
        await _turn();
        expect(h.engine.restartCalls, 1);
        expect(h.engine.video.answers, 2);
        expect(h.snapshot.state, CallState.connected);
        expect(h.engine.video.cameraStarts, 0);
      },
    );
  }

  test(
    'U3j-R repeated peer-only episodes reuse real readiness without callbacks',
    () async {
      final h = _Rig(recovery: true, incoming: true);
      addTearDown(h.close);
      await h.connect();
      h.engine.mediaReady = true;
      for (var generation = 1; generation <= 2; generation++) {
        final negotiation = generation == 1
            ? _otherNegotiation
            : _remoteNegotiation;
        expect(
          h.admit(
            h.remote(
              'offer',
              negotiation: negotiation,
              generation: generation,
              purpose: 'ice_restart',
            ),
          ),
          IncomingCallSignalOutcome.accepted,
        );
        await h.owner.workSettled;
        await _turn();
        expect(h.snapshot.state, CallState.connected);
        expect(h.engine.restartCalls, generation);
        expect(
          h.events.where((e) => e.type == CallEventType.mediaRecovered),
          hasLength(generation),
        );
      }
      expect(h.engine.snapshotCalls, greaterThanOrEqualTo(2));
      expect(h.engine.eventListeners, 1);
      expect(h.engine.candidateListeners, 1);
      expect(h.engine.video.cameraStarts, 0);
    },
  );

  for (final rejectedEvent in [
    CallSignalV2Type.iceRestart,
    CallSignalV2Type.offer,
  ]) {
    test(
      'U3j-R retries exact $rejectedEvent custody without repeating native restart',
      () async {
        final h = _Rig(recovery: true, media: CallMediaKind.audio);
        addTearDown(h.close);
        await h.connect();
        h.deliveryFor = (signal) => signal.event != rejectedEvent;
        await h.loseMedia();
        await h.owner.workSettled;
        final first = h.sent.lastWhere((s) => s.event == rejectedEvent);
        final offers = h.engine.video.offers;
        final deadline = h.reconnectDeadline;
        h.deliveryFor = (_) => true;
        h.advance(500);
        await h.resumeRecovery();
        await h.owner.workSettled;
        final sentAgain = h.sent.where((s) => s.event == rejectedEvent).last;
        expect(identical(first, sentAgain), isTrue);
        expect(first.toMap(), sentAgain.toMap());
        expect(h.engine.restartCalls, 1);
        expect(
          h.engine.video.offers,
          rejectedEvent == CallSignalV2Type.offer ? offers : offers + 1,
        );
        expect(h.reconnectDeadline, same(deadline));
        expect(h.reconnectTimers, 1);
        expect(h.engine.video.cameraStarts, 0);
      },
    );
  }

  for (final boundary in ['end', 'timeout']) {
    test(
      'U3j-R $boundary fences a held native restart before any replacement SDP',
      () async {
        final h = _Rig(recovery: true);
        addTearDown(h.close);
        await h.connect();
        final held = Completer<void>();
        h.engine.restartGate = held;
        final pending = h.loseMedia();
        await _turn();
        try {
          expect(h.engine.restartCalls, 1);
          if (boundary == 'end') {
            await h.end();
          } else {
            h.advance(15000);
            await h.reconnectDeadline!.callback();
          }
        } finally {
          held.complete();
          await pending;
          await h.owner.workSettled;
        }
        expect(h.engine.video.offers, 1);
        expect(
          h.sent.where((s) => s.event == CallSignalV2Type.iceRestart),
          isEmpty,
        );
        expect(h.engine.video.cameraStarts, 0);
        expect(
          h.snapshot.isTerminal || h.snapshot.state == CallState.ending,
          isTrue,
        );
      },
    );
  }

  test(
    'U3j-R transport upgrade keeps the original audio-interruption deadline',
    () async {
      final h = _Rig(recovery: true);
      addTearDown(h.close);
      await h.connect();
      await h.loseMedia(audioOnly: true);
      final deadline = h.reconnectDeadline!;
      expect(h.engine.restartCalls, 0);
      h.advance(14000);
      final held = Completer<void>();
      h.engine.restartGate = held;
      final pending = h.loseMedia();
      await _turn();
      try {
        expect(h.engine.restartCalls, 1);
        expect(h.reconnectDeadline, same(deadline));
        expect(h.reconnectTimers, 1);
        h.advance(1000);
        await deadline.callback();
      } finally {
        held.complete();
        await pending;
        await h.owner.workSettled;
      }
      expect(h.engine.video.offers, 1);
      expect(
        h.sent.where((s) => s.event == CallSignalV2Type.iceRestart),
        isEmpty,
      );
      expect(
        h.snapshot.isTerminal || h.snapshot.state == CallState.ending,
        isTrue,
      );
    },
  );

  test(
    'U3j-R rejects a skipped generation and wrong settled revision',
    () async {
      final h = _Rig(recovery: true, incoming: true);
      addTearDown(h.close);
      await h.connect();
      expect(
        h.admit(
          h.remote(
            'ice_restart',
            generation: 2,
            negotiation: _otherNegotiation,
          ),
        ),
        IncomingCallSignalOutcome.rejected,
      );
      expect(
        h.admit(
          h.remote(
            'offer',
            generation: 1,
            revision: 1,
            negotiation: _otherNegotiation,
            purpose: 'ice_restart',
          ),
        ),
        IncomingCallSignalOutcome.rejected,
      );
      await h.owner.workSettled;
      expect(h.engine.restartCalls, 0);
      expect(h.engine.video.answers, 1);
      expect(h.snapshot.state, CallState.connected);
    },
  );

  test(
    'U3j-R pending switch native apply closes capture and blocks replacement',
    () async {
      final h = _Rig(recovery: true, media: CallMediaKind.audio);
      addTearDown(h.close);
      await h.connect();
      h.owner.mediaSwitch!.request(h.switchRequest);
      await h.owner.workSettled;
      final held = Completer<void>();
      h.engine.video.localApplyGate = held;
      h.admit(
        h.switchWire('media_response', {
          'switch_id': _otherNegotiation,
          'base_revision': 0,
          'decision': 'accept',
          'camera': 'off',
        }),
      );
      await _turn();
      final tokens = h.engine.video.tokens.length;
      final recovery = h.loseMedia();
      await _turn();
      try {
        expect(h.engine.video.retired, greaterThan(0));
        expect(h.engine.restartCalls, 0);
        expect(h.engine.video.tokens, hasLength(tokens));
        expect(h.reconnectTimers, 1);
      } finally {
        held.complete();
        await recovery;
        await h.owner.workSettled;
      }
      expect(h.engine.restartCalls, 0);
      expect(h.engine.video.tokens, hasLength(tokens));
      expect(h.engine.video.cameraStarts, 0);
      expect(h.snapshot.state, CallState.reconnecting);
    },
  );

  test(
    'U3j-R unproved native stability blocks replacement but keeps canonical timeout',
    () async {
      final h = _Rig(recovery: true);
      addTearDown(h.close);
      await h.connect();
      h.engine.video.reconciliation =
          CallVideoSdpReconciliationOutcome.unreconciled;
      await h.loseMedia();
      await h.owner.workSettled;
      expect(h.engine.video.reconciliations, 1);
      expect(h.engine.restartCalls, 0);
      expect(h.engine.video.offers, 1);
      expect(h.engine.video.retired, greaterThan(0));
      expect(h.snapshot.state, CallState.reconnecting);
      expect(h.reconnectTimers, 1);
    },
  );

  test(
    'U4 saturated incoming identity ledger retains selected response and abort',
    () async {
      final h = _Rig(media: CallMediaKind.audio);
      addTearDown(h.close);
      await h.connect();
      for (var i = 0; i < 127; i++) {
        expect(
          h.admit(
            h.remote('ice', negotiation: h.owner.negotiation!.negotiationId),
          ),
          IncomingCallSignalOutcome.accepted,
        );
        await h.owner.workSettled;
      }
      expect(h.owner.mediaSwitch, isNotNull);
      h.owner.mediaSwitch!.request(h.switchRequest);
      await h.owner.workSettled;
      expect(
        h.admit(
          h.switchWire('media_response', {
            'switch_id': _otherNegotiation,
            'base_revision': 0,
            'decision': 'accept',
            'camera': 'off',
          }),
        ),
        IncomingCallSignalOutcome.accepted,
      );
      await h.owner.workSettled;
      expect(
        h.admit(
          h.switchWire('answer', {
            'switch_id': _otherNegotiation,
            'negotiation_id': h.owner.negotiation!.negotiationId,
            'purpose': 'media_switch',
            'media_revision': 1,
            'media': 'video',
            'description': 'switch-answer',
            'fingerprint': 'fingerprint',
          }),
        ),
        IncomingCallSignalOutcome.accepted,
      );
      await h.owner.workSettled;
      expect(
        h.admit(
          h.switchWire('media_abort', {
            'switch_id': _otherNegotiation,
            'base_revision': 0,
            'media_revision': 1,
            'media': 'audio',
            'reason': 'cancelled',
          }),
        ),
        IncomingCallSignalOutcome.accepted,
      );
      await h.owner.workSettled;
      expect(h.owner.mediaSwitch!.machine.phase, MediaSwitchPhase.aborted);
      expect(h.engine.video.retired, greaterThan(0));
      expect(h.engine.closed, isFalse);
    },
  );

  test(
    'U4 saturated ledger coalesces exact answer replay until native success',
    () async {
      final h = _Rig(media: CallMediaKind.audio);
      addTearDown(h.close);
      await h.connect();
      for (var i = 0; i < 127; i++) {
        expect(
          h.admit(
            h.remote('ice', negotiation: h.owner.negotiation!.negotiationId),
          ),
          IncomingCallSignalOutcome.accepted,
        );
        await h.owner.workSettled;
      }
      h.owner.mediaSwitch!.request(h.switchRequest);
      await h.owner.workSettled;
      expect(
        h.admit(
          h.switchWire('media_response', {
            'switch_id': _otherNegotiation,
            'base_revision': 0,
            'decision': 'accept',
            'camera': 'off',
          }),
        ),
        IncomingCallSignalOutcome.accepted,
      );
      await h.owner.workSettled;
      final answer = h.switchWire('answer', {
        'switch_id': _otherNegotiation,
        'negotiation_id': h.owner.negotiation!.negotiationId,
        'purpose': 'media_switch',
        'media_revision': 1,
        'media': 'video',
        'description': 'held-switch-answer',
        'fingerprint': 'fingerprint',
      });
      final applied = Completer<void>();
      h.engine.video.remoteApplyGate = applied;
      expect(h.admit(answer), IncomingCallSignalOutcome.accepted);
      await _turn();
      try {
        expect(
          h.engine.video.remote.where((d) => d.value == 'held-switch-answer'),
          hasLength(1),
        );
        h.admit(answer);
        h.admit(answer);
        await _turn();
        expect(
          h.sent.where((s) => s.event == CallSignalV2Type.mediaCommit),
          isEmpty,
        );
        expect(h.engine.video.cameraStarts, 0);
      } finally {
        applied.complete();
        await h.owner.workSettled;
      }
      final commit = h.sent.singleWhere(
        (s) => s.event == CallSignalV2Type.mediaCommit,
      );
      h.admit(answer);
      await h.owner.workSettled;
      final commits = h.sent
          .where((s) => s.event == CallSignalV2Type.mediaCommit)
          .toList();
      expect(commits, hasLength(2));
      expect(identical(commits.last, commit), isTrue);
      expect(commits.last.toMap(), commit.toMap());
      expect(
        h.engine.video.remote.where((d) => d.value == 'held-switch-answer'),
        hasLength(1),
      );
      expect(h.engine.candidateListeners, 1);
      expect(h.engine.video.cameraStarts, 0);
    },
  );

  test(
    'U4 switch owner requires completed initial agreement and connected call',
    () async {
      final h = _Rig(media: CallMediaKind.audio);
      addTearDown(h.close);
      expect(h.owner.mediaSwitch, isNull);
      await h.connect();
      expect(h.owner.mediaSwitch, isNotNull);
      h.current = false;
      expect(h.owner.mediaSwitch, isNull);
    },
  );

  test(
    'U4 caller uses typed switch signaling and the one candidate listener',
    () async {
      final h = _Rig(media: CallMediaKind.audio);
      addTearDown(h.close);
      await h.connect();
      final switches = h.owner.mediaSwitch!;
      expect(switches.request(h.switchRequest), isTrue);
      await h.owner.workSettled;
      expect(h.sent.last.event, CallSignalV2Type.mediaRequest);
      expect(
        h.admit(
          h.switchWire('media_response', {
            'switch_id': _otherNegotiation,
            'base_revision': 0,
            'decision': 'accept',
            'camera': 'off',
          }),
        ),
        IncomingCallSignalOutcome.accepted,
      );
      await h.owner.workSettled;
      final offer = h.sent.last;
      expect(offer.event, CallSignalV2Type.offer);
      expect(offer.payload['purpose'], 'media_switch');
      expect(offer.payload['media_revision'], 1);
      expect(offer.payload['switch_id'], _otherNegotiation);
      h.engine.candidates.add(
        const CallIceCandidate(
          value: 'optional-ice',
          mediaId: 'audio',
          mediaLineIndex: 0,
          iceGeneration: 0,
        ),
      );
      await h.owner.workSettled;
      expect(h.sent.last.event, CallSignalV2Type.ice);
      expect(
        h.sent.last.payload['negotiation_id'],
        offer.payload['negotiation_id'],
      );
      expect(h.engine.candidateListeners, 1);
      expect(h.legacySignaling.candidateSends, 0);
      expect(h.engine.video.cameraStarts, 0);
    },
  );

  test(
    'U4 callee buffers bounded pre-offer ICE until selected native SDP',
    () async {
      final h = _Rig(incoming: true, media: CallMediaKind.audio, capacity: 1);
      addTearDown(h.close);
      await h.connect();
      expect(
        h.admit(
          h.switchWire('media_request', {
            'switch_id': _otherNegotiation,
            'base_revision': 0,
            'target_media': 'video',
            'camera': 'off',
          }),
        ),
        IncomingCallSignalOutcome.accepted,
      );
      await h.owner.workSettled;
      final switches = h.owner.mediaSwitch!;
      expect(
        switches.respond(
          id: _otherNegotiation,
          baseRevision: 0,
          fromCaller: false,
          response: MediaSwitchResponse.accept,
        ),
        isTrue,
      );
      await h.owner.workSettled;
      expect(
        h.admit(h.remote('ice', negotiation: _otherNegotiation)),
        IncomingCallSignalOutcome.accepted,
      );
      expect(
        h.admit(h.remote('ice', negotiation: _otherNegotiation)),
        IncomingCallSignalOutcome.deferred,
      );
      expect(h.engine.remoteCandidates, isEmpty);
      expect(
        h.admit(
          h.switchWire('offer', {
            'negotiation_id': _otherNegotiation,
            'purpose': 'media_switch',
            'switch_id': _otherNegotiation,
            'media_revision': 1,
            'media': 'video',
            'description': 'switch-offer',
            'fingerprint': 'fingerprint',
          }),
        ),
        IncomingCallSignalOutcome.accepted,
      );
      await h.owner.workSettled;
      expect(h.engine.remoteCandidates, hasLength(1));
      expect(h.sent.last.event, CallSignalV2Type.answer);
      expect(h.sent.last.payload['purpose'], 'media_switch');
      expect(h.engine.candidateListeners, 1);
    },
  );

  test(
    'U4 duplicate commit reuses exact ACK identity and never repeats capture',
    () async {
      final h = _Rig(incoming: true, media: CallMediaKind.audio);
      addTearDown(h.close);
      await h.connect();
      h.admit(
        h.switchWire('media_request', {
          'switch_id': _otherNegotiation,
          'base_revision': 0,
          'target_media': 'video',
          'camera': 'off',
        }),
      );
      await h.owner.workSettled;
      h.owner.mediaSwitch!.respond(
        id: _otherNegotiation,
        baseRevision: 0,
        fromCaller: false,
        response: MediaSwitchResponse.accept,
      );
      await h.owner.workSettled;
      h.admit(
        h.switchWire('offer', {
          'negotiation_id': _otherNegotiation,
          'purpose': 'media_switch',
          'switch_id': _otherNegotiation,
          'media_revision': 1,
          'media': 'video',
          'description': 'switch-offer',
          'fingerprint': 'fingerprint',
        }),
      );
      await h.owner.workSettled;
      for (var i = 0; i < 2; i++) {
        h.admit(
          h.switchWire('media_commit', {
            'switch_id': _otherNegotiation,
            'media_revision': 1,
            'media': 'video',
          }),
        );
        await h.owner.workSettled;
      }
      final acks = h.sent
          .where((s) => s.event == CallSignalV2Type.mediaCommitAck)
          .toList();
      expect(acks, hasLength(2));
      expect(acks[0].toMap(), acks[1].toMap());
      expect(h.engine.video.cameraStarts, 0);
      expect(
        h.engine.video.commits,
        2,
        reason: 'one initial and one switched commit',
      );
    },
  );

  test(
    'U4 timer retires pending native offer without awaiting the SDP queue',
    () async {
      final h = _Rig(media: CallMediaKind.audio);
      addTearDown(h.close);
      await h.connect();
      h.owner.mediaSwitch!.request(h.switchRequest);
      await h.owner.workSettled;
      h.engine.video.offerGate = Completer<void>();
      h.admit(
        h.switchWire('media_response', {
          'switch_id': _otherNegotiation,
          'base_revision': 0,
          'decision': 'accept',
          'camera': 'off',
        }),
      );
      await Future<void>.delayed(Duration.zero);
      h.elapsedMs += 10000;
      await h.timers.fire();
      expect(h.owner.mediaSwitch!.machine.phase, MediaSwitchPhase.aborted);
      expect(h.engine.video.retired, greaterThan(0));
      h.engine.video.offerGate!.complete();
      await h.owner.workSettled;
      expect(
        h.events.where((e) => e.type == CallEventType.negotiationFailed),
        isEmpty,
      );
      expect(h.engine.closed, isFalse);
    },
  );

  test(
    'U4 authority drift after consent never replaces original endpoint',
    () async {
      final h = _Rig(media: CallMediaKind.audio);
      addTearDown(h.close);
      await h.connect();
      h.owner.mediaSwitch!.request(h.switchRequest);
      await h.owner.workSettled;
      h.freshEndpoint = _endpoint(signing: 'rotated');
      h.admit(
        h.switchWire('media_response', {
          'switch_id': _otherNegotiation,
          'base_revision': 0,
          'decision': 'accept',
          'camera': 'off',
        }),
      );
      await h.owner.workSettled;
      expect(h.engine.video.offers, 1, reason: 'only initial offer');
      expect(
        h.events.where((e) => e.type == CallEventType.negotiationFailed),
        isEmpty,
      );
      expect(h.engine.closed, isFalse);
    },
  );

  for (final incoming in [false, true]) {
    test(
      'U3i original invite expiry survives later signals incoming=$incoming',
      () async {
        final h = _Rig(incoming: incoming);
        addTearDown(h.close);
        expect(h.contexts.originalV2InviteExpiresAtMs(_call), 41000);
        h.contexts.captureAuthenticatedV2(
          signal: h.remote(incoming ? 'invite' : 'ringing', expires: 45000),
          callHandle: _handle,
          admissionAuthority: _authority,
        );
        expect(h.contexts.originalV2InviteExpiresAtMs(_call), 41000);
      },
    );
  }

  for (final media in CallMediaKind.values) {
    test(
      'U3i caller offers only authenticated accepted ${media.name}',
      () async {
        final h = _Rig(media: media);
        addTearDown(h.close);
        final result = await h.start();
        expect(result?.type, CallEventType.negotiationReady);
        expect(h.preparer.calls, 1);
        expect(h.engine.binds, 1);
        expect(h.engine.legacyOffers, 0);
        expect(h.engine.video.local.map((d) => d.type), [
          CallSessionDescriptionType.offer,
        ]);
        expect(h.sent, hasLength(1));
        expect(h.sent.single.payload, containsPair('media', media.name));
        expect(h.sent.single.payload, containsPair('purpose', 'initial'));
        expect(h.sent.single.payload, containsPair('media_revision', 0));
        expect(h.sent.single.expiresAtMs, lessThanOrEqualTo(41000));
        expect(h.engine.video.cameraStarts, 0);
        await h.start();
        expect(
          h.engine.video.offers,
          1,
          reason: 'negotiationReady must not create another offer',
        );
      },
    );
  }

  test(
    'U3i audio-only acceptance of a video invite controls initial SDP',
    () async {
      final h = _Rig(
        media: CallMediaKind.audio,
        requestedMedia: CallMediaKind.video,
      );
      addTearDown(h.close);
      await h.start();
      expect(h.contexts.read(_call)!.requestedMedia, CallMediaKind.video);
      expect(h.sent.single.payload['media'], 'audio');
      expect(h.engine.video.cameraStarts, 0);
    },
  );

  test('U3i callee never creates an unsolicited offer', () async {
    final h = _Rig(incoming: true);
    addTearDown(h.close);
    await h.start();
    expect(h.sent, isEmpty);
    expect(h.engine.video.offers, 0);
    expect(h.engine.legacyOffers, 0);
  });

  test(
    'U3i incoming offer dispatches outside SDP queue and commits camera-off answer',
    () async {
      final h = _Rig(incoming: true);
      addTearDown(h.close);
      expect(h.admit(h.remote('offer')), IncomingCallSignalOutcome.accepted);
      expect(
        h.engine.video.remote,
        isEmpty,
        reason: 'admission must stay synchronous',
      );
      await h.owner.workSettled;
      expect(h.events.map((e) => e.type), contains(CallEventType.remoteOffer));
      expect(
        h.engine.video.remote.single.type,
        CallSessionDescriptionType.offer,
      );
      expect(h.engine.video.answers, 1);
      expect(h.sent.single.event, CallSignalV2Type.answer);
      expect(h.engine.video.commits, 1);
      expect(h.engine.video.cameraStarts, 0);
      expect(h.engine.legacyAnswers, 0);
    },
  );

  test('U3i caller accepts only its exact pending answer', () async {
    final h = _Rig();
    addTearDown(h.close);
    await h.start();
    final id = h.sent.single.payload['negotiation_id']! as String;
    expect(
      h.admit(h.remote('answer', negotiation: _otherNegotiation)),
      IncomingCallSignalOutcome.rejected,
    );
    expect(
      h.admit(h.remote('answer', negotiation: id)),
      IncomingCallSignalOutcome.accepted,
    );
    await h.owner.workSettled;
    expect(
      h.engine.video.remote.single.type,
      CallSessionDescriptionType.answer,
    );
    expect(h.engine.video.commits, 1);
    expect(h.engine.video.cameraStarts, 0);
  });

  test('U3i no SDP or microphone before explicit media acceptance', () async {
    final h = _Rig(accepted: false);
    addTearDown(h.close);
    await h.start();
    expect(h.preparer.calls, 0);
    expect(h.engine.binds, 0);
    expect(h.sent, isEmpty);
  });

  test('U3i ringing peer cannot enqueue media before acceptance', () async {
    final h = _Rig(incoming: true, accepted: false, state: CallState.ringing);
    addTearDown(h.close);
    expect(h.admit(h.remote('offer')), IncomingCallSignalOutcome.rejected);
    await h.owner.workSettled;
    expect(h.engine.binds, 0);
  });

  test('U3i disabled v2 cannot fall through to legacy SDP or ICE', () async {
    final h = _Rig(enabled: false);
    addTearDown(h.close);
    await h.start();
    expect(h.owner.consumeLocalCandidate(h.snapshot, _candidate()), isTrue);
    expect(h.sent, isEmpty);
    expect(h.engine.binds, 0);
    expect(h.engine.legacyOffers, 0);
    expect(h.legacySignaling.candidateSends, 0);
  });

  test('U3i v1 retains existing executor and candidate sender', () async {
    final h = _Rig(v1: true);
    addTearDown(h.close);
    await h.start();
    h.engine.candidates.add(_candidate());
    await _microtasks();
    expect(h.engine.legacyOffers, 1);
    expect(h.legacySignaling.descriptions, 1);
    expect(h.legacySignaling.candidateSends, 1);
    expect(h.engine.binds, 0);
  });

  for (final mutation in [
    'call',
    'handle',
    'sender-account',
    'sender-device',
    'recipient-account',
    'recipient-device',
  ]) {
    test('U3i rejects authenticated media with mismatched $mutation', () async {
      final h = _Rig(incoming: true);
      addTearDown(h.close);
      final map = h.remote('offer').toMap();
      switch (mutation) {
        case 'call':
          map['call_id'] = _otherNegotiation;
        case 'sender-account':
          map['sender_account_peer_id'] = 'wrong';
        case 'sender-device':
          map['sender_device_peer_id'] = 'wrong';
        case 'recipient-account':
          map['recipient_account_peer_id'] = 'wrong';
        case 'recipient-device':
          map['recipient_device_peer_id'] = 'wrong';
      }
      expect(
        h.admit(
          CallSignalV2.fromMap(map, videoEnabled: true),
          handle: mutation == 'handle' ? _otherNegotiation : _handle,
        ),
        IncomingCallSignalOutcome.rejected,
      );
      await h.owner.workSettled;
      expect(h.engine.binds, 0);
    });
  }

  for (final mutation in ['media', 'purpose', 'generation', 'role']) {
    test(
      'U3i refuses wrong initial $mutation without legacy fallback',
      () async {
        final h = _Rig(incoming: mutation != 'role');
        addTearDown(h.close);
        final signal = h.remote(
          'offer',
          media: mutation == 'media'
              ? CallMediaKind.audio
              : CallMediaKind.video,
          purpose: mutation == 'purpose' ? 'ice_restart' : 'initial',
          generation: mutation == 'generation' ? 1 : 0,
        );
        expect(h.admit(signal), IncomingCallSignalOutcome.rejected);
        await h.owner.workSettled;
        expect(h.engine.video.remote, isEmpty);
        expect(h.engine.legacyOffers, 0);
      },
    );
  }

  test(
    'U3i queue capacity defers ICE while reserving admission for the offer',
    () async {
      final h = _Rig(incoming: true, capacity: 2);
      addTearDown(h.close);
      expect(h.admit(h.remote('ice')), IncomingCallSignalOutcome.accepted);
      expect(h.admit(h.remote('ice')), IncomingCallSignalOutcome.accepted);
      expect(h.admit(h.remote('ice')), IncomingCallSignalOutcome.deferred);
      await h.owner.workSettled;
      expect(h.engine.remoteCandidates, isEmpty);
      expect(h.admit(h.remote('offer')), IncomingCallSignalOutcome.accepted);
      await h.owner.workSettled;
      expect(h.engine.remoteCandidates, hasLength(2));
      expect(h.engine.video.remote, hasLength(1));
    },
  );

  test('U3i ICE cannot be retagged to a different negotiation', () async {
    final h = _Rig(incoming: true);
    addTearDown(h.close);
    expect(
      h.admit(h.remote('ice', negotiation: _otherNegotiation)),
      IncomingCallSignalOutcome.accepted,
    );
    expect(h.admit(h.remote('ice')), IncomingCallSignalOutcome.accepted);
    expect(h.admit(h.remote('offer')), IncomingCallSignalOutcome.accepted);
    await h.owner.workSettled;
    expect(h.engine.remoteCandidates, hasLength(1));
    expect(
      h.admit(h.remote('ice', negotiation: _otherNegotiation)),
      IncomingCallSignalOutcome.rejected,
    );
  });

  test(
    'U3i single engine listener routes local ICE after its typed offer',
    () async {
      final h = _Rig();
      addTearDown(h.close);
      h.engine.video.onOffer = () => h.engine.candidates.add(_candidate());
      await h.start();
      await h.owner.workSettled;
      expect(h.sent.map((s) => s.event), [
        CallSignalV2Type.offer,
        CallSignalV2Type.ice,
      ]);
      expect(
        h.sent.last.payload['negotiation_id'],
        h.sent.first.payload['negotiation_id'],
      );
      expect(h.engine.candidateListeners, 1);
      expect(h.legacySignaling.candidateSends, 0);
    },
  );

  test('U3i stale ICE generation is discarded without a legacy send', () async {
    final h = _Rig();
    addTearDown(h.close);
    await h.start();
    h.engine.candidates.add(_candidate(generation: 1));
    await h.owner.workSettled;
    expect(h.sent, hasLength(1));
    expect(h.legacySignaling.candidateSends, 0);
    expect(
      h.events.where((e) => e.type == CallEventType.negotiationFailed),
      isEmpty,
    );
  });

  test(
    'U3i original authority survives a fresh rotated endpoint refusal',
    () async {
      final h = _Rig();
      addTearDown(h.close);
      h.freshEndpoint = _endpoint(signing: 'rotated');
      final result = await h.start();
      expect(result?.type, CallEventType.negotiationFailed);
      expect(h.engine.binds, 0);
      expect(h.contexts.admittedV2Endpoint(_call)!.signingPublicKey, 'signing');
      expect(h.sent, isEmpty);
    },
  );

  test(
    'U3i stale completion after createOffer cannot apply or send SDP',
    () async {
      final h = _Rig();
      final gate = Completer<void>();
      h.engine.video.offerGate = gate;
      addTearDown(() async {
        if (!gate.isCompleted) gate.complete();
        await h.close();
      });
      final pending = h.start();
      await _microtasks();
      expect(h.engine.video.offers, 1);
      h.current = false;
      gate.complete();
      await pending;
      expect(h.engine.video.local, isEmpty);
      expect(h.sent, isEmpty);
    },
  );

  test(
    'U3i incoming queue rechecks its authenticated work fence after lookup',
    () async {
      final h = _Rig(incoming: true);
      final gate = Completer<ResolvedCallEndpoint>();
      h.lookupGate = gate;
      var incomingCurrent = true;
      addTearDown(() async {
        if (!gate.isCompleted) gate.complete(h.freshEndpoint);
        await h.close();
      });
      expect(
        h.admit(h.remote('offer'), allowed: () => incomingCurrent),
        IncomingCallSignalOutcome.accepted,
      );
      await _microtasks();
      expect(h.lookupCalls, 1);
      incomingCurrent = false;
      gate.complete(h.freshEndpoint);
      await h.owner.workSettled;
      expect(h.engine.video.remote, isEmpty);
      expect(h.sent, isEmpty);
    },
  );

  test('U3i transport wake without custody cannot announce an offer', () async {
    final h = _Rig();
    addTearDown(h.close);
    h.delivered = false;
    final result = await h.start();
    expect(result?.type, CallEventType.negotiationFailed);
    expect(h.engine.video.commits, 0);
    expect(h.legacySignaling.descriptions, 0);
  });

  test(
    'U3i original deadline cannot reset on repeated start or wall-clock reversal',
    () async {
      final h = _Rig();
      addTearDown(h.close);
      await h.start();
      expect(h.timers.handles, hasLength(1));
      expect(h.timers.delays.single, const Duration(milliseconds: 31000));
      h.nowMs = 5000;
      await h.start();
      expect(h.timers.handles, hasLength(1));
      h.elapsedMs += 31000;
      await h.timers.fire();
      await h.owner.workSettled;
      expect(
        h.events.where((e) => e.type == CallEventType.negotiationFailed),
        hasLength(1),
      );
      expect(
        h.admit(
          h.remote(
            'answer',
            negotiation: h.sent.single.payload['negotiation_id']! as String,
          ),
        ),
        IncomingCallSignalOutcome.rejected,
      );
    },
  );

  test(
    'U3i expired original invite cannot borrow a later accept expiry',
    () async {
      final h = _Rig();
      addTearDown(h.close);
      h.nowMs = 41000;
      final result = await h.start();
      expect(result?.type, CallEventType.negotiationFailed);
      expect(h.engine.binds, 0);
      expect(h.sent, isEmpty);
    },
  );

  test(
    'U3i deadline retires a pending native offer without waiting for it',
    () async {
      final h = _Rig();
      final gate = Completer<void>();
      h.engine.video.offerGate = gate;
      addTearDown(() async {
        if (!gate.isCompleted) gate.complete();
        await h.close();
      });
      final pending = h.start();
      await _microtasks();
      expect(h.engine.video.offers, 1);
      h.elapsedMs += 31000;
      await h.timers.fire();
      await _microtasks();
      expect(
        h.events.where((e) => e.type == CallEventType.negotiationFailed),
        hasLength(1),
      );
      gate.complete();
      await pending;
      expect(h.engine.video.local, isEmpty);
      expect(h.sent, isEmpty);
    },
  );

  test('U3i permission denial retains the audio preparer reason', () async {
    final h = _Rig();
    addTearDown(h.close);
    h.preparer.error = const CallNegotiationPortException(
      CallNegotiationPortErrorCode.permissionDenied,
    );
    final result = await h.start();
    expect(result?.type, CallEventType.negotiationFailed);
    expect(result?.endReason, CallEndReason.permissionDenied);
    expect(h.engine.binds, 0);
  });

  test('U3i close revokes the pending token and still closes audio', () async {
    final h = _Rig();
    final gate = Completer<void>();
    h.engine.video.offerGate = gate;
    addTearDown(() async {
      if (!gate.isCompleted) gate.complete();
      await h.close();
    });
    final pending = h.start();
    await _microtasks();
    expect(h.engine.video.offers, 1);
    await h.close();
    expect(h.engine.closed, isTrue);
    expect(h.engine.video.closed, isTrue);
    gate.complete();
    await pending;
    expect(h.engine.video.local, isEmpty);
    expect(h.sent, isEmpty);
  });
}

Future<void> _microtasks() => Future<void>.delayed(Duration.zero);

CallIceCandidate _candidate({int generation = 0}) => CallIceCandidate(
  value: 'opaque-ice',
  mediaId: 'audio',
  mediaLineIndex: 0,
  iceGeneration: generation,
);

ResolvedCallEndpoint _endpoint({String signing = 'signing'}) =>
    ResolvedCallEndpoint(
      accountPeerId: 'remote-account',
      devicePeerId: 'remote-device',
      signingPublicKey: signing,
      mlKemPublicKey: 'kem',
      admissionAuthority: _authority,
      deviceKeyEpoch: 1,
      preferenceEpoch: 1,
      platform: CallEndpointPlatform.android,
      expiresAtMs: 100000,
      routingHandle: 'routing',
      wakeHandle: 'wake',
      capabilities: const {'voice_call_v1', 'video_call_v2'},
    );

Future<void> _turn() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class _Rig {
  _Rig({
    this.incoming = false,
    this.recovery = false,
    this.media = CallMediaKind.video,
    CallMediaKind? requestedMedia,
    bool accepted = true,
    bool enabled = true,
    bool v1 = false,
    int capacity = 64,
    CallState state = CallState.accepted,
  }) {
    if (recovery) engine.video = _RecoveryVideo();
    snapshot = CallSessionSnapshot.active(
      callId: _call,
      contactPeerId: 'remote-account',
      direction: incoming ? CallDirection.incoming : CallDirection.outgoing,
      state: state,
      callerAccountPeerId: incoming ? 'remote-account' : 'local-account',
      callerDeviceId: incoming ? 'remote-device' : 'local-device',
      startedAt: DateTime.fromMillisecondsSinceEpoch(1000),
      acceptedAt: accepted ? DateTime.fromMillisecondsSinceEpoch(nowMs) : null,
      observedAt: DateTime.fromMillisecondsSinceEpoch(nowMs),
    );
    if (v1) {
      contexts.storeOutgoing(
        callId: _call,
        callHandle: _handle,
        localAccountPeerId: 'local-account',
        localDevicePeerId: 'local-device',
        remoteAccountPeerId: 'remote-account',
        remoteDevicePeerId: 'remote-device',
        admissionAuthority: _authority,
        invitePayload: const {},
      );
    } else if (incoming) {
      contexts.captureAuthenticatedV2(
        signal: remote('invite', created: 1000, media: requestedMedia),
        callHandle: _handle,
        admissionAuthority: _authority,
        admittedEndpoint: freshEndpoint,
      );
      if (accepted) contexts.recordLocalAcceptance(_call, media: media);
    } else {
      final map = remote(
        'invite',
        created: 1000,
        media: requestedMedia,
      ).toMap();
      map.addAll({
        'sender_account_peer_id': 'local-account',
        'sender_device_peer_id': 'local-device',
        'recipient_account_peer_id': 'remote-account',
        'recipient_device_peer_id': 'remote-device',
      });
      contexts.storeOutgoingV2(
        invite: CallSignalV2.fromMap(map, videoEnabled: true),
        callHandle: _handle,
        admissionAuthority: _authority,
        admittedEndpoint: freshEndpoint,
      );
      if (accepted) {
        contexts.captureAuthenticatedV2(
          signal: remote('accept'),
          callHandle: _handle,
          admissionAuthority: _authority,
        );
      }
    }
    legacy = CallNegotiationEffectExecutor(
      engine: engine,
      materialStore: CallNegotiationMaterialStore(),
      mediaPreparer: preparer,
      signaling: legacySignaling,
      configuration: _configuration,
      dispatchEvent: dispatch,
      readActiveSnapshot: () => snapshot,
      readStagedIceServers: (_) async =>
          await (serversGate?.future ??
              Future.value(
                recovery
                    ? [
                        CallIceServer(
                          urls: ['turn:relay.invalid:3478'],
                          username: 'fixture',
                          credential: 'fixture',
                          expiresAt: DateTime.fromMillisecondsSinceEpoch(
                            90000,
                            isUtc: true,
                          ),
                        ),
                      ]
                    : <CallIceServer>[],
              )),
      mediaReadinessTimerScheduler: recovery ? timers : null,
      clock: () => DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true),
      consumeLocalCandidate: (s, c) => owner.consumeLocalCandidate(s, c),
    );
    owner = CallV2NegotiationEffectExecutor(
      callId: _call,
      legacy: legacy,
      videoEngine: engine,
      contexts: contexts,
      resolveEndpoint: (_) async {
        lookupCalls++;
        return await (lookupGate?.future ?? Future.value(freshEndpoint));
      },
      sendSignal:
          ({
            required signal,
            required callHandle,
            required admittedEndpoint,
            required canApply,
          }) async {
            expect(callHandle, _handle);
            expect(admittedEndpoint.signingPublicKey, 'signing');
            if (!canApply()) return false;
            sent.add(signal);
            return deliveryFor?.call(signal) ?? delivered;
          },
      canApply: () => current,
      idSource: () =>
          'aaaaaaaa-aaaa-4aaa-8aaa-${(++ids).toRadixString(16).padLeft(12, '0')}',
      videoEnabled: enabled,
      maxPendingMedia: capacity,
      monotonicNowMs: () => elapsedMs,
      timerScheduler: timers,
    );
  }

  final bool incoming;
  final bool recovery;
  final CallMediaKind media;
  final contexts = CallSignalingContextStore(videoEnabled: true);
  final engine = _Engine();
  final preparer = _Preparer();
  final legacySignaling = _LegacySignaling();
  final timers = _Timers();
  final List<CallSignalV2> sent = [];
  final List<CallEvent> events = [];
  late final CallNegotiationEffectExecutor legacy;
  late final CallV2NegotiationEffectExecutor owner;
  late CallSessionSnapshot snapshot;
  ResolvedCallEndpoint freshEndpoint = _endpoint();
  Completer<ResolvedCallEndpoint>? lookupGate;
  Completer<List<CallIceServer>>? serversGate;
  bool Function(CallSignalV2)? deliveryFor;
  _TimerHandle? reconnectDeadline;
  int reconnectTimers = 0;
  int eventIds = 0;
  int lookupCalls = 0;
  int nowMs = 10000;
  int elapsedMs = 1000;
  int ids = 0;
  int sequence = 0;
  bool current = true;
  bool delivered = true;

  MediaSwitchRequest get switchRequest => MediaSwitchRequest(
    id: _otherNegotiation,
    baseRevision: 0,
    target: CallMediaKind.video,
    requesterIsCaller: true,
    createdAtMs: elapsedMs,
    deadlineMs: elapsedMs + 30000,
  );

  CallSignalV2 switchWire(String event, Map<String, Object?> payload) {
    final map = remote('ringing').toMap();
    map['event'] = event;
    map['payload'] = payload;
    return CallSignalV2.fromMap(map, videoEnabled: true);
  }

  Future<void> connect() async {
    if (incoming) {
      admit(remote('offer'));
    } else {
      await start();
      admit(remote('answer', negotiation: owner.negotiation!.negotiationId));
    }
    await owner.workSettled;
    snapshot = snapshot.copyWith(state: CallState.connected);
  }

  Future<CallEvent?> start() async {
    final result = await owner.execute(
      const CallEffect(CallEffectType.startNegotiation),
      snapshot,
    );
    if (result?.type == CallEventType.negotiationReady) {
      snapshot = snapshot.copyWith(state: CallState.negotiating);
    }
    return result;
  }

  Future<void> dispatch(CallEvent event) async {
    events.add(event);
    if (recovery &&
        (snapshot.state == CallState.connected ||
            snapshot.state == CallState.reconnecting ||
            snapshot.isTerminal)) {
      final reduction = const CallReducer().reduce(snapshot, event);
      snapshot = reduction.snapshot;
      for (final effect in reduction.effects) {
        if (effect.type == CallEffectType.scheduleReconnectTimeout) {
          reconnectTimers++;
          final generation = snapshot.reconnectGeneration;
          late final _TimerHandle deadline;
          deadline =
              timers.schedule(effect.delay!, () async {
                    if (!identical(reconnectDeadline, deadline) ||
                        !deadline.isActive) {
                      return;
                    }
                    await dispatch(
                      CallEvent(
                        type: CallEventType.timeout,
                        timeoutKind: CallTimeoutKind.reconnect,
                        eventId: 'recovery-timeout-${++eventIds}',
                        occurredAt: DateTime.fromMillisecondsSinceEpoch(
                          nowMs,
                          isUtc: true,
                        ),
                        callId: _call,
                        reconnectGeneration: generation,
                      ),
                    );
                  })
                  as _TimerHandle;
          reconnectDeadline = deadline;
        } else if (effect.type == CallEffectType.cancelTimers) {
          reconnectDeadline?.cancel();
        } else {
          final followUp = await owner.execute(effect, snapshot);
          if (followUp != null) await dispatch(followUp);
        }
      }
      return;
    }
    final effect = switch (event.type) {
      CallEventType.remoteOffer => CallEffectType.deliverOffer,
      CallEventType.remoteAnswer => CallEffectType.deliverAnswer,
      _ => null,
    };
    if (effect != null) {
      snapshot = snapshot.copyWith(
        state: CallState.negotiating,
        recentEventIds: [event.eventId],
      );
      final result = await owner.execute(CallEffect(effect), snapshot);
      if (result != null) events.add(result);
    }
  }

  Future<void> loseMedia({bool audioOnly = false}) => dispatch(
    CallEvent(
      type: audioOnly
          ? CallEventType.audioInterrupted
          : CallEventType.mediaLost,
      eventId: 'loss-${++eventIds}',
      occurredAt: DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true),
      callId: _call,
    ),
  );

  Future<void> resumeRecovery() => owner
      .execute(const CallEffect(CallEffectType.resumeRecoverySignals), snapshot)
      .then((_) {});

  void advance(int milliseconds) {
    nowMs += milliseconds;
    elapsedMs += milliseconds;
  }

  Future<void> end() => dispatch(
    CallEvent(
      type: CallEventType.end,
      eventId: 'end-${++eventIds}',
      occurredAt: DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true),
      callId: _call,
    ),
  );

  IncomingCallSignalOutcome admit(
    CallSignalV2 signal, {
    String handle = _handle,
    bool Function()? allowed,
  }) => owner.handleAuthenticated(
    signal: signal,
    callHandle: handle,
    canApply: allowed ?? () => true,
  );

  CallSignalV2 remote(
    String event, {
    String negotiation = _remoteNegotiation,
    CallMediaKind? media,
    String purpose = 'initial',
    int generation = 0,
    int revision = 0,
    int? created,
    int expires = 41000,
  }) => CallSignalV2.fromMap({
    'schema': CallSignalV2.schema,
    'call_id': _call.value,
    'message_id':
        'bbbbbbbb-bbbb-4bbb-8bbb-${(++sequence).toRadixString(16).padLeft(12, '0')}',
    'event': event,
    'sender_account_peer_id': 'remote-account',
    'sender_device_peer_id': 'remote-device',
    'recipient_account_peer_id': 'local-account',
    'recipient_device_peer_id': 'local-device',
    'sender_sequence': sequence,
    'ice_generation': generation,
    'created_at_ms': created ?? nowMs,
    'expires_at_ms': expires,
    'payload': switch (event) {
      'invite' => {
        'media': (media ?? this.media).name,
        'camera': 'off',
        'capabilities': ['audio', 'video'],
      },
      'accept' => {'media': (media ?? this.media).name, 'camera': 'off'},
      'offer' || 'answer' => {
        'negotiation_id': negotiation,
        'purpose': purpose,
        'switch_id': null,
        'media_revision': revision,
        'media': (media ?? this.media).name,
        'description': 'opaque-sdp',
        'fingerprint': 'opaque-fingerprint',
      },
      'ice_restart' => {
        'negotiation_id': negotiation,
        'media_revision': revision,
      },
      'ice' => {
        'negotiation_id': negotiation,
        'candidate': 'opaque-ice',
        'media_id': 'audio',
        'media_line_index': 0,
      },
      _ => <String, Object?>{},
    },
  }, videoEnabled: true);

  Future<void> close() => owner.close();
}

final class _Preparer implements CallNegotiationMediaPreparer {
  int calls = 0;
  Object? error;
  @override
  Future<void> prepareLocallyAcceptedMedia({
    required CallSessionSnapshot snapshot,
    required CallConnectionConfiguration configuration,
  }) async {
    calls++;
    if (error != null) throw error!;
  }
}

final class _LegacySignaling implements CallNegotiationSignalingPort {
  int descriptions = 0;
  int candidateSends = 0;
  @override
  Future<void> sendDescription({
    required CallId callId,
    required CallSessionDescription description,
    required int iceGeneration,
  }) async {
    descriptions++;
  }

  @override
  Future<void> sendCandidates({
    required CallId callId,
    required List<CallIceCandidate> candidates,
  }) async {
    candidateSends++;
  }

  @override
  Future<void> sendIceRestart({
    required CallId callId,
    required int iceGeneration,
  }) async {}
}

final class _Engine implements CallEngine, CallVideoEngine {
  _Engine() {
    eventController = StreamController<CallEngineEvent>.broadcast(
      sync: true,
      onListen: () => eventListeners++,
    );
    candidates = StreamController<CallIceCandidate>.broadcast(
      sync: true,
      onListen: () => candidateListeners++,
    );
  }
  late final StreamController<CallEngineEvent> eventController;
  late final StreamController<CallIceCandidate> candidates;
  _Video video = _Video();
  final List<CallIceCandidate> remoteCandidates = [];
  int candidateListeners = 0;
  int eventListeners = 0;
  int generation = 0;
  int restartCalls = 0;
  int snapshotCalls = 0;
  bool mediaReady = false;
  Completer<void>? restartGate;
  int binds = 0;
  int legacyOffers = 0;
  int legacyAnswers = 0;
  bool closed = false;
  @override
  Stream<CallEngineEvent> get events => eventController.stream;
  @override
  Stream<CallIceCandidate> get localCandidates => candidates.stream;
  @override
  List<CallEngineEvent> get recentEvents => [];
  @override
  bool get isClosed => closed;
  @override
  int get iceGeneration => generation;
  @override
  int get candidateBatchCapacity => 8;
  @override
  CallVideoSession bindV2Video({
    required CallId callId,
    required bool localIsCaller,
    required CallWireVersion wireVersion,
    required bool Function() canApply,
    bool videoEnabled = false,
  }) {
    expect(callId, _call);
    expect(wireVersion, CallWireVersion.v2);
    expect(videoEnabled, isTrue);
    binds++;
    return video;
  }

  @override
  Future<int> restartIce({List<CallIceServer> iceServers = const []}) async {
    restartCalls++;
    await restartGate?.future;
    return ++generation;
  }

  @override
  Future<CallConnectionSnapshot> snapshot() async {
    snapshotCalls++;
    return CallConnectionSnapshot(
      state: CallConnectionState.connected,
      transportPolicy: CallTransportPolicy.relayOnly,
      transport: CallTransportClass.relay,
      quality: CallQualityBand.good,
      localAudioCaptureTrackCount: 1,
      localVideoCaptureTrackCount: 0,
      audioReceiveTransceiverCount: 1,
      videoTransceiverCount: 1,
      selectedPairSucceeded: mediaReady,
      selectedPairNominated: mediaReady,
      dtlsReady: mediaReady,
      audioSessionActive: mediaReady,
      localAudioSenderAttached: mediaReady,
      localAudioTrackLive: mediaReady,
      remoteAudioReceiverAttached: mediaReady,
      remoteAudioTrackLive: mediaReady,
    );
  }

  @override
  Future<CallSessionDescription> createOffer() async {
    legacyOffers++;
    return _description(CallSessionDescriptionType.offer);
  }

  @override
  Future<CallSessionDescription> createAnswer() async {
    legacyAnswers++;
    return _description(CallSessionDescriptionType.answer);
  }

  @override
  Future<void> setLocalDescription(CallSessionDescription description) async {}
  @override
  Future<void> addIceCandidates(List<CallIceCandidate> candidates) async {
    remoteCandidates.addAll(candidates);
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    await eventController.close();
    await candidates.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected engine operation ${invocation.memberName}');
}

CallSessionDescription _description(CallSessionDescriptionType type) =>
    CallSessionDescription(
      type: type,
      value: 'opaque-sdp',
      fingerprint: 'opaque-fingerprint',
    );

final class _Token implements CallVideoNegotiation {
  _Token(this.negotiationId, this.mediaRevision, this.media);
  @override
  CallId get callId => _call;
  @override
  final String negotiationId;
  @override
  final int mediaRevision;
  @override
  final CallMediaKind media;
}

final class _RecoveryVideo extends _Video implements CallVideoSdpReconciler {}

class _Video implements CallVideoSession {
  Completer<void>? offerGate;
  Completer<void>? remoteApplyGate;
  Completer<void>? localApplyGate;
  Completer<void>? commitGate;
  Completer<CallVideoSdpReconciliationOutcome>? reconcileGate;
  int reconciliations = 0;
  CallVideoSdpReconciliationOutcome reconciliation =
      CallVideoSdpReconciliationOutcome.alreadyStable;
  final List<CallVideoNegotiation> tokens = [];
  void Function()? onOffer;
  int offers = 0;
  int answers = 0;
  int commits = 0;
  int cameraStarts = 0;
  bool closed = false;
  int retired = 0;
  @override
  Future<bool> retireVideo() async {
    retired++;
    return true;
  }

  @override
  Future<bool> stopLocalCamera() async => true;
  final List<CallSessionDescription> local = [];
  final List<CallSessionDescription> remote = [];
  @override
  CallId get callId => _call;
  @override
  bool get hasPendingCleanup => false;
  @override
  CallVideoNegotiation beginNegotiation({
    required String negotiationId,
    required int mediaRevision,
    required CallMediaKind media,
    required bool Function() canApply,
  }) {
    final token = _Token(negotiationId, mediaRevision, media);
    tokens.add(token);
    return token;
  }

  Future<CallVideoSdpReconciliationOutcome> reconcilePending(
    CallVideoNegotiation token, {
    required bool Function() canApply,
  }) async {
    reconciliations++;
    final result =
        await (reconcileGate?.future ?? Future.value(reconciliation));
    return canApply() ? result : CallVideoSdpReconciliationOutcome.unreconciled;
  }

  @override
  Future<CallSessionDescription> createOffer(CallVideoNegotiation token) async {
    offers++;
    onOffer?.call();
    await offerGate?.future;
    return _description(CallSessionDescriptionType.offer);
  }

  @override
  Future<CallSessionDescription> createAnswer(
    CallVideoNegotiation token,
  ) async {
    answers++;
    return _description(CallSessionDescriptionType.answer);
  }

  @override
  Future<void> applyLocal(
    CallVideoNegotiation token,
    CallSessionDescription description,
  ) async {
    local.add(description);
    await localApplyGate?.future;
  }

  @override
  Future<void> applyRemote(
    CallVideoNegotiation token,
    CallSessionDescription description,
  ) async {
    remote.add(description);
    await remoteApplyGate?.future;
  }

  @override
  Future<void> commit(CallVideoNegotiation token) async {
    commits++;
    await commitGate?.future;
  }

  @override
  Future<bool> setLocalCamera(
    CallVideoNegotiation token,
    CallLocalCameraGrant grant,
  ) async {
    cameraStarts++;
    return true;
  }

  @override
  Future<bool> close() async {
    closed = true;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected video operation ${invocation.memberName}');
}

final class _Timers implements CallTimerScheduler {
  final List<_TimerHandle> handles = [];
  final List<Duration> delays = [];
  @override
  CallTimerHandle schedule(Duration delay, Future<void> Function() callback) {
    delays.add(delay);
    final handle = _TimerHandle(callback);
    handles.add(handle);
    return handle;
  }

  Future<void> fire() async {
    for (final handle in List<_TimerHandle>.of(handles)) {
      if (!handle.isActive) continue;
      handle.cancel();
      await handle.callback();
    }
  }
}

final class _TimerHandle implements CallTimerHandle {
  _TimerHandle(this.callback);
  final Future<void> Function() callback;
  @override
  bool isActive = true;
  @override
  void cancel() {
    isActive = false;
  }
}
