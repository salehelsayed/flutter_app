import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_event.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';

import 'sims_runtime_protocol.dart';

const String androidForegroundWebRtcAudioEvidenceSchema =
    'mknoon.sims.android-foreground-webrtc-audio.v2';
const String androidForegroundWebRtcAudioEndpointSchema =
    'mknoon.sims.android-foreground-webrtc-audio-endpoint.v2';
const String androidForegroundWebRtcAudioRelayEndpointSchema =
    'mknoon.sims.android-foreground-webrtc-audio-relay-endpoint.v1';
const String androidForegroundWebRtcAudioRelayEvidenceSchema =
    'mknoon.sims.android-foreground-webrtc-audio-relay.v1';
const String androidForegroundWebRtcAudioArtifactValidatorId =
    'validateForegroundWebRtcAudioCanonicalArtifactV2';
const int androidForegroundWebRtcAudioAssertionCount = 18;

const Set<String> _canonicalJourneyKeys = <String>{
  'coordinatorDriven',
  'placeInvite',
  'ringing',
  'acceptApplied',
  'encryptedSignaling',
  'noPreAcceptMedia',
  'connectedByReducer',
  'canonicalEnd',
};

const Set<String> _connectedReadinessKeys = <String>{
  'selectedPairSucceeded',
  'selectedPairNominated',
  'iceConnected',
  'dtlsReady',
  'audioSessionActive',
  'localAudioSenderAttached',
  'localAudioTrackLive',
  'remoteAudioReceiverAttached',
  'remoteAudioTrackLive',
};

const Set<String> _signalCountKeys = <String>{
  'invite',
  'ringing',
  'accept',
  'reject',
  'offer',
  'answer',
  'ice',
  'ice_restart',
  'terminate',
};

const Set<String> _endpointCleanupKeys = <String>{
  'connectionClosed',
  'audioSessionReleased',
  'bundleClosedExactlyOnce',
  'coordinatorCleanupExactlyOnce',
  'historyProjectedExactlyOnce',
  'signalingContextPurged',
  'negotiationMaterialPurged',
};

const Set<String> _probeStageNames = <String>{
  'none',
  'idle',
  'creatingConnection',
  'connectionReady',
  'samplingSnapshot',
  'snapshotSampled',
  'creatingOffer',
  'offerCreated',
  'creatingAnswer',
  'answerCreated',
  'applyingLocalDescription',
  'localDescriptionApplied',
  'applyingRemoteDescription',
  'remoteDescriptionApplied',
  'addingCandidates',
  'candidatesApplied',
};

const Set<String> _turnConfigStageNames = <String>{
  'notRequested',
  'fixtureBound',
  'bridgeAccepted',
  'providerAccepted',
  'relayPolicyApplied',
  'turnServerApplied',
  'peerConnectionCreated',
};

const Set<String> _descriptionCandidateProfileNames = <String>{
  'notCreated',
  'none',
  'relayOnly',
  'nonRelayPresent',
};

const Set<String> _descriptionSecurityProfileNames = <String>{
  'notCreated',
  'validAudioOnlySha256',
  'sha256CaseVariant',
  'fingerprintMissing',
  'fingerprintMalformed',
  'fingerprintAmbiguous',
  'videoPresent',
};

const Set<String> _readinessFailureNames = <String>{
  'notCaptured',
  'permissionNotGranted',
  'audioCaptureMissing',
  'audioCaptureMultiple',
  'videoCapturePresent',
  'audioReceiveMissing',
  'audioReceiveMultiple',
  'videoTransceiverPresent',
  'mediaNotReady',
  'iceConnectionNotReady',
  'selectedPairNotSucceeded',
  'selectedPairNotNominated',
  'dtlsNotReady',
  'audioSessionInactive',
  'localAudioSenderMissing',
  'localAudioTrackNotLive',
  'remoteAudioReceiverMissing',
  'remoteAudioTrackNotLive',
  'transportUnknown',
  'relayProtocolUnknown',
  'transportMismatch',
  'ready',
};

final class AndroidForegroundWebRtcAudioValidation {
  const AndroidForegroundWebRtcAudioValidation._(this.ok, this.detail);

  const AndroidForegroundWebRtcAudioValidation.accept()
    : this._(true, 'foreground WebRTC audio proof accepted');

  const AndroidForegroundWebRtcAudioValidation.reject(String detail)
    : this._(false, detail);

  final bool ok;
  final String detail;
}

/// Coarse execution boundary for an ephemeral failed endpoint marker.
///
/// The marker is invocation-bound and deleted during campaign cleanup. It is
/// deliberately limited to enum names so it cannot carry signaling, network,
/// credential, identity, or media material back to the host.
enum AndroidForegroundWebRtcAudioFailureStage {
  foregroundResume,
  rendezvousJoin,
  transportPrecondition,
  canonicalSetup,
  callSignaling,
  mediaReadiness,
  controls,
  directionalMedia,
  canonicalEnd,
  cleanup,
  unexpected,
}

enum AndroidForegroundWebRtcAudioRelayMode { turnUdp, turnTcp }

/// Ephemeral host input for one fresh two-peer relay case.
///
/// The invocations contain private short-lived credentials, so this object is
/// never serialized and deliberately has a redacted string representation.
final class AndroidForegroundWebRtcAudioRelayLegEvidence {
  const AndroidForegroundWebRtcAudioRelayLegEvidence({
    required this.mode,
    required this.callerEndpoint,
    required this.calleeEndpoint,
    required this.callerInvocation,
    required this.calleeInvocation,
    required this.wireSummary,
    required this.processesStopped,
    required this.runtimeFilesRemoved,
    required this.reverseMappingsRemoved,
    required this.rendezvousClosed,
    required this.appStateRestored,
  });

  final AndroidForegroundWebRtcAudioRelayMode mode;
  final Map<String, Object?> callerEndpoint;
  final Map<String, Object?> calleeEndpoint;
  final SimsRuntimeInvocation callerInvocation;
  final SimsRuntimeInvocation calleeInvocation;
  final Map<String, Object?> wireSummary;
  final bool processesStopped;
  final bool runtimeFilesRemoved;
  final bool reverseMappingsRemoved;
  final bool rendezvousClosed;
  final bool appStateRestored;

  @override
  String toString() =>
      'AndroidForegroundWebRtcAudioRelayLegEvidence(${mode.name}, redacted)';
}

final class AndroidForegroundWebRtcAudioArtifactProofs {
  const AndroidForegroundWebRtcAudioArtifactProofs({
    required this.canonical,
    required this.relay,
  });

  final Map<String, Object?> canonical;
  final Map<String, Object?> relay;
}

enum AndroidForegroundWebRtcAudioClientStage {
  none,
  joining,
  joined,
  publishingEnvelope,
  publishingControl,
  polling,
  handlingEnvelope,
  handlingControl,
  waitingControl,
  closed,
}

Map<String, Object?> androidForegroundWebRtcAudioFailedEndpoint({
  required SimsRuntimeInvocation invocation,
  required AndroidForegroundWebRtcAudioFailureStage stage,
  required String state,
  required String endReason,
  required String effect,
  required String followUp,
  String probeStage = 'none',
  String turnConfigStage = 'notRequested',
  String descriptionCandidates = 'notCreated',
  String descriptionSecurity = 'notCreated',
  String engineError = 'none',
  String readinessFailure = 'notCaptured',
  String selectedTransport = 'none',
  String selectedRelayProtocol = 'none',
  String clientStage = 'none',
  String inboundOutcome = 'none',
  int publishedControlCount = 0,
  int receivedControlCount = 0,
}) {
  final endpoint = <String, Object?>{
    'schema': androidForegroundWebRtcAudioEndpointSchema,
    'scenario': simsAndroidForegroundWebRtcAudioScenarioId,
    'status': 'failed',
    'role': invocation.role,
    'targetKind': invocation.values['targetKind'],
    'bindingSha256': androidForegroundWebRtcAudioBindingSha256(invocation),
    'failure': <String, Object?>{
      'stage': stage.name,
      'state': state,
      'endReason': endReason,
      'effect': effect,
      'followUp': followUp,
      'probeStage': probeStage,
      'turnConfigStage': turnConfigStage,
      'descriptionCandidates': descriptionCandidates,
      'descriptionSecurity': descriptionSecurity,
      'engineError': engineError,
      'readinessFailure': readinessFailure,
      'selectedTransport': selectedTransport,
      'selectedRelayProtocol': selectedRelayProtocol,
      'clientStage': clientStage,
      'inboundOutcome': inboundOutcome,
      'publishedControlCount': publishedControlCount,
      'receivedControlCount': receivedControlCount,
    },
  };
  final validation = validateAndroidForegroundWebRtcAudioFailedEndpoint(
    endpoint,
    invocation: invocation,
  );
  if (!validation.ok) throw FormatException(validation.detail);
  return Map<String, Object?>.unmodifiable(endpoint);
}

