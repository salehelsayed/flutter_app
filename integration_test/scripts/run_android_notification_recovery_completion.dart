#!/usr/bin/env dart

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../tool/sims/artifact_evidence.dart';
import '../support/android_app_state_guard.dart';
import '_android_app_package.dart';
import 'android_notification_recovery_completion_criteria.dart';
import 'reaction_notification_proof_support.dart';

const String _captureDriver =
    'integration_test/scripts/capture_1to1_reaction_head_provenance.dart';
const String _physicalEnvironment = 'SIMS_ANDROID_PHYSICAL_DEVICE_ID';
const String _emulatorEnvironment = 'SIMS_ANDROID_EMULATOR_DEVICE_ID';
const String _fixtureProbeEnvironment = 'PLAN393_RELAY_FIXTURE_PROBE_URL';

final RegExp _safeTarget = RegExp(r'^[A-Za-z0-9._:-]{1,160}$');
final RegExp _emulatorTarget = RegExp(r'^emulator-[0-9]+$');
final RegExp _safeRelayTarget = RegExp(r'^[A-Za-z0-9._-]+@[A-Za-z0-9.-]+$');

final class _AdapterResult {
  const _AdapterResult(this.json, this.exitCode);

  final Map<String, Object?> json;
  final int exitCode;
}

final class _CaptureSuccess {
  const _CaptureSuccess({required this.artifact, required this.root});

  final File artifact;
  final Directory root;
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
      'scenarioIds': const <String>[
        androidNotificationRecoveryCompletionScenarioId,
      ],
    }, 78);

_AdapterResult _failed({
  required String detail,
  required int assertionsAttempted,
  required bool artifactPresent,
  int childExitCode = 1,
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
    'scenarioIds': const <String>[
      androidNotificationRecoveryCompletionScenarioId,
    ],
  }, code);
}

_AdapterResult _passed(SimsArtifactEvidence evidence) =>
    _AdapterResult(<String, Object?>{
      'status': 'PASS',
      'assertionsAttempted':
          androidNotificationRecoveryCompletionAssertions.length,
      'artifactPresent': true,
      'printOnly': false,
      'exitCode': 0,
      'detail':
          'The fixed-cohort alive/background and killed direct-reaction '
          'transitions passed live opaque selection, canonical settlement, '
          'generic retirement, authenticated route removal, and exact state '
          'restoration with zero notification taps or child builds.',
      'artifactEvidence': evidence.toJson(),
    }, 0);

