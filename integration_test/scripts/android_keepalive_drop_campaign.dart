import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/debug/keepalive_drop_e2e_contract.dart';

import '../../tool/sims/artifact_evidence.dart';
import '../../tool/sims/device_criteria.dart';
import '../support/android_app_state_guard.dart';
import '../support/android_keepalive_drop_campaign.dart';
import '../support/sims_runtime_protocol.dart';
import '_android_app_package.dart';

const String _mainArtifactProfile = simsAndroidMainProfileId;
const String _configFile = 'intro_e2e_config.json';
const String _resultFile = 'intro_e2e_result.json';
const String _identityFile = 'intro_e2e_identity.json';

/// Typed result returned to the legacy 1:1 catalog adapter.
final class AndroidKeepaliveDropCampaignResult {
  const AndroidKeepaliveDropCampaignResult(this.exitCode, this.json);

  final int exitCode;
  final Map<String, Object?> json;
}

/// Runs the keepalive proof against the centrally prepared main-app APK.
///
/// The campaign never invokes Flutter, Gradle, or another build. It installs
/// the supplied APK once on each explicit target, waits for the production
/// 8-second keepalive to miss naturally twice, and restores each target's
/// original APK/private-data/process state before it can emit PASS evidence.
Future<AndroidKeepaliveDropCampaignResult> runAndroidKeepaliveDropCampaign({
  required List<String> devices,
  required String? artifactPath,
}) async {
  final artifactPresent =
      artifactPath != null &&
      FileSystemEntity.typeSync(
            File(artifactPath).absolute.path,
            followLinks: true,
          ) ==
          FileSystemEntityType.file;
  try {
    final campaign = _KeepaliveCampaign.fromInputs(
      devices: devices,
      artifactPath: artifactPath,
    );
    return await campaign.run();
  } on _CampaignBlocked catch (error) {
    return _blocked(
      error.detail,
      blocker: error.blocker,
      artifactPresent: artifactPresent,
    );
  } on _CampaignFailure catch (error) {
    return _failed(error.detail, artifactPresent: artifactPresent);
  } on Object {
    return _failed(
      'Keepalive campaign failed inside the host harness.',
      artifactPresent: artifactPresent,
    );
  }
}

final class _KeepaliveCampaign {
  _KeepaliveCampaign({
    required this.artifact,
    required this.physical,
    required this.emulator,
    required this.packageName,
    required this.proofDirectory,
  });

  factory _KeepaliveCampaign.fromInputs({
    required List<String> devices,
    required String? artifactPath,
  }) {
    if (artifactPath == null || artifactPath.trim().isEmpty) {
      throw const _CampaignBlocked(
        'A readable central android.e2e.main APK is required; this campaign '
        'is forbidden from building its own app.',
        blocker: 'missingArtifact',
      );
    }
    final artifact = File(artifactPath).absolute;
    if (FileSystemEntity.typeSync(artifact.path, followLinks: true) !=
        FileSystemEntityType.file) {
      throw const _CampaignBlocked(
        'The centrally prepared android.e2e.main APK is missing.',
        blocker: 'missingArtifact',
      );
    }
    final configuredProfile = Platform.environment['SIMS_ARTIFACT_PROFILE_ID']
        ?.trim();
    if (configuredProfile != null &&
        configuredProfile.isNotEmpty &&
        configuredProfile != _mainArtifactProfile) {
      throw _CampaignBlocked(
        'Keepalive requires $_mainArtifactProfile; the executor supplied '
        '$configuredProfile.',
        blocker: 'missingArtifact',
      );
    }
    final safeTarget = RegExp(r'^[A-Za-z0-9._:-]{1,160}$');
    if (devices.length != 2 ||
        devices.first == devices.last ||
        devices.any((device) => !safeTarget.hasMatch(device))) {
      throw const _CampaignBlocked(
        'Keepalive requires two distinct explicit Android targets ordered as '
        'one USB physical device and one emulator.',
        blocker: 'targetUnavailable',
      );
    }
    late final String packageName;
    try {
      packageName = resolveAndroidAppPackage();
    } on Object {
      throw const _CampaignBlocked(
        'The Android application ID could not be resolved.',
      );
    }
    final proofPath = Platform.environment['SIMS_PROOF_DIRECTORY']?.trim();
    return _KeepaliveCampaign(
      artifact: artifact,
      physical: devices.first,
      emulator: devices.last,
      packageName: packageName,
      proofDirectory: Directory(
        proofPath == null || proofPath.isEmpty
            ? 'build/sims/proofs/$keepaliveDropScenarioId'
            : proofPath,
      ).absolute,
    );
  }

