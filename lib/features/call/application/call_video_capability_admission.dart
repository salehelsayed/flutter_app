import 'call_endpoint_resolver.dart';

enum CallVideoAdmissionFailure { disabled, unsupported, mismatched, expired }

final class CallVideoAdmissionException implements Exception {
  const CallVideoAdmissionException(this.reason);

  final CallVideoAdmissionFailure reason;
}

/// A video request cannot reuse a capability decision from an earlier attempt.
Future<ResolvedCallEndpoint> resolveVideoCallEndpoint({
  required String contactAccountPeerId,
  required Future<ResolvedCallEndpoint> Function(String) resolveEndpoint,
  required int Function() nowMs,
  bool videoEnabled = false,
}) async {
  if (!videoEnabled) {
    throw const CallVideoAdmissionException(CallVideoAdmissionFailure.disabled);
  }
  // RED interface scaffold: no video authority is admitted yet.
  throw const CallVideoAdmissionException(
    CallVideoAdmissionFailure.unsupported,
  );
}