AndroidForegroundWebRtcAudioValidation
validateAndroidForegroundWebRtcAudioFailedEndpoint(
  Map<String, Object?> endpoint, {
  required SimsRuntimeInvocation invocation,
}) {
  if (!_hasExactKeys(endpoint, const <String>{
    'schema',
    'scenario',
    'status',
    'role',
    'targetKind',
    'bindingSha256',
    'failure',
  })) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC audio failed endpoint keys are not exact',
    );
  }
  final invocationValidation =
      validateAndroidForegroundWebRtcAudioRuntimeInvocation(invocation);
  if (!invocationValidation.ok) return invocationValidation;
  if (endpoint['schema'] != androidForegroundWebRtcAudioEndpointSchema ||
      endpoint['scenario'] != simsAndroidForegroundWebRtcAudioScenarioId ||
      endpoint['status'] != 'failed' ||
      endpoint['role'] != invocation.role ||
      endpoint['targetKind'] != invocation.values['targetKind'] ||
      endpoint['bindingSha256'] !=
          androidForegroundWebRtcAudioBindingSha256(invocation)) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC audio failed endpoint binding is invalid',
    );
  }
  final failure = _object(endpoint['failure']);
  if (failure == null ||
      !_hasExactKeys(failure, const <String>{
        'stage',
        'state',
        'endReason',
        'effect',
        'followUp',
        'probeStage',
        'turnConfigStage',
        'descriptionCandidates',
        'descriptionSecurity',
        'engineError',
        'readinessFailure',
        'selectedTransport',
        'selectedRelayProtocol',
        'clientStage',
        'inboundOutcome',
        'publishedControlCount',
        'receivedControlCount',
      }) ||
      !_enumName(
        failure['stage'],
        AndroidForegroundWebRtcAudioFailureStage.values,
      ) ||
      !_enumName(failure['state'], CallState.values, allowNone: true) ||
      !_enumName(failure['endReason'], CallEndReason.values, allowNone: true) ||
      !_enumName(failure['effect'], CallEffectType.values, allowNone: true) ||
      !_enumName(failure['followUp'], CallEventType.values, allowNone: true) ||
      failure['probeStage'] is! String ||
      !_probeStageNames.contains(failure['probeStage']) ||
      failure['turnConfigStage'] is! String ||
      !_turnConfigStageNames.contains(failure['turnConfigStage']) ||
      failure['descriptionCandidates'] is! String ||
      !_descriptionCandidateProfileNames.contains(
        failure['descriptionCandidates'],
      ) ||
      failure['descriptionSecurity'] is! String ||
      !_descriptionSecurityProfileNames.contains(
        failure['descriptionSecurity'],
      ) ||
      !_enumName(
        failure['engineError'],
        CallEngineErrorCode.values,
        allowNone: true,
      ) ||
      failure['readinessFailure'] is! String ||
      !_readinessFailureNames.contains(failure['readinessFailure']) ||
      !_enumName(
        failure['selectedTransport'],
        CallTransportClass.values,
        allowNone: true,
      ) ||
      !_enumName(
        failure['selectedRelayProtocol'],
        CallRelayProtocol.values,
        allowNone: true,
      ) ||
      !_enumName(
        failure['clientStage'],
        AndroidForegroundWebRtcAudioClientStage.values,
      ) ||
      failure['inboundOutcome'] is! String ||
      !const <String>{
        'none',
        'accepted',
        'duplicate',
        'rejected',
        'deferred',
      }.contains(failure['inboundOutcome']) ||
      !_isBoundedCount(failure['publishedControlCount']) ||
      !_isBoundedCount(failure['receivedControlCount'])) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC audio failed endpoint diagnostic is invalid',
    );
  }
  if (utf8.encode(jsonEncode(endpoint)).length > 1024) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC audio failed endpoint exceeds its evidence bound',
    );
  }
  return const AndroidForegroundWebRtcAudioValidation.accept();
}

AndroidForegroundWebRtcAudioValidation
validateAndroidForegroundWebRtcAudioInvocation(
  SimsRuntimeInvocation invocation,
) {
  if (invocation.profileId != simsAndroidStandardProfileId ||
      invocation.scenarioId != simsAndroidForegroundWebRtcAudioScenarioId ||
      (invocation.role != simsForegroundWebRtcCallerRole &&
          invocation.role != simsForegroundWebRtcCalleeRole)) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC audio runtime tuple is unsupported',
    );
  }
  if (!_hasExactKeys(invocation.values, const <String>{
    'rendezvousUrl',
    'bearer',
    'targetKind',
    'sharedApkSha256',
  })) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC audio runtime values are not exact',
    );
  }
  final expectedTargetKind = invocation.role == simsForegroundWebRtcCallerRole
      ? 'physical'
      : 'emulator';
  if (invocation.values['targetKind'] != expectedTargetKind ||
      !_isSha256(invocation.values['sharedApkSha256'])) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC audio target binding is invalid',
    );
  }
  final bearer = invocation.values['bearer'];
  if (bearer is! String ||
      bearer.length < 32 ||
      bearer.length > 128 ||
      !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(bearer)) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC audio authorization is invalid',
    );
  }
  final rawUrl = invocation.values['rendezvousUrl'];
  final uri = rawUrl is String ? Uri.tryParse(rawUrl) : null;
  if (uri == null ||
      uri.scheme != 'http' ||
      uri.host != '127.0.0.1' ||
      !uri.hasPort ||
      uri.port < 1024 ||
      uri.port > 65535 ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.userInfo.isNotEmpty) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC audio rendezvous is invalid',
    );
  }
  return const AndroidForegroundWebRtcAudioValidation.accept();
}

AndroidForegroundWebRtcAudioValidation
validateAndroidForegroundWebRtcAudioRelayInvocation(
  SimsRuntimeInvocation invocation,
) {
  if (invocation.profileId != simsAndroidStandardProfileId ||
      invocation.scenarioId != simsAndroidForegroundWebRtcAudioScenarioId ||
      (invocation.role != simsForegroundWebRtcCallerRole &&
          invocation.role != simsForegroundWebRtcCalleeRole) ||
      !_hasExactKeys(invocation.values, const <String>{
        'rendezvousUrl',
        'bearer',
        'targetKind',
        'sharedApkSha256',
        'relayMode',
        'turnUrls',
        'turnUsername',
        'turnPassword',
        'turnExpiresAtMs',
      })) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC relay runtime tuple is unsupported',
    );
  }
  final expectedTargetKind = invocation.role == simsForegroundWebRtcCallerRole
      ? 'physical'
      : 'emulator';
  final mode = _relayMode(invocation.values['relayMode']);
  final urls = invocation.values['turnUrls'];
  final username = invocation.values['turnUsername'];
  final password = invocation.values['turnPassword'];
  final expiresAtMs = invocation.values['turnExpiresAtMs'];
  if (invocation.values['targetKind'] != expectedTargetKind ||
      !_isSha256(invocation.values['sharedApkSha256']) ||
      mode == null ||
      urls is! List ||
      !_validTurnUrlsForMode(urls, mode) ||
      !_boundedPrivateToken(username, 512) ||
      !_boundedPrivateToken(password, 512) ||
      expiresAtMs is! int ||
      expiresAtMs <= 0) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC relay configuration is invalid',
    );
  }
  final bearer = invocation.values['bearer'];
  if (bearer is! String ||
      bearer.length < 32 ||
      bearer.length > 128 ||
      !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(bearer)) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC relay authorization is invalid',
    );
  }
  final rawRendezvous = invocation.values['rendezvousUrl'];
  final rendezvous = rawRendezvous is String
      ? Uri.tryParse(rawRendezvous)
      : null;
  if (rendezvous == null ||
      rendezvous.scheme != 'http' ||
      rendezvous.host != '127.0.0.1' ||
      !rendezvous.hasPort ||
      rendezvous.port < 1024 ||
      rendezvous.port > 65535 ||
      (rendezvous.path.isNotEmpty && rendezvous.path != '/') ||
      rendezvous.hasQuery ||
      rendezvous.hasFragment ||
      rendezvous.userInfo.isNotEmpty) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC relay rendezvous is invalid',
    );
  }
  return const AndroidForegroundWebRtcAudioValidation.accept();
}

/// Accepts exactly one of the privacy-bounded direct or relay runtime shapes.
///
/// This union is intentionally used only at the dispatcher/failure boundary;
/// each successful endpoint is still validated against its mode-specific
/// exact schema.
AndroidForegroundWebRtcAudioValidation
validateAndroidForegroundWebRtcAudioRuntimeInvocation(
  SimsRuntimeInvocation invocation,
) {
  final direct = validateAndroidForegroundWebRtcAudioInvocation(invocation);
  if (direct.ok) return direct;
  final relay = validateAndroidForegroundWebRtcAudioRelayInvocation(invocation);
  if (relay.ok) return relay;
  return const AndroidForegroundWebRtcAudioValidation.reject(
    'foreground WebRTC audio runtime tuple is unsupported',
  );
}

