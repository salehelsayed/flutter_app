#!/usr/bin/env dart

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../tool/sims/artifact_evidence.dart';
import '../support/android_app_state_guard.dart';
import '_android_app_package.dart';
import 'group_reaction_notification_device_criteria.dart';
import 'group_strict_notification_criteria.dart'
    hide groupStrictNotificationScenarioId;
import 'physical_device_capture_harness.dart';

const String _captureDriver =
    'integration_test/scripts/capture_group_reaction_notification_device.dart';
const String _preparedArtifactEnvironment =
    'SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM';
const String _physicalEnvironment = 'SIMS_ANDROID_PHYSICAL_DEVICE_ID';
const String _emulatorEnvironment = 'SIMS_ANDROID_EMULATOR_DEVICE_ID';
const String _artifactValidator =
    'integration_test/group_strict_notification_proof_test.dart';

final RegExp _safeTargetId = RegExp(r'^[A-Za-z0-9._:-]+$');

final class _AdapterResult {
  const _AdapterResult(this.json, this.processExitCode);

  final Map<String, Object?> json;
  final int processExitCode;
}

final class _CaptureSuccess {
  const _CaptureSuccess({required this.artifact, required this.captureRoot});

  final File artifact;
  final Directory captureRoot;
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
      'scenarioIds': const <String>[groupStrictNotificationScenarioId],
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
    'scenarioIds': const <String>[groupStrictNotificationScenarioId],
  }, code);
}

_AdapterResult _passed(SimsArtifactEvidence evidence) =>
    _AdapterResult(<String, Object?>{
      'status': 'PASS',
      'assertionsAttempted': groupStrictNotificationCriteria.length,
      'artifactPresent': true,
      'printOnly': false,
      'exitCode': 0,
      'detail':
          'Strict exact-chat suppression, killed message, author-targeted ADD, '
          'relay provenance, and exact Android state restoration passed.',
      'artifactEvidence': evidence.toJson(),
    }, 0);

