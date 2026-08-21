#!/usr/bin/env dart

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../tool/sims/artifact_evidence.dart';
import '../support/android_app_state_guard.dart';
import '_android_app_package.dart';
import 'reaction_notification_proof_support.dart';

const String _capabilityId = 'notifications.android_typed_reaction_smoke';
const String _scenarioId = 'android_typed_reaction_smoke';
const String _runnerPath =
    'integration_test/scripts/run_1to1_reaction_notification_device.dart';
const String _validatorPath =
    'integration_test/one_to_one_reaction_notification_proof_test.dart';
const String _artifactEnvironmentKey = 'SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM';
const String _physicalEnvironmentKey = 'SIMS_ANDROID_PHYSICAL_DEVICE_ID';
const String _emulatorEnvironmentKey = 'SIMS_ANDROID_EMULATOR_DEVICE_ID';
const String _buildProfile = 'android.production_fcm';

final RegExp _safeAndroidId = RegExp(r'^[A-Za-z0-9._:-]{1,160}$');
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
      'scenarioIds': const <String>[_scenarioId],
    }, 78);

_AdapterResult _failed(
  String detail, {
  int assertionsAttempted = 0,
  bool artifactPresent = false,
  int childExitCode = 1,
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
      'assertionsAttempted': 1,
      'artifactPresent': true,
      'printOnly': false,
      'exitCode': 0,
      'detail':
          'The killed-recipient typed 1:1 reaction passed from one unchanged '
          'central android.production_fcm APK with zero child builds and '
          'exact Android state restoration.',
      'artifactEvidence': evidence.toJson(),
    }, 0);

_AdapterResult _g30DiagnosticFailed(SimsArtifactEvidence evidence) =>
    _AdapterResult(<String, Object?>{
      'status': 'FAIL',
      'assertionsAttempted': 1,
      'artifactPresent': true,
      'printOnly': false,
      'blocker': 'test',
      'exitCode': 1,
      'detail':
          'Expected TC-393-14 diagnostic reproduced direct post-show '
          'database_closed on the base rich FlutterFire path.',
      // Use the existing Sims evidence envelope. SimsVerdict intentionally
      // discards unknown adapter fields while preserving this content-addressed
      // path/digest/validator binding in the aggregate report.
      'artifactEvidence': evidence.toJson(),
    }, 1);