String androidForegroundWebRtcAudioBindingSha256(
  SimsRuntimeInvocation invocation,
) {
  final bearer = invocation.values['bearer'];
  if (bearer is! String) {
    throw const FormatException('foreground WebRTC audio binding is invalid');
  }
  return sha256
      .convert(utf8.encode('${invocation.runId}:${invocation.nonce}:$bearer'))
      .toString();
}

String androidForegroundWebRtcAudioReducerPathSha256(String role) {
  final states = switch (role) {
    simsForegroundWebRtcCallerRole => const <String>[
      'preparing',
      'inviting',
      'ringing',
      'accepted',
      'negotiating',
      'connected',
      'ended',
    ],
    simsForegroundWebRtcCalleeRole => const <String>[
      'incomingValidating',
      'ringing',
      'accepted',
      'negotiating',
      'connected',
      'ended',
    ],
    _ => throw ArgumentError.value(role, 'role', 'unsupported call role'),
  };
  return sha256.convert(utf8.encode(jsonEncode(states))).toString();
}

AndroidForegroundWebRtcAudioValidation
validateAndroidForegroundWebRtcAudioEndpoint(
  Map<String, Object?> endpoint, {
  required SimsRuntimeInvocation invocation,
}) {
  if (!_hasExactKeys(endpoint, const <String>{
    'schema',
    'scenario',
    'status',
    'role',
    'targetKind',
    'bindingSha256',
    'callBindingSha256',
    'foregroundResumed',
    'locallyAccepted',
    'permissionGranted',
    'audioOnly',
    'mediaReady',
    'directSelected',
    'bothMuted',
    'canonicalJourney',
    'connectedReadiness',
    'signalingTrace',
    'route',
    'directionalRtpDelta',
    'cleanup',
  })) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC audio endpoint keys are not exact',
    );
  }
  final invocationValidation = validateAndroidForegroundWebRtcAudioInvocation(
    invocation,
  );
  if (!invocationValidation.ok) return invocationValidation;
  final expectedTargetKind = invocation.values['targetKind'];
  if (endpoint['schema'] != androidForegroundWebRtcAudioEndpointSchema ||
      endpoint['scenario'] != simsAndroidForegroundWebRtcAudioScenarioId ||
      endpoint['status'] != 'passed' ||
      endpoint['role'] != invocation.role ||
      endpoint['targetKind'] != expectedTargetKind ||
      endpoint['bindingSha256'] !=
          androidForegroundWebRtcAudioBindingSha256(invocation) ||
      !_isSha256(endpoint['callBindingSha256'])) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC audio endpoint binding is invalid',
    );
  }
  for (final key in const <String>[
    'foregroundResumed',
    'locallyAccepted',
    'permissionGranted',
    'audioOnly',
    'mediaReady',
    'directSelected',
    'bothMuted',
  ]) {
    if (endpoint[key] != true) {
      return AndroidForegroundWebRtcAudioValidation.reject(
        'foreground WebRTC audio endpoint $key was not proven',
      );
    }
  }
  if (!_allTrue(_object(endpoint['canonicalJourney']), _canonicalJourneyKeys)) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC audio canonical journey is invalid',
    );
  }
  if (!_allTrue(
    _object(endpoint['connectedReadiness']),
    _connectedReadinessKeys,
  )) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC audio connected readiness is invalid',
    );
  }
  if (!_validSignalingTrace(
    _object(endpoint['signalingTrace']),
    role: invocation.role,
  )) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC audio signaling trace is invalid',
    );
  }
  if (!_validRoute(_object(endpoint['route']))) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC audio route proof is invalid',
    );
  }
  final directional = _object(endpoint['directionalRtpDelta']);
  if (directional == null ||
      !_hasExactKeys(directional, const <String>{
        'callerToCalleeOutbound',
        'callerToCalleeInbound',
        'calleeToCallerOutbound',
        'calleeToCallerInbound',
      }) ||
      directional.values.any((value) => value is! bool)) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC audio directional proof is invalid',
    );
  }
  final cleanup = _object(endpoint['cleanup']);
  if (!_allTrue(cleanup, _endpointCleanupKeys)) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC audio endpoint cleanup is invalid',
    );
  }
  if (utf8.encode(jsonEncode(endpoint)).length > 4096) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC audio endpoint exceeds its evidence bound',
    );
  }
  return const AndroidForegroundWebRtcAudioValidation.accept();
}

AndroidForegroundWebRtcAudioValidation
validateAndroidForegroundWebRtcAudioRelayEndpoint(
  Map<String, Object?> endpoint, {
  required SimsRuntimeInvocation invocation,
}) {
  if (!_hasExactKeys(endpoint, const <String>{
    'schema',
    'scenario',
    'status',
    'role',
    'targetKind',
    'relayMode',
    'bindingSha256',
    'callBindingSha256',
    'foregroundResumed',
    'locallyAccepted',
    'permissionGranted',
    'audioOnly',
    'mediaReady',
    'bothMuted',
    'canonicalJourney',
    'connectedReadiness',
    'signalingTrace',
    'bridgeCredentialPath',
    'relayPrivacy',
    'selectedTransport',
    'selectedRelayProtocol',
    'tcpFallbackPrecondition',
    'directionalRtpDelta',
    'acceptToAudioMs',
    'cleanup',
  })) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC relay endpoint keys are not exact',
    );
  }
  final invocationValidation =
      validateAndroidForegroundWebRtcAudioRelayInvocation(invocation);
  if (!invocationValidation.ok) return invocationValidation;
  final mode = _relayMode(invocation.values['relayMode'])!;
  final expectedTransport = switch (mode) {
    AndroidForegroundWebRtcAudioRelayMode.turnUdp => 'turnUdp',
    AndroidForegroundWebRtcAudioRelayMode.turnTcp => 'turnTcpTls',
  };
  final expectedProtocol = switch (mode) {
    AndroidForegroundWebRtcAudioRelayMode.turnUdp => 'udp',
    AndroidForegroundWebRtcAudioRelayMode.turnTcp => 'tcp',
  };
  if (endpoint['schema'] != androidForegroundWebRtcAudioRelayEndpointSchema ||
      endpoint['scenario'] != simsAndroidForegroundWebRtcAudioScenarioId ||
      endpoint['status'] != 'passed' ||
      endpoint['role'] != invocation.role ||
      endpoint['targetKind'] != invocation.values['targetKind'] ||
      endpoint['relayMode'] != mode.name ||
      endpoint['bindingSha256'] !=
          androidForegroundWebRtcAudioBindingSha256(invocation) ||
      !_isSha256(endpoint['callBindingSha256']) ||
      endpoint['selectedTransport'] != expectedTransport ||
      endpoint['selectedRelayProtocol'] != expectedProtocol) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC relay endpoint binding is invalid',
    );
  }
  final tcpFallback = _object(endpoint['tcpFallbackPrecondition']);
  if (tcpFallback == null ||
      !_hasExactKeys(tcpFallback, const <String>{
        'applied',
        'udpProbeAttempts',
        'udpStunResponseAbsent',
        'tcpReachable',
      })) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC relay fallback evidence is invalid',
    );
  }
  final fallbackValid = switch (mode) {
    AndroidForegroundWebRtcAudioRelayMode.turnUdp =>
      tcpFallback['applied'] == false &&
          tcpFallback['udpProbeAttempts'] == 0 &&
          tcpFallback['udpStunResponseAbsent'] == false &&
          tcpFallback['tcpReachable'] == false,
    AndroidForegroundWebRtcAudioRelayMode.turnTcp =>
      tcpFallback['applied'] == true &&
          tcpFallback['udpProbeAttempts'] == 3 &&
          tcpFallback['udpStunResponseAbsent'] == true &&
          tcpFallback['tcpReachable'] == true,
  };
  if (!fallbackValid) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC relay fallback was not proven',
    );
  }
  for (final key in const <String>{
    'foregroundResumed',
    'locallyAccepted',
    'permissionGranted',
    'audioOnly',
    'mediaReady',
    'bothMuted',
  }) {
    if (endpoint[key] != true) {
      return AndroidForegroundWebRtcAudioValidation.reject(
        'foreground WebRTC relay endpoint $key was not proven',
      );
    }
  }
  if (!_allTrue(_object(endpoint['canonicalJourney']), _canonicalJourneyKeys) ||
      !_allTrue(
        _object(endpoint['connectedReadiness']),
        _connectedReadinessKeys,
      ) ||
      !_validSignalingTrace(
        _object(endpoint['signalingTrace']),
        role: invocation.role,
      ) ||
      !_allTrue(_object(endpoint['bridgeCredentialPath']), const <String>{
        'commandExact',
        'providerReadExactlyOnce',
        'preparerRequiredTurn',
        'modeBoundTransportOptions',
      }) ||
      !_allTrue(_object(endpoint['relayPrivacy']), const <String>{
        'transportPolicyRelayOnly',
        'relayCandidateSignaled',
        'trickleNonRelayCountZero',
        'embeddedSdpNonRelayCountZero',
      })) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC relay endpoint path is invalid',
    );
  }
  final directional = _object(endpoint['directionalRtpDelta']);
  if (directional == null ||
      !_hasExactKeys(directional, const <String>{
        'callerToCalleeOutbound',
        'callerToCalleeInbound',
        'calleeToCallerOutbound',
        'calleeToCallerInbound',
      }) ||
      directional.values.any((value) => value is! bool)) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC relay directional proof is invalid',
    );
  }
  final latency = endpoint['acceptToAudioMs'];
  if (latency is! int || latency <= 0 || latency > 120000) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC relay latency is invalid',
    );
  }
  if (!_allTrue(_object(endpoint['cleanup']), _endpointCleanupKeys)) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC relay endpoint cleanup is invalid',
    );
  }
  final encoded = jsonEncode(endpoint);
  if (utf8.encode(encoded).length > 4096 ||
      _containsForbiddenDurableMaterial(endpoint) ||
      RegExp(
        r'"(?:sdp|candidates?|addresses?|urls?|usernames?|passwords?|credentials?|secrets?|rawAudio|rtpCounters?)"\s*:',
        caseSensitive: false,
      ).hasMatch(encoded)) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC relay endpoint violates its privacy bound',
    );
  }
  return const AndroidForegroundWebRtcAudioValidation.accept();
}

