#!/usr/bin/env dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../tool/sims/artifact_evidence.dart';
import '../support/android_app_state_guard.dart';
import '_android_app_package.dart';

const String _capabilityId = 'intro.accept_notification_campaign';
const String _runnerPath =
    'integration_test/scripts/run_intro_accept_notification_android.dart';
const String _artifactEnvironmentKey = 'SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM';
const String _physicalEnvironmentKey = 'SIMS_ANDROID_PHYSICAL_DEVICE_ID';
const String _firstEmulatorEnvironmentKey = 'SIMS_ANDROID_EMULATOR_DEVICE_ID';
const String _secondEmulatorEnvironmentKey =
    'SIMS_ANDROID_EMULATOR_SECOND_DEVICE_ID';
const String _validatorId =
    'integration_test/intro_accept_notification_android_proof_test.dart';
const Duration _scenarioCampaignBudget = Duration(minutes: 24);
const Duration _childTerminationGrace = Duration(seconds: 5);

abstract interface class IntroChildProcess {
  Future<int> get exitCode;

  bool kill(ProcessSignal signal);
}

final class IntroChildSupervisor {
  IntroChildSupervisor(this._child) : _exitCode = _child.exitCode;

  final IntroChildProcess _child;
  final Future<int> _exitCode;
  Future<void>? _termination;
  bool _exited = false;

  Future<int> waitUntil(
    DateTime deadline, {
    Duration terminationGrace = _childTerminationGrace,
  }) async {
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      await terminate(terminationGrace: terminationGrace);
      throw TimeoutException(
        'Intro campaign child reached the shared campaign deadline.',
        Duration.zero,
      );
    }
    try {
      final code = await _exitCode.timeout(remaining);
      _exited = true;
      return code;
    } on TimeoutException {
      await terminate(terminationGrace: terminationGrace);
      throw TimeoutException(
        'Intro campaign child reached the shared campaign deadline.',
        remaining,
      );
    }
  }

  Future<void> terminate({Duration terminationGrace = _childTerminationGrace}) {
    return _termination ??= _terminate(terminationGrace);
  }

  Future<void> _terminate(Duration terminationGrace) async {
    if (_exited) return;
    final terminationRequested = _child.kill(ProcessSignal.sigterm);
    if (terminationRequested) {
      try {
        await _exitCode.timeout(terminationGrace);
        _exited = true;
        return;
      } on TimeoutException {
        // Escalate below.
      }
    } else {
      try {
        await _exitCode.timeout(terminationGrace);
        _exited = true;
        return;
      } on TimeoutException {
        // A false return can race process exit; fail closed with SIGKILL.
      }
    }

    _child.kill(ProcessSignal.sigkill);
    await _exitCode.timeout(
      terminationGrace,
      onTimeout: () => throw TimeoutException(
        'Timed out terminating intro campaign child.',
        terminationGrace,
      ),
    );
    _exited = true;
  }
}

final class _ProcessIntroChild implements IntroChildProcess {
  const _ProcessIntroChild(this.process);

  final Process process;

  @override
  Future<int> get exitCode => process.exitCode;

  @override
  bool kill(ProcessSignal signal) => process.kill(signal);
}

const List<({String id, String testCase})> _scenarios =
    <({String id, String testCase})>[
      (id: 'physical_introducer', testCase: 'TC-12'),
      (id: 'emulator_introducer', testCase: 'TC-13'),
    ];

const List<String> _requiredChecks = <String>[
  'targetsDiscovered',
  'centralPreparedArtifactInstalled',
  'identitiesCollected',
  'contactsEstablished',
  'introductionSent',
  'copyExtractorFeasibility',
  'b_acceptIntroducerTerminatedBeforeSend',
  'b_acceptIntroducerStillTerminatedBeforeTap',
  'b_acceptAcceptanceCopy',
  'b_acceptBoundedNodeTap',
  'b_acceptFinalPeerIsRecipient',
  'b_acceptStatusContext',
  'c_acceptIntroducerTerminatedBeforeSend',
  'c_acceptIntroducerStillTerminatedBeforeTap',
  'c_acceptAcceptanceCopy',
  'c_acceptBoundedNodeTap',
  'c_acceptFinalPeerIsRecipient',
  'c_acceptStatusContext',
  'zeroNavigationErrors',
];

