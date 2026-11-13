import 'dart:async';

import 'call_coordinator.dart';
import '../domain/call_engine.dart';
import '../domain/call_media.dart';
import '../domain/call_media_switch.dart';

/// The existing v2 negotiation owner supplies its single native queue, bound
/// session and immutable signaling custody. The switch executor owns no engine
/// listener or independent SDP queue.
abstract interface class CallMediaSwitchHost {
  bool get current;
  CallVideoSession get session;
  Future<void> serialize(Future<void> Function() job);
  Future<bool> freshUpgradeAuthority();
  CallVideoNegotiation beginNegotiation({
    required String negotiationId,
    required int revision,
    required CallMediaKind media,
    required bool Function() canApply,
  });
  void expectRemoteOffer();
  Future<void> remoteDescriptionApplied(CallVideoNegotiation token);
  void localDescriptionAnnounced(CallVideoNegotiation token);
  Future<bool> closeVideo();
  Future<bool> sendControl(
    MediaSwitchEffect effect, {
    required bool Function() canApply,
  });
  Future<bool> sendDescription({
    required String switchId,
    required CallVideoNegotiation token,
    required CallSessionDescription description,
    required bool repair,
    required int deadlineMs,
    required bool Function() canApply,
  });
}

/// Executes the pure switch machine with fresh local consent and the host's
/// existing SDP queue. Native failures can disable switching but never end the
/// live audio call. Native reconciliation and repair share one abort-time budget.
final class CallMediaSwitchEffectExecutor {
  CallMediaSwitchEffectExecutor({
    required this.host,
    required this.localIsCaller,
    required CallMediaKind initialMedia,
    int settledRevision = 0,
    required this.nowMs,
    required this.idSource,
    this.videoEnabled = false,
    this.maximumTransactions = 32,
    this.onChanged,
    this.timerScheduler = const DartCallTimerScheduler(),
  }) : machine = CallMediaSwitchMachine(
         localIsCaller: localIsCaller,
         wireVersion: CallWireVersion.v2,
         videoEnabled: videoEnabled,
         connected: true,
         settledMedia: initialMedia,
         nowMs: nowMs,
       ) {
    if (maximumTransactions < 1 || maximumTransactions > 128) {
      throw ArgumentError.value(maximumTransactions, 'maximumTransactions');
    }
  }

  final CallMediaSwitchHost host;
  final bool localIsCaller;
  final int Function() nowMs;
  final String Function() idSource;
  final bool videoEnabled;
  final int maximumTransactions;
  final void Function()? onChanged;
  final CallTimerScheduler timerScheduler;
  final CallMediaSwitchMachine machine;
  final Map<String, _SwitchWork> _transactions = {};
  final Set<Future<void>> _pending = {};
  CallTimerHandle? _timer;
  int? _timerDeadline;
  bool _closed = false;

  bool get _current => !_closed && videoEnabled && host.current;
  _SwitchWork? get _selected => _transactions[machine.selectedSwitchId];

  /// Cancels unfinished work while retaining this call's machine and tombstones.
  void beginRecovery({
    required int reconnectGeneration,
    required int deadlineMs,
    required bool Function() canApply,
  }) {}

  Future<void> get workSettled async {
    while (_pending.isNotEmpty) {
      await Future.wait<void>(_pending.toList(growable: false));
    }
  }

