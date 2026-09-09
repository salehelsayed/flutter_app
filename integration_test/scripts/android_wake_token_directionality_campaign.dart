import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/debug/wake_token_directionality_e2e_protocol.dart';

import '../../tool/sims/artifact_evidence.dart';
import '../../tool/sims/device_criteria.dart';
import '../support/android_app_state_guard.dart';
import '_android_app_package.dart';

const int androidWakeTokenDirectionalityAssertionCount = 2;
const String androidWakeTokenArtifactValidatorId = 'validateWakeTokenArtifact';

/// Typed result consumed by the universal Sims runner.
final class AndroidWakeTokenDirectionalityCampaignResult {
  const AndroidWakeTokenDirectionalityCampaignResult._({
    required this.processExitCode,
    required this.json,
  });

  factory AndroidWakeTokenDirectionalityCampaignResult.pass(
    SimsArtifactEvidence evidence,
  ) => AndroidWakeTokenDirectionalityCampaignResult._(
    processExitCode: 0,
    json: <String, Object?>{
      'status': 'PASS',
      'assertionsAttempted': androidWakeTokenDirectionalityAssertionCount,
      'artifactPresent': true,
      'printOnly': false,
      'exitCode': 0,
      'detail':
          'One centrally prepared wake-token APK proved that the real relay '
          'registered value, receiver store value, and accepted inbox-store '
          'attachment have the same SHA-256 digest.',
      'artifactEvidence': evidence.toJson(),
    },
  );

  factory AndroidWakeTokenDirectionalityCampaignResult.blocked({
    required String blocker,
    required String detail,
    required bool artifactPresent,
  }) => AndroidWakeTokenDirectionalityCampaignResult._(
    processExitCode: 78,
    json: <String, Object?>{
      'status': 'BLOCKED',
      'assertionsAttempted': 0,
      'artifactPresent': artifactPresent,
      'printOnly': false,
      'blocker': blocker,
      'exitCode': 78,
      'detail': detail,
    },
  );

  factory AndroidWakeTokenDirectionalityCampaignResult.fail({
    required String blocker,
    required String detail,
    required bool artifactPresent,
    int assertionsAttempted = 0,
  }) => AndroidWakeTokenDirectionalityCampaignResult._(
    processExitCode: 1,
    json: <String, Object?>{
      'status': 'FAIL',
      'assertionsAttempted': assertionsAttempted,
      'artifactPresent': artifactPresent,
      'printOnly': false,
      'blocker': blocker,
      'exitCode': 1,
      'detail': detail,
    },
  );

  int get exitCode => processExitCode;

  final int processExitCode;
  final Map<String, Object?> json;
}