/// A valid transport campaign can still miss the product's latency target.
/// Keep that failure distinct from malformed evidence without relaxing the gate.
final class AndroidForegroundWebRtcAudioLatencyExceeded
    extends FormatException {
  const AndroidForegroundWebRtcAudioLatencyExceeded(this.p95Ms)
    : super('foreground WebRTC relay campaign p95 exceeded the product target');

  static const thresholdMs = 3000;
  final int p95Ms;
}

Map<String, Object?> aggregateAndroidForegroundWebRtcAudioRelayEvidence({
  required List<AndroidForegroundWebRtcAudioRelayLegEvidence> legs,
  required String sharedApkSha256,
}) {
  if (!_isSha256(sharedApkSha256) ||
      legs.length != AndroidForegroundWebRtcAudioRelayMode.values.length ||
      legs.map((leg) => leg.mode).toSet().length != legs.length ||
      !AndroidForegroundWebRtcAudioRelayMode.values.every(
        (mode) => legs.any((leg) => leg.mode == mode),
      )) {
    throw const FormatException(
      'foreground WebRTC relay case matrix is invalid',
    );
  }

  final modes = <String, Object?>{};
  final latencySamples = <int>[];
  for (final mode in AndroidForegroundWebRtcAudioRelayMode.values) {
    final leg = legs.singleWhere((candidate) => candidate.mode == mode);
    final callerInvocation = leg.callerInvocation;
    final calleeInvocation = leg.calleeInvocation;
    if (callerInvocation.role != simsForegroundWebRtcCallerRole ||
        calleeInvocation.role != simsForegroundWebRtcCalleeRole ||
        callerInvocation.values['relayMode'] != mode.name ||
        calleeInvocation.values['relayMode'] != mode.name ||
        callerInvocation.values['sharedApkSha256'] != sharedApkSha256 ||
        calleeInvocation.values['sharedApkSha256'] != sharedApkSha256 ||
        !validateAndroidForegroundWebRtcAudioRelayEndpoint(
          leg.callerEndpoint,
          invocation: callerInvocation,
        ).ok ||
        !validateAndroidForegroundWebRtcAudioRelayEndpoint(
          leg.calleeEndpoint,
          invocation: calleeInvocation,
        ).ok) {
      throw const FormatException(
        'foreground WebRTC relay endpoint evidence was rejected',
      );
    }
    final callBinding = leg.callerEndpoint['callBindingSha256'];
    if (!_isSha256(callBinding) ||
        callBinding != leg.calleeEndpoint['callBindingSha256'] ||
        !_validEnvelopeBindings(leg.wireSummary)) {
      throw const FormatException(
        'foreground WebRTC relay bindings do not converge',
      );
    }
    final callerTrace = _object(leg.callerEndpoint['signalingTrace'])!;
    final calleeTrace = _object(leg.calleeEndpoint['signalingTrace'])!;
    final callerToCallee = _object(leg.wireSummary['callerToCallee'])!;
    final calleeToCaller = _object(leg.wireSummary['calleeToCaller'])!;
    if (!_matchesEnvelopeDirection(
          outboundTrace: callerTrace,
          wire: callerToCallee,
          inboundTrace: calleeTrace,
        ) ||
        !_matchesEnvelopeDirection(
          outboundTrace: calleeTrace,
          wire: calleeToCaller,
          inboundTrace: callerTrace,
        ) ||
        !leg.processesStopped ||
        !leg.runtimeFilesRemoved ||
        !leg.reverseMappingsRemoved ||
        !leg.rendezvousClosed ||
        !leg.appStateRestored) {
      throw const FormatException(
        'foreground WebRTC relay host boundary was not restored',
      );
    }

    final callerDirectional = _object(
      leg.callerEndpoint['directionalRtpDelta'],
    )!;
    final calleeDirectional = _object(
      leg.calleeEndpoint['directionalRtpDelta'],
    )!;
    final callerBridge = _object(leg.callerEndpoint['bridgeCredentialPath'])!;
    final calleeBridge = _object(leg.calleeEndpoint['bridgeCredentialPath'])!;
    final callerPrivacy = _object(leg.callerEndpoint['relayPrivacy'])!;
    final calleePrivacy = _object(leg.calleeEndpoint['relayPrivacy'])!;
    final callerFallback = _object(
      leg.callerEndpoint['tcpFallbackPrecondition'],
    )!;
    final calleeFallback = _object(
      leg.calleeEndpoint['tcpFallbackPrecondition'],
    )!;
    final callerLatency = leg.callerEndpoint['acceptToAudioMs']! as int;
    final calleeLatency = leg.calleeEndpoint['acceptToAudioMs']! as int;
    latencySamples.addAll(<int>[callerLatency, calleeLatency]);
    modes[mode.name] = <String, Object?>{
      'callBindingSha256': callBinding,
      'selectedTransport': <String, Object?>{
        'caller': leg.callerEndpoint['selectedTransport'],
        'callee': leg.calleeEndpoint['selectedTransport'],
      },
      'selectedRelayProtocol': <String, Object?>{
        'caller': leg.callerEndpoint['selectedRelayProtocol'],
        'callee': leg.calleeEndpoint['selectedRelayProtocol'],
      },
      'tcpFallbackPrecondition': <String, Object?>{
        'caller': Map<String, Object?>.from(callerFallback),
        'callee': Map<String, Object?>.from(calleeFallback),
      },
      'bridgeCredentialPath': <String, Object?>{
        for (final key in const <String>{
          'commandExact',
          'providerReadExactlyOnce',
          'preparerRequiredTurn',
          'modeBoundTransportOptions',
        })
          key: callerBridge[key] == true && calleeBridge[key] == true,
      },
      'relayPrivacy': <String, Object?>{
        for (final key in const <String>{
          'transportPolicyRelayOnly',
          'relayCandidateSignaled',
          'trickleNonRelayCountZero',
          'embeddedSdpNonRelayCountZero',
        })
          key: callerPrivacy[key] == true && calleePrivacy[key] == true,
      },
      'directionalRtpDelta': <String, Object?>{
        'callerToCallee':
            callerDirectional['callerToCalleeOutbound'] == true &&
            calleeDirectional['callerToCalleeInbound'] == true,
        'calleeToCaller':
            calleeDirectional['calleeToCallerOutbound'] == true &&
            callerDirectional['calleeToCallerInbound'] == true,
      },
      'latencySamplesMs': <String, Object?>{
        'caller': callerLatency,
        'callee': calleeLatency,
      },
      'cleanup': <String, Object?>{
        'endpointCleanupExactlyOnce': true,
        'processesStopped': leg.processesStopped,
        'runtimeFilesRemoved': leg.runtimeFilesRemoved,
        'reverseMappingsRemoved': leg.reverseMappingsRemoved,
        'rendezvousClosed': leg.rendezvousClosed,
        'appStateRestored': leg.appStateRestored,
      },
    };
  }

  latencySamples.sort();
  const percentile = 95;
  final rank = (percentile * latencySamples.length + 99) ~/ 100;
  final p95Ms = latencySamples[rank - 1];
  const thresholdMs = AndroidForegroundWebRtcAudioLatencyExceeded.thresholdMs;
  if (p95Ms > thresholdMs) {
    throw AndroidForegroundWebRtcAudioLatencyExceeded(p95Ms);
  }
  final evidence = <String, Object?>{
    'schema': androidForegroundWebRtcAudioRelayEvidenceSchema,
    'scenario': simsAndroidForegroundWebRtcAudioScenarioId,
    'status': 'passed',
    'platform': 'android',
    'profileId': simsAndroidStandardProfileId,
    'runtimeDispatched': true,
    'sharedApkSha256': sharedApkSha256,
    'modes': modes,
    'latencyMeasurement': <String, Object?>{
      'metric': 'acceptToBidirectionalRtpReady',
      'sampleCount': latencySamples.length,
      'percentile': percentile,
      'method': 'nearestRank',
      'p95Ms': p95Ms,
      'thresholdMs': thresholdMs,
      'withinTarget': true,
      'confidence': 'campaignSampleLimited',
    },
    'claimsBoundary': const <String, Object?>{
      'hostMintedAuthenticatedTurn': true,
      'nativeGoIssuanceProven': false,
      'turnEndpointUdpUnavailableProven': true,
      'selectedTcpRelayProven': true,
      'osUdpBlockingProven': false,
      'tlsProven': false,
    },
    'relayCasesAttempted': AndroidForegroundWebRtcAudioRelayMode.values.length,
  };
  final validation = validateAndroidForegroundWebRtcAudioRelayEvidence(
    evidence,
  );
  if (!validation.ok) throw FormatException(validation.detail);
  return evidence;
}