  bool request(
    MediaSwitchRequest request, {
    CallLocalCameraGrant? localGrant,
    bool Function()? canApply,
  }) {
    if (!_current || !_allowed(canApply)) return false;
    final local = request.requesterIsCaller == localIsCaller;
    if ((!local && localGrant != null) ||
        (local &&
            request.camera == CallCameraState.on &&
            !_grantCurrent(localGrant)) ||
        (request.target == CallMediaKind.audio && localGrant != null)) {
      return false;
    }
    final known = _transactions[request.id];
    if (known != null) {
      if (!_sameRequest(known.request, request) || !known.admitted) {
        return false;
      }
      _apply(machine.request(known.request, freshUpgradeAdmitted: true));
      return false;
    }
    if (_transactions.length >= maximumTransactions &&
        local &&
        request.target == CallMediaKind.audio) {
      final selected = _selected;
      _track(host.closeVideo());
      return selected != null &&
          abort(
            id: selected.request.id,
            baseRevision: selected.request.baseRevision,
            revision: selected.revision,
          );
    }
    if (_transactions.length >= maximumTransactions ||
        request.deadlineMs <= nowMs() ||
        request.createdAtMs + 30000 <= nowMs()) {
      return false;
    }
    final work = _SwitchWork(request, localGrant, canApply);
    _transactions[request.id] = work;
    if (request.target == CallMediaKind.audio) {
      if (local) _track(host.closeVideo());
      work.admitted = true;
      final decision = machine.request(request);
      _apply(decision);
      if (decision.accepted &&
          !localIsCaller &&
          machine.selectedSwitchId == request.id) {
        host.expectRemoteOffer();
      }
      return decision.accepted;
    }
    _track(
      Future<void>.sync(() async {
        final admitted = await host.freshUpgradeAuthority();
        if (!_current ||
            !admitted ||
            !_allowed(work.canApply) ||
            nowMs() >= request.deadlineMs ||
            nowMs() >= request.createdAtMs + 30000) {
          work.grant = null;
          return;
        }
        work.admitted = true;
        _apply(machine.request(request, freshUpgradeAdmitted: true));
      }),
      onFailure: () {
        work.grant = null;
      },
    );
    return true;
  }

  bool respond({
    required String id,
    required int baseRevision,
    required bool fromCaller,
    required MediaSwitchResponse response,
    CallCameraState camera = CallCameraState.off,
    CallLocalCameraGrant? localGrant,
    bool Function()? canApply,
  }) {
    if (!_current || !_allowed(canApply)) return false;
    final work = _transactions[id];
    if (work == null || !work.admitted) return false;
    final local = fromCaller == localIsCaller;
    if ((!local && localGrant != null) ||
        (local && camera == CallCameraState.on && !_grantCurrent(localGrant))) {
      return false;
    }
    final decision = machine.respond(
      id: id,
      baseRevision: baseRevision,
      fromCaller: fromCaller,
      response: response,
      camera: camera,
    );
    if (decision.accepted && local) {
      work.grant =
          response == MediaSwitchResponse.accept && camera == CallCameraState.on
          ? localGrant
          : null;
    }
    if (decision.accepted &&
        response == MediaSwitchResponse.accept &&
        !localIsCaller) {
      host.expectRemoteOffer();
    }
    _apply(decision);
    return decision.accepted;
  }