/// Runs the Android physical/emulator directionality proof. The campaign never
/// invokes Flutter: both peers install the exact same centrally cached APK.
Future<AndroidWakeTokenDirectionalityCampaignResult>
runAndroidWakeTokenDirectionalityCampaign({
  required List<String> devices,
  required String? artifactPath,
  Map<String, String>? environment,
}) async {
  final env = environment ?? Platform.environment;
  if (artifactPath == null ||
      artifactPath.trim().isEmpty ||
      !File(artifactPath).isFileSync()) {
    return AndroidWakeTokenDirectionalityCampaignResult.blocked(
      blocker: 'missingArtifact',
      detail:
          'A readable centrally cached $wakeTokenDirectionalityProfileId APK '
          'is required; this campaign never builds an application.',
      artifactPresent: false,
    );
  }
  final configuredProfile = env['SIMS_ARTIFACT_PROFILE_ID']?.trim();
  if (configuredProfile != null &&
      configuredProfile.isNotEmpty &&
      configuredProfile != wakeTokenDirectionalityProfileId) {
    return AndroidWakeTokenDirectionalityCampaignResult.blocked(
      blocker: 'missingArtifact',
      detail:
          'Wake-token directionality requires '
          '$wakeTokenDirectionalityProfileId; the executor supplied '
          '$configuredProfile.',
      artifactPresent: true,
    );
  }
  if (devices.length != 2 ||
      devices.first.isEmpty ||
      devices.last.isEmpty ||
      devices.first == devices.last) {
    return AndroidWakeTokenDirectionalityCampaignResult.blocked(
      blocker: 'targetUnavailable',
      detail:
          'Wake-token directionality requires two distinct explicit targets '
          'ordered as one USB physical Android and one Android emulator.',
      artifactPresent: true,
    );
  }

  final artifact = File(artifactPath).absolute;
  late final String artifactSha256;
  try {
    artifactSha256 = sha256.convert(await artifact.readAsBytes()).toString();
  } on FileSystemException catch (error) {
    return AndroidWakeTokenDirectionalityCampaignResult.blocked(
      blocker: 'missingArtifact',
      detail: 'The prepared APK could not be read: ${error.message}',
      artifactPresent: false,
    );
  }

  late final _AndroidWakeTokenHost host;
  try {
    host = _AndroidWakeTokenHost(
      physicalDeviceId: devices.first,
      emulatorDeviceId: devices.last,
      artifact: artifact,
      artifactSha256: artifactSha256,
      packageName: resolveAndroidAppPackage(),
      proofDirectory: _proofDirectory(env),
    );
    await host.verifyPrerequisites();
  } on _WakeBlocked catch (blocked) {
    return AndroidWakeTokenDirectionalityCampaignResult.blocked(
      blocker: blocked.blocker,
      detail: blocked.detail,
      artifactPresent: true,
    );
  } on Object catch (error) {
    return AndroidWakeTokenDirectionalityCampaignResult.blocked(
      blocker: 'environment',
      detail: 'Wake-token prerequisite validation failed: $error',
      artifactPresent: true,
    );
  }

  try {
    return AndroidWakeTokenDirectionalityCampaignResult.pass(await host.run());
  } on _WakeBlocked catch (blocked) {
    return AndroidWakeTokenDirectionalityCampaignResult.blocked(
      blocker: blocked.blocker,
      detail: blocked.detail,
      artifactPresent: true,
    );
  } on _WakeFailure catch (failure) {
    return AndroidWakeTokenDirectionalityCampaignResult.fail(
      blocker: failure.blocker,
      detail: failure.detail,
      artifactPresent: false,
      assertionsAttempted: failure.assertionsAttempted,
    );
  } on Object catch (error, stackTrace) {
    return AndroidWakeTokenDirectionalityCampaignResult.fail(
      blocker: 'harness',
      detail: 'Wake-token campaign failed unexpectedly: $error\n$stackTrace',
      artifactPresent: false,
    );
  }
}

/// Binds two independently produced endpoint receipts and rejects any raw
/// secret before building the small validator payload.
Map<String, Object?> aggregateAndroidWakeTokenDirectionalityEvidence({
  required Map<String, Object?> issuerEndpoint,
  required Map<String, Object?> presenterEndpoint,
  required String runId,
  required String issuerNonce,
  required String presenterNonce,
  required String artifactSha256,
  required String physicalDeviceId,
  required String emulatorDeviceId,
}) {
  _validateWakeEndpoint(
    issuerEndpoint,
    role: wakeTokenIssuerRole,
    stepId: wakeTokenIssuerStepId(runId),
    runId: runId,
    nonce: issuerNonce,
  );
  _validateWakeEndpoint(
    presenterEndpoint,
    role: wakeTokenPresenterRole,
    stepId: wakeTokenPresenterStepId(runId),
    runId: runId,
    nonce: presenterNonce,
  );
  _rejectSecretBearingFields(issuerEndpoint);
  _rejectSecretBearingFields(presenterEndpoint);

  final registered = issuerEndpoint['registeredTokenSha256'];
  final stored = presenterEndpoint['storedTokenSha256'];
  final attached = presenterEndpoint['attachedTokenSha256'];
  final hashPattern = RegExp(r'^[0-9a-f]{64}$');
  if (registered is! String ||
      stored is! String ||
      attached is! String ||
      !hashPattern.hasMatch(registered) ||
      !hashPattern.hasMatch(stored) ||
      !hashPattern.hasMatch(attached) ||
      issuerEndpoint['registerRelayAccepted'] != true ||
      issuerEndpoint['registeredMemberCount'] != 1 ||
      presenterEndpoint['receivedStorePersisted'] != true ||
      presenterEndpoint['inboxStoreAccepted'] != true ||
      !const <String>{
        'stored',
        'duplicate',
      }.contains(presenterEndpoint['inboxStoreStatus'])) {
    throw const FormatException(
      'wake-token endpoint observations are incomplete',
    );
  }
  if (registered != stored || stored != attached) {
    throw const FormatException(
      'registered, stored, and attached wake-token hashes differ',
    );
  }

  final proof = <String, Object?>{
    'schema': wakeTokenDurableEvidenceSchema,
    'scenario': wakeTokenDirectionalityScenarioId,
    'status': 'passed',
    'platform': 'android',
    'runtimeDispatched': true,
    'runId': runId,
    'registeredTokenSha256': registered,
    'storedTokenSha256': stored,
    'attachedTokenSha256': attached,
    'deviceIds': <String>[physicalDeviceId, emulatorDeviceId],
    'targetKinds': const <String, Object?>{
      'issuer': 'physical',
      'presenter': 'emulator',
    },
    'sharedArtifact': <String, Object?>{
      'profileId': wakeTokenDirectionalityProfileId,
      'sha256': artifactSha256,
    },
    'relayRegistrationAccepted': true,
    'receiverStorePersisted': true,
    'acceptedInboxStoreAttachmentObserved': true,
    'childFlutterBuilds': 0,
    'assertionsAttempted': androidWakeTokenDirectionalityAssertionCount,
  };
  final validation = validateWakeTokenArtifact(proof);
  if (!validation.ok) throw FormatException(validation.detail);
  return Map<String, Object?>.unmodifiable(proof);
}