  final File artifact;
  final String physical;
  final String emulator;
  final String packageName;
  final Directory proofDirectory;
  final Random _random = Random.secure();

  Future<AndroidKeepaliveDropCampaignResult> run() async {
    await _preflight();
    final artifactSha256 = await _hostFileSha256(artifact);
    final runId = _token('keepalive');
    final nonce = _token('nonce');
    final invocation = SimsRuntimeInvocation(
      schema: simsRuntimeConfigSchema,
      profileId: _mainArtifactProfile,
      scenarioId: keepaliveDropScenarioId,
      role: 'sender',
      runId: runId,
      nonce: nonce,
      values: <String, Object?>{
        'targetId': physical,
        'targetKind': 'physical',
        'buildArtifactSha256': artifactSha256,
      },
    );
    final invocationFailure = validateKeepaliveCampaignInvocation(invocation);
    if (invocationFailure != null) {
      throw _CampaignFailure(invocationFailure);
    }

    late final AndroidAppStateGuard stateGuard;
    try {
      stateGuard = await AndroidAppStateGuard.capture(
        devices: <String>[physical, emulator],
        packageName: packageName,
        backupLabel: 'keepalive',
      );
    } on AndroidAppStateBlocked catch (error) {
      throw _CampaignBlocked(error.detail);
    } on AndroidAppStateFailure catch (error) {
      throw _CampaignFailure(error.detail);
    }
    Object? pendingError;
    Map<String, Object?>? observedProof;

    try {
      await _installFresh(physical, 'sims-keepalive-sender', stateGuard);
      await _installFresh(emulator, 'sims-keepalive-receiver', stateGuard);
      observedProof = await _executeProof(
        invocation: invocation,
        artifactSha256: artifactSha256,
      );
    } on AndroidAppStateFailure catch (error) {
      pendingError = _CampaignFailure(error.detail);
    } on Object catch (error) {
      pendingError = error;
    }

    try {
      await stateGuard.restoreAll();
    } on AndroidAppStateFailure catch (error) {
      throw _CampaignFailure(
        '${error.detail} no passing artifact was written.',
      );
    }

    if (pendingError != null) {
      if (pendingError is _CampaignBlocked) throw pendingError;
      if (pendingError is _CampaignFailure) throw pendingError;
      throw const _CampaignFailure(
        'Keepalive proof failed inside the production-app campaign.',
      );
    }
    if (observedProof == null) {
      throw const _CampaignFailure('Keepalive proof returned no observations.');
    }
    final payload = <String, Object?>{
      ...observedProof,
      'targetKinds': const <String>['physical', 'emulator'],
      'preparedBuild': <String, Object?>{
        'profileId': _mainArtifactProfile,
        'sha256': artifactSha256,
      },
      'runBinding': <String, Object?>{
        'runIdSha256': sha256.convert(utf8.encode(runId)).toString(),
        'nonceSha256': sha256.convert(utf8.encode(nonce)).toString(),
      },
      'naturalKeepalive': const <String, Object?>{
        'intervalMs': 8000,
        'missThreshold': 2,
        'thresholdOverrideUsed': false,
      },
      'preparedApkInstalls': 2,
      'childFlutterBuilds': 0,
      'stateRestored': true,
    };
    final validation = validateKeepaliveDropArtifact(payload);
    if (!validation.ok) throw _CampaignFailure(validation.detail);
    final evidence = writeSimsArtifactEvidenceSync(
      directory: proofDirectory,
      capabilityId: keepaliveDropScenarioId,
      validatorIds: const <String>[keepaliveArtifactValidatorId],
      payload: payload,
    );
    final audit = auditSimsArtifactEvidence(
      evidence: evidence,
      expectedValidatorIds: const <String>[keepaliveArtifactValidatorId],
    );
    if (!audit.isValid) throw _CampaignFailure(audit.detail);
    return AndroidKeepaliveDropCampaignResult(0, <String, Object?>{
      'status': 'PASS',
      'assertionsAttempted': 6,
      'artifactPresent': true,
      'printOnly': false,
      'exitCode': 0,
      'detail':
          'Natural keepalive drop skipped the direct leg, gained sub-second '
          'custody, delivered once, re-armed, and restored both app states.',
      'artifactEvidence': evidence.toJson(),
    });
  }