  bool receiveDescription({
    required String id,
    required String negotiationId,
    required int revision,
    required CallMediaKind media,
    required CallSessionDescription description,
    bool repair = false,
    bool Function()? canApply,
  }) {
    tick();
    final work = _transactions[id];
    final offer = description.type == CallSessionDescriptionType.offer;
    if (!_current ||
        !_allowed(canApply) ||
        work == null ||
        !identical(work, _selected) ||
        revision != work.revision ||
        offer == localIsCaller ||
        description.value.isEmpty ||
        (description.fingerprint?.isEmpty ?? true) ||
        (repair
            ? media != CallMediaKind.audio ||
                  (!_repairCurrent(work) && !_settledAudio(work))
            : media != work.request.target || !_live(work))) {
      return false;
    }
    final existing = repair ? work.remoteRepair : work.remoteSwitch;
    if (existing != null) {
      if (existing.negotiationId != negotiationId ||
          !_sameDescription(existing.description, description)) {
        return false;
      }
      // Admission owns the description while native application is pending.
      // Only successful application permits replaying its recorded result.
      if (!existing.applied) return false;
      if (!repair) {
        _apply(
          machine.descriptionApplied(
            id: id,
            revision: revision,
            media: media,
            description: offer
                ? MediaSwitchDescription.offer
                : MediaSwitchDescription.answer,
            local: false,
          ),
        );
      } else if (!localIsCaller &&
          work.localRepair != null &&
          work.token != null) {
        _track(_sendDescription(work, work.localRepair!, repair: true));
      }
      return false;
    }
    if ((repair && work.repairComplete) ||
        (!offer && work.token?.negotiationId != negotiationId) ||
        (offer && !repair && work.token != null) ||
        (offer && repair && work.token?.negotiationId == negotiationId)) {
      return false;
    }
    final remote = _RemoteSwitchDescription(
      negotiationId,
      description,
      canApply,
    );
    if (repair) {
      work.remoteRepair = remote;
    } else {
      work.remoteSwitch = remote;
    }
    _queue(work, () async {
      if (!_allowed(remote.canApply)) throw const _SwitchRetired();
      if (repair && !work.reconciled) {
        throw StateError('native state unreconciled');
      }
      if (offer) {
        if (!repair && !await host.freshUpgradeAuthority()) {
          throw StateError('authority');
        }
        _check(work, repair: repair);
        if (!_allowed(remote.canApply)) throw const _SwitchRetired();
        _begin(work, negotiationId, repair: repair);
      }
      final token = work.token!;
      if (!repair) _descriptionStarted(work, description, local: false);
      await host.session.applyRemote(token, description);
      _check(work, repair: repair);
      if (!_allowed(remote.canApply)) throw const _SwitchRetired();
      await host.remoteDescriptionApplied(token);
      _check(work, repair: repair);
      remote.applied = true;
      if (repair) {
        if (offer) {
          await _answer(work, repair: true);
        } else {
          await _completeRepair(work);
        }
      } else {
        _apply(
          machine.descriptionApplied(
            id: id,
            revision: revision,
            media: media,
            description: offer
                ? MediaSwitchDescription.offer
                : MediaSwitchDescription.answer,
            local: false,
          ),
        );
      }
    }, repair: repair);
    return true;
  }

  bool receiveCommit({
    required String id,
    required int revision,
    required CallMediaKind media,
  }) {
    if (!_current) return false;
    final work = _transactions[id];
    final deadline = machine.stageDeadlineMs;
    final decision = machine.receiveCommit(
      id: id,
      revision: revision,
      media: media,
    );
    if (decision.accepted && work != null) work.commitDeadline = deadline;
    _apply(decision);
    return decision.accepted;
  }

  bool receiveAck({
    required String id,
    required int revision,
    required CallMediaKind media,
  }) {
    if (!_current) return false;
    final work = _transactions[id];
    final deadline = machine.stageDeadlineMs;
    final decision = machine.receiveAck(
      id: id,
      revision: revision,
      media: media,
    );
    if (decision.accepted && work != null) work.commitDeadline = deadline;
    _apply(decision);
    return decision.accepted;
  }

  bool abort({
    required String id,
    required int baseRevision,
    required int revision,
    bool remote = false,
    MediaSwitchAbortReason reason = MediaSwitchAbortReason.cancelled,
  }) {
    if (!_current) return false;
    final decision = machine.abort(
      id: id,
      baseRevision: baseRevision,
      revision: revision,
      remote: remote,
      reason: reason,
    );
    _apply(decision);
    return decision.accepted;
  }

  void tick() {
    if (_closed) return;
    _apply(machine.tick());
    final selected = _selected;
    if (machine.phase == MediaSwitchPhase.committed &&
        selected != null &&
        selected.settlementScheduled &&
        !selected.committed &&
        selected.commitDeadline != null &&
        nowMs() >= selected.commitDeadline!) {
      abort(
        id: selected.request.id,
        baseRevision: selected.request.baseRevision,
        revision: selected.revision,
        reason: MediaSwitchAbortReason.timeout,
      );
    }
  }

  /// Optional ICE/signaling failures cannot tear down the audio coordinator.
  void failOptionalMedia() {
    final work = _selected;
    if (work == null || !_current) return;
    if (_repairCurrent(work)) {
      _repairFailed(work);
    } else {
      abort(
        id: work.request.id,
        baseRevision: work.request.baseRevision,
        revision: work.revision,
        reason: MediaSwitchAbortReason.transport,
      );
    }
  }

  void reconnect() {
    if (_current) _apply(machine.reconnect());
  }

  void terminate() {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    _timer = null;
    _timerDeadline = null;
    for (final work in _transactions.values) {
      work.grant = null;
    }
    _apply(machine.terminate());
    _track(host.closeVideo());
  }