AndroidForegroundWebRtcAudioValidation
validateAndroidForegroundWebRtcAudioRelayEvidence(
  Map<String, Object?> evidence,
) {
  if (!_hasExactKeys(evidence, const <String>{
        'schema',
        'scenario',
        'status',
        'platform',
        'profileId',
        'runtimeDispatched',
        'sharedApkSha256',
        'modes',
        'latencyMeasurement',
        'claimsBoundary',
        'relayCasesAttempted',
      }) ||
      evidence['schema'] != androidForegroundWebRtcAudioRelayEvidenceSchema ||
      evidence['scenario'] != simsAndroidForegroundWebRtcAudioScenarioId ||
      evidence['status'] != 'passed' ||
      evidence['platform'] != 'android' ||
      evidence['profileId'] != simsAndroidStandardProfileId ||
      evidence['runtimeDispatched'] != true ||
      !_isSha256(evidence['sharedApkSha256']) ||
      evidence['relayCasesAttempted'] != 2) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC relay evidence header is invalid',
    );
  }
  final modes = _object(evidence['modes']);
  if (modes == null ||
      !_hasExactKeys(
        modes,
        AndroidForegroundWebRtcAudioRelayMode.values
            .map((mode) => mode.name)
            .toSet(),
      )) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC relay modes are invalid',
    );
  }
  final samples = <int>[];
  for (final mode in AndroidForegroundWebRtcAudioRelayMode.values) {
    final value = _object(modes[mode.name]);
    if (value == null ||
        !_hasExactKeys(value, const <String>{
          'callBindingSha256',
          'selectedTransport',
          'selectedRelayProtocol',
          'tcpFallbackPrecondition',
          'bridgeCredentialPath',
          'relayPrivacy',
          'directionalRtpDelta',
          'latencySamplesMs',
          'cleanup',
        }) ||
        !_isSha256(value['callBindingSha256'])) {
      return const AndroidForegroundWebRtcAudioValidation.reject(
        'foreground WebRTC relay mode binding is invalid',
      );
    }
    final expectedTransport = switch (mode) {
      AndroidForegroundWebRtcAudioRelayMode.turnUdp => 'turnUdp',
      AndroidForegroundWebRtcAudioRelayMode.turnTcp => 'turnTcpTls',
    };
    final expectedProtocol = switch (mode) {
      AndroidForegroundWebRtcAudioRelayMode.turnUdp => 'udp',
      AndroidForegroundWebRtcAudioRelayMode.turnTcp => 'tcp',
    };
    final selected = _object(value['selectedTransport']);
    final selectedProtocol = _object(value['selectedRelayProtocol']);
    final fallback = _object(value['tcpFallbackPrecondition']);
    final latency = _object(value['latencySamplesMs']);
    if (selected == null ||
        !_hasExactKeys(selected, const <String>{'caller', 'callee'}) ||
        selected.values.any((entry) => entry != expectedTransport) ||
        selectedProtocol == null ||
        !_hasExactKeys(selectedProtocol, const <String>{'caller', 'callee'}) ||
        selectedProtocol.values.any((entry) => entry != expectedProtocol) ||
        fallback == null ||
        !_hasExactKeys(fallback, const <String>{'caller', 'callee'}) ||
        !_validTcpFallbackPrecondition(_object(fallback['caller']), mode) ||
        !_validTcpFallbackPrecondition(_object(fallback['callee']), mode) ||
        !_allTrue(_object(value['bridgeCredentialPath']), const <String>{
          'commandExact',
          'providerReadExactlyOnce',
          'preparerRequiredTurn',
          'modeBoundTransportOptions',
        }) ||
        !_allTrue(_object(value['relayPrivacy']), const <String>{
          'transportPolicyRelayOnly',
          'relayCandidateSignaled',
          'trickleNonRelayCountZero',
          'embeddedSdpNonRelayCountZero',
        }) ||
        !_allTrue(_object(value['directionalRtpDelta']), const <String>{
          'callerToCallee',
          'calleeToCaller',
        }) ||
        latency == null ||
        !_hasExactKeys(latency, const <String>{'caller', 'callee'}) ||
        latency.values.any(
          (entry) => entry is! int || entry <= 0 || entry > 120000,
        ) ||
        !_allTrue(_object(value['cleanup']), const <String>{
          'endpointCleanupExactlyOnce',
          'processesStopped',
          'runtimeFilesRemoved',
          'reverseMappingsRemoved',
          'rendezvousClosed',
          'appStateRestored',
        })) {
      return const AndroidForegroundWebRtcAudioValidation.reject(
        'foreground WebRTC relay mode proof is invalid',
      );
    }
    samples.add(latency['caller']! as int);
    samples.add(latency['callee']! as int);
  }
  samples.sort();
  final p95Ms = samples[((95 * samples.length + 99) ~/ 100) - 1];
  final measurement = _object(evidence['latencyMeasurement']);
  if (measurement == null ||
      !_hasExactKeys(measurement, const <String>{
        'metric',
        'sampleCount',
        'percentile',
        'method',
        'p95Ms',
        'thresholdMs',
        'withinTarget',
        'confidence',
      }) ||
      measurement['metric'] != 'acceptToBidirectionalRtpReady' ||
      measurement['sampleCount'] != 4 ||
      measurement['percentile'] != 95 ||
      measurement['method'] != 'nearestRank' ||
      measurement['p95Ms'] != p95Ms ||
      measurement['thresholdMs'] != 3000 ||
      measurement['withinTarget'] != true ||
      measurement['confidence'] != 'campaignSampleLimited' ||
      p95Ms > 3000) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC relay latency measurement is invalid',
    );
  }
  final claims = _object(evidence['claimsBoundary']);
  if (claims == null ||
      !_hasExactKeys(claims, const <String>{
        'hostMintedAuthenticatedTurn',
        'nativeGoIssuanceProven',
        'turnEndpointUdpUnavailableProven',
        'selectedTcpRelayProven',
        'osUdpBlockingProven',
        'tlsProven',
      }) ||
      claims['hostMintedAuthenticatedTurn'] != true ||
      claims['nativeGoIssuanceProven'] != false ||
      claims['turnEndpointUdpUnavailableProven'] != true ||
      claims['selectedTcpRelayProven'] != true ||
      claims['osUdpBlockingProven'] != false ||
      claims['tlsProven'] != false) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC relay claims boundary is invalid',
    );
  }
  final encoded = jsonEncode(evidence);
  if (utf8.encode(encoded).length > 8192 ||
      _containsForbiddenDurableMaterial(evidence) ||
      RegExp(
        r'"(?:sdp|candidates?|addresses?|urls?|usernames?|passwords?|credentials?|secrets?|rawAudio|rtpCounters?)"\s*:',
        caseSensitive: false,
      ).hasMatch(encoded)) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC relay evidence violates its privacy bound',
    );
  }
  return const AndroidForegroundWebRtcAudioValidation.accept();
}