Future<_AdapterResult> _run(Map<String, String> environment) async {
  final source = groupReactionNotificationScenario(
    groupStrictNotificationScenarioId,
  );
  if (source == null ||
      source.senderPlatform != 'android' ||
      source.senderDeviceKind != 'emulator' ||
      source.recipientPlatform != 'android' ||
      source.recipientDeviceKind != 'physical') {
    return _blocked(
      'missingDriver',
      'The shared group capture does not expose the exact Plan-393 strict '
          'Android topology.',
    );
  }
  if (!_isRegularFile(File(_captureDriver))) {
    return _blocked('missingDriver', 'The shared group capture is missing.');
  }

  final artifactPath = environment[_preparedArtifactEnvironment]?.trim();
  if (artifactPath == null || artifactPath.isEmpty) {
    return _blocked(
      'missingArtifact',
      '$_preparedArtifactEnvironment is required; strict proof never builds '
          'an APK in a child process.',
    );
  }
  final preparedArtifact = File(artifactPath).absolute;
  if (!_isRegularFile(preparedArtifact)) {
    return _blocked('missingArtifact', 'The prepared APK is not a file.');
  }
  final preparedSha = sha256
      .convert(preparedArtifact.readAsBytesSync())
      .toString();

  final physical = environment[_physicalEnvironment]?.trim();
  final emulator = environment[_emulatorEnvironment]?.trim();
  if (physical == null ||
      emulator == null ||
      physical == emulator ||
      !_safeTargetId.hasMatch(physical) ||
      !_safeTargetId.hasMatch(emulator) ||
      RegExp(r'^emulator-[0-9]+$').hasMatch(physical) ||
      !RegExp(r'^emulator-[0-9]+$').hasMatch(emulator)) {
    return _blocked(
      'targetUnavailable',
      'Explicit live physical-Android and Android-emulator IDs are required.',
    );
  }

  final relayTarget = environment['MKNOON_257_RELAY_TARGET']?.trim();
  final relayKeyPath = environment['MKNOON_257_RELAY_KEY']?.trim();
  final stagingPath = environment['MKNOON_257_STAGING_MANIFEST']?.trim();
  final relayAddresses = environment['MKNOON_RELAY_ADDRESSES']?.trim();
  if (!_safeSingleLine(relayAddresses) ||
      !_safeSingleLine(relayTarget) ||
      relayKeyPath == null ||
      !_isRegularFile(File(relayKeyPath).absolute) ||
      stagingPath == null ||
      !_isRegularFile(File(stagingPath).absolute)) {
    return _blocked(
      'environment',
      'Safe staging relay addresses/target and readable relay key/manifest '
          'are required.',
    );
  }
  final staging = File(stagingPath).absolute;
  final stagingError = _validateStaging(staging, source);
  if (stagingError != null) return _blocked('environment', stagingError);

  final credentialPath =
      environment['SIMS_PROVIDER_FCM_CREDENTIAL_PATH']?.trim().isNotEmpty ==
          true
      ? environment['SIMS_PROVIDER_FCM_CREDENTIAL_PATH']!.trim()
      : environment['FIREBASE_SERVICE_ACCOUNT']?.trim();
  if (credentialPath == null ||
      !_isUsableServiceAccount(File(credentialPath).absolute)) {
    return _blocked('credentials', 'A usable FCM service account is required.');
  }

  final live = await _liveAdbDevices();
  if (!live.contains(physical) || !live.contains(emulator)) {
    return _blocked(
      'deviceLost',
      'An explicitly assigned Android target is not live in ADB.',
    );
  }
  final packageName = resolveAndroidAppPackage();
  if (await _appCardCount(physical, packageName) != 0 ||
      await _appCardCount(emulator, packageName) != 0) {
    return _blocked(
      'environment',
      'Strict proof requires a zero app-card baseline on both targets.',
    );
  }

  late final AndroidAppStateGuard stateGuard;
  try {
    stateGuard = await AndroidAppStateGuard.capture(
      devices: <String>[physical, emulator],
      packageName: packageName,
      backupLabel: 'group-strict-notification-393',
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
  late final Object outcome;
  try {
    await stateGuard.prepareFreshInstalls(preparedArtifact);
    outcome = await _capture(
      environment: environment,
      captureDirectory: captureDirectory,
      physical: physical,
      emulator: emulator,
      staging: staging,
      relayTarget: relayTarget!,
      relayKey: File(relayKeyPath).absolute,
      credential: File(credentialPath).absolute,
      preparedArtifact: preparedArtifact,
      preparedSha: preparedSha,
      packageName: packageName,
    );
  } finally {
    await stateGuard.restoreAll();
  }
  if (outcome is _AdapterResult) return outcome;
  final success = outcome as _CaptureSuccess;

  if (await _appCardCount(physical, packageName) != 0 ||
      await _appCardCount(emulator, packageName) != 0) {
    return _failed(
      detail: 'App state restored but a campaign notification card survived.',
      childExitCode: 1,
      assertionsAttempted: groupStrictNotificationCriteria.length,
      artifactPresent: true,
    );
  }

  final artifactCanonical = success.artifact.resolveSymbolicLinksSync();
  final evidence = writeSimsArtifactEvidenceSync(
    directory: proofDirectory,
    capabilityId: groupStrictNotificationCapabilityId,
    validatorIds: const <String>[_artifactValidator],
    payload: <String, Object?>{
      'status': 'passed',
      'scenarioIds': const <String>[groupStrictNotificationScenarioId],
      'criteria': groupStrictNotificationCriteria,
      'targetIds': <String>[physical, emulator],
      'targetKinds': const <String>['physical', 'emulator'],
      'preparedArtifactPath': preparedArtifact.resolveSymbolicLinksSync(),
      'preparedArtifactSha256': preparedSha,
      'captureRoot': success.captureRoot.resolveSymbolicLinksSync(),
      'captureArtifactPath': artifactCanonical,
      'captureArtifactSha256': sha256
          .convert(File(artifactCanonical).readAsBytesSync())
          .toString(),
      'childBuildCount': 0,
      'manualTaps': 0,
      'stateRestored': true,
      'postRestoreAppCardCount': 0,
    },
  );
  final audit = auditSimsArtifactEvidence(
    evidence: evidence,
    expectedValidatorIds: const <String>[_artifactValidator],
  );
  return audit.isValid
      ? _passed(evidence)
      : _failed(
          detail: 'Strict aggregate proof audit failed: ${audit.detail}',
          childExitCode: 1,
          assertionsAttempted: groupStrictNotificationCriteria.length,
          artifactPresent: true,
        );
}

Future<Object> _capture({
  required Map<String, String> environment,
  required Directory captureDirectory,
  required String physical,
  required String emulator,
  required File staging,
  required String relayTarget,
  required File relayKey,
  required File credential,
  required File preparedArtifact,
  required String preparedSha,
  required String packageName,
}) async {
  final adapter = PhysicalDeviceCaptureAdapter(
    captureDriver: File(_captureDriver),
    scenarioId: groupStrictNotificationScenarioId,
    senderDeviceId: emulator,
    recipientDeviceId: physical,
    artifactDirectory: captureDirectory,
    additionalArguments: <String>[
      '--staging-manifest',
      staging.path,
      '--relay-target',
      relayTarget,
      '--relay-key',
      relayKey.path,
      '--service-account',
      credential.path,
      '--prebuilt-android-apk',
      preparedArtifact.path,
      '--no-child-builds',
      '--android-state-prepared',
    ],
    environment: environment,
  );
  final capture = await runPhysicalDeviceCapture(adapter);
  if (capture.launchError case final error?) {
    return _blocked(
      'missingDriver',
      'Strict capture launch failed: ${error.message}',
    );
  }
  final childExit = capture.exitCode!;
  if (childExit != 0) {
    return childExit == 78
        ? _blocked(
            'environment',
            'The strict source capture was environment-blocked. Raw evidence '
                'is retained at ${captureDirectory.path}.',
          )
        : _failed(
            detail: 'The strict source capture exited $childExit.',
            childExitCode: childExit,
            assertionsAttempted: 1,
            artifactPresent: false,
          );
  }
  final artifact = physicalDeviceCaptureArtifact(
    captureDirectory,
    groupStrictNotificationScenarioId,
  );
  final validation = await validateGroupStrictNotificationArtifact(
    artifactFile: artifact,
    expectedPhysicalDeviceId: physical,
    expectedEmulatorDeviceId: emulator,
    expectedApkSha256: preparedSha,
    expectedPackageName: packageName,
  );
  if (!validation.ok) {
    return _failed(
      detail: 'Strict raw artifact rejected: ${validation.detail}',
      childExitCode: 1,
      assertionsAttempted: groupStrictNotificationCriteria.length,
      artifactPresent: _isRegularFile(artifact),
    );
  }
  final provenance = File(
    '${captureDirectory.path}${Platform.pathSeparator}'
    'candidate_build_provenance.json',
  );
  if (!_isCentralPreparedProvenance(provenance, preparedSha)) {
    return _failed(
      detail: 'Strict capture did not retain central base-APK provenance.',
      childExitCode: 1,
      assertionsAttempted: groupStrictNotificationCriteria.length,
      artifactPresent: true,
    );
  }
  return _CaptureSuccess(artifact: artifact, captureRoot: captureDirectory);
}

String? _validateStaging(
  File file,
  GroupReactionNotificationScenario scenario,
) {
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) return 'Staging manifest root must be an object.';
    final result = validateGroupReactionNotificationStagingManifest(
      decoded.map<String, Object?>((key, value) => MapEntry('$key', value)),
      scenario: scenario,
    );
    return result.ok ? null : result.detail;
  } on Object catch (error) {
    return 'Staging manifest is invalid: $error';
  }
}

