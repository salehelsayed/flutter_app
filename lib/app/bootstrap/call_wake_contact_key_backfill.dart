import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/call/domain/call_wake_handle_grant.dart';
import 'package:flutter_app/features/call/domain/issued_call_wake_handle_store.dart';
import 'package:flutter_app/features/call/domain/received_call_wake_handle_store.dart';

typedef ReconcileCallWakeEligibility = Future<void> Function();
typedef HasPendingCallWakeDistribution = Future<bool> Function();
typedef RetryCallWakeDistribution =
    Future<int> Function({required String trigger, required bool requireFresh});
typedef ResumeCallSignaling = Future<void> Function();
typedef CallWakeDistributionRetryDelay =
    Future<void> Function(Duration duration);
typedef RequestReceivedCallWakeHandleRecovery =
    Future<void> Function({required String contactAccountPeerId});

const callWakeContactKeyUpdatedTrigger = 'call_wake_contact_key_updated';
const callWakeResumeReconcileTrigger = 'call_wake_resume_reconcile';
const callWakeOutgoingPreflightTrigger = 'call_wake_outgoing_preflight';
const outgoingCallWakeDistributionMaxAttempts = 31;
const outgoingCallWakeDistributionRetryDelay = Duration(seconds: 1);

/// Repairs a missing receiver-issued wake grant without multiplying network
/// work when several presentation or call-preflight checks run together.
///
/// Flights are isolated by contact. Failures are deliberately represented as
/// `false` so callers remain fail-closed, and the completed flight is always
/// removed so a later availability check can retry. No identifier, handle, or
/// failure payload is emitted from this coordinator.
final class ReceivedCallWakeHandleRecoveryCoordinator {
  ReceivedCallWakeHandleRecoveryCoordinator({
    required ReceivedCallWakeHandleStore receivedCallWakeHandleStore,
    required int Function() nowMs,
    required RequestReceivedCallWakeHandleRecovery requestRecovery,
  }) : _receivedCallWakeHandleStore = receivedCallWakeHandleStore,
       _nowMs = nowMs,
       _requestRecovery = requestRecovery;

  final ReceivedCallWakeHandleStore _receivedCallWakeHandleStore;
  final int Function() _nowMs;
  final RequestReceivedCallWakeHandleRecovery _requestRecovery;
  final Map<String, Future<bool>> _inFlightByContact = <String, Future<bool>>{};

  /// Returns whether a current grant is available after any coalesced repair.
  Future<bool> ensureCurrentGrantFor(String contactAccountPeerId) async {
    if (!CallWakeHandleGrant.hasValidPeerIdGrammar(contactAccountPeerId)) {
      return false;
    }
    try {
      if (_isCurrentReceivedGrant(
        await _receivedCallWakeHandleStore.readForIssuer(contactAccountPeerId),
        nowMs: _nowMs(),
      )) {
        return true;
      }
    } catch (_) {
      return false;
    }

    final existing = _inFlightByContact[contactAccountPeerId];
    if (existing != null) {
      return existing;
    }

    late final Future<bool> flight;
    flight = _requestAndRecheck(contactAccountPeerId).whenComplete(() {
      if (identical(_inFlightByContact[contactAccountPeerId], flight)) {
        _inFlightByContact.remove(contactAccountPeerId);
      }
    });
    _inFlightByContact[contactAccountPeerId] = flight;
    return flight;
  }

  Future<bool> _requestAndRecheck(String contactAccountPeerId) async {
    try {
      if (_isCurrentReceivedGrant(
        await _receivedCallWakeHandleStore.readForIssuer(contactAccountPeerId),
        nowMs: _nowMs(),
      )) {
        return true;
      }
      await _requestRecovery(contactAccountPeerId: contactAccountPeerId);
      return _isCurrentReceivedGrant(
        await _receivedCallWakeHandleStore.readForIssuer(contactAccountPeerId),
        nowMs: _nowMs(),
      );
    } catch (_) {
      return false;
    }
  }
}

bool _isCurrentReceivedGrant(
  CallWakeHandleGrant? grant, {
  required int nowMs,
}) =>
    grant != null &&
    grant.version == CallWakeHandleGrant.currentVersion &&
    CallWakeHandleGrant.hasValidPeerIdGrammar(grant.recipientDevicePeerId) &&
    grant.isValidAt(nowMs);

