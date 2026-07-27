import 'dart:async';
import 'dart:convert';
import 'dart:io';

const groupMultiPartyRuntimeConfigFileName =
    'group_multi_party_runtime_config.json';
const groupMultiPartySimsArtifactEnvironmentKey =
    'SIMS_ARTIFACT_IOS_SIMULATOR_E2E';
const groupMultiPartyRuntimeConfigStagingMechanism = 'documents-file';

const groupMultiPartySharedDirKey = 'E2E_SHARED_DIR';
const groupMultiPartyDbNameKey = 'E2E_DB_NAME';
const groupMultiPartyRoleKey = 'GROUP_MULTI_PARTY_ROLE';
const groupMultiPartyScenarioKey = 'GROUP_MULTI_PARTY_SCENARIO';
const groupMultiPartyRunIdKey = 'GROUP_MULTI_PARTY_RUN_ID';
const groupMultiPartyModeKey = 'GROUP_MULTI_PARTY_MODE';
const groupMultiPartyRestoreMnemonicKey = 'GROUP_MULTI_PARTY_RESTORE_MNEMONIC';
const groupMultiPartyRestoreIdentityPathKey =
    'GROUP_MULTI_PARTY_RESTORE_IDENTITY_PATH';
const groupMultiPartyReuseExistingIdentityKey =
    'GROUP_MULTI_PARTY_REUSE_EXISTING_IDENTITY';

typedef GroupMultiPartyRuntimeConfigFileExists =
    FutureOr<bool> Function(File file);
typedef GroupMultiPartyRuntimeConfigFileRead =
    FutureOr<String> Function(File file);
typedef GroupMultiPartyRuntimeConfigDelay =
    Future<void> Function(Duration duration);
typedef GroupMultiPartyRuntimeConfigElapsed = Duration Function();

class GroupMultiPartyRuntimeConfig {
  const GroupMultiPartyRuntimeConfig({
    required this.sharedDir,
    required this.role,
    required this.scenario,
    required this.runId,
    required this.mode,
    required this.restoreMnemonic,
    required this.restoreIdentityPath,
    required this.reuseExistingIdentity,
    required this.dbName,
  });

  final String sharedDir;
  final String role;
  final String scenario;
  final String runId;
  final String mode;
  final String restoreMnemonic;
  final String restoreIdentityPath;
  final bool reuseExistingIdentity;
  final String dbName;

  String get stagingMechanism => groupMultiPartyRuntimeConfigStagingMechanism;

  Map<String, Object> toJson() => <String, Object>{
    groupMultiPartySharedDirKey: sharedDir,
    groupMultiPartyRoleKey: role,
    groupMultiPartyScenarioKey: scenario,
    groupMultiPartyRunIdKey: runId,
    groupMultiPartyModeKey: mode,
    groupMultiPartyRestoreMnemonicKey: restoreMnemonic,
    groupMultiPartyRestoreIdentityPathKey: restoreIdentityPath,
    groupMultiPartyReuseExistingIdentityKey: reuseExistingIdentity,
    groupMultiPartyDbNameKey: dbName,
  };
}