  void _apply(MediaSwitchDecision decision) {
    for (final effect in decision.effects) {
      final work = _transactions[effect.switchId];
      if (work == null) continue;
      switch (effect.kind) {
        case MediaSwitchEffectKind.closeVideo:
          if (machine.phase == MediaSwitchPhase.committed &&
              machine.settledMedia == CallMediaKind.audio &&
              work.token != null) {
            _track(host.session.stopLocalCamera());
            _settle(work);
          } else {
            work.grant = null;
            work.commitDeadline = null;
            _track(host.closeVideo());
          }
        case MediaSwitchEffectKind.discardCapture:
          work.grant = null;
        case MediaSwitchEffectKind.prompt:
          break;
        case MediaSwitchEffectKind.createOffer:
          _offer(work);
        case MediaSwitchEffectKind.createAnswer:
          _queue(work, () => _answer(work));
        case MediaSwitchEffectKind.sendRequest:
        case MediaSwitchEffectKind.sendResponse:
        case MediaSwitchEffectKind.sendCommit:
        case MediaSwitchEffectKind.sendAck:
        case MediaSwitchEffectKind.sendAbort:
        case MediaSwitchEffectKind.replayRecorded:
          if (effect.kind == MediaSwitchEffectKind.replayRecorded &&
              effect.replayOf == MediaSwitchEffectKind.createAnswer) {
            final answer = work.localSwitch;
            if (answer != null) _track(_sendDescription(work, answer));
          } else {
            final sending = _sendControl(work, effect);
            if (effect.kind == MediaSwitchEffectKind.sendAck) {
              work.ackDelivery = sending;
            }
            _track(sending);
          }
        case MediaSwitchEffectKind.rollbackOffer:
        case MediaSwitchEffectKind.repairAudio:
        case MediaSwitchEffectKind.awaitAudioRepair:
          work.repairDeadline ??= effect.deadlineMs;
          work.grant = null;
          if (work.reconciled) {
            _startRepair(work);
          } else {
            _reconcile(
              work,
              rollback: effect.kind == MediaSwitchEffectKind.rollbackOffer,
            );
          }
        case MediaSwitchEffectKind.openVideo:
          _settle(work);
        case MediaSwitchEffectKind.disableSwitching:
          work.grant = null;
          _track(host.closeVideo());
      }
    }
    _scheduleTick();
    try {
      onChanged?.call();
    } catch (_) {
      /* An observer has no media authority. */
    }
  }

  void _offer(_SwitchWork work, {bool repair = false}) {
    _queue(work, () async {
      if (!repair && !await host.freshUpgradeAuthority()) {
        throw StateError('authority');
      }
      _check(work, repair: repair);
      _begin(work, idSource(), repair: repair);
      final token = work.token!;
      final offer = await host.session.createOffer(token);
      _check(work, repair: repair);
      _validateDescription(offer, CallSessionDescriptionType.offer);
      if (!repair) _descriptionStarted(work, offer, local: true);
      await host.session.applyLocal(token, offer);
      _check(work, repair: repair);
      if (!repair) {
        _apply(
          machine.descriptionApplied(
            id: work.request.id,
            revision: work.revision,
            media: work.request.target,
            description: MediaSwitchDescription.offer,
            local: true,
          ),
        );
      }
      if (repair) {
        work.localRepair = offer;
      } else {
        work.localSwitch = offer;
      }
      if (!await _sendDescription(work, offer, repair: repair)) {
        throw StateError('transport');
      }
      _check(work, repair: repair);
      host.localDescriptionAnnounced(token);
    }, repair: repair);
  }

  Future<void> _answer(_SwitchWork work, {bool repair = false}) async {
    _check(work, repair: repair);
    final token = work.token!;
    final answer = await host.session.createAnswer(token);
    _check(work, repair: repair);
    _validateDescription(answer, CallSessionDescriptionType.answer);
    if (!repair) _descriptionStarted(work, answer, local: true);
    await host.session.applyLocal(token, answer);
    _check(work, repair: repair);
    if (!repair) {
      _apply(
        machine.descriptionApplied(
          id: work.request.id,
          revision: work.revision,
          media: work.request.target,
          description: MediaSwitchDescription.answer,
          local: true,
        ),
      );
    }
    if (repair) {
      work.localRepair = answer;
    } else {
      work.localSwitch = answer;
    }
    if (!await _sendDescription(work, answer, repair: repair)) {
      throw StateError('transport');
    }
    _check(work, repair: repair);
    host.localDescriptionAnnounced(token);
    if (repair) await _completeRepair(work);
  }