Map<String, Object?> aggregateAndroidForegroundWebRtcAudioEvidence({
  required Map<String, Object?> callerEndpoint,
  required Map<String, Object?> calleeEndpoint,
  required SimsRuntimeInvocation callerInvocation,
  required SimsRuntimeInvocation calleeInvocation,
  required Map<String, Object?> wireSummary,
  required String sharedApkSha256,
  required String physicalTargetDigest,
  required String emulatorTargetDigest,
  required bool processesStopped,
  required bool runtimeFilesRemoved,
  required bool reverseMappingsRemoved,
  required bool rendezvousClosed,
  required bool appStateRestored,
}) {
  if (callerInvocation.role != simsForegroundWebRtcCallerRole ||
      calleeInvocation.role != simsForegroundWebRtcCalleeRole ||
      callerInvocation.values['sharedApkSha256'] != sharedApkSha256 ||
      calleeInvocation.values['sharedApkSha256'] != sharedApkSha256) {
    throw const FormatException(
      'foreground WebRTC audio aggregate runtime binding is invalid',
    );
  }
  final callerValidation = validateAndroidForegroundWebRtcAudioEndpoint(
    callerEndpoint,
    invocation: callerInvocation,
  );
  final calleeValidation = validateAndroidForegroundWebRtcAudioEndpoint(
    calleeEndpoint,
    invocation: calleeInvocation,
  );
  if (!callerValidation.ok || !calleeValidation.ok) {
    throw const FormatException(
      'foreground WebRTC audio endpoint evidence was rejected',
    );
  }
  final callerCallBinding = callerEndpoint['callBindingSha256'];
  final calleeCallBinding = calleeEndpoint['callBindingSha256'];
  if (callerCallBinding != calleeCallBinding || !_isSha256(callerCallBinding)) {
    throw const FormatException(
      'foreground WebRTC audio call binding does not converge',
    );
  }
  if (!_validEnvelopeBindings(wireSummary)) {
    throw const FormatException(
      'foreground WebRTC audio wire summary is invalid',
    );
  }

  final callerTrace = _object(callerEndpoint['signalingTrace'])!;
  final calleeTrace = _object(calleeEndpoint['signalingTrace'])!;
  final callerToCallee = _object(wireSummary['callerToCallee'])!;
  final calleeToCaller = _object(wireSummary['calleeToCaller'])!;
  if (!_matchesEnvelopeDirection(
        outboundTrace: callerTrace,
        wire: callerToCallee,
        inboundTrace: calleeTrace,
      ) ||
      !_matchesEnvelopeDirection(
        outboundTrace: calleeTrace,
        wire: calleeToCaller,
        inboundTrace: callerTrace,
      )) {
    throw const FormatException(
      'foreground WebRTC audio envelope bindings do not converge',
    );
  }

  final callerDirectional = _object(callerEndpoint['directionalRtpDelta'])!;
  final calleeDirectional = _object(calleeEndpoint['directionalRtpDelta'])!;
  final callerRoute = _object(callerEndpoint['route'])!;
  final calleeRoute = _object(calleeEndpoint['route'])!;
  final callerCleanup = _object(callerEndpoint['cleanup'])!;
  final calleeCleanup = _object(calleeEndpoint['cleanup'])!;
  final callerJourney = _object(callerEndpoint['canonicalJourney'])!;
  final calleeJourney = _object(calleeEndpoint['canonicalJourney'])!;
  final callerReadiness = _object(callerEndpoint['connectedReadiness'])!;
  final calleeReadiness = _object(calleeEndpoint['connectedReadiness'])!;

  final evidence = <String, Object?>{
    'schema': androidForegroundWebRtcAudioEvidenceSchema,
    'scenario': simsAndroidForegroundWebRtcAudioScenarioId,
    'status': 'passed',
    'platform': 'android',
    'profileId': simsAndroidStandardProfileId,
    'runtimeDispatched': true,
    'sharedApkSha256': sharedApkSha256,
    'callBindingSha256': callerCallBinding,
    'targetKindDigests': <String, Object?>{
      'physical': physicalTargetDigest,
      'emulator': emulatorTargetDigest,
    },
    'foregroundResumed': <String, Object?>{
      'caller': callerEndpoint['foregroundResumed'],
      'callee': calleeEndpoint['foregroundResumed'],
    },
    'locallyAccepted': <String, Object?>{
      'caller': callerEndpoint['locallyAccepted'],
      'callee': calleeEndpoint['locallyAccepted'],
    },
    'permissionGranted': <String, Object?>{
      'caller': callerEndpoint['permissionGranted'],
      'callee': calleeEndpoint['permissionGranted'],
    },
    'audioOnly': <String, Object?>{
      'caller': callerEndpoint['audioOnly'],
      'callee': calleeEndpoint['audioOnly'],
    },
    'mediaReady': <String, Object?>{
      'caller': callerEndpoint['mediaReady'],
      'callee': calleeEndpoint['mediaReady'],
    },
    'directSelected': <String, Object?>{
      'caller': callerEndpoint['directSelected'],
      'callee': calleeEndpoint['directSelected'],
    },
    'bothMuted':
        callerEndpoint['bothMuted'] == true &&
        calleeEndpoint['bothMuted'] == true,
    'canonicalJourney': <String, Object?>{
      for (final key in _canonicalJourneyKeys)
        key: callerJourney[key] == true && calleeJourney[key] == true,
    },
    'connectedReadiness': <String, Object?>{
      for (final key in _connectedReadinessKeys)
        key: callerReadiness[key] == true && calleeReadiness[key] == true,
    },
    'envelopeBindings': <String, Object?>{
      'callerToCallee': Map<String, Object?>.from(callerToCallee),
      'calleeToCaller': Map<String, Object?>.from(calleeToCaller),
    },
    'directionalRtpDelta': <String, Object?>{
      'callerToCallee':
          callerDirectional['callerToCalleeOutbound'] == true &&
          calleeDirectional['callerToCalleeInbound'] == true,
      'calleeToCaller':
          calleeDirectional['calleeToCallerOutbound'] == true &&
          callerDirectional['calleeToCallerInbound'] == true,
    },
    'routeClasses': <String, Object?>{
      'caller': <String, Object?>{
        'speakerSupported': callerRoute['speakerSupported'],
        'speakerSelected': callerRoute['speakerSelected'],
        'finalRoute': callerRoute['finalRoute'],
      },
      'callee': <String, Object?>{
        'speakerSupported': calleeRoute['speakerSupported'],
        'speakerSelected': calleeRoute['speakerSelected'],
        'finalRoute': calleeRoute['finalRoute'],
      },
    },
    'cleanup': <String, Object?>{
      'connectionsClosed':
          callerCleanup['connectionClosed'] == true &&
          calleeCleanup['connectionClosed'] == true,
      'audioSessionsReleased':
          callerCleanup['audioSessionReleased'] == true &&
          calleeCleanup['audioSessionReleased'] == true,
      'endpointCleanupExactlyOnce':
          callerCleanup['bundleClosedExactlyOnce'] == true &&
          callerCleanup['coordinatorCleanupExactlyOnce'] == true &&
          callerCleanup['historyProjectedExactlyOnce'] == true &&
          calleeCleanup['bundleClosedExactlyOnce'] == true &&
          calleeCleanup['coordinatorCleanupExactlyOnce'] == true &&
          calleeCleanup['historyProjectedExactlyOnce'] == true,
      'processesStopped': processesStopped,
      'runtimeFilesRemoved': runtimeFilesRemoved,
      'reverseMappingsRemoved': reverseMappingsRemoved,
      'rendezvousClosed': rendezvousClosed,
      'appStateRestored': appStateRestored,
    },
    'assertionsAttempted': androidForegroundWebRtcAudioAssertionCount,
  };
  final validation = validateAndroidForegroundWebRtcAudioEvidence(evidence);
  if (!validation.ok) throw FormatException(validation.detail);
  return evidence;
}

