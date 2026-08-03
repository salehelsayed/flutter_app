#!/usr/bin/env dart

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../tool/sims/artifact_evidence.dart';
import '../support/android_app_state_guard.dart';
import '_android_app_package.dart';
import 'group_notification_projection_android_criteria.dart';
import 'group_reaction_notification_device_criteria.dart';

const String _captureDriver =
    'integration_test/scripts/capture_group_reaction_notification_device.dart';
const String _preparedArtifactEnvironment =
    'SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM';
const String _physicalEnvironment = 'SIMS_ANDROID_PHYSICAL_DEVICE_ID';
const String _emulatorEnvironment = 'SIMS_ANDROID_EMULATOR_DEVICE_ID';
const String _artifactValidator =
    'integration_test/group_notification_projection_android_proof_test.dart';

final RegExp _safeTargetId = RegExp(r'^[A-Za-z0-9._:-]+$');

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
      'scenarioIds': const <String>[groupNotificationProjectionScenarioId],
    }, 78);

_AdapterResult _failed({
  required String detail,
  required int childExitCode,
  required int assertionsAttempted,
  required bool artifactPresent,
}) {
  final code = childExitCode == 0 ? 1 : childExitCode;
  return _AdapterResult(<String, Object?>{
    'status': 'FAIL',
    'assertionsAttempted': assertionsAttempted,
    'artifactPresent': artifactPresent,
    'printOnly': false,
    'blocker': 'test',
    'exitCode': code,
    'detail': detail,
    'scenarioIds': const <String>[groupNotificationProjectionScenarioId],
  }, code);
}

_AdapterResult _passed(SimsArtifactEvidence evidence) =>
    _AdapterResult(<String, Object?>{
      'status': 'PASS',
      'assertionsAttempted': groupNotificationProjectionCriteria.length,
      'artifactPresent': true,
      'printOnly': false,
      'exitCode': 0,
      'detail':
          'Exact in-app read-zero cancellation and localized photo/video/voice '
          'reaction projection passed on the pinned Android pair with one '
          'centrally prepared production-FCM APK.',
      'artifactEvidence': evidence.toJson(),
    }, 0);

