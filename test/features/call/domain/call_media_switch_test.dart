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

  test('callee requests but caller alone offers, and callee needs stable answer before commit', () {
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
    expect(_kinds(accept), isNot(contains(MediaSwitchEffectKind.createOffer)));
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
  });

  test('caller glare winner gets fresh prompt, abandoned consent cannot authorize it', () {
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
  });

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

  test('duplicates and mismatched bindings do not extend deadlines or repeat capture', () {
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
  });

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

  test('pending-offer abort rolls back, stable-answer abort repairs once without rollback', () {
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
      _kinds(stable.machine.abort(id: 'stable', baseRevision: 0, revision: 1)),
      isNot(contains(MediaSwitchEffectKind.repairAudio)),
    );
    expect(stable.machine.settledRevision, 1);
    expect(stable.machine.settledMedia, _audio);
  });

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

  test('local audio stop wins during upgrade and repair failure never restores camera', () {
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
  });

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

  test('reconnect replays terminal result before admission, stale reconciliation ignored', () {
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
  });

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
}