Future<Set<String>> _liveAdbDevices() async {
  try {
    final result = await Process.run('adb', const <String>['devices']);
    if (result.exitCode != 0) return const <String>{};
    return '${result.stdout}'
        .split('\n')
        .where((line) => line.endsWith('\tdevice'))
        .map((line) => line.split('\t').first.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
  } on ProcessException {
    return const <String>{};
  }
}

Future<int> _appCardCount(String device, String packageName) async {
  final result = await Process.run('adb', <String>[
    '-s',
    device,
    'shell',
    'dumpsys',
    'notification',
    '--noredact',
  ]);
  if (result.exitCode != 0) {
    throw StateError('notification state is unreadable on $device');
  }
  final active = '${result.stdout}'.split(RegExp(r'\nRanking Config:')).first;
  final package = RegExp(r'\bpkg=' + RegExp.escape(packageName) + r'\b');
  return RegExp(r'NotificationRecord\([\s\S]*?(?=\n\s*NotificationRecord\(|$)')
      .allMatches(active)
      .map((match) => match.group(0)!)
      .where(package.hasMatch)
      .length;
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
        ? 'build/sims/proofs/$groupStrictNotificationCapabilityId'
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
    for (final criterion in groupStrictNotificationCriteria) {
      stdout.writeln(criterion);
    }
    return;
  }
  if (args.contains('--probe-source-extension')) {
    final source = groupReactionNotificationScenario(
      groupStrictNotificationScenarioId,
    );
    if (source == null) {
      stderr.writeln('MISSING: strict source extension.');
      exitCode = 78;
    } else {
      stdout.writeln('READY: strict source extension.');
    }
    return;
  }
  final artifact = _valueFor(args, '--validate-artifact');
  if (artifact != null) {
    final validation = await validateGroupStrictNotificationArtifact(
      artifactFile: File(artifact),
      expectedPhysicalDeviceId: _valueFor(args, '--physical') ?? '',
      expectedEmulatorDeviceId: _valueFor(args, '--emulator') ?? '',
      expectedApkSha256: _valueFor(args, '--apk-sha256') ?? '',
      expectedPackageName: _valueFor(args, '--package') ?? '',
    );
    if (!validation.ok) {
      stderr.writeln('INVALID: ${validation.detail}');
      exitCode = 65;
    } else {
      stdout.writeln('VALID: Plan-393 strict artifact accepted.');
    }
    return;
  }
  if (args.isNotEmpty) {
    stderr.writeln(
      'Usage: run_group_strict_notification_sims.dart '
      '[--list-criteria | --probe-source-extension | --validate-artifact '
      '<json> --physical <id> --emulator <id> --apk-sha256 <sha> '
      '--package <name>]',
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
      detail: 'Strict adapter failed before verdict: ${error.runtimeType}.',
      childExitCode: 1,
      assertionsAttempted: 0,
      artifactPresent: false,
    );
  }
  stdout.writeln('SIMS_RESULT_JSON=${jsonEncode(result.json)}');
  exitCode = result.processExitCode;
}
