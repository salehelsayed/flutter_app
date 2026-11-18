enum CallEndCause {
  localHangup('local_hangup'),
  remoteTerminate('remote_terminate'),
  canceled('canceled'),
  declined('declined'),
  busy('busy'),
  noAnswer('no_answer'),
  permissionDenied('permission_denied'),
  unsupported('unsupported'),
  policyRejected('policy_rejected'),
  recoveryDenied('recovery_denied'),
  recoveryTimeout('recovery_timeout'),
  iceFailed('ice_failed'),
  mediaFailed('media_failed'),
  mediaUnavailable('media_unavailable'),
  mediaConfiguration('media_configuration'),
  mediaTimeout('media_timeout'),
  audioSessionFailed('audio_session_failed'),
  signalingFailed('signaling_failed'),
  signalingTimeout('signaling_timeout'),
  endpointUnavailable('endpoint_unavailable'),
  checkpointFailed('checkpoint_failed'),
  appLifecycle('app_lifecycle'),
  nativeLifecycle('native_lifecycle'),
  nativeIncomingReport('native_incoming_report'),
  nativeOutgoingTransaction('native_outgoing_transaction'),
  nativeAudioConfiguration('native_audio_configuration'),
  nativeAudioActivation('native_audio_activation'),
  nativeActionTimeout('native_action_timeout'),
  nativeAnswerAdoptionTimeout('native_answer_adoption_timeout'),
  unknown('unknown');

  const CallEndCause(this.wireValue);
  final String wireValue;
}

enum CallEndCauseStage {
  preflight,
  authority,
  signaling,
  presentation,
  answer,
  audio,
  media,
  runtime,
  unknown,
}

enum CallRecoveryCheck {
  bindingCurrent('binding_current'),
  accountPeer('account_peer'),
  devicePeer('device_peer'),
  signingKey('signing_key'),
  kemKey('kem_key'),
  admissionAuthority('admission_authority'),
  deviceKeyEpoch('device_key_epoch'),
  preferenceEpoch('preference_epoch'),
  platform('platform'),
  routingHandle('routing_handle'),
  wakeHandle('wake_handle'),
  capabilities('capabilities'),
  trustedRoster('trusted_roster'),
  wakeGrant('wake_grant'),
  signature('signature'),
  endpointRecord('endpoint_record'),
  budget('budget'),
  unknown('unknown');

  const CallRecoveryCheck(this.wireValue);
  final String wireValue;
}

/// Observation-only values for a separate detail record, never call authority.
final class CallEndDetail {
  static const valueKeys = {'endCause', 'endCauseStage', 'recoveryCheck'};

  const CallEndDetail({
    required this.cause,
    required this.stage,
    this.recoveryCheck,
    this.elapsed = Duration.zero,
  });

  final CallEndCause cause;
  final CallEndCauseStage stage;
  final CallRecoveryCheck? recoveryCheck;
  final Duration elapsed;

  Map<String, Object?> toValues() => {
    'endCause': cause.wireValue,
    'endCauseStage': stage.name,
    if (recoveryCheck case final check?) 'recoveryCheck': check.wireValue,
    'durationMs': elapsed.inSeconds.clamp(0, 9007199254740).toInt() * 1000,
  };
}
