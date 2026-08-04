#!/usr/bin/env dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../../tool/sims/artifact_evidence.dart';
import '../support/android_app_state_guard.dart';
import '_android_app_package.dart';
import 'android_notification_recovery_completion_criteria.dart';

const String _preparedArtifactEnvironment =
    'SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM';
const String _physicalEnvironment = 'SIMS_ANDROID_PHYSICAL_DEVICE_ID';
const String _emulatorEnvironment = 'SIMS_ANDROID_EMULATOR_DEVICE_ID';
const String _configFile = 'plan331_notification_recovery_config.json';
const String _receiptFile = 'plan331_notification_recovery_receipt.json';
const String _flowFile = 'plan331_notification_recovery_flow.log';
const String _debugAction =
    'com.mknoon.app.debug.NOTIFICATION_RECOVERY_COMPLETION';
const String _debugReceiverSource =
    'android/app/src/debug/kotlin/com/mknoon/app/'
    'NotificationRecoveryCompletionReceiver.kt';
const String _debugObserverSource =
    'lib/core/debug/android_notification_recovery_completion_e2e.dart';
const String _campaignDriverSource =
    'integration_test/scripts/'
    'android_notification_recovery_completion_campaign_driver.dart';
const Duration _receiptTimeout = Duration(minutes: 8);
const Duration _processPoll = Duration(milliseconds: 300);

final RegExp _safeTarget = RegExp(r'^[A-Za-z0-9._:-]{1,160}$');
final RegExp _safeRelayTarget = RegExp(r'^[A-Za-z0-9._-]+@[A-Za-z0-9.-]+$');

final class _AdapterResult {
  const _AdapterResult(this.json, this.exitCode);

  final Map<String, Object?> json;
  final int exitCode;
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

_AdapterResult _failed(String detail, {int assertionsAttempted = 1}) =>
    _AdapterResult(<String, Object?>{
      'status': 'FAIL',
      'assertionsAttempted': assertionsAttempted,
      'artifactPresent': false,
      'printOnly': false,
      'blocker': 'test',
      'exitCode': 1,
      'detail': detail,
    }, 1);

_AdapterResult _passed(
  SimsArtifactEvidence evidence,
) => _AdapterResult(<String, Object?>{
  'status': 'PASS',
  'assertionsAttempted': androidNotificationRecoveryCompletionAssertions.length,
  'artifactPresent': true,
  'printOnly': false,
  'exitCode': 0,
  'detail':
      'Plan-331 direct/group recovery, handoff, custody, synthetic identity, '
      'history/count, health, and locale rows passed in both pinned Android '
      'receiver roles with one prepared APK and no notification-card taps.',
  'artifactEvidence': evidence.toJson(),
}, 0);

final class _Credentials {
  const _Credentials({
    required this.serviceAccount,
    required this.relayAddresses,
    required this.relayTarget,
    required this.relayKey,
  });

  final File serviceAccount;
  final String relayAddresses;
  final String relayTarget;
  final File relayKey;
}

final class _Preflight {
  const _Preflight({
    required this.credentials,
    required this.preparedArtifact,
    required this.preparedArtifactSha256,
    required this.physicalDeviceId,
    required this.emulatorDeviceId,
    required this.packageName,
    required this.proofDirectory,
  });

  final _Credentials credentials;
  final File preparedArtifact;
  final String preparedArtifactSha256;
  final String physicalDeviceId;
  final String emulatorDeviceId;
  final String packageName;
  final Directory proofDirectory;
}

final class _Blocked implements Exception {
  const _Blocked(this.kind, this.detail);

  final String kind;
  final String detail;
}

final class _CampaignFailure implements Exception {
  const _CampaignFailure(this.detail, {this.assertionsAttempted = 1});

  final String detail;
  final int assertionsAttempted;
}

final class _RecoveryDriverSourceAudit {
  const _RecoveryDriverSourceAudit(this.missing);

  final List<String> missing;

  bool get ready => missing.isEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    'schema': 'mknoon.plan331.android-recovery-driver-preflight.v1',
    'status': ready ? 'READY' : 'BLOCKED',
    'blocker': ready ? null : 'missingDriver',
    'missing': missing,
  };
}

