#!/usr/bin/env dart

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../tool/sims/artifact_evidence.dart';
import '../support/android_app_state_guard.dart';
import '_android_app_package.dart';
import 'group_muted_notification_android_criteria.dart';
import 'group_reaction_notification_device_criteria.dart';

const String _captureDriver =
    'integration_test/scripts/capture_group_reaction_notification_device.dart';
const String _preparedArtifactEnvironment =
    'SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM';
const String _physicalEnvironment = 'SIMS_ANDROID_PHYSICAL_DEVICE_ID';
const String _emulatorEnvironment = 'SIMS_ANDROID_EMULATOR_DEVICE_ID';
const String _artifactValidator =
    'integration_test/group_muted_notification_proof_test.dart';

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
      'scenarioIds': groupMutedNotificationScenarioIds,
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
    'scenarioIds': groupMutedNotificationScenarioIds,
  }, code);
}

_AdapterResult _passed(SimsArtifactEvidence evidence) =>
    _AdapterResult(<String, Object?>{
      'status': 'PASS',
      'assertionsAttempted': groupMutedNotificationCriteria.length,
      'artifactPresent': true,
      'printOnly': false,
      'exitCode': 0,
      'detail':
          'A muted group produced no notification card on the live message '
          'path and none on the FCM/background reaction path, while unread, '
          'persistence, and an unmuted control group stayed intact on the '
          'pinned Android pair with one centrally prepared production-FCM APK.',
      'artifactEvidence': evidence.toJson(),
    }, 0);