Future<_AdapterResult> _run(Map<String, String> environment) async {
  final expectG30Diagnostic =
      environment['PLAN393_EXPECT_G30_DIAGNOSTIC'] == 'true';
  final relayAddresses = environment['MKNOON_RELAY_ADDRESSES']?.trim() ?? '';
  final relayTarget = environment['MKNOON_257_RELAY_TARGET']?.trim() ?? '';
  if (relayAddresses.isEmpty ||
      relayAddresses.contains(RegExp(r'[\r\n]')) ||
      relayTarget.isEmpty ||
      relayTarget.contains(RegExp(r'[\r\n]'))) {
    return _blocked(
      'environment',
      'MKNOON_RELAY_ADDRESSES and MKNOON_257_RELAY_TARGET are required for '
          'the staging relay boundary.',
    );
  }

  final artifactPath = environment[_artifactEnvironmentKey]?.trim() ?? '';
  if (artifactPath.isEmpty) {
    return _blocked(
      'missingArtifact',
      '$_artifactEnvironmentKey is required; child builds are forbidden.',
    );
  }
  final artifact = File(artifactPath).absolute;
  if (!_isRegularFile(artifact) || artifact.lengthSync() <= 0) {
    return _blocked(
      'missingArtifact',
      '$_artifactEnvironmentKey is not a non-empty prepared APK: '
          '$artifactPath',
    );
  }
  final profile = environment['SIMS_ARTIFACT_PROFILE_ID']?.trim();
  if (profile != null && profile.isNotEmpty && profile != _buildProfile) {
    return _blocked(
      'missingArtifact',
      'Prepared profile $profile is not $_buildProfile.',
    );
  }

  final credentialPath =
      environment['SIMS_PROVIDER_FCM_CREDENTIAL_PATH']?.trim().isNotEmpty ==
          true
      ? environment['SIMS_PROVIDER_FCM_CREDENTIAL_PATH']!.trim()
      : environment['FIREBASE_SERVICE_ACCOUNT']?.trim() ?? '';
  if (!_isUsableServiceAccount(File(credentialPath).absolute)) {
    return _blocked(
      'credentials',
      'A readable FCM service-account JSON containing project_id is '
          'required.',
    );
  }

  final relayKeyPath = environment['MKNOON_257_RELAY_KEY']?.trim() ?? '';
  final stagingPath = environment['MKNOON_257_STAGING_MANIFEST']?.trim() ?? '';
  final relayKey = File(relayKeyPath).absolute;
  final staging = File(stagingPath).absolute;
  if (!_isRegularFile(relayKey) || !_isRegularFile(staging)) {
    return _blocked(
      'environment',
      'MKNOON_257_RELAY_KEY and MKNOON_257_STAGING_MANIFEST must name '
          'readable files.',
    );
  }
  final stagingError = _validateStagingManifest(staging);
  if (stagingError != null) return _blocked('environment', stagingError);

  final physical = environment[_physicalEnvironmentKey]?.trim() ?? '';
  final emulator = environment[_emulatorEnvironmentKey]?.trim() ?? '';
  if (!_safeAndroidId.hasMatch(physical) ||
      !_emulatorId.hasMatch(emulator) ||
      physical == emulator ||
      _emulatorId.hasMatch(physical)) {
    return _blocked(
      'targetUnavailable',
      'One explicit physical Android ID and one distinct Android emulator ID '
          'are required.',
    );
  }

  final runner = File(_runnerPath).absolute;
  if (!_isRegularFile(runner)) {
    return _blocked('missingDriver', 'The typed reaction runner is missing.');
  }
  final targets = await _verifyTargets(physical: physical, emulator: emulator);
  if (targets != null) return targets;

  final proofDirectory = _proofDirectory(environment)
    ..createSync(recursive: true);
  final captureRoot = Directory(
    '${proofDirectory.path}${Platform.pathSeparator}'
    'capture-${DateTime.now().toUtc().microsecondsSinceEpoch}-$pid',
  );
  if (captureRoot.existsSync()) {
    return _failed('Unique typed-reaction capture directory already exists.');
  }
  captureRoot.createSync();
  if (captureRoot.listSync().isNotEmpty) {
    return _failed('Fresh typed-reaction capture directory is not empty.');
  }

  final preparedArtifactSha256Before = _sha256File(artifact);
  _AdapterResult? stopped;
  File? rawArtifact;
  Map<String, Object?>? expectedG30Diagnostic;
  late final AndroidAppStateGuard stateGuard;
  try {
    stateGuard = await AndroidAppStateGuard.capture(
      devices: <String>[physical, emulator],
      packageName: resolveAndroidAppPackage(),
      backupLabel: 'typed-reaction-notification',
    );
  } on AndroidAppStateBlocked catch (error) {
    return _blocked('environment', error.detail);
  } on AndroidAppStateFailure catch (error) {
    return _failed(error.detail);
  }

  try {
    await stateGuard.prepareFreshInstalls(artifact);
    Process? child;
    try {
      child = await Process.start(
        Platform.resolvedExecutable,
        <String>[
          'run',
          runner.path,
          '--scenario',
          _scenarioId,
          '--sender',
          physical,
          '--recipient',
          emulator,
          '--artifact-dir',
          captureRoot.path,
          '--relay-target',
          relayTarget,
          '--relay-key',
          relayKey.path,
          '--service-account',
          File(credentialPath).absolute.path,
          '--staging-manifest',
          staging.path,
          '--prebuilt-android-apk',
          artifact.path,
          '--no-child-builds',
          '--android-state-prepared',
        ],
        environment: environment,
        includeParentEnvironment: true,
      );
    } on ProcessException catch (error) {
      stopped = _blocked(
        'missingDriver',
        'Could not launch the typed reaction runner: ${error.message}',
      );
    }
    if (child != null) {
      final stdoutDone = child.stdout.listen(stderr.add).asFuture<void>();
      final stderrDone = child.stderr.listen(stderr.add).asFuture<void>();
      final childExit = await child.exitCode;
      await Future.wait<void>(<Future<void>>[stdoutDone, stderrDone]);
      rawArtifact = File(
        '${captureRoot.path}${Platform.pathSeparator}$_scenarioId.json',
      );
      if (childExit == 78) {
        stopped = _blocked(
          'environment',
          'The typed reaction device proof could not execute on its assigned '
              'boundary.',
        );
      } else if (childExit != 0) {
        stopped = _failed(
          'Typed reaction capture/proof exited $childExit.',
          assertionsAttempted: 1,
          artifactPresent: rawArtifact.existsSync(),
          childExitCode: childExit,
        );
      } else {
        final rawError = _validateRawArtifact(
          rawArtifact,
          expectedSha256: preparedArtifactSha256Before,
          expectedSender: physical,
          expectedRecipient: emulator,
        );
        final provenanceError = _validateCentralProvenance(
          File(
            '${captureRoot.path}${Platform.pathSeparator}'
            'candidate_build_provenance.json',
          ),
          expectedSha256: preparedArtifactSha256Before,
        );
        final validationError = rawError ?? provenanceError;
        if (validationError != null) {
          stopped = _failed(
            validationError,
            assertionsAttempted: 1,
            artifactPresent: rawArtifact.existsSync(),
          );
        } else {
          final diagnosticLog = File(
            '${captureRoot.path}${Platform.pathSeparator}'
            'recipient_background_push.log',
          );
          final diagnosticResult = _validateG30Diagnostics(
            diagnosticLog,
            expectFailure: expectG30Diagnostic,
          );
          if (diagnosticResult.error != null) {
            stopped = _failed(
              diagnosticResult.error!,
              assertionsAttempted: 1,
              artifactPresent: true,
            );
          } else if (expectG30Diagnostic) {
            final sanitized =
                File(
                  '${captureRoot.path}${Platform.pathSeparator}'
                  'plan393_g30_diagnostic.json',
                )..writeAsStringSync(
                  const JsonEncoder.withIndent(' ').convert(<String, Object?>{
                    'schema': 'mknoon.plan393.g30-diagnostic.v1',
                    'buildProfile': _buildProfile,
                    'predicate': 'direct_post_show_database_closed',
                    'rawLogSha256': _sha256File(diagnosticLog),
                    'records': diagnosticResult.records,
                  }),
                );
            expectedG30Diagnostic = <String, Object?>{
              'schema': 'mknoon.plan393.g30-diagnostic-result.v1',
              'predicate': 'direct_post_show_database_closed',
              'buildProfile': _buildProfile,
              'rawArtifactPath': rawArtifact.resolveSymbolicLinksSync(),
              'rawArtifactSha256': _sha256File(rawArtifact),
              'rawLogPath': diagnosticLog.resolveSymbolicLinksSync(),
              'rawLogSha256': _sha256File(diagnosticLog),
              'diagnosticEvidencePath': sanitized.resolveSymbolicLinksSync(),
              'diagnosticEvidenceSha256': _sha256File(sanitized),
              'freshCaptureRoot': captureRoot.resolveSymbolicLinksSync(),
              'appStateRestored': false,
              'zeroCardBaselineRestored': false,
            };
          }
        }
      }
    }
  } finally {
    await stateGuard.restoreAll();
  }

  if (expectedG30Diagnostic != null) {
    final notificationDump = await Process.run('adb', <String>[
      '-s',
      emulator,
      'shell',
      'dumpsys',
      'notification',
      '--noredact',
    ]);
    final zeroCards =
        notificationDump.exitCode == 0 &&
        extractActiveNotificationCards(
          '${notificationDump.stdout}',
          packageName: resolveAndroidAppPackage(),
        ).isEmpty;
    expectedG30Diagnostic['appStateRestored'] = stateGuard.restored;
    expectedG30Diagnostic['zeroCardBaselineRestored'] = zeroCards;
    if (!stateGuard.restored || !zeroCards) {
      return _failed(
        'G30 was reproduced, but local/card restoration did not complete.',
        assertionsAttempted: 1,
        artifactPresent: true,
      );
    }
    final evidence = writeSimsArtifactEvidenceSync(
      directory: proofDirectory,
      capabilityId: _capabilityId,
      validatorIds: const <String>[_validatorPath],
      payload: <String, Object?>{
        'status': 'diagnostic_failure',
        'evidenceKind': 'plan393_g30_diagnostic',
        'diagnostic': expectedG30Diagnostic,
      },
    );
    final audit = auditSimsArtifactEvidence(
      evidence: evidence,
      expectedValidatorIds: const <String>[_validatorPath],
    );
    if (!audit.isValid) {
      return _failed(
        'G30 diagnostic evidence failed: ${audit.detail}',
        assertionsAttempted: 1,
        artifactPresent: true,
      );
    }
    return _g30DiagnosticFailed(evidence.copyWith(path: audit.canonicalPath!));
  }
  if (stopped != null) return stopped;
  if (!_isRegularFile(artifact)) {
    return _failed(
      'The central prepared APK was deleted by the typed reaction child.',
      assertionsAttempted: 1,
      artifactPresent: rawArtifact?.existsSync() ?? false,
    );
  }
  final preparedArtifactSha256After = _sha256File(artifact);
  if (preparedArtifactSha256After != preparedArtifactSha256Before) {
    return _failed(
      'The central prepared APK changed during typed reaction capture.',
      assertionsAttempted: 1,
      artifactPresent: rawArtifact?.existsSync() ?? false,
    );
  }

  final captured = rawArtifact!;
  final evidence = writeSimsArtifactEvidenceSync(
    directory: proofDirectory,
    capabilityId: _capabilityId,
    validatorIds: const <String>[_validatorPath],
    payload: <String, Object?>{
      'status': 'passed',
      'scenarioIds': const <String>[_scenarioId],
      'targetIds': <String>[physical, emulator],
      'targetKinds': const <String>['physical', 'emulator'],
      'preparedArtifactPath': artifact.resolveSymbolicLinksSync(),
      'preparedArtifactSha256': preparedArtifactSha256Before,
      'preparedArtifactSha256Before': preparedArtifactSha256Before,
      'preparedArtifactSha256After': preparedArtifactSha256After,
      'buildMode': 'central_prebuilt',
      'buildProfile': _buildProfile,
      'childBuildCount': 0,
      'captureArtifacts': <Map<String, Object?>>[
        <String, Object?>{
          'scenario': _scenarioId,
          'path': captured.resolveSymbolicLinksSync(),
          'sha256': _sha256File(captured),
        },
      ],
      'appStateRestored': stateGuard.restored,
    },
  );
  final audit = auditSimsArtifactEvidence(
    evidence: evidence,
    expectedValidatorIds: const <String>[_validatorPath],
  );
  if (!audit.isValid) {
    return _failed(
      'Aggregate typed-reaction evidence failed: ${audit.detail}',
      assertionsAttempted: 1,
      artifactPresent: true,
    );
  }
  return _passed(evidence);
}