Future<_AdapterResult> _run(Map<String, String> environment) async {
  late final _Preflight preflight;
  try {
    preflight = await _preflight(environment);
  } on _Blocked catch (error) {
    return _blocked(error.kind, error.detail);
  }

  late final AndroidAppStateGuard stateGuard;
  try {
    stateGuard = await AndroidAppStateGuard.capture(
      devices: <String>[preflight.physicalDeviceId, preflight.emulatorDeviceId],
      packageName: preflight.packageName,
      backupLabel: 'notification-recovery-completion-331',
      preparedArtifact: preflight.preparedArtifact,
      expectedArtifactSha256: preflight.preparedArtifactSha256,
    );
  } on AndroidAppStateBlocked catch (error) {
    return _blocked('environment', error.detail);
  } on AndroidAppStateFailure catch (error) {
    return _failed(error.detail);
  }

  late final _AdapterResult result;
  try {
    await stateGuard.prepareFreshInstalls(preflight.preparedArtifact);
    final campaign = _RecoveryCampaign(preflight);
    result = _passed(await campaign.run());
  } on _Blocked catch (error) {
    result = _blocked(error.kind, error.detail);
  } on _CampaignFailure catch (error) {
    result = _failed(
      error.detail,
      assertionsAttempted: error.assertionsAttempted,
    );
  } on Object catch (error) {
    result = _failed(
      'The Plan-331 campaign failed closed before semantic validation '
      '(${error.runtimeType}).',
    );
  }
  try {
    await stateGuard.restoreAll();
  } on Object {
    return _failed(
      'Exact Android package/private-state restoration failed; campaign '
      'evidence is not accepted.',
      assertionsAttempted: result.json['assertionsAttempted'] as int? ?? 0,
    );
  }
  return result;
}

Future<_Preflight> _preflight(Map<String, String> environment) async {
  // Credentials intentionally come first: a release invocation without live
  // relay/FCM authority must stop here without touching either Android target
  // or printing a secret/path/value.
  final credentialPath =
      environment['SIMS_PROVIDER_FCM_CREDENTIAL_PATH']?.trim().isNotEmpty ==
          true
      ? environment['SIMS_PROVIDER_FCM_CREDENTIAL_PATH']!.trim()
      : environment['FIREBASE_SERVICE_ACCOUNT']?.trim() ?? '';
  final relayAddresses = environment['MKNOON_RELAY_ADDRESSES']?.trim() ?? '';
  final relayTarget =
      environment['SIMS_NOTIFICATION_RELAY_TARGET']?.trim().isNotEmpty == true
      ? environment['SIMS_NOTIFICATION_RELAY_TARGET']!.trim()
      : environment['MKNOON_257_RELAY_TARGET']?.trim().isNotEmpty == true
      ? environment['MKNOON_257_RELAY_TARGET']!.trim()
      : environment['MKNOON_RELAY_TARGET']?.trim() ?? '';
  final relayKeyPath =
      environment['SIMS_NOTIFICATION_RELAY_KEY']?.trim().isNotEmpty == true
      ? environment['SIMS_NOTIFICATION_RELAY_KEY']!.trim()
      : environment['MKNOON_257_RELAY_KEY']?.trim().isNotEmpty == true
      ? environment['MKNOON_257_RELAY_KEY']!.trim()
      : environment['MKNOON_RELAY_KEY']?.trim() ?? '';
  final serviceAccount = File(credentialPath).absolute;
  final relayKey = File(relayKeyPath).absolute;
  if (!_usableServiceAccount(serviceAccount) ||
      relayAddresses.isEmpty ||
      relayAddresses.contains(RegExp(r'[\r\n]')) ||
      !_safeRelayTarget.hasMatch(relayTarget) ||
      !_isRegularFile(relayKey)) {
    throw const _Blocked(
      'credentials',
      'Live staging-relay addresses/SSH authority and a readable FCM '
          'service-account JSON are required. Credential values are redacted.',
    );
  }
  final credentials = _Credentials(
    serviceAccount: serviceAccount,
    relayAddresses: relayAddresses,
    relayTarget: relayTarget,
    relayKey: relayKey,
  );

  final driverAudit = _auditRecoveryDriverSource();
  if (!driverAudit.ready) {
    throw _Blocked(
      'missingDriver',
      'The repository does not yet provide the debug-only Plan-331 recovery '
          'action/receipt producer. Missing contract seams: '
          '${driverAudit.missing.join(', ')}. The registered campaign remains '
          'fail-closed and cannot infer success from host-generated files.',
    );
  }

  final artifactPath = environment[_preparedArtifactEnvironment]?.trim() ?? '';
  final preparedArtifact = File(artifactPath).absolute;
  if (!_isRegularFile(preparedArtifact) || preparedArtifact.lengthSync() <= 0) {
    throw const _Blocked(
      'missingArtifact',
      'A centrally prepared android.production_fcm APK is required; this '
          'runner never starts a child build.',
    );
  }
  final profile = environment['SIMS_ARTIFACT_PROFILE_ID']?.trim();
  if (profile != null &&
      profile.isNotEmpty &&
      profile != 'android.production_fcm') {
    throw const _Blocked(
      'missingArtifact',
      'The prepared artifact is not owned by android.production_fcm.',
    );
  }
  final preparedSha = sha256
      .convert(preparedArtifact.readAsBytesSync())
      .toString();

  final physical = environment[_physicalEnvironment]?.trim() ?? '';
  final emulator = environment[_emulatorEnvironment]?.trim() ?? '';
  if (physical != plan331PhysicalAndroidDeviceId ||
      emulator != plan331AndroidEmulatorDeviceId ||
      !_safeTarget.hasMatch(physical) ||
      !_safeTarget.hasMatch(emulator) ||
      physical == emulator) {
    throw const _Blocked(
      'targetUnavailable',
      'The campaign requires the explicitly assigned USB Android '
          '$plan331PhysicalAndroidDeviceId and Android emulator '
          '$plan331AndroidEmulatorDeviceId.',
    );
  }
  final devices = await Process.run('adb', const <String>['devices']);
  final listing = '${devices.stdout}';
  if (devices.exitCode != 0 ||
      !listing.contains('$physical\tdevice') ||
      !listing.contains('$emulator\tdevice')) {
    throw const _Blocked(
      'deviceLost',
      'One or both explicitly assigned Android targets are not online.',
    );
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
    throw const _Blocked(
      'targetUnavailable',
      'The explicit Android IDs do not resolve to physical/emulator roles.',
    );
  }
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
    throw const _Blocked(
      'environment',
      'The credentialed staging relay is not reachable and active.',
    );
  }

  final configuredProof = environment['SIMS_PROOF_DIRECTORY']?.trim();
  final proofDirectory = Directory(
    configuredProof == null || configuredProof.isEmpty
        ? 'build/sims/proofs/'
              '$androidNotificationRecoveryCompletionCapabilityId'
        : configuredProof,
  ).absolute..createSync(recursive: true);
  return _Preflight(
    credentials: credentials,
    preparedArtifact: preparedArtifact,
    preparedArtifactSha256: preparedSha,
    physicalDeviceId: physical,
    emulatorDeviceId: emulator,
    packageName: resolveAndroidAppPackage(),
    proofDirectory: proofDirectory,
  );
}

