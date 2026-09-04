import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'android_campaign_evidence_validation.dart';

const String androidProductionAudioCallScenarioId =
    'android.production_1to1_audio_call';
const String androidProductionAudioCallProfileId =
    'android.e2e.production_call_local';
const String androidProductionAudioCallEvidenceSchema =
    'mknoon.sims.android-production-audio-call-e2e.v1';
const String androidProductionAudioCallArtifactValidatorId =
    'validateAndroidProductionAudioCallArtifact';
const String androidProductionAudioCallObservationRequestSchema =
    'mknoon.android-production-audio-call-observation-request.v1';
const String androidProductionAudioCallObservationResultSchema =
    'mknoon.android-production-audio-call-observation-result.v1';
const String androidProductionAudioCallObserverAction =
    'android_production_audio_call_observe';
const String androidProductionAudioCallPionOracleResultSchema =
    'mknoon.call_audio_oracle.result.v1';
const String androidProductionAudioCallPionVersion = 'v4.2.19';
const String androidProductionAudioCallCoturnImage = 'coturn/coturn:4.17.2-r0';
const String androidProductionAudioCallCoturnImageDigest =
    'sha256:aa68aab64a3b929d57fc2924c98ea447bf996cf8dade2508e7b71eaf23f1f14e';
const String androidProductionAudioCallCallerRole = 'caller';
const String androidProductionAudioCallCalleeRole = 'callee';
const String androidProductionAudioCallArmOperation = 'arm';
const String androidProductionAudioCallSampleOperation = 'sample';
const String androidProductionAudioCallStopOperation = 'stop';
const int androidProductionAudioCallAssertionCount = 27;

const Set<String> _receiptKeys = <String>{
  'schema',
  'scenario',
  'buildProfile',
  'role',
  'operation',
  'stepId',
  'runId',
  'nonce',
  'profileSha256',
  'apkSha256',
  'callBindingSha256',
  'status',
  'success',
  'stateSequence',
  'outgoingObserved',
  'ringingObserved',
  'acceptedObserved',
  'connectedObserved',
  'terminalObserved',
  'activeCallSurfaceObserved',
  'structuralMediaReadyObserved',
  'relayOnlyObserved',
  'selectedRelayTransport',
  'localAudioEnabledObserved',
  'inboundAudioRtpObserved',
  'outboundAudioRtpObserved',
  'wakeAuthorityReady',
  'containsPrivateMaterial',
};

const Set<String> _rootKeys = <String>{
  'schema',
  'scenario',
  'status',
  'platform',
  'runtimeDispatched',
  'productionEntrypoint',
  'runBindingSha256',
  'sharedArtifact',
  'topology',
  'relay',
  'endpoints',
  'controls',
  'cleanup',
  'artifacts',
  'mediaProof',
  'assertionsAttempted',
};

final class AndroidProductionAudioCallSemanticControls {
  const AndroidProductionAudioCallSemanticControls({
    required this.callStarted,
    required this.nativeAnswered,
    required this.muteExercised,
    required this.speakerExercised,
    required this.hangupExercised,
  });

  final bool callStarted;
  final bool nativeAnswered;
  final bool muteExercised;
  final bool speakerExercised;
  final bool hangupExercised;

  Map<String, Object?> toJson() => <String, Object?>{
    'semanticSelectorsOnly': true,
    'callStarted': callStarted,
    'nativeAnswered': nativeAnswered,
    'muteExercised': muteExercised,
    'speakerExercised': speakerExercised,
    'hangupExercised': hangupExercised,
  };
}

final class AndroidProductionAudioCallArtifactDigest {
  const AndroidProductionAudioCallArtifactDigest({
    required this.role,
    required this.kind,
    required this.sha256Digest,
    required this.bounded,
    required this.redacted,
  });

  final String role;
  final String kind;
  final String sha256Digest;
  final bool bounded;
  final bool redacted;

  Map<String, Object?> toJson() => <String, Object?>{
    'role': role,
    'kind': kind,
    'sha256': sha256Digest,
    'bounded': bounded,
    'redacted': redacted,
  };
}

