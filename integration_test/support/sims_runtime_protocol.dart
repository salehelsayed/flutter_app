import 'dart:convert';

const String simsRuntimeConfigSchema = 'mknoon.sims.runtime-config.v1';
const String simsRuntimeAckSchema = 'mknoon.sims.runtime-ack.v1';
const String simsAndroidStandardProfileId = 'android.e2e.standard';
const String simsAndroidMainProfileId = 'android.e2e.main';
const String simsAndroidVoiceRecorderScenarioId =
    'android.voice_recorder_native_smoke';
const String simsAndroidCriticalPerformanceScenarioId =
    'performance.device.critical';
const String simsAndroidVoiceMessageScenarioId = 'android.voice_message_e2e';
const String simsPrimaryRole = 'primary';
const String simsVoiceMessageSenderRole = 'sender';
const String simsVoiceMessageReceiverRole = 'receiver';
const String simsRuntimeDirectory = 'sims';
const String simsRuntimeConfigFileName = 'runtime-config.json';
const String simsRuntimeAckFileName = 'runtime-ack.json';
const String simsRuntimeResultFileName = 'runtime-result.json';
const String simsRuntimeConfigRelativePath =
    'files/$simsRuntimeDirectory/$simsRuntimeConfigFileName';
const String simsRuntimeAckRelativePath =
    'files/$simsRuntimeDirectory/$simsRuntimeAckFileName';
const String simsRuntimeResultRelativePath =
    'files/$simsRuntimeDirectory/$simsRuntimeResultFileName';

typedef SimsRuntimeScenarioHandler =
    Future<void> Function(SimsRuntimeInvocation invocation);
typedef SimsRuntimeScenarioValidator =
    String? Function(SimsRuntimeInvocation invocation);
typedef SimsRuntimeAckWriter = Future<void> Function(SimsRuntimeAck ack);

final class SimsRuntimeInvocation {
  const SimsRuntimeInvocation({
    required this.schema,
    required this.profileId,
    required this.scenarioId,
    required this.role,
    required this.runId,
    required this.nonce,
    required this.values,
  });

  factory SimsRuntimeInvocation.fromJson(Map<String, Object?> json) {
    final values = json['values'];
    if (values is! Map) {
      throw const FormatException('runtime values must be an object');
    }
    return SimsRuntimeInvocation(
      schema: _requiredToken(json, 'schema'),
      profileId: _requiredToken(json, 'profileId'),
      scenarioId: _requiredToken(json, 'scenarioId'),
      role: _requiredToken(json, 'role'),
      runId: _requiredToken(json, 'runId'),
      nonce: _requiredToken(json, 'nonce'),
      values: Map<String, Object?>.unmodifiable(
        values.map((key, value) => MapEntry('$key', value)),
      ),
    );
  }

  factory SimsRuntimeInvocation.decode(String encoded) {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map) {
      throw const FormatException('runtime config root must be an object');
    }
    return SimsRuntimeInvocation.fromJson(
      decoded.map<String, Object?>((key, value) => MapEntry('$key', value)),
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

  SimsRuntimeInvocation copyWith({
    String? schema,
    String? profileId,
    String? scenarioId,
    String? role,
    String? runId,
    String? nonce,
    Map<String, Object?>? values,
  }) => SimsRuntimeInvocation(
    schema: schema ?? this.schema,
    profileId: profileId ?? this.profileId,
    scenarioId: scenarioId ?? this.scenarioId,
    role: role ?? this.role,
    runId: runId ?? this.runId,
    nonce: nonce ?? this.nonce,
    values: values ?? this.values,
  );
}

final class SimsRuntimeAck {
  const SimsRuntimeAck({
    required this.schema,
    required this.profileId,
    required this.scenarioId,
    required this.role,
    required this.runId,
    required this.nonce,
    required this.accepted,
    required this.detail,
  });

  factory SimsRuntimeAck.accept(SimsRuntimeInvocation invocation) =>
      SimsRuntimeAck(
        schema: simsRuntimeAckSchema,
        profileId: invocation.profileId,
        scenarioId: invocation.scenarioId,
        role: invocation.role,
        runId: invocation.runId,
        nonce: invocation.nonce,
        accepted: true,
        detail: 'runtime invocation accepted',
      );

  factory SimsRuntimeAck.reject({
    required String installedProfileId,
    required String detail,
    SimsRuntimeInvocation? invocation,
  }) => SimsRuntimeAck(
    schema: simsRuntimeAckSchema,
    profileId: invocation?.profileId ?? _placeholder(installedProfileId),
    scenarioId: invocation?.scenarioId ?? 'invalid-scenario',
    role: invocation?.role ?? 'invalid-role',
    runId: invocation?.runId ?? 'invalid-run',
    nonce: invocation?.nonce ?? 'invalid-nonce',
    accepted: false,
    detail: detail,
  );

  factory SimsRuntimeAck.fromJson(Map<String, Object?> json) {
    final accepted = json['accepted'];
    if (accepted is! bool) {
      throw const FormatException('runtime ack accepted must be boolean');
    }
    final detail = json['detail'];
    if (detail is! String || detail.trim().isEmpty) {
      throw const FormatException('runtime ack detail must be nonempty');
    }
    return SimsRuntimeAck(
      schema: _requiredToken(json, 'schema'),
      profileId: _requiredToken(json, 'profileId'),
      scenarioId: _requiredToken(json, 'scenarioId'),
      role: _requiredToken(json, 'role'),
      runId: _requiredToken(json, 'runId'),
      nonce: _requiredToken(json, 'nonce'),
      accepted: accepted,
      detail: detail,
    );
  }

