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

/// Contact repair is owned by an explicit call action, never a passive probe.
abstract interface class OutgoingCallContactReadinessRecovery {
  Future<bool> recoverOutgoingCallAvailabilityFor(
    String contactAccountPeerId, {
    required OutgoingCallStartRequest request,
  });
}

/// Closed-vocabulary call diagnostic values that explain why the outgoing
/// call graph is not ready: the last start stage and outcome, whether the P2P
/// transport is started, and whether a failed withdrawal blocks restarts.
abstract interface class OutgoingCallStartDiagnostics {
  Map<String, Object?> outgoingCallStartDiagnostics();
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

/// Optional explicit video entry on the same process-owned outgoing graph.
///
/// The inherited audio commands keep their existing behavior. Implementing
/// this capability does not enable video: availability remains false while
/// the video gate is off. [outgoingCallAvailabilityChanges] also invalidates
/// video availability; cached presentation state never authorizes a call.
abstract interface class OutgoingVideoCallCapability
    implements OutgoingCallCapability {
  bool get isOutgoingVideoCallAvailable;

  /// Resolves this contact afresh and requires the exact trusted, signed
  /// endpoint to support both voice v1 and video v2. Passive availability
  /// checks do not request permission, acquire media or place a call.
  Future<bool> isOutgoingVideoCallAvailableFor(String contactAccountPeerId);

  /// Requests a video call only after fresh admission and ownership checks.
  ///
  /// Implementations preserve [OutgoingCallStartRequest] cancellation across
  /// awaits and never silently fall back to a legacy audio invitation. This
  /// command alone cannot open a camera: foreground consent, OS permission,
  /// accepted media and committed negotiation are still required.
  Future<OutgoingCallStartResult> startOutgoingVideoCall(
    String contactAccountPeerId, {
    OutgoingCallStartRequest? request,
  });
}