Future<_AdapterResult> _run(Map<String, String> environment) async {
  final credentialPath =
      environment['SIMS_PROVIDER_FCM_CREDENTIAL_PATH']?.trim().isNotEmpty ==
          true
      ? environment['SIMS_PROVIDER_FCM_CREDENTIAL_PATH']!.trim()
      : environment['FIREBASE_SERVICE_ACCOUNT']?.trim() ?? '';
  final relayAddresses = environment['MKNOON_RELAY_ADDRESSES']?.trim() ?? '';
  final relayTarget =
      environment['SIMS_NOTIFICATION_RELAY_TARGET']?.trim().isNotEmpty == true
      ? environment['SIMS_NOTIFICATION_RELAY_TARGET']!.trim()
      : environment['MKNOON_257_RELAY_TARGET']?.trim() ?? '';
  final relayKeyPath =
      environment['SIMS_NOTIFICATION_RELAY_KEY']?.trim().isNotEmpty == true
      ? environment['SIMS_NOTIFICATION_RELAY_KEY']!.trim()
      : environment['MKNOON_257_RELAY_KEY']?.trim() ?? '';
  final stagingPath = environment['MKNOON_257_STAGING_MANIFEST']?.trim() ?? '';
  final fixtureProbe = _fixtureProbe(environment[_fixtureProbeEnvironment]);
  final credential = File(credentialPath).absolute;
  final relayKey = File(relayKeyPath).absolute;
  final staging = File(stagingPath).absolute;
  if (!_usableServiceAccount(credential) ||
      relayAddresses.isEmpty ||
      relayAddresses.contains(RegExp(r'[\r\n]')) ||
      (fixtureProbe == null &&
          (!_safeRelayTarget.hasMatch(relayTarget) || !_regular(relayKey))) ||
      !_regular(staging)) {
    return _blocked(
      'credentials',
      'A service account and safe staging relay/fixture manifest authority '
          'are required. Credential values remain redacted.',
    );
  }
  final stagingError = _validateStaging(
    staging,
    requireFixture: fixtureProbe != null,
  );
  if (stagingError != null) return _blocked('environment', stagingError);

  final artifactPath =
      environment[androidNotificationRecoveryCompletionArtifactEnvironment]
          ?.trim() ??
      '';
  final preparedArtifact = File(artifactPath).absolute;
  if (!_regular(preparedArtifact) || preparedArtifact.lengthSync() <= 0) {
    return _blocked(
      'missingArtifact',
      '$androidNotificationRecoveryCompletionArtifactEnvironment must name '
          'the centrally prepared fixed-cohort APK; child builds are forbidden.',
    );
  }
  if (environment['SIMS_ARTIFACT_PROFILE_ID']?.trim() !=
      androidNotificationRecoveryCompletionBuildProfile) {
    return _blocked(
      'missingArtifact',
      'The prepared artifact is not owned by '
          '$androidNotificationRecoveryCompletionBuildProfile.',
    );
  }
  final preparedSha = _digest(preparedArtifact);

  final physical = environment[_physicalEnvironment]?.trim() ?? '';
  final emulator = environment[_emulatorEnvironment]?.trim() ?? '';
  if (!_safeTarget.hasMatch(physical) ||
      !_emulatorTarget.hasMatch(emulator) ||
      _emulatorTarget.hasMatch(physical) ||
      physical == emulator) {
    return _blocked(
      'targetUnavailable',
      'One explicit physical Android sender and a distinct Android emulator '
          'receiver are required.',
    );
  }
  final liveError = await _verifyLiveTargets(
    physical: physical,
    emulator: emulator,
  );
  if (liveError != null) return _blocked('deviceLost', liveError);

  if (fixtureProbe == null) {
    final relay = await Process.run('ssh', <String>[
      '-o',
      'BatchMode=yes',
      '-o',
      'ConnectTimeout=15',
      '-i',
      relayKey.path,
      relayTarget,
      'systemctl is-active relay-server',
    ]);
    if (relay.exitCode != 0 || '${relay.stdout}'.trim() != 'active') {
      return _blocked(
        'environment',
        'The credentialed staging relay is not active.',
      );
    }
  } else if (!await _fixtureReady(fixtureProbe)) {
    return _blocked(
      'environment',
      'The disposable encrypted Redis/FCM relay fixture is not ready.',
    );
  }
  if (!_regular(File(_captureDriver).absolute)) {
    return _blocked(
      'missingDriver',
      'The shared 1:1 capture driver is missing.',
    );
  }

  final packageName = resolveAndroidAppPackage();
  if (await _appCardCount(physical, packageName) != 0 ||
      await _appCardCount(emulator, packageName) != 0) {
    return _blocked(
      'environment',
      'Recovery proof requires a zero app-card baseline on both targets.',
    );
  }

  late final AndroidAppStateGuard stateGuard;
  try {
    stateGuard = await AndroidAppStateGuard.capture(
      devices: <String>[physical, emulator],
      packageName: packageName,
      backupLabel: 'android-fixed-wake-recovery-393',
      preparedArtifact: preparedArtifact,
      expectedArtifactSha256: preparedSha,
    );
  } on AndroidAppStateBlocked catch (error) {
    return _blocked('environment', error.detail);
  } on AndroidAppStateFailure catch (error) {
    return _failed(
      detail: error.detail,
      assertionsAttempted: 0,
      artifactPresent: false,
    );
  }

  final proofDirectory = _proofDirectory(environment)
    ..createSync(recursive: true);
  final captureRoot = Directory(
    '${proofDirectory.path}${Platform.pathSeparator}'
    'capture-${DateTime.now().toUtc().microsecondsSinceEpoch}-$pid',
  )..createSync();
  late final Object outcome;
  try {
    await stateGuard.prepareFreshInstalls(preparedArtifact);
    outcome = await _capture(
      environment: environment,
      physical: physical,
      emulator: emulator,
      captureRoot: captureRoot,
      relayTarget: relayTarget,
      relayKey: relayKey,
      staging: staging,
      credential: credential,
      preparedArtifact: preparedArtifact,
      preparedSha: preparedSha,
      packageName: packageName,
      fixtureProbe: fixtureProbe,
    );
  } finally {
    try {
      await stateGuard.restoreAll();
    } on Object {
      return _failed(
        detail: 'Exact Android package/private-state restoration failed.',
        assertionsAttempted:
            androidNotificationRecoveryCompletionAssertions.length,
        artifactPresent: true,
      );
    }
  }
  if (outcome is _AdapterResult) return outcome;
  final success = outcome as _CaptureSuccess;
  if (_digest(preparedArtifact) != preparedSha) {
    return _failed(
      detail: 'The central prepared APK changed during capture.',
      assertionsAttempted:
          androidNotificationRecoveryCompletionAssertions.length,
      artifactPresent: true,
    );
  }
  if (await _appCardCount(physical, packageName) != 0 ||
      await _appCardCount(emulator, packageName) != 0) {
    return _failed(
      detail: 'State restoration completed but a campaign app card survived.',
      assertionsAttempted:
          androidNotificationRecoveryCompletionAssertions.length,
      artifactPresent: true,
    );
  }

  final finalEvidence = writeSimsArtifactEvidenceSync(
    directory: proofDirectory,
    capabilityId: androidNotificationRecoveryCompletionCapabilityId,
    validatorIds: const <String>[
      androidNotificationRecoveryCompletionValidator,
    ],
    payload: <String, Object?>{
      'status': 'passed',
      'recordedAt': DateTime.now().toUtc().toIso8601String(),
      'campaignSchema': androidNotificationRecoveryCompletionCampaignSchema,
      'scenarioIds': const <String>[
        androidNotificationRecoveryCompletionScenarioId,
      ],
      'criteria': androidNotificationRecoveryCompletionAssertions,
      'targetIds': <String>[physical, emulator],
      'targetKinds': const <String>['physical', 'emulator'],
      'buildProfile': androidNotificationRecoveryCompletionBuildProfile,
      'buildCapability': androidNotificationRecoveryCompletionBuildCapability,
      'preparedArtifactEnvironment':
          androidNotificationRecoveryCompletionArtifactEnvironment,
      'preparedArtifactSha256': preparedSha,
      'captureRoot': success.root.resolveSymbolicLinksSync(),
      'captureArtifactPath': success.artifact.resolveSymbolicLinksSync(),
      'captureArtifactSha256': _digest(success.artifact),
      'childBuildCount': 0,
      'manualTaps': 0,
      'notificationCardTaps': 0,
      'mainActivityLaunchesDuringKilledRecovery': 0,
      'authenticatedRouteUnregister': true,
      'routeAbsentReadback': true,
      'stateRestored': stateGuard.restored,
      'postRestoreAppCardCount': 0,
    },
  );
  final finalFile = File(finalEvidence.path);
  final validation = validateAndroidNotificationRecoveryCompletionArtifact(
    artifactFile: finalFile,
    expectedPhysicalDeviceId: physical,
    expectedEmulatorDeviceId: emulator,
    expectedApkSha256: preparedSha,
    expectedPackageName: packageName,
  );
  final audit = auditSimsArtifactEvidence(
    evidence: finalEvidence,
    expectedValidatorIds: const <String>[
      androidNotificationRecoveryCompletionValidator,
    ],
  );
  if (!validation.ok || !audit.isValid) {
    return _failed(
      detail: validation.ok
          ? 'Final artifact evidence audit failed: ${audit.detail}'
          : 'Final recovery artifact rejected: ${validation.detail}',
      assertionsAttempted:
          androidNotificationRecoveryCompletionAssertions.length,
      artifactPresent: true,
    );
  }
  return _passed(finalEvidence);
}

