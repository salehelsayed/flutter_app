import '../domain/call_engine.dart';

/// Local diagnostic classifications using the existing v1 schema vocabulary.
/// These never become peer-facing call end reasons or include exception text.
enum CallSetupFailure {
  signaling('signaling', 'transport_failed'),
  ice('media', 'ice_failed'),
  mediaTransport('media', 'transport_failed'),
  configuration('media', 'negotiation_failed'),
  mediaStart('media', 'media_failed'),
  mediaNotReady('media', 'unavailable'),
  mediaClosed('media', 'media_stalled'),
  permission('preflight', 'permission_denied'),
  turn('turn', 'turn_unavailable'),
  checkpoint('runtime', 'write_failed'),
  runtime('runtime', 'unknown'),
  mediaTimeout('media', 'timeout'),
  signalingTimeout('signaling', 'timeout'),
  runtimeTimeout('runtime', 'timeout');

  const CallSetupFailure(this.stage, this.reason);
  final String stage;
  final String reason;

  static CallSetupFailure fromEngine(CallEngineErrorCode code) =>
      switch (code) {
        CallEngineErrorCode.iceConnectionFailed => ice,
        CallEngineErrorCode.transportUnavailable => mediaTransport,
        CallEngineErrorCode.configurationRejected ||
        CallEngineErrorCode.malformedFingerprint ||
        CallEngineErrorCode.fingerprintMismatch ||
        CallEngineErrorCode.candidateOverflow ||
        CallEngineErrorCode.staleIceGeneration ||
        CallEngineErrorCode.futureIceGeneration ||
        CallEngineErrorCode.restartLimitReached ||
        CallEngineErrorCode.relayPolicyViolation => configuration,
        CallEngineErrorCode.notReady ||
        CallEngineErrorCode.observationUnavailable => mediaNotReady,
        CallEngineErrorCode.closed => mediaClosed,
        CallEngineErrorCode.other => mediaStart,
      };

  static CallSetupFailure fromObservation(CallFailureReason reason) =>
      switch (reason) {
        CallFailureReason.iceConnectionFailed => ice,
        CallFailureReason.transportUnavailable => mediaTransport,
        CallFailureReason.configurationRejected => configuration,
        CallFailureReason.notReady => mediaNotReady,
        CallFailureReason.closed => mediaClosed,
        CallFailureReason.none || CallFailureReason.other => mediaStart,
      };
}