/// Strict, privacy-bounded projection of the host-only Pion oracle result.
///
/// The raw result has no credentials or network coordinates. This parser also
/// rejects unknown fields so future oracle output cannot silently expand the
/// durable production-call artifact.
final class AndroidProductionAudioCallPionOracleEvidence {
  const AndroidProductionAudioCallPionOracleEvidence._({
    required this.knownFixtureSha256,
    required this.turnAuthoritySha256,
    required this.fixtureInstanceSha256,
  });

  factory AndroidProductionAudioCallPionOracleEvidence.fromResult(
    Map<String, Object?> result,
  ) {
    final coturn = _object(result['coturn']);
    final aToB = _object(result['a_to_b']);
    final bToA = _object(result['b_to_a']);
    final peerARoute = _object(result['peer_a_route']);
    final peerBRoute = _object(result['peer_b_route']);
    final fixtureSha256 = result['fixture_sha256'];
    if (!_hasExactKeys(result, const <String>{
          'schema',
          'version',
          'passed',
          'pion_version',
          'fixture_sha256',
          'turn_authority_sha256',
          'fixture_instance_sha256',
          'coturn',
          'expected_transport',
          'a_to_b',
          'b_to_a',
          'peer_a_route',
          'peer_b_route',
          'cleanup_complete',
        }) ||
        result['schema'] != androidProductionAudioCallPionOracleResultSchema ||
        result['version'] != 1 ||
        result['passed'] != true ||
        result['pion_version'] != androidProductionAudioCallPionVersion ||
        !_isSha256(fixtureSha256) ||
        !_isSha256(result['turn_authority_sha256']) ||
        !_isSha256(result['fixture_instance_sha256']) ||
        result['expected_transport'] != 'udp' ||
        result['cleanup_complete'] != true ||
        coturn == null ||
        !_hasExactKeys(coturn, const <String>{'image', 'digest'}) ||
        coturn['image'] != androidProductionAudioCallCoturnImage ||
        coturn['digest'] != androidProductionAudioCallCoturnImageDigest ||
        !_validOracleDirection(aToB) ||
        !_validOracleDirection(bToA) ||
        !_validOracleRoute(peerARoute) ||
        !_validOracleRoute(peerBRoute)) {
      throw const FormatException(
        'Production audio-call Pion oracle evidence is incomplete or unsafe.',
      );
    }
    return AndroidProductionAudioCallPionOracleEvidence._(
      knownFixtureSha256: fixtureSha256! as String,
      turnAuthoritySha256: result['turn_authority_sha256']! as String,
      fixtureInstanceSha256: result['fixture_instance_sha256']! as String,
    );
  }

  final String knownFixtureSha256;
  final String turnAuthoritySha256;
  final String fixtureInstanceSha256;

  Map<String, Object?> toJson() => <String, Object?>{
    'directionalMediaOracle': 'production-stats-and-pion',
    'productionRtpClaimed': true,
    'pionOraclePassed': true,
    'pionVersion': androidProductionAudioCallPionVersion,
    'knownFixtureSha256': knownFixtureSha256,
    'turnAuthoritySha256': turnAuthoritySha256,
    'fixtureInstanceSha256': fixtureInstanceSha256,
    'coturnVersion': '4.17.2-r0',
    'coturnImageSha256': androidProductionAudioCallCoturnImageDigest.substring(
      'sha256:'.length,
    ),
    'expectedTransport': 'udp',
    'aToB': _oracleDirectionEvidence(),
    'bToA': _oracleDirectionEvidence(),
    'peerARoute': _oracleRouteEvidence(),
    'peerBRoute': _oracleRouteEvidence(),
    'cleanupComplete': true,
  };
}

