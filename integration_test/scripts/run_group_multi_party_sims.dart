#!/usr/bin/env dart

import 'dart:convert';
import 'dart:io';

import '../../tool/sims/artifact_evidence.dart';
import 'group_multi_party_device_criteria.dart';
import 'group_multi_party_runtime_config.dart';

const _runnerPath =
    'integration_test/scripts/run_group_multi_party_device_real.dart';
const _capabilityId = 'groups.multi_party_release';
const _artifactValidatorId = 'validateGroupMultiPartyLedger';
const _disposableSimulatorIdsEnvironment = 'SIMS_IOS_DISPOSABLE_SIMULATOR_IDS';
const _simulatorEnvironmentKeys = <String>[
  'SIMS_IOS_SIMULATOR_A_DEVICE_ID',
  'SIMS_IOS_SIMULATOR_B_DEVICE_ID',
  'SIMS_IOS_SIMULATOR_C_DEVICE_ID',
  'SIMS_IOS_SIMULATOR_D_DEVICE_ID',
];

final _simulatorIdPattern = RegExp(
  r'^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$',
  caseSensitive: false,
);

final class _AdapterResult {
  const _AdapterResult(this.json, this.processExitCode);

  final Map<String, Object?> json;
  final int processExitCode;
}

_AdapterResult _blocked(String blocker, String detail) =>
    _AdapterResult(<String, Object?>{
      'status': 'BLOCKED',
      'assertionsAttempted': 0,
      'artifactPresent': false,
      'printOnly': false,
      'blocker': blocker,
      'exitCode': 78,
      'detail': detail,
    }, 78);

_AdapterResult _failed(int childExitCode) => _AdapterResult(<String, Object?>{
  'status': 'FAIL',
  'assertionsAttempted': 1,
  'artifactPresent': true,
  'printOnly': false,
  'blocker': 'test',
  'exitCode': childExitCode == 0 ? 1 : childExitCode,
  'detail': 'Group multi-party smoke exited with code $childExitCode.',
}, childExitCode == 0 ? 1 : childExitCode);

_AdapterResult _passed(SimsArtifactEvidence artifactEvidence) =>
    _AdapterResult(<String, Object?>{
      'status': 'PASS',
      'assertionsAttempted': smokeGroupMultiPartyDeviceScenarioIds.length,
      'artifactPresent': true,
      'printOnly': false,
      'exitCode': 0,
      'detail':
          'Group multi-party release smoke passed '
          '${smokeGroupMultiPartyDeviceScenarioIds.length} scenarios.',
      'artifactEvidence': artifactEvidence.toJson(),
    }, 0);

Future<_AdapterResult> _run(Map<String, String> environment) async {
  final relayAddresses = environment['MKNOON_RELAY_ADDRESSES']?.trim();
  if (relayAddresses == null || relayAddresses.isEmpty) {
    return _blocked(
      'environment',
      'MKNOON_RELAY_ADDRESSES is required for the real relay smoke.',
    );
  }

  final runnerAppPath = environment[groupMultiPartySimsArtifactEnvironmentKey]
      ?.trim();
  if (runnerAppPath == null || runnerAppPath.isEmpty) {
    return _blocked(
      'missingArtifact',
      '$groupMultiPartySimsArtifactEnvironmentKey is required.',
    );
  }
  final runnerApp = Directory(runnerAppPath);
  if (!runnerApp.existsSync() ||
      !File('${runnerApp.path}/Info.plist').existsSync()) {
    return _blocked(
      'missingArtifact',
      '$groupMultiPartySimsArtifactEnvironmentKey is not a usable Runner.app: '
          '$runnerAppPath',
    );
  }

  final missingTargetKeys = <String>[];
  final simulatorIds = <String>[];
  for (final key in _simulatorEnvironmentKeys) {
    final value = environment[key]?.trim();
    if (value == null || value.isEmpty) {
      missingTargetKeys.add(key);
    } else {
      simulatorIds.add(value);
    }
  }
  if (missingTargetKeys.isNotEmpty) {
    return _blocked(
      'targetUnavailable',
      'Four explicit iOS Simulator targets are required; missing '
          '${missingTargetKeys.join(', ')}.',
    );
  }
  if (simulatorIds.toSet().length != _simulatorEnvironmentKeys.length ||
      simulatorIds.any((id) => !_simulatorIdPattern.hasMatch(id))) {
    return _blocked(
      'targetUnavailable',
      'The four iOS Simulator target IDs must be distinct simulator UUIDs.',
    );
  }
  final disposableIds = (environment[_disposableSimulatorIdsEnvironment] ?? '')
      .split(',')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet();
  if (disposableIds.length != simulatorIds.length ||
      !disposableIds.containsAll(simulatorIds)) {
    return _blocked(
      'permissions',
      'The four resolved simulators are not exactly authorized as disposable '
          'by $_disposableSimulatorIdsEnvironment; generic available '
          'simulators cannot be uninstalled or data-reset.',
    );
  }

  Process child;
  try {
    child = await Process.start(
      'dart',
      <String>[
        'run',
        _runnerPath,
        '--scenario',
        'smoke',
        '-d',
        simulatorIds.join(','),
      ],
      environment: <String, String>{
        ...environment,
        groupMultiPartySimsArtifactEnvironmentKey: runnerApp.path,
        // Retain the legacy cross-process reuse contract as a second guard.
        'GMP_SKIP_HARNESS_BUILD': '1',
      },
    );
  } on ProcessException catch (error) {
    return _blocked(
      'missingDriver',
      'Could not launch the group multi-party runner: ${error.message}',
    );
  }

  // Child diagnostics are intentionally kept off stdout. The adapter is the
  // sole owner of the one structured result sentinel consumed by `$sims`.
  final stdoutDone = child.stdout.listen(stderr.add).asFuture<void>();
  final stderrDone = child.stderr.listen(stderr.add).asFuture<void>();
  final childExitCode = await child.exitCode;
  await Future.wait<void>(<Future<void>>[stdoutDone, stderrDone]);

  if (childExitCode == 0) {
    final evidence = writeSimsArtifactEvidenceSync(
      directory: _proofDirectory(environment),
      capabilityId: _capabilityId,
      validatorIds: const <String>[_artifactValidatorId],
      payload: <String, Object?>{
        'status': 'passed',
        'scenario': 'smoke',
        'scenarioIds': smokeGroupMultiPartyDeviceScenarioIds,
        'targetIds': simulatorIds,
        'runnerAppPath': runnerApp.resolveSymbolicLinksSync(),
        'childExitCode': childExitCode,
      },
    );
    return _passed(evidence);
  }
  if (childExitCode == 64) {
    return _blocked(
      'environment',
      'Group multi-party smoke rejected its relay or target configuration.',
    );
  }
  return _failed(childExitCode);
}

Directory _proofDirectory(Map<String, String> environment) {
  final configured = environment['SIMS_PROOF_DIRECTORY']?.trim();
  if (configured != null && configured.isNotEmpty) {
    return Directory(configured).absolute;
  }
  return Directory('build/sims/proofs/$_capabilityId').absolute;
}

Future<void> main() async {
  late final _AdapterResult result;
  try {
    result = await _run(Platform.environment);
  } catch (error, stackTrace) {
    stderr.writeln(stackTrace);
    result = _blocked(
      'harness',
      'Group multi-party sims adapter failed before a verdict: $error',
    );
  }
  stdout.writeln('SIMS_RESULT_JSON=${jsonEncode(result.json)}');
  exitCode = result.processExitCode;
}
