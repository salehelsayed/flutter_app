import 'dart:async';

/// Detail-free outcome exposed to presentation after one outgoing-call
/// request. Adapter and routing failures deliberately stay behind this seam.
enum OutgoingCallStartResult { started, unavailable, failed }

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
    String contactAccountPeerId,
  );
}