  void _begin(_SwitchWork work, String negotiationId, {required bool repair}) {
    work.token = host.beginNegotiation(
      negotiationId: negotiationId,
      revision: work.revision,
      media: repair ? CallMediaKind.audio : work.request.target,
      canApply: () =>
          repair ? _repairCurrent(work) || _settledAudio(work) : _live(work),
    );
  }

  void _descriptionStarted(
    _SwitchWork work,
    CallSessionDescription description, {
    required bool local,
  }) {
    final decision = machine.descriptionStarted(
      id: work.request.id,
      revision: work.revision,
      media: work.request.target,
      description: description.type == CallSessionDescriptionType.offer
          ? MediaSwitchDescription.offer
          : MediaSwitchDescription.answer,
      local: local,
    );
    _apply(decision);
    if (!decision.accepted) throw const _SwitchRetired();
  }

  Future<bool> _sendDescription(
    _SwitchWork work,
    CallSessionDescription description, {
    bool repair = false,
  }) => host.sendDescription(
    switchId: work.request.id,
    token: work.token!,
    description: description,
    repair: repair,
    deadlineMs: repair ? work.repairDeadline! : work.request.deadlineMs,
    canApply: () =>
        repair ? _repairCurrent(work) || _settledAudio(work) : _live(work),
  );

  Future<bool> _sendControl(_SwitchWork work, MediaSwitchEffect effect) async {
    bool delivered = false;
    try {
      delivered = await host.sendControl(
        effect,
        canApply: () => _controlCurrent(work, effect),
      );
    } catch (_) {
      /* Preserve failed transport custody as a failed outcome. */
    }
    if (!_current) return false;
    final kind = effect.replayOf ?? effect.kind;
    if (kind == MediaSwitchEffectKind.sendAbort ||
        (machine.requiresReconciliation &&
            (kind == MediaSwitchEffectKind.sendAck ||
                kind == MediaSwitchEffectKind.sendCommit))) {
      _apply(
        machine.reconciliationCompleted(
          id: work.request.id,
          delivered: delivered,
        ),
      );
    } else if (!delivered && machine.currentSwitchId == work.request.id) {
      abort(
        id: work.request.id,
        baseRevision: work.request.baseRevision,
        revision: work.revision,
        reason: MediaSwitchAbortReason.transport,
      );
    }
    return delivered;
  }

  bool _controlCurrent(_SwitchWork work, MediaSwitchEffect effect) {
    if (!_current || nowMs() >= effect.deadlineMs) return false;
    final kind = effect.replayOf ?? effect.kind;
    if (kind == MediaSwitchEffectKind.sendResponse &&
        effect.response != MediaSwitchResponse.accept) {
      return true;
    }
    if (kind == MediaSwitchEffectKind.sendRequest) {
      return machine.currentSwitchId == work.request.id &&
          machine.phase == MediaSwitchPhase.decision;
    }
    if (!identical(work, _selected)) return false;
    if (kind == MediaSwitchEffectKind.sendAbort) {
      return machine.phase == MediaSwitchPhase.aborted;
    }
    return machine.phase != MediaSwitchPhase.aborted &&
        !machine.switchingDisabled;
  }

  void _reconcile(_SwitchWork work, {required bool rollback}) {
    if (work.reconciliationScheduled) return;
    work.reconciliationScheduled = true;
    final token = work.token;
    if (!localIsCaller) host.expectRemoteOffer();
    _queue(work, () async {
      final session = host.session;
      var result = CallVideoSdpReconciliationOutcome.unreconciled;
      if (token != null && session is CallVideoSdpReconciler) {
        result = await (session as CallVideoSdpReconciler).reconcilePending(
          token,
          canApply: () => _repairCurrent(work) && identical(work.token, token),
        );
      }
      _check(work, repair: true);
      if (result == CallVideoSdpReconciliationOutcome.unreconciled) {
        _repairFailed(work, rollback: rollback);
        return;
      }
      work.reconciled = true;
      if (rollback) {
        _apply(machine.rollbackCompleted(id: work.request.id, success: true));
      } else {
        _startRepair(work);
      }
    }, repair: true);
  }