final class _AndroidWakeTokenHost {
  _AndroidWakeTokenHost({
    required this.physicalDeviceId,
    required this.emulatorDeviceId,
    required this.artifact,
    required this.artifactSha256,
    required this.packageName,
    required this.proofDirectory,
  });

  final String physicalDeviceId;
  final String emulatorDeviceId;
  final File artifact;
  final String artifactSha256;
  final String packageName;
  final Directory proofDirectory;
  final _random = Random.secure();

  bool _mutated = false;

  Future<void> verifyPrerequisites() async {
    final version = await _process('adb', const <String>[
      'version',
    ], mutate: false);
    if (version.exitCode != 0) {
      throw const _WakeBlocked('missingDriver', 'adb version failed');
    }
    final listed = await _process('adb', const <String>[
      'devices',
      '-l',
    ], mutate: false);
    final states = <String, String>{};
    for (final line in '${listed.stdout}'.split('\n')) {
      final fields = line.trim().split(RegExp(r'\s+'));
      if (fields.length >= 2) states[fields.first] = fields[1];
    }
    for (final id in <String>[physicalDeviceId, emulatorDeviceId]) {
      if (states[id] != 'device') {
        throw _WakeBlocked(
          'targetUnavailable',
          'Android target "$id" is not attached in device state.',
        );
      }
    }
    final physicalQemu = (await _adbShell(physicalDeviceId, const <String>[
      'getprop',
      'ro.kernel.qemu',
    ], mutate: false)).trim();
    final emulatorQemu = (await _adbShell(emulatorDeviceId, const <String>[
      'getprop',
      'ro.kernel.qemu',
    ], mutate: false)).trim();
    if (physicalQemu == '1' || emulatorQemu != '1') {
      throw _WakeBlocked(
        'targetUnavailable',
        'Target ordering is invalid: $physicalDeviceId must be physical and '
            '$emulatorDeviceId must be an emulator.',
      );
    }
  }

