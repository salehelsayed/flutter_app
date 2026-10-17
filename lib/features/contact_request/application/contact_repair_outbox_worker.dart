import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contact_request/application/existing_contact_repair_policy.dart';
import 'package:flutter_app/features/contact_request/application/send_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_control.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_repair_repository.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:uuid/uuid.dart';

/// Points in one job's life where a test can freeze the worker as if the
/// process died there.
enum ContactRepairWorkerStage { claimed, built, committed, transmitted }

/// Drains the durable repair-reply outbox (Task 12b).
///
/// One worker owns one claim token. Each job is built once, its complete
/// envelope is committed before the first send, and every retry transmits
/// those same bytes. Every step re-checks the job's authority, relationship,
/// local identity and call-wake grant, and every state change is a
/// compare-and-set on the claim token, so a worker that lost ownership (a new
/// owner took over) can neither commit nor send.
final class ContactRepairOutboxWorker {
  ContactRepairOutboxWorker({
    required ContactRepairRepository repository,
    required P2PService p2pService,
    required IdentityRepository identityRepo,
    required Bridge bridge,
    required ContactRepository contactRepo,
    ResolveCallWakeHandle? resolveCallWakeHandle,
    OnCallWakeHandleDistributed? onCallWakeHandleDistributed,
    Future<String?> Function(String peerId)? resolveWakeToken,
    int Function()? nowMs,
    String? claimToken,
    bool scheduleWakeups = true,
    Future<void> Function(ContactRepairWorkerStage stage)? debugStageHook,
  }) : _repository = repository,
       _p2pService = p2pService,
       _identityRepo = identityRepo,
       _bridge = bridge,
       _contactRepo = contactRepo,
       _resolveCallWakeHandle = resolveCallWakeHandle,
       _onCallWakeHandleDistributed = onCallWakeHandleDistributed,
       _resolveWakeToken = resolveWakeToken,
       _nowMs = nowMs ?? (() => DateTime.now().toUtc().millisecondsSinceEpoch),
       claimToken = claimToken ?? const Uuid().v4(),
       _scheduleWakeups = scheduleWakeups,
       _debugStageHook = debugStageHook;

  static const Duration _maxWakeDelay = Duration(minutes: 5);

  final ContactRepairRepository _repository;
  final P2PService _p2pService;
  final IdentityRepository _identityRepo;
  final Bridge _bridge;
  final ContactRepository _contactRepo;
  final ResolveCallWakeHandle? _resolveCallWakeHandle;
  final OnCallWakeHandleDistributed? _onCallWakeHandleDistributed;
  final Future<String?> Function(String peerId)? _resolveWakeToken;
  final int Function() _nowMs;
  final bool _scheduleWakeups;
  final Future<void> Function(ContactRepairWorkerStage stage)? _debugStageHook;

  /// This worker's ownership generation.
  final String claimToken;

  Future<void>? _running;
  var _rerun = false;
  var _disposed = false;
  Timer? _wakeup;
  StreamSubscription<Object?>? _nodeStates;

  /// Takes over jobs a previous owner left in flight, then drains. Also drains
  /// whenever the node reports started.
  Future<void> start() async {
    await _repository.takeOverInFlight(newClaimToken: claimToken);
    _nodeStates ??= _p2pService.stateStream.listen((state) {
      if (state.isStarted) unawaited(drain());
    });
    await drain();
  }

  /// Sends every due reply. Concurrent calls share one run.
  Future<void> drain() {
    if (_disposed) return Future<void>.value();
    final running = _running;
    if (running != null) {
      _rerun = true;
      return running;
    }
    final run = _run().whenComplete(() => _running = null);
    _running = run;
    return run;
  }

  void dispose() {
    _disposed = true;
    _wakeup?.cancel();
    unawaited(_nodeStates?.cancel());
  }