  void _startRepair(_SwitchWork work) {
    if (!_repairCurrent(work) || !work.reconciled || work.repairStarted) return;
    work.repairStarted = true;
    if (localIsCaller) {
      _offer(work, repair: true);
    } else {
      host.expectRemoteOffer();
    }
  }

  Future<void> _completeRepair(_SwitchWork work) async {
    _check(work, repair: true);
    await host.session.commit(work.token!);
    _check(work, repair: true);
    work.repairComplete = true;
    _apply(machine.repairCompleted(id: work.request.id, success: true));
  }

  void _repairFailed(_SwitchWork work, {bool rollback = false}) {
    final decision = rollback
        ? machine.rollbackCompleted(id: work.request.id, success: false)
        : machine.repairCompleted(id: work.request.id, success: false);
    _apply(decision);
    if (!decision.accepted) {
      _apply(machine.rollbackCompleted(id: work.request.id, success: false));
    }
  }

  void _settle(_SwitchWork work) {
    if (work.settlementScheduled) return;
    work.settlementScheduled = true;
    _track(
      Future<void>.sync(() async {
        final ack = work.ackDelivery;
        if (ack != null && !await ack) return;
        if (!_live(work)) {
          tick();
          return;
        }
        _queue(work, () async {
          final token = work.token!;
          await host.session.commit(token);
          _check(work);
          work.committed = true;
          final grant = work.grant;
          if (token.media == CallMediaKind.video && _grantCurrent(grant)) {
            final scopedGrant = CallLocalCameraGrant(
              foregroundConsent: grant!.foregroundConsent,
              permissionGranted: grant.permissionGranted,
              videoAgreed: true,
              isCurrent: () =>
                  _live(work) &&
                  identical(work.grant, grant) &&
                  _grantCurrent(grant),
            );
            await host.session.setLocalCamera(token, scopedGrant);
            if (!_live(work) ||
                !_grantCurrent(grant) ||
                !identical(work.grant, grant)) {
              await host.session.stopLocalCamera();
            }
          }
          _scheduleTick();
        });
      }),
      onFailure: () => _nativeFailure(work),
    );
  }

  void _queue(
    _SwitchWork work,
    Future<void> Function() job, {
    bool repair = false,
  }) {
    _track(
      Future<void>.sync(
        () => host.serialize(() async {
          tick();
          if (repair ? !_repairCurrent(work) : !_live(work)) return;
          try {
            await job();
          } on _SwitchRetired {
            /* A retired job can never grant new media authority. */
          } catch (_) {
            _nativeFailure(work, repair: repair);
          }
        }),
      ),
      onFailure: () => _nativeFailure(work, repair: repair),
    );
  }

  void _nativeFailure(_SwitchWork work, {bool repair = false}) {
    if (!_current || !identical(work, _selected)) return;
    if (repair) {
      if (_repairCurrent(work)) _repairFailed(work);
    } else if (_live(work)) {
      abort(
        id: work.request.id,
        baseRevision: work.request.baseRevision,
        revision: work.revision,
        reason: MediaSwitchAbortReason.negotiation,
      );
    }
  }

  void _check(_SwitchWork work, {bool repair = false}) {
    if (repair ? _repairCurrent(work) : _live(work)) return;
    tick();
    throw const _SwitchRetired();
  }

  bool _live(_SwitchWork work) =>
      _current &&
      identical(work, _selected) &&
      !machine.switchingDisabled &&
      machine.phase != MediaSwitchPhase.aborted &&
      (work.committed ||
          (_allowed(work.canApply) &&
              nowMs() < work.request.deadlineMs &&
              nowMs() < work.request.createdAtMs + 30000 &&
              (work.commitDeadline == null || nowMs() < work.commitDeadline!)));

