#!/usr/bin/env dart

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/debug/private_media_outbox_e2e.dart';

import '../../tool/sims/artifact_evidence.dart';
import '../../tool/sims/device_criteria.dart';
import '../support/android_app_state_guard.dart';
import '_android_app_package.dart';

const String _capabilityId = privateMediaOutboxE2EScenario;
const String _validatorId = 'validatePrivateMediaOutboxRestoreArtifact';
const String _artifactEnvironment = 'SIMS_ARTIFACT_ANDROID_E2E_MAIN';
const String _physicalEnvironment = 'SIMS_ANDROID_PHYSICAL_DEVICE_ID';
const String _emulatorEnvironment = 'SIMS_ANDROID_EMULATOR_DEVICE_ID';
const Duration _endpointTimeout = Duration(minutes: 4);

Future<void> main() async {
  _Result result;
  try {
    result = await _Campaign.fromEnvironment().run();
  } on _Blocked catch (error) {
    result = _Result.blocked(error.detail);
  } on _Failure catch (error) {
    result = _Result.fail(error.detail);
  } on Object {
    result = _Result.fail(
      'Private-media outbox campaign failed in the host harness.',
    );
  }
  stdout.writeln('SIMS_RESULT_JSON=${jsonEncode(result.json)}');
  exitCode = result.exitCode;
}

final class _Campaign {
  _Campaign({
    required this.artifact,
    required this.physical,
    required this.emulator,
    required this.packageName,
    required this.proofDirectory,
  });