Future<_AdapterResult> _run(Map<String, String> environment) async {
  final sourceScenario = groupReactionNotificationScenario(
    groupNotificationProjectionScenarioId,
  );
  if (sourceScenario == null) {
    return _blocked(
      'missingDriver',
      'The existing group-reaction campaign does not yet expose the named '
          '$groupNotificationProjectionScenarioId capture. The adapter fails '
          'closed instead of reusing legacy one-group/text-reaction evidence.',
    );
  }
  if (sourceScenario.senderPlatform != 'android' ||
      sourceScenario.senderDeviceKind != 'emulator' ||
      sourceScenario.recipientPlatform != 'android' ||
      sourceScenario.recipientDeviceKind != 'physical') {
    return _blocked(
      'missingDriver',
      'The source campaign registered $groupNotificationProjectionScenarioId '
          'with a topology other than Android emulator sender plus physical '
          'Android recipient.',
    );
  }
  if (!_isRegularFile(File(_captureDriver))) {
    return _blocked(
      'missingDriver',
      'The existing group-reaction capture driver is unavailable.',
    );
  }

  final artifactPath = environment[_preparedArtifactEnvironment]?.trim();
  if (artifactPath == null || artifactPath.isEmpty) {
    return _blocked(
      'missingArtifact',
      '$_preparedArtifactEnvironment is required; this lane never builds an '
          'APK in a child process.',
    );
  }
  final preparedArtifact = File(artifactPath).absolute;
  if (!_isRegularFile(preparedArtifact)) {
    return _blocked(
      'missingArtifact',
      '$_preparedArtifactEnvironment is not a regular centrally prepared APK.',
    );
  }
  final preparedSha = sha256
      .convert(preparedArtifact.readAsBytesSync())
      .toString();

  final physical = environment[_physicalEnvironment]?.trim();
  final emulator = environment[_emulatorEnvironment]?.trim();
  if (physical != plan330PhysicalAndroidDeviceId ||
      emulator != plan330AndroidEmulatorDeviceId ||
      !_safeTargetId.hasMatch(physical ?? '') ||
      !_safeTargetId.hasMatch(emulator ?? '')) {
    return _blocked(
      'targetUnavailable',
      'Plan 330 is availability-bounded to USB Android '
          '$plan330PhysicalAndroidDeviceId and Android emulator '
          '$plan330AndroidEmulatorDeviceId; both must be explicitly assigned.',
    );
  }
  final assignedPhysical = physical!;
  final assignedEmulator = emulator!;

  final relayAddresses = environment['MKNOON_RELAY_ADDRESSES']?.trim();
  final relayTarget = environment['MKNOON_257_RELAY_TARGET']?.trim();
  final relayKeyPath = environment['MKNOON_257_RELAY_KEY']?.trim();
  final stagingPath = environment['MKNOON_257_STAGING_MANIFEST']?.trim();
  if (!_safeSingleLine(relayAddresses) ||
      !_safeSingleLine(relayTarget) ||
      relayKeyPath == null ||
      relayKeyPath.isEmpty ||
      !_isRegularFile(File(relayKeyPath).absolute) ||
      stagingPath == null ||
      stagingPath.isEmpty ||
      !_isRegularFile(File(stagingPath).absolute)) {
    return _blocked(
      'environment',
      'The existing staging group campaign requires safe relay addresses and '
          'target plus readable MKNOON_257_RELAY_KEY and '
          'MKNOON_257_STAGING_MANIFEST files.',
    );
  }
  final staging = File(stagingPath).absolute;
  final stagingError = _validateStaging(staging, sourceScenario);
  if (stagingError != null) return _blocked('environment', stagingError);

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
      'A readable FCM service-account JSON containing project_id is required.',
    );
  }

  try {
    final listed = await Process.run('adb', const <String>['devices']);
    final output = '${listed.stdout}';
    if (listed.exitCode != 0 ||
        !output.contains('$assignedPhysical\tdevice') ||
        !output.contains('$assignedEmulator\tdevice')) {
      return _blocked(
        'deviceLost',
        'An explicitly assigned Plan-330 Android target disappeared before '
            'state capture.',
      );
    }
  } on ProcessException {
    return _blocked(
      'deviceLost',
      'ADB could not verify the explicitly assigned Plan-330 Android targets.',
    );
  }

  final packageName = resolveAndroidAppPackage();
  late final AndroidAppStateGuard stateGuard;
  try {
    stateGuard = await AndroidAppStateGuard.capture(
      devices: <String>[assignedPhysical, assignedEmulator],
      packageName: packageName,
      backupLabel: 'group-notification-projection-330',
      preparedArtifact: preparedArtifact,
      expectedArtifactSha256: preparedSha,
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
  final captureDirectory = Directory(
    '${proofDirectory.path}${Platform.pathSeparator}'
    'capture-${DateTime.now().toUtc().microsecondsSinceEpoch}-$pid',
  )..createSync(recursive: true);
  try {
    await stateGuard.prepareFreshInstalls(preparedArtifact);
    late final Process child;
    try {
      child = await Process.start(
        Platform.resolvedExecutable,
        <String>[
          'run',
          File(_captureDriver).absolute.path,
          '--scenario',
          groupNotificationProjectionScenarioId,
          '--sender',
          assignedEmulator,
          '--recipient',
          assignedPhysical,
          '--artifact-dir',
          captureDirectory.path,
          '--staging-manifest',
          staging.path,
          '--relay-target',
          relayTarget!,
          '--relay-key',
          File(relayKeyPath).absolute.path,
          '--service-account',
          File(credentialPath).absolute.path,
          '--prebuilt-android-apk',
          preparedArtifact.path,
          '--no-child-builds',
          '--android-state-prepared',
        ],
        environment: environment,
        includeParentEnvironment: true,
      );
    } on ProcessException catch (error) {
      return _blocked(
        'missingDriver',
        'Could not launch the group notification projection capture: '
            '${error.message}',
      );
    }
    final stdoutDone = child.stdout.listen(stderr.add).asFuture<void>();
    final stderrDone = child.stderr.listen(stderr.add).asFuture<void>();
    final childExit = await child.exitCode;
    await Future.wait<void>(<Future<void>>[stdoutDone, stderrDone]);
    if (childExit != 0) {
      return childExit == 78
          ? _blocked(
              'environment',
              'The named Plan-330 source capture could not execute. See '
                  '${captureDirectory.path} for its typed verdict.',
            )
          : _failed(
              detail:
                  'The named Plan-330 source capture exited $childExit; '
                  'legacy artifacts are never accepted as substitutes.',
              childExitCode: childExit,
              assertionsAttempted: 1,
              artifactPresent: false,
            );
    }

    final artifact = File(
      '${captureDirectory.path}${Platform.pathSeparator}'
      '$groupNotificationProjectionScenarioId.json',
    );
    final validation = await validateGroupNotificationProjectionAndroidArtifact(
      artifactFile: artifact,
      expectedPhysicalDeviceId: assignedPhysical,
      expectedEmulatorDeviceId: assignedEmulator,
      expectedApkSha256: preparedSha,
      expectedPackageName: packageName,
    );
    if (!validation.ok) {
      return _failed(
        detail:
            'The capture omitted or contradicted required raw Plan-330 '
            'observables: ${validation.detail}',
        childExitCode: 1,
        assertionsAttempted: groupNotificationProjectionCriteria.length,
        artifactPresent: _isRegularFile(artifact),
      );
    }
    final candidate = File(
      '${captureDirectory.path}${Platform.pathSeparator}'
      'candidate_build_provenance.json',
    );
    if (!_isCentralPreparedProvenance(candidate, preparedSha)) {
      return _failed(
        detail:
            'The capture did not prove zero child builds from the central '
            'android.production_fcm APK.',
        childExitCode: 1,
        assertionsAttempted: groupNotificationProjectionCriteria.length,
        artifactPresent: true,
      );
    }

    final artifactCanonical = artifact.resolveSymbolicLinksSync();
    final evidence = writeSimsArtifactEvidenceSync(
      directory: proofDirectory,
      capabilityId: groupNotificationProjectionCapabilityId,
      validatorIds: const <String>[_artifactValidator],
      payload: <String, Object?>{
        'status': 'passed',
        'scenarioIds': const <String>[groupNotificationProjectionScenarioId],
        'criteria': groupNotificationProjectionCriteria,
        'targetIds': <String>[assignedPhysical, assignedEmulator],
        'targetKinds': const <String>['physical', 'emulator'],
        'preparedArtifactPath': preparedArtifact.resolveSymbolicLinksSync(),
        'preparedArtifactSha256': preparedSha,
        'captureArtifactPath': artifactCanonical,
        'captureArtifactSha256': sha256
            .convert(File(artifactCanonical).readAsBytesSync())
            .toString(),
        'childBuildCount': 0,
      },
    );
    final audit = auditSimsArtifactEvidence(
      evidence: evidence,
      expectedValidatorIds: const <String>[_artifactValidator],
    );
    if (!audit.isValid) {
      return _failed(
        detail: 'Aggregate proof failed its content audit: ${audit.detail}',
        childExitCode: 1,
        assertionsAttempted: groupNotificationProjectionCriteria.length,
        artifactPresent: true,
      );
    }
    return _passed(evidence);
  } finally {
    await stateGuard.restoreAll();
  }
}

String? _validateStaging(
  File file,
  GroupReactionNotificationScenario scenario,
) {
  try {
    final value = jsonDecode(file.readAsStringSync());
    if (value is! Map) return 'The staging manifest root must be an object.';
    final result = validateGroupReactionNotificationStagingManifest(
      value.map<String, Object?>((key, item) => MapEntry('$key', item)),
      scenario: scenario,
    );
    return result.ok
        ? null
        : 'The source campaign rejected the staging manifest: '
              '${result.detail}.';
  } on Object catch (error) {
    return 'The staging manifest is invalid: $error';
  }
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

Directory _proofDirectory(Map<String, String> environment) {
  final configured = environment['SIMS_PROOF_DIRECTORY']?.trim();
  return Directory(
    configured == null || configured.isEmpty
        ? 'build/sims/proofs/$groupNotificationProjectionCapabilityId'
        : configured,
  ).absolute;
}

bool _safeSingleLine(String? value) =>
    value != null && value.isNotEmpty && !value.contains(RegExp(r'[\r\n]'));

bool _isUsableServiceAccount(File file) {
  if (!_isRegularFile(file)) return false;
  try {
    final value = jsonDecode(file.readAsStringSync());
    return value is Map && '${value['project_id'] ?? ''}'.trim().isNotEmpty;
  } on Object {
    return false;
  }
}

bool _isRegularFile(File file) =>
    FileSystemEntity.typeSync(file.path, followLinks: true) ==
    FileSystemEntityType.file;

String? _valueFor(List<String> args, String name) {
  for (var index = 0; index < args.length; index += 1) {
    final argument = args[index];
    if (argument == name) {
      if (index + 1 >= args.length || args[index + 1].startsWith('--')) {
        throw FormatException('Missing value for $name.');
      }
      return args[index + 1];
    }
    if (argument.startsWith('$name=')) {
      final value = argument.substring(name.length + 1);
      if (value.isEmpty) throw FormatException('Missing value for $name.');
      return value;
    }
  }
  return null;
}

Future<void> main(List<String> args) async {
  if (args.contains('--list-criteria')) {
    for (final criterion in groupNotificationProjectionCriteria) {
      stdout.writeln(criterion);
    }
    return;
  }
  if (args.contains('--probe-source-extension')) {
    final available = groupReactionNotificationScenario(
      groupNotificationProjectionScenarioId,
    );
    if (available == null) {
      stderr.writeln(
        'MISSING: existing group-reaction campaign has no '
        '$groupNotificationProjectionScenarioId criteria/capture branch.',
      );
      exitCode = 78;
      return;
    }
    stdout.writeln(
      'READY: existing group-reaction campaign exposes '
      '$groupNotificationProjectionScenarioId.',
    );
    return;
  }
  final validationPath = _valueFor(args, '--validate-artifact');
  if (validationPath != null) {
    final validation = await validateGroupNotificationProjectionAndroidArtifact(
      artifactFile: File(validationPath),
    );
    if (!validation.ok) {
      stderr.writeln('INVALID: ${validation.detail}');
      exitCode = 65;
      return;
    }
    stdout.writeln('VALID: Plan-330 Android projection artifact accepted.');
    return;
  }
  if (args.isNotEmpty) {
    stderr.writeln(
      'Usage: dart run integration_test/scripts/'
      'run_group_notification_projection_android.dart '
      '[--list-criteria | --probe-source-extension | '
      '--validate-artifact <json>]',
    );
    exitCode = 64;
    return;
  }

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
      detail:
          'Group notification projection adapter failed before a verdict: '
          '${error.runtimeType}.',
      childExitCode: 1,
      assertionsAttempted: 0,
      artifactPresent: false,
    );
  }
  stdout.writeln('SIMS_RESULT_JSON=${jsonEncode(result.json)}');
  exitCode = result.processExitCode;
}
