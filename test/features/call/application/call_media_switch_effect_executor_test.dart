import 'dart:async';

import 'package:flutter_app/features/call/application/call_media_switch_effect_executor.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_media.dart';
import 'package:flutter_app/features/call/domain/call_media_switch.dart';
import 'package:flutter_test/flutter_test.dart';

const _audio = CallMediaKind.audio;
const _video = CallMediaKind.video;
const _offer = CallSessionDescription(
  type: CallSessionDescriptionType.offer,
  value: 'offer',
  fingerprint: 'fingerprint',
);
const _answer = CallSessionDescription(
  type: CallSessionDescriptionType.answer,
  value: 'answer',
  fingerprint: 'fingerprint',
);
final _call = CallId.parse('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');

void main() {
  test(
    'local stop remains available when transaction custody is full',
    () async {
      final r = _Rig(maximumTransactions: 1);
      await r.select();
      expect(
        r.owner.request(
          MediaSwitchRequest(
            id: 'stop',
            baseRevision: 0,
            target: _audio,
            requesterIsCaller: true,
            createdAtMs: r.host.now,
            deadlineMs: r.host.now + 30000,
          ),
        ),
        isTrue,
      );
      expect(r.owner.machine.phase, MediaSwitchPhase.aborted);
      expect(r.owner.machine.settledMedia, _audio);
      expect(r.video.events, contains('retire'));
      await r.owner.workSettled;
      expect(r.video.captureCalls, 0);
      expect(r.video.closeCalls, 0);
    },
  );

  test('disabled switching performs no authority or native work', () async {
    final r = _Rig(enabled: false);
    expect(r.owner.request(r.request()), isFalse);
    await r.owner.workSettled;
    expect(r.host.authorityCalls, 0);
    expect(r.video.events, isEmpty);
  });

  test(
    'local request is freshly admitted before any offer or camera',
    () async {
      final r = _Rig();
      expect(r.owner.request(r.request(), localGrant: r.grant), isTrue);
      await r.owner.workSettled;
      expect(r.host.authorityCalls, 1);
      expect(r.host.controls.single.kind, MediaSwitchEffectKind.sendRequest);
      expect(r.video.events, isEmpty);
      expect(r.owner.machine.phase, MediaSwitchPhase.decision);
    },
  );

  test('remote request cannot confer local camera consent', () async {
    final r = _Rig(caller: false);
    expect(r.owner.request(r.request(), localGrant: r.grant), isFalse);
    expect(r.owner.request(r.request()), isTrue);
    await r.owner.workSettled;
    expect(r.owner.machine.phase, MediaSwitchPhase.decision);
    expect(r.video.events, isEmpty);
  });

  test('fresh authority rejection never prompts or negotiates', () async {
    final r = _Rig();
    r.host.authorized = false;
    expect(r.owner.request(r.request(), localGrant: r.grant), isTrue);
    await r.owner.workSettled;
    expect(r.owner.machine.currentSwitchId, isNull);
    expect(r.host.controls, isEmpty);
    expect(r.video.events, isEmpty);
  });

  test('stale authority await cannot adopt expired request', () async {
    final r = _Rig();
    r.host.authorityGate = Completer<bool>();
    r.owner.request(r.request(), localGrant: r.grant);
    await _turn();
    r.host.now += 30000;
    r.host.authorityGate!.complete(true);
    await r.owner.workSettled;
    expect(r.owner.machine.currentSwitchId, isNull);
    expect(r.host.controls, isEmpty);
  });

  test(
    'caller offers on consent and opens video only after exact ACK',
    () async {
      final r = _Rig();
      await r.select();
      expect(r.video.events, ['begin:video', 'offer', 'local:offer']);
      expect(r.host.descriptions.single.repair, isFalse);
      expect(r.video.captureCalls, 0);
      expect(
        r.owner.receiveAck(id: 'switch', revision: 1, media: _video),
        isFalse,
      );
      expect(
        r.owner.receiveDescription(
          id: 'switch',
          negotiationId: r.token.negotiationId,
          revision: 1,
          media: _video,
          description: _answer,
        ),
        isTrue,
      );
      await r.owner.workSettled;
      expect(r.host.controls.last.kind, MediaSwitchEffectKind.sendCommit);
      expect(r.video.captureCalls, 0);
      expect(
        r.owner.receiveAck(id: 'switch', revision: 2, media: _video),
        isFalse,
      );
      expect(
        r.owner.receiveAck(id: 'switch', revision: 1, media: _video),
        isTrue,
      );
      await r.owner.workSettled;
      expect(r.video.events, contains('commit:video'));
      expect(r.video.captureCalls, 1);
      expect(r.owner.machine.settledMedia, _video);
    },
  );

  for (final succeeds in [true, false]) {
    test(
      'pending duplicate answer cannot commit before native ${succeeds ? 'success' : 'failure'}',
      () async {
        final r = _Rig();
        await r.select();
        final deadline = r.owner.machine.stageDeadlineMs;
        final applied = Completer<void>();
        r.video.applyGate = applied;
        expect(
          r.owner.receiveDescription(
            id: 'switch',
            negotiationId: r.token.negotiationId,
            revision: 1,
            media: _video,
            description: _answer,
          ),
          isTrue,
        );
        await _turn();
        try {
          expect(
            r.video.events.where((e) => e == 'remote:answer'),
            hasLength(1),
          );
          expect(
            r.owner.receiveDescription(
              id: 'switch',
              negotiationId: r.token.negotiationId,
              revision: 1,
              media: _video,
              description: _answer,
            ),
            isFalse,
          );
          await _turn();
          expect(
            r.host.controls.where(
              (e) => e.kind == MediaSwitchEffectKind.sendCommit,
            ),
            isEmpty,
          );
          expect(r.owner.machine.stageDeadlineMs, deadline);
          expect(
            r.owner.receiveAck(id: 'switch', revision: 1, media: _video),
            isFalse,
          );
          expect(r.video.captureCalls, 0);
        } finally {
          r.video.applyGate = null;
          if (succeeds) {
            applied.complete();
          } else {
            applied.completeError(StateError('native answer rejected'));
          }
          await r.owner.workSettled;
        }
        final commits = r.host.controls
            .where((e) => e.kind == MediaSwitchEffectKind.sendCommit)
            .toList();
        expect(commits, hasLength(succeeds ? 1 : 0));
        expect(r.video.events.where((e) => e == 'remote:answer'), hasLength(1));
        expect(r.video.captureCalls, 0);
        if (succeeds) {
          r.owner.receiveDescription(
            id: 'switch',
            negotiationId: r.token.negotiationId,
            revision: 1,
            media: _video,
            description: _answer,
          );
          await r.owner.workSettled;
          final replay = r.host.controls.last;
          expect(replay.kind, MediaSwitchEffectKind.replayRecorded);
          expect(replay.replayOf, MediaSwitchEffectKind.sendCommit);
          expect(replay.deadlineMs, commits.single.deadlineMs);
        } else {
          expect(r.owner.machine.phase, MediaSwitchPhase.aborted);
        }
      },
    );
  }

  test(
    'callee answers only selected offer and opens after commit custody',
    () async {
      final r = _Rig(caller: false);
      await r.select();
      expect(r.video.events, isEmpty);
      expect(
        r.owner.receiveDescription(
          id: 'switch',
          negotiationId: 'peer-negotiation',
          revision: 1,
          media: _video,
          description: _offer,
        ),
        isTrue,
      );
      await r.owner.workSettled;
      expect(r.video.events, [
        'begin:video',
        'remote:offer',
        'answer',
        'local:answer',
      ]);
      expect(r.video.captureCalls, 0);
      expect(
        r.owner.receiveCommit(id: 'switch', revision: 1, media: _video),
        isTrue,
      );
      await r.owner.workSettled;
      expect(r.host.controls.last.kind, MediaSwitchEffectKind.sendAck);
      expect(r.video.captureCalls, 1);
      expect(r.video.events.where((e) => e == 'offer'), isEmpty);
    },
  );

  test(
    'audio-only acceptance opens reception without a camera grant',
    () async {
      final r = _Rig(caller: false);
      await r.select(camera: false);
      r.owner.receiveDescription(
        id: 'switch',
        negotiationId: 'peer-negotiation',
        revision: 1,
        media: _video,
        description: _offer,
      );
      await r.owner.workSettled;
      r.owner.receiveCommit(id: 'switch', revision: 1, media: _video);
      await r.owner.workSettled;
      expect(r.video.events, contains('commit:video'));
      expect(r.video.captureCalls, 0);
    },
  );

  test(
    'late permission loss cannot turn committed consent into capture',
    () async {
      final r = _Rig();
      await r.select();
      r.owner.receiveDescription(
        id: 'switch',
        negotiationId: r.token.negotiationId,
        revision: 1,
        media: _video,
        description: _answer,
      );
      await r.owner.workSettled;
      r.permission = false;
      r.owner.receiveAck(id: 'switch', revision: 1, media: _video);
      await r.owner.workSettled;
      expect(r.video.captureCalls, 0);
      expect(r.owner.machine.settledMedia, _video);
    },
  );

  test('retired call after native commit await cannot capture', () async {
    final r = _Rig();
    await r.select();
    r.owner.receiveDescription(
      id: 'switch',
      negotiationId: r.token.negotiationId,
      revision: 1,
      media: _video,
      description: _answer,
    );
    await r.owner.workSettled;
    r.video.commitGate = Completer<void>();
    r.owner.receiveAck(id: 'switch', revision: 1, media: _video);
    await _turn();
    r.host.current = false;
    r.video.commitGate!.complete();
    await r.owner.workSettled;
    expect(r.video.captureCalls, 0);
  });

  test(
    'abort during pending native apply closes gates before that apply settles',
    () async {
      final r = _Rig();
      r.video.applyGate = Completer<void>();
      await r.requestAndConsent();
      await _turn();
      expect(r.video.events, contains('local:offer'));
      expect(r.owner.abort(id: 'switch', baseRevision: 0, revision: 1), isTrue);
      expect(r.video.events.last, 'retire');
      expect(r.owner.machine.videoGatesOpen, isFalse);
      expect(r.video.reconcileCalls, 0);
      r.video.applyGate!.complete();
      await r.owner.workSettled;
      expect(r.video.reconcileCalls, 1);
      expect(
        r.video.events.indexOf('reconcile'),
        greaterThan(r.video.events.indexOf('retire')),
      );
      expect(r.video.events.where((e) => e == 'begin:audio'), hasLength(1));
      expect(r.host.descriptions.single.repair, isTrue);
    },
  );

  test(
    'unreconciled native state never starts repair despite legacy rollback false',
    () async {
      final r = _Rig();
      await r.select();
      r.video.outcome = CallVideoSdpReconciliationOutcome.unreconciled;
      r.owner.abort(id: 'switch', baseRevision: 0, revision: 1);
      await r.owner.workSettled;
      expect(r.video.reconcileCalls, 1);
      expect(r.video.rollbackCalls, 0);
      expect(r.video.events, isNot(contains('begin:audio')));
      expect(r.owner.machine.switchingDisabled, isTrue);
      expect(r.owner.machine.settledMedia, _audio);
      expect(r.video.closeCalls, 0);
    },
  );

  for (final proof in [
    CallVideoSdpReconciliationOutcome.rolledBack,
    CallVideoSdpReconciliationOutcome.alreadyStable,
  ]) {
    test(
      'positive $proof permits one caller audio repair with fixed budget',
      () async {
        final r = _Rig();
        await r.select();
        r.video.outcome = proof;
        r.owner.abort(id: 'switch', baseRevision: 0, revision: 1);
        await r.owner.workSettled;
        expect(r.video.events.where((e) => e == 'begin:audio'), hasLength(1));
        final repair = r.host.descriptions.last;
        expect(repair.repair, isTrue);
        expect(repair.deadline, 16000);
        expect(
          r.owner.receiveDescription(
            id: 'switch',
            negotiationId: r.token.negotiationId,
            revision: 1,
            media: _audio,
            description: _answer,
            repair: true,
          ),
          isTrue,
        );
        await r.owner.workSettled;
        expect(r.video.events.last, 'commit:audio');
        expect(r.video.captureCalls, 0);
        expect(r.owner.machine.switchingDisabled, isFalse);
      },
    );
  }

  test('slow reconciliation consumes original abort-time budget', () async {
    final r = _Rig();
    await r.select();
    r.video.reconcileGate = Completer<CallVideoSdpReconciliationOutcome>();
    r.owner.abort(id: 'switch', baseRevision: 0, revision: 1);
    await _turn();
    r.host.now += 14000;
    r.video.reconcileGate!.complete(
      CallVideoSdpReconciliationOutcome.alreadyStable,
    );
    await r.owner.workSettled;
    expect(r.host.descriptions.last.deadline, 16000);
    r.host.now += 1000;
    r.owner.tick();
    expect(r.owner.machine.switchingDisabled, isTrue);
    expect(
      r.owner.receiveDescription(
        id: 'switch',
        negotiationId: r.token.negotiationId,
        revision: 1,
        media: _audio,
        description: _answer,
        repair: true,
      ),
      isFalse,
    );
    expect(r.video.captureCalls, 0);
  });

  test(
    'pending apply beyond repair deadline never starts replacement negotiation',
    () async {
      final r = _Rig();
      r.video.applyGate = Completer<void>();
      await r.requestAndConsent();
      await _turn();
      r.owner.abort(id: 'switch', baseRevision: 0, revision: 1);
      r.host.now += 15000;
      r.owner.tick();
      r.video.applyGate!.complete();
      await r.owner.workSettled;
      expect(r.video.events, isNot(contains('begin:audio')));
      expect(r.owner.machine.switchingDisabled, isTrue);
    },
  );

  test(
    'callee reconciles locally then waits for caller repair offer',
    () async {
      final r = _Rig(caller: false);
      await r.select();
      r.owner.receiveDescription(
        id: 'switch',
        negotiationId: 'video',
        revision: 1,
        media: _video,
        description: _offer,
      );
      await r.owner.workSettled;
      r.owner.abort(id: 'switch', baseRevision: 0, revision: 1, remote: true);
      await r.owner.workSettled;
      expect(r.video.reconcileCalls, 1);
      expect(r.video.events.where((e) => e == 'offer'), isEmpty);
      expect(
        r.owner.receiveDescription(
          id: 'switch',
          negotiationId: 'audio-repair',
          revision: 1,
          media: _audio,
          description: _offer,
          repair: true,
        ),
        isTrue,
      );
      await r.owner.workSettled;
      expect(r.host.descriptions.last.repair, isTrue);
      expect(r.video.events.last, 'commit:audio');
      expect(r.video.captureCalls, 0);
    },
  );

  test(
    'description replay reuses recorded answer without native apply or capture',
    () async {
      final r = _Rig(caller: false);
      await r.select();
      r.owner.receiveDescription(
        id: 'switch',
        negotiationId: 'video',
        revision: 1,
        media: _video,
        description: _offer,
      );
      await r.owner.workSettled;
      final native = List.of(r.video.events);
      r.owner.receiveDescription(
        id: 'switch',
        negotiationId: 'video',
        revision: 1,
        media: _video,
        description: _offer,
      );
      await r.owner.workSettled;
      expect(r.video.events, native);
      expect(r.host.descriptions, hasLength(2));
      expect(
        identical(
          r.host.descriptions.first.description,
          r.host.descriptions.last.description,
        ),
        isTrue,
      );
      expect(r.video.captureCalls, 0);
    },
  );

  test('terminal replay never reacquires a fresh local grant', () async {
    final r = _Rig();
    await r.select();
    r.owner.abort(id: 'switch', baseRevision: 0, revision: 1);
    await r.owner.workSettled;
    final native = List.of(r.video.events);
    r.owner.reconnect();
    await r.owner.workSettled;
    expect(r.video.events, native);
    expect(r.host.controls.last.kind, MediaSwitchEffectKind.replayRecorded);
    expect(r.host.controls.last.replayOf, MediaSwitchEffectKind.sendAbort);
    expect(r.video.captureCalls, 0);
  });

  test(
    'transport failure aborts optional video and leaves live audio owned',
    () async {
      final r = _Rig();
      await r.requestWork();
      r.host.delivered = false;
      r.respond();
      await r.owner.workSettled;
      expect(r.owner.machine.settledMedia, _audio);
      expect(r.owner.machine.videoGatesOpen, isFalse);
      expect(r.video.closeCalls, 0);
    },
  );

  test('native failure is observed and does not close audio', () async {
    final r = _Rig();
    r.video.failOffer = true;
    await r.select();
    expect(r.owner.machine.phase, MediaSwitchPhase.aborted);
    expect(r.video.closeCalls, 0);
    expect(r.video.captureCalls, 0);
  });

  test('bounded request custody reserves existing abort handling', () async {
    final r = _Rig(maximumTransactions: 1);
    await r.select();
    expect(r.owner.request(r.request(id: 'overflow')), isFalse);
    expect(r.owner.abort(id: 'switch', baseRevision: 0, revision: 1), isTrue);
    await r.owner.workSettled;
    expect(r.video.events, contains('retire'));
  });

  test(
    'terminal state fences pending lookup and does not await native work',
    () async {
      final r = _Rig();
      r.host.authorityGate = Completer<bool>();
      r.owner.request(r.request(), localGrant: r.grant);
      await _turn();
      r.owner.terminate();
      expect(r.owner.machine.terminal, isTrue);
      r.host.authorityGate!.complete(true);
      await r.owner.workSettled;
      expect(r.host.controls, isEmpty);
      expect(r.video.captureCalls, 0);
      expect(r.video.closeCalls, 0);
    },
  );
}