final class _RecoveryCampaign {
  _RecoveryCampaign(this.preflight);

  final _Preflight preflight;
  final Random _random = Random.secure();
  final List<Map<String, Object?>> _commands = <Map<String, Object?>>[];
  String _phase = 'setup';

  Future<SimsArtifactEvidence> run() async {
    for (final device in <String>[
      preflight.physicalDeviceId,
      preflight.emulatorDeviceId,
    ]) {
      await _writeAppFile(
        device,
        'auto_setup.json',
        jsonEncode(<String, Object?>{
          'username': device == preflight.physicalDeviceId
              ? 'plan331-physical'
              : 'plan331-emulator',
        }),
      );
      await _adb(device, <String>[
        'shell',
        'pm',
        'grant',
        preflight.packageName,
        'android.permission.POST_NOTIFICATIONS',
      ], allowFailure: true);
      await _launch(device);
      await _waitForAppFile(
        device,
        'intro_e2e_identity.json',
        const Duration(minutes: 2),
      );
    }

    final captures = <Map<String, Object?>>[];
    for (final receiver in <String>[
      preflight.physicalDeviceId,
      preflight.emulatorDeviceId,
    ]) {
      final sender = receiver == preflight.physicalDeviceId
          ? preflight.emulatorDeviceId
          : preflight.physicalDeviceId;
      for (final scenarioId
          in androidNotificationRecoveryCompletionScenarioIds) {
        captures.add(
          await _runScenario(
            scenarioId: scenarioId,
            senderDeviceId: sender,
            receiverDeviceId: receiver,
          ),
        );
      }
    }

    final evidence = writeSimsArtifactEvidenceSync(
      directory: preflight.proofDirectory,
      capabilityId: androidNotificationRecoveryCompletionCapabilityId,
      validatorIds: const <String>[
        androidNotificationRecoveryCompletionValidator,
      ],
      payload: <String, Object?>{
        'campaignSchema': androidNotificationRecoveryCompletionCampaignSchema,
        'status': 'passed',
        'recordedAt': DateTime.now().toUtc().toIso8601String(),
        'buildProfile': 'android.production_fcm',
        'preparedArtifactSha256': preflight.preparedArtifactSha256,
        'packageName': preflight.packageName,
        'childBuildCount': 0,
        'manualTaps': 0,
        'notificationCardTaps': 0,
        'headlessActivityLaunchCount': 0,
        'forbiddenProcessStopCount': 0,
        'platforms': const <String>['android'],
        'physicalDeviceId': preflight.physicalDeviceId,
        'emulatorDeviceId': preflight.emulatorDeviceId,
        'scenarios': captures,
      },
    );
    final validation = validateAndroidNotificationRecoveryCompletionArtifact(
      artifactFile: File(evidence.path),
      expectedPhysicalDeviceId: preflight.physicalDeviceId,
      expectedEmulatorDeviceId: preflight.emulatorDeviceId,
      expectedApkSha256: preflight.preparedArtifactSha256,
      expectedPackageName: preflight.packageName,
    );
    if (!validation.ok) {
      throw _CampaignFailure(
        'Strict Plan-331 artifact validation rejected the capture: '
        '${validation.detail}',
        assertionsAttempted:
            androidNotificationRecoveryCompletionAssertions.length,
      );
    }
    final audit = auditSimsArtifactEvidence(
      evidence: evidence,
      expectedValidatorIds: const <String>[
        androidNotificationRecoveryCompletionValidator,
      ],
    );
    if (!audit.isValid) {
      throw _CampaignFailure(
        'Content-addressed Sims evidence audit failed: ${audit.detail}',
        assertionsAttempted:
            androidNotificationRecoveryCompletionAssertions.length,
      );
    }
    return evidence;
  }