  Future<SimsArtifactEvidence> run() async {
    final issuer = _WakeParty(
      role: wakeTokenIssuerRole,
      deviceId: physicalDeviceId,
      username: 'SimsWakeIssuer',
    );
    final presenter = _WakeParty(
      role: wakeTokenPresenterRole,
      deviceId: emulatorDeviceId,
      username: 'SimsWakePresenter',
    );
    final runId = _token('wake');
    final issuerNonce = _token('issuer');
    final presenterNonce = _token('presenter');
    late final AndroidAppStateGuard stateGuard;
    try {
      stateGuard = await AndroidAppStateGuard.capture(
        devices: <String>[physicalDeviceId, emulatorDeviceId],
        packageName: packageName,
        backupLabel: 'wake-token',
      );
    } on AndroidAppStateBlocked catch (error) {
      throw _WakeBlocked('environment', error.detail);
    } on AndroidAppStateFailure catch (error) {
      throw _WakeFailure('restoration', error.detail, assertionsAttempted: 2);
    }
    late Map<String, Object?> acceptedProof;

    try {
      await _installAndReset(issuer, stateGuard);
      await _installAndReset(presenter, stateGuard);
      await _bootstrapIdentity(issuer);
      await _bootstrapIdentity(presenter);
      await _exchangeContacts(issuer, presenter);

      final issuerEndpoint = await _runEndpoint(
        issuer,
        config: <String, Object?>{
          'schema': wakeTokenIssuerRequestSchema,
          'profileId': wakeTokenDirectionalityProfileId,
          'scenario': wakeTokenDirectionalityScenarioId,
          'role': wakeTokenIssuerRole,
          'transport_action': wakeTokenIssuerAction,
          'stepId': wakeTokenIssuerStepId(runId),
          'runId': runId,
          'nonce': issuerNonce,
          'contactPeerId': presenter.peerId,
          'timeoutMs': 160000,
        },
        runId: runId,
        nonce: issuerNonce,
      );

      // Distribute the exact registered contact-bound value through the real
      // signed contact-request path; no token crosses the host process.
      await _runGeneric(
        issuer,
        stepId: 'wake-distribute-$runId',
        values: <String, Object?>{
          'add_contacts': <Object?>[_contact(presenter)],
          'send_contact_requests_for_added_contacts': true,
          'contact_settle_delay_ms': 1000,
        },
      );
      // Force the receiver's ordinary health/drain path, then accept any live
      // request. Verified request handling persists `wt` before all early exits.
      await _runGeneric(
        presenter,
        stepId: 'wake-receive-$runId',
        values: <String, Object?>{
          'add_contacts': <Object?>[_contact(issuer)],
          'contact_request_action': 'accept_all',
          'contact_settle_delay_ms': 1000,
        },
      );

      final presenterEndpoint = await _runEndpoint(
        presenter,
        config: <String, Object?>{
          'schema': wakeTokenPresenterRequestSchema,
          'profileId': wakeTokenDirectionalityProfileId,
          'scenario': wakeTokenDirectionalityScenarioId,
          'role': wakeTokenPresenterRole,
          'transport_action': wakeTokenPresenterAction,
          'stepId': wakeTokenPresenterStepId(runId),
          'runId': runId,
          'nonce': presenterNonce,
          'contactPeerId': issuer.peerId,
          'timeoutMs': 160000,
        },
        runId: runId,
        nonce: presenterNonce,
      );

      acceptedProof = aggregateAndroidWakeTokenDirectionalityEvidence(
        issuerEndpoint: issuerEndpoint,
        presenterEndpoint: presenterEndpoint,
        runId: runId,
        issuerNonce: issuerNonce,
        presenterNonce: presenterNonce,
        artifactSha256: artifactSha256,
        physicalDeviceId: physicalDeviceId,
        emulatorDeviceId: emulatorDeviceId,
      );
    } on AndroidAppStateFailure catch (error) {
      throw _WakeFailure('environment', error.detail, assertionsAttempted: 2);
    } on _WakeBlocked {
      rethrow;
    } on _WakeFailure {
      rethrow;
    } on TimeoutException catch (error) {
      throw _WakeFailure(
        'test',
        error.message ?? 'wake-token campaign timed out',
      );
    } on FormatException catch (error) {
      throw _WakeFailure('harness', error.message, assertionsAttempted: 2);
    } finally {
      try {
        await stateGuard.restoreAll();
      } on AndroidAppStateFailure catch (error) {
        throw _WakeFailure('restoration', error.detail, assertionsAttempted: 2);
      }
    }
    final durable = writeSimsArtifactEvidenceSync(
      directory: proofDirectory,
      capabilityId: wakeTokenDirectionalityScenarioId,
      validatorIds: const <String>[androidWakeTokenArtifactValidatorId],
      payload: acceptedProof,
    );
    final audit = auditSimsArtifactEvidence(
      evidence: durable,
      expectedValidatorIds: const <String>[androidWakeTokenArtifactValidatorId],
    );
    if (!audit.isValid) {
      throw _WakeFailure('harness', audit.detail, assertionsAttempted: 2);
    }
    final decoded = jsonDecode(File(durable.path).readAsStringSync());
    if (decoded is! Map ||
        !validateWakeTokenArtifact(
          decoded.map<String, Object?>((key, value) => MapEntry('$key', value)),
        ).ok) {
      throw const _WakeFailure(
        'harness',
        'Durable wake-token evidence failed its exact validator.',
        assertionsAttempted: 2,
      );
    }
    return durable;
  }