final RegExp _safeAndroidId = RegExp(r'^[A-Za-z0-9._:-]+$');
final RegExp _emulatorId = RegExp(r'^emulator-[0-9]+$');

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

_AdapterResult _failed({
  required String detail,
  required int childExitCode,
  required bool artifactPresent,
  int assertionsAttempted = 1,
}) => _AdapterResult(<String, Object?>{
  'status': 'FAIL',
  'assertionsAttempted': assertionsAttempted,
  'artifactPresent': artifactPresent,
  'printOnly': false,
  'blocker': 'test',
  'exitCode': childExitCode == 0 ? 1 : childExitCode,
  'detail': detail,
}, childExitCode == 0 ? 1 : childExitCode);

_AdapterResult _passed(SimsArtifactEvidence evidence) =>
    _AdapterResult(<String, Object?>{
      'status': 'PASS',
      'assertionsAttempted': _scenarios.length,
      'artifactPresent': true,
      'printOnly': false,
      'exitCode': 0,
      'detail':
          'Both Android intro acceptance notification campaigns passed using '
          'one centrally prepared FCM APK.',
      'artifactEvidence': evidence.toJson(),
    }, 0);

Future<_AdapterResult> _run(Map<String, String> environment) async {
  final relayAddresses = environment['MKNOON_RELAY_ADDRESSES']?.trim();
  if (relayAddresses == null || relayAddresses.isEmpty) {
    return _blocked(
      'environment',
      'MKNOON_RELAY_ADDRESSES is required for the staging-relay campaign.',
    );
  }
  if (relayAddresses.contains(RegExp(r'[\r\n]'))) {
    return _blocked(
      'environment',
      'MKNOON_RELAY_ADDRESSES must be a single safe value.',
    );
  }

  final artifactPath = environment[_artifactEnvironmentKey]?.trim();
  if (artifactPath == null || artifactPath.isEmpty) {
    return _blocked(
      'missingArtifact',
      '$_artifactEnvironmentKey is required; child builds are forbidden.',
    );
  }
  final artifact = File(artifactPath).absolute;
  if (!_isRegularFile(artifact)) {
    return _blocked(
      'missingArtifact',
      '$_artifactEnvironmentKey is not a regular prepared APK: $artifactPath',
    );
  }

  final credentialPath =
      environment['SIMS_PROVIDER_FCM_CREDENTIAL_PATH']?.trim().isNotEmpty ==
          true
      ? environment['SIMS_PROVIDER_FCM_CREDENTIAL_PATH']!.trim()
      : environment['FIREBASE_SERVICE_ACCOUNT']?.trim();
  if (credentialPath == null || credentialPath.isEmpty) {
    return _blocked(
      'credentials',
      'FIREBASE_SERVICE_ACCOUNT (or SIMS_PROVIDER_FCM_CREDENTIAL_PATH) is '
          'required for the real FCM proof boundary.',
    );
  }
  final credential = File(credentialPath).absolute;
  if (!_isUsableServiceAccount(credential)) {
    return _blocked(
      'credentials',
      'The configured FCM service-account path is not a readable JSON file '
          'with project_id: $credentialPath',
    );
  }

  final physical = environment[_physicalEnvironmentKey]?.trim();
  final firstEmulator = environment[_firstEmulatorEnvironmentKey]?.trim();
  final secondEmulator = environment[_secondEmulatorEnvironmentKey]?.trim();
  final missingTargets = <String>[
    if (physical == null || physical.isEmpty) _physicalEnvironmentKey,
    if (firstEmulator == null || firstEmulator.isEmpty)
      _firstEmulatorEnvironmentKey,
    if (secondEmulator == null || secondEmulator.isEmpty)
      _secondEmulatorEnvironmentKey,
  ];
  if (missingTargets.isNotEmpty) {
    return _blocked(
      'targetUnavailable',
      'The Android-only three-party campaign requires one physical target '
          'and two emulators; missing ${missingTargets.join(', ')}.',
    );
  }
  final targets = <String>[physical!, firstEmulator!, secondEmulator!];
  if (targets.toSet().length != 3 ||
      targets.any((target) => !_safeAndroidId.hasMatch(target)) ||
      !_emulatorId.hasMatch(firstEmulator) ||
      !_emulatorId.hasMatch(secondEmulator)) {
    return _blocked(
      'targetUnavailable',
      'The three Android IDs must be distinct and safe, and both emulator '
          'IDs must use the adb emulator-<port> form.',
    );
  }

  final runner = File(_runnerPath);
  if (!_isRegularFile(runner)) {
    return _blocked('missingDriver', 'Intro campaign runner is missing.');
  }

  late final AndroidAppStateGuard stateGuard;
  try {
    stateGuard = await AndroidAppStateGuard.capture(
      devices: targets,
      packageName: resolveAndroidAppPackage(),
      backupLabel: 'intro-accept',
    );
  } on AndroidAppStateBlocked catch (error) {
    return _blocked('environment', error.detail);
  } on AndroidAppStateFailure catch (error) {
    return _failed(
      detail: error.detail,
      childExitCode: 1,
      artifactPresent: false,
      assertionsAttempted: 0,
    );
  }

  final proofDirectory = _proofDirectory(environment);
  final captureRoot = Directory(
    '${proofDirectory.path}${Platform.pathSeparator}'
    'capture-${DateTime.now().toUtc().microsecondsSinceEpoch}-$pid',
  )..createSync(recursive: true);
  final capturedArtifacts = <Map<String, Object?>>[];
  IntroChildSupervisor? activeChild;

  try {
    for (final scenario in _scenarios) {
      await stateGuard.prepareFreshInstalls(artifact);
      final scenarioDirectory = Directory(
        '${captureRoot.path}${Platform.pathSeparator}${scenario.id}',
      )..createSync(recursive: true);
      final introducer = scenario.id == 'physical_introducer'
          ? physical
          : firstEmulator;
      final recipient = scenario.id == 'physical_introducer'
          ? firstEmulator
          : physical;
      final scenarioDeadline = DateTime.now().toUtc().add(
        _scenarioCampaignBudget,
      );

      late final Process child;
      try {
        child = await Process.start('dart', <String>[
          'run',
          runner.path,
          '--scenario',
          scenario.id,
          '--introducer',
          introducer,
          '--recipient',
          recipient,
          '--introduced-android',
          secondEmulator,
          '--artifact',
          artifact.path,
          '--artifact-dir',
          scenarioDirectory.path,
          '--campaign-deadline-epoch-ms',
          '${scenarioDeadline.millisecondsSinceEpoch}',
          '--android-state-prepared',
        ], environment: environment);
      } on ProcessException catch (error) {
        return _blocked(
          'missingDriver',
          'Could not launch the intro campaign runner: ${error.message}',
        );
      }

      // The adapter alone owns stdout's structured Sims result sentinel.
      final stdoutDone = child.stdout.listen(stderr.add).asFuture<void>();
      final stderrDone = child.stderr.listen(stderr.add).asFuture<void>();
      activeChild = IntroChildSupervisor(_ProcessIntroChild(child));
      late final int childExitCode;
      try {
        childExitCode = await activeChild.waitUntil(scenarioDeadline);
      } on TimeoutException {
        await _awaitChildOutputDrain(stdoutDone, stderrDone);
        return _failed(
          detail:
              '${scenario.id} intro acceptance capture exceeded its shared '
              '${_scenarioCampaignBudget.inMinutes}-minute campaign deadline; '
              'the child was terminated before app-state restoration.',
          childExitCode: 1,
          artifactPresent: false,
          assertionsAttempted: capturedArtifacts.length + 1,
        );
      }
      await _awaitChildOutputDrain(stdoutDone, stderrDone);
      if (childExitCode != 0) {
        return _failed(
          detail:
              '${scenario.id} intro acceptance capture exited with code '
              '$childExitCode.',
          childExitCode: childExitCode,
          artifactPresent: false,
          assertionsAttempted: capturedArtifacts.length + 1,
        );
      }

      final captured = File(
        '${scenarioDirectory.path}${Platform.pathSeparator}${scenario.id}.json',
      );
      final validation = _validateArtifact(
        captured,
        scenario: scenario,
        expectedDevices: <String>[introducer, recipient, secondEmulator],
      );
      if (validation != null) {
        return _failed(
          detail: '${scenario.id} artifact was rejected: $validation',
          childExitCode: 1,
          artifactPresent: captured.existsSync(),
          assertionsAttempted: capturedArtifacts.length + 1,
        );
      }
      capturedArtifacts.add(<String, Object?>{
        'scenario': scenario.id,
        'path': captured.resolveSymbolicLinksSync(),
        'sha256': sha256.convert(captured.readAsBytesSync()).toString(),
      });
      activeChild = null;
    }
  } finally {
    try {
      await activeChild?.terminate();
    } finally {
      await stateGuard.restoreAll();
    }
  }

  final evidence = writeSimsArtifactEvidenceSync(
    directory: proofDirectory,
    capabilityId: _capabilityId,
    validatorIds: const <String>[_validatorId],
    payload: <String, Object?>{
      'status': 'passed',
      'scenarioIds': _scenarios.map((scenario) => scenario.id).toList(),
      'targetIds': targets,
      'preparedArtifactPath': artifact.resolveSymbolicLinksSync(),
      'preparedArtifactSha256': sha256
          .convert(artifact.readAsBytesSync())
          .toString(),
      'captureArtifacts': capturedArtifacts,
      'childBuildCount': 0,
    },
  );
  return _passed(evidence);
}