  Future<Map<String, Object?>> _runScenario({
    required String scenarioId,
    required String senderDeviceId,
    required String receiverDeviceId,
  }) async {
    _commands.clear();
    _phase = 'setup';
    final runId = _token('plan331-$scenarioId');
    final nonce = _token('nonce');
    final startedAt = DateTime.now().toUtc();
    final config = <String, Object?>{
      'schema': 'mknoon.plan331.android-notification-recovery-request.v1',
      'transport_action': 'notification_recovery_completion',
      'scenarioId': scenarioId,
      'runId': runId,
      'nonce': nonce,
      'senderDeviceId': senderDeviceId,
      'receiverDeviceId': receiverDeviceId,
      'relayAddresses': preflight.credentials.relayAddresses,
      'syntheticTransportMutation': scenarioId == 'synthetic_outer_id_removal',
      'manualTapsAllowed': false,
      'notificationCardTapsAllowed': false,
      'childBuildsAllowed': false,
    };
    await _removeAppFile(receiverDeviceId, _receiptFile);
    await _removeAppFile(receiverDeviceId, _flowFile);
    await _writeAppFile(receiverDeviceId, _configFile, jsonEncode(config));
    await _writeAppFile(senderDeviceId, _configFile, jsonEncode(config));

    // Setup may launch both roles. The headless proof window starts only after
    // the receiver is backgrounded and the process is observed absent.
    await _launch(senderDeviceId);
    await _launch(receiverDeviceId);
    await _terminateWithoutUserStop(receiverDeviceId);

    _phase = 'headless';
    await _adb(receiverDeviceId, <String>[
      'shell',
      'am',
      'broadcast',
      '-a',
      _debugAction,
      '-p',
      preflight.packageName,
      '--es',
      'scenarioId',
      scenarioId,
      '--es',
      'runId',
      runId,
      '--es',
      'nonce',
      nonce,
    ]);
    final receipt = await _waitForAppFile(
      receiverDeviceId,
      _receiptFile,
      _receiptTimeout,
    );
    _validateBoundReceipt(
      receipt,
      scenarioId: scenarioId,
      runId: runId,
      nonce: nonce,
      senderDeviceId: senderDeviceId,
      receiverDeviceId: receiverDeviceId,
    );
    final flow = await _waitForAppFile(
      receiverDeviceId,
      _flowFile,
      const Duration(seconds: 30),
    );

    _phase = 'capture';
    final notificationDump = await _shellText(receiverDeviceId, const <String>[
      'dumpsys',
      'notification',
      '--noredact',
    ]);
    final activityDump = await _shellText(receiverDeviceId, const <String>[
      'dumpsys',
      'activity',
      'activities',
    ]);
    final relayJournal = await _relayJournalSince(startedAt);

    final stem = '${receiverDeviceId.replaceAll(':', '_')}-$scenarioId-$runId';
    final evidence = <String, Object?>{
      'receipt': _writeEvidence('$stem-receipt.json', receipt),
      'flowLog': _writeEvidence('$stem-flow.log', flow),
      'notificationDump': _writeEvidence(
        '$stem-notification.txt',
        notificationDump,
      ),
      'activityDump': _writeEvidence('$stem-activity.txt', activityDump),
      'relayJournal': _writeEvidence('$stem-relay.log', relayJournal),
    };
    if (scenarioId == 'localized_recovery_copy') {
      for (final locale in const <String>['en', 'de', 'ar', 'fallback']) {
        final localeDump = await _captureLocale(
          receiverDeviceId: receiverDeviceId,
          locale: locale,
          scenarioId: scenarioId,
          runId: runId,
          nonce: nonce,
        );
        evidence['locale${locale == 'fallback' ? 'Fallback' : locale[0].toUpperCase() + locale.substring(1)}Dump'] =
            _writeEvidence('$stem-locale-$locale.txt', localeDump);
      }
    }
    evidence['commandJournal'] = _writeEvidence(
      '$stem-commands.json',
      jsonEncode(<String, Object?>{
        'schema': androidNotificationRecoveryCompletionCommandSchema,
        'scenarioId': scenarioId,
        'runId': runId,
        'nonce': nonce,
        'commands': List<Map<String, Object?>>.from(_commands),
      }),
    );
    return <String, Object?>{
      'id': scenarioId,
      'mode': scenarioId == 'synthetic_outer_id_removal'
          ? 'test_only_transport_mutation'
          : 'real_relay',
      'receiverDeviceId': receiverDeviceId,
      'senderDeviceId': senderDeviceId,
      'evidence': evidence,
    };
  }