Future<_AdapterResult> _run(Map<String, String> environment) async {
  final sourceScenarios = <GroupReactionNotificationScenario>[];
  for (final id in groupMutedNotificationScenarioIds) {
    final scenario = groupReactionNotificationScenario(id);
    if (scenario == null) {
      return _blocked(
        'missingDriver',
        'The shared group-reaction campaign does not expose the named $id '
            'capture. The adapter fails closed instead of reusing the Plan-257 '
            'reaction grammar, which asserts the opposite of mute.',
      );
    }
    if (scenario.senderPlatform != 'android' ||
        scenario.senderDeviceKind != 'emulator' ||
        scenario.recipientPlatform != 'android' ||
        scenario.recipientDeviceKind != 'physical') {
      return _blocked(
        'missingDriver',
        'The source campaign registered $id with a topology other than '
            'Android emulator sender plus physical Android recipient.',
      );
    }
    sourceScenarios.add(scenario);
  }
  if (!_isRegularFile(File(_captureDriver))) {
    return _blocked(
      'missingDriver',
      'The shared group-reaction capture driver is unavailable.',
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
  if (physical != plan379PhysicalAndroidDeviceId ||
      emulator != plan379AndroidEmulatorDeviceId ||
      !_safeTargetId.hasMatch(physical ?? '') ||
      !_safeTargetId.hasMatch(emulator ?? '')) {
    return _blocked(
      'targetUnavailable',
      'Plan 379 is availability-bounded to USB Android '
          '$plan379PhysicalAndroidDeviceId and Android emulator '
          '$plan379AndroidEmulatorDeviceId; both must be explicitly assigned.',
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
      'The shared staging group campaign requires safe relay addresses and '
          'target plus readable MKNOON_257_RELAY_KEY and '
          'MKNOON_257_STAGING_MANIFEST files.',
    );
  }
  final staging = File(stagingPath).absolute;
  // The staging manifest varies only on recipientPlatform, so the Plan-257
  // validator is reused verbatim for both muted ids.
  final stagingError = _validateStaging(staging, sourceScenarios.first);
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
        'An explicitly assigned Plan-379 Android target disappeared before '
            'state capture.',
      );
    }
  } on ProcessException {
    return _blocked(
      'deviceLost',
      'ADB could not verify the explicitly assigned Plan-379 Android targets.',
    );
  }

  final packageName = resolveAndroidAppPackage();
  late final AndroidAppStateGuard stateGuard;
  try {
    stateGuard = await AndroidAppStateGuard.capture(
      devices: <String>[assignedPhysical, assignedEmulator],
      packageName: packageName,
      backupLabel: 'group-muted-notification-379',
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
  final capturedArtifacts = <String, String>{};
  try {
    for (final scenarioId in groupMutedNotificationScenarioIds) {
      await stateGuard.prepareFreshInstalls(preparedArtifact);
      // Fresh directory per run makes stale artifacts structurally impossible,
      // but both ids share it, so a prior id's failure artifact is purged
      // explicitly rather than being read as this id's verdict.
      _purgeScenarioArtifacts(captureDirectory, scenarioId);

      late final Process child;
      try {
        child = await Process.start(
          Platform.resolvedExecutable,
          <String>[
            'run',
            File(_captureDriver).absolute.path,
            '--scenario',
            scenarioId,
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
          'Could not launch the muted-group capture for $scenarioId: '
              '${error.message}',
        );
      }
      // Both child streams go to STDERR: the sims executor fails the harness
      // when more than one SIMS_RESULT_JSON marker appears anywhere on stdout.
      final stdoutDone = child.stdout.listen(stderr.add).asFuture<void>();
      final stderrDone = child.stderr.listen(stderr.add).asFuture<void>();
      final childExit = await child.exitCode;
      await Future.wait<void>(<Future<void>>[stdoutDone, stderrDone]);
      if (childExit != 0) {
        return childExit == 78
            ? _blocked(
                'environment',
                'The muted-group capture for $scenarioId could not execute. '
                    'See ${captureDirectory.path} for its typed verdict.',
              )
            : _failed(
                detail:
                    'The muted-group capture for $scenarioId exited '
                    '$childExit; reaction-grammar artifacts are never accepted '
                    'as substitutes.',
                childExitCode: childExit,
                assertionsAttempted: 1,
                artifactPresent: false,
              );
      }

      final artifact = File(
        '${captureDirectory.path}${Platform.pathSeparator}$scenarioId.json',
      );
      final validation = await validateGroupMutedNotificationAndroidArtifact(
        artifactFile: artifact,
        expectedPhysicalDeviceId: assignedPhysical,
        expectedEmulatorDeviceId: assignedEmulator,
        expectedApkSha256: preparedSha,
        expectedPackageName: packageName,
      );
      if (!validation.ok) {
        return _failed(
          detail:
              'The $scenarioId capture omitted or contradicted required raw '
              'muted-group observables: ${validation.detail}',
          childExitCode: 1,
          assertionsAttempted: groupMutedNotificationCriteria.length,
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
              'The $scenarioId capture did not prove zero child builds from '
              'the central android.production_fcm APK.',
          childExitCode: 1,
          assertionsAttempted: groupMutedNotificationCriteria.length,
          artifactPresent: true,
        );
      }
      capturedArtifacts[scenarioId] = artifact.resolveSymbolicLinksSync();
    }

    final evidence = writeSimsArtifactEvidenceSync(
      directory: proofDirectory,
      capabilityId: groupMutedNotificationCapabilityId,
      validatorIds: const <String>[_artifactValidator],
      payload: <String, Object?>{
        'status': 'passed',
        'scenarioIds': groupMutedNotificationScenarioIds,
        'criteria': groupMutedNotificationCriteria,
        'targetIds': <String>[assignedPhysical, assignedEmulator],
        'targetKinds': const <String>['physical', 'emulator'],
        'preparedArtifactPath': preparedArtifact.resolveSymbolicLinksSync(),
        'preparedArtifactSha256': preparedSha,
        'captureArtifactPaths': capturedArtifacts,
        'captureArtifactSha256': <String, String>{
          for (final entry in capturedArtifacts.entries)
            entry.key: sha256
                .convert(File(entry.value).readAsBytesSync())
                .toString(),
        },
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
        assertionsAttempted: groupMutedNotificationCriteria.length,
        artifactPresent: true,
      );
    }
    return _passed(evidence);
  } finally {
    await stateGuard.restoreAll();
  }
}

/// Removes both artifact names a prior capture of [scenarioId] can leave.
///
/// The capture driver publishes `<id>.json` on success and
/// `<id>_capture_failure.json` on a typed failure; reading a stale one as this
/// run's verdict is the failure mode this guards.
void _purgeScenarioArtifacts(Directory directory, String scenarioId) {
  for (final name in <String>[
    '$scenarioId.json',
    '${scenarioId}_capture_failure.json',
  ]) {
    final file = File(
      '${directory.path}${Platform.pathSeparator}$name',
    );
    if (FileSystemEntity.typeSync(file.path, followLinks: false) ==
        FileSystemEntityType.file) {
      file.deleteSync();
    }
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
        ? 'build/sims/proofs/$groupMutedNotificationCapabilityId'
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
  if (args.contains('--list-scenarios')) {
    // A deliberate leading newline: `dart run` may emit package build-hook
    // progress on stdout without a trailing newline, which would otherwise
    // glue itself to the first id and break the contract census.
    stdout.writeln();
    for (final scenarioId in groupMutedNotificationScenarioIds) {
      stdout.writeln(scenarioId);
    }
    return;
  }
  if (args.contains('--list-criteria')) {
    for (final criterion in groupMutedNotificationCriteria) {
      stdout.writeln(criterion);
    }
    return;
  }
  if (args.contains('--probe-source-extension')) {
    for (final scenarioId in groupMutedNotificationScenarioIds) {
      if (groupReactionNotificationScenario(scenarioId) == null) {
        stderr.writeln(
          'MISSING: the shared group-reaction campaign has no $scenarioId '
          'source scenario.',
        );
        exitCode = 78;
        return;
      }
    }
    stdout.writeln(
      'READY: the shared group-reaction campaign exposes '
      '${groupMutedNotificationScenarioIds.join(', ')}.',
    );
    return;
  }
  final fixtureKind = _valueFor(args, '--emit-fixture');
  if (fixtureKind != null) {
    final output = _valueFor(args, '--output');
    if (output == null) {
      stderr.writeln('Missing value for --output.');
      exitCode = 64;
      return;
    }
    final input = switch (fixtureKind) {
      'happy-message' => happyMutedMessageCaptureInput(),
      'happy-reaction' => happyMutedReactionCaptureInput(),
      'unread-unchanged' => unreadUnchangedMutedMessageCaptureInput(),
      _ => null,
    };
    if (input == null) {
      stderr.writeln(
        'Unknown --emit-fixture $fixtureKind; expected happy-message, '
        'happy-reaction, or unread-unchanged.',
      );
      exitCode = 64;
      return;
    }
    final file = await writeGroupMutedNotificationArtifact(
      proofDirectory: Directory(output).absolute,
      input: input,
    );
    // Same leading-newline guard as --list-scenarios: `dart run` emits build
    // hook progress on stdout without a trailing newline.
    stdout
      ..writeln()
      ..writeln(file.path);
    return;
  }
  final validationPath = _valueFor(args, '--validate-artifact');
  if (validationPath != null) {
    final validation = await validateGroupMutedNotificationAndroidArtifact(
      artifactFile: File(validationPath),
    );
    if (!validation.ok) {
      stderr.writeln('INVALID: ${validation.detail}');
      exitCode = 65;
      return;
    }
    stdout.writeln('VALID: Plan-379 Android muted-group artifact accepted.');
    return;
  }
  if (args.isNotEmpty) {
    stderr.writeln(
      'Usage: dart run integration_test/scripts/'
      'run_group_muted_notification_android.dart '
      '[--list-scenarios | --list-criteria | --probe-source-extension | '
      '--emit-fixture <kind> --output <dir> | --validate-artifact <json>]',
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
          'Muted-group notification adapter failed before a verdict: '
          '${error.runtimeType}.',
      childExitCode: 1,
      assertionsAttempted: 0,
      artifactPresent: false,
    );
  }
  stdout.writeln('SIMS_RESULT_JSON=${jsonEncode(result.json)}');
  exitCode = result.processExitCode;
}