  Future<Map<String, Object?>> _executeProof({
    required SimsRuntimeInvocation invocation,
    required String artifactSha256,
  }) async {
    await _launch(physical);
    await _launch(emulator);
    final sender = await _identity(physical);
    final receiver = await _identity(emulator);

    await _runConfig(physical, <String, Object?>{
      'stepId': 'keepalive-contact-${invocation.runId}',
      'add_contacts': <Object?>[
        <String, Object?>{
          'qrPayload': receiver.qrPayload,
          if (receiver.mlKemPublicKey != null)
            'mlKemPublicKey': receiver.mlKemPublicKey,
        },
      ],
      'send_contact_requests_for_added_contacts': true,
      'contact_settle_delay_ms': 1500,
    });
    await _runConfig(emulator, <String, Object?>{
      'stepId': 'keepalive-accept-${invocation.runId}',
      'contact_request_action': 'accept_all',
      'contact_settle_delay_ms': 1500,
    });
    await _runConfig(physical, <String, Object?>{
      'stepId': 'keepalive-open-${invocation.runId}',
      'open_conversation_with_peer_id': receiver.peerId,
      'open_conversation_retry_cycles': 16,
      'post_navigation_delay_ms': 1000,
    });
    await _requireForeground(physical);

    await _clearLogcat(physical);
    await _waitForTargetPing(
      physical,
      receiver.peerId,
      const Duration(seconds: 24),
    );
    await _clearLogcat(physical);
    await _forceStop(emulator);
    await _requireForeground(physical);

    final dropIndex = await _waitForEvent(
      physical,
      event: 'KEEPALIVE_PEER_DROP',
      afterIndex: -1,
      timeout: const Duration(seconds: 48),
    );
    final naturalDrop = await _validateNaturalDropWindow(
      physical,
      peerId: receiver.peerId,
      dropIndex: dropIndex,
    );
    final warmTerminal = await _waitForWarmTerminal(
      physical,
      afterIndex: dropIndex,
      timeout: const Duration(seconds: 16),
    );
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await _requireForeground(physical);

    final sendRequest = <String, Object?>{
      'schema': keepaliveDroppedSendRequestSchema,
      'profileId': _mainArtifactProfile,
      'scenario': keepaliveDropScenarioId,
      'role': 'sender',
      'transport_action': keepaliveDroppedSendAction,
      'runId': invocation.runId,
      'nonce': invocation.nonce,
      'stepId': keepaliveDroppedSendStepId(invocation.runId),
      'targetPeerId': receiver.peerId,
      'text': keepaliveRunMessageText(invocation.runId),
    };
    final requestFailure = validateKeepaliveDroppedSendRequest(
      sendRequest,
      installedProfileId: _mainArtifactProfile,
    );
    if (requestFailure != null) throw _CampaignFailure(requestFailure);
    final sendResult = await _runConfig(
      physical,
      sendRequest,
      timeout: const Duration(seconds: 45),
    );
    final sendFailure = validateKeepaliveDroppedSendResult(
      sendResult,
      invocation: invocation,
      targetPeerId: receiver.peerId,
    );
    if (sendFailure != null) throw _CampaignFailure(sendFailure);
    final messageId = sendResult['messageId']! as String;

    final recoveryRequest = <String, Object?>{
      'schema': keepaliveRecoveryRequestSchema,
      'profileId': _mainArtifactProfile,
      'scenario': keepaliveDropScenarioId,
      'role': 'sender',
      'transport_action': keepaliveRecoveryObserveAction,
      'runId': invocation.runId,
      'nonce': invocation.nonce,
      'stepId': keepaliveRecoveryStepId(invocation.runId),
      'targetPeerId': receiver.peerId,
      'messageId': messageId,
      'timeoutMs': 150000,
    };
    final recoveryFailure = validateKeepaliveRecoveryRequest(
      recoveryRequest,
      installedProfileId: _mainArtifactProfile,
    );
    if (recoveryFailure != null) throw _CampaignFailure(recoveryFailure);
    await _stageConfig(physical, recoveryRequest);
    await _waitForResult(
      physical,
      stepId: keepaliveRecoveryStepId(invocation.runId),
      expectedStatus: 'armed',
      runId: invocation.runId,
      nonce: invocation.nonce,
      expectedSchema: keepaliveRecoveryResultSchema,
      timeout: const Duration(seconds: 20),
    );

    final receiverStep = 'keepalive-receive-${invocation.runId}';
    await _stageConfig(emulator, <String, Object?>{
      'stepId': receiverStep,
      'expected_chat_messages': <Object?>[
        <String, Object?>{
          'contactPeerId': sender.peerId,
          'text': keepaliveRunMessageText(invocation.runId),
          'isIncoming': true,
        },
      ],
      'chat_poll_cycles': 240,
      'chat_poll_interval_ms': 500,
    });
    await _launch(emulator);
    final receiverResultFuture = _waitForResult(
      emulator,
      stepId: receiverStep,
      expectedStatus: 'complete',
      timeout: const Duration(seconds: 150),
    );
    final recoveryResultFuture = _waitForResult(
      physical,
      stepId: keepaliveRecoveryStepId(invocation.runId),
      expectedStatus: 'complete',
      runId: invocation.runId,
      nonce: invocation.nonce,
      expectedSchema: keepaliveRecoveryResultSchema,
      timeout: const Duration(seconds: 155),
    );
    final results = await Future.wait<Map<String, Object?>>(
      <Future<Map<String, Object?>>>[
        receiverResultFuture,
        recoveryResultFuture,
      ],
    );
    final receiverResult = results.first;
    final recoveryResult = results.last;
    _validateReceiverResult(
      receiverResult,
      senderPeerId: sender.peerId,
      messageId: messageId,
      text: keepaliveRunMessageText(invocation.runId),
    );
    final completedRecoveryFailure = validateKeepaliveRecoveryResult(
      recoveryResult,
      invocation: invocation,
      messageId: messageId,
    );
    if (completedRecoveryFailure != null) {
      throw _CampaignFailure(completedRecoveryFailure);
    }

    final artifact = assembleKeepaliveDropArtifact(
      sendResult: sendResult,
      recoveryResult: recoveryResult,
      deviceIds: <String>[physical, emulator],
    );
    return <String, Object?>{
      ...artifact,
      'recoveryWarmTerminal': warmTerminal,
      'receiverMessageIdMatched': true,
      'receiverMatchingCopies': 1,
      'naturalMissesObserved': naturalDrop.misses,
      'naturalProbeSpacingMs': naturalDrop.probeSpacingMs,
      'artifactSha256ObservedBeforeInstall': artifactSha256,
    };
  }

