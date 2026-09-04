const String androidProductionAudioCallE2EAction =
    'android_production_audio_call_observe';
const String androidProductionAudioCallE2EScenario =
    'android.production_1to1_audio_call';
const String androidProductionAudioCallE2EBuildProfile =
    'android.e2e.production_call_local';
const String androidProductionAudioCallE2ERequestSchema =
    'mknoon.android-production-audio-call-observation-request.v1';
const String androidProductionAudioCallE2EResultSchema =
    'mknoon.android-production-audio-call-observation-result.v1';

const String androidProductionAudioCallCallerRole = 'caller';
const String androidProductionAudioCallCalleeRole = 'callee';
const String androidProductionAudioCallArmOperation = 'arm';
const String androidProductionAudioCallSampleOperation = 'sample';
const String androidProductionAudioCallStopOperation = 'stop';
const String androidProductionAudioCallReadinessOperation = 'readiness';

const Set<String> _baseRequestKeys = <String>{
  'schema',
  'transport_action',
  'scenario',
  'buildProfile',
  'role',
  'operation',
  'stepId',
  'runId',
  'nonce',
  'profileSha256',
  'apkSha256',
};
const Set<String> _readinessRequestKeys = <String>{
  ..._baseRequestKeys,
  'contactAccountPeerId',
};

final RegExp _token = RegExp(r'^[A-Za-z0-9._:-]+$');
final RegExp _sha256 = RegExp(r'^[0-9a-f]{64}$');
final RegExp _peerId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,254}$');

String androidProductionAudioCallStepId({
  required String role,
  required String operation,
  required String runId,
}) => 'production-call-$role-$operation-$runId';

/// Exact, file-channel request for a read-only production-call observation.
///
/// The strict key allowlist is intentional: a host cannot smuggle a call
/// command, signaling value, or media sample through this boundary. The sole
/// peer input is accepted only for the read-only readiness lookup and is never
/// reflected in a receipt.
final class AndroidProductionAudioCallE2ERequest {
  const AndroidProductionAudioCallE2ERequest({
    required this.role,
    required this.operation,
    required this.runId,
    required this.nonce,
    required this.profileSha256,
    required this.apkSha256,
    required this.contactAccountPeerId,
  });

  factory AndroidProductionAudioCallE2ERequest.fromConfig(
    Map<String, dynamic> config,
  ) {
    final expectedKeys =
        config['operation'] == androidProductionAudioCallReadinessOperation
        ? _readinessRequestKeys
        : _baseRequestKeys;
    if (config.keys.toSet().length != expectedKeys.length ||
        !config.keys.toSet().containsAll(expectedKeys) ||
        config['schema'] != androidProductionAudioCallE2ERequestSchema ||
        config['transport_action'] != androidProductionAudioCallE2EAction ||
        config['scenario'] != androidProductionAudioCallE2EScenario ||
        config['buildProfile'] != androidProductionAudioCallE2EBuildProfile) {
      throw const FormatException('production-call observation rejected');
    }
    final role = _requiredToken(config, 'role', maxLength: 16);
    if (role != androidProductionAudioCallCallerRole &&
        role != androidProductionAudioCallCalleeRole) {
      throw const FormatException('production-call role rejected');
    }
    final operation = _requiredToken(config, 'operation', maxLength: 16);
    if (operation != androidProductionAudioCallArmOperation &&
        operation != androidProductionAudioCallSampleOperation &&
        operation != androidProductionAudioCallStopOperation &&
        operation != androidProductionAudioCallReadinessOperation) {
      throw const FormatException('production-call operation rejected');
    }
    final contactAccountPeerId = switch (operation) {
      androidProductionAudioCallReadinessOperation =>
        _requiredContactAccountPeerId(config),
      _ => null,
    };
    final runId = _requiredToken(config, 'runId', maxLength: 80);
    if (config['stepId'] !=
        androidProductionAudioCallStepId(
          role: role,
          operation: operation,
          runId: runId,
        )) {
      throw const FormatException('production-call step binding rejected');
    }
    final profileSha256 = config['profileSha256'];
    final apkSha256 = config['apkSha256'];
    if (profileSha256 is! String ||
        !_sha256.hasMatch(profileSha256) ||
        apkSha256 is! String ||
        !_sha256.hasMatch(apkSha256)) {
      throw const FormatException('production-call artifact binding rejected');
    }
    return AndroidProductionAudioCallE2ERequest(
      role: role,
      operation: operation,
      runId: runId,
      nonce: _requiredToken(config, 'nonce', maxLength: 128),
      profileSha256: profileSha256,
      apkSha256: apkSha256,
      contactAccountPeerId: contactAccountPeerId,
    );
  }

