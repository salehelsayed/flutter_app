import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/debug/android_voice_message_e2e_protocol.dart';

import '../../tool/sims/artifact_evidence.dart';
import '../support/android_app_state_guard.dart';
import '../support/android_voice_message_evidence.dart';
import '../support/sims_runtime_protocol.dart';
import '_android_app_package.dart';

const int androidVoiceMessageAssertionCount = 1;

/// Typed result returned to the Sims adapter. It deliberately mirrors the
/// universal runner sentinel without importing that runner's private class.
final class AndroidVoiceMessageCampaignResult {
  const AndroidVoiceMessageCampaignResult._({
    required this.processExitCode,
    required this.json,
  });

  factory AndroidVoiceMessageCampaignResult.pass(
    SimsArtifactEvidence evidence,
  ) => AndroidVoiceMessageCampaignResult._(
    processExitCode: 0,
    json: <String, Object?>{
      'status': 'PASS',
      'assertionsAttempted': androidVoiceMessageAssertionCount,
      'artifactPresent': true,
      'printOnly': false,
      'exitCode': 0,
      'detail':
          'One centrally prepared main-app APK completed the physical-Android '
          'record/send and emulator receive/download/playback journey.',
      'artifactEvidence': evidence.toJson(),
    },
  );

  factory AndroidVoiceMessageCampaignResult.blocked({
    required String blocker,
    required String detail,
    required bool artifactPresent,
  }) => AndroidVoiceMessageCampaignResult._(
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

  factory AndroidVoiceMessageCampaignResult.fail({
    required String blocker,
    required String detail,
    required bool artifactPresent,
    int assertionsAttempted = 0,
  }) => AndroidVoiceMessageCampaignResult._(
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

  final int processExitCode;
  final Map<String, Object?> json;
}

/// Runs the full two-peer voice campaign without invoking Flutter build or
/// Flutter drive. Both Android targets receive the exact same cached APK.
Future<AndroidVoiceMessageCampaignResult> runAndroidVoiceMessageDeviceCampaign({
  required List<String> devices,
  required String? artifactPath,
  Map<String, String>? environment,
}) async {
  final env = environment ?? Platform.environment;
  if (artifactPath == null ||
      artifactPath.trim().isEmpty ||
      !File(artifactPath).isFileSync()) {
    return AndroidVoiceMessageCampaignResult.blocked(
      blocker: 'missingArtifact',
      detail:
          'A readable centrally cached $simsAndroidMainProfileId APK is '
          'required; the voice campaign never builds an application.',
      artifactPresent: false,
    );
  }
  final configuredProfile = env['SIMS_ARTIFACT_PROFILE_ID']?.trim();
  if (configuredProfile != null &&
      configuredProfile.isNotEmpty &&
      configuredProfile != simsAndroidMainProfileId) {
    return AndroidVoiceMessageCampaignResult.blocked(
      blocker: 'missingArtifact',
      detail:
          'Voice-message E2E requires $simsAndroidMainProfileId; the executor '
          'supplied $configuredProfile.',
      artifactPresent: true,
    );
  }
  if (devices.length != 2 ||
      devices.first.isEmpty ||
      devices.last.isEmpty ||
      devices.first == devices.last) {
    return AndroidVoiceMessageCampaignResult.blocked(
      blocker: 'targetUnavailable',
      detail:
          'Voice-message E2E requires two distinct explicit targets ordered '
          'as one USB physical Android and one Android emulator.',
      artifactPresent: true,
    );
  }

  final artifact = File(artifactPath).absolute;
  late final String artifactSha256;
  try {
    artifactSha256 = sha256.convert(await artifact.readAsBytes()).toString();
  } on FileSystemException catch (error) {
    return AndroidVoiceMessageCampaignResult.blocked(
      blocker: 'missingArtifact',
      detail: 'The prepared APK could not be read: ${error.message}',
      artifactPresent: false,
    );
  }

  late final _AndroidVoiceHost host;
  try {
    host = _AndroidVoiceHost(
      physicalDeviceId: devices.first,
      emulatorDeviceId: devices.last,
      artifact: artifact,
      artifactSha256: artifactSha256,
      packageName: resolveAndroidAppPackage(),
      proofDirectory: _proofDirectory(env),
    );
    await host.verifyPrerequisites();
  } on _VoiceBlocked catch (blocked) {
    return AndroidVoiceMessageCampaignResult.blocked(
      blocker: blocked.blocker,
      detail: blocked.detail,
      artifactPresent: true,
    );
  } on Object catch (error) {
    return AndroidVoiceMessageCampaignResult.blocked(
      blocker: 'environment',
      detail: 'Voice-message prerequisite validation failed: $error',
      artifactPresent: true,
    );
  }

  try {
    final evidence = await host.run();
    return AndroidVoiceMessageCampaignResult.pass(evidence);
  } on _VoiceBlocked catch (blocked) {
    return AndroidVoiceMessageCampaignResult.blocked(
      blocker: blocked.blocker,
      detail: blocked.detail,
      artifactPresent: true,
    );
  } on _VoiceFailure catch (failure) {
    return AndroidVoiceMessageCampaignResult.fail(
      blocker: failure.blocker,
      detail: failure.detail,
      artifactPresent: false,
    );
  } on Object catch (error, stackTrace) {
    return AndroidVoiceMessageCampaignResult.fail(
      blocker: 'harness',
      detail: 'Voice-message campaign failed unexpectedly: $error\n$stackTrace',
      artifactPresent: false,
    );
  }
}

/// Aggregates two independently nonce-bound endpoint receipts and refuses to
/// trust host file transfer, raw audio, or mismatched identity/byte evidence.
Map<String, Object?> aggregateAndroidVoiceMessageEvidence({
  required Map<String, Object?> senderEndpoint,
  required Map<String, Object?> receiverEndpoint,
  required String runId,
  required String senderNonce,
  required String receiverNonce,
  required String artifactSha256,
  required String physicalDeviceId,
  required String emulatorDeviceId,
}) {
  _validateEndpointTuple(
    senderEndpoint,
    role: androidVoiceMessageSenderRole,
    runId: runId,
    nonce: senderNonce,
  );
  _validateEndpointTuple(
    receiverEndpoint,
    role: androidVoiceMessageReceiverRole,
    runId: runId,
    nonce: receiverNonce,
  );
  final sender = _object(senderEndpoint['sender']);
  final receiver = _object(receiverEndpoint['receiver']);
  final senderTransport = _object(senderEndpoint['transport']);
  final receiverTransport = _object(receiverEndpoint['transport']);
  if (sender == null ||
      receiver == null ||
      senderTransport == null ||
      receiverTransport == null) {
    throw const FormatException('voice endpoint evidence is incomplete');
  }

  final senderDigest = sender['recordedPlaintextSha256'];
  final receiverDigest = receiver['downloadedPlaintextSha256'];
  final senderPeerHash = sender['receiverPeerIdSha256'];
  final receiverPeerHash = receiver['ownPeerIdSha256'];
  final proof = <String, Object?>{
    'schema': androidVoiceMessageEvidenceSchema,
    'scenario': simsAndroidVoiceMessageScenarioId,
    'status': 'passed',
    'platform': 'android',
    'runtimeDispatched': true,
    'runId': runId,
    'sharedArtifact': <String, Object?>{
      'profileId': simsAndroidMainProfileId,
      'sha256': artifactSha256,
    },
    'deviceIds': <String>[physicalDeviceId, emulatorDeviceId],
    'targetKinds': const <String, Object?>{
      'sender': 'physical',
      'receiver': 'emulator',
    },
    'sender': <String, Object?>{
      ...sender,
      'role': simsVoiceMessageSenderRole,
      'deviceId': physicalDeviceId,
    },
    'receiver': <String, Object?>{
      ...receiver,
      'role': simsVoiceMessageReceiverRole,
      'deviceId': emulatorDeviceId,
    },
    'transport': <String, Object?>{
      'realRelayMediaUpload': senderTransport['realRelayMediaUpload'],
      'senderCustodyAccepted': senderTransport['senderCustodyAccepted'],
      'realMessageDelivery': receiverTransport['realMessageDelivery'],
      'realRelayMediaDownload': receiverTransport['realRelayMediaDownload'],
      'senderReceiverPeerMatch':
          senderPeerHash is String && senderPeerHash == receiverPeerHash,
      'usedFakeNetwork':
          senderTransport['usedFakeNetwork'] == true ||
          receiverTransport['usedFakeNetwork'] == true,
      'usedHostFileTransfer':
          senderTransport['usedHostFileTransfer'] == true ||
          receiverTransport['usedHostFileTransfer'] == true,
    },
    'assertionsAttempted': androidVoiceMessageAssertionCount,
  };
  if (senderDigest != receiverDigest) {
    throw const FormatException('sender and receiver voice hashes differ');
  }
  final validation = validateAndroidVoiceMessageEvidence(proof);
  if (!validation.ok) throw FormatException(validation.detail);
  return Map<String, Object?>.unmodifiable(proof);
}

final class _AndroidVoiceHost {
  _AndroidVoiceHost({
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
    final version = await _process(
      'adb',
      const <String>['version'],
      missingToolBlocker: 'missingDriver',
      mutate: false,
    );
    if (version.exitCode != 0) {
      throw const _VoiceBlocked('missingDriver', 'adb version failed');
    }
    final devices = await _process('adb', const <String>[
      'devices',
      '-l',
    ], mutate: false);
    final states = <String, String>{};
    for (final line in '${devices.stdout}'.split('\n')) {
      final fields = line.trim().split(RegExp(r'\s+'));
      if (fields.length >= 2) states[fields.first] = fields[1];
    }
    for (final device in <String>[physicalDeviceId, emulatorDeviceId]) {
      if (states[device] != 'device') {
        throw _VoiceBlocked(
          'targetUnavailable',
          'Android target "$device" is not attached in device state.',
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
      throw _VoiceBlocked(
        'targetUnavailable',
        'Target ordering is invalid: $physicalDeviceId must be physical and '
            '$emulatorDeviceId must be an emulator.',
      );
    }
  }

  Future<SimsArtifactEvidence> run() async {
    final physical = _Party(
      role: androidVoiceMessageSenderRole,
      deviceId: physicalDeviceId,
      username: 'SimsVoiceSender',
    );
    final emulator = _Party(
      role: androidVoiceMessageReceiverRole,
      deviceId: emulatorDeviceId,
      username: 'SimsVoiceReceiver',
    );
    final runId = _token('voice');
    final messageId = _token('message');
    final attachmentId = _token('attachment');
    final senderNonce = _token('sender');
    final receiverNonce = _token('receiver');
    late final AndroidAppStateGuard stateGuard;
    try {
      stateGuard = await AndroidAppStateGuard.capture(
        devices: <String>[physicalDeviceId, emulatorDeviceId],
        packageName: packageName,
        backupLabel: 'voice-message',
      );
    } on AndroidAppStateBlocked catch (error) {
      throw _VoiceBlocked('environment', error.detail);
    } on AndroidAppStateFailure catch (error) {
      throw _VoiceFailure('restoration', error.detail);
    }
    late Map<String, Object?> acceptedProof;

    try {
      await _installAndReset(physical, stateGuard);
      await _installAndReset(emulator, stateGuard);
      await _grantRecordAudio();
      await _bootstrapIdentity(physical);
      await _bootstrapIdentity(emulator);
      await _exchangeContacts(physical, emulator);

      await _deleteAppFile(emulator, 'intro_e2e_result.json');
      await _writeAppFile(
        emulator,
        'intro_e2e_config.json',
        jsonEncode(
          _voiceConfig(
            party: emulator,
            contactPeerId: physical.peerId!,
            runId: runId,
            nonce: receiverNonce,
            messageId: messageId,
            attachmentId: attachmentId,
          ),
        ),
      );
      final receiverArmed = await _waitForEndpoint(
        emulator,
        role: androidVoiceMessageReceiverRole,
        runId: runId,
        nonce: receiverNonce,
        status: 'armed',
        timeout: const Duration(minutes: 3),
      );
      if (receiverArmed['messageId'] != messageId ||
          receiverArmed['attachmentId'] != attachmentId) {
        throw const _VoiceFailure(
          'harness',
          'Receiver armed a different message/attachment tuple.',
        );
      }

      await _deleteAppFile(physical, 'intro_e2e_result.json');
      await _writeAppFile(
        physical,
        'intro_e2e_config.json',
        jsonEncode(
          _voiceConfig(
            party: physical,
            contactPeerId: emulator.peerId!,
            runId: runId,
            nonce: senderNonce,
            messageId: messageId,
            attachmentId: attachmentId,
          ),
        ),
      );
      final senderEndpoint = await _waitForEndpoint(
        physical,
        role: androidVoiceMessageSenderRole,
        runId: runId,
        nonce: senderNonce,
        status: 'complete',
        timeout: const Duration(minutes: 3),
      );
      final receiverEndpoint = await _waitForEndpoint(
        emulator,
        role: androidVoiceMessageReceiverRole,
        runId: runId,
        nonce: receiverNonce,
        status: 'complete',
        timeout: const Duration(minutes: 3),
      );

      acceptedProof = aggregateAndroidVoiceMessageEvidence(
        senderEndpoint: senderEndpoint,
        receiverEndpoint: receiverEndpoint,
        runId: runId,
        senderNonce: senderNonce,
        receiverNonce: receiverNonce,
        artifactSha256: artifactSha256,
        physicalDeviceId: physicalDeviceId,
        emulatorDeviceId: emulatorDeviceId,
      );
    } on AndroidAppStateFailure catch (error) {
      throw _VoiceFailure('environment', error.detail);
    } on _VoiceBlocked {
      rethrow;
    } on _VoiceFailure {
      rethrow;
    } on TimeoutException catch (error) {
      throw _VoiceFailure('test', error.message ?? 'voice campaign timed out');
    } on FormatException catch (error) {
      throw _VoiceFailure('harness', error.message);
    } finally {
      try {
        await stateGuard.restoreAll();
      } on AndroidAppStateFailure catch (error) {
        throw _VoiceFailure('restoration', error.detail);
      }
    }
    final durable = writeSimsArtifactEvidenceSync(
      directory: proofDirectory,
      capabilityId: simsAndroidVoiceMessageScenarioId,
      validatorIds: const <String>[androidVoiceMessageArtifactValidatorId],
      payload: androidVoiceMessageDurablePayload(acceptedProof),
    );
    final audit = auditSimsArtifactEvidence(
      evidence: durable,
      expectedValidatorIds: const <String>[
        androidVoiceMessageArtifactValidatorId,
      ],
    );
    if (!audit.isValid) {
      throw _VoiceFailure('harness', audit.detail);
    }
    final durableJson = jsonDecode(File(durable.path).readAsStringSync());
    if (durableJson is! Map ||
        !validateAndroidVoiceMessageDurableArtifact(
          durableJson.map<String, Object?>(
            (key, value) => MapEntry('$key', value),
          ),
        ).ok) {
      throw const _VoiceFailure(
        'harness',
        'Durable voice evidence failed its exact validator.',
      );
    }
    return durable;
  }

  Future<void> _installAndReset(
    _Party party,
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

  Future<void> _bootstrapIdentity(_Party party) async {
    await _launch(party);
    final raw = await _waitForAppFile(
      party,
      'intro_e2e_identity.json',
      const Duration(minutes: 3),
    );
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const _VoiceFailure('harness', 'Identity export is not an object.');
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
      throw const _VoiceFailure(
        'harness',
        'Identity export lacks signed QR/ML-KEM material.',
      );
    }
    final qr = jsonDecode(qrPayload);
    if (qr is! Map || qr['ns'] is! String) {
      throw const _VoiceFailure('harness', 'Identity QR payload is invalid.');
    }
    party
      ..qrPayload = qrPayload
      ..mlKemPublicKey = mlKemPublicKey
      ..peerId = qr['ns']! as String;
  }

  Future<void> _exchangeContacts(_Party sender, _Party receiver) async {
    await _stageContactBootstrap(sender, receiver);
    await _stageContactBootstrap(receiver, sender);
    await _launch(sender);
    await _launch(receiver);
    await Future.wait(<Future<void>>[
      _waitForGenericStep(sender, 'voice-contact-${sender.role}'),
      _waitForGenericStep(receiver, 'voice-contact-${receiver.role}'),
    ]);
  }

  Future<void> _stageContactBootstrap(_Party owner, _Party contact) async {
    await _deleteAppFile(owner, 'intro_e2e_result.json');
    await _writeAppFile(
      owner,
      'intro_e2e_config.json',
      jsonEncode(<String, Object?>{
        'stepId': 'voice-contact-${owner.role}',
        'add_contacts': <Object?>[
          <String, Object?>{
            'qrPayload': contact.qrPayload,
            'mlKemPublicKey': contact.mlKemPublicKey,
          },
        ],
      }),
    );
  }

  Future<void> _waitForGenericStep(_Party party, String stepId) async {
    final deadline = DateTime.now().add(const Duration(minutes: 3));
    while (DateTime.now().isBefore(deadline)) {
      final raw = await _readAppFile(party, 'intro_e2e_result.json');
      if (raw != null) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map && decoded['stepId'] == stepId) {
            if (decoded['status'] == 'failed' || decoded['success'] == false) {
              throw _VoiceFailure(
                'test',
                'Contact bootstrap failed on ${party.deviceId}.',
              );
            }
            if (decoded['status'] == 'complete' && decoded['success'] == true) {
              return;
            }
          }
        } on FormatException {
          // Atomic rename may not yet be visible; retry within the bound.
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw TimeoutException('Contact bootstrap timed out on ${party.deviceId}.');
  }

  Map<String, Object?> _voiceConfig({
    required _Party party,
    required String contactPeerId,
    required String runId,
    required String nonce,
    required String messageId,
    required String attachmentId,
  }) => <String, Object?>{
    'schema': androidVoiceMessageE2ERequestSchema,
    'transport_action': androidVoiceMessageE2EAction,
    'scenario': androidVoiceMessageE2EScenario,
    'role': party.role,
    'stepId': 'voice-${party.role}-$runId',
    'runId': runId,
    'nonce': nonce,
    'contactPeerId': contactPeerId,
    'messageId': messageId,
    'attachmentId': attachmentId,
    'timeoutMs': 160000,
  };

  Future<Map<String, Object?>> _waitForEndpoint(
    _Party party, {
    required String role,
    required String runId,
    required String nonce,
    required String status,
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final raw = await _readAppFile(party, 'intro_e2e_result.json');
      if (raw != null) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            final value = decoded.map<String, Object?>(
              (key, item) => MapEntry('$key', item),
            );
            if (value['schema'] == androidVoiceMessageE2EEndpointResultSchema &&
                value['scenario'] == androidVoiceMessageE2EScenario &&
                value['role'] == role &&
                value['runId'] == runId &&
                value['nonce'] == nonce) {
              if (value['status'] == 'failed' || value['success'] == false) {
                throw _VoiceFailure(
                  'test',
                  'Voice endpoint $role failed on ${party.deviceId}.',
                );
              }
              if (value['status'] == status && value['success'] == true) {
                return value;
              }
            }
          }
        } on FormatException {
          // Retry an incomplete atomic observation within the bounded window.
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw TimeoutException(
      'Voice endpoint $role did not reach $status on ${party.deviceId}.',
    );
  }

  Future<void> _grantRecordAudio() async {
    await _adbShell(physicalDeviceId, <String>[
      'pm',
      'grant',
      packageName,
      'android.permission.RECORD_AUDIO',
    ], mutate: true);
  }

  Future<void> _launch(_Party party) async {
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
      '$packageName/.MainActivity',
    ], mutate: true);
  }

  Future<String> _waitForAppFile(
    _Party party,
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

  Future<String?> _readAppFile(_Party party, String name) async {
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

  Future<void> _deleteAppFile(_Party party, String name) async {
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

  Future<void> _writeAppFile(_Party party, String name, String content) async {
    final safeName = name.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    final temp = File(
      '${Directory.systemTemp.path}/sims-voice-${party.deviceId.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_')}-$safeName-$pid-${_random.nextInt(1 << 32)}',
    );
    final remote = '/data/local/tmp/sims-voice-$safeName-${_token('cfg')}';
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
      throw _VoiceFailure(
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
    bool mutate = false,
    String missingToolBlocker = 'missingDriver',
  }) async {
    if (mutate) _mutated = true;
    late final ProcessResult result;
    try {
      result = await Process.run(executable, arguments);
    } on ProcessException catch (error) {
      if (!_mutated) {
        throw _VoiceBlocked(
          missingToolBlocker,
          '$executable is unavailable: ${error.message}',
        );
      }
      throw _VoiceFailure(
        missingToolBlocker,
        '$executable could not start: ${error.message}',
      );
    }
    if (!allowFailure && result.exitCode != 0) {
      if (!_mutated) {
        throw _VoiceBlocked(
          'environment',
          '$executable ${arguments.take(3).join(' ')} failed.',
        );
      }
      throw _VoiceFailure(
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

final class _Party {
  _Party({required this.role, required this.deviceId, required this.username});

  final String role;
  final String deviceId;
  final String username;
  String? peerId;
  String? qrPayload;
  String? mlKemPublicKey;
}

final class _VoiceBlocked implements Exception {
  const _VoiceBlocked(this.blocker, this.detail);

  final String blocker;
  final String detail;
}

final class _VoiceFailure implements Exception {
  const _VoiceFailure(this.blocker, this.detail);

  final String blocker;
  final String detail;
}

void _validateEndpointTuple(
  Map<String, Object?> endpoint, {
  required String role,
  required String runId,
  required String nonce,
}) {
  if (endpoint['schema'] != androidVoiceMessageE2EEndpointResultSchema ||
      endpoint['scenario'] != androidVoiceMessageE2EScenario ||
      endpoint['buildProfile'] != androidVoiceMessageE2EBuildProfile ||
      endpoint['status'] != 'complete' ||
      endpoint['success'] != true ||
      endpoint['role'] != role ||
      endpoint['stepId'] != 'voice-$role-$runId' ||
      endpoint['runId'] != runId ||
      endpoint['nonce'] != nonce) {
    throw FormatException('voice $role endpoint tuple rejected');
  }
}

Map<String, Object?>? _object(Object? value) {
  if (value is! Map) return null;
  return value.map<String, Object?>((key, item) => MapEntry('$key', item));
}

Directory _proofDirectory(Map<String, String> environment) {
  final configured = environment['SIMS_PROOF_DIRECTORY']?.trim();
  if (configured != null && configured.isNotEmpty) {
    return Directory(configured).absolute;
  }
  return Directory(
    'build/sims/proofs/$simsAndroidVoiceMessageScenarioId',
  ).absolute;
}

extension on File {
  bool isFileSync() =>
      FileSystemEntity.typeSync(path, followLinks: false) ==
      FileSystemEntityType.file;
}