({String? error, List<Map<String, Object?>> records}) _validateG30Diagnostics(
  File log, {
  required bool expectFailure,
}) {
  if (!_isRegularFile(log)) {
    return (
      error: 'Typed capture omitted its G30 diagnostic log.',
      records: const [],
    );
  }
  final records = <Map<String, Object?>>[];
  for (final line in log.readAsLinesSync()) {
    if (!line.contains('PUSH_BACKGROUND_DIRECT_VALIDATOR_DIAGNOSTIC')) {
      continue;
    }
    final marker = line.indexOf('[FLOW] ');
    if (marker < 0) continue;
    try {
      final decoded = jsonDecode(line.substring(marker + '[FLOW] '.length));
      if (decoded is! Map ||
          decoded['event'] != 'PUSH_BACKGROUND_DIRECT_VALIDATOR_DIAGNOSTIC' ||
          decoded['details'] is! Map) {
        continue;
      }
      final details = (decoded['details'] as Map).map<String, Object?>(
        (key, value) => MapEntry('$key', value),
      );
      const exactKeys = <String>{
        'phase',
        'sqfliteCode',
        'independentHandleState',
        'validatorDisposition',
        'outcome',
      };
      if (details.keys.toSet().difference(exactKeys).isNotEmpty ||
          exactKeys.difference(details.keys.toSet()).isNotEmpty) {
        return (
          error: 'G30 diagnostic escaped its closed-domain field set.',
          records: records,
        );
      }
      records.add(details);
    } on Object {
      return (
        error: 'G30 diagnostic flow record is invalid JSON.',
        records: records,
      );
    }
  }
  if (records.isEmpty) {
    return (
      error: 'No direct post-show validator completion was observed.',
      records: records,
    );
  }
  final failures = records.where(
    (record) =>
        record['outcome'] == 'failure' &&
        record['sqfliteCode'] == 'database_closed' &&
        record['validatorDisposition'] == 'not_completed',
  );
  if (expectFailure) {
    if (failures.isEmpty) {
      return (
        error: 'Expected G30 database_closed predicate was not reproduced.',
        records: records,
      );
    }
    return (error: null, records: records);
  }
  const positiveDispositions = <String>{'keep', 'read', 'retire'};
  if (records.any(
    (record) =>
        record['outcome'] != 'completed' ||
        record['sqfliteCode'] != 'none' ||
        !positiveDispositions.contains(record['validatorDisposition']),
  )) {
    return (
      error: 'Direct post-show validator did not complete positively.',
      records: records,
    );
  }
  return (error: null, records: records);
}