Future<void> _turn() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class _Rig {
  _Rig({
    this.caller = true,
    bool enabled = true,
    int maximumTransactions = 32,
  }) {
    owner = CallMediaSwitchEffectExecutor(
      host: host,
      localIsCaller: caller,
      initialMedia: _audio,
      nowMs: () => host.now,
      idSource: () => 'negotiation-${++ids}',
      videoEnabled: enabled,
      maximumTransactions: maximumTransactions,
    );
    addTearDown(owner.terminate);
  }
  final bool caller;
  final _Host host = _Host();
  late final CallMediaSwitchEffectExecutor owner;
  int ids = 0;
  bool permission = true;
  _Video get video => host.video;
  _Token get token => host.token!;
  CallLocalCameraGrant get grant => CallLocalCameraGrant(
    foregroundConsent: true,
    permissionGranted: true,
    videoAgreed: true,
    isCurrent: () => permission,
  );
  MediaSwitchRequest request({String id = 'switch'}) => MediaSwitchRequest(
    id: id,
    baseRevision: 0,
    target: _video,
    requesterIsCaller: true,
    createdAtMs: host.now,
    deadlineMs: host.now + 30000,
    camera: CallCameraState.on,
  );
  Future<void> requestAndConsent({bool camera = true}) async {
    await requestWork(camera: camera);
    respond(camera: camera);
  }

  Future<void> requestWork({bool camera = true}) async {
    expect(
      owner.request(request(), localGrant: caller && camera ? grant : null),
      isTrue,
    );
    await owner.workSettled;
  }

  bool respond({bool camera = true}) => owner.respond(
    id: 'switch',
    baseRevision: 0,
    fromCaller: false,
    response: MediaSwitchResponse.accept,
    camera: camera ? CallCameraState.on : CallCameraState.off,
    localGrant: !caller && camera ? grant : null,
  );
  Future<void> select({bool camera = true}) async {
    await requestAndConsent(camera: camera);
    await owner.workSettled;
  }
}