AndroidForegroundWebRtcAudioValidation
validateAndroidForegroundWebRtcAudioEvidence(Map<String, Object?> evidence) {
  if (!_hasExactKeys(evidence, const <String>{
    'schema',
    'scenario',
    'status',
    'platform',
    'profileId',
    'runtimeDispatched',
    'sharedApkSha256',
    'callBindingSha256',
    'targetKindDigests',
    'foregroundResumed',
    'locallyAccepted',
    'permissionGranted',
    'audioOnly',
    'mediaReady',
    'directSelected',
    'bothMuted',
    'canonicalJourney',
    'connectedReadiness',
    'envelopeBindings',
    'directionalRtpDelta',
    'routeClasses',
    'cleanup',
    'assertionsAttempted',
  })) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC audio evidence keys are not exact',
    );
  }
  if (evidence['schema'] != androidForegroundWebRtcAudioEvidenceSchema ||
      evidence['scenario'] != simsAndroidForegroundWebRtcAudioScenarioId ||
      evidence['status'] != 'passed' ||
      evidence['platform'] != 'android' ||
      evidence['profileId'] != simsAndroidStandardProfileId ||
      evidence['runtimeDispatched'] != true ||
      !_isSha256(evidence['sharedApkSha256']) ||
      !_isSha256(evidence['callBindingSha256']) ||
      evidence['bothMuted'] != true ||
      evidence['assertionsAttempted'] !=
          androidForegroundWebRtcAudioAssertionCount) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC audio evidence header is invalid',
    );
  }
  final targetDigests = _object(evidence['targetKindDigests']);
  if (targetDigests == null ||
      !_hasExactKeys(targetDigests, const <String>{'physical', 'emulator'}) ||
      !_isSha256(targetDigests['physical']) ||
      !_isSha256(targetDigests['emulator']) ||
      targetDigests['physical'] == targetDigests['emulator']) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC audio target digests are invalid',
    );
  }
  for (final key in const <String>[
    'foregroundResumed',
    'locallyAccepted',
    'permissionGranted',
    'audioOnly',
    'mediaReady',
    'directSelected',
  ]) {
    if (!_bothTrue(_object(evidence[key]))) {
      return AndroidForegroundWebRtcAudioValidation.reject(
        'foreground WebRTC audio $key evidence is invalid',
      );
    }
  }
  if (!_allTrue(_object(evidence['canonicalJourney']), _canonicalJourneyKeys)) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC audio canonical journey evidence is invalid',
    );
  }
  if (!_allTrue(
    _object(evidence['connectedReadiness']),
    _connectedReadinessKeys,
  )) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC audio connected readiness evidence is invalid',
    );
  }
  final envelopeBindings = _object(evidence['envelopeBindings']);
  if (envelopeBindings == null || !_validEnvelopeBindings(envelopeBindings)) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC audio envelope binding evidence is invalid',
    );
  }
  final directional = _object(evidence['directionalRtpDelta']);
  if (directional == null ||
      !_hasExactKeys(directional, const <String>{
        'callerToCallee',
        'calleeToCaller',
      }) ||
      directional.values.any((value) => value != true)) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC audio directional RTP evidence is invalid',
    );
  }
  final routes = _object(evidence['routeClasses']);
  if (routes == null ||
      !_hasExactKeys(routes, const <String>{'caller', 'callee'}) ||
      !_validRoute(_object(routes['caller'])) ||
      !_validRoute(_object(routes['callee']))) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC audio route evidence is invalid',
    );
  }
  final cleanup = _object(evidence['cleanup']);
  if (!_allTrue(cleanup, const <String>{
    'connectionsClosed',
    'audioSessionsReleased',
    'endpointCleanupExactlyOnce',
    'processesStopped',
    'runtimeFilesRemoved',
    'reverseMappingsRemoved',
    'rendezvousClosed',
    'appStateRestored',
  })) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC audio cleanup evidence is invalid',
    );
  }
  final encoded = jsonEncode(evidence);
  if (utf8.encode(encoded).length > 4096 ||
      _containsForbiddenDurableMaterial(evidence) ||
      RegExp(
        r'"(?:sdp|descriptions?|iceCandidates?|candidates?|addresses?|ip|ports?|deviceIds?|tokens?|peerIds?|identities?|credentials?|secrets?|rawEnvelopes?|rawAudio|audioSamples?|rtpCounters?)"\s*:',
        caseSensitive: false,
      ).hasMatch(encoded)) {
    return const AndroidForegroundWebRtcAudioValidation.reject(
      'foreground WebRTC audio evidence violates its privacy bound',
    );
  }
  return const AndroidForegroundWebRtcAudioValidation.accept();
}

Map<String, Object?> androidForegroundWebRtcAudioDurablePayload(
  Map<String, Object?> evidence,
) {
  final validation = validateAndroidForegroundWebRtcAudioEvidence(evidence);
  if (!validation.ok) throw FormatException(validation.detail);
  return Map<String, Object?>.unmodifiable(evidence);
}

Map<String, Object?> androidForegroundWebRtcAudioRelayDurablePayload(
  Map<String, Object?> evidence,
) {
  final validation = validateAndroidForegroundWebRtcAudioRelayEvidence(
    evidence,
  );
  if (!validation.ok) throw FormatException(validation.detail);
  return Map<String, Object?>.unmodifiable(evidence);
}

Map<String, Object?> androidForegroundWebRtcAudioArtifactPayload({
  required Map<String, Object?> canonical,
  required Map<String, Object?> relay,
}) => <String, Object?>{
  'canonical': androidForegroundWebRtcAudioDurablePayload(canonical),
  'relay': androidForegroundWebRtcAudioRelayDurablePayload(relay),
};

AndroidForegroundWebRtcAudioArtifactProofs
androidForegroundWebRtcAudioProofsFromArtifact(Map<String, Object?> artifact) {
  if (!_hasExactKeys(artifact, const <String>{
        'schema',
        'capabilityId',
        'validatorIds',
        'canonical',
        'relay',
      }) ||
      artifact['schema'] != 'mknoon.sims.proof.v1' ||
      artifact['capabilityId'] != simsAndroidForegroundWebRtcAudioScenarioId ||
      !_sameOrderedStrings(artifact['validatorIds'], const <String>[
        androidForegroundWebRtcAudioArtifactValidatorId,
      ])) {
    throw const FormatException(
      'foreground WebRTC audio artifact envelope is invalid',
    );
  }
  final canonical = _object(artifact['canonical']);
  final relay = _object(artifact['relay']);
  if (canonical == null || relay == null) {
    throw const FormatException(
      'foreground WebRTC audio artifact proof is missing',
    );
  }
  final canonicalValidation = validateAndroidForegroundWebRtcAudioEvidence(
    canonical,
  );
  final relayValidation = validateAndroidForegroundWebRtcAudioRelayEvidence(
    relay,
  );
  if (!canonicalValidation.ok || !relayValidation.ok) {
    throw const FormatException(
      'foreground WebRTC audio artifact proof is invalid',
    );
  }
  if (canonical['sharedApkSha256'] != relay['sharedApkSha256'] ||
      utf8.encode(jsonEncode(artifact)).length > 12288 ||
      _containsForbiddenDurableMaterial(artifact)) {
    throw const FormatException(
      'foreground WebRTC audio artifact binding is invalid',
    );
  }
  return AndroidForegroundWebRtcAudioArtifactProofs(
    canonical: Map<String, Object?>.unmodifiable(canonical),
    relay: Map<String, Object?>.unmodifiable(relay),
  );
}

/// Extracts the canonical v2 proof from the generic SIMS artifact envelope.
///
/// The shared artifact writer owns the outer `mknoon.sims.proof.v1` schema, so
/// the capability-specific proof must remain under the exact `proof` key.
Map<String, Object?> androidForegroundWebRtcAudioProofFromArtifact(
  Map<String, Object?> artifact,
) {
  if (!_hasExactKeys(artifact, const <String>{
        'schema',
        'capabilityId',
        'validatorIds',
        'proof',
      }) ||
      artifact['schema'] != 'mknoon.sims.proof.v1' ||
      artifact['capabilityId'] != simsAndroidForegroundWebRtcAudioScenarioId ||
      !_sameOrderedStrings(artifact['validatorIds'], const <String>[
        androidForegroundWebRtcAudioArtifactValidatorId,
      ])) {
    throw const FormatException(
      'foreground WebRTC audio artifact envelope is invalid',
    );
  }
  final proof = _object(artifact['proof']);
  if (proof == null) {
    throw const FormatException(
      'foreground WebRTC audio artifact proof is missing',
    );
  }
  final validation = validateAndroidForegroundWebRtcAudioEvidence(proof);
  if (!validation.ok) throw FormatException(validation.detail);
  if (utf8.encode(jsonEncode(artifact)).length > 5120) {
    throw const FormatException(
      'foreground WebRTC audio artifact exceeds its evidence bound',
    );
  }
  return Map<String, Object?>.unmodifiable(proof);
}

bool _validSignalingTrace(Map<String, Object?>? trace, {required String role}) {
  if (trace == null ||
      !_hasExactKeys(trace, const <String>{
        'reducerPathSha256',
        'outboundEnvelopeCount',
        'inboundEnvelopeCount',
        'outboundEnvelopeChainSha256',
        'inboundEnvelopeChainSha256',
        'outboundSignalCounts',
      }) ||
      trace['reducerPathSha256'] !=
          androidForegroundWebRtcAudioReducerPathSha256(role) ||
      !_isNonNegativeInt(trace['outboundEnvelopeCount']) ||
      !_isNonNegativeInt(trace['inboundEnvelopeCount']) ||
      !_isSha256(trace['outboundEnvelopeChainSha256']) ||
      !_isSha256(trace['inboundEnvelopeChainSha256'])) {
    return false;
  }
  final counts = _object(trace['outboundSignalCounts']);
  if (!_validOutboundSignalCounts(counts, role: role)) return false;
  final countSum = counts!.values.fold<int>(
    0,
    (sum, value) => sum + (value as int),
  );
  return trace['outboundEnvelopeCount'] == countSum;
}