Future<_AdapterResult?> _verifyTargets({
  required String physical,
  required String emulator,
}) async {
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
      );
    }
    final roleResults = await Future.wait<ProcessResult>(
      <Future<ProcessResult>>[
        Process.run('adb', <String>[
          '-s',
          physical,
          'shell',
          'getprop',
          'ro.kernel.qemu',
        ]),
        Process.run('adb', <String>[
          '-s',
          emulator,
          'shell',
          'getprop',
          'ro.kernel.qemu',
        ]),
      ],
    );
    if (roleResults[0].exitCode != 0 ||
        roleResults[1].exitCode != 0 ||
        '${roleResults[0].stdout}'.trim() == '1' ||
        '${roleResults[1].stdout}'.trim() != '1') {
      return _blocked(
        'targetUnavailable',
        'Assigned targets are not a physical sender and emulator recipient.',
      );
    }
  } on ProcessException {
    return _blocked('deviceLost', 'ADB could not verify assigned targets.');
  }
  return null;
}

String? _validateRawArtifact(
  File file, {
  required String expectedSha256,
  required String expectedSender,
  required String expectedRecipient,
}) {
  if (!_isRegularFile(file)) return 'Fresh typed-reaction artifact is absent.';
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) {
      return 'Typed-reaction artifact root is not an object.';
    }
    final artifact = decoded.map<String, Object?>(
      (key, value) => MapEntry('$key', value),
    );
    final appValue = artifact['app'];
    final observationValue = artifact['observation'];
    final attributionValue = artifact['sourceAttribution'];
    if (appValue is! Map ||
        observationValue is! Map ||
        attributionValue is! Map) {
      return 'Typed-reaction artifact omits its app/observation/attribution maps.';
    }
    final app = appValue.map<String, Object?>(
      (key, value) => MapEntry('$key', value),
    );
    final observation = observationValue.map<String, Object?>(
      (key, value) => MapEntry('$key', value),
    );
    final attribution = attributionValue.map<String, Object?>(
      (key, value) => MapEntry('$key', value),
    );
    if (artifact['scenario'] != _scenarioId ||
        artifact['status'] != 'passed' ||
        app['buildMode'] != 'central_prebuilt' ||
        app['buildProfile'] != _buildProfile ||
        app['childBuildCount'] != 0 ||
        app['apkSha256'] != expectedSha256 ||
        app['senderHarnessApkSha256'] != expectedSha256 ||
        app['senderApkSha256'] != expectedSha256 ||
        app['recipientApkSha256'] != expectedSha256 ||
        app['senderDevice'] != expectedSender ||
        app['recipientDevice'] != expectedRecipient ||
        observation['cardPresent'] != true ||
        observation['recipientProcessAbsentBeforeReaction'] != true ||
        observation['typedCopyRequired'] != true ||
        observation['genericNewMessageRejected'] != true ||
        attribution['providerMatchedEvent'] != true ||
        attribution['recipientBackgroundPushObserved'] != true ||
        artifact['unreadLifecycle'] is! Map) {
      return 'Typed-reaction artifact failed behavior or central-build audit.';
    }
  } on Object {
    return 'Typed-reaction artifact is invalid JSON.';
  }
  return null;
}