  bool _repairCurrent(_SwitchWork work) =>
      _current &&
      identical(work, _selected) &&
      !machine.switchingDisabled &&
      machine.phase == MediaSwitchPhase.aborted &&
      !work.repairComplete &&
      work.repairDeadline != null &&
      nowMs() < work.repairDeadline!;

  bool _settledAudio(_SwitchWork work) =>
      _current &&
      identical(work, _selected) &&
      work.repairComplete &&
      !machine.switchingDisabled &&
      machine.settledMedia == CallMediaKind.audio;

  void _track(Future<Object?> future, {void Function()? onFailure}) {
    late final Future<void> pending;
    pending = future
        .then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {
            onFailure?.call();
          },
        )
        .whenComplete(() => _pending.remove(pending));
    _pending.add(pending);
  }

  void _scheduleTick() {
    if (!_current) {
      _timer?.cancel();
      _timer = null;
      _timerDeadline = null;
      return;
    }
    var deadline = machine.nextDeadlineMs;
    final selected = _selected;
    final commit =
        machine.phase == MediaSwitchPhase.committed &&
            selected?.committed == false
        ? selected?.commitDeadline
        : null;
    if (commit != null && (deadline == null || commit < deadline)) {
      deadline = commit;
    }
    if (_timerDeadline == deadline && _timer?.isActive == true) return;
    _timer?.cancel();
    _timer = null;
    _timerDeadline = deadline;
    if (deadline == null) return;
    final remaining = deadline - nowMs();
    _timer = timerScheduler.schedule(
      Duration(milliseconds: remaining > 0 ? remaining : 0),
      () async {
        _timer = null;
        _timerDeadline = null;
        tick();
      },
    );
  }

  static bool _grantCurrent(CallLocalCameraGrant? grant) =>
      grant != null &&
      grant.foregroundConsent &&
      grant.permissionGranted &&
      grant.videoAgreed &&
      _allowed(grant.isCurrent);
  static bool _allowed(bool Function()? predicate) {
    try {
      return predicate?.call() ?? true;
    } catch (_) {
      return false;
    }
  }

  static bool _sameDescription(
    CallSessionDescription a,
    CallSessionDescription b,
  ) => a.type == b.type && a.value == b.value && a.fingerprint == b.fingerprint;
  static void _validateDescription(
    CallSessionDescription description,
    CallSessionDescriptionType type,
  ) {
    if (description.type != type ||
        description.value.isEmpty ||
        (description.fingerprint?.isEmpty ?? true)) {
      throw StateError('invalid description');
    }
  }

  static bool _sameRequest(MediaSwitchRequest a, MediaSwitchRequest b) =>
      a.id == b.id &&
      a.baseRevision == b.baseRevision &&
      a.target == b.target &&
      a.requesterIsCaller == b.requesterIsCaller &&
      a.createdAtMs == b.createdAtMs &&
      a.deadlineMs == b.deadlineMs &&
      a.camera == b.camera;
}

final class _SwitchWork {
  _SwitchWork(this.request, this.grant, this.canApply);
  final MediaSwitchRequest request;
  final bool Function()? canApply;
  CallLocalCameraGrant? grant;
  int get revision => request.baseRevision + 1;
  bool admitted = false;
  CallVideoNegotiation? token;
  _RemoteSwitchDescription? remoteSwitch;
  _RemoteSwitchDescription? remoteRepair;
  CallSessionDescription? localSwitch;
  CallSessionDescription? localRepair;
  int? repairDeadline;
  int? commitDeadline;
  bool reconciliationScheduled = false;
  bool reconciled = false;
  bool repairStarted = false;
  bool repairComplete = false;
  bool settlementScheduled = false;
  bool committed = false;
  Future<bool>? ackDelivery;
}

final class _RemoteSwitchDescription {
  _RemoteSwitchDescription(this.negotiationId, this.description, this.canApply);
  final String negotiationId;
  final CallSessionDescription description;
  final bool Function()? canApply;
  bool applied = false;
}

final class _SwitchRetired implements Exception {
  const _SwitchRetired();
}