  final String schema;
  final String profileId;
  final String scenarioId;
  final String role;
  final String runId;
  final String nonce;
  final bool accepted;
  final String detail;

  Map<String, Object?> toJson() => <String, Object?>{
    'schema': schema,
    'profileId': profileId,
    'scenarioId': scenarioId,
    'role': role,
    'runId': runId,
    'nonce': nonce,
    'accepted': accepted,
    'detail': detail,
  };

  SimsRuntimeAck copyWith({
    String? schema,
    String? profileId,
    String? scenarioId,
    String? role,
    String? runId,
    String? nonce,
    bool? accepted,
    String? detail,
  }) => SimsRuntimeAck(
    schema: schema ?? this.schema,
    profileId: profileId ?? this.profileId,
    scenarioId: scenarioId ?? this.scenarioId,
    role: role ?? this.role,
    runId: runId ?? this.runId,
    nonce: nonce ?? this.nonce,
    accepted: accepted ?? this.accepted,
    detail: detail ?? this.detail,
  );
}

final class SimsRuntimeProtocolValidation {
  const SimsRuntimeProtocolValidation._(this.accepted, this.detail);

  const SimsRuntimeProtocolValidation.accept()
    : this._(true, 'runtime handshake accepted');

  const SimsRuntimeProtocolValidation.reject(String detail)
    : this._(false, detail);

  final bool accepted;
  final String detail;
}

Future<void> dispatchSimsRuntimeEncodedConfig({
  required String? encodedConfig,
  required String installedProfileId,
  required String supportedRole,
  Set<String> additionalSupportedRoles = const <String>{},
  required Map<String, SimsRuntimeScenarioHandler> scenarioHandlers,
  Map<String, SimsRuntimeScenarioValidator> scenarioValidators =
      const <String, SimsRuntimeScenarioValidator>{},
  required SimsRuntimeAckWriter writeAck,
}) async {
  SimsRuntimeInvocation? invocation;
  String? rejection;
  if (encodedConfig == null || encodedConfig.trim().isEmpty) {
    rejection = 'runtime config is missing; no fallback scenario is allowed';
  } else {
    try {
      invocation = SimsRuntimeInvocation.decode(encodedConfig);
    } on Object catch (error) {
      rejection = 'runtime config is invalid: $error';
    }
  }

  rejection ??= _validateInvocation(
    invocation!,
    installedProfileId: installedProfileId,
    supportedRoles: <String>{supportedRole, ...additionalSupportedRoles},
    scenarioHandlers: scenarioHandlers,
    scenarioValidators: scenarioValidators,
  );

  if (rejection != null) {
    await writeAck(
      SimsRuntimeAck.reject(
        installedProfileId: installedProfileId,
        invocation: invocation,
        detail: rejection,
      ),
    );
    throw StateError(rejection);
  }

  final accepted = SimsRuntimeAck.accept(invocation!);
  await writeAck(accepted);
  await scenarioHandlers[invocation.scenarioId]!(invocation);
}

SimsRuntimeProtocolValidation validateSimsRuntimeAck(
  Map<String, Object?> encodedAck,
  SimsRuntimeInvocation expected,
) {
  late final SimsRuntimeAck ack;
  try {
    ack = SimsRuntimeAck.fromJson(encodedAck);
  } on Object catch (error) {
    return SimsRuntimeProtocolValidation.reject(
      'runtime ack is invalid: $error',
    );
  }
  if (ack.schema != simsRuntimeAckSchema) {
    return const SimsRuntimeProtocolValidation.reject(
      'runtime ack schema is unsupported',
    );
  }
  if (!ack.accepted) {
    return SimsRuntimeProtocolValidation.reject(
      'app rejected runtime invocation: ${ack.detail}',
    );
  }
  final mismatches = <String>[
    if (ack.profileId != expected.profileId) 'profileId',
    if (ack.scenarioId != expected.scenarioId) 'scenarioId',
    if (ack.role != expected.role) 'role',
    if (ack.runId != expected.runId) 'runId',
    if (ack.nonce != expected.nonce) 'nonce',
  ];
  if (mismatches.isNotEmpty) {
    return SimsRuntimeProtocolValidation.reject(
      'runtime ack mismatched ${mismatches.join(', ')}',
    );
  }
  return const SimsRuntimeProtocolValidation.accept();
}

String? _validateInvocation(
  SimsRuntimeInvocation invocation, {
  required String installedProfileId,
  required Set<String> supportedRoles,
  required Map<String, SimsRuntimeScenarioHandler> scenarioHandlers,
  required Map<String, SimsRuntimeScenarioValidator> scenarioValidators,
}) {
  if (installedProfileId.trim().isEmpty) {
    return 'installed build profile is missing';
  }
  if (invocation.schema != simsRuntimeConfigSchema) {
    return 'runtime config schema is unsupported';
  }
  if (invocation.profileId != installedProfileId) {
    return 'runtime profile ${invocation.profileId} does not match installed '
        '$installedProfileId';
  }
  if (!supportedRoles.contains(invocation.role)) {
    return 'runtime role ${invocation.role} is unsupported';
  }
  if (!scenarioHandlers.containsKey(invocation.scenarioId)) {
    return 'runtime scenario ${invocation.scenarioId} has no registered handler';
  }
  return scenarioValidators[invocation.scenarioId]?.call(invocation);
}

String _requiredToken(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String ||
      value.isEmpty ||
      value.length > 160 ||
      !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(value)) {
    throw FormatException('runtime $key must be a safe nonempty token');
  }
  return value;
}

String _placeholder(String value) => value.trim().isEmpty
    ? 'missing-profile'
    : value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