String? _validateCentralProvenance(
  File file, {
  required String expectedSha256,
}) {
  if (!_isRegularFile(file)) return 'Central build provenance is absent.';
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map ||
        decoded['schema'] != 'mknoon.plan257.candidate-build.v1' ||
        decoded['buildMode'] != 'central_prebuilt' ||
        decoded['buildProfile'] != _buildProfile ||
        decoded['childBuildCount'] != 0 ||
        decoded['e2eApkSha256'] != expectedSha256 ||
        decoded['normalApkSha256'] != expectedSha256 ||
        decoded['senderApkSha256'] != expectedSha256 ||
        decoded['recipientApkSha256'] != expectedSha256) {
      return 'Central build provenance does not bind both roles to the APK.';
    }
  } on Object {
    return 'Central build provenance is invalid JSON.';
  }
  return null;
}

String? _validateStagingManifest(File file) {
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map ||
        decoded['schema'] != 'mknoon.plan257.staging-prerequisites.v1' ||
        decoded['environment'] != 'staging' ||
        decoded['relayActive'] != true ||
        decoded['providerConfigured'] != true ||
        decoded['providerProbeSucceeded'] != true ||
        decoded['allowAppDataReset'] != true ||
        decoded['provider'] != 'fcm') {
      return 'The staging manifest does not authorize the FCM device proof.';
    }
  } on Object catch (error) {
    return 'The staging manifest is invalid JSON: $error';
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

String _sha256File(File file) =>
    sha256.convert(file.readAsBytesSync()).toString();

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

Future<bool> _validateG30DiagnosticReport(File report) async {
  if (!_isRegularFile(report) || report.lengthSync() <= 0) return false;
  try {
    final decoded = jsonDecode(report.readAsStringSync());
    if (decoded is! Map || decoded['verdicts'] is! List) return false;
    final verdicts = (decoded['verdicts'] as List).whereType<Map>();
    final matches = verdicts.where(
      (value) => value['capabilityId'] == _capabilityId,
    );
    if (matches.length != 1) return false;
    final verdict = matches.single;
    if (verdict['status'] != 'FAIL' ||
        verdict['blocker'] != 'test' ||
        verdict['exitCode'] == 0 ||
        verdict['artifactPresent'] != true ||
        verdict['artifactEvidence'] is! Map) {
      return false;
    }
    final envelope = SimsArtifactEvidence.fromJson(verdict['artifactEvidence']);
    final envelopeAudit = auditSimsArtifactEvidence(
      evidence: envelope,
      expectedValidatorIds: const <String>[_validatorPath],
    );
    if (!envelopeAudit.isValid || envelopeAudit.canonicalPath == null) {
      return false;
    }
    final proofValue = jsonDecode(
      File(envelopeAudit.canonicalPath!).readAsStringSync(),
    );
    if (proofValue is! Map ||
        proofValue['schema'] != 'mknoon.sims.proof.v1' ||
        proofValue['capabilityId'] != _capabilityId ||
        proofValue['status'] != 'diagnostic_failure' ||
        proofValue['evidenceKind'] != 'plan393_g30_diagnostic' ||
        proofValue['diagnostic'] is! Map) {
      return false;
    }
    final diagnostic = (proofValue['diagnostic'] as Map).map<String, Object?>(
      (key, value) => MapEntry('$key', value),
    );
    if (diagnostic['schema'] != 'mknoon.plan393.g30-diagnostic-result.v1' ||
        diagnostic['predicate'] != 'direct_post_show_database_closed' ||
        diagnostic['buildProfile'] != _buildProfile ||
        diagnostic['appStateRestored'] != true ||
        diagnostic['zeroCardBaselineRestored'] != true) {
      return false;
    }
    final rootValue = diagnostic['freshCaptureRoot'];
    if (rootValue is! String || rootValue.trim().isEmpty) return false;
    final root = Directory(rootValue);
    if (!root.existsSync()) return false;
    final resolvedRoot = root.resolveSymbolicLinksSync();
    File checkedFile(String pathKey, String shaKey) {
      final path = diagnostic[pathKey];
      final expectedSha = diagnostic[shaKey];
      if (path is! String ||
          expectedSha is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedSha)) {
        throw const FormatException('missing evidence binding');
      }
      final file = File(path);
      if (!_isRegularFile(file) || _sha256File(file) != expectedSha) {
        throw const FormatException('evidence hash mismatch');
      }
      final resolved = file.resolveSymbolicLinksSync();
      if (!resolved.startsWith('$resolvedRoot${Platform.pathSeparator}')) {
        throw const FormatException('evidence escaped capture root');
      }
      return file;
    }

    final rawArtifact = checkedFile('rawArtifactPath', 'rawArtifactSha256');
    checkedFile('rawLogPath', 'rawLogSha256');
    final sanitized = checkedFile(
      'diagnosticEvidencePath',
      'diagnosticEvidenceSha256',
    );
    final raw = jsonDecode(rawArtifact.readAsStringSync());
    if (raw is! Map ||
        raw['status'] != 'passed' ||
        raw['scenario'] != _scenarioId ||
        raw['app'] is! Map ||
        (raw['app'] as Map)['buildProfile'] != _buildProfile) {
      return false;
    }
    final evidence = jsonDecode(sanitized.readAsStringSync());
    if (evidence is! Map ||
        evidence['schema'] != 'mknoon.plan393.g30-diagnostic.v1' ||
        evidence['buildProfile'] != _buildProfile ||
        evidence['predicate'] != 'direct_post_show_database_closed' ||
        evidence['records'] is! List) {
      return false;
    }
    final records = (evidence['records'] as List).whereType<Map>();
    if (!records.any(
      (record) =>
          record['outcome'] == 'failure' &&
          record['sqfliteCode'] == 'database_closed' &&
          record['validatorDisposition'] == 'not_completed',
    )) {
      return false;
    }
    final age = DateTime.now().toUtc().difference(
      report.lastModifiedSync().toUtc(),
    );
    return age >= Duration.zero && age <= const Duration(hours: 48);
  } on Object {
    return false;
  }
}

Future<void> main(List<String> args) async {
  if (args.isNotEmpty) {
    if (args.length != 2 || args.first != '--validate-g30-diagnostic-report') {
      stderr.writeln(
        'Usage: dart run $_runnerPath or '
        '--validate-g30-diagnostic-report <report.json>',
      );
      exitCode = 64;
      return;
    }
    final valid = await _validateG30DiagnosticReport(File(args[1]).absolute);
    if (!valid) {
      stderr.writeln('TC-393-14 diagnostic report rejected.');
      exitCode = 1;
      return;
    }
    stdout.writeln('PASS: TC-393-14 diagnostic report is causal and restored.');
    return;
  }
  late final _AdapterResult result;
  try {
    result = await _run(Platform.environment);
  } on AndroidAppStateFailure catch (error, stackTrace) {
    stderr.writeln(stackTrace);
    result = _failed(error.detail);
  } catch (error, stackTrace) {
    stderr.writeln(stackTrace);
    result = _failed(
      'Typed reaction Sims adapter failed before a verdict: '
      '${error.runtimeType}.',
    );
  }
  stdout.writeln('SIMS_RESULT_JSON=${jsonEncode(result.json)}');
  exitCode = result.processExitCode;
}