Future<void> _awaitChildOutputDrain(
  Future<void> stdoutDone,
  Future<void> stderrDone,
) {
  return Future.wait<void>(<Future<void>>[stdoutDone, stderrDone]).timeout(
    const Duration(seconds: 10),
    onTimeout: () => throw TimeoutException(
      'Timed out draining terminated intro campaign child output.',
      const Duration(seconds: 10),
    ),
  );
}

String? _validateArtifact(
  File artifact, {
  required ({String id, String testCase}) scenario,
  required List<String> expectedDevices,
}) {
  if (!_isRegularFile(artifact)) return 'authoritative JSON is missing';
  late final Map<String, Object?> decoded;
  try {
    final value = jsonDecode(artifact.readAsStringSync());
    if (value is! Map) return 'root must be an object';
    decoded = value.map<String, Object?>(
      (key, value) => MapEntry('$key', value),
    );
  } on Object catch (error) {
    return 'JSON could not be decoded: $error';
  }
  if (decoded['testCase'] != scenario.testCase ||
      decoded['scenario'] != scenario.id ||
      decoded['status'] != 'passed') {
    return 'scenario, testCase, or passed status does not match';
  }
  final devices = decoded['devices'];
  if (devices is! List ||
      devices.length != expectedDevices.length ||
      !_sameStrings(devices, expectedDevices)) {
    return 'device binding does not match the orchestrated topology';
  }
  if (decoded['copyExtractor'] != 'dumpsys' &&
      decoded['copyExtractor'] != 'uiautomator') {
    return 'copy extractor was not a bounded Android extractor';
  }
  final checks = decoded['checks'];
  if (checks is! Map) return 'checks must be an object';
  for (final required in _requiredChecks) {
    if (checks[required] != true) return 'required check "$required" is false';
  }
  return null;
}

bool _sameStrings(List<Object?> actual, List<String> expected) {
  for (var index = 0; index < expected.length; index++) {
    if (actual[index] != expected[index]) return false;
  }
  return true;
}

bool _isRegularFile(File file) =>
    FileSystemEntity.typeSync(file.path, followLinks: true) ==
    FileSystemEntityType.file;

bool _isUsableServiceAccount(File file) {
  if (!_isRegularFile(file)) return false;
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    return decoded is Map && '${decoded['project_id'] ?? ''}'.trim().isNotEmpty;
  } on Object {
    return false;
  }
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
  } on AndroidAppStateFailure catch (error, stackTrace) {
    stderr.writeln(stackTrace);
    result = _failed(
      detail: error.detail,
      childExitCode: 1,
      artifactPresent: false,
      assertionsAttempted: 0,
    );
  } catch (error, stackTrace) {
    stderr.writeln(stackTrace);
    result = _blocked(
      'harness',
      'Intro acceptance Sims adapter failed before a verdict: $error',
    );
  }
  stdout.writeln('SIMS_RESULT_JSON=${jsonEncode(result.json)}');
  exitCode = result.processExitCode;
}