  void _validateReceiverResult(
    Map<String, Object?> result, {
    required String senderPeerId,
    required String messageId,
    required String text,
  }) {
    final chatExpectations = _jsonObject(result['chatExpectations']);
    final matched = chatExpectations['matched'];
    if (matched is! List || matched.length != 1) {
      throw const _CampaignFailure(
        'Receiver did not match exactly one run-bound message.',
      );
    }
    final match = _jsonObject(matched.single);
    if (match['contactPeerId'] != senderPeerId ||
        match['messageId'] != messageId ||
        match['text'] != text ||
        match['isIncoming'] != true) {
      throw const _CampaignFailure(
        'Receiver message did not correlate to the exact sender message ID.',
      );
    }
    final snapshot = _jsonObject(result['snapshot']);
    final conversations = snapshot['chatMessages'];
    if (conversations is! List) {
      throw const _CampaignFailure('Receiver message snapshot was malformed.');
    }
    var matchingCopies = 0;
    for (final rawConversation in conversations) {
      final conversation = _jsonObject(rawConversation);
      if (conversation['contactPeerId'] != senderPeerId) continue;
      final messages = conversation['messages'];
      if (messages is! List) continue;
      for (final rawMessage in messages) {
        final message = _jsonObject(rawMessage);
        if (message['id'] == messageId &&
            message['text'] == text &&
            message['isIncoming'] == true) {
          matchingCopies += 1;
        }
      }
    }
    if (matchingCopies != 1) {
      throw _CampaignFailure(
        'Receiver persisted $matchingCopies copies of the exact message.',
      );
    }
  }

