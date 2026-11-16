import 'package:flutter_app/features/call/domain/call_media.dart';
import 'package:flutter_app/features/call/domain/call_media_switch.dart';
import 'package:flutter_test/flutter_test.dart';

class _Rig {
  _Rig({bool caller = true}) {
    machine = CallMediaSwitchMachine(
      localIsCaller: caller,
      wireVersion: CallWireVersion.v2,
      videoEnabled: true,
      connected: true,
      settledMedia: CallMediaKind.audio,
      nowMs: () => now,
    );
  }
  int now = 1000;
  late final CallMediaSwitchMachine machine;

  MediaSwitchRequest request(
    String id, {
    bool caller = true,
    int base = 0,
    CallMediaKind target = CallMediaKind.video,
  }) => MediaSwitchRequest(
    id: id,
    baseRevision: base,
    target: target,
    requesterIsCaller: caller,
    createdAtMs: now,
    deadlineMs: now + 30000,
  );

  void admit(
    String id, {
    bool caller = true,
    int base = 0,
    CallMediaKind target = CallMediaKind.video,
  }) {
    expect(
      machine
          .request(
            request(id, caller: caller, base: base, target: target),
            freshUpgradeAdmitted: true,
          )
          .accepted,
      isTrue,
    );
  }

  MediaSwitchDecision respond(
    String id,
    MediaSwitchResponse response, {
    bool fromCaller = false,
    int base = 0,
  }) => machine.respond(
    id: id,
    baseRevision: base,
    fromCaller: fromCaller,
    response: response,
  );

  void select(
    String id, {
    int base = 0,
    CallMediaKind target = CallMediaKind.video,
  }) {
    admit(id, base: base, target: target);
    expect(
      respond(id, MediaSwitchResponse.accept, base: base).accepted,
      isTrue,
    );
  }

  void settle(
    String id, {
    int revision = 1,
    CallMediaKind media = CallMediaKind.video,
  }) {
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
    expect(
      machine
          .descriptionApplied(
            id: id,
            revision: revision,
            media: media,
            description: MediaSwitchDescription.answer,
            local: !machine.localIsCaller,
          )
          .accepted,
      isTrue,
    );
    final result = machine.localIsCaller
        ? machine.receiveAck(id: id, revision: revision, media: media)
        : machine.receiveCommit(id: id, revision: revision, media: media);
    expect(result.accepted, isTrue);
  }
}

MediaSwitchOutcome _outcome(
  _Rig r,
  String id,
  MediaSwitchOutcomeKind kind, {
  int base = 0,
}) {
  final outcome = r.machine.lastOutcome;
  expect(
    outcome,
    isNotNull,
    reason: 'The validated current transition must expose its exact outcome.',
  );
  expect(outcome!.switchId, id);
  expect(outcome.baseRevision, base);
  expect(outcome.kind, kind);
  return outcome;
}

