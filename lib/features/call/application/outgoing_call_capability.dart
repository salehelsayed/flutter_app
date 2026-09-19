import 'dart:async';

/// Safe outcome exposed to presentation after one outgoing-call request.
/// Only an explicit microphone refusal carries actionable permission feedback;
/// adapter and routing failures deliberately stay behind this seam.
enum OutgoingCallStartResult {
  started,
  unavailable,
  failed,
  microphoneDenied,
  canceled,
}

/// Ownership of preflight only. Admission transfers control to the canonical
/// coordinator; cancellation after that point belongs to its exact call ID.
final class OutgoingCallStartRequest {
  OutgoingCallStartRequest({this.onAdmitted, this.isCurrent});

  final void Function()? onAdmitted;
  final bool Function()? isCurrent;
  bool _canceled = false;
  bool _admitted = false;

  bool get isCanceled =>
      _canceled || (!_admitted && isCurrent?.call() == false);
  bool get isAdmitted => _admitted;

  void cancel() {
    if (!_admitted) _canceled = true;
  }

  void checkPending() {
    if (isCanceled) throw const OutgoingCallStartCanceled();
  }

  void admit() {
    checkPending();
    _admitted = true;
    onAdmitted?.call();
  }
}

final class OutgoingCallStartCanceled implements Exception {
  const OutgoingCallStartCanceled();
}

/// Optional recovery for an explicit call action. Passive availability probes
/// must not invoke this hook. Recovery never places a call or requests audio.
abstract interface class OutgoingCallReadinessRecovery {
  Future<bool> recoverOutgoingCallReadiness();
}

/// Presentation-neutral access to the one process-owned outgoing call graph.
///
/// Availability is read at use time because the underlying graph may be
/// withdrawn and rebuilt as lifecycle or relay authority changes.
abstract interface class OutgoingCallCapability {
  bool get isOutgoingCallAvailable;

  /// Emits current process readiness whenever presentation must re-evaluate
  /// contact-specific availability. A repeated `true` after resume is
  /// meaningful because the trusted endpoint roster may have changed.
  Stream<bool> get outgoingCallAvailabilityChanges;

  /// True only when this exact contact currently resolves to one trusted,
  /// signed, voice-capable endpoint. Presentation keeps the action hidden
  /// while this asynchronous check is unavailable or fails.
  Future<bool> isOutgoingCallAvailableFor(String contactAccountPeerId);

  Future<OutgoingCallStartResult> startOutgoingCall(
    String contactAccountPeerId, {
    OutgoingCallStartRequest? request,
  });
}
