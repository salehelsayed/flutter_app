import 'dart:convert';

const String simsRuntimeConfigSchema = 'mknoon.sims.runtime-config.v1';

final class SimsRuntimeConfig {
  const SimsRuntimeConfig({
    required this.schema,
    required this.profileId,
    required this.scenarioId,
    required this.role,
    required this.runId,
    required this.nonce,
    required this.values,
  });

  factory SimsRuntimeConfig.fromJson(Map<String, Object?> json) {
    final values = json['values'];
    if (values is! Map) {
      throw const FormatException('runtime values must be an object');
    }
    return SimsRuntimeConfig(
      schema: _requiredString(json, 'schema'),
      profileId: _requiredString(json, 'profileId'),
      scenarioId: _requiredString(json, 'scenarioId'),
      role: _requiredString(json, 'role'),
      runId: _requiredString(json, 'runId'),
      nonce: _requiredString(json, 'nonce'),
      values: values.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  final String schema;
  final String profileId;
  final String scenarioId;
  final String role;
  final String runId;
  final String nonce;
  final Map<String, Object?> values;

  Map<String, Object?> toJson() => <String, Object?>{
    'schema': schema,
    'profileId': profileId,
    'scenarioId': scenarioId,
    'role': role,
    'runId': runId,
    'nonce': nonce,
    'values': values,
  };

  SimsRuntimeConfig copyWith({
    String? schema,
    String? profileId,
    String? scenarioId,
    String? role,
    String? runId,
    String? nonce,
    Map<String, Object?>? values,
  }) => SimsRuntimeConfig(
    schema: schema ?? this.schema,
    profileId: profileId ?? this.profileId,
    scenarioId: scenarioId ?? this.scenarioId,
    role: role ?? this.role,
    runId: runId ?? this.runId,
    nonce: nonce ?? this.nonce,
    values: values ?? this.values,
  );
}

final class RuntimeConfigValidation {
  const RuntimeConfigValidation._({
    required this.accepted,
    required this.detail,
    this.config,
  });

  const RuntimeConfigValidation.accept(SimsRuntimeConfig config)
    : this._(accepted: true, detail: 'runtime config accepted', config: config);

  const RuntimeConfigValidation.reject(String detail)
    : this._(accepted: false, detail: detail);

  final bool accepted;
  final String detail;
  final SimsRuntimeConfig? config;
}

/// Models the host/app nonce handshake used by a prebuilt runtime dispatcher.
/// It never creates an artifact: [buildCount] is intentionally fixed at zero.
final class SimsRuntimeDispatcher {
  SimsRuntimeDispatcher({
    required this.installedProfileId,
    required this.artifactDigest,
  });

  final String installedProfileId;
  final String artifactDigest;
  int launchCount = 0;
  int get buildCount => 0;
  String? lastAcceptedScenario;

  String stage(SimsRuntimeConfig config) {
    launchCount += 1;
    return jsonEncode(config.toJson());
  }

  RuntimeConfigValidation decodeAndValidate(String? encoded) {
    if (encoded == null || encoded.trim().isEmpty) {
      return const RuntimeConfigValidation.reject(
        'runtime config is missing; there is no fallback scenario',
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(encoded);
    } on FormatException {
      return const RuntimeConfigValidation.reject('runtime config is corrupt');
    }
    if (decoded is! Map) {
      return const RuntimeConfigValidation.reject(
        'runtime config root must be an object',
      );
    }
    SimsRuntimeConfig config;
    try {
      config = SimsRuntimeConfig.fromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
    } on FormatException catch (error) {
      return RuntimeConfigValidation.reject(error.message);
    }
    if (config.schema != simsRuntimeConfigSchema) {
      return const RuntimeConfigValidation.reject(
        'runtime config schema is unsupported',
      );
    }
    if (config.profileId != installedProfileId) {
      return RuntimeConfigValidation.reject(
        'runtime profile ${config.profileId} does not match installed '
        '$installedProfileId',
      );
    }
    return RuntimeConfigValidation.accept(config);
  }

  RuntimeConfigValidation acknowledge(
    String? encoded, {
    required String profileId,
    required String scenarioId,
    required String nonce,
  }) {
    final validation = decodeAndValidate(encoded);
    if (!validation.accepted) return validation;
    final config = validation.config!;
    if (profileId != installedProfileId || config.profileId != profileId) {
      return const RuntimeConfigValidation.reject(
        'app acknowledged the wrong build profile',
      );
    }
    if (config.scenarioId != scenarioId) {
      return const RuntimeConfigValidation.reject(
        'app acknowledged the wrong scenario',
      );
    }
    if (config.nonce != nonce) {
      return const RuntimeConfigValidation.reject(
        'app acknowledged a stale invocation nonce',
      );
    }
    lastAcceptedScenario = config.scenarioId;
    return RuntimeConfigValidation.accept(config);
  }
}

final class SimsRuntimeState {
  const SimsRuntimeState({
    required this.processRunning,
    required this.appDataDigest,
    required this.identityDigest,
    required this.grantedPermissions,
    required this.notificationCount,
    required this.networkEnabled,
    required this.installedArtifactDigest,
  });

  final bool processRunning;
  final String appDataDigest;
  final String identityDigest;
  final Set<String> grantedPermissions;
  final int notificationCount;
  final bool networkEnabled;
  final String installedArtifactDigest;

  @override
  bool operator ==(Object other) =>
      other is SimsRuntimeState &&
      other.processRunning == processRunning &&
      other.appDataDigest == appDataDigest &&
      other.identityDigest == identityDigest &&
      _sameSet(other.grantedPermissions, grantedPermissions) &&
      other.notificationCount == notificationCount &&
      other.networkEnabled == networkEnabled &&
      other.installedArtifactDigest == installedArtifactDigest;

  @override
  int get hashCode => Object.hash(
    processRunning,
    appDataDigest,
    identityDigest,
    Object.hashAll(grantedPermissions.toList()..sort()),
    notificationCount,
    networkEnabled,
    installedArtifactDigest,
  );
}

abstract final class SimsRuntimeResetter {
  static SimsRuntimeState restore({
    required SimsRuntimeState current,
    required SimsRuntimeState baseline,
  }) {
    if (current.installedArtifactDigest != baseline.installedArtifactDigest) {
      throw StateError(
        'scenario reset cannot swap or rebuild the installed artifact',
      );
    }
    return baseline;
  }
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('runtime $key must be a nonempty string');
  }
  return value;
}

bool _sameSet(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);