/// Reconciles the two final observer receipts with host-only UI and cleanup
/// proof. Raw device IDs, peer IDs, call IDs, addresses, credentials, SDP,
/// ICE, and media counters are deliberately not copied into the durable map.
Map<String, Object?> aggregateAndroidProductionAudioCallEvidence({
  required Map<String, Object?> callerReceipt,
  required Map<String, Object?> calleeReceipt,
  required String runId,
  required String callerNonce,
  required String calleeNonce,
  required String profileSha256,
  required String apkSha256,
  required String relayFixtureIdentitySha256,
  required String turnAuthoritySha256,
  required String coturnInstanceIdentitySha256,
  required AndroidProductionAudioCallPionOracleEvidence pionOracle,
  required String callerIdentitySha256,
  required String calleeIdentitySha256,
  required String physicalDeviceId,
  required String emulatorDeviceId,
  required AndroidProductionAudioCallSemanticControls semanticControls,
  required bool terminalSurfacesDismissed,
  required bool nativeCallsReleasedBothEndpoints,
  required bool appStateRestored,
  required List<AndroidProductionAudioCallArtifactDigest> artifacts,
}) {
  _validateFinalReceipt(
    callerReceipt,
    role: androidProductionAudioCallCallerRole,
    runId: runId,
    nonce: callerNonce,
    profileSha256: profileSha256,
    apkSha256: apkSha256,
  );
  _validateFinalReceipt(
    calleeReceipt,
    role: androidProductionAudioCallCalleeRole,
    runId: runId,
    nonce: calleeNonce,
    profileSha256: profileSha256,
    apkSha256: apkSha256,
  );
  if (physicalDeviceId == emulatorDeviceId ||
      !_isSafeToken(physicalDeviceId) ||
      !_isSafeToken(emulatorDeviceId) ||
      !_isSha256(relayFixtureIdentitySha256) ||
      !_isSha256(turnAuthoritySha256) ||
      !_isSha256(coturnInstanceIdentitySha256) ||
      !_isSha256(callerIdentitySha256) ||
      !_isSha256(calleeIdentitySha256) ||
      pionOracle.turnAuthoritySha256 != turnAuthoritySha256 ||
      pionOracle.fixtureInstanceSha256 != coturnInstanceIdentitySha256 ||
      callerIdentitySha256 == calleeIdentitySha256 ||
      artifacts.isEmpty) {
    throw const FormatException(
      'production audio-call topology, identities, or artifacts are invalid',
    );
  }

  final callerTransport = callerReceipt['selectedRelayTransport']! as String;
  final calleeTransport = calleeReceipt['selectedRelayTransport']! as String;
  final proof = <String, Object?>{
    'schema': androidProductionAudioCallEvidenceSchema,
    'scenario': androidProductionAudioCallScenarioId,
    'status': 'passed',
    'platform': 'android',
    'runtimeDispatched': true,
    'productionEntrypoint': 'lib/main.dart',
    'runBindingSha256': _sha256Text(
      '$runId\n$callerNonce\n$calleeNonce\n$profileSha256\n$apkSha256',
    ),
    'sharedArtifact': <String, Object?>{
      'profileId': androidProductionAudioCallProfileId,
      'profileSha256': profileSha256,
      'apkSha256': apkSha256,
      'sameApkBothTargets': true,
    },
    'topology': <String, Object?>{
      'callerKind': 'emulator',
      'calleeKind': 'physical',
      'callerDeviceSha256': _sha256Text(emulatorDeviceId),
      'calleeDeviceSha256': _sha256Text(physicalDeviceId),
      'distinctTargets': true,
    },
    'relay': <String, Object?>{
      'localDisposableFixture': true,
      'fixtureIdentitySha256': relayFixtureIdentitySha256,
      'turnAuthoritySha256': turnAuthoritySha256,
      'coturnInstanceIdentitySha256': coturnInstanceIdentitySha256,
      'relayOnlyBothEndpoints': true,
      'callerTransport': callerTransport,
      'calleeTransport': calleeTransport,
    },
    'endpoints': <String, Object?>{
      'caller': _endpointEvidence(
        callerReceipt,
        identitySha256: callerIdentitySha256,
      ),
      'callee': _endpointEvidence(
        calleeReceipt,
        identitySha256: calleeIdentitySha256,
      ),
    },
    'controls': semanticControls.toJson(),
    'cleanup': <String, Object?>{
      'terminalBothEndpoints': true,
      'activeSurfacesDismissed': terminalSurfacesDismissed,
      'nativeCallsReleasedBothEndpoints': nativeCallsReleasedBothEndpoints,
      'appStateRestored': appStateRestored,
    },
    'artifacts': artifacts.map((artifact) => artifact.toJson()).toList(),
    'mediaProof': pionOracle.toJson(),
    'assertionsAttempted': androidProductionAudioCallAssertionCount,
  };
  final validation = validateAndroidProductionAudioCallEvidence(proof);
  if (!validation.ok) throw FormatException(validation.detail);
  return Map<String, Object?>.unmodifiable(proof);
}

