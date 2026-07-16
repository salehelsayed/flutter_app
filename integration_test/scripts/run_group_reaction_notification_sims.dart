#!/usr/bin/env dart

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../tool/sims/artifact_evidence.dart';
import '../support/android_app_state_guard.dart';
import '_android_app_package.dart';
import 'group_reaction_notification_device_criteria.dart';

const String _capabilityId = 'groups.reaction_notification_campaign';
const String _runnerPath =
    'integration_test/scripts/run_group_reaction_notification_device.dart';
const String _artifactEnvironmentKey = 'SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM';
const String _physicalEnvironmentKey = 'SIMS_ANDROID_PHYSICAL_DEVICE_ID';
const String _emulatorEnvironmentKey = 'SIMS_ANDROID_EMULATOR_DEVICE_ID';
const String _artifactValidator =
    'integration_test/scripts/validate_group_reaction_notification_artifacts.dart';

final RegExp _safeAndroidId = RegExp(r'^[A-Za-z0-9._:-]+$');
final RegExp _emulatorId = RegExp(r'^emulator-[0-9]+$');

final List<GroupReactionNotificationScenario> _androidScenarios =
    groupReactionNotificationScenarios
        .where(
          (scenario) =>
              scenario.senderPlatform == 'android' &&
              scenario.recipientPlatform == 'android',
        )
        .toList(growable: false);

final class _AdapterResult {
  const _AdapterResult(this.json, this.processExitCode);

  final Map<String, Object?> json;
  final int processExitCode;
}

_AdapterResult _blocked(
  String blocker,
  String detail, {
  List<String>? scenarioIds,
}) => _AdapterResult(<String, Object?>{
  'status': 'BLOCKED',
  'assertionsAttempted': 0,
  'artifactPresent': false,
  'printOnly': false,
  'blocker': blocker,
  'exitCode': 78,
  'detail': detail,
  'scenarioIds': scenarioIds ?? const <String>[],
}, 78);

_AdapterResult _failed({
  required String detail,
  required int childExitCode,
  required int assertionsAttempted,
  required bool artifactPresent,
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
      'assertionsAttempted': _androidScenarios.length,
      'artifactPresent': true,
      'printOnly': false,
      'exitCode': 0,
      'detail':
          'All four Android group message/reaction notification scenarios '
          'passed with one centrally prepared production-FCM APK.',
      'artifactEvidence': evidence.toJson(),
    }, 0);

