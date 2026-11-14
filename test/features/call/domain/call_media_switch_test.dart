import 'package:flutter_app/features/call/domain/call_media.dart';
import 'package:flutter_app/features/call/domain/call_media_switch.dart';
import 'package:flutter_test/flutter_test.dart';

const _audio = CallMediaKind.audio;
const _video = CallMediaKind.video;
const _on = CallCameraState.on;
const _off = CallCameraState.off;

final class _Rig {
  _Rig({
    bool caller = true,
    CallMediaKind media = _audio,
    CallWireVersion version = CallWireVersion.v2,
    bool enabled = true,
    bool connected = true,
  }) {
    machine = CallMediaSwitchMachine(
      localIsCaller: caller,
      wireVersion: version,
      videoEnabled: enabled,
      connected: connected,
      settledMedia: media,
      nowMs: () => now,
    );
  }
  int now = 1000;
  late final CallMediaSwitchMachine machine;
  MediaSwitchRequest req(
    String id, {
    bool caller = true,
    CallMediaKind target = _video,
    int base = 0,
    int? created,
    int? deadline,
  }) => MediaSwitchRequest(
    id: id,
    baseRevision: base,
    target: target,
    requesterIsCaller: caller,
    createdAtMs: created ?? now,
    deadlineMs: deadline ?? now + 30000,
    camera: target == _video ? _on : _off,
  );
  void select(
    String id, {
    bool requester = true,
    CallMediaKind target = _video,
    int base = 0,
  }) {
    expect(
      machine
          .request(
            req(id, caller: requester, target: target, base: base),
            freshUpgradeAdmitted: true,
          )
          .accepted,
      isTrue,
    );
    if (target == _video || requester == machine.localIsCaller) {
      expect(
        machine
            .respond(
              id: id,
              baseRevision: base,
              fromCaller: !requester,
              response: MediaSwitchResponse.accept,
              camera: target == _video ? _on : _off,
            )
            .accepted,
        isTrue,
      );
    }
  }

  void offer(String id, {int revision = 1, CallMediaKind media = _video}) {
    expect(
      machine
          .descriptionApplied(
            id: id,
            revision: revision,
            media: media,
            description: MediaSwitchDescription.offer,
            local: machine.localIsCaller,
          )
          .accepted,
      isTrue,
    );
  }

  MediaSwitchDecision answer(
    String id, {
    int revision = 1,
    CallMediaKind media = _video,
  }) => machine.descriptionApplied(
    id: id,
    revision: revision,
    media: media,
    description: MediaSwitchDescription.answer,
    local: !machine.localIsCaller,
  );
  void settle(String id, {int revision = 1, CallMediaKind media = _video}) {
    offer(id, revision: revision, media: media);
    expect(answer(id, revision: revision, media: media).accepted, isTrue);
    final result = machine.localIsCaller
        ? machine.receiveAck(id: id, revision: revision, media: media)
        : machine.receiveCommit(id: id, revision: revision, media: media);
    expect(result.accepted, isTrue);
  }
}

List<MediaSwitchEffectKind> _kinds(MediaSwitchDecision decision) =>
    decision.effects.map((e) => e.kind).toList();