AndroidCampaignEvidenceValidation validateAndroidProductionAudioCallEvidence(
  Map<String, Object?> artifact,
) {
  if (!_hasExactKeys(artifact, _rootKeys) ||
      artifact['schema'] != androidProductionAudioCallEvidenceSchema ||
      artifact['scenario'] != androidProductionAudioCallScenarioId ||
      artifact['status'] != 'passed' ||
      artifact['platform'] != 'android' ||
      artifact['runtimeDispatched'] != true ||
      artifact['productionEntrypoint'] != 'lib/main.dart' ||
      !_isSha256(artifact['runBindingSha256']) ||
      artifact['assertionsAttempted'] !=
          androidProductionAudioCallAssertionCount) {
    return const AndroidCampaignEvidenceValidation.fail(
      'production audio-call root evidence is not canonical',
    );
  }

  final shared = _object(artifact['sharedArtifact']);
  if (shared == null ||
      !_hasExactKeys(shared, const <String>{
        'profileId',
        'profileSha256',
        'apkSha256',
        'sameApkBothTargets',
      }) ||
      shared['profileId'] != androidProductionAudioCallProfileId ||
      !_isSha256(shared['profileSha256']) ||
      !_isSha256(shared['apkSha256']) ||
      shared['sameApkBothTargets'] != true) {
    return const AndroidCampaignEvidenceValidation.fail(
      'production audio-call APK/profile custody is invalid',
    );
  }

  final topology = _object(artifact['topology']);
  if (topology == null ||
      !_hasExactKeys(topology, const <String>{
        'callerKind',
        'calleeKind',
        'callerDeviceSha256',
        'calleeDeviceSha256',
        'distinctTargets',
      }) ||
      topology['callerKind'] != 'emulator' ||
      topology['calleeKind'] != 'physical' ||
      !_isSha256(topology['callerDeviceSha256']) ||
      !_isSha256(topology['calleeDeviceSha256']) ||
      topology['callerDeviceSha256'] == topology['calleeDeviceSha256'] ||
      topology['distinctTargets'] != true) {
    return const AndroidCampaignEvidenceValidation.fail(
      'production audio-call target topology is invalid',
    );
  }

  final relay = _object(artifact['relay']);
  if (relay == null ||
      !_hasExactKeys(relay, const <String>{
        'localDisposableFixture',
        'fixtureIdentitySha256',
        'turnAuthoritySha256',
        'coturnInstanceIdentitySha256',
        'relayOnlyBothEndpoints',
        'callerTransport',
        'calleeTransport',
      }) ||
      relay['localDisposableFixture'] != true ||
      !_isSha256(relay['fixtureIdentitySha256']) ||
      !_isSha256(relay['turnAuthoritySha256']) ||
      !_isSha256(relay['coturnInstanceIdentitySha256']) ||
      relay['relayOnlyBothEndpoints'] != true ||
      !_validRelayTransport(relay['callerTransport']) ||
      !_validRelayTransport(relay['calleeTransport'])) {
    return const AndroidCampaignEvidenceValidation.fail(
      'production audio-call local relay proof is invalid',
    );
  }

  final endpoints = _object(artifact['endpoints']);
  if (endpoints == null ||
      !_hasExactKeys(endpoints, const <String>{'caller', 'callee'}) ||
      !_validateEndpointEvidence(
        _object(endpoints['caller']),
        role: androidProductionAudioCallCallerRole,
      ) ||
      !_validateEndpointEvidence(
        _object(endpoints['callee']),
        role: androidProductionAudioCallCalleeRole,
      ) ||
      (_object(endpoints['caller'])!['identitySha256'] ==
          _object(endpoints['callee'])!['identitySha256'])) {
    return const AndroidCampaignEvidenceValidation.fail(
      'production audio-call endpoint proof is invalid',
    );
  }

  final controls = _object(artifact['controls']);
  if (controls == null ||
      !_hasExactKeys(controls, const <String>{
        'semanticSelectorsOnly',
        'callStarted',
        'nativeAnswered',
        'muteExercised',
        'speakerExercised',
        'hangupExercised',
      }) ||
      controls.values.any((value) => value != true)) {
    return const AndroidCampaignEvidenceValidation.fail(
      'production audio-call semantic controls are incomplete',
    );
  }

  final cleanup = _object(artifact['cleanup']);
  if (cleanup == null ||
      !_hasExactKeys(cleanup, const <String>{
        'terminalBothEndpoints',
        'activeSurfacesDismissed',
        'nativeCallsReleasedBothEndpoints',
        'appStateRestored',
      }) ||
      cleanup.values.any((value) => value != true)) {
    return const AndroidCampaignEvidenceValidation.fail(
      'production audio-call terminal/native cleanup is incomplete',
    );
  }

  final artifactRows = artifact['artifacts'];
  if (!_validArtifactSet(artifactRows)) {
    return const AndroidCampaignEvidenceValidation.fail(
      'production audio-call bounded artifacts are invalid',
    );
  }

  final mediaProof = _object(artifact['mediaProof']);
  if (!_validMediaProof(
    mediaProof,
    turnAuthoritySha256: relay['turnAuthoritySha256']! as String,
    coturnInstanceIdentitySha256:
        relay['coturnInstanceIdentitySha256']! as String,
  )) {
    return const AndroidCampaignEvidenceValidation.fail(
      'production RTP and Pion evidence must pass in both directions',
    );
  }
  return const AndroidCampaignEvidenceValidation.pass();
}