Future<_AdapterResult> _run(Map<String, String> environment) async {
  final relayAddresses = environment['MKNOON_RELAY_ADDRESSES']?.trim();
  final relayTarget = environment['MKNOON_257_RELAY_TARGET']?.trim();
  if (relayAddresses == null ||
      relayAddresses.isEmpty ||
      relayAddresses.contains(RegExp(r'[\r\n]')) ||
      relayTarget == null ||
      relayTarget.isEmpty ||
      relayTarget.contains(RegExp(r'[\r\n]'))) {
    return _blocked(
      'environment',
      'MKNOON_RELAY_ADDRESSES and MKNOON_257_RELAY_TARGET are required for '
          'the explicit staging relay boundary.',
    );
  }

  final artifactPath = environment[_artifactEnvironmentKey]?.trim();
  if (artifactPath == null || artifactPath.isEmpty) {
    return _blocked(
      'missingArtifact',
      '$_artifactEnvironmentKey is required; campaign child builds are '
          'forbidden.',
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
  if (credentialPath == null ||
      credentialPath.isEmpty ||
      !_isUsableServiceAccount(File(credentialPath).absolute)) {
    return _blocked(
      'credentials',
      'A readable FCM service-account JSON containing project_id is '
          'required.',
    );
  }

  final relayKeyPath = environment['MKNOON_257_RELAY_KEY']?.trim();
  final stagingPath = environment['MKNOON_257_STAGING_MANIFEST']?.trim();
  if (relayKeyPath == null ||
      relayKeyPath.isEmpty ||
      !_isRegularFile(File(relayKeyPath).absolute) ||
      stagingPath == null ||
      stagingPath.isEmpty ||
      !_isRegularFile(File(stagingPath).absolute)) {
    return _blocked(
      'environment',
      'MKNOON_257_RELAY_KEY and MKNOON_257_STAGING_MANIFEST must name '
          'readable staging files.',
    );
  }
  final staging = File(stagingPath).absolute;
  final stagingError = _validateStagingManifest(staging);
  if (stagingError != null) return _blocked('environment', stagingError);

  final physical = environment[_physicalEnvironmentKey]?.trim();
  final emulator = environment[_emulatorEnvironmentKey]?.trim();
  if (physical == null ||
      physical.isEmpty ||
      emulator == null ||
      emulator.isEmpty ||
      physical == emulator ||
      !_safeAndroidId.hasMatch(physical) ||
      !_emulatorId.hasMatch(emulator)) {
    return _blocked(
      'targetUnavailable',
      'One explicit physical Android ID and one distinct adb emulator ID are '
          'required for all four scenarios.',
    );
  }

  final runner = File(_runnerPath).absolute;
  if (!_isRegularFile(runner)) {
    return _blocked('missingDriver', 'The group reaction runner is missing.');
  }

  try {
    final listed = await Process.run('adb', const <String>['devices']);
    final output = '${listed.stdout}';
    if (listed.exitCode != 0 ||
        !output.contains('$physical\tdevice') ||
        !output.contains('$emulator\tdevice')) {
      return _blocked(
        'deviceLost',
        'An explicitly assigned Android target disappeared before state '
            'capture.',
        scenarioIds: _androidScenarios
            .map((scenario) => scenario.id)
            .toList(growable: false),
      );
    }
  } on ProcessException {
    return _blocked(
      'deviceLost',
      'ADB could not verify the explicitly assigned Android targets.',
      scenarioIds: _androidScenarios
          .map((scenario) => scenario.id)
          .toList(growable: false),
    );
  }

  late final AndroidAppStateGuard stateGuard;
  try {
    stateGuard = await AndroidAppStateGuard.capture(
      devices: <String>[physical, emulator],
      packageName: resolveAndroidAppPackage(),
      backupLabel: 'group-reaction-notification',
    );
  } on AndroidAppStateBlocked catch (error) {
    return _blocked('environment', error.detail);
  } on AndroidAppStateFailure catch (error) {
    return _failed(
      detail: error.detail,
      childExitCode: 1,
      assertionsAttempted: 0,
      artifactPresent: false,
    );
  }

  final proofDirectory = _proofDirectory(environment);
  final captureRoot = Directory(
    '${proofDirectory.path}${Platform.pathSeparator}'
    'capture-${DateTime.now().toUtc().microsecondsSinceEpoch}-$pid',
  )..createSync(recursive: true);
  final artifactSha = sha256.convert(artifact.readAsBytesSync()).toString();
  final captures = <Map<String, Object?>>[];

  try {
    for (final scenario in _androidScenarios) {
      await stateGuard.prepareFreshInstalls(artifact);
      final scenarioDirectory = Directory(
        '${captureRoot.path}${Platform.pathSeparator}${scenario.id}',
      )..createSync(recursive: true);
      late final Process child;
      try {
        child = await Process.start(
          Platform.resolvedExecutable,
          <String>[
            'run',
            runner.path,
            '--scenario',
            scenario.id,
            '--sender',
            emulator,
            '--recipient',
            physical,
            '--artifact-dir',
            scenarioDirectory.path,
            '--staging-manifest',
            staging.path,
            '--relay-target',
            relayTarget,
            '--relay-key',
            File(relayKeyPath).absolute.path,
            '--service-account',
            File(credentialPath).absolute.path,
            '--prebuilt-android-apk',
            artifact.path,
            '--no-child-builds',
            '--android-state-prepared',
          ],
          environment: environment,
          includeParentEnvironment: true,
        );
      } on ProcessException catch (error) {
        return _blocked(
          'missingDriver',
          'Could not launch the group reaction runner: ${error.message}',
        );
      }
      final stdoutDone = child.stdout.listen(stderr.add).asFuture<void>();
      final stderrDone = child.stderr.listen(stderr.add).asFuture<void>();
      final childExit = await child.exitCode;
      await Future.wait<void>(<Future<void>>[stdoutDone, stderrDone]);
      if (childExit != 0) {
        final verdict = _readScenarioVerdict(scenarioDirectory, scenario.id);
        if (childExit == 78) {
          return _blocked(
            _blockerForVerdict(verdict),
            '${scenario.id} could not execute: '
            '${verdict?['detail'] ?? 'runner exited 78'}.',
            scenarioIds: _androidScenarios
                .map((item) => item.id)
                .toList(growable: false),
          );
        }
        return _failed(
          detail:
              '${scenario.id} capture/validation exited $childExit: '
              '${verdict?['detail'] ?? 'no typed verdict'}',
          childExitCode: childExit,
          assertionsAttempted: captures.length + 1,
          artifactPresent: false,
        );
      }

      final captured = File(
        '${scenarioDirectory.path}${Platform.pathSeparator}${scenario.id}.json',
      );
      final validation = await validateGroupReactionNotificationArtifact(
        scenario: scenario.id,
        artifactFile: captured,
        expectedSenderDeviceId: emulator,
        expectedRecipientDeviceId: physical,
      );
      final verdict = _readScenarioVerdict(scenarioDirectory, scenario.id);
      if (!validation.ok ||
          verdict?['ok'] != true ||
          verdict?['status'] != 'passed') {
        return _failed(
          detail:
              '${scenario.id} did not retain an accepted validator verdict: '
              '${validation.detail}',
          childExitCode: 1,
          assertionsAttempted: captures.length + 1,
          artifactPresent: captured.existsSync(),
        );
      }
      final candidate = File(
        '${scenarioDirectory.path}${Platform.pathSeparator}'
        'candidate_build_provenance.json',
      );
      if (!_isCentralPreparedProvenance(candidate, artifactSha)) {
        return _failed(
          detail:
              '${scenario.id} did not prove zero child builds from the central '
              'android.production_fcm APK.',
          childExitCode: 1,
          assertionsAttempted: captures.length + 1,
          artifactPresent: captured.existsSync(),
        );
      }
      captures.add(<String, Object?>{
        'scenario': scenario.id,
        'testCase': scenario.testCase,
        'path': captured.resolveSymbolicLinksSync(),
        'sha256': sha256.convert(captured.readAsBytesSync()).toString(),
        'verdictPath': File(
          '${scenarioDirectory.path}${Platform.pathSeparator}${scenario.id}'
          '_orchestrator_verdict.json',
        ).resolveSymbolicLinksSync(),
      });
    }
  } finally {
    await stateGuard.restoreAll();
  }

  final evidence = writeSimsArtifactEvidenceSync(
    directory: proofDirectory,
    capabilityId: _capabilityId,
    validatorIds: const <String>[_artifactValidator],
    payload: <String, Object?>{
      'status': 'passed',
      'scenarioIds': _androidScenarios
          .map((scenario) => scenario.id)
          .toList(growable: false),
      'targetIds': <String>[physical, emulator],
      'targetKinds': const <String>['physical', 'emulator'],
      'preparedArtifactPath': artifact.resolveSymbolicLinksSync(),
      'preparedArtifactSha256': artifactSha,
      'captureArtifacts': captures,
      'childBuildCount': 0,
    },
  );
  final audit = auditSimsArtifactEvidence(
    evidence: evidence,
    expectedValidatorIds: const <String>[_artifactValidator],
  );
  if (!audit.isValid) {
    return _failed(
      detail: 'Aggregate evidence failed its content audit: ${audit.detail}',
      childExitCode: 1,
      assertionsAttempted: _androidScenarios.length,
      artifactPresent: true,
    );
  }
  return _passed(evidence);
}

Map<String, Object?>? _readScenarioVerdict(
  Directory directory,
  String scenario,
) {
  final file = File(
    '${directory.path}${Platform.pathSeparator}$scenario'
    '_orchestrator_verdict.json',
  );
  if (!_isRegularFile(file)) return null;
  try {
    final value = jsonDecode(file.readAsStringSync());
    if (value is! Map) return null;
    return value.map<String, Object?>((key, item) => MapEntry('$key', item));
  } on Object {
    return null;
  }
}

String _blockerForVerdict(Map<String, Object?>? verdict) {
  final stage = '${verdict?['stage'] ?? ''}';
  final detail = '${verdict?['detail'] ?? ''}';
  if (stage == 'device_inventory' || detail.contains('device_unavailable')) {
    // Initial absence is handled by the Sims device resolver as policy-bounded
    // N/A. Reaching this point means an explicitly assigned target vanished
    // between resolution and capture.
    return 'deviceLost';
  }
  if (stage == 'runtime_probe' || detail.contains('driver_missing')) {
    return 'missingDriver';
  }
  return 'environment';
}

bool _isCentralPreparedProvenance(File file, String expectedSha) {
  if (!_isRegularFile(file)) return false;
  try {
    final value = jsonDecode(file.readAsStringSync());
    return value is Map &&
        value['schema'] == 'mknoon.plan257.candidate-build.v1' &&
        value['buildMode'] == 'central_prebuilt' &&
        value['buildProfile'] == 'android.production_fcm' &&
        value['childBuildCount'] == 0 &&
        value['e2eApkSha256'] == expectedSha &&
        value['normalApkSha256'] == expectedSha;
  } on Object {
    return false;
  }
}

String? _validateStagingManifest(File file) {
  late final Map<String, Object?> decoded;
  try {
    final value = jsonDecode(file.readAsStringSync());
    if (value is! Map) return 'The staging manifest root must be an object.';
    decoded = value.map<String, Object?>(
      (key, value) => MapEntry('$key', value),
    );
  } on Object catch (error) {
    return 'The staging manifest is invalid JSON: $error';
  }
  for (final scenario in _androidScenarios) {
    final validation = validateGroupReactionNotificationStagingManifest(
      decoded,
      scenario: scenario,
    );
    if (!validation.ok) {
      return 'The staging manifest was rejected for ${scenario.id}: '
          '${validation.detail}.';
    }
  }
  return null;
}

Directory _proofDirectory(Map<String, String> environment) {
  final configured = environment['SIMS_PROOF_DIRECTORY']?.trim();
  return Directory(
    configured == null || configured.isEmpty
        ? 'build/sims/proofs/$_capabilityId'
        : configured,
  ).absolute;
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

Future<void> main() async {
  late final _AdapterResult result;
  try {
    result = await _run(Platform.environment);
  } on AndroidAppStateFailure catch (error, stackTrace) {
    stderr.writeln(stackTrace);
    result = _failed(
      detail: error.detail,
      childExitCode: 1,
      assertionsAttempted: 0,
      artifactPresent: false,
    );
  } catch (error, stackTrace) {
    stderr.writeln(stackTrace);
    result = _failed(
      detail: 'Group reaction Sims adapter failed before a verdict: $error',
      childExitCode: 1,
      assertionsAttempted: 0,
      artifactPresent: false,
    );
  }
  stdout.writeln('SIMS_RESULT_JSON=${jsonEncode(result.json)}');
  exitCode = result.processExitCode;
}