  final String role;
  final String operation;
  final String runId;
  final String nonce;
  final String profileSha256;
  final String apkSha256;
  final String? contactAccountPeerId;

  String get stepId => androidProductionAudioCallStepId(
    role: role,
    operation: operation,
    runId: runId,
  );

  bool isSameRun(AndroidProductionAudioCallE2ERequest other) =>
      role == other.role &&
      runId == other.runId &&
      nonce == other.nonce &&
      profileSha256 == other.profileSha256 &&
      apkSha256 == other.apkSha256 &&
      contactAccountPeerId == other.contactAccountPeerId;
}

/// Fixed-shape failure receipt used by the shared file-channel dispatcher.
/// Invalid request values are never reflected unless they satisfy the same
/// small token/hash vocabulary as a valid command.
Map<String, Object?> androidProductionAudioCallE2EFailureReceipt({
  required Map<String, dynamic> config,
}) {
  String safeToken(String key, String fallback, {int maxLength = 128}) {
    final value = config[key];
    return value is String &&
            value.isNotEmpty &&
            value.length <= maxLength &&
            _token.hasMatch(value)
        ? value
        : fallback;
  }

  String safeDigest(String key) {
    final value = config[key];
    return value is String && _sha256.hasMatch(value) ? value : '0' * 64;
  }

  final role = safeToken('role', 'invalid', maxLength: 16);
  final operation = safeToken('operation', 'invalid', maxLength: 16);
  final runId = safeToken('runId', 'invalid-run', maxLength: 80);
  return <String, Object?>{
    'schema': androidProductionAudioCallE2EResultSchema,
    'scenario': androidProductionAudioCallE2EScenario,
    'buildProfile': androidProductionAudioCallE2EBuildProfile,
    'role': role,
    'operation': operation,
    'stepId': androidProductionAudioCallStepId(
      role: role,
      operation: operation,
      runId: runId,
    ),
    'runId': runId,
    'nonce': safeToken('nonce', 'invalid-nonce'),
    'profileSha256': safeDigest('profileSha256'),
    'apkSha256': safeDigest('apkSha256'),
    'callBindingSha256': null,
    'status': 'failed',
    'success': false,
    'stateSequence': const <String>[],
    'outgoingObserved': false,
    'ringingObserved': false,
    'acceptedObserved': false,
    'connectedObserved': false,
    'terminalObserved': false,
    'activeCallSurfaceObserved': false,
    'structuralMediaReadyObserved': false,
    'relayOnlyObserved': false,
    'selectedRelayTransport': 'unknown',
    'localAudioEnabledObserved': false,
    'inboundAudioRtpObserved': false,
    'outboundAudioRtpObserved': false,
    'wakeAuthorityReady': false,
    'containsPrivateMaterial': false,
  };
}

String _requiredContactAccountPeerId(Map<String, dynamic> config) {
  final value = config['contactAccountPeerId'];
  if (value is! String || !_peerId.hasMatch(value)) {
    throw const FormatException('production-call contact peer rejected');
  }
  return value;
}

String _requiredToken(
  Map<String, dynamic> config,
  String key, {
  required int maxLength,
}) {
  final value = config[key];
  if (value is! String ||
      value.isEmpty ||
      value.length > maxLength ||
      !_token.hasMatch(value)) {
    throw FormatException('production-call $key rejected');
  }
  return value;
}