Map<String, Object?> androidProductionAudioCallDurablePayload(
  Map<String, Object?> runtimeProof,
) => validatedAndroidRuntimeProofPayload(
  runtimeProof: runtimeProof,
  validate: validateAndroidProductionAudioCallEvidence,
);

AndroidCampaignEvidenceValidation
validateAndroidProductionAudioCallDurableArtifact(
  Map<String, Object?> artifact,
) => validateDurableAndroidCampaignArtifact(
  artifact: artifact,
  capabilityId: androidProductionAudioCallScenarioId,
  validatorId: androidProductionAudioCallArtifactValidatorId,
  validateRuntimeProof: validateAndroidProductionAudioCallEvidence,
);

void _validateFinalReceipt(
  Map<String, Object?> receipt, {
  required String role,
  required String runId,
  required String nonce,
  required String profileSha256,
  required String apkSha256,
}) {
  final expectedSequence = role == androidProductionAudioCallCallerRole
      ? const <String>[
          'outgoing',
          'ringing',
          'accepted',
          'connected',
          'terminal',
        ]
      : const <String>['ringing', 'accepted', 'connected', 'terminal'];
  if (!_hasExactKeys(receipt, _receiptKeys) ||
      receipt['schema'] != androidProductionAudioCallObservationResultSchema ||
      receipt['scenario'] != androidProductionAudioCallScenarioId ||
      receipt['buildProfile'] != androidProductionAudioCallProfileId ||
      receipt['role'] != role ||
      receipt['operation'] != androidProductionAudioCallStopOperation ||
      receipt['stepId'] != 'production-call-$role-stop-$runId' ||
      receipt['runId'] != runId ||
      receipt['nonce'] != nonce ||
      receipt['profileSha256'] != profileSha256 ||
      receipt['apkSha256'] != apkSha256 ||
      !_isSha256(receipt['callBindingSha256']) ||
      receipt['status'] != 'complete' ||
      receipt['success'] != true ||
      !_sameStrings(receipt['stateSequence'], expectedSequence) ||
      receipt['outgoingObserved'] !=
          (role == androidProductionAudioCallCallerRole) ||
      receipt['ringingObserved'] != true ||
      receipt['acceptedObserved'] != true ||
      receipt['connectedObserved'] != true ||
      receipt['terminalObserved'] != true ||
      receipt['activeCallSurfaceObserved'] != true ||
      receipt['structuralMediaReadyObserved'] != true ||
      receipt['relayOnlyObserved'] != true ||
      !_validRelayTransport(receipt['selectedRelayTransport']) ||
      receipt['localAudioEnabledObserved'] != true ||
      receipt['inboundAudioRtpObserved'] != true ||
      receipt['outboundAudioRtpObserved'] != true ||
      receipt['wakeAuthorityReady'] != false ||
      receipt['containsPrivateMaterial'] != false) {
    throw FormatException('production audio-call $role receipt rejected');
  }
}