final class _Host implements CallMediaSwitchHost {
  @override
  bool current = true;
  int now = 1000;
  bool authorized = true;
  bool delivered = true;
  int authorityCalls = 0;
  Completer<bool>? authorityGate;
  final _Video video = _Video();
  _Token? token;
  Future<void> _tail = Future.value();
  final List<MediaSwitchEffect> controls = [];
  final List<({CallSessionDescription description, bool repair, int deadline})>
  descriptions = [];
  @override
  CallVideoSession get session => video;
  @override
  Future<void> serialize(Future<void> Function() job) {
    final result = _tail.then((_) => job());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  Future<bool> freshUpgradeAuthority() async {
    authorityCalls++;
    return await (authorityGate?.future ?? Future.value(authorized));
  }

  @override
  CallVideoNegotiation beginNegotiation({
    required String negotiationId,
    required int revision,
    required CallMediaKind media,
    required bool Function() canApply,
  }) {
    token =
        video.beginNegotiation(
              negotiationId: negotiationId,
              mediaRevision: revision,
              media: media,
              canApply: canApply,
            )
            as _Token;
    return token!;
  }

  @override
  void expectRemoteOffer() {}
  @override
  Future<void> remoteDescriptionApplied(CallVideoNegotiation token) async {}
  @override
  void localDescriptionAnnounced(CallVideoNegotiation token) {}
  @override
  Future<bool> closeVideo() => video.retireVideo();
  @override
  Future<bool> sendControl(
    MediaSwitchEffect effect, {
    required bool Function() canApply,
  }) async {
    if (!canApply()) return false;
    controls.add(effect);
    return delivered;
  }

  @override
  Future<bool> sendDescription({
    required String switchId,
    required CallVideoNegotiation token,
    required CallSessionDescription description,
    required bool repair,
    required int deadlineMs,
    required bool Function() canApply,
  }) async {
    if (!canApply()) return false;
    descriptions.add((
      description: description,
      repair: repair,
      deadline: deadlineMs,
    ));
    return delivered;
  }
}

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

final class _Video implements CallVideoSession, CallVideoSdpReconciler {
  @override
  CallId get callId => _call;
  @override
  bool get hasPendingCleanup => false;
  final List<String> events = [];
  int captureCalls = 0;
  int closeCalls = 0;
  int rollbackCalls = 0;
  int reconcileCalls = 0;
  bool failOffer = false;
  Completer<void>? applyGate;
  Completer<void>? commitGate;
  Completer<CallVideoSdpReconciliationOutcome>? reconcileGate;
  CallVideoSdpReconciliationOutcome outcome =
      CallVideoSdpReconciliationOutcome.alreadyStable;
  @override
  CallVideoNegotiation beginNegotiation({
    required String negotiationId,
    required int mediaRevision,
    required CallMediaKind media,
    required bool Function() canApply,
  }) {
    if (!canApply()) throw StateError('stale');
    events.add('begin:${media.name}');
    return _Token(negotiationId, mediaRevision, media);
  }

