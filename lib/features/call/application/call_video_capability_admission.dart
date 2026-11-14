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
  final endpoint = await resolveEndpoint(contactAccountPeerId);
  if (endpoint.accountPeerId != contactAccountPeerId) {
    throw const CallVideoAdmissionException(
      CallVideoAdmissionFailure.mismatched,
    );
  }
  // Lookup and signature verification can cross the lease boundary.
  if (endpoint.expiresAtMs <= nowMs()) {
    throw const CallVideoAdmissionException(CallVideoAdmissionFailure.expired);
  }
  if (!endpoint.capabilities.contains(CallEndpointResolver.voiceCapability) ||
      !endpoint.capabilities.contains('video_call_v2')) {
    throw const CallVideoAdmissionException(
      CallVideoAdmissionFailure.unsupported,
    );
  }
  return endpoint;
}