  Future<void> _terminateWithoutUserStop(String device) async {
    _phase = 'termination';
    await _adb(device, const <String>[
      'shell',
      'input',
      'keyevent',
      'KEYCODE_HOME',
    ]);
    await _adb(device, <String>[
      'shell',
      'am',
      'kill',
      preflight.packageName,
    ], allowFailure: true);
    if (!await _pidAbsentWithin(device, const Duration(seconds: 5))) {
      await _adb(device, <String>[
        'shell',
        'cmd',
        'activity',
        'stop-app',
        preflight.packageName,
      ]);
    }
    if (!await _pidAbsentWithin(device, const Duration(seconds: 20))) {
      throw const _CampaignFailure(
        'The receiver process remained alive after bounded background '
        'termination; the headless row was not attempted.',
      );
    }
  }

  Future<bool> _pidAbsentWithin(String device, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    do {
      final result = await _adb(device, <String>[
        'shell',
        'pidof',
        preflight.packageName,
      ], allowFailure: true);
      if ('${result.stdout}'.trim().isEmpty) return true;
      await Future<void>.delayed(_processPoll);
    } while (DateTime.now().isBefore(deadline));
    return false;
  }

  Future<String> _captureLocale({
    required String receiverDeviceId,
    required String locale,
    required String scenarioId,
    required String runId,
    required String nonce,
  }) async {
    final readiness = 'plan331_locale_$locale.ready';
    await _removeAppFile(receiverDeviceId, readiness);
    await _adb(receiverDeviceId, <String>[
      'shell',
      'am',
      'broadcast',
      '-a',
      _debugAction,
      '-p',
      preflight.packageName,
      '--es',
      'scenarioId',
      scenarioId,
      '--es',
      'runId',
      runId,
      '--es',
      'nonce',
      nonce,
      '--es',
      'locale',
      locale,
    ]);
    final readyReceipt = await _waitForAppFile(
      receiverDeviceId,
      readiness,
      const Duration(seconds: 45),
    );
    _validateLocaleReadiness(
      readyReceipt,
      locale: locale,
      scenarioId: scenarioId,
      runId: runId,
      nonce: nonce,
    );
    final dump = await _shellText(receiverDeviceId, const <String>[
      'dumpsys',
      'notification',
      '--noredact',
    ]);
    await _removeAppFile(receiverDeviceId, readiness);
    return dump;
  }

