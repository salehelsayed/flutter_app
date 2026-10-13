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
  }) async {
    if (_busy) return OutgoingCallStartResult.canceled;
    _busy = true;
    final request = OutgoingCallStartRequest(
      isCurrent: () =>
          (this.isCurrent?.call() ?? true) && (isCurrent?.call() ?? true),
    );
    try {
      return await _start(peerId, request).timeout(
        timeout,
        onTimeout: () {
          if (request.isAdmitted) return OutgoingCallStartResult.started;
          request.cancel();
          return OutgoingCallStartResult.failed;
        },
      );
    } catch (_) {
      request.cancel();
      return OutgoingCallStartResult.failed;
    } finally {
      _busy = false;
    }
  }

  Future<OutgoingCallStartResult> _start(
    String peerId,
    OutgoingCallStartRequest request,
  ) async {
    final owner = capability();
    if (owner == null || !await contactAllowed(peerId)) {
      return OutgoingCallStartResult.unavailable;
    }
    request.checkPending();
    if (!owner.isOutgoingCallAvailable &&
        owner is OutgoingCallReadinessRecovery) {
      await (owner as OutgoingCallReadinessRecovery)
          .recoverOutgoingCallReadiness();
    }
    request.checkPending();
    if (!owner.isOutgoingCallAvailable ||
        !await owner.isOutgoingCallAvailableFor(peerId)) {
      return OutgoingCallStartResult.unavailable;
    }
    request.checkPending();
    if (!identical(owner, capability())) {
      return OutgoingCallStartResult.unavailable;
    }
    return owner.startOutgoingCall(peerId, request: request);
  }
}

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
  Future<void>? _drain;

  Future<void> submit(CallId id) {
    if (_consumed.contains(id)) return Future<void>.value();
    _pending = id;
    return retryPending();
  }

  Future<void> retryPending() => _drain ??= _drainOnce().whenComplete(() {
    _drain = null;
  });
  Future<void> _drainOnce() async {
    while (_pending != null) {
      final id = _pending!;
      try {
        if (!await ready()) return;
      } catch (_) {
        return;
      }
      if (_pending != id) continue;
      _pending = null;
      if (!_consumed.add(id)) continue;
      if (_consumed.length > 64) _consumed.remove(_consumed.first);
      try {
        final source = history();
        final entry = await source?.findCall(id);
        if (entry == null ||
            entry.direction != CallDirection.incoming ||
            !const {
              CallHistoryStatus.missed,
              CallHistoryStatus.busy,
              CallHistoryStatus.cancelled,
            }.contains(entry.status)) {
          onResult(OutgoingCallStartResult.unavailable);
          continue;
        }
        final latest = await source!.recentCallsForContact(
          entry.contactAccountPeerId,
        );
        if (latest.isEmpty || latest.first.callId != id || !await ready()) {
          onResult(OutgoingCallStartResult.unavailable);
          continue;
        }
        onResult(await redial.start(entry.contactAccountPeerId));
      } catch (_) {
        onResult(OutgoingCallStartResult.failed);
      }
    }
  }
}