  Future<void> _preflight() async {
    final version = await _adb(null, const <String>[
      'version',
    ], allowFailure: true);
    if (version.exitCode != 0) {
      throw const _CampaignBlocked('ADB is unavailable.');
    }
    for (final device in <String>[physical, emulator]) {
      final state = await _adb(device, const <String>[
        'get-state',
      ], allowFailure: true);
      if (state.exitCode != 0 || '${state.stdout}'.trim() != 'device') {
        throw _CampaignBlocked(
          'Android target $device is not ready.',
          blocker: 'targetUnavailable',
        );
      }
    }
    final physicalQemu = await _shellText(physical, const <String>[
      'getprop',
      'ro.kernel.qemu',
    ]);
    final emulatorQemu = await _shellText(emulator, const <String>[
      'getprop',
      'ro.kernel.qemu',
    ]);
    if (physicalQemu.trim() == '1' || emulatorQemu.trim() != '1') {
      throw const _CampaignBlocked(
        'Targets do not match physical-sender/emulator-receiver ordering.',
        blocker: 'targetUnavailable',
      );
    }
    if (!await _networkAvailable(physical) ||
        !await _networkAvailable(emulator)) {
      throw const _CampaignBlocked(
        'Both Android targets must begin with a usable network.',
      );
    }
  }

  Future<void> _installFresh(
    String device,
    String username,
    AndroidAppStateGuard stateGuard,
  ) async {
    await stateGuard.prepareFreshInstall(device: device, artifact: artifact);
    await _adb(device, <String>[
      'shell',
      'pm',
      'grant',
      packageName,
      'android.permission.POST_NOTIFICATIONS',
    ], allowFailure: true);
    await _writeAppFile(
      device,
      'auto_setup.json',
      jsonEncode(<String, Object?>{'username': username}),
    );
  }

  Future<_Identity> _identity(String device) async {
    final raw = await _waitForValue<String>(
      'main-app identity on $device',
      const Duration(seconds: 150),
      () => _readAppFile(device, _identityFile),
    );
    try {
      final decoded = _jsonObject(jsonDecode(raw));
      final qrPayload = decoded['qrPayload'] as String;
      final qr = _jsonObject(jsonDecode(qrPayload));
      final peerId = qr['ns'] as String;
      if (peerId.isEmpty || peerId.length > 160) throw const FormatException();
      return _Identity(
        peerId: peerId,
        qrPayload: qrPayload,
        mlKemPublicKey: decoded['mlKemPublicKey'] as String?,
      );
    } on Object {
      throw const _CampaignFailure('Main-app identity export was malformed.');
    }
  }

  Future<Map<String, Object?>> _runConfig(
    String device,
    Map<String, Object?> config, {
    Duration timeout = const Duration(seconds: 180),
  }) async {
    final stepId = config['stepId'];
    if (stepId is! String || stepId.isEmpty) {
      throw const _CampaignFailure('App config has no step ID.');
    }
    await _stageConfig(device, config);
    return _waitForResult(
      device,
      stepId: stepId,
      expectedStatus: 'complete',
      timeout: timeout,
    );
  }

  Future<void> _stageConfig(String device, Map<String, Object?> config) async {
    await _removeAppFile(device, _resultFile);
    await _removeAppFile(device, _configFile);
    await _writeAppFile(device, _configFile, jsonEncode(config));
  }