Future<Object> _capture({
  required Map<String, String> environment,
  required String physical,
  required String emulator,
  required Directory captureRoot,
  required String relayTarget,
  required File relayKey,
  required File staging,
  required File credential,
  required File preparedArtifact,
  required String preparedSha,
  required String packageName,
  required Uri? fixtureProbe,
}) async {
  late final Process child;
  try {
    final arguments = <String>[
      'run',
      File(_captureDriver).absolute.path,
      '--fixed-wake-recovery',
      '--sender',
      physical,
      '--recipient',
      emulator,
      '--artifact-dir',
      captureRoot.path,
      if (fixtureProbe == null) ...<String>[
        '--relay-target',
        relayTarget,
        '--relay-key',
        relayKey.path,
      ] else ...<String>['--relay-fixture-probe', fixtureProbe.toString()],
      '--staging-manifest',
      staging.path,
      '--service-account',
      credential.path,
      '--prebuilt-android-apk',
      preparedArtifact.path,
      '--no-child-builds',
      '--android-state-prepared',
    ];
    child = await Process.start(
      Platform.resolvedExecutable,
      arguments,
      environment: environment,
      includeParentEnvironment: true,
    );
  } on ProcessException catch (error) {
    return _blocked(
      'missingDriver',
      'The fixed-wake capture could not launch: ${error.message}',
    );
  }
  final stdoutDone = child.stdout.listen(stderr.add).asFuture<void>();
  final stderrDone = child.stderr.listen(stderr.add).asFuture<void>();
  final childExit = await child.exitCode;
  await Future.wait<void>(<Future<void>>[stdoutDone, stderrDone]);
  final raw = File(
    '${captureRoot.path}${Platform.pathSeparator}'
    '$androidNotificationRecoveryCompletionScenarioId.json',
  );
  if (childExit != 0) {
    return childExit == 78
        ? _blocked(
            'environment',
            'The fixed-wake source capture was environment-blocked; raw '
                'diagnostics remain at ${captureRoot.path}.',
          )
        : _failed(
            detail: 'The fixed-wake source capture exited $childExit.',
            assertionsAttempted: 1,
            artifactPresent: _regular(raw),
            childExitCode: childExit,
          );
  }
  final validation = validateAndroidNotificationRecoveryRawArtifact(
    artifactFile: raw,
    expectedPhysicalDeviceId: physical,
    expectedEmulatorDeviceId: emulator,
    expectedApkSha256: preparedSha,
    expectedPackageName: packageName,
  );
  if (!validation.ok) {
    return _failed(
      detail: 'Raw fixed-wake artifact rejected: ${validation.detail}',
      assertionsAttempted:
          androidNotificationRecoveryCompletionAssertions.length,
      artifactPresent: _regular(raw),
    );
  }
  final provenance = File(
    '${captureRoot.path}${Platform.pathSeparator}'
    'candidate_build_provenance.json',
  );
  if (!_centralProvenance(provenance, preparedSha)) {
    return _failed(
      detail: 'Capture did not bind both roles to the fixed-cohort APK.',
      assertionsAttempted:
          androidNotificationRecoveryCompletionAssertions.length,
      artifactPresent: true,
    );
  }
  return _CaptureSuccess(artifact: raw, root: captureRoot);
}