void main() {
  for (final caller in [true, false]) {
    test(
      'BL16-CANCEL old unselected peer ignores abort and retains original timeout caller=$caller',
      () {
        final requester = _Rig(caller: caller);
        final oldPeer = _Rig(caller: !caller);
        final request = requester.req('old-peer', caller: caller);
        requester.machine.request(request, freshUpgradeAdmitted: true);
        oldPeer.machine.request(request, freshUpgradeAdmitted: true);
        requester.machine.abort(id: request.id, baseRevision: 0, revision: 1);
        // Compatibility fixture: the old receiver rejects the unselected abort;
        // no cancellation or outcome witness is delivered to either machine.
        expect(oldPeer.machine.phase, MediaSwitchPhase.decision);
        oldPeer.now = request.createdAtMs + 15000;
        oldPeer.machine.tick();
        expect(oldPeer.machine.phase, MediaSwitchPhase.declined);
        requester.now = request.deadlineMs;
        requester.machine.tick();
        expect(requester.machine.switchingDisabled, isTrue);
        expect(requester.machine.settledRevision, 0);
        expect(oldPeer.machine.settledRevision, 0);
        expect(requester.machine.settledMedia, _audio);
        expect(requester.machine.videoGatesOpen, isFalse);
      },
    );
  }
  for (final requester in [true, false]) {
    test(
      'BL16-CANCEL unselected cancellation converges without revision caller=$requester',
      () {
        final local = _Rig(caller: requester);
        final peer = _Rig(caller: !requester);
        final request = local.req('cancel', caller: requester);
        local.machine.request(request, freshUpgradeAdmitted: true);
        peer.machine.request(request, freshUpgradeAdmitted: true);
        final cancel = local.machine.abort(
          id: 'cancel',
          baseRevision: 0,
          revision: 1,
        );
        expect(cancel.accepted, isTrue);
        final abort = cancel.effects.singleWhere(
          (e) => e.kind == MediaSwitchEffectKind.sendAbort,
        );
        expect(abort.media, _audio);
        expect(abort.revision, 1);
        expect(abort.abortReason, MediaSwitchAbortReason.cancelled);
        expect(abort.deadlineMs, request.deadlineMs);
        expect(local.machine.requiresReconciliation, isTrue);
        expect(local.machine.nextDeadlineMs, request.deadlineMs);
        final received = peer.machine.abort(
          id: 'cancel',
          baseRevision: 0,
          revision: 1,
          remote: true,
        );
        expect(received.accepted, isTrue);
        final decline = received.effects.singleWhere(
          (e) => e.kind == MediaSwitchEffectKind.sendResponse,
        );
        expect(decline.response, MediaSwitchResponse.decline);
        expect(
          local.machine
              .respond(
                id: 'cancel',
                baseRevision: 0,
                fromCaller: !requester,
                response: decline.response!,
              )
              .accepted,
          isTrue,
        );
        for (final rig in [local, peer]) {
          expect(rig.machine.settledRevision, 0);
          expect(rig.machine.settledMedia, _audio);
          expect(rig.machine.requiresReconciliation, isFalse);
          expect(rig.machine.videoGatesOpen, isFalse);
          expect(
            _kinds(rig.machine.request(request, freshUpgradeAdmitted: true)),
            isNot(contains(MediaSwitchEffectKind.prompt)),
          );
        }
        expect(
          local.machine
              .request(
                local.req('fresh', caller: requester),
                freshUpgradeAdmitted: true,
              )
              .accepted,
          isTrue,
        );
        final duplicate = peer.machine.abort(
          id: 'cancel',
          baseRevision: 0,
          revision: 1,
          remote: true,
        );
        expect(
          duplicate.effects
              .where((e) => e.kind == MediaSwitchEffectKind.replayRecorded)
              .single
              .response,
          MediaSwitchResponse.decline,
        );
      },
    );

    test(
      'BL16-CANCEL late accept selects cancelled audio repair caller=$requester',
      () {
        final r = _Rig(caller: requester);
        final request = r.req('cross', caller: requester);
        r.machine.request(request, freshUpgradeAdmitted: true);
        r.machine.abort(id: 'cross', baseRevision: 0, revision: 1);
        final result = r.machine.respond(
          id: 'cross',
          baseRevision: 0,
          fromCaller: !requester,
          response: MediaSwitchResponse.accept,
          camera: _on,
        );
        expect(result.accepted, isTrue);
        expect(
          _kinds(result),
          isNot(contains(MediaSwitchEffectKind.createOffer)),
        );
        expect(
          _kinds(result),
          isNot(contains(MediaSwitchEffectKind.openVideo)),
        );
        expect(
          _kinds(result),
          contains(
            requester
                ? MediaSwitchEffectKind.repairAudio
                : MediaSwitchEffectKind.awaitAudioRepair,
          ),
        );
        expect(r.machine.settledRevision, 1);
        expect(r.machine.settledMedia, _audio);
        expect(r.machine.videoGatesOpen, isFalse);
        expect(
          r.machine
              .respond(
                id: 'cross',
                baseRevision: 0,
                fromCaller: !requester,
                response: MediaSwitchResponse.accept,
                camera: _on,
              )
              .effects,
          isEmpty,
        );
      },
    );

    for (final stage in ['accepted', 'offer', 'answer', 'committed']) {
      test(
        'BL16-CANCEL responder preserves original accept at $stage caller=$requester',
        () {
          final r = _Rig(caller: !requester);
          r.machine.request(
            r.req('cross', caller: requester),
            freshUpgradeAdmitted: true,
          );
          final accepted = r.machine.respond(
            id: 'cross',
            baseRevision: 0,
            fromCaller: !requester,
            response: MediaSwitchResponse.accept,
            camera: _on,
          );
          final original = accepted.effects.singleWhere(
            (e) => e.kind == MediaSwitchEffectKind.sendResponse,
          );
          if (stage != 'accepted') r.offer('cross');
          if (stage == 'answer' || stage == 'committed') r.answer('cross');
          if (stage == 'committed') {
            if (r.machine.localIsCaller) {
              r.machine.receiveAck(id: 'cross', revision: 1, media: _video);
            } else {
              r.machine.receiveCommit(id: 'cross', revision: 1, media: _video);
            }
          }
          final result = r.machine.abort(
            id: 'cross',
            baseRevision: 0,
            revision: 1,
            remote: true,
          );
          final replay = result.effects
              .where(
                (e) =>
                    e.kind == MediaSwitchEffectKind.replayRecorded &&
                    e.replayOf == MediaSwitchEffectKind.sendResponse,
              )
              .single;
          expect(replay.response, MediaSwitchResponse.accept);
          expect(replay.camera, original.camera);
          expect(replay.deadlineMs, original.deadlineMs);
          expect(r.machine.settledRevision, 1);
          expect(r.machine.settledMedia, _audio);
          expect(r.machine.videoGatesOpen, isFalse);
        },
      );
    }
  }

  test(
    'BL16-CANCEL transport custody cannot resolve unknown selection or renew cutoff',
    () {
      final r = _Rig();
      final request = r.req('lost');
      r.machine.request(request, freshUpgradeAdmitted: true);
      r.machine.abort(id: 'lost', baseRevision: 0, revision: 1);
      r.machine.reconciliationCompleted(id: 'lost', delivered: true);
      expect(r.machine.requiresReconciliation, isTrue);
      expect(r.machine.nextDeadlineMs, request.deadlineMs);
      expect(
        r.machine
            .request(r.req('blocked'), freshUpgradeAdmitted: true)
            .accepted,
        isFalse,
      );
      r.now = request.deadlineMs;
      r.machine.tick();
      expect(r.machine.switchingDisabled, isTrue);
      expect(r.machine.settledRevision, 0);
      expect(r.machine.settledMedia, _audio);
      expect(
        r.machine
            .respond(
              id: 'lost',
              baseRevision: 0,
              fromCaller: false,
              response: MediaSwitchResponse.accept,
            )
            .accepted,
        isFalse,
      );
      expect(r.machine.terminate().accepted, isTrue);
    },
  );

  test('BL16-CANCEL authenticated abort before request suppresses prompt', () {
    final r = _Rig(caller: false);
    expect(
      r.machine
          .abort(id: 'early', baseRevision: 0, revision: 1, remote: true)
          .accepted,
      isTrue,
    );
    expect(r.machine.currentRequest, isNull);
    final result = r.machine.request(
      r.req('early'),
      freshUpgradeAdmitted: true,
    );
    expect(_kinds(result), isNot(contains(MediaSwitchEffectKind.prompt)));
    expect(
      result.effects
          .singleWhere((e) => e.kind == MediaSwitchEffectKind.sendResponse)
          .response,
      MediaSwitchResponse.decline,
    );
    expect(r.machine.settledRevision, 0);
    expect(r.machine.videoGatesOpen, isFalse);
  });

  test(
    'BL16-CANCEL wrong requester revision and unknown successor cannot mutate pending request',
    () {
      final r = _Rig();
      r.machine.request(r.req('owned'), freshUpgradeAdmitted: true);
      for (final wrong in ['role', 'base', 'revision', 'id']) {
        final result = r.machine.abort(
          id: wrong == 'id' ? 'other' : 'owned',
          baseRevision: wrong == 'base' ? 1 : 0,
          revision: wrong == 'revision' ? 2 : 1,
          remote: wrong == 'role',
        );
        expect(result.accepted, isFalse);
        expect(r.machine.currentSwitchId, 'owned');
        expect(r.machine.phase, MediaSwitchPhase.decision);
      }
    },
  );

  test(
    'BL16-CANCEL contradictory witness disables optional switching without revision mutation',
    () {
      final r = _Rig();
      r.machine.request(r.req('conflict'), freshUpgradeAdmitted: true);
      r.machine.abort(id: 'conflict', baseRevision: 0, revision: 1);
      expect(
        r.machine
            .respond(
              id: 'conflict',
              baseRevision: 0,
              fromCaller: false,
              response: MediaSwitchResponse.decline,
            )
            .accepted,
        isTrue,
      );
      r.machine.respond(
        id: 'conflict',
        baseRevision: 0,
        fromCaller: false,
        response: MediaSwitchResponse.accept,
      );
      expect(r.machine.switchingDisabled, isTrue);
      expect(r.machine.settledRevision, 0);
      expect(r.machine.videoGatesOpen, isFalse);
    },
  );

  for (final requester in [true, false]) {
    test('U3j-S exposes the immutable current request caller=$requester', () {
      final rig = _Rig();
      expect(rig.machine.currentRequest, isNull);
      final request = rig.req('current-request', caller: requester);
      expect(
        rig.machine.request(request, freshUpgradeAdmitted: true).accepted,
        isTrue,
      );
      expect(rig.machine.currentRequest, same(request));
      expect(rig.machine.currentRequest!.requesterIsCaller, requester);
      expect(rig.machine.currentRequest!.target, _video);
      expect(rig.machine.currentRequest!.baseRevision, 0);
      expect(rig.machine.currentRequest!.deadlineMs, request.deadlineMs);
      expect(rig.machine.settledMedia, _audio);
      expect(rig.machine.videoGatesOpen, isFalse);
    });
  }

  test('U3j-S disabled machine does not expose a refused request', () {
    final rig = _Rig(enabled: false);
    rig.machine.request(rig.req('disabled'), freshUpgradeAdmitted: true);
    expect(rig.machine.currentRequest, isNull);
    expect(rig.machine.videoGatesOpen, isFalse);
  });

  for (final caller in [true, false]) {
    test(
      'pending native offer abort arms original repair budget caller=$caller',
      () {
        final rig = _Rig(caller: caller);
        rig.select('pending-native');
        expect(
          rig.machine
              .descriptionStarted(
                id: 'pending-native',
                revision: 1,
                media: _video,
                description: MediaSwitchDescription.offer,
                local: caller,
              )
              .accepted,
          isTrue,
        );
        final abort = rig.machine.abort(
          id: 'pending-native',
          baseRevision: 0,
          revision: 1,
          remote: !caller,
        );
        final rollback = abort.effects.singleWhere(
          (e) => e.kind == MediaSwitchEffectKind.rollbackOffer,
        );
        expect(rollback.deadlineMs, 16000);
        expect(
          _kinds(abort),
          isNot(contains(MediaSwitchEffectKind.repairAudio)),
        );
        expect(rig.machine.videoGatesOpen, isFalse);
        rig.now += 14000;
        expect(
          rig.machine
              .descriptionApplied(
                id: 'pending-native',
                revision: 1,
                media: _video,
                description: MediaSwitchDescription.offer,
                local: caller,
              )
              .accepted,
          isFalse,
        );
        final proof = rig.machine.rollbackCompleted(
          id: 'pending-native',
          success: true,
        );
        final repair = proof.effects.singleWhere(
          (e) =>
              e.kind ==
              (caller
                  ? MediaSwitchEffectKind.repairAudio
                  : MediaSwitchEffectKind.awaitAudioRepair),
        );
        expect(repair.deadlineMs, 16000);
        rig.now += 1000;
        expect(
          _kinds(rig.machine.tick()),
          contains(MediaSwitchEffectKind.disableSwitching),
        );
        expect(
          rig.machine
              .repairCompleted(id: 'pending-native', success: true)
              .accepted,
          isFalse,
        );
      },
    );
  }

  test('native answer in flight needs positive reconciliation after abort', () {
    final rig = _Rig();
    rig.select('pending-answer');
    rig.offer('pending-answer');
    expect(
      rig.machine
          .descriptionStarted(
            id: 'pending-answer',
            revision: 1,
            media: _video,
            description: MediaSwitchDescription.answer,
            local: false,
          )
          .accepted,
      isTrue,
    );
    final abort = rig.machine.abort(
      id: 'pending-answer',
      baseRevision: 0,
      revision: 1,
    );
    expect(_kinds(abort), contains(MediaSwitchEffectKind.rollbackOffer));
    expect(
      rig.machine.repairCompleted(id: 'pending-answer', success: true).accepted,
      isFalse,
    );
    expect(
      _kinds(
        rig.machine.rollbackCompleted(id: 'pending-answer', success: false),
      ),
      contains(MediaSwitchEffectKind.disableSwitching),
    );
    expect(rig.machine.settledMedia, _audio);
  });

  test(
    'description start requires exact selected role and cannot duplicate',
    () {
      final rig = _Rig();
      rig.select('bound');
      for (final candidate in [
        (id: 'foreign', revision: 1, local: true),
        (id: 'bound', revision: 2, local: true),
        (id: 'bound', revision: 1, local: false),
      ]) {
        expect(
          rig.machine
              .descriptionStarted(
                id: candidate.id,
                revision: candidate.revision,
                media: _video,
                description: MediaSwitchDescription.offer,
                local: candidate.local,
              )
              .accepted,
          isFalse,
        );
      }
      expect(
        rig.machine
            .descriptionStarted(
              id: 'bound',
              revision: 1,
              media: _video,
              description: MediaSwitchDescription.answer,
              local: false,
            )
            .accepted,
        isFalse,
      );
      expect(
        rig.machine
            .descriptionStarted(
              id: 'bound',
              revision: 1,
              media: _video,
              description: MediaSwitchDescription.offer,
              local: true,
            )
            .accepted,
        isTrue,
      );
      expect(
        rig.machine
            .descriptionStarted(
              id: 'bound',
              revision: 1,
              media: _video,
              description: MediaSwitchDescription.offer,
              local: true,
            )
            .accepted,
        isFalse,
      );
      rig.offer('bound');
      expect(
        rig.machine
            .descriptionStarted(
              id: 'bound',
              revision: 1,
              media: _video,
              description: MediaSwitchDescription.answer,
              local: false,
            )
            .accepted,
        isTrue,
      );
    },
  );

  test(
    'pending native start cannot revive an aborted or terminal transaction',
    () {
      final rig = _Rig();
      rig.select('retired');
      rig.machine.abort(id: 'retired', baseRevision: 0, revision: 1);
      expect(
        rig.machine
            .descriptionStarted(
              id: 'retired',
              revision: 1,
              media: _video,
              description: MediaSwitchDescription.offer,
              local: true,
            )
            .accepted,
        isFalse,
      );
      rig.machine.terminate();
      expect(
        rig.machine
            .descriptionStarted(
              id: 'retired',
              revision: 1,
              media: _video,
              description: MediaSwitchDescription.offer,
              local: true,
            )
            .accepted,
        isFalse,
      );
    },
  );

  test('expired pending native reconciliation never renews repair budget', () {
    final rig = _Rig();
    rig.select('expired-native');
    expect(
      rig.machine
          .descriptionStarted(
            id: 'expired-native',
            revision: 1,
            media: _video,
            description: MediaSwitchDescription.offer,
            local: true,
          )
          .accepted,
      isTrue,
    );
    rig.machine.abort(id: 'expired-native', baseRevision: 0, revision: 1);
    rig.now += 15000;
    final late = rig.machine.rollbackCompleted(
      id: 'expired-native',
      success: true,
    );
    expect(late.accepted, isFalse);
    expect(_kinds(late), contains(MediaSwitchEffectKind.disableSwitching));
    expect(_kinds(late), isNot(contains(MediaSwitchEffectKind.repairAudio)));
    expect(rig.machine.switchingDisabled, isTrue);
  });

  test('only connected enabled v2 sessions admit fresh video requests', () {
    for (final rig in [
      _Rig(version: CallWireVersion.v1),
      _Rig(enabled: false),
      _Rig(connected: false),
    ]) {
      expect(
        rig.machine
            .request(rig.req('blocked'), freshUpgradeAdmitted: true)
            .accepted,
        isFalse,
      );
    }
    final rig = _Rig();
    expect(rig.machine.request(rig.req('no-capability')).accepted, isFalse);
    expect(
      rig.machine
          .request(rig.req('fresh'), freshUpgradeAdmitted: true)
          .accepted,
      isTrue,
    );
    expect(rig.machine.videoGatesOpen, isFalse);
  });

  test(
    'initial Audio only needs new remote consent and caller waits for ACK',
    () {
      final rig = _Rig();
      rig.machine.request(rig.req('upgrade'), freshUpgradeAdmitted: true);
      expect(
        rig.machine
            .descriptionApplied(
              id: 'upgrade',
              revision: 1,
              media: _video,
              description: MediaSwitchDescription.offer,
              local: true,
            )
            .accepted,
        isFalse,
      );
      final accepted = rig.machine.respond(
        id: 'upgrade',
        baseRevision: 0,
        fromCaller: false,
        response: MediaSwitchResponse.accept,
        camera: _off,
      );
      expect(_kinds(accepted), contains(MediaSwitchEffectKind.createOffer));
      rig.offer('upgrade');
      expect(
        _kinds(rig.answer('upgrade')),
        contains(MediaSwitchEffectKind.sendCommit),
      );
      expect(rig.machine.videoGatesOpen, isFalse);
      expect(
        rig.machine
            .receiveAck(id: 'wrong', revision: 1, media: _video)
            .accepted,
        isFalse,
      );
      rig.machine.receiveAck(id: 'upgrade', revision: 1, media: _video);
      expect(rig.machine.videoGatesOpen, isTrue);
      expect(rig.machine.settledRevision, 1);
    },
  );

  test(
    'callee requests but caller alone offers, and callee needs stable answer before commit',
    () {
      final rig = _Rig(caller: false);
      rig.machine.request(
        rig.req('callee', caller: false),
        freshUpgradeAdmitted: true,
      );
      final accept = rig.machine.respond(
        id: 'callee',
        baseRevision: 0,
        fromCaller: true,
        response: MediaSwitchResponse.accept,
      );
      expect(
        _kinds(accept),
        isNot(contains(MediaSwitchEffectKind.createOffer)),
      );
      expect(
        rig.machine
            .receiveCommit(id: 'callee', revision: 1, media: _video)
            .accepted,
        isFalse,
      );
      rig.offer('callee');
      rig.answer('callee');
      final commit = rig.machine.receiveCommit(
        id: 'callee',
        revision: 1,
        media: _video,
      );
      expect(_kinds(commit), contains(MediaSwitchEffectKind.sendAck));
      expect(rig.machine.videoGatesOpen, isTrue);
    },
  );

  test(
    'caller glare winner gets fresh prompt, abandoned consent cannot authorize it',
    () {
      final rig = _Rig(caller: false);
      rig.machine.request(
        rig.req('loser', caller: false),
        freshUpgradeAdmitted: true,
      );
      final winner = rig.machine.request(
        rig.req('winner'),
        freshUpgradeAdmitted: true,
      );
      expect(_kinds(winner), contains(MediaSwitchEffectKind.prompt));
      expect(_kinds(winner), isNot(contains(MediaSwitchEffectKind.sendAbort)));
      expect(rig.machine.currentSwitchId, 'winner');
      expect(rig.machine.selectedSwitchId, isNull);
      expect(
        rig.machine
            .respond(
              id: 'loser',
              baseRevision: 0,
              fromCaller: true,
              response: MediaSwitchResponse.accept,
            )
            .accepted,
        isFalse,
      );
      expect(
        rig.machine
            .descriptionApplied(
              id: 'winner',
              revision: 1,
              media: _video,
              description: MediaSwitchDescription.offer,
              local: false,
            )
            .accepted,
        isFalse,
      );
      expect(
        rig.machine
            .respond(
              id: 'winner',
              baseRevision: 0,
              fromCaller: false,
              response: MediaSwitchResponse.decline,
            )
            .accepted,
        isTrue,
      );
      expect(rig.machine.settledMedia, _audio);
      expect(rig.machine.settledRevision, 0);
    },
  );

  test('selected transaction is busy regardless of requester role', () {
    final rig = _Rig(caller: false);
    rig.select('selected', requester: false);
    final busy = rig.machine.request(
      rig.req('later'),
      freshUpgradeAdmitted: true,
    );
    expect(busy.accepted, isFalse);
    expect(busy.effects.single.response, MediaSwitchResponse.busy);
    expect(rig.machine.selectedSwitchId, 'selected');
  });

  test(
    'duplicates and mismatched bindings do not extend deadlines or repeat capture',
    () {
      final rig = _Rig();
      final request = rig.req('id', deadline: 9000);
      rig.machine.request(request, freshUpgradeAdmitted: true);
      final deadline = rig.machine.stageDeadlineMs;
      rig.now += 1000;
      expect(
        _kinds(rig.machine.request(request, freshUpgradeAdmitted: true)),
        isNot(contains(MediaSwitchEffectKind.prompt)),
      );
      expect(rig.machine.stageDeadlineMs, deadline);
      rig.machine.respond(
        id: 'id',
        baseRevision: 0,
        fromCaller: false,
        response: MediaSwitchResponse.accept,
      );
      final selectedDeadline = rig.machine.stageDeadlineMs;
      rig.now += 1000;
      rig.machine.respond(
        id: 'id',
        baseRevision: 0,
        fromCaller: false,
        response: MediaSwitchResponse.accept,
      );
      expect(rig.machine.stageDeadlineMs, selectedDeadline);
      expect(
        rig.machine
            .descriptionApplied(
              id: 'id',
              revision: 2,
              media: _video,
              description: MediaSwitchDescription.offer,
              local: true,
            )
            .accepted,
        isFalse,
      );
      expect(
        rig.machine
            .descriptionApplied(
              id: 'id',
              revision: 1,
              media: _audio,
              description: MediaSwitchDescription.offer,
              local: true,
            )
            .accepted,
        isFalse,
      );
    },
  );

  test(
    'decision expiry is exact, does not consume revision and cannot be renewed',
    () {
      final rig = _Rig();
      final request = rig.req('late');
      rig.machine.request(request, freshUpgradeAdmitted: true);
      expect(rig.machine.stageDeadlineMs, 16000);
      rig.now = 16000;
      expect(
        rig.machine
            .respond(
              id: 'late',
              baseRevision: 0,
              fromCaller: false,
              response: MediaSwitchResponse.accept,
            )
            .accepted,
        isFalse,
      );
      expect(rig.machine.settledRevision, 0);
      expect(
        rig.machine.request(request, freshUpgradeAdmitted: true).accepted,
        isFalse,
      );
    },
  );

  test('SDP and commit budgets respect immutable authenticated deadline', () {
    final rig = _Rig();
    rig.machine.request(
      rig.req('bounded', deadline: 18000),
      freshUpgradeAdmitted: true,
    );
    rig.now = 15000;
    rig.machine.respond(
      id: 'bounded',
      baseRevision: 0,
      fromCaller: false,
      response: MediaSwitchResponse.accept,
    );
    expect(rig.machine.stageDeadlineMs, 18000);
    rig.offer('bounded');
    rig.now = 17000;
    rig.answer('bounded');
    expect(rig.machine.stageDeadlineMs, 18000);
    rig.now = 18000;
    expect(
      _kinds(rig.machine.tick()),
      contains(MediaSwitchEffectKind.sendAbort),
    );
    expect(rig.machine.settledMedia, _audio);
    expect(
      rig.machine
          .receiveAck(id: 'bounded', revision: 1, media: _video)
          .accepted,
      isFalse,
    );
  });

  test(
    'pending-offer abort rolls back, stable-answer abort repairs once without rollback',
    () {
      final pending = _Rig();
      pending.select('pending');
      pending.offer('pending');
      final rollback = pending.machine.abort(
        id: 'pending',
        baseRevision: 0,
        revision: 1,
      );
      expect(_kinds(rollback), contains(MediaSwitchEffectKind.rollbackOffer));
      final stable = _Rig();
      stable.select('stable');
      stable.offer('stable');
      stable.answer('stable');
      final repair = stable.machine.abort(
        id: 'stable',
        baseRevision: 0,
        revision: 1,
      );
      expect(_kinds(repair), contains(MediaSwitchEffectKind.repairAudio));
      expect(
        _kinds(repair),
        isNot(contains(MediaSwitchEffectKind.rollbackOffer)),
      );
      expect(
        _kinds(
          stable.machine.abort(id: 'stable', baseRevision: 0, revision: 1),
        ),
        isNot(contains(MediaSwitchEffectKind.repairAudio)),
      );
      expect(stable.machine.settledRevision, 1);
      expect(stable.machine.settledMedia, _audio);
    },
  );

  test('abort overrides commit and duplicate ACK never reopens video', () {
    final rig = _Rig();
    rig.select('old');
    rig.settle('old');
    expect(rig.machine.videoGatesOpen, isTrue);
    rig.machine.abort(id: 'old', baseRevision: 0, revision: 1, remote: true);
    expect(rig.machine.videoGatesOpen, isFalse);
    expect(
      rig.machine.receiveAck(id: 'old', revision: 1, media: _video).accepted,
      isFalse,
    );
    expect(rig.machine.settledMedia, _audio);
  });

  test('late abort still dominates while newer request is only unselected', () {
    final rig = _Rig();
    rig.select('old');
    rig.settle('old');
    rig.machine.request(rig.req('new', target: _audio, base: 1));
    rig.machine.abort(id: 'old', baseRevision: 0, revision: 1, remote: true);
    expect(rig.machine.settledMedia, _audio);
    expect(
      rig.machine
          .respond(
            id: 'new',
            baseRevision: 1,
            fromCaller: false,
            response: MediaSwitchResponse.accept,
          )
          .accepted,
      isFalse,
    );
  });

  test('older abort cannot tear down newer selected or settled revision', () {
    final rig = _Rig();
    rig.select('old');
    rig.settle('old');
    rig.select('new', target: _audio, base: 1);
    expect(
      rig.machine
          .abort(id: 'old', baseRevision: 0, revision: 1, remote: true)
          .accepted,
      isFalse,
    );
    rig.settle('new', revision: 2, media: _audio);
    expect(rig.machine.settledRevision, 2);
    expect(
      rig.machine
          .abort(id: 'old', baseRevision: 0, revision: 1, remote: true)
          .accepted,
      isFalse,
    );
  });

  test(
    'local audio stop wins during upgrade and repair failure never restores camera',
    () {
      final rig = _Rig();
      rig.select('upgrade');
      rig.offer('upgrade');
      rig.answer('upgrade');
      final stop = rig.machine.request(rig.req('stop', target: _audio));
      expect(_kinds(stop), contains(MediaSwitchEffectKind.closeVideo));
      expect(rig.machine.videoGatesOpen, isFalse);
      rig.machine.repairCompleted(id: 'upgrade', success: false);
      expect(rig.machine.switchingDisabled, isTrue);
      expect(rig.machine.settledMedia, _audio);
      expect(
        rig.machine
            .receiveAck(id: 'upgrade', revision: 1, media: _video)
            .accepted,
        isFalse,
      );
    },
  );

  test(
    'repair deadline is bounded and stale completion cannot unlock switching',
    () {
      final rig = _Rig();
      rig.select('repair');
      rig.offer('repair');
      rig.answer('repair');
      rig.machine.abort(id: 'repair', baseRevision: 0, revision: 1);
      rig.now += 15000;
      expect(
        _kinds(rig.machine.tick()),
        contains(MediaSwitchEffectKind.disableSwitching),
      );
      rig.machine.repairCompleted(id: 'repair', success: true);
      expect(rig.machine.switchingDisabled, isTrue);
    },
  );

  test(
    'reconnect replays terminal result before admission, stale reconciliation ignored',
    () {
      final rig = _Rig();
      rig.select('aborted');
      rig.offer('aborted');
      rig.answer('aborted');
      rig.machine.abort(id: 'aborted', baseRevision: 0, revision: 1);
      rig.machine.repairCompleted(id: 'aborted', success: true);
      expect(
        rig.machine
            .request(rig.req('blocked', base: 1), freshUpgradeAdmitted: true)
            .accepted,
        isFalse,
      );
      expect(
        _kinds(rig.machine.reconnect()),
        contains(MediaSwitchEffectKind.replayRecorded),
      );
      expect(
        rig.machine
            .reconciliationCompleted(id: 'stale', delivered: true)
            .accepted,
        isFalse,
      );
      expect(rig.machine.requiresReconciliation, isTrue);
      rig.machine.reconciliationCompleted(id: 'aborted', delivered: true);
      expect(
        rig.machine
            .request(rig.req('fresh', base: 1), freshUpgradeAdmitted: true)
            .accepted,
        isTrue,
      );
    },
  );

  test('terminal state dominates all late work', () {
    final rig = _Rig();
    rig.select('terminal');
    rig.offer('terminal');
    rig.answer('terminal');
    rig.machine.terminate();
    expect(rig.machine.terminal, isTrue);
    expect(rig.machine.videoGatesOpen, isFalse);
    expect(
      rig.machine
          .receiveAck(id: 'terminal', revision: 1, media: _video)
          .accepted,
      isFalse,
    );
    expect(
      rig.machine.request(rig.req('late'), freshUpgradeAdmitted: true).accepted,
      isFalse,
    );
    expect(
      rig.machine.repairCompleted(id: 'terminal', success: true).accepted,
      isFalse,
    );
  });
  test(
    'pending rollback finishes before one repair with the original repair deadline',
    () {
      final rig = _Rig();
      rig.select('pending');
      rig.offer('pending');
      final abort = rig.machine.abort(
        id: 'pending',
        baseRevision: 0,
        revision: 1,
      );
      expect(_kinds(abort), contains(MediaSwitchEffectKind.rollbackOffer));
      expect(_kinds(abort), isNot(contains(MediaSwitchEffectKind.repairAudio)));
      rig.now += 14000;
      final repair = rig.machine.rollbackCompleted(
        id: 'pending',
        success: true,
      );
      expect(_kinds(repair), contains(MediaSwitchEffectKind.repairAudio));
      expect(
        _kinds(rig.machine.rollbackCompleted(id: 'pending', success: true)),
        isEmpty,
      );
      rig.now += 1000;
      expect(
        _kinds(rig.machine.tick()),
        contains(MediaSwitchEffectKind.disableSwitching),
      );
      expect(rig.machine.settledMedia, _audio);
    },
  );

  test(
    'callee rolls back locally then awaits caller repair without creating an offer',
    () {
      final rig = _Rig(caller: false);
      rig.select('callee');
      rig.offer('callee');
      rig.machine.abort(
        id: 'callee',
        baseRevision: 0,
        revision: 1,
        remote: true,
      );
      final repaired = rig.machine.rollbackCompleted(
        id: 'callee',
        success: true,
      );
      expect(
        _kinds(repaired),
        contains(MediaSwitchEffectKind.awaitAudioRepair),
      );
      expect(
        _kinds(repaired),
        isNot(contains(MediaSwitchEffectKind.repairAudio)),
      );
      expect(
        _kinds(repaired),
        isNot(contains(MediaSwitchEffectKind.createOffer)),
      );
    },
  );

  test('duplicate commit replays ACK without another gate opening', () {
    final rig = _Rig(caller: false);
    rig.select('id');
    rig.settle('id');
    final duplicate = rig.machine.receiveCommit(
      id: 'id',
      revision: 1,
      media: _video,
    );
    expect(_kinds(duplicate), [MediaSwitchEffectKind.replayRecorded]);
    expect(duplicate.effects.single.replayOf, MediaSwitchEffectKind.sendAck);
    expect(rig.machine.settledRevision, 1);
  });

  test(
    'repeated uncertain terminal delivery settles audio and disables switching',
    () {
      final rig = _Rig();
      rig.select('uncertain');
      rig.settle('uncertain');
      rig.machine.reconnect();
      rig.machine.reconciliationCompleted(id: 'uncertain', delivered: false);
      rig.machine.reconnect();
      final failed = rig.machine.reconciliationCompleted(
        id: 'uncertain',
        delivered: false,
      );
      expect(_kinds(failed), contains(MediaSwitchEffectKind.disableSwitching));
      expect(rig.machine.switchingDisabled, isTrue);
      expect(rig.machine.settledMedia, _audio);
      expect(rig.machine.videoGatesOpen, isFalse);
    },
  );

  test(
    'an independent negotiation rejects a new request without queueing consent',
    () {
      final rig = _Rig(caller: false);
      final busy = rig.machine.request(
        rig.req('busy'),
        freshUpgradeAdmitted: true,
        negotiationBusy: true,
      );
      expect(busy.accepted, isFalse);
      expect(busy.effects.single.response, MediaSwitchResponse.busy);
      expect(rig.machine.currentSwitchId, isNull);
      expect(
        rig.machine
            .respond(
              id: 'busy',
              baseRevision: 0,
              fromCaller: false,
              response: MediaSwitchResponse.accept,
            )
            .accepted,
        isFalse,
      );
    },
  );
  for (final deliveryFirst in [true, false]) {
    test(
      'abort delivery and repair independently unblock fresh consent (delivery first=$deliveryFirst)',
      () {
        final rig = _Rig();
        rig.select('aborted');
        rig.offer('aborted');
        rig.answer('aborted');
        rig.machine.abort(id: 'aborted', baseRevision: 0, revision: 1);
        MediaSwitchDecision delivered() =>
            rig.machine.reconciliationCompleted(id: 'aborted', delivered: true);
        MediaSwitchDecision repaired() =>
            rig.machine.repairCompleted(id: 'aborted', success: true);
        expect((deliveryFirst ? delivered() : repaired()).accepted, isTrue);
        expect(
          rig.machine
              .request(
                rig.req('too-early', base: 1),
                freshUpgradeAdmitted: true,
              )
              .accepted,
          isFalse,
        );
        expect((deliveryFirst ? repaired() : delivered()).accepted, isTrue);
        expect(rig.machine.requiresReconciliation, isFalse);
        final fresh = rig.machine.request(
          rig.req('fresh-consent', base: 1),
          freshUpgradeAdmitted: true,
        );
        expect(fresh.accepted, isTrue);
        expect(rig.machine.phase, MediaSwitchPhase.decision);
        expect(rig.machine.videoGatesOpen, isFalse);
        expect(
          rig.machine
              .reconciliationCompleted(id: 'aborted', delivered: true)
              .accepted,
          isFalse,
        );
      },
    );
  }
}