  Future<void> _run() async {
    try {
      do {
        _rerun = false;
        await _repository.collectGarbage(wallNowMs: _nowMs());
        if (!_p2pService.currentState.isStarted) break;
        while (!_disposed) {
          final jobs = await _repository.takeDueJobs(
            claimToken: claimToken,
            wallNowMs: _nowMs(),
            limit: ContactRepairLimits.maxTransmitting,
          );
          if (jobs.isEmpty) break;
          await Future.wait(jobs.map(_process));
        }
      } while (_rerun && !_disposed);
      await _scheduleNextWakeup();
    } catch (_) {
      // Durable state is unchanged by a failed drain; the next reservation,
      // node start or scheduled wake-up retries it.
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_REPAIR_DRAIN_FAILED',
        details: {'reason': 'error'},
      );
    }
  }

  Future<void> _scheduleNextWakeup() async {
    if (!_scheduleWakeups || _disposed) return;
    _wakeup?.cancel();
    final next = await _repository.nextDueAtMs();
    if (next == null) return;
    final waitMs = (next - _nowMs()).clamp(0, _maxWakeDelay.inMilliseconds);
    _wakeup = Timer(Duration(milliseconds: waitMs), () => unawaited(drain()));
  }

  Future<void> _process(ContactRepairJob job) async {
    try {
      await _debugStageHook?.call(ContactRepairWorkerStage.claimed);
      if (!await _fenceHolds(job)) {
        await _cancel(job, 'authority_changed');
        return;
      }

      BuiltContactRequestEnvelope envelope;
      final committedJson = job.envelopeJson;
      if (committedJson == null) {
        final contact = (await _contactRepo.getContact(job.peerId))!;
        final build = await buildContactRequestEnvelope(
          identityRepo: _identityRepo,
          bridge: _bridge,
          targetPeerId: job.peerId,
          recipientPublicKey: contact.publicKey,
          resolveWakeToken: _resolveWakeToken,
          resolveCallWakeHandle: _resolveCallWakeHandle,
          control: ContactRequestControl.repairReply(
            id: job.replyId,
            to: job.peerId,
            replyTo: job.requestId,
          ),
        );
        final built = build.envelope;
        if (built == null) {
          await _retry(job, 'build_failed');
          return;
        }
        await _debugStageHook?.call(ContactRepairWorkerStage.built);
        if (!await _fenceHolds(job)) {
          await _cancel(job, 'authority_changed');
          return;
        }
        final committed = await _repository.commitEnvelope(
          job: job,
          claimToken: claimToken,
          envelopeJson: jsonEncode(built.toJson()),
          grantGeneration: built.callWakeHandle?.generation,
        );
        if (!committed) return;
        envelope = built;
        await _debugStageHook?.call(ContactRepairWorkerStage.committed);
      } else {
        envelope = BuiltContactRequestEnvelope.fromJson(
          jsonDecode(committedJson) as Map<String, Object?>,
        );
      }

      if (!await _grantStillCurrent(envelope)) {
        // The exact grant this reply carries rotated or expired. Never mint a
        // second reply for the same request; distribution stays pending.
        await _cancel(job, 'grant_changed');
        return;
      }
      if (!await _fenceHolds(job) ||
          !await _repository.stillOwns(job: job, claimToken: claimToken)) {
        await _cancel(job, 'authority_changed');
        return;
      }

      final outcome = await transmitContactRequestEnvelope(
        p2pService: _p2pService,
        envelope: envelope,
      );
      await _debugStageHook?.call(ContactRepairWorkerStage.transmitted);
      if (outcome.result != SendContactRequestResult.success) {
        await _retry(job, 'send_failed');
        return;
      }
      if (await _repository.completeJob(job: job, claimToken: claimToken)) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CONTACT_REPAIR_REPLY_SENT',
          details: {'status': 'completed'},
        );
      }
      if (outcome.exactCallWakeReceipt) {
        await markContactRequestCallWakeHandleDistributed(
          envelope: envelope,
          onCallWakeHandleDistributed: _onCallWakeHandleDistributed,
        );
      }
    } catch (_) {
      await _retry(job, 'error');
    }
  }

  Future<bool> _fenceHolds(ContactRepairJob job) async {
    final ContactModel? contact = await _contactRepo.getContact(job.peerId);
    if (contact == null || contact.isBlocked) return false;
    final String fingerprint;
    try {
      fingerprint = ed25519AuthorityFingerprint(contact.publicKey);
    } on FormatException {
      return false;
    }
    if (fingerprint != job.authorityFingerprint) return false;
    final consent = await _repository.readConsent(job.peerId);
    final revision = consent?.revision ?? 0;
    if ((consent != null && consent.state != ContactRelationshipState.active) ||
        revision != job.relationshipRevision) {
      return false;
    }
    if (job.localAuthorityFingerprint.isNotEmpty) {
      final identity = await _identityRepo.loadIdentity();
      if (identity == null) return false;
      try {
        if (ed25519AuthorityFingerprint(identity.publicKey) !=
            job.localAuthorityFingerprint) {
          return false;
        }
      } on FormatException {
        return false;
      }
    }
    return true;
  }

  Future<bool> _grantStillCurrent(BuiltContactRequestEnvelope envelope) async {
    final carried = envelope.callWakeHandle;
    if (carried == null) return true;
    if (!carried.isValidAt(_nowMs())) return false;
    final resolve = _resolveCallWakeHandle;
    if (resolve == null) return true;
    final current = await resolve(envelope.targetPeerId);
    return current != null && current.generation == carried.generation;
  }

  Future<void> _cancel(ContactRepairJob job, String reason) async {
    if (await _repository.cancelJob(job: job, claimToken: claimToken)) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_REPAIR_REPLY_CANCELLED',
        details: {'reason': reason},
      );
    }
  }

  Future<void> _retry(ContactRepairJob job, String reason) async {
    final released = await _repository.releaseForRetry(
      job: job,
      claimToken: claimToken,
      dueAtMs:
          _nowMs() +
          ContactRepairLimits.retryBackoff(job.attempts).inMilliseconds,
    );
    if (released) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_REPAIR_REPLY_RETRY',
        details: {'reason': reason},
      );
    }
  }
}