  Map<String, Object?> _writeEvidence(String name, String contents) {
    final safeName = name.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    final file = File(
      '${preflight.proofDirectory.path}${Platform.pathSeparator}$safeName',
    );
    file.writeAsStringSync(
      contents.endsWith('\n') ? contents : '$contents\n',
      flush: true,
    );
    final bytes = file.readAsBytesSync();
    return <String, Object?>{
      'path': safeName,
      'sha256': sha256.convert(bytes).toString(),
      'bytes': bytes.length,
    };
  }

  Future<String> _relayJournalSince(DateTime since) async {
    final result = await Process.run('ssh', <String>[
      '-o',
      'BatchMode=yes',
      '-o',
      'ConnectTimeout=15',
      '-i',
      preflight.credentials.relayKey.path,
      preflight.credentials.relayTarget,
      'journalctl -u relay-server --since '
          '@${since.millisecondsSinceEpoch ~/ 1000} --no-pager -o cat',
    ]);
    if (result.exitCode != 0) {
      throw const _CampaignFailure(
        'The staging relay journal could not be captured.',
      );
    }
    return '${result.stdout}';
  }

  Future<void> _launch(String device) async {
    final result = await _adb(device, <String>[
      'shell',
      'am',
      'start',
      '-W',
      '-n',
      '${preflight.packageName}/.MainActivity',
    ], allowFailure: true);
    if (result.exitCode != 0 ||
        !RegExp(
          r'^Status:[ \t]+ok',
          multiLine: true,
        ).hasMatch('${result.stdout}')) {
      throw const _CampaignFailure('The prepared Android app did not launch.');
    }
  }

  Future<String> _waitForAppFile(
    String device,
    String name,
    Duration timeout,
  ) async {
    final deadline = DateTime.now().add(timeout);
    do {
      final result = await _adb(device, <String>[
        'shell',
        'run-as',
        preflight.packageName,
        'cat',
        'app_flutter/$name',
      ], allowFailure: true);
      final value = '${result.stdout}'.trim();
      if (result.exitCode == 0 && value.isNotEmpty) return value;
      await Future<void>.delayed(_processPoll);
    } while (DateTime.now().isBefore(deadline));
    throw _CampaignFailure(
      'The prepared APK did not emit the nonce-bound $name evidence. No '
      'scenario success was inferred.',
    );
  }

  Future<void> _writeAppFile(String device, String name, String value) async {
    final local = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'plan331-${_token('file')}-$name',
    );
    final remote = '/data/local/tmp/plan331-${_token('remote')}-$name';
    local.writeAsStringSync(value, flush: true);
    try {
      await _adb(device, <String>['push', local.path, remote]);
      await _adb(device, <String>[
        'shell',
        'run-as',
        preflight.packageName,
        'mkdir',
        '-p',
        'app_flutter',
      ]);
      await _adb(device, <String>[
        'shell',
        'run-as',
        preflight.packageName,
        'cp',
        remote,
        'app_flutter/$name',
      ]);
    } finally {
      if (local.existsSync()) local.deleteSync();
      await _adb(device, <String>[
        'shell',
        'rm',
        '-f',
        remote,
      ], allowFailure: true);
    }
  }

  Future<void> _removeAppFile(String device, String name) =>
      _adb(device, <String>[
        'shell',
        'run-as',
        preflight.packageName,
        'rm',
        '-f',
        'app_flutter/$name',
      ], allowFailure: true).then((_) {});

  Future<String> _shellText(String device, List<String> command) async =>
      '${(await _adb(device, <String>['shell', ...command])).stdout}';

  Future<ProcessResult> _adb(
    String device,
    List<String> arguments, {
    bool allowFailure = false,
  }) async {
    final capturedAt = DateTime.now().toUtc().toIso8601String();
    final result = await Process.run('adb', <String>[
      '-s',
      device,
      ...arguments,
    ]);
    _commands.add(<String, Object?>{
      'phase': _phase,
      'device': device,
      'args': arguments,
      'exitCode': result.exitCode,
      'stdoutEmpty': '${result.stdout}'.trim().isEmpty,
      'capturedAt': capturedAt,
    });
    if (!allowFailure && result.exitCode != 0) {
      throw _CampaignFailure(
        'An ADB command failed during $_phase; command output is retained only '
        'in the Sims execution log.',
      );
    }
    return result;
  }

  String _token(String prefix) {
    final bytes = List<int>.generate(12, (_) => _random.nextInt(256));
    return '$prefix-${base64Url.encode(bytes).replaceAll('=', '')}';
  }
}