bool _validOutboundSignalCounts(
  Map<String, Object?>? counts, {
  required String role,
}) {
  if (counts == null ||
      !_hasExactKeys(counts, _signalCountKeys) ||
      counts.values.any((value) => !_isNonNegativeInt(value))) {
    return false;
  }
  int count(String key) => counts[key]! as int;
  if (count('ice') < 1) return false;
  return switch (role) {
    simsForegroundWebRtcCallerRole =>
      count('invite') == 1 &&
          count('ringing') == 0 &&
          count('accept') == 0 &&
          count('reject') == 0 &&
          count('offer') == 1 &&
          count('answer') == 0 &&
          count('ice_restart') == 0 &&
          count('terminate') == 1,
    simsForegroundWebRtcCalleeRole =>
      count('invite') == 0 &&
          count('ringing') == 1 &&
          count('accept') == 1 &&
          count('reject') == 0 &&
          count('offer') == 0 &&
          count('answer') == 1 &&
          count('ice_restart') == 0 &&
          count('terminate') == 0,
    _ => false,
  };
}

bool _validEnvelopeBindings(Map<String, Object?> value) {
  if (!_hasExactKeys(value, const <String>{
    'callerToCallee',
    'calleeToCaller',
  })) {
    return false;
  }
  return _validEnvelopeDirection(_object(value['callerToCallee'])) &&
      _validEnvelopeDirection(_object(value['calleeToCaller']));
}

bool _validEnvelopeDirection(Map<String, Object?>? value) =>
    value != null &&
    _hasExactKeys(value, const <String>{'count', 'chainSha256'}) &&
    _isNonNegativeInt(value['count']) &&
    _isSha256(value['chainSha256']);

bool _matchesEnvelopeDirection({
  required Map<String, Object?> outboundTrace,
  required Map<String, Object?> wire,
  required Map<String, Object?> inboundTrace,
}) =>
    outboundTrace['outboundEnvelopeCount'] == wire['count'] &&
    wire['count'] == inboundTrace['inboundEnvelopeCount'] &&
    outboundTrace['outboundEnvelopeChainSha256'] == wire['chainSha256'] &&
    wire['chainSha256'] == inboundTrace['inboundEnvelopeChainSha256'];

bool _validRoute(Map<String, Object?>? route) {
  if (route == null ||
      !_hasExactKeys(route, const <String>{
        'speakerSupported',
        'speakerSelected',
        'finalRoute',
      })) {
    return false;
  }
  final speakerSupported = route['speakerSupported'];
  final speakerSelected = route['speakerSelected'];
  return speakerSupported is bool &&
      speakerSelected is bool &&
      speakerSelected == speakerSupported &&
      route['finalRoute'] == 'systemDefault';
}

bool _bothTrue(Map<String, Object?>? value) =>
    value != null &&
    _hasExactKeys(value, const <String>{'caller', 'callee'}) &&
    value.values.every((entry) => entry == true);

bool _allTrue(Map<String, Object?>? value, Set<String> expectedKeys) =>
    value != null &&
    _hasExactKeys(value, expectedKeys) &&
    value.values.every((entry) => entry == true);

bool _isNonNegativeInt(Object? value) => value is int && value >= 0;

bool _isBoundedCount(Object? value) =>
    value is int && value >= 0 && value <= 256;

AndroidForegroundWebRtcAudioRelayMode? _relayMode(Object? value) {
  for (final mode in AndroidForegroundWebRtcAudioRelayMode.values) {
    if (value == mode.name) return mode;
  }
  return null;
}

bool _validTcpFallbackPrecondition(
  Map<String, Object?>? value,
  AndroidForegroundWebRtcAudioRelayMode mode,
) {
  if (value == null ||
      !_hasExactKeys(value, const <String>{
        'applied',
        'udpProbeAttempts',
        'udpStunResponseAbsent',
        'tcpReachable',
      })) {
    return false;
  }
  return switch (mode) {
    AndroidForegroundWebRtcAudioRelayMode.turnUdp =>
      value['applied'] == false &&
          value['udpProbeAttempts'] == 0 &&
          value['udpStunResponseAbsent'] == false &&
          value['tcpReachable'] == false,
    AndroidForegroundWebRtcAudioRelayMode.turnTcp =>
      value['applied'] == true &&
          value['udpProbeAttempts'] == 3 &&
          value['udpStunResponseAbsent'] == true &&
          value['tcpReachable'] == true,
  };
}

bool _validTurnUrlsForMode(
  List<Object?> values,
  AndroidForegroundWebRtcAudioRelayMode mode,
) {
  final expectedTransports = switch (mode) {
    AndroidForegroundWebRtcAudioRelayMode.turnUdp => const <String>['udp'],
    AndroidForegroundWebRtcAudioRelayMode.turnTcp => const <String>[
      'udp',
      'tcp',
    ],
  };
  if (values.length != expectedTransports.length) return false;
  String? authority;
  for (var index = 0; index < values.length; index++) {
    final value = values[index];
    if (value is! String ||
        value.isEmpty ||
        value.length > 2048 ||
        value.trim() != value ||
        value.contains('@') ||
        RegExp(r'\s').hasMatch(value)) {
      return false;
    }
    final match = RegExp(
      r'^turn:([0-9]{1,3}(?:\.[0-9]{1,3}){3}):([0-9]{1,5})\?transport=(udp|tcp)$',
    ).firstMatch(value);
    final host = match?.group(1);
    final port = int.tryParse(match?.group(2) ?? '');
    if (match == null ||
        host == null ||
        !_isDeviceRoutableIpv4Host(host) ||
        port == null ||
        port < 1 ||
        port > 65535 ||
        match.group(3) != expectedTransports[index]) {
      return false;
    }
    final currentAuthority = '$host:$port';
    authority ??= currentAuthority;
    if (authority != currentAuthority) return false;
  }
  return true;
}

bool _isDeviceRoutableIpv4Host(String value) {
  final parts = value.split('.');
  if (parts.length != 4) return false;
  final octets = parts.map(int.tryParse).toList(growable: false);
  if (octets.any((octet) => octet == null || octet < 0 || octet > 255)) {
    return false;
  }
  final first = octets[0]!;
  final second = octets[1]!;
  final last = octets[3]!;
  return first != 0 &&
      first != 127 &&
      first < 224 &&
      !(first == 169 && second == 254) &&
      last != 0 &&
      last != 255;
}

bool _boundedPrivateToken(Object? value, int maximumLength) =>
    value is String &&
    value.isNotEmpty &&
    value.length <= maximumLength &&
    !RegExp(r'\s').hasMatch(value);

bool _isSha256(Object? value) =>
    value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

bool _enumName(
  Object? value,
  Iterable<Enum> values, {
  bool allowNone = false,
}) =>
    value is String &&
    ((allowNone && value == 'none') ||
        values.any((candidate) => candidate.name == value));

Map<String, Object?>? _object(Object? value) => value is Map
    ? value.map<String, Object?>((key, entry) => MapEntry('$key', entry))
    : null;

bool _hasExactKeys(Map<Object?, Object?> value, Set<String> expected) =>
    value.keys.map((key) => '$key').toSet().containsAll(expected) &&
    value.length == expected.length;

bool _sameOrderedStrings(Object? value, List<String> expected) {
  if (value is! List || value.length != expected.length) return false;
  for (var index = 0; index < expected.length; index++) {
    if (value[index] != expected[index]) return false;
  }
  return true;
}

const Set<String> _forbiddenDurableKeys = <String>{
  'url',
  'urls',
  'turnurl',
  'username',
  'turnusername',
  'password',
  'turnpassword',
  'credential',
  'credentials',
  'secret',
  'sharedsecret',
  'authority',
  'sdp',
  'candidate',
  'candidates',
  'address',
  'addresses',
  'ip',
  'port',
  'deviceid',
  'peerid',
  'token',
  'rawaudio',
  'rtpcounters',
};

bool _containsForbiddenDurableMaterial(Object? value) {
  if (value is Map) {
    for (final entry in value.entries) {
      final key = '${entry.key}'.toLowerCase().replaceAll(
        RegExp(r'[^a-z0-9]'),
        '',
      );
      if (_forbiddenDurableKeys.contains(key) ||
          _containsForbiddenDurableMaterial(entry.value)) {
        return true;
      }
    }
    return false;
  }
  if (value is Iterable) {
    return value.any(_containsForbiddenDurableMaterial);
  }
  if (value is! String) return false;
  final normalized = value.trim().toLowerCase();
  return normalized.startsWith('turn:') ||
      normalized.startsWith('turns:') ||
      normalized.startsWith('candidate:') ||
      normalized.contains('\na=candidate:') ||
      normalized.startsWith('v=0\r\n') ||
      RegExp(r'^\d{1,3}(?:\.\d{1,3}){3}(?::\d{1,5})?$').hasMatch(normalized);
}