  Future<Map<String, Object?>> _waitForResult(
    String device, {
    required String stepId,
    required String expectedStatus,
    String? runId,
    String? nonce,
    String? expectedSchema,
    required Duration timeout,
  }) async {
    return _waitForValue<Map<String, Object?>>(
      '$stepId/$expectedStatus on $device',
      timeout,
      () async {
        final raw = await _readAppFile(device, _resultFile);
        if (raw == null) return null;
        try {
          final result = _jsonObject(jsonDecode(raw));
          if (result['stepId'] != stepId ||
              (runId != null && result['runId'] != runId) ||
              (nonce != null && result['nonce'] != nonce) ||
              (expectedSchema != null && result['schema'] != expectedSchema)) {
            return null;
          }
          if (result['status'] == 'failed' || result['success'] == false) {
            throw _CampaignFailure(
              'Production app step $stepId failed '
              '(${result['errorType'] ?? 'unknown'}).',
            );
          }
          if (result['status'] != expectedStatus || result['success'] != true) {
            return null;
          }
          return result;
        } on _CampaignFailure {
          rethrow;
        } on Object {
          return null;
        }
      },
    );
  }

  Future<void> _waitForTargetPing(
    String device,
    String peerId,
    Duration timeout,
  ) async {
    final prefix = peerId.length > 10 ? peerId.substring(0, 10) : peerId;
    await _waitFor(
      'a successful production peer ping',
      timeout,
      () async => (await _flowEvents(device)).any(
        (event) =>
            event.name == 'P2P_SERVICE_PEER_PING_SUCCESS' &&
            event.details['peerId'] == prefix,
      ),
    );
  }

  Future<int> _waitForEvent(
    String device, {
    required String event,
    required int afterIndex,
    required Duration timeout,
  }) => _waitForValue<int>(event, timeout, () async {
    final events = await _flowEvents(device);
    for (var index = afterIndex + 1; index < events.length; index += 1) {
      if (events[index].name == event) return index;
    }
    return null;
  });

  Future<String> _waitForWarmTerminal(
    String device, {
    required int afterIndex,
    required Duration timeout,
  }) => _waitForValue<String>(
    'terminal keepalive recovery warm',
    timeout,
    () async {
      final events = await _flowEvents(device);
      const directWarmTerminals = <String>{
        'P2P_SERVICE_WARM_PEER_DIAL_SKIPPED',
        'P2P_SERVICE_WARM_PEER_DEBOUNCED',
        'P2P_SERVICE_WARM_PEER_SKIPPED',
      };
      const dialOutcomes = <String>{
        'P2P_SERVICE_DIAL_PEER_SUCCESS',
        'P2P_SERVICE_DIAL_PEER_ERROR',
        'P2P_SERVICE_DIAL_PEER_EXCEPTION',
      };
      var recoveryDialStarted = false;
      for (var index = afterIndex + 1; index < events.length; index += 1) {
        final name = events[index].name;
        if (directWarmTerminals.contains(name)) return name;
        if (name == 'P2P_SERVICE_WARM_PEER_DIAL') {
          recoveryDialStarted = true;
          continue;
        }
        if (recoveryDialStarted && dialOutcomes.contains(name)) return name;
      }
      return null;
    },
  );

  Future<_NaturalDropObservation> _validateNaturalDropWindow(
    String device, {
    required String peerId,
    required int dropIndex,
  }) async {
    final events = await _flowEvents(device);
    if (dropIndex < 0 ||
        dropIndex >= events.length ||
        events[dropIndex].name != 'KEEPALIVE_PEER_DROP') {
      throw const _CampaignFailure('Keepalive drop window was unstable.');
    }
    final prefix = peerId.length > 10 ? peerId.substring(0, 10) : peerId;
    final begins = <_FlowEvent>[];
    var misses = 0;
    for (var index = 0; index < dropIndex; index += 1) {
      final event = events[index];
      if (event.details['peerId'] != prefix) continue;
      if (event.name == 'P2P_SERVICE_PEER_PING_BEGIN') begins.add(event);
      if (event.name == 'P2P_SERVICE_PEER_PING_FAILED' ||
          event.name == 'P2P_SERVICE_PEER_PING_EXCEPTION') {
        misses += 1;
      }
    }
    if (begins.length < 2 || misses < 2) {
      throw const _CampaignFailure(
        'Natural keepalive drop did not contain two real failed probes.',
      );
    }
    final spacing = begins.last.observedAt
        .difference(begins[begins.length - 2].observedAt)
        .inMilliseconds;
    // Probe starts, unlike completions, directly reflect the timer cadence.
    if (spacing < 7000) {
      throw _CampaignFailure(
        'Keepalive probes were only ${spacing}ms apart; the natural 8-second '
        'cadence was not observed.',
      );
    }
    return _NaturalDropObservation(misses: 2, probeSpacingMs: spacing);
  }