  Future<void> _installAndReset(
    _WakeParty party,
    AndroidAppStateGuard stateGuard,
  ) async {
    await stateGuard.prepareFreshInstall(
      device: party.deviceId,
      artifact: artifact,
    );
    await _writeAppFile(
      party,
      'auto_setup.json',
      jsonEncode(<String, Object?>{'username': party.username}),
    );
  }

  Future<void> _bootstrapIdentity(_WakeParty party) async {
    await _launch(party);
    final decoded = jsonDecode(
      await _waitForAppFile(
        party,
        'intro_e2e_identity.json',
        const Duration(minutes: 3),
      ),
    );
    if (decoded is! Map) {
      throw const _WakeFailure('harness', 'Identity export is not an object.');
    }
    final identity = decoded.map<String, Object?>(
      (key, value) => MapEntry('$key', value),
    );
    final qrPayload = identity['qrPayload'];
    final mlKemPublicKey = identity['mlKemPublicKey'];
    if (qrPayload is! String ||
        qrPayload.isEmpty ||
        mlKemPublicKey is! String ||
        mlKemPublicKey.isEmpty) {
      throw const _WakeFailure(
        'harness',
        'Identity export lacks signed QR/ML-KEM material.',
      );
    }
    final qr = jsonDecode(qrPayload);
    final peerId = qr is Map ? qr['ns'] : null;
    if (peerId is! String ||
        peerId.isEmpty ||
        !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(peerId)) {
      throw const _WakeFailure('harness', 'Identity QR peer ID is invalid.');
    }
    party
      ..qrPayload = qrPayload
      ..mlKemPublicKey = mlKemPublicKey
      ..peerId = peerId;
  }

  Future<void> _exchangeContacts(
    _WakeParty issuer,
    _WakeParty presenter,
  ) async {
    await _stageGeneric(
      issuer,
      stepId: 'wake-contact-${issuer.role}',
      values: <String, Object?>{
        'add_contacts': <Object?>[_contact(presenter)],
      },
    );
    await _stageGeneric(
      presenter,
      stepId: 'wake-contact-${presenter.role}',
      values: <String, Object?>{
        'add_contacts': <Object?>[_contact(issuer)],
      },
    );
    await _launch(issuer);
    await _launch(presenter);
    await Future.wait(<Future<void>>[
      _waitForGeneric(issuer, 'wake-contact-${issuer.role}'),
      _waitForGeneric(presenter, 'wake-contact-${presenter.role}'),
    ]);
  }

  Map<String, Object?> _contact(_WakeParty party) => <String, Object?>{
    'qrPayload': party.qrPayload,
    'mlKemPublicKey': party.mlKemPublicKey,
  };

  Future<Map<String, Object?>> _runEndpoint(
    _WakeParty party, {
    required Map<String, Object?> config,
    required String runId,
    required String nonce,
  }) async {
    await _deleteAppFile(party, 'intro_e2e_result.json');
    await _writeAppFile(party, 'intro_e2e_config.json', jsonEncode(config));
    await _launch(party);
    final deadline = DateTime.now().add(const Duration(minutes: 3));
    while (DateTime.now().isBefore(deadline)) {
      final raw = await _readAppFile(party, 'intro_e2e_result.json');
      if (raw != null) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            final value = decoded.map<String, Object?>(
              (key, item) => MapEntry('$key', item),
            );
            if (value['schema'] == wakeTokenEndpointResultSchema &&
                value['scenario'] == wakeTokenDirectionalityScenarioId &&
                value['role'] == party.role &&
                value['runId'] == runId &&
                value['nonce'] == nonce) {
              if (value['status'] == 'failed' || value['success'] == false) {
                throw _WakeFailure(
                  'test',
                  'Wake-token ${party.role} endpoint failed with '
                      '${value['errorType'] ?? 'unknown error type'}.',
                );
              }
              if (value['status'] == 'complete' && value['success'] == true) {
                return value;
              }
            }
          }
        } on FormatException {
          // Retry an incomplete atomic observation inside the fixed window.
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw TimeoutException(
      'Wake-token ${party.role} endpoint timed out on ${party.deviceId}.',
    );
  }