Future<String?> _verifyLiveTargets({
  required String physical,
  required String emulator,
}) async {
  final devices = await Process.run('adb', const <String>['devices']);
  final listing = '${devices.stdout}';
  if (devices.exitCode != 0 ||
      !listing.contains('$physical\tdevice') ||
      !listing.contains('$emulator\tdevice')) {
    return 'One or both assigned Android targets are not live.';
  }
  final physicalQemu = await Process.run('adb', <String>[
    '-s',
    physical,
    'shell',
    'getprop',
    'ro.kernel.qemu',
  ]);
  final emulatorQemu = await Process.run('adb', <String>[
    '-s',
    emulator,
    'shell',
    'getprop',
    'ro.kernel.qemu',
  ]);
  if ('${physicalQemu.stdout}'.trim() == '1' ||
      '${emulatorQemu.stdout}'.trim() != '1') {
    return 'Assigned target kinds do not match physical/emulator roles.';
  }
  return null;
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
    throw StateError('Notification state is unreadable on $device.');
  }
  return extractActiveContentNotificationCards(
    '${result.stdout}',
    packageName: packageName,
  ).length;
}

String? _validateStaging(File file, {required bool requireFixture}) {
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map ||
        decoded['schema'] != 'mknoon.plan257.staging-prerequisites.v1' ||
        decoded['environment'] != 'staging' ||
        decoded['relayActive'] != true ||
        decoded['providerConfigured'] != true ||
        decoded['providerProbeSucceeded'] != true ||
        decoded['allowAppDataReset'] != true ||
        decoded['provider'] != 'fcm' ||
        (requireFixture &&
            (decoded['executionBoundary'] !=
                    'ephemeral_production_redis_fixture' ||
                decoded['pushTokenState'] != 'encrypted' ||
                decoded['wakeOutcomeLedger'] != 'redis'))) {
      return 'The staging manifest does not authorize fixed-wake FCM proof.';
    }
  } on Object {
    return 'The staging manifest is invalid JSON.';
  }
  return null;
}

Uri? _fixtureProbe(String? raw) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty) return null;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'http' ||
      uri.host.isEmpty ||
      uri.port <= 0 ||
      !RegExp(r'^/[0-9a-f]{64}$').hasMatch(uri.path) ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri;
}