  Future<List<_FlowEvent>> _flowEvents(String device) async {
    final result = await _adb(device, const <String>[
      'logcat',
      '-d',
      '-v',
      'raw',
      '-t',
      '4000',
    ], allowFailure: true);
    if (result.exitCode != 0) {
      throw const _CampaignFailure('Android flow-event log could not be read.');
    }
    final events = <_FlowEvent>[];
    for (final line in '${result.stdout}'.split('\n')) {
      final marker = line.indexOf('[FLOW] ');
      if (marker < 0) continue;
      final encoded = line.substring(marker + '[FLOW] '.length).trim();
      try {
        final payload = _jsonObject(jsonDecode(encoded));
        final name = payload['event'];
        final observedAt = DateTime.tryParse('${payload['ts']}');
        if (name is! String || name.isEmpty || observedAt == null) continue;
        final rawDetails = payload['details'];
        final details = rawDetails is Map
            ? rawDetails.map<String, Object?>(
                (key, value) => MapEntry('$key', value),
              )
            : const <String, Object?>{};
        events.add(_FlowEvent(name, details, observedAt.toUtc()));
      } on Object {
        // Ignore unrelated/truncated log lines; required events still fail
        // closed through the bounded wait above.
      }
    }
    return events;
  }

  Future<void> _clearLogcat(String device) async {
    final result = await _adb(device, const <String>[
      'logcat',
      '-c',
    ], allowFailure: true);
    if (result.exitCode != 0) {
      throw const _CampaignFailure('Android log window could not be reset.');
    }
  }

  Future<bool> _networkAvailable(String device) async {
    final dump = await _shellText(device, const <String>[
      'dumpsys',
      'connectivity',
    ]);
    final match = RegExp(
      r'Active default network:\s*([^\r\n]+)',
      caseSensitive: false,
    ).firstMatch(dump);
    if (match == null) return false;
    final value = match.group(1)!.trim().toLowerCase();
    return value != 'none' && value != 'null' && value != '-1';
  }

