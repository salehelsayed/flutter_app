import 'dart:async';
import 'dart:collection';
import '../data/call_history_repository.dart';
import '../domain/call_id.dart';
import '../domain/call_session_snapshot.dart';
import 'call_history_access.dart';
import 'outgoing_call_capability.dart';

/// Rechecks local contact policy and the current authenticated outgoing owner.
/// A historical call supplies only a contact route; admission creates a fresh call.
class CallRedialController {
  CallRedialController({
    required this.capability,
    required this.contactAllowed,
    this.isCurrent,
    this.timeout = const Duration(seconds: 12),
  });
  final OutgoingCallCapability? Function() capability;
  final Future<bool> Function(String peerId) contactAllowed;
  final Duration timeout;
  final bool Function()? isCurrent;
  bool _busy = false;

  Future<OutgoingCallStartResult> start(
    String peerId, {
    bool Function()? isCurrent,
    Future<bool> Function()? isEligible,
  }) async {
    if (_busy) return OutgoingCallStartResult.canceled;
    _busy = true;
    final request = OutgoingCallStartRequest(
      isCurrent: () =>
          (this.isCurrent?.call() ?? true) && (isCurrent?.call() ?? true),
    );
    try {
      return await _start(peerId, request, isEligible).timeout(
        timeout,
        onTimeout: () {
          if (request.isAdmitted) return OutgoingCallStartResult.started;
          final canceled = request.isCanceled;
          request.cancel();
          return canceled
              ? OutgoingCallStartResult.canceled
              : OutgoingCallStartResult.failed;
        },
      );
    } on OutgoingCallStartCanceled {
      request.cancel();
      return OutgoingCallStartResult.canceled;
    } catch (_) {
      final canceled = request.isCanceled;
      request.cancel();
      return canceled
          ? OutgoingCallStartResult.canceled
          : OutgoingCallStartResult.failed;
    } finally {
      _busy = false;
    }
  }

  Future<OutgoingCallStartResult> _start(
    String peerId,
    OutgoingCallStartRequest request,
    Future<bool> Function()? isEligible,
  ) async {
    request.checkPending();
    final owner = capability();
    if (owner == null) {
      return OutgoingCallStartResult.unavailable;
    }
    final allowed = await contactAllowed(peerId);
    request.checkPending();
    if (!allowed) return OutgoingCallStartResult.unavailable;
    if (!owner.isOutgoingCallAvailable &&
        owner is OutgoingCallReadinessRecovery) {
      await (owner as OutgoingCallReadinessRecovery)
          .recoverOutgoingCallReadiness();
    }
    request.checkPending();
    if (!owner.isOutgoingCallAvailable) {
      return OutgoingCallStartResult.unavailable;
    }
    final contactAvailable = await owner.isOutgoingCallAvailableFor(peerId);
    request.checkPending();
    if (!contactAvailable) return OutgoingCallStartResult.unavailable;
    if (!identical(owner, capability())) {
      return OutgoingCallStartResult.unavailable;
    }
    // Notification eligibility is local history, not payload authority. Recheck
    // after contact/endpoint awaits; the synchronous request fence then follows
    // the existing outgoing owner through its preflight to canonical admission.
    final eligible = await isEligible?.call() ?? true;
    request.checkPending();
    if (!eligible) return OutgoingCallStartResult.unavailable;
    if (!identical(owner, capability())) {
      return OutgoingCallStartResult.unavailable;
    }
    return owner.startOutgoingCall(peerId, request: request);
  }
}

/// An incoming call the user did not take. Such a card may start a fresh call
/// only while it is still the contact's newest call.
bool isMissedIncomingCall(CallHistoryEntry entry) =>
    entry.direction == CallDirection.incoming &&
    const {
      CallHistoryStatus.missed,
      CallHistoryStatus.busy,
      CallHistoryStatus.cancelled,
    }.contains(entry.status);

/// Bounded local action inbox. Cold/locked opens wait for the canonical runtime
/// and foreground unlock. Duplicates and superseded cards cannot double dial.
class CallBackActionHandler {
  CallBackActionHandler({
    required this.history,
    required this.ready,
    required this.redial,
    required this.onResult,
  });
  final CallHistoryAccess? Function() history;
  final Future<bool> Function() ready;
  final CallRedialController redial;
  final void Function(OutgoingCallStartResult result) onResult;
  final LinkedHashSet<CallId> _consumed = LinkedHashSet();
  CallId? _pending;
  Object _generation = Object();
  Future<void>? _drain;

  Future<void> submit(CallId id) {
    if (_consumed.contains(id)) return Future<void>.value();
    if (_pending == id) return retryPending();
    _generation = Object();
    _pending = id;
    return retryPending();
  }

  Future<void> retryPending() => _drain ??= _drainOnce().whenComplete(() {
    _drain = null;
  });
  Future<void> _drainOnce() async {
    while (_pending != null) {
      final id = _pending!;
      final generation = _generation;
      bool isCurrent() => identical(generation, _generation);
      try {
        final isReady = await ready();
        if (!isCurrent()) continue;
        if (!isReady) return;
      } catch (_) {
        if (!isCurrent()) continue;
        return;
      }
      if (_pending != id) continue;
      _pending = null;
      if (!_consumed.add(id)) continue;
      if (_consumed.length > 64) _consumed.remove(_consumed.first);
      try {
        final source = history();
        final entry = await source?.findCall(id);
        if (!isCurrent()) continue;
        if (entry == null || !isMissedIncomingCall(entry)) {
          onResult(OutgoingCallStartResult.unavailable);
          continue;
        }
        final latest = await source!.recentCallsForContact(
          entry.contactAccountPeerId,
        );
        if (!isCurrent()) continue;
        if (latest.isEmpty || latest.first.callId != id) {
          onResult(OutgoingCallStartResult.unavailable);
          continue;
        }
        final isReady = await ready();
        if (!isCurrent()) continue;
        if (!isReady) {
          onResult(OutgoingCallStartResult.unavailable);
          continue;
        }
        onResult(
          await redial.start(
            entry.contactAccountPeerId,
            isCurrent: isCurrent,
            isEligible: () async {
              final current = await source.recentCallsForContact(
                entry.contactAccountPeerId,
              );
              return current.isNotEmpty && current.first.callId == id;
            },
          ),
        );
      } catch (_) {
        if (isCurrent()) onResult(OutgoingCallStartResult.failed);
      }
    }
  }
}