  factory _Campaign.fromEnvironment() {
    String requiredValue(String name) {
      final value = Platform.environment[name]?.trim();
      if (value == null || value.isEmpty) {
        throw _Blocked('Required sims binding $name is unavailable.');
      }
      return value;
    }

    final artifact = File(requiredValue(_artifactEnvironment)).absolute;
    if (FileSystemEntity.typeSync(artifact.path, followLinks: true) !=
        FileSystemEntityType.file) {
      throw const _Blocked('The centrally prepared main-app APK is missing.');
    }
    final physical = requiredValue(_physicalEnvironment);
    final emulator = requiredValue(_emulatorEnvironment);
    final safeTarget = RegExp(r'^[A-Za-z0-9._:-]{1,160}$');
    if (!safeTarget.hasMatch(physical) ||
        !safeTarget.hasMatch(emulator) ||
        physical == emulator ||
        physical.startsWith('emulator-') ||
        !emulator.startsWith('emulator-')) {
      throw const _Blocked(
        'Private-media outbox proof requires one explicit physical Android '
        'control target and one distinct Android emulator target.',
      );
    }
    final proofPath = Platform.environment['SIMS_PROOF_DIRECTORY']?.trim();
    return _Campaign(
      artifact: artifact,
      physical: physical,
      emulator: emulator,
      packageName: resolveAndroidAppPackage(),
      proofDirectory: Directory(
        proofPath == null || proofPath.isEmpty
            ? 'build/sims/proofs/$_capabilityId'
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
  final Set<String> _issuedMessageIds = <String>{};

  Future<_Result> run() async {
    await _preflight();
    final apkSha256 = sha256.convert(artifact.readAsBytesSync()).toString();
    final originalPhysicalNetwork = await _NetworkState.capture(this, physical);
    var physicalNetworkMutated = false;
    late final AndroidAppStateGuard stateGuard;
    try {
      stateGuard = await AndroidAppStateGuard.capture(
        devices: <String>[physical, emulator],
        packageName: packageName,
        backupLabel: 'private-media-outbox',
      );
    } on AndroidAppStateBlocked catch (error) {
      throw _Blocked(error.detail);
    } on AndroidAppStateFailure catch (error) {
      throw _Failure(error.detail);
    }

    late final Map<String, Object?> acceptedArtifact;
    try {
      // One centrally prepared APK is reused on both explicit Android targets.
      // This host runner never starts a nested Flutter build.
      await _installFresh(physical, 'sims-private-media-sender', stateGuard);
      await _installFresh(emulator, 'sims-private-media-receiver', stateGuard);
      await _launch(physical);
      await _launch(emulator);

      final senderIdentity = await _identity(physical);
      final receiverIdentity = await _identity(emulator);
      final setupRun = _token('setup');
      await _runGenericConfig(physical, <String, Object?>{
        'stepId': 'private-media-contacts-$setupRun',
        'add_contacts': <Object?>[
          <String, Object?>{
            'qrPayload': receiverIdentity.qrPayload,
            if (receiverIdentity.mlKemPublicKey != null)
              'mlKemPublicKey': receiverIdentity.mlKemPublicKey,
          },
        ],
        'send_contact_requests_for_added_contacts': true,
        'contact_settle_delay_ms': 2000,
      });
      await _runGenericConfig(emulator, <String, Object?>{
        'stepId': 'private-media-accept-$setupRun',
        'contact_request_action': 'accept_all',
        'contact_settle_delay_ms': 2500,
      });

      final phases = <Map<String, Object?>>[];
      for (final phase in const <int>[1, 2]) {
        final result = await _runPhase(
          phase: phase,
          senderPeerId: senderIdentity.peerId,
          receiverPeerId: receiverIdentity.peerId,
          markNetworkMutated: () => physicalNetworkMutated = true,
        );
        phases.add(result);
      }

      acceptedArtifact = <String, Object?>{
        'schemaVersion': 1,
        'scenario': _capabilityId,
        'status': 'passed',
        'physicalSenderTargetSha256': privateMediaOutboxTargetSha256(
          role: privateMediaOutboxPhysicalSenderTargetRole,
          adbTargetId: physical,
        ),
        'emulatorReceiverTargetSha256': privateMediaOutboxTargetSha256(
          role: privateMediaOutboxEmulatorReceiverTargetRole,
          adbTargetId: emulator,
        ),
        'phases': phases,
      };
      final validation = validatePrivateMediaOutboxRestoreArtifact(
        acceptedArtifact,
      );
      if (!validation.ok) throw _Failure(validation.detail);
    } on AndroidAppStateFailure catch (error) {
      throw _Failure(error.detail);
    } finally {
      var networkRestoreFailed = false;
      if (physicalNetworkMutated) {
        try {
          await originalPhysicalNetwork.restore(this, physical);
        } on Object {
          networkRestoreFailed = true;
        }
      }
      try {
        await stateGuard.restoreAll();
      } on AndroidAppStateFailure catch (error) {
        throw _Failure(error.detail);
      }
      if (networkRestoreFailed) {
        throw const _Failure(
          'The physical Android network state could not be restored exactly.',
        );
      }
    }

    final evidence = _writeExactArtifact(acceptedArtifact);
    final audit = auditSimsArtifactEvidence(
      evidence: evidence,
      expectedValidatorIds: const <String>[_validatorId],
    );
    if (!audit.isValid) throw _Failure(audit.detail);
    final decoded = _object(
      jsonDecode(File(audit.canonicalPath!).readAsStringSync()),
    );
    final durableValidation = validatePrivateMediaOutboxRestoreArtifact(
      decoded,
    );
    if (!durableValidation.ok) throw _Failure(durableValidation.detail);
    return _Result.pass(evidence, apkSha256: apkSha256);
  }

  Future<Map<String, Object?>> _runPhase({
    required int phase,
    required String senderPeerId,
    required String receiverPeerId,
    required void Function() markNetworkMutated,
  }) async {
    if (!await _networkAvailable(physical) ||
        !await _networkAvailable(emulator)) {
      throw _Failure('Both Android peers must be online before phase $phase.');
    }
    final runId = _token('phase$phase');
    final nonce = _token('nonce');
    final messageId = _exactMessageId();
    final attachmentId = _token('attachment');
    final senderRequest = PrivateMediaOutboxE2ERequest(
      role: privateMediaOutboxSenderRole,
      phase: phase,
      runId: runId,
      nonce: nonce,
      contactPeerId: receiverPeerId,
      messageId: messageId,
      attachmentId: attachmentId,
      timeout: _endpointTimeout,
    );
    final receiverRequest = PrivateMediaOutboxE2ERequest(
      role: privateMediaOutboxReceiverRole,
      phase: phase,
      runId: runId,
      nonce: nonce,
      contactPeerId: senderPeerId,
      messageId: messageId,
      attachmentId: attachmentId,
      timeout: _endpointTimeout,
    );

    await _stagePrivateRequest(emulator, receiverRequest);
    await _waitForPrivateReceipt(
      emulator,
      request: receiverRequest,
      expectedStatus: 'armed',
      timeout: const Duration(seconds: 45),
    );
    await _requireForeground(emulator, role: 'receiver');
    await _requireForeground(physical, role: 'sender');

    await _stagePrivateRequest(physical, senderRequest);
    await _waitForPrivateReceipt(
      physical,
      request: senderRequest,
      expectedStatus: 'armed',
      timeout: const Duration(seconds: 45),
    );

    markNetworkMutated();
    await _setNetworkAvailable(physical, false);
    await _waitFor(
      'physical Android offline state for phase $phase',
      const Duration(seconds: 30),
      () => _networkAvailable(physical).then((available) => !available),
    );
    if (!await _networkAvailable(emulator)) {
      throw const _Failure(
        'The emulator receiver lost network during sender isolation.',
      );
    }

    await _releasePrivateMediaSender(physical, senderRequest);
    final queued = await _waitForPrivateReceipt(
      physical,
      request: senderRequest,
      expectedStatus: 'queued',
      timeout: const Duration(minutes: 3),
    );

    Map<String, Object?>? resumedQueued;
    if (phase == 2) {
      await _adb(physical, const <String>[
        'shell',
        'input',
        'keyevent',
        'KEYCODE_HOME',
      ]);
      await _waitFor(
        'physical Android background state',
        const Duration(seconds: 15),
        () => _isForeground(physical).then((foreground) => !foreground),
      );
      await Future<void>.delayed(const Duration(seconds: 31));
      if (await _networkAvailable(physical)) {
        throw const _Failure(
          'The physical sender regained network during the offline dwell.',
        );
      }
      // Contract: adb shell 'am' 'start' resumes MainActivity before restore.
      await _launch(physical);
      await _requireForeground(physical, role: 'sender');
      resumedQueued = await _waitForPrivateReceipt(
        physical,
        request: senderRequest,
        expectedStatus: 'resumed_queued',
        timeout: const Duration(seconds: 45),
      );
      if (await _networkAvailable(physical)) {
        throw const _Failure(
          'Phase two resume was not observed while the sender was offline.',
        );
      }
    }

    // From this restore onward the host performs no UI input, navigation, or
    // app launch. Only read-only polling observes production completion.
    await _setNetworkAvailable(physical, true);
    await _waitFor(
      'physical Android restored state for phase $phase',
      const Duration(seconds: 45),
      () => _networkAvailable(physical),
    );
    final senderComplete = await _waitForPrivateReceipt(
      physical,
      request: senderRequest,
      expectedStatus: 'complete',
      timeout: _endpointTimeout,
    );
    final receiverComplete = await _waitForPrivateReceipt(
      emulator,
      request: receiverRequest,
      expectedStatus: 'complete',
      timeout: _endpointTimeout,
    );

    return _buildPhaseArtifact(
      phase: phase,
      request: senderRequest,
      queued: queued,
      resumedQueued: resumedQueued,
      senderComplete: senderComplete,
      receiverComplete: receiverComplete,
    );
  }

  Map<String, Object?> _buildPhaseArtifact({
    required int phase,
    required PrivateMediaOutboxE2ERequest request,
    required Map<String, Object?> queued,
    required Map<String, Object?>? resumedQueued,
    required Map<String, Object?> senderComplete,
    required Map<String, Object?> receiverComplete,
  }) {
    final rawSenderEvents = _eventObjects(senderComplete['events']);
    final triggerIndex = rawSenderEvents.indexWhere(
      (event) => event['event'] == privateMediaOutboxNetworkRestoredEvent,
    );
    if (triggerIndex < 0) {
      throw _Failure('Phase $phase did not report the restored trigger.');
    }
    final attemptsBeforeRestore = rawSenderEvents
        .take(triggerIndex)
        .where(
          (event) =>
              event['event'] == privateMediaOutboxEncryptionPreparedEvent ||
              event['event'] == privateMediaOutboxUploadStartEvent,
        )
        .length;
    if (attemptsBeforeRestore != 0) {
      throw _Failure(
        'Phase $phase issued a media attempt while resumed offline.',
      );
    }

    const senderNames = <String>[
      privateMediaOutboxNetworkRestoredEvent,
      privateMediaOutboxLeaseClaimedEvent,
      privateMediaOutboxEncryptionPreparedEvent,
      privateMediaOutboxUploadStartEvent,
      privateMediaOutboxSendSuccessEvent,
    ];
    if (rawSenderEvents.length != senderNames.length) {
      throw _Failure(
        'Phase $phase sender returned an unexpected correlated event window.',
      );
    }
    final senderEvents = <_EventEvidence>[];
    for (var index = 0; index < senderNames.length; index++) {
      senderEvents.add(
        _EventEvidence.parse(
          rawSenderEvents[index],
          expectedEvent: senderNames[index],
          expectedRunHash: request.runCorrelationSha256,
          expectedAttachmentHash: request.attachmentIdHash,
        ),
      );
      if (index > 0 &&
          senderEvents[index].timestampMs <
              senderEvents[index - 1].timestampMs) {
        throw _Failure('Phase $phase sender event timestamps are not causal.');
      }
    }

    final rawReceiverEvents = _eventObjects(receiverComplete['events']);
    if (rawReceiverEvents.length != 1) {
      throw _Failure(
        'Phase $phase receiver returned an unexpected delivery event window.',
      );
    }
    final receiverEvent = _EventEvidence.parse(
      rawReceiverEvents.single,
      expectedEvent: privateMediaOutboxReceivedEvent,
      expectedRunHash: request.runCorrelationSha256,
      expectedAttachmentHash: request.attachmentIdHash,
    );
    final trigger = senderEvents[0];
    final uploadStart = senderEvents[3];
    final latency = uploadStart.timestampMs - trigger.timestampMs;
    if (latency < 0) {
      throw _Failure('Phase $phase restore latency was negative.');
    }

    final initialEncryptionCount = queued['encryptionPreparedCount'] as int;
    final initialUploadCount = queued['uploadRequestCount'] as int;
    final postRestoreEncryptionCount = senderEvents
        .where(
          (event) => event.event == privateMediaOutboxEncryptionPreparedEvent,
        )
        .length;
    final postRestoreUploadCount = senderEvents
        .where((event) => event.event == privateMediaOutboxUploadStartEvent)
        .length;
    final causalEvents = <Map<String, Object?>>[
      for (var index = 0; index < senderEvents.length; index++)
        senderEvents[index].toArtifact(includeAttachment: index != 0),
      receiverEvent.toArtifact(),
    ];

    return <String, Object?>{
      'phase': phase,
      'runCorrelationSha256': request.runCorrelationSha256,
      'attachmentSha256': request.attachmentIdHash,
      'queuedNoRed': queued['queuedNoRed'] == true,
      'pauseResumeRemainedQueued': phase == 2
          ? resumedQueued!['pauseResumeRemainedQueued'] == true
          : false,
      'offlineResumeAttemptCount': phase == 2
          ? resumedQueued!['offlineResumeAttemptCount']
          : 0,
      'zeroPostRestoreUiActions': true,
      'receiverExactMediaDelivered': true,
      'encryptionPreparedCount':
          initialEncryptionCount + postRestoreEncryptionCount,
      'uploadRequestCount': initialUploadCount + postRestoreUploadCount,
      'envelopeCount': senderEvents
          .where((event) => event.event == privateMediaOutboxSendSuccessEvent)
          .length,
      'receiveCount': 1,
      'networkRestoredClaimCount': senderEvents
          .where((event) => event.event == privateMediaOutboxLeaseClaimedEvent)
          .length,
      'postRestoreEncryptionCount': postRestoreEncryptionCount,
      'postRestoreUploadCount': postRestoreUploadCount,
      'restoreRetryLatencyMs': latency,
      'events': causalEvents,
    };
  }

  Future<void> _preflight() async {
    final version = await _adb(null, const <String>[
      'version',
    ], allowFailure: true);
    if (version.exitCode != 0) {
      throw const _Blocked(
        'ADB is unavailable for the private-media outbox campaign.',
      );
    }
    for (final device in <String>[physical, emulator]) {
      final state = await _adb(device, const <String>[
        'get-state',
      ], allowFailure: true);
      if (state.exitCode != 0 || '${state.stdout}'.trim() != 'device') {
        throw _Blocked('Android target $device is not ready.');
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
      throw const _Blocked(
        'Live Android targets do not match physical-sender/emulator-receiver.',
      );
    }
    if (!await _networkAvailable(physical) ||
        !await _networkAvailable(emulator)) {
      throw const _Blocked(
        'Both selected Android targets must begin with a usable network.',
      );
    }
  }

  Future<void> _installFresh(
    String device,
    String username,
    AndroidAppStateGuard stateGuard,
  ) async {
    await stateGuard.prepareFreshInstall(device: device, artifact: artifact);
    await _writeAppFile(
      device,
      'auto_setup.json',
      jsonEncode(<String, Object?>{'username': username}),
    );
  }

  Future<void> _launch(String device) async {
    final result = await _adb(device, <String>[
      'shell',
      'am',
      'start',
      '-W',
      '-n',
      '$packageName/.MainActivity',
    ], allowFailure: true);
    final output = '${result.stdout}\n${result.stderr}';
    if (result.exitCode != 0 ||
        !RegExp(
          r'^Status:[ \t]+ok[ \t]*\r?$',
          multiLine: true,
        ).hasMatch(output)) {
      throw _Failure('App launch failed on $device.');
    }
  }

  Future<_Identity> _identity(String device) async {
    final raw = await _waitForValue<String>(
      'main-app identity export',
      const Duration(seconds: 120),
      () => _readAppFile(device, 'intro_e2e_identity.json'),
    );
    try {
      final decoded = _object(jsonDecode(raw));
      final qrPayload = decoded['qrPayload'] as String;
      final qr = _object(jsonDecode(qrPayload));
      final peerId = qr['ns'] as String;
      if (peerId.isEmpty) throw const FormatException();
      return _Identity(
        peerId: peerId,
        qrPayload: qrPayload,
        mlKemPublicKey: decoded['mlKemPublicKey'] as String?,
      );
    } on Object {
      throw const _Failure('Main-app identity export was malformed.');
    }
  }

  Future<Map<String, Object?>> _runGenericConfig(
    String device,
    Map<String, Object?> config,
  ) async {
    final stepId = config['stepId'] as String;
    await _stageConfig(device, config);
    final raw = await _waitForValue<String>(
      '$stepId/complete',
      const Duration(seconds: 180),
      () async {
        final value = await _readAppFile(device, 'intro_e2e_result.json');
        if (value == null) return null;
        try {
          final result = _object(jsonDecode(value));
          if (result['stepId'] != stepId || result['status'] != 'complete') {
            return null;
          }
          return value;
        } on Object {
          return null;
        }
      },
    );
    final result = _object(jsonDecode(raw));
    if (result['success'] != true) {
      throw _Failure('Production setup step $stepId did not succeed.');
    }
    return result;
  }

  Future<void> _stagePrivateRequest(
    String device,
    PrivateMediaOutboxE2ERequest request,
  ) async {
    await _removeAppFile(device, privateMediaOutboxE2EHostReleaseFileName);
    await _stageConfig(device, <String, Object?>{
      'schema': privateMediaOutboxE2ERequestSchema,
      'transport_action': privateMediaOutboxE2EAction,
      'scenario': privateMediaOutboxE2EScenario,
      'role': request.role,
      'phase': request.phase,
      'runId': request.runId,
      'nonce': request.nonce,
      'stepId': request.stepId,
      'contactPeerId': request.contactPeerId,
      'messageId': request.messageId,
      'attachmentId': request.attachmentId,
      'timeoutMs': request.timeout.inMilliseconds,
    });
  }

  Future<void> _releasePrivateMediaSender(
    String device,
    PrivateMediaOutboxE2ERequest request,
  ) => _writeAppFile(
    device,
    privateMediaOutboxE2EHostReleaseFileName,
    jsonEncode(privateMediaOutboxE2EHostRelease(request)),
  );

  Future<Map<String, Object?>> _waitForPrivateReceipt(
    String device, {
    required PrivateMediaOutboxE2ERequest request,
    required String expectedStatus,
    required Duration timeout,
  }) async {
    return _waitForValue<Map<String, Object?>>(
      '${request.stepId}/$expectedStatus',
      timeout,
      () async {
        final raw = await _readAppFile(device, 'intro_e2e_result.json');
        if (raw == null) return null;
        Map<String, Object?> result;
        try {
          result = _object(jsonDecode(raw));
        } on Object {
          return null;
        }
        if (result['schema'] != privateMediaOutboxE2EEndpointResultSchema ||
            result['stepId'] != request.stepId ||
            result['runId'] != request.runId ||
            result['nonce'] != request.nonce) {
          return null;
        }
        if (result['status'] == 'failed') {
          throw _Failure(
            'Production private-media endpoint failed in phase '
            '${request.phase}/${request.role}.',
          );
        }
        if (result['status'] != expectedStatus) return null;
        _validatePrivateReceipt(
          result,
          request: request,
          expectedStatus: expectedStatus,
        );
        return result;
      },
    );
  }

  void _validatePrivateReceipt(
    Map<String, Object?> result, {
    required PrivateMediaOutboxE2ERequest request,
    required String expectedStatus,
  }) {
    const baseKeys = <String>{
      'schema',
      'status',
      'success',
      'scenario',
      'buildProfile',
      'role',
      'phase',
      'stepId',
      'runId',
      'nonce',
      'runCorrelationSha256',
      'messageIdHash',
      'attachmentIdHash',
    };
    final expectedKeys = <String>{
      ...baseKeys,
      if (expectedStatus == 'queued') ...<String>{
        'queuedNoRed',
        'encryptionPreparedCount',
        'uploadRequestCount',
      },
      if (expectedStatus == 'resumed_queued') ...<String>{
        'queuedNoRed',
        'offlineResumeAttemptCount',
        'pauseResumeRemainedQueued',
      },
      if (expectedStatus == 'complete') 'events',
    };
    if (result.keys.toSet().difference(expectedKeys).isNotEmpty ||
        expectedKeys.difference(result.keys.toSet()).isNotEmpty ||
        result['schema'] != privateMediaOutboxE2EEndpointResultSchema ||
        result['status'] != expectedStatus ||
        result['success'] != true ||
        result['scenario'] != privateMediaOutboxE2EScenario ||
        result['buildProfile'] != privateMediaOutboxE2EBuildProfile ||
        result['role'] != request.role ||
        result['phase'] != request.phase ||
        result['stepId'] != request.stepId ||
        result['runId'] != request.runId ||
        result['nonce'] != request.nonce ||
        result['runCorrelationSha256'] != request.runCorrelationSha256 ||
        result['messageIdHash'] != request.messageIdHash ||
        result['attachmentIdHash'] != request.attachmentIdHash) {
      throw _Failure(
        'Private-media endpoint receipt failed safe binding checks for '
        '${request.role}/$expectedStatus.',
      );
    }
    if (expectedStatus == 'queued' &&
        (result['queuedNoRed'] != true ||
            result['encryptionPreparedCount'] != 1 ||
            result['uploadRequestCount'] != 1)) {
      throw _Failure(
        'Phase ${request.phase} did not prove one queued, non-red attempt.',
      );
    }
    if (expectedStatus == 'resumed_queued' &&
        (result['queuedNoRed'] != true ||
            result['offlineResumeAttemptCount'] != 0 ||
            result['pauseResumeRemainedQueued'] != true)) {
      throw _Failure(
        'Phase ${request.phase} did not remain queued across offline resume.',
      );
    }
  }

  Future<void> _stageConfig(String device, Map<String, Object?> config) async {
    await _removeAppFile(device, 'intro_e2e_result.json');
    await _removeAppFile(device, 'intro_e2e_config.json');
    await _writeAppFile(device, 'intro_e2e_config.json', jsonEncode(config));
  }

  Future<void> _requireForeground(String device, {required String role}) async {
    if (!await _isForeground(device)) {
      throw _Failure(
        'Private-media $role was not foreground in the required proof window.',
      );
    }
  }

  Future<bool> _isForeground(String device) async {
    final dump = await _shellText(device, const <String>[
      'dumpsys',
      'activity',
      'activities',
    ]);
    final foregroundLines = dump
        .split('\n')
        .where(
          (line) =>
              line.contains('ResumedActivity') ||
              line.contains('topResumedActivity'),
        )
        .join('\n');
    return foregroundLines.contains(packageName);
  }

  Future<void> _setNetworkAvailable(String device, bool available) async {
    await _adb(device, <String>[
      'shell',
      'cmd',
      'connectivity',
      'airplane-mode',
      available ? 'disable' : 'enable',
    ]);
    await _adb(device, <String>[
      'shell',
      'svc',
      'wifi',
      available ? 'enable' : 'disable',
    ], allowFailure: true);
    await _adb(device, <String>[
      'shell',
      'svc',
      'data',
      available ? 'enable' : 'disable',
    ], allowFailure: true);
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
    if (match == null) {
      throw const _Blocked(
        'Android connectivity service did not expose active-network state.',
      );
    }
    final value = match.group(1)!.trim().toLowerCase();
    return value != 'none' && value != 'null' && value != '-1';
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
      '${Directory.systemTemp.path}/sims-${_token('file')}-$name',
    );
    local.writeAsStringSync(contents, flush: true);
    final remote = '/data/local/tmp/sims-private-media-$name';
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

  Future<String> _shellText(String device, List<String> command) async {
    final result = await _adb(device, <String>['shell', ...command]);
    return '${result.stdout}';
  }

  Future<ProcessResult> _adb(
    String? device,
    List<String> arguments, {
    bool allowFailure = false,
  }) async {
    final result = await Process.run('adb', <String>[
      if (device != null) ...<String>['-s', device],
      ...arguments,
    ]);
    if (!allowFailure && result.exitCode != 0) {
      throw const _Failure('An ADB private-media campaign operation failed.');
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
    throw _Failure('Timed out waiting for $label.');
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
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw _Failure('Timed out waiting for $label.');
  }

  SimsArtifactEvidence _writeExactArtifact(
    Map<String, Object?> acceptedArtifact,
  ) {
    proofDirectory.createSync(recursive: true);
    final safeCapability = _capabilityId.replaceAll(
      RegExp(r'[^A-Za-z0-9_.-]'),
      '_',
    );
    final token = '${DateTime.now().toUtc().microsecondsSinceEpoch}-$pid';
    final file = File('${proofDirectory.path}/$safeCapability-$token.json');
    final temporary = File('${file.path}.tmp');
    if (temporary.existsSync()) temporary.deleteSync();
    temporary.writeAsStringSync(
      '${jsonEncode(acceptedArtifact)}\n',
      flush: true,
    );
    if (file.existsSync()) file.deleteSync();
    temporary.renameSync(file.path);
    final canonicalPath = file.resolveSymbolicLinksSync();
    final digest = sha256
        .convert(File(canonicalPath).readAsBytesSync())
        .toString();
    return SimsArtifactEvidence(
      path: canonicalPath,
      sha256Digest: digest,
      validatorIds: const <String>[_validatorId],
    );
  }

  String _token(String prefix) {
    final bytes = List<int>.generate(12, (_) => _random.nextInt(256));
    return '$prefix-${base64Url.encode(bytes).replaceAll('=', '')}';
  }

  String _exactMessageId() {
    while (true) {
      final candidate = List<int>.generate(
        4,
        (_) => _random.nextInt(256),
      ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
      if (_issuedMessageIds.add(candidate)) return candidate;
    }
  }
}

final class _EventEvidence {
  const _EventEvidence({
    required this.event,
    required this.runCorrelationSha256,
    required this.attachmentSha256,
    required this.timestampMs,
    this.source,
  });

  factory _EventEvidence.parse(
    Map<String, Object?> value, {
    required String expectedEvent,
    required String expectedRunHash,
    required String expectedAttachmentHash,
  }) {
    final expectsSource = expectedEvent == privateMediaOutboxLeaseClaimedEvent;
    final expectedKeys = <String>{
      'event',
      'runCorrelationSha256',
      'attachmentSha256',
      'timestampMs',
      if (expectsSource) 'source',
    };
    final timestamp = value['timestampMs'];
    if (value.keys.toSet().difference(expectedKeys).isNotEmpty ||
        expectedKeys.difference(value.keys.toSet()).isNotEmpty ||
        value['event'] != expectedEvent ||
        value['runCorrelationSha256'] != expectedRunHash ||
        value['attachmentSha256'] != expectedAttachmentHash ||
        timestamp is! int ||
        timestamp < 0 ||
        (expectsSource &&
            value['source'] != privateMediaOutboxNetworkRestoredSource)) {
      throw _Failure(
        'Private-media endpoint returned malformed safe event evidence.',
      );
    }
    return _EventEvidence(
      event: expectedEvent,
      runCorrelationSha256: expectedRunHash,
      attachmentSha256: expectedAttachmentHash,
      timestampMs: timestamp,
      source: expectsSource ? privateMediaOutboxNetworkRestoredSource : null,
    );
  }

  final String event;
  final String runCorrelationSha256;
  final String attachmentSha256;
  final int timestampMs;
  final String? source;

  Map<String, Object?> toArtifact({bool includeAttachment = true}) =>
      <String, Object?>{
        'event': event,
        if (source != null) 'source': source,
        'runCorrelationSha256': runCorrelationSha256,
        if (includeAttachment) 'attachmentSha256': attachmentSha256,
      };
}

final class _NetworkState {
  const _NetworkState({
    required this.airplaneEnabled,
    required this.wifiEnabled,
    required this.dataEnabled,
  });

  final bool airplaneEnabled;
  final bool wifiEnabled;
  final bool dataEnabled;

  static Future<_NetworkState> capture(
    _Campaign campaign,
    String device,
  ) async {
    final airplane = await campaign._shellText(device, const <String>[
      'cmd',
      'connectivity',
      'airplane-mode',
    ]);
    final wifi = await campaign._shellText(device, const <String>[
      'settings',
      'get',
      'global',
      'wifi_on',
    ]);
    final data = await campaign._shellText(device, const <String>[
      'settings',
      'get',
      'global',
      'mobile_data',
    ]);
    return _NetworkState(
      airplaneEnabled: airplane.trim().toLowerCase().contains('enabled'),
      wifiEnabled: wifi.trim() == '1',
      dataEnabled: data.trim() == '1',
    );
  }

  Future<void> restore(
    _Campaign campaign,
    String device, {
    bool allowFailure = false,
  }) async {
    Future<void> run(List<String> command) async {
      await campaign._adb(device, <String>[
        'shell',
        ...command,
      ], allowFailure: allowFailure);
    }

    await run(<String>[
      'cmd',
      'connectivity',
      'airplane-mode',
      airplaneEnabled ? 'enable' : 'disable',
    ]);
    await run(<String>['svc', 'wifi', wifiEnabled ? 'enable' : 'disable']);
    await run(<String>['svc', 'data', dataEnabled ? 'enable' : 'disable']);
    await campaign._waitFor(
      'exact physical Android network-state restoration',
      const Duration(seconds: 30),
      () async => _matches(await _NetworkState.capture(campaign, device)),
    );
  }

  bool _matches(_NetworkState current) =>
      current.airplaneEnabled == airplaneEnabled &&
      current.wifiEnabled == wifiEnabled &&
      current.dataEnabled == dataEnabled;
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

Map<String, Object?> _object(Object? value) {
  if (value is! Map) throw const FormatException('expected JSON object');
  return value.map<String, Object?>((key, item) => MapEntry('$key', item));
}

List<Map<String, Object?>> _eventObjects(Object? value) {
  if (value is! List || value.any((item) => item is! Map)) {
    throw const _Failure('Private-media endpoint events were malformed.');
  }
  return List<Map<String, Object?>>.unmodifiable(
    value.map((item) => _object(item)),
  );
}

final class _Result {
  const _Result(this.exitCode, this.json);

  factory _Result.pass(
    SimsArtifactEvidence evidence, {
    required String apkSha256,
  }) => _Result(0, <String, Object?>{
    'status': 'PASS',
    'assertionsAttempted': 8,
    'artifactPresent': true,
    'printOnly': false,
    'exitCode': 0,
    'detail':
        'Two-phase production private-media restore causality and delivery '
        'were proven.',
    'centralBuildArtifacts': 1,
    'centralApkSha256': apkSha256,
    'childFlutterBuilds': 0,
    'artifactEvidence': evidence.toJson(),
  });

  factory _Result.fail(String detail) => _Result(1, <String, Object?>{
    'status': 'FAIL',
    'assertionsAttempted': 8,
    'artifactPresent': false,
    'printOnly': false,
    'blocker': 'test',
    'exitCode': 1,
    'detail': detail,
  });

  factory _Result.blocked(String detail) => _Result(78, <String, Object?>{
    'status': 'BLOCKED',
    'assertionsAttempted': 0,
    'artifactPresent': false,
    'printOnly': false,
    'blocker': 'environment',
    'exitCode': 78,
    'detail': detail,
  });

  final int exitCode;
  final Map<String, Object?> json;
}

final class _Blocked implements Exception {
  const _Blocked(this.detail);
  final String detail;
}

final class _Failure implements Exception {
  const _Failure(this.detail);
  final String detail;
}