/// Loads the exact final Documents runtime-config file.
///
/// Required Android callers wait for the host's atomic pending-file promotion
/// and fail closed when the final file never appears. A sibling `.pending`
/// file is deliberately invisible to this loader. Legacy/non-required callers
/// retain the historical missing-file behavior and receive an empty value map.
Future<Map<String, String>> loadGroupMultiPartyRuntimeConfigValues({
  required File finalConfigFile,
  required bool requireConfig,
  Duration timeout = const Duration(seconds: 30),
  Duration pollInterval = const Duration(milliseconds: 100),
  GroupMultiPartyRuntimeConfigFileExists? fileExists,
  GroupMultiPartyRuntimeConfigFileRead? readFile,
  GroupMultiPartyRuntimeConfigDelay? delay,
  GroupMultiPartyRuntimeConfigElapsed? elapsed,
}) async {
  if (timeout <= Duration.zero) {
    throw ArgumentError.value(timeout, 'timeout', 'must be positive');
  }
  if (pollInterval <= Duration.zero) {
    throw ArgumentError.value(pollInterval, 'pollInterval', 'must be positive');
  }

  final stopwatch = Stopwatch()..start();
  final elapsedNow = elapsed ?? () => stopwatch.elapsed;
  final wait = delay ?? (duration) => Future<void>.delayed(duration);
  final exists = fileExists ?? (file) => file.exists();
  final read = readFile ?? (file) => file.readAsString();

  while (true) {
    if (await exists(finalConfigFile)) {
      try {
        final encoded = await read(finalConfigFile);
        return _decodeRuntimeConfigValues(
          encoded,
          requireCompleteConfig: requireConfig,
        );
      } on FileSystemException {
        // The exact final file may disappear only if a concurrent launcher is
        // replacing app data. Required callers keep waiting within the same
        // finite deadline; legacy callers preserve the original read failure.
        if (!requireConfig) rethrow;
      }
    } else if (!requireConfig) {
      return const <String, String>{};
    }

    final elapsedDuration = elapsedNow();
    if (elapsedDuration >= timeout) {
      throw TimeoutException(
        'Timed out waiting for required runtime config: '
        '${finalConfigFile.path}',
        timeout,
      );
    }
    final remaining = timeout - elapsedDuration;
    await wait(pollInterval < remaining ? pollInterval : remaining);
  }
}

Map<String, String> _decodeRuntimeConfigValues(
  String encoded, {
  required bool requireCompleteConfig,
}) {
  final decoded = jsonDecode(encoded);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException(
      'Group multi-party runtime config must be a JSON object.',
    );
  }

  if (requireCompleteConfig) {
    for (final key in const <String>[
      groupMultiPartySharedDirKey,
      groupMultiPartyRoleKey,
      groupMultiPartyScenarioKey,
      groupMultiPartyRunIdKey,
      groupMultiPartyDbNameKey,
    ]) {
      final value = decoded[key];
      if (value is! String || value.trim().isEmpty) {
        throw StateError(
          'Required runtime config field $key must be a non-empty string.',
        );
      }
    }

    for (final key in const <String>[
      groupMultiPartyModeKey,
      groupMultiPartyRestoreMnemonicKey,
      groupMultiPartyRestoreIdentityPathKey,
    ]) {
      final value = decoded[key];
      if (value != null && value is! String) {
        throw FormatException('Runtime config field $key must be a string.');
      }
    }
    final reuseExistingIdentity =
        decoded[groupMultiPartyReuseExistingIdentityKey];
    if (reuseExistingIdentity != null && reuseExistingIdentity is! bool) {
      throw FormatException(
        'Runtime config field $groupMultiPartyReuseExistingIdentityKey '
        'must be a bool.',
      );
    }
  }

  return decoded.map<String, String>((key, value) => MapEntry(key, '$value'));
}

GroupMultiPartyRuntimeConfig resolveGroupMultiPartyConfig(
  Map<String, String> values,
) {
  return GroupMultiPartyRuntimeConfig(
    sharedDir: _stringValue(values, groupMultiPartySharedDirKey, '/tmp'),
    role: _stringValue(values, groupMultiPartyRoleKey, 'alice'),
    scenario: _stringValue(values, groupMultiPartyScenarioKey, 'gm001'),
    runId: _stringValue(values, groupMultiPartyRunIdKey, 'adhoc'),
    mode: _stringValue(values, groupMultiPartyModeKey, 'proof'),
    restoreMnemonic: _stringValue(
      values,
      groupMultiPartyRestoreMnemonicKey,
      '',
    ),
    restoreIdentityPath: _stringValue(
      values,
      groupMultiPartyRestoreIdentityPathKey,
      '',
    ),
    reuseExistingIdentity: _boolValue(
      values,
      groupMultiPartyReuseExistingIdentityKey,
    ),
    dbName: _stringValue(values, groupMultiPartyDbNameKey, ''),
  );
}

String _stringValue(
  Map<String, String> values,
  String key,
  String defaultValue,
) {
  return values[key]?.trim() ?? defaultValue;
}

bool _boolValue(Map<String, String> values, String key) {
  return values[key]?.trim().toLowerCase() == 'true';
}