  Future<String> _hostFileSha256(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  Future<void> _launch(String device, {bool forceStopFirst = true}) async {
    if (forceStopFirst) await _forceStop(device);
    final result = await _adb(device, <String>[
      'shell',
      'am',
      'start',
      '-W',
      '-n',
      '$packageName/.MainActivity',
    ], allowFailure: true);
    if (result.exitCode != 0 || '${result.stdout}'.contains('Error:')) {
      throw _CampaignFailure('App launch failed on $device.');
    }
  }

  Future<void> _forceStop(String device) async {
    final result = await _adb(device, <String>[
      'shell',
      'am',
      'force-stop',
      packageName,
    ], allowFailure: true);
    if (result.exitCode != 0) {
      throw _CampaignFailure('App process could not be stopped on $device.');
    }
  }

  Future<void> _requireForeground(String device) async {
    final dump = await _shellText(device, const <String>[
      'dumpsys',
      'activity',
      'activities',
    ]);
    final foreground = dump
        .split('\n')
        .where(
          (line) =>
              line.contains('ResumedActivity') ||
              line.contains('topResumedActivity'),
        )
        .any((line) => line.contains(packageName));
    if (!foreground) {
      throw const _CampaignFailure(
        'Sender was not foreground during the keepalive window.',
      );
    }
  }

  Future<String?> _readAppFile(String device, String name) async {
    final result = await _adb(device, <String>[
      'shell',
      'run-as',
      packageName,
      'cat',
      'app_flutter/$name',
    ], allowFailure: true);
    if (result.exitCode != 0 || '${result.stdout}'.trim().isEmpty) return null;
    return '${result.stdout}'.trim();
  }

  Future<void> _writeAppFile(
    String device,
    String name,
    String contents,
  ) async {
    final local = File(
      '${Directory.systemTemp.path}/${_token('config')}-$name',
    );
    local.writeAsStringSync(contents, flush: true);
    final remote = '/data/local/tmp/${_token('keepalive')}-$name';
    try {
      await _adb(device, <String>['push', local.path, remote]);
      await _adb(device, <String>[
        'shell',
        'run-as',
        packageName,
        'mkdir',
        '-p',
        'app_flutter',
      ]);
      await _adb(device, <String>[
        'shell',
        'run-as',
        packageName,
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

  Future<void> _removeAppFile(String device, String name) async {
    await _adb(device, <String>[
      'shell',
      'run-as',
      packageName,
      'rm',
      '-f',
      'app_flutter/$name',
    ], allowFailure: true);
  }

  Future<String> _shellText(
    String device,
    List<String> command, {
    bool allowFailure = false,
  }) async {
    final result = await _adb(device, <String>[
      'shell',
      ...command,
    ], allowFailure: allowFailure);
    return '${result.stdout}';
  }

  Future<ProcessResult> _adb(
    String? device,
    List<String> arguments, {
    bool allowFailure = false,
  }) async {
    late final ProcessResult result;
    try {
      result = await Process.run('adb', <String>[
        if (device != null) ...<String>['-s', device],
        ...arguments,
      ]);
    } on ProcessException {
      if (allowFailure) return ProcessResult(0, 127, '', '');
      throw const _CampaignBlocked('ADB could not start.');
    }
    if (!allowFailure && result.exitCode != 0) {
      throw const _CampaignFailure('An ADB campaign operation failed.');
    }
    return result;
  }

  Future<void> _waitFor(
    String label,
    Duration timeout,
    Future<bool> Function() check,
  ) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await check()) return;
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    throw _CampaignFailure('Timed out waiting for $label.');
  }

  Future<T> _waitForValue<T>(
    String label,
    Duration timeout,
    Future<T?> Function() read,
  ) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final value = await read();
      if (value != null) return value;
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    throw _CampaignFailure('Timed out waiting for $label.');
  }

  String _token(String prefix) {
    final bytes = List<int>.generate(12, (_) => _random.nextInt(256));
    return '$prefix-${base64Url.encode(bytes).replaceAll('=', '')}';
  }
}

final class _Identity {
  const _Identity({
    required this.peerId,
    required this.qrPayload,
    required this.mlKemPublicKey,
  });

  final String peerId;
  final String qrPayload;
  final String? mlKemPublicKey;
}

final class _FlowEvent {
  const _FlowEvent(this.name, this.details, this.observedAt);

  final String name;
  final Map<String, Object?> details;
  final DateTime observedAt;
}

final class _NaturalDropObservation {
  const _NaturalDropObservation({
    required this.misses,
    required this.probeSpacingMs,
  });

  final int misses;
  final int probeSpacingMs;
}

Map<String, Object?> _jsonObject(Object? value) {
  if (value is! Map) throw const FormatException('expected JSON object');
  return value.map<String, Object?>((key, item) => MapEntry('$key', item));
}

AndroidKeepaliveDropCampaignResult _blocked(
  String detail, {
  required String blocker,
  required bool artifactPresent,
}) => AndroidKeepaliveDropCampaignResult(78, <String, Object?>{
  'status': 'BLOCKED',
  'assertionsAttempted': 0,
  'artifactPresent': artifactPresent,
  'printOnly': false,
  'blocker': blocker,
  'exitCode': 78,
  'detail': detail,
});

AndroidKeepaliveDropCampaignResult _failed(
  String detail, {
  required bool artifactPresent,
}) => AndroidKeepaliveDropCampaignResult(1, <String, Object?>{
  'status': 'FAIL',
  'assertionsAttempted': 6,
  'artifactPresent': artifactPresent,
  'printOnly': false,
  'blocker': 'test',
  'exitCode': 1,
  'detail': detail,
});

final class _CampaignBlocked implements Exception {
  const _CampaignBlocked(this.detail, {this.blocker = 'environment'});

  final String detail;
  final String blocker;
}

final class _CampaignFailure implements Exception {
  const _CampaignFailure(this.detail);

  final String detail;
}