/// Ensures the exact target contact's current wake grant has completed its
/// encrypted distribution before an outgoing call delegates an invite.
///
/// A current grant whose distribution was already proven by the receiver's
/// exact durable receipt can be reused while that receiver is offline. Pending
/// grants get a small bounded set of fresh, target-specific receipt attempts.
/// Every attempt re-reads the durable record, and every post-attempt read must
/// still name the target contact and the exact initial grant generation. A
/// missing record, rotation, revocation, expiry, or exhausted pending result
/// all fail closed. This helper is intentionally total because readiness
/// failure is an unavailable-call outcome rather than an application error.
Future<bool> ensureOutgoingCallWakeAuthorityReady({
  required String contactAccountPeerId,
  required IssuedCallWakeHandleStore issuedCallWakeHandleStore,
  required int Function() nowMs,
  required RetryCallWakeDistribution retryCallWakeDistribution,
  int maxAttempts = outgoingCallWakeDistributionMaxAttempts,
  Duration retryDelay = outgoingCallWakeDistributionRetryDelay,
  CallWakeDistributionRetryDelay delay = _delayCallWakeDistributionRetry,
}) async {
  try {
    if (!CallWakeHandleGrant.hasValidPeerIdGrammar(contactAccountPeerId)) {
      return false;
    }
    final before = await issuedCallWakeHandleStore.readForContact(
      contactAccountPeerId,
    );
    if (!_isUsableOutgoingWakeRecord(
      before,
      contactAccountPeerId: contactAccountPeerId,
      nowMs: nowMs(),
    )) {
      return false;
    }
    final exactBefore = before!;
    if (!exactBefore.distributionPending &&
        exactBefore.hasCurrentDistributionReceipt) {
      return true;
    }
    final boundedAttempts = maxAttempts < 1
        ? 1
        : maxAttempts > outgoingCallWakeDistributionMaxAttempts
        ? outgoingCallWakeDistributionMaxAttempts
        : maxAttempts;

    for (var attempt = 0; attempt < boundedAttempts; attempt++) {
      final current = attempt == 0
          ? exactBefore
          : await issuedCallWakeHandleStore.readForContact(
              contactAccountPeerId,
            );
      if (!_isSameUsableOutgoingWakeRecord(
        current,
        exactBefore: exactBefore,
        contactAccountPeerId: contactAccountPeerId,
        nowMs: nowMs(),
      )) {
        return false;
      }
      if (!current!.distributionPending &&
          current.hasCurrentDistributionReceipt) {
        return true;
      }

      try {
        await retryCallWakeDistribution(
          trigger: callWakeOutgoingPreflightTrigger,
          requireFresh: true,
        );
      } catch (_) {
        // A transport/discovery failure can be transient. Durable state below
        // remains the only authority and determines whether another attempt is
        // safe.
      }

      final after = await issuedCallWakeHandleStore.readForContact(
        contactAccountPeerId,
      );
      if (!_isSameUsableOutgoingWakeRecord(
        after,
        exactBefore: exactBefore,
        contactAccountPeerId: contactAccountPeerId,
        nowMs: nowMs(),
      )) {
        return false;
      }
      if (!after!.distributionPending && after.hasCurrentDistributionReceipt) {
        return true;
      }
      if (attempt + 1 < boundedAttempts) {
        await delay(retryDelay);
      }
    }
    return false;
  } catch (_) {
    return false;
  }
}

Future<void> _delayCallWakeDistributionRetry(Duration duration) =>
    Future<void>.delayed(duration);

bool _isSameUsableOutgoingWakeRecord(
  CallIssuedWakeHandleRecord? record, {
  required CallIssuedWakeHandleRecord exactBefore,
  required String contactAccountPeerId,
  required int nowMs,
}) =>
    _isUsableOutgoingWakeRecord(
      record,
      contactAccountPeerId: contactAccountPeerId,
      nowMs: nowMs,
    ) &&
    record!.grant == exactBefore.grant;

bool _isUsableOutgoingWakeRecord(
  CallIssuedWakeHandleRecord? record, {
  required String contactAccountPeerId,
  required int nowMs,
}) =>
    record != null &&
    record.contactAccountPeerId == contactAccountPeerId &&
    !record.revokePending &&
    record.grant.isValidAt(nowMs);

/// Reconciles the newly trusted contact key before draining any call-wake
/// grant that reconciliation made distribution-pending.
///
/// This function is intentionally total because it is launched from a stream
/// listener. A reconnect or app resume retains ownership of any pending retry.
Future<bool> backfillCallWakeAfterContactKeyUpdate({
  required ReconcileCallWakeEligibility reconcileCallWakeEligibility,
  required HasPendingCallWakeDistribution hasPendingCallWakeDistribution,
  required RetryCallWakeDistribution retryCallWakeDistribution,
  String trigger = callWakeContactKeyUpdatedTrigger,
}) async {
  final outcome = await _backfillCallWakeAfterContactKeyUpdate(
    reconcileCallWakeEligibility: reconcileCallWakeEligibility,
    hasPendingCallWakeDistribution: hasPendingCallWakeDistribution,
    retryCallWakeDistribution: retryCallWakeDistribution,
    trigger: trigger,
    requireFreshRetry: false,
  );
  return outcome.completed;
}