Future<bool> _fixtureReady(Uri probe) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final uri = probe.replace(
      queryParameters: const <String, String>{
        'kind': 'plan393_relay_snapshot',
        'sinceUnixMs': '0',
      },
    );
    final request = await client
        .getUrl(uri)
        .timeout(const Duration(seconds: 5));
    final response = await request.close().timeout(const Duration(seconds: 5));
    final body = await utf8.decoder
        .bind(response)
        .join()
        .timeout(const Duration(seconds: 5));
    if (response.statusCode != HttpStatus.ok) return false;
    final decoded = jsonDecode(body);
    return decoded is Map &&
        decoded['schema'] == 'mknoon.plan393.relay-fixture-snapshot.v1' &&
        decoded['backend'] == 'redis' &&
        decoded['ephemeral'] == true &&
        decoded['pushTokenState'] == 'encrypted' &&
        decoded['wakeOutcomeAdmissionEnabled'] == true &&
        decoded['wakeOutcomeCoordinatorStarted'] == true &&
        decoded['directReactionPushEnabled'] == true &&
        decoded['realFcmConfigured'] == true &&
        RegExp(r'^[0-9a-f]{64}$').hasMatch('${decoded['relayBinarySha256']}');
  } on Object {
    return false;
  } finally {
    client.close(force: true);
  }
}

bool _centralProvenance(File file, String expectedSha) {
  if (!_regular(file)) return false;
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    return decoded is Map &&
        decoded['schema'] == 'mknoon.plan257.candidate-build.v1' &&
        decoded['buildMode'] == 'central_prebuilt' &&
        decoded['buildProfile'] ==
            androidNotificationRecoveryCompletionBuildProfile &&
        decoded['childBuildCount'] == 0 &&
        decoded['e2eApkSha256'] == expectedSha &&
        decoded['normalApkSha256'] == expectedSha &&
        decoded['senderApkSha256'] == expectedSha &&
        decoded['recipientApkSha256'] == expectedSha;
  } on Object {
    return false;
  }
}

Directory _proofDirectory(Map<String, String> environment) {
  final configured = environment['SIMS_PROOF_DIRECTORY']?.trim();
  return Directory(
    configured == null || configured.isEmpty
        ? 'build/sims/proofs/'
              '$androidNotificationRecoveryCompletionCapabilityId'
        : configured,
  ).absolute;
}

bool _usableServiceAccount(File file) {
  if (!_regular(file)) return false;
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    return decoded is Map &&
        decoded['type'] == 'service_account' &&
        '${decoded['project_id'] ?? ''}'.trim().isNotEmpty;
  } on Object {
    return false;
  }
}

bool _regular(File file) =>
    FileSystemEntity.typeSync(file.path, followLinks: true) ==
    FileSystemEntityType.file;

String _digest(File file) => sha256.convert(file.readAsBytesSync()).toString();

Future<void> main(List<String> args) async {
  if (args.contains('--list-criteria')) {
    for (final assertion in androidNotificationRecoveryCompletionAssertions) {
      stdout.writeln(assertion);
    }
    return;
  }
  if (args.contains('--probe-source-extension')) {
    stdout.writeln(
      jsonEncode(<String, Object?>{
        'scenario': androidNotificationRecoveryCompletionScenarioId,
        'captureDriver': _captureDriver,
        'buildProfile': androidNotificationRecoveryCompletionBuildProfile,
        'artifactEnvironment':
            androidNotificationRecoveryCompletionArtifactEnvironment,
        'physicalIdPinned': false,
        'emulatorIdPinned': false,
        'legacyMissingSourcesRequired': false,
      }),
    );
    return;
  }
  if (args.isNotEmpty) {
    stderr.writeln(
      'Usage: dart run integration_test/scripts/'
      'run_android_notification_recovery_completion.dart '
      '[--list-criteria|--probe-source-extension]',
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
      assertionsAttempted: 0,
      artifactPresent: false,
    );
  } catch (error, stackTrace) {
    stderr.writeln(stackTrace);
    result = _failed(
      detail:
          'Fixed-wake recovery adapter failed before verdict: '
          '${error.runtimeType}.',
      assertionsAttempted: 0,
      artifactPresent: false,
    );
  }
  stdout.writeln('SIMS_RESULT_JSON=${jsonEncode(result.json)}');
  exitCode = result.exitCode;
}