  Future<void> _runGeneric(
    _WakeParty party, {
    required String stepId,
    required Map<String, Object?> values,
  }) async {
    await _stageGeneric(party, stepId: stepId, values: values);
    await _launch(party);
    await _waitForGeneric(party, stepId);
  }

  Future<void> _stageGeneric(
    _WakeParty party, {
    required String stepId,
    required Map<String, Object?> values,
  }) async {
    await _deleteAppFile(party, 'intro_e2e_result.json');
    await _writeAppFile(
      party,
      'intro_e2e_config.json',
      jsonEncode(<String, Object?>{'stepId': stepId, ...values}),
    );
  }

  Future<void> _waitForGeneric(_WakeParty party, String stepId) async {
    final deadline = DateTime.now().add(const Duration(minutes: 3));
    while (DateTime.now().isBefore(deadline)) {
      final raw = await _readAppFile(party, 'intro_e2e_result.json');
      if (raw != null) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map && decoded['stepId'] == stepId) {
            if (decoded['status'] == 'failed' || decoded['success'] == false) {
              throw _WakeFailure(
                'test',
                'Generic step $stepId failed on ${party.deviceId}.',
              );
            }
            if (decoded['status'] == 'complete' && decoded['success'] == true) {
              return;
            }
          }
        } on FormatException {
          // Retry until the app's write is complete.
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw TimeoutException('Generic step $stepId timed out.');
  }

  Future<void> _launch(_WakeParty party) async {
    await _adbShell(party.deviceId, <String>[
      'am',
      'force-stop',
      packageName,
    ], mutate: true);
    await _adbShell(party.deviceId, <String>[
      'am',
      'start',
      '-W',
      '-n',
      '$packageName/com.mknoon.app.MainActivity',
    ], mutate: true);
  }