  @override
  Future<CallSessionDescription> createOffer(CallVideoNegotiation token) async {
    events.add('offer');
    if (failOffer) throw StateError('native');
    return _offer;
  }

  @override
  Future<CallSessionDescription> createAnswer(
    CallVideoNegotiation token,
  ) async {
    events.add('answer');
    return _answer;
  }

  @override
  Future<void> applyLocal(
    CallVideoNegotiation token,
    CallSessionDescription description,
  ) async {
    events.add('local:${description.type.name}');
    await (applyGate?.future ?? Future<void>.value());
  }

  @override
  Future<void> applyRemote(
    CallVideoNegotiation token,
    CallSessionDescription description,
  ) async {
    events.add('remote:${description.type.name}');
    await (applyGate?.future ?? Future<void>.value());
  }

  @override
  Future<void> commit(CallVideoNegotiation token) async {
    events.add('commit:${token.media.name}');
    await (commitGate?.future ?? Future<void>.value());
  }

  @override
  Future<bool> rollbackPending(CallVideoNegotiation token) async {
    rollbackCalls++;
    return false;
  }

  @override
  Future<CallVideoSdpReconciliationOutcome> reconcilePending(
    CallVideoNegotiation token, {
    required bool Function() canApply,
  }) async {
    events.add('reconcile');
    reconcileCalls++;
    final result = await (reconcileGate?.future ?? Future.value(outcome));
    return canApply() ? result : CallVideoSdpReconciliationOutcome.unreconciled;
  }

  @override
  Future<bool> setLocalCamera(
    CallVideoNegotiation token,
    CallLocalCameraGrant grant,
  ) async {
    captureCalls++;
    events.add('camera');
    return grant.isCurrent();
  }

  @override
  Future<bool> stopLocalCamera() async => true;
  @override
  Future<CallVideoView?> attachRenderer(
    CallVideoNegotiation token,
    CallVideoRendererSlot slot,
  ) async => null;
  @override
  Future<bool> detachRenderer(CallVideoRendererSlot slot) async => true;
  @override
  Future<bool> retireVideo() {
    events.add('retire');
    return Future.value(true);
  }

  @override
  Future<bool> retryCleanup() async => true;
  @override
  Future<bool> close() async {
    closeCalls++;
    return true;
  }
}