bool _usableServiceAccount(File file) {
  if (!_isRegularFile(file)) return false;
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    return decoded is Map &&
        '${decoded['project_id'] ?? ''}'.trim().isNotEmpty &&
        '${decoded['client_email'] ?? ''}'.trim().isNotEmpty &&
        '${decoded['private_key'] ?? ''}'.contains('PRIVATE KEY');
  } on Object {
    return false;
  }
}

_RecoveryDriverSourceAudit _auditRecoveryDriverSource() {
  final receiver = _readSource(_debugReceiverSource);
  final observer = _readSource(_debugObserverSource);
  final campaignDriver = _readSource(_campaignDriverSource);
  final producer = '${receiver ?? ''}\n${observer ?? ''}';
  final debugManifest = _readSource(
    'android/app/src/debug/AndroidManifest.xml',
  );
  final mainManifest = _readSource('android/app/src/main/AndroidManifest.xml');
  final mainDart = _readSource('lib/main.dart');
  final worker = _readSource(
    'android/app/src/main/kotlin/com/mknoon/app/'
    'HeadlessCanonicalRecoveryWorker.kt',
  );
  final simsManifest = _readSource('tool/sims/critical_features.json');
  final missing = <String>[];

  void require(String id, bool condition) {
    if (!condition) missing.add(id);
  }

  require(
    'debug_receiver_manifest',
    debugManifest?.contains('.NotificationRecoveryCompletionReceiver') ==
            true &&
        debugManifest?.contains(_debugAction) == true &&
        debugManifest?.contains(
              'android:permission="android.permission.DUMP"',
            ) ==
            true,
  );
  require(
    'debug_receiver_nonce_config_binding',
    receiver?.contains('class NotificationRecoveryCompletionReceiver') ==
            true &&
        receiver?.contains(_debugAction) == true &&
        receiver?.contains(_configFile) == true &&
        receiver?.contains('scenarioId') == true &&
        receiver?.contains('runId') == true &&
        receiver?.contains('nonce') == true,
  );
  require(
    'production_worker_activation',
    receiver?.contains('DroppedPushRecoveryStore') == true &&
        receiver?.contains('recoveryWorkEnabled = true') == true &&
        receiver?.contains('DroppedPushRecoveryWorkScheduler') == true &&
        receiver?.contains('onBindingRotated') == true &&
        receiver?.contains('recordDeletion') == true &&
        receiver?.contains('enqueueDeletedBatch') == true,
  );
  require(
    'observed_worker_completion',
    receiver?.contains('WorkManager') == true &&
        receiver?.contains('WorkInfo.State.SUCCEEDED') == true &&
        receiver?.contains('pendingRecovery') == true,
  );
  require(
    'observed_notification_state',
    receiver?.contains('NotificationManager') == true &&
        receiver?.contains('activeNotifications') == true,
  );
  require(
    'headless_dart_entrypoint',
    worker?.contains('androidHeadlessCanonicalRecoveryMain') == true &&
        mainDart?.contains(
              'Future<void> androidHeadlessCanonicalRecoveryMain',
            ) ==
            true,
  );
  require(
    'read_only_sqlcipher_observer',
    observer?.contains(
              'mknoon.plan331.android-notification-recovery-request.v1',
            ) ==
            true &&
        observer?.contains(
              'mknoon.plan331.android-notification-recovery-receipt.v1',
            ) ==
            true &&
        observer?.contains('openEncryptedDatabaseReadOnlyTolerant') == true &&
        observer?.contains('direct_notification_display_outbox') == true &&
        observer?.contains('group_notification_display_outbox') == true,
  );
  require(
    'atomic_observation_receipt',
    producer.contains(_receiptFile) &&
        producer.contains('writeAsString') &&
        producer.contains('.tmp') &&
        producer.contains('rename') &&
        producer.contains(_flowFile),
  );
  require(
    'paired_sender_identity_choreography',
    campaignDriver?.contains('intro_e2e_identity.json') == true &&
        campaignDriver?.contains('intro_e2e_config.json') == true &&
        campaignDriver?.contains('establishContacts') == true &&
        campaignDriver?.contains('sendRecoveryFixtures') == true &&
        campaignDriver?.contains('sentEventIds') == true,
  );
  require(
    'debug_only_release_exclusion',
    mainManifest?.contains(_debugAction) == false &&
        mainManifest?.contains('NotificationRecoveryCompletionReceiver') ==
            false,
  );
  require(
    'sims_automation_enabled',
    _simsCapabilityAutomationReady(simsManifest),
  );
  return _RecoveryDriverSourceAudit(List<String>.unmodifiable(missing));
}