  Future<String> _waitForAppFile(
    _WakeParty party,
    String name,
    Duration timeout,
  ) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final value = await _readAppFile(party, name);
      if (value != null && value.trim().isNotEmpty) return value;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw TimeoutException('$name timed out on ${party.deviceId}.');
  }

  Future<String?> _readAppFile(_WakeParty party, String name) async {
    final result = await _process(
      'adb',
      <String>[
        '-s',
        party.deviceId,
        'shell',
        'run-as',
        packageName,
        'cat',
        'app_flutter/$name',
      ],
      allowFailure: true,
      mutate: false,
    );
    if (result.exitCode != 0 || '${result.stdout}'.trim().isEmpty) return null;
    return '${result.stdout}';
  }

  Future<void> _deleteAppFile(_WakeParty party, String name) async {
    await _process(
      'adb',
      <String>[
        '-s',
        party.deviceId,
        'shell',
        'run-as',
        packageName,
        'rm',
        '-f',
        'app_flutter/$name',
      ],
      allowFailure: true,
      mutate: true,
    );
  }

  Future<void> _writeAppFile(
    _WakeParty party,
    String name,
    String content,
  ) async {
    final safeName = name.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    final device = party.deviceId.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
    final temp = File(
      '${Directory.systemTemp.path}/sims-wake-$device-$safeName-$pid-'
      '${_random.nextInt(1 << 32)}',
    );
    final remote = '/data/local/tmp/sims-wake-$safeName-${_token('cfg')}';
    try {
      await temp.writeAsString(content, flush: true);
      await _process('adb', <String>[
        '-s',
        party.deviceId,
        'push',
        temp.path,
        remote,
      ], mutate: true);
      await _adbShell(party.deviceId, <String>[
        'run-as',
        packageName,
        'mkdir',
        '-p',
        'app_flutter',
      ], mutate: true);
      await _adbShell(party.deviceId, <String>[
        'run-as',
        packageName,
        'cp',
        remote,
        'app_flutter/$name',
      ], mutate: true);
    } finally {
      await _process(
        'adb',
        <String>['-s', party.deviceId, 'shell', 'rm', '-f', remote],
        allowFailure: true,
        mutate: true,
      );
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<String> _adbShell(
    String deviceId,
    List<String> command, {
    required bool mutate,
  }) async {
    final result = await _process('adb', <String>[
      '-s',
      deviceId,
      'shell',
      ...command,
    ], mutate: mutate);
    if (result.exitCode != 0) {
      throw _WakeFailure(
        _mutated ? 'environment' : 'targetUnavailable',
        'adb shell command failed on $deviceId.',
      );
    }
    return '${result.stdout}';
  }

  Future<ProcessResult> _process(
    String executable,
    List<String> arguments, {
    bool allowFailure = false,
    required bool mutate,
  }) async {
    if (mutate) _mutated = true;
    late final ProcessResult result;
    try {
      result = await Process.run(executable, arguments);
    } on ProcessException catch (error) {
      if (!_mutated) {
        throw _WakeBlocked(
          'missingDriver',
          '$executable is unavailable: ${error.message}',
        );
      }
      throw _WakeFailure(
        'missingDriver',
        '$executable could not start: ${error.message}',
      );
    }
    if (!allowFailure && result.exitCode != 0) {
      if (!_mutated) {
        throw _WakeBlocked(
          'environment',
          '$executable ${arguments.take(3).join(' ')} failed.',
        );
      }
      throw _WakeFailure(
        'environment',
        '$executable ${arguments.take(3).join(' ')} failed.',
      );
    }
    return result;
  }

  String _token(String prefix) {
    final bytes = List<int>.generate(8, (_) => _random.nextInt(256));
    final suffix = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '$prefix-${DateTime.now().toUtc().microsecondsSinceEpoch}-$suffix';
  }
}

final class _WakeParty {
  _WakeParty({
    required this.role,
    required this.deviceId,
    required this.username,
  });

  final String role;
  final String deviceId;
  final String username;
  String? peerId;
  String? qrPayload;
  String? mlKemPublicKey;
}

final class _WakeBlocked implements Exception {
  const _WakeBlocked(this.blocker, this.detail);

  final String blocker;
  final String detail;
}

final class _WakeFailure implements Exception {
  const _WakeFailure(this.blocker, this.detail, {this.assertionsAttempted = 0});

  final String blocker;
  final String detail;
  final int assertionsAttempted;
}

void _validateWakeEndpoint(
  Map<String, Object?> endpoint, {
  required String role,
  required String stepId,
  required String runId,
  required String nonce,
}) {
  if (endpoint['schema'] != wakeTokenEndpointResultSchema ||
      endpoint['scenario'] != wakeTokenDirectionalityScenarioId ||
      endpoint['buildProfile'] != wakeTokenDirectionalityProfileId ||
      endpoint['role'] != role ||
      endpoint['stepId'] != stepId ||
      endpoint['runId'] != runId ||
      endpoint['nonce'] != nonce ||
      endpoint['status'] != 'complete' ||
      endpoint['success'] != true) {
    throw FormatException('wake-token $role endpoint tuple rejected');
  }
}

void _rejectSecretBearingFields(Object? value) {
  if (value is Map) {
    for (final entry in value.entries) {
      final key = '${entry.key}'.toLowerCase();
      if ((key.contains('token') || key.contains('secret')) &&
          !key.endsWith('sha256') &&
          entry.value != null) {
        throw FormatException(
          'wake-token endpoint contains forbidden secret-bearing field '
          '${entry.key}',
        );
      }
      _rejectSecretBearingFields(entry.value);
    }
  } else if (value is Iterable) {
    for (final item in value) {
      _rejectSecretBearingFields(item);
    }
  }
}

Directory _proofDirectory(Map<String, String> environment) {
  final configured = environment['SIMS_PROOF_DIRECTORY']?.trim();
  if (configured != null && configured.isNotEmpty) {
    return Directory(configured).absolute;
  }
  return Directory(
    'build/sims/proofs/$wakeTokenDirectionalityScenarioId',
  ).absolute;
}

extension on File {
  bool isFileSync() =>
      FileSystemEntity.typeSync(path, followLinks: false) ==
      FileSystemEntityType.file;
}