Map<String, Object?> _endpointEvidence(
  Map<String, Object?> receipt, {
  required String identitySha256,
}) => <String, Object?>{
  'role': receipt['role'],
  'identitySha256': identitySha256,
  'callBindingSha256': receipt['callBindingSha256'],
  'stateSequence': receipt['stateSequence'],
  'activeCallSurface': receipt['activeCallSurfaceObserved'],
  'structuralMediaReady': receipt['structuralMediaReadyObserved'],
  'localAudioEnabled': receipt['localAudioEnabledObserved'],
  'inboundAudioRtpObserved': receipt['inboundAudioRtpObserved'],
  'outboundAudioRtpObserved': receipt['outboundAudioRtpObserved'],
  'relayOnly': receipt['relayOnlyObserved'],
  'selectedRelayTransport': receipt['selectedRelayTransport'],
  'terminal': receipt['terminalObserved'],
};

bool _validateEndpointEvidence(
  Map<String, Object?>? endpoint, {
  required String role,
}) {
  if (endpoint == null ||
      !_hasExactKeys(endpoint, const <String>{
        'role',
        'identitySha256',
        'callBindingSha256',
        'stateSequence',
        'activeCallSurface',
        'structuralMediaReady',
        'localAudioEnabled',
        'inboundAudioRtpObserved',
        'outboundAudioRtpObserved',
        'relayOnly',
        'selectedRelayTransport',
        'terminal',
      }) ||
      endpoint['role'] != role ||
      !_isSha256(endpoint['identitySha256']) ||
      !_isSha256(endpoint['callBindingSha256']) ||
      endpoint['activeCallSurface'] != true ||
      endpoint['structuralMediaReady'] != true ||
      endpoint['localAudioEnabled'] != true ||
      endpoint['inboundAudioRtpObserved'] != true ||
      endpoint['outboundAudioRtpObserved'] != true ||
      endpoint['relayOnly'] != true ||
      !_validRelayTransport(endpoint['selectedRelayTransport']) ||
      endpoint['terminal'] != true) {
    return false;
  }
  final expected = role == androidProductionAudioCallCallerRole
      ? const <String>[
          'outgoing',
          'ringing',
          'accepted',
          'connected',
          'terminal',
        ]
      : const <String>['ringing', 'accepted', 'connected', 'terminal'];
  return _sameStrings(endpoint['stateSequence'], expected);
}

const Map<String, bool> _artifactKindsAndRedaction = <String, bool>{
  'activeUiDump': true,
  'activeLogcat': true,
  'activeScreenshot': false,
  'terminalUiDump': true,
  'terminalLogcat': true,
  'terminalScreenshot': false,
};

bool _validArtifactSet(Object? value) {
  if (value is! List || value.length != 2 * _artifactKindsAndRedaction.length) {
    return false;
  }
  final seen = <String>{};
  for (final row in value) {
    final artifact = _object(row);
    if (artifact == null ||
        !_hasExactKeys(artifact, const <String>{
          'role',
          'kind',
          'sha256',
          'bounded',
          'redacted',
        })) {
      return false;
    }
    final role = artifact['role'];
    final kind = artifact['kind'];
    if (!const <String>{
          androidProductionAudioCallCallerRole,
          androidProductionAudioCallCalleeRole,
        }.contains(role) ||
        kind is! String ||
        !_artifactKindsAndRedaction.containsKey(kind) ||
        !_isSha256(artifact['sha256']) ||
        artifact['bounded'] != true ||
        artifact['redacted'] != _artifactKindsAndRedaction[kind] ||
        !seen.add('$role/$kind')) {
      return false;
    }
  }
  return seen.length == 2 * _artifactKindsAndRedaction.length;
}