String? _readSource(String path) {
  final file = File(path);
  if (!_isRegularFile(file)) return null;
  try {
    return file.readAsStringSync();
  } on Object {
    return null;
  }
}

bool _simsCapabilityAutomationReady(String? encoded) {
  if (encoded == null) return false;
  try {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map || decoded['capabilities'] is! List) return false;
    for (final raw in decoded['capabilities'] as List) {
      if (raw is Map &&
          raw['id'] == androidNotificationRecoveryCompletionCapabilityId) {
        return raw['automationReady'] == true;
      }
    }
  } on Object {
    return false;
  }
  return false;
}

void _validateBoundReceipt(
  String encoded, {
  required String scenarioId,
  required String runId,
  required String nonce,
  required String senderDeviceId,
  required String receiverDeviceId,
}) {
  try {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map ||
        decoded['schema'] !=
            androidNotificationRecoveryCompletionReceiptSchema ||
        decoded['scenarioId'] != scenarioId ||
        decoded['runId'] != runId ||
        decoded['nonce'] != nonce ||
        decoded['senderDeviceId'] != senderDeviceId ||
        decoded['receiverDeviceId'] != receiverDeviceId ||
        decoded['status'] != 'passed' ||
        decoded['facts'] is! Map) {
      throw const FormatException();
    }
  } on Object {
    throw const _CampaignFailure(
      'The installed debug producer returned a stale, malformed, or '
      'unbound recovery receipt. No scenario facts were accepted.',
    );
  }
}

void _validateLocaleReadiness(
  String encoded, {
  required String locale,
  required String scenarioId,
  required String runId,
  required String nonce,
}) {
  try {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map ||
        decoded['schema'] !=
            'mknoon.plan331.android-notification-locale-ready.v1' ||
        decoded['locale'] != locale ||
        decoded['scenarioId'] != scenarioId ||
        decoded['runId'] != runId ||
        decoded['nonce'] != nonce ||
        decoded['notificationObserved'] != true) {
      throw const FormatException();
    }
  } on Object {
    throw const _CampaignFailure(
      'The installed debug producer returned a stale, malformed, or '
      'unbound locale readiness receipt.',
    );
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
  if (args.length == 1 && args.single == '--driver-preflight') {
    final audit = _auditRecoveryDriverSource();
    stdout.writeln('DRIVER_PREFLIGHT_JSON=${jsonEncode(audit.toJson())}');
    exitCode = audit.ready ? 0 : 78;
    return;
  }
  if (args.contains('--list-scenarios')) {
    for (final scenario in androidNotificationRecoveryCompletionScenarioIds) {
      stdout.writeln(scenario);
    }
    return;
  }
  if (args.contains('--list-criteria')) {
    for (final criterion in androidNotificationRecoveryCompletionAssertions) {
      stdout.writeln(criterion);
    }
    return;
  }
  final validationPath = _valueFor(args, '--validate-artifact');
  if (validationPath != null) {
    final validation = validateAndroidNotificationRecoveryCompletionArtifact(
      artifactFile: File(validationPath),
    );
    if (!validation.ok) {
      stderr.writeln('INVALID: ${validation.detail}');
      exitCode = 65;
      return;
    }
    stdout.writeln('VALID: Plan-331 Android recovery artifact accepted.');
    return;
  }
  if (args.isNotEmpty) {
    stderr.writeln(
      'Usage: dart run integration_test/scripts/'
      'run_android_notification_recovery_completion.dart '
      '[--driver-preflight | --list-scenarios | --list-criteria | '
      '--validate-artifact <json>]',
    );
    exitCode = 64;
    return;
  }

  final result = await _run(Platform.environment);
  stdout.writeln('SIMS_RESULT_JSON=${jsonEncode(result.json)}');
  exitCode = result.exitCode;
}