void main() {
  for (final caller in [true, false]) {
    test('VUI3b genuine decline records exact identity caller=$caller', () {
      final r = _Rig(caller: caller);
      r.admit('declined');
      expect(
        r.respond('declined', MediaSwitchResponse.decline).accepted,
        isTrue,
      );
      final first = _outcome(r, 'declined', MediaSwitchOutcomeKind.declined);
      expect(
        r.respond('declined', MediaSwitchResponse.decline).accepted,
        isFalse,
      );
      expect(r.machine.lastOutcome, same(first));
      r.machine.request(r.machine.currentRequest!, freshUpgradeAdmitted: true);
      expect(r.machine.lastOutcome, same(first));
      expect(r.machine.settledMedia, CallMediaKind.audio);
      expect(r.machine.videoGatesOpen, isFalse);
    });
  }

  for (final response in [
    MediaSwitchResponse.busy,
    MediaSwitchResponse.stale,
    MediaSwitchResponse.unsupported,
    MediaSwitchResponse.superseded,
  ]) {
    test('VUI3b $response is not a user decline', () {
      final r = _Rig();
      r.admit('request');
      expect(r.respond('request', response).accepted, isTrue);
      expect(r.machine.phase, MediaSwitchPhase.declined);
      expect(r.machine.lastOutcome, isNull);
    });
  }

  for (final wrong in ['sender', 'base', 'id']) {
    test('VUI3b invalid decline $wrong cannot report an outcome', () {
      final r = _Rig();
      r.admit('current');
      expect(
        r
            .respond(
              wrong == 'id' ? 'other' : 'current',
              MediaSwitchResponse.decline,
              fromCaller: wrong == 'sender',
              base: wrong == 'base' ? 1 : 0,
            )
            .accepted,
        isFalse,
      );
      expect(r.machine.lastOutcome, isNull);
      expect(r.machine.phase, MediaSwitchPhase.decision);
    });
  }

  for (final lateAction in ['tick', 'accept', 'cancel']) {
    test('VUI3b unanswered expiry survives $lateAction at deadline', () {
      final r = _Rig();
      r.admit('expired');
      r.now = r.machine.stageDeadlineMs!;
      if (lateAction == 'tick') {
        r.machine.tick();
      } else if (lateAction == 'accept') {
        expect(
          r.respond('expired', MediaSwitchResponse.accept).accepted,
          isFalse,
        );
      } else {
        expect(
          r.machine.abort(id: 'expired', baseRevision: 0, revision: 1).accepted,
          isFalse,
        );
      }
      final first = _outcome(r, 'expired', MediaSwitchOutcomeKind.expired);
      r.machine.tick();
      expect(r.machine.lastOutcome, same(first));
      expect(r.machine.settledRevision, 0);
      expect(r.machine.videoGatesOpen, isFalse);
    });
  }

  test(
    'VUI3b predeadline acceptance and selected timeout are not request expiry',
    () {
      final r = _Rig();
      r.admit('selected');
      r.now = r.machine.stageDeadlineMs! - 1;
      expect(
        r.respond('selected', MediaSwitchResponse.accept).accepted,
        isTrue,
      );
      expect(r.machine.lastOutcome, isNull);
      r.now = r.machine.stageDeadlineMs!;
      r.machine.tick();
      expect(r.machine.phase, MediaSwitchPhase.aborted);
      expect(r.machine.lastOutcome, isNull);
    },
  );

  for (final reason in [
    MediaSwitchAbortReason.timeout,
    MediaSwitchAbortReason.permission,
    MediaSwitchAbortReason.negotiation,
    MediaSwitchAbortReason.transport,
    MediaSwitchAbortReason.superseded,
  ]) {
    test(
      'VUI3b early abort $reason does not fabricate expiry or cancellation',
      () {
        final r = _Rig();
        r.admit('request');
        expect(
          r.machine
              .abort(
                id: 'request',
                baseRevision: 0,
                revision: 1,
                reason: reason,
              )
              .accepted,
          isTrue,
        );
        expect(r.machine.lastOutcome, isNull);
      },
    );
  }

  for (final remote in [false, true]) {
    test(
      'VUI3b current requester cancellation remote=$remote records once',
      () {
        final r = _Rig(caller: !remote);
        r.admit('cancelled');
        expect(
          r.machine
              .abort(
                id: 'cancelled',
                baseRevision: 0,
                revision: 1,
                remote: remote,
              )
              .accepted,
          isTrue,
        );
        final first = _outcome(
          r,
          'cancelled',
          MediaSwitchOutcomeKind.cancelled,
        );
        expect(
          r.machine
              .abort(
                id: 'cancelled',
                baseRevision: 0,
                revision: 1,
                remote: remote,
              )
              .accepted,
          isFalse,
        );
        expect(r.machine.lastOutcome, same(first));
      },
    );
  }

  for (final witness in [
    MediaSwitchResponse.decline,
    MediaSwitchResponse.accept,
  ]) {
    test('VUI3b cancellation witness $witness retains original result', () {
      final r = _Rig();
      r.admit('cancelled');
      expect(
        r.machine.abort(id: 'cancelled', baseRevision: 0, revision: 1).accepted,
        isTrue,
      );
      final first = _outcome(r, 'cancelled', MediaSwitchOutcomeKind.cancelled);
      expect(r.respond('cancelled', witness).accepted, isTrue);
      expect(r.machine.lastOutcome, same(first));
      r.respond('cancelled', witness);
      expect(r.machine.lastOutcome, same(first));
    });
  }

  test(
    'VUI3b local audio stop cancels the current unanswered video request',
    () {
      final r = _Rig();
      r.admit('video');
      expect(
        r.machine
            .request(r.request('stop', target: CallMediaKind.audio))
            .accepted,
        isTrue,
      );
      _outcome(r, 'video', MediaSwitchOutcomeKind.cancelled);
      expect(r.machine.settledMedia, CallMediaKind.audio);
    },
  );

  test(
    'VUI3b early cancellation custody and synthetic decline produce no notice',
    () {
      final r = _Rig(caller: false);
      expect(
        r.machine
            .abort(id: 'early', baseRevision: 0, revision: 1, remote: true)
            .accepted,
        isTrue,
      );
      expect(r.machine.lastOutcome, isNull);
      final result = r.machine.request(
        r.request('early'),
        freshUpgradeAdmitted: true,
      );
      expect(result.accepted, isTrue);
      expect(
        result.effects
            .where((e) => e.kind == MediaSwitchEffectKind.sendResponse)
            .single
            .response,
        MediaSwitchResponse.decline,
      );
      expect(r.machine.lastOutcome, isNull);
    },
  );

  test('VUI3b actual new admission clears outcome while unrelated rejection does not', () {
    final r = _Rig();
    r.admit('old');
    expect(r.respond('old', MediaSwitchResponse.decline).accepted, isTrue);
    final first = _outcome(r, 'old', MediaSwitchOutcomeKind.declined);
    expect(
      r.machine
          .request(
            r.request('invalid-base', base: 9),
            freshUpgradeAdmitted: true,
          )
          .accepted,
      isFalse,
    );
    expect(r.machine.lastOutcome, same(first));
    r.admit('new');
    expect(r.machine.lastOutcome, isNull);
    expect(r.respond('old', MediaSwitchResponse.decline).accepted, isFalse);
    expect(r.machine.lastOutcome, isNull);
    expect(r.machine.currentSwitchId, 'new');
    expect(r.respond('new', MediaSwitchResponse.accept).accepted, isTrue);
    expect(r.machine.lastOutcome, isNull);
    r.settle('new');
    expect(r.machine.lastOutcome, isNull);
  });

  test('VUI3b old response and abort cannot overwrite a newer result', () {
    final r = _Rig();
    r.admit('old');
    expect(r.respond('old', MediaSwitchResponse.decline).accepted, isTrue);
    _outcome(r, 'old', MediaSwitchOutcomeKind.declined);
    r.admit('new');
    expect(
      r.machine.abort(id: 'new', baseRevision: 0, revision: 1).accepted,
      isTrue,
    );
    final current = _outcome(r, 'new', MediaSwitchOutcomeKind.cancelled);
    expect(r.respond('old', MediaSwitchResponse.decline).accepted, isFalse);
    expect(
      r.machine.abort(id: 'old', baseRevision: 0, revision: 1).accepted,
      isFalse,
    );
    expect(r.machine.lastOutcome, same(current));
  });

  for (final wrong in ['sender', 'base', 'revision']) {
    test('VUI3b invalid cancellation $wrong cannot report an outcome', () {
      final r = _Rig();
      r.admit('current');
      expect(
        r.machine
            .abort(
              id: 'current',
              baseRevision: wrong == 'base' ? 1 : 0,
              revision: wrong == 'revision' ? 2 : 1,
              remote: wrong == 'sender',
            )
            .accepted,
        isFalse,
      );
      expect(r.machine.lastOutcome, isNull);
      expect(r.machine.currentSwitchId, 'current');
      expect(r.machine.phase, MediaSwitchPhase.decision);
    });
  }

  test('VUI3b termination clears a real retained outcome', () {
    final r = _Rig();
    r.admit('old');
    r.respond('old', MediaSwitchResponse.decline);
    _outcome(r, 'old', MediaSwitchOutcomeKind.declined);
    r.machine.terminate();
    expect(r.machine.lastOutcome, isNull);
    expect(r.machine.terminal, isTrue);
  });

  test(
    'VUI3b caller glare winner is current and abandoned request cannot report',
    () {
      final r = _Rig();
      r.admit('callee', caller: false);
      r.admit('caller');
      expect(r.machine.currentSwitchId, 'caller');
      expect(r.machine.lastOutcome, isNull);
      expect(
        r
            .respond('callee', MediaSwitchResponse.decline, fromCaller: true)
            .accepted,
        isFalse,
      );
      expect(r.machine.lastOutcome, isNull);
      expect(r.respond('caller', MediaSwitchResponse.decline).accepted, isTrue);
      _outcome(r, 'caller', MediaSwitchOutcomeKind.declined);
    },
  );

  test('VUI3b selected current cancellation qualifies before success', () {
    final r = _Rig();
    r.select('current');
    expect(
      r.machine.abort(id: 'current', baseRevision: 0, revision: 1).accepted,
      isTrue,
    );
    _outcome(r, 'current', MediaSwitchOutcomeKind.cancelled);
  });

  test(
    'VUI3b old selected abort over successor does not gain outcome authority',
    () {
      final r = _Rig();
      r.select('established');
      r.settle('established');
      r.admit('audio-successor', base: 1, target: CallMediaKind.audio);
      expect(r.machine.currentSwitchId, 'audio-successor');
      // _abort may select the old transaction for repair; that is not a current
      // request cancellation and must not synthesize a user-facing result.
      r.machine.abort(
        id: 'established',
        baseRevision: 0,
        revision: 1,
        remote: true,
      );
      expect(r.machine.lastOutcome, isNull);
    },
  );
}