Future<_CallWakeBackfillOutcome> _backfillCallWakeAfterContactKeyUpdate({
  required ReconcileCallWakeEligibility reconcileCallWakeEligibility,
  required HasPendingCallWakeDistribution hasPendingCallWakeDistribution,
  required RetryCallWakeDistribution retryCallWakeDistribution,
  required String trigger,
  required bool requireFreshRetry,
}) async {
  var reconciliationCompleted = false;
  var pendingCheckCompleted = false;
  var pendingDistribution = false;
  var retryAttempted = false;
  var retryCompleted = false;
  var sentCount = 0;

  try {
    await reconcileCallWakeEligibility();
    reconciliationCompleted = true;
    pendingDistribution = await hasPendingCallWakeDistribution();
    pendingCheckCompleted = true;
    if (!pendingDistribution) {
      return _CallWakeBackfillOutcome(
        reconciliationCompleted: reconciliationCompleted,
        pendingCheckCompleted: pendingCheckCompleted,
        pendingDistribution: pendingDistribution,
        retryAttempted: retryAttempted,
        retryCompleted: retryCompleted,
        sentCount: sentCount,
        completed: true,
      );
    }
    retryAttempted = true;
    sentCount = await retryCallWakeDistribution(
      trigger: trigger,
      requireFresh: requireFreshRetry,
    );
    retryCompleted = true;
    return _CallWakeBackfillOutcome(
      reconciliationCompleted: reconciliationCompleted,
      pendingCheckCompleted: pendingCheckCompleted,
      pendingDistribution: pendingDistribution,
      retryAttempted: retryAttempted,
      retryCompleted: retryCompleted,
      sentCount: sentCount,
      completed: true,
    );
  } catch (_) {
    return _CallWakeBackfillOutcome(
      reconciliationCompleted: reconciliationCompleted,
      pendingCheckCompleted: pendingCheckCompleted,
      pendingDistribution: pendingDistribution,
      retryAttempted: retryAttempted,
      retryCompleted: retryCompleted,
      sentCount: sentCount,
      completed: false,
    );
  }
}

/// Replays call-signaling resume work before repairing a grant distribution
/// that may have been missed while the application was backgrounded.
///
/// Resume and grant repair are independent best-effort recovery legs. A
/// signaling failure is reported by the return value but does not strand a
/// pending grant, and no failure escapes into the application lifecycle.
Future<bool> resumeCallSignalingAndBackfillCallWake({
  required ResumeCallSignaling resumeCallSignaling,
  required ReconcileCallWakeEligibility reconcileCallWakeEligibility,
  required HasPendingCallWakeDistribution hasPendingCallWakeDistribution,
  required RetryCallWakeDistribution retryCallWakeDistribution,
}) async {
  var resumeCompleted = true;
  try {
    await resumeCallSignaling();
  } catch (_) {
    resumeCompleted = false;
  }

  final backfillOutcome = await _backfillCallWakeAfterContactKeyUpdate(
    reconcileCallWakeEligibility: reconcileCallWakeEligibility,
    hasPendingCallWakeDistribution: hasPendingCallWakeDistribution,
    retryCallWakeDistribution: retryCallWakeDistribution,
    trigger: callWakeResumeReconcileTrigger,
    requireFreshRetry: true,
  );
  final completed = resumeCompleted && backfillOutcome.completed;
  _emitResumeReconcileResult(
    resumeCompleted: resumeCompleted,
    backfillOutcome: backfillOutcome,
    completed: completed,
  );
  return completed;
}

void _emitResumeReconcileResult({
  required bool resumeCompleted,
  required _CallWakeBackfillOutcome backfillOutcome,
  required bool completed,
}) {
  try {
    emitFlowEvent(
      layer: 'FL',
      event: 'CALL_WAKE_RESUME_RECONCILE_RESULT',
      details: <String, dynamic>{
        'resumeCompleted': resumeCompleted,
        'reconciliationCompleted': backfillOutcome.reconciliationCompleted,
        'pendingCheckCompleted': backfillOutcome.pendingCheckCompleted,
        'pendingDistribution': backfillOutcome.pendingDistribution,
        'retryAttempted': backfillOutcome.retryAttempted,
        'retryCompleted': backfillOutcome.retryCompleted,
        'sentCount': backfillOutcome.sentCount,
        'completed': completed,
      },
    );
  } catch (_) {
    // Diagnostics must not escape into the application lifecycle.
  }
}

final class _CallWakeBackfillOutcome {
  const _CallWakeBackfillOutcome({
    required this.reconciliationCompleted,
    required this.pendingCheckCompleted,
    required this.pendingDistribution,
    required this.retryAttempted,
    required this.retryCompleted,
    required this.sentCount,
    required this.completed,
  });

  final bool reconciliationCompleted;
  final bool pendingCheckCompleted;
  final bool pendingDistribution;
  final bool retryAttempted;
  final bool retryCompleted;
  final int sentCount;
  final bool completed;
}