bool _validRelayTransport(Object? value) => value == 'turn_udp';

bool _validOracleDirection(Map<String, Object?>? direction) =>
    direction != null &&
    _hasExactKeys(direction, const <String>{
      'codec_valid',
      'payload_count_exact',
      'payload_order_exact',
      'payload_hash_exact',
    }) &&
    direction.values.every((value) => value == true);

bool _validOracleRoute(Map<String, Object?>? route) =>
    route != null &&
    _hasExactKeys(route, const <String>{'relay_selected', 'transport_match'}) &&
    route.values.every((value) => value == true);

Map<String, Object?> _oracleDirectionEvidence() => <String, Object?>{
  'codecValid': true,
  'payloadCountExact': true,
  'payloadOrderExact': true,
  'payloadHashExact': true,
};

Map<String, Object?> _oracleRouteEvidence() => <String, Object?>{
  'relaySelected': true,
  'transportMatched': true,
};

bool _validMediaProof(
  Map<String, Object?>? proof, {
  required String turnAuthoritySha256,
  required String coturnInstanceIdentitySha256,
}) =>
    proof != null &&
    _hasExactKeys(proof, const <String>{
      'directionalMediaOracle',
      'productionRtpClaimed',
      'pionOraclePassed',
      'pionVersion',
      'knownFixtureSha256',
      'turnAuthoritySha256',
      'fixtureInstanceSha256',
      'coturnVersion',
      'coturnImageSha256',
      'expectedTransport',
      'aToB',
      'bToA',
      'peerARoute',
      'peerBRoute',
      'cleanupComplete',
    }) &&
    proof['directionalMediaOracle'] == 'production-stats-and-pion' &&
    proof['productionRtpClaimed'] == true &&
    proof['pionOraclePassed'] == true &&
    proof['pionVersion'] == androidProductionAudioCallPionVersion &&
    _isSha256(proof['knownFixtureSha256']) &&
    proof['turnAuthoritySha256'] == turnAuthoritySha256 &&
    proof['fixtureInstanceSha256'] == coturnInstanceIdentitySha256 &&
    proof['coturnVersion'] == '4.17.2-r0' &&
    _isSha256(proof['coturnImageSha256']) &&
    proof['coturnImageSha256'] ==
        androidProductionAudioCallCoturnImageDigest.substring(
          'sha256:'.length,
        ) &&
    proof['expectedTransport'] == 'udp' &&
    _validCanonicalOracleDirection(_object(proof['aToB'])) &&
    _validCanonicalOracleDirection(_object(proof['bToA'])) &&
    _validCanonicalOracleRoute(_object(proof['peerARoute'])) &&
    _validCanonicalOracleRoute(_object(proof['peerBRoute'])) &&
    proof['cleanupComplete'] == true;

bool _validCanonicalOracleDirection(Map<String, Object?>? direction) =>
    direction != null &&
    _hasExactKeys(direction, const <String>{
      'codecValid',
      'payloadCountExact',
      'payloadOrderExact',
      'payloadHashExact',
    }) &&
    direction.values.every((value) => value == true);

bool _validCanonicalOracleRoute(Map<String, Object?>? route) =>
    route != null &&
    _hasExactKeys(route, const <String>{'relaySelected', 'transportMatched'}) &&
    route.values.every((value) => value == true);

bool _hasExactKeys(Map<String, Object?> value, Set<String> allowed) =>
    value.keys.toSet().length == allowed.length &&
    value.keys.toSet().containsAll(allowed);

bool _sameStrings(Object? value, List<String> expected) {
  if (value is! List || value.length != expected.length) return false;
  for (var index = 0; index < expected.length; index += 1) {
    if (value[index] != expected[index]) return false;
  }
  return true;
}

Map<String, Object?>? _object(Object? value) {
  if (value is! Map) return null;
  return value.map<String, Object?>((key, item) => MapEntry('$key', item));
}

bool _isSha256(Object? value) =>
    value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

bool _isSafeToken(Object? value) =>
    value is String &&
    value.isNotEmpty &&
    value.length <= 160 &&
    RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(value);

String _sha256Text(String value) =>
    sha256.convert(utf8.encode(value)).toString();
