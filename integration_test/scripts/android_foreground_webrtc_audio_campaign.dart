import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../../tool/sims/artifact_evidence.dart';
import '../support/android_app_state_guard.dart';
import '../support/android_foreground_webrtc_audio_evidence.dart';
import '../support/sims_runtime_protocol.dart';
import '_android_app_package.dart';

const String _recordAudioPermission = 'android.permission.RECORD_AUDIO';
const String _turnAuthorityEnvironment =
    'SIMS_FOREGROUND_WEBRTC_TURN_AUTHORITY';
const String _turnTcpAuthorityEnvironment =
    'SIMS_FOREGROUND_WEBRTC_TURN_TCP_AUTHORITY';
const String _turnSecretEnvironment =
    'SIMS_FOREGROUND_WEBRTC_TURN_SHARED_SECRET';
const String _allowEmulatorPairDebugEnvironment =
    'SIMS_FOREGROUND_WEBRTC_ALLOW_EMULATOR_PAIR_DEBUG';
const Duration _privateFileTimeout = Duration(minutes: 2);
const Duration _peerFailureGrace = Duration(seconds: 5);
const int _maximumPrivateResultBytes = 16 * 1024;
const int _maximumRendezvousRequestBytes = 256 * 1024;
const int _maximumRendezvousEvents = 256;
const Set<String> _foregroundAudioControlNames = <String>{
  'canonical-endpoint-ready',
  'callee-ringing-ready',
  'caller-ringing-observed',
  'both-muted',
  'caller-to-callee-baseline',
  'caller-to-callee-unmuted',
  'caller-to-callee-sampled',
  'caller-to-callee-muted',
  'callee-to-caller-baseline',
  'callee-to-caller-unmuted',
  'callee-to-caller-sampled',
  'callee-to-caller-muted',
  'canonical-ended-observed',
};
const Set<String> _secureCallEnvelopeKeys = <String>{
  'type',
  'version',
  'message_id',
  'call_handle',
  'expires_at_ms',
  'kem',
  'ciphertext',
  'nonce',
  'signature',
};

/// Host-side SIMS protocol gate. The rendezvous may relay only the real secure
/// outer call envelope or one fixed synchronization barrier; it never accepts
/// plaintext SDP, candidates, identities, or media statistics.
bool validateAndroidForegroundWebRtcAudioRendezvousEvent({
  required String kind,
  required Map<String, Object?> payload,
}) {
  if (kind == 'control') {
    return payload.length == 1 &&
        payload['name'] is String &&
        _foregroundAudioControlNames.contains(payload['name']);
  }
  if (kind != 'envelope' ||
      payload.length != 1 ||
      payload['envelope'] is! String) {
    return false;
  }
  final envelope = payload['envelope']! as String;
  if (envelope.isEmpty ||
      utf8.encode(envelope).length > _maximumRendezvousRequestBytes) {
    return false;
  }
  try {
    final decoded = jsonDecode(envelope);
    final outer = _object(decoded);
    if (outer == null ||
        outer.length != _secureCallEnvelopeKeys.length ||
        !outer.keys.toSet().containsAll(_secureCallEnvelopeKeys) ||
        outer['type'] != 'call_signal' ||
        outer['version'] != '1' ||
        outer['expires_at_ms'] is! int) {
      return false;
    }
    for (final key in const <String>[
      'message_id',
      'call_handle',
      'kem',
      'ciphertext',
      'nonce',
      'signature',
    ]) {
      final value = outer[key];
      if (value is! String || value.isEmpty) return false;
    }
    return true;
  } on Object {
    return false;
  }
}

final class AndroidForegroundWebRtcAudioCampaignResult {
  const AndroidForegroundWebRtcAudioCampaignResult._({
    required this.processExitCode,
    required this.json,
  });

  factory AndroidForegroundWebRtcAudioCampaignResult.pass(
    SimsArtifactEvidence evidence,
  ) => AndroidForegroundWebRtcAudioCampaignResult._(
    processExitCode: 0,
    json: <String, Object?>{
      'status': 'PASS',
      'assertionsAttempted': androidForegroundWebRtcAudioAssertionCount,
      'artifactPresent': true,
      'printOnly': false,
      'exitCode': 0,
      'detail':
          'The shared standard APK completed the two-Android foreground '
          'audio-only WebRTC proof with privacy-safe durable evidence.',
      'artifactEvidence': evidence.toJson(),
    },
  );

  factory AndroidForegroundWebRtcAudioCampaignResult.blocked({
    required String blocker,
    required String detail,
    required bool artifactPresent,
  }) => AndroidForegroundWebRtcAudioCampaignResult._(
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

  /// A selected relay's endpoint/media/cleanup checks are useful evidence, but
  /// cannot satisfy the complete direct + UDP + TCP campaign contract.
  factory AndroidForegroundWebRtcAudioCampaignResult.relayProbePassed(
    AndroidForegroundWebRtcAudioRelayMode mode,
  ) => AndroidForegroundWebRtcAudioCampaignResult._(
    processExitCode: 78,
    json: <String, Object?>{
      'status': 'BLOCKED',
      'assertionsAttempted': androidForegroundWebRtcAudioAssertionCount,
      'artifactPresent': false,
      'printOnly': false,
      'blocker': 'selectedTransportOnly',
      'exitCode': 78,
      'selectedTransport': mode.name,
      'selectedTransportStatus': 'PASS',
      'fullCampaignCompleted': false,
      'detail':
          'Selected ${mode.name} endpoint media, controls and cleanup checks '
          'passed; the complete campaign and cross-mode artifact were not run.',
    },
  );

  factory AndroidForegroundWebRtcAudioCampaignResult.fail({
    required String blocker,
    required String detail,
    required bool artifactPresent,
  }) => AndroidForegroundWebRtcAudioCampaignResult._(
    processExitCode: 1,
    json: <String, Object?>{
      'status': 'FAIL',
      'assertionsAttempted': 0,
      'artifactPresent': artifactPresent,
      'printOnly': false,
      'blocker': blocker,
      'exitCode': 1,
      'detail': detail,
    },
  );

  factory AndroidForegroundWebRtcAudioCampaignResult.latencyExceeded(
    AndroidForegroundWebRtcAudioLatencyExceeded failure,
  ) => AndroidForegroundWebRtcAudioCampaignResult._(
    processExitCode: 1,
    json: <String, Object?>{
      'status': 'FAIL',
      'assertionsAttempted': androidForegroundWebRtcAudioAssertionCount,
      'artifactPresent': false,
      'printOnly': false,
      'blocker': 'product',
      'exitCode': 1,
      'detail':
          'Direct, TURN/UDP and TURN/TCP media and cleanup checks completed, '
          'but relay accept-to-audio p95=${failure.p95Ms}ms exceeded '
          '${AndroidForegroundWebRtcAudioLatencyExceeded.thresholdMs}ms.',
    },
  );

  final int processExitCode;
  final Map<String, Object?> json;
}

Future<AndroidForegroundWebRtcAudioCampaignResult>
runAndroidForegroundWebRtcAudioCampaign({
  required List<String> devices,
  required String? artifactPath,
  Map<String, String>? environment,
}) async {
  final env = environment ?? Platform.environment;
  final requestedProbe = env['SIMS_FOREGROUND_WEBRTC_RELAY_PROBE']?.trim();
  final relayProbe = switch (requestedProbe) {
    'turnUdp' => AndroidForegroundWebRtcAudioRelayMode.turnUdp,
    'turnTcp' => AndroidForegroundWebRtcAudioRelayMode.turnTcp,
    _ => null,
  };
  if (requestedProbe != null &&
      requestedProbe.isNotEmpty &&
      relayProbe == null) {
    return AndroidForegroundWebRtcAudioCampaignResult.blocked(
      blocker: 'environment',
      detail: 'The selected relay probe must name turnUdp or turnTcp.',
      artifactPresent: false,
    );
  }
  if (artifactPath == null ||
      artifactPath.trim().isEmpty ||
      FileSystemEntity.typeSync(artifactPath, followLinks: true) !=
          FileSystemEntityType.file) {
    return AndroidForegroundWebRtcAudioCampaignResult.blocked(
      blocker: 'missingArtifact',
      detail:
          'A readable centrally prepared $simsAndroidStandardProfileId APK is '
          'required; this campaign never builds an application.',
      artifactPresent: false,
    );
  }
  final configuredProfile = env['SIMS_ARTIFACT_PROFILE_ID']?.trim();
  if (configuredProfile != null &&
      configuredProfile.isNotEmpty &&
      configuredProfile != simsAndroidStandardProfileId) {
    return AndroidForegroundWebRtcAudioCampaignResult.blocked(
      blocker: 'missingArtifact',
      detail: 'Foreground WebRTC audio requires the standard Android profile.',
      artifactPresent: true,
    );
  }
  if (devices.length != 2 ||
      devices.first.isEmpty ||
      devices.last.isEmpty ||
      devices.first == devices.last) {
    return AndroidForegroundWebRtcAudioCampaignResult.blocked(
      blocker: 'targetUnavailable',
      detail:
          'Exactly two distinct explicit targets are required in physical '
          'Android then Android-emulator order.',
      artifactPresent: true,
    );
  }

  final artifact = File(artifactPath).absolute;
  late final String artifactSha256;
  try {
    artifactSha256 = sha256.convert(await artifact.readAsBytes()).toString();
  } on FileSystemException {
    return AndroidForegroundWebRtcAudioCampaignResult.blocked(
      blocker: 'missingArtifact',
      detail: 'The centrally prepared APK could not be read.',
      artifactPresent: false,
    );
  }

  late final _AndroidForegroundWebRtcAudioHost host;
  try {
    host = _AndroidForegroundWebRtcAudioHost(
      physicalDevice: devices.first,
      emulatorDevice: devices.last,
      artifact: artifact,
      artifactSha256: artifactSha256,
      packageName: resolveAndroidAppPackage(),
      proofDirectory: _proofDirectory(env),
      turnFixture: _TurnFixtureConfiguration.fromEnvironment(env),
      debugEmulatorPair: env[_allowEmulatorPairDebugEnvironment] == '1',
    );
    await host.verifyPrerequisites();
  } on _AudioProofBlocked catch (blocked) {
    return AndroidForegroundWebRtcAudioCampaignResult.blocked(
      blocker: blocked.blocker,
      detail: blocked.detail,
      artifactPresent: true,
    );
  } on Object {
    return AndroidForegroundWebRtcAudioCampaignResult.blocked(
      blocker: 'environment',
      detail: 'Foreground WebRTC audio prerequisite validation failed.',
      artifactPresent: true,
    );
  }

  try {
    if (relayProbe != null) {
      await host.runRelayProbe(relayProbe);
      return AndroidForegroundWebRtcAudioCampaignResult.relayProbePassed(
        relayProbe,
      );
    }
    return AndroidForegroundWebRtcAudioCampaignResult.pass(await host.run());
  } on _AudioProofBlocked catch (blocked) {
    return AndroidForegroundWebRtcAudioCampaignResult.blocked(
      blocker: blocked.blocker,
      detail: blocked.detail,
      artifactPresent: true,
    );
  } on _AudioProofFailure catch (failure) {
    return AndroidForegroundWebRtcAudioCampaignResult.fail(
      blocker: failure.blocker,
      detail: failure.detail,
      artifactPresent: false,
    );
  } on AndroidForegroundWebRtcAudioLatencyExceeded catch (failure) {
    return AndroidForegroundWebRtcAudioCampaignResult.latencyExceeded(failure);
  } on Object catch (error) {
    return AndroidForegroundWebRtcAudioCampaignResult.fail(
      blocker: 'harness',
      detail:
          'Foreground WebRTC audio proof failed unexpectedly '
          '(${error.runtimeType}).',
      artifactPresent: false,
    );
  }
}

final class _AndroidForegroundWebRtcAudioHost {
  _AndroidForegroundWebRtcAudioHost({
    required this.physicalDevice,
    required this.emulatorDevice,
    required this.artifact,
    required this.artifactSha256,
    required this.packageName,
    required this.proofDirectory,
    required this.turnFixture,
    required this.debugEmulatorPair,
    AndroidHostProcessRunner processRunner =
        const SystemAndroidHostProcessRunner(),
  }) : _processRunner = processRunner;

  final String physicalDevice;
  final String emulatorDevice;
  final File artifact;
  final String artifactSha256;
  final String packageName;
  final Directory proofDirectory;
  final _TurnFixtureConfiguration turnFixture;
  final bool debugEmulatorPair;
  final AndroidHostProcessRunner _processRunner;

  List<String> get _devices => <String>[physicalDevice, emulatorDevice];

  Future<void> verifyPrerequisites() async {
    final version = await _processRunner.run('adb', const <String>['version']);
    if (version.exitCode != 0) {
      throw const _AudioProofBlocked('missingDriver', 'adb is unavailable.');
    }
    for (final device in _devices) {
      final state = await _adb(device, const <String>['get-state']);
      if (state.exitCode != 0 || '${state.stdout}'.trim() != 'device') {
        throw const _AudioProofBlocked(
          'targetUnavailable',
          'One required Android target is not ready.',
        );
      }
    }
    final physicalQemu = await _shellText(physicalDevice, const <String>[
      'getprop',
      'ro.kernel.qemu',
    ]);
    final emulatorQemu = await _shellText(emulatorDevice, const <String>[
      'getprop',
      'ro.kernel.qemu',
    ]);
    final targetOrderValid = debugEmulatorPair
        ? physicalQemu.trim() == '1' && emulatorQemu.trim() == '1'
        : physicalQemu.trim() != '1' && emulatorQemu.trim() == '1';
    if (!targetOrderValid) {
      throw const _AudioProofBlocked(
        'targetUnavailable',
        'Target order does not match the selected Android proof topology.',
      );
    }
  }

  Future<SimsArtifactEvidence> run() async {
    final lease = await _AndroidForegroundWebRtcAudioTargetPairLease.acquire(
      devices: _devices,
      scenarioId: simsAndroidForegroundWebRtcAudioScenarioId,
    );
    try {
      return await _runWithTargetPairLease();
    } finally {
      await lease.release();
    }
  }

  Future<void> runRelayProbe(AndroidForegroundWebRtcAudioRelayMode mode) async {
    final lease = await _AndroidForegroundWebRtcAudioTargetPairLease.acquire(
      devices: _devices,
      scenarioId: simsAndroidForegroundWebRtcAudioScenarioId,
    );
    try {
      await _runTransportCase(mode: mode);
    } finally {
      await lease.release();
    }
  }

  Future<SimsArtifactEvidence> _runWithTargetPairLease() async {
    late final AndroidAppStateGuard stateGuard;
    try {
      stateGuard = await AndroidAppStateGuard.capture(
        devices: _devices,
        packageName: packageName,
        backupLabel: 'foreground-webrtc-audio',
        runner: const SystemAndroidHostProcessRunner(
          commandTimeout: Duration(minutes: 10),
          terminationGrace: Duration(seconds: 5),
        ),
        privateArchiveTimeout: const Duration(minutes: 10),
      );
    } on AndroidAppStateBlocked catch (blocked) {
      throw _AudioProofBlocked(
        'environment',
        debugEmulatorPair
            ? 'Debug app-state capture blocked '
                  '(${_appStateBlockCategory(blocked.detail)}).'
            : 'App-state capture could not prepare the foreground audio proof '
                  '(${_appStateBlockCategory(blocked.detail)}).',
      );
    } on AndroidAppStateFailure {
      throw const _AudioProofFailure(
        'restoration',
        'App-state capture failed before the foreground audio proof.',
      );
    }

    _LoopbackAudioRendezvous? rendezvous;
    final reverseMappedDevices = <String>{};
    SimsRuntimeInvocation? callerInvocation;
    SimsRuntimeInvocation? calleeInvocation;
    Map<String, Object?>? callerEndpoint;
    Map<String, Object?>? calleeEndpoint;
    Map<String, Object?>? wireSummary;
    Map<String, Object?>? controlSummary;
    Object? proofError;
    StackTrace? proofStack;
    late AndroidForegroundWebRtcAudioProtocolCleanupResult protocolCleanup;
    var appStateRestored = false;

    try {
      await stateGuard.prepareFreshInstall(
        device: physicalDevice,
        artifact: artifact,
      );
      await stateGuard.prepareFreshInstall(
        device: emulatorDevice,
        artifact: artifact,
      );
      await _pregrantMicrophone(physicalDevice);
      await _pregrantMicrophone(emulatorDevice);

      rendezvous = await _LoopbackAudioRendezvous.start();
      for (final device in _devices) {
        final reverse = await _adb(device, <String>[
          'reverse',
          'tcp:${rendezvous.port}',
          'tcp:${rendezvous.port}',
        ]);
        if (reverse.exitCode != 0) {
          throw const _AudioProofBlocked(
            'environment',
            'A pinned Android reverse mapping could not be created.',
          );
        }
        reverseMappedDevices.add(device);
      }

      final runId = _safeToken('audio');
      callerInvocation = _invocation(
        role: simsForegroundWebRtcCallerRole,
        targetKind: 'physical',
        runId: runId,
        rendezvous: rendezvous,
      );
      calleeInvocation = _invocation(
        role: simsForegroundWebRtcCalleeRole,
        targetKind: 'emulator',
        runId: runId,
        rendezvous: rendezvous,
      );
      await _stageInvocation(physicalDevice, callerInvocation);
      await _stageInvocation(emulatorDevice, calleeInvocation);

      // The caller's canonical no-answer timer begins as soon as its runtime
      // starts. Launch both already-staged endpoints together so emulator app
      // startup cannot consume the caller's production timeout budget.
      await Future.wait<void>(<Future<void>>[
        _launch(physicalDevice),
        _launch(emulatorDevice),
      ]);
      final acknowledgements = await Future.wait(<Future<Map<String, Object?>>>[
        _waitForPrivateJson(physicalDevice, simsRuntimeAckRelativePath),
        _waitForPrivateJson(emulatorDevice, simsRuntimeAckRelativePath),
      ]);
      if (!validateSimsRuntimeAck(
            acknowledgements.first,
            callerInvocation,
          ).accepted ||
          !validateSimsRuntimeAck(
            acknowledgements.last,
            calleeInvocation,
          ).accepted) {
        throw const _AudioProofFailure(
          'harness',
          'A dispatcher runtime acknowledgement was rejected.',
        );
      }

      DateTime? endpointFailedAt;
      final endpoints = await Future.wait(<Future<Map<String, Object?>>>[
        _waitForEndpointResult(
          physicalDevice,
          callerInvocation,
          shouldAbort: () =>
              endpointFailedAt != null &&
              DateTime.now().difference(endpointFailedAt!) >= _peerFailureGrace,
          markFailed: () => endpointFailedAt ??= DateTime.now(),
        ),
        _waitForEndpointResult(
          emulatorDevice,
          calleeInvocation,
          shouldAbort: () =>
              endpointFailedAt != null &&
              DateTime.now().difference(endpointFailedAt!) >= _peerFailureGrace,
          markFailed: () => endpointFailedAt ??= DateTime.now(),
        ),
      ]);
      callerEndpoint = endpoints.first;
      calleeEndpoint = endpoints.last;
      final failedDetails = <String>[];
      for (final entry in <(SimsRuntimeInvocation, Map<String, Object?>)>[
        (callerInvocation, callerEndpoint),
        (calleeInvocation, calleeEndpoint),
      ]) {
        final endpoint = entry.$2;
        if (endpoint['status'] == 'peerAborted') continue;
        if (endpoint['status'] != 'failed') continue;
        final validation = validateAndroidForegroundWebRtcAudioFailedEndpoint(
          endpoint,
          invocation: entry.$1,
        );
        if (!validation.ok) {
          throw const _AudioProofFailure(
            'harness',
            'A failed foreground WebRTC audio endpoint marker was rejected.',
          );
        }
        failedDetails.add(_failedEndpointDetail(entry.$1, endpoint));
      }
      if (failedDetails.isNotEmpty) {
        throw _AudioProofFailure('test', failedDetails.join(' '));
      }
      if (endpoints.any((endpoint) => endpoint['status'] == 'peerAborted')) {
        throw const _AudioProofFailure(
          'test',
          'A foreground WebRTC audio peer did not publish its result within '
              'the bounded failure grace period.',
        );
      }
      if (!validateAndroidForegroundWebRtcAudioEndpoint(
            callerEndpoint,
            invocation: callerInvocation,
          ).ok ||
          !validateAndroidForegroundWebRtcAudioEndpoint(
            calleeEndpoint,
            invocation: calleeInvocation,
          ).ok) {
        throw const _AudioProofFailure(
          'test',
          'A foreground WebRTC audio endpoint result was rejected.',
        );
      }
      wireSummary = rendezvous.wireSummary();
    } catch (error, stackTrace) {
      proofError = error;
      proofStack = stackTrace;
    } finally {
      // Preserve only bounded opaque-envelope counts/chains for diagnosing a
      // failed endpoint run. The rendezvous clears its in-memory journal when
      // cleanup closes it, and no envelope bytes or signal types leave it.
      wireSummary ??= rendezvous?.wireSummary();
      controlSummary ??= rendezvous?.controlSummary();
      protocolCleanup =
          await AndroidForegroundWebRtcAudioProtocolCleaner(
            processRunner: _processRunner,
          ).cleanup(
            devices: _devices,
            packageName: packageName,
            reversePort: rendezvous?.port,
            reverseMappedDevices: reverseMappedDevices,
            closeRendezvous: () async {
              final activeRendezvous = rendezvous;
              if (activeRendezvous != null) await activeRendezvous.close();
            },
          );
      try {
        await stateGuard.restoreAll();
        appStateRestored = true;
      } on AndroidAppStateFailure {
        appStateRestored = false;
      }
    }

    if (!protocolCleanup.ok || !appStateRestored) {
      throw const _AudioProofFailure(
        'restoration',
        'Foreground WebRTC audio protocol or app state did not restore.',
      );
    }
    if (proofError != null) {
      if (proofError case final _AudioProofFailure failure
          when wireSummary != null) {
        Error.throwWithStackTrace(
          _AudioProofFailure(
            failure.blocker,
            '${failure.detail} ${_wireFailureDetail(wireSummary)} '
            '${_controlFailureDetail(controlSummary)}',
          ),
          proofStack ?? StackTrace.current,
        );
      }
      Error.throwWithStackTrace(proofError, proofStack ?? StackTrace.current);
    }
    if (callerInvocation == null ||
        calleeInvocation == null ||
        callerEndpoint == null ||
        calleeEndpoint == null ||
        wireSummary == null) {
      throw const _AudioProofFailure(
        'harness',
        'Foreground WebRTC audio proof produced no endpoint result.',
      );
    }

    final digestSalt = _randomUrlToken(24);
    final canonicalProof = aggregateAndroidForegroundWebRtcAudioEvidence(
      callerEndpoint: callerEndpoint,
      calleeEndpoint: calleeEndpoint,
      callerInvocation: callerInvocation,
      calleeInvocation: calleeInvocation,
      sharedApkSha256: artifactSha256,
      physicalTargetDigest: sha256
          .convert(utf8.encode('$digestSalt:physical:$physicalDevice'))
          .toString(),
      emulatorTargetDigest: sha256
          .convert(utf8.encode('$digestSalt:emulator:$emulatorDevice'))
          .toString(),
      wireSummary: wireSummary,
      processesStopped: protocolCleanup.processesStopped,
      runtimeFilesRemoved: protocolCleanup.runtimeFilesRemoved,
      reverseMappingsRemoved: protocolCleanup.reverseMappingsRemoved,
      rendezvousClosed: protocolCleanup.rendezvousClosed,
      appStateRestored: appStateRestored,
    );
    final turnUdp = await _runTransportCase(
      mode: AndroidForegroundWebRtcAudioRelayMode.turnUdp,
    );
    final turnTcp = await _runTransportCase(
      mode: AndroidForegroundWebRtcAudioRelayMode.turnTcp,
    );
    final relayProof = aggregateAndroidForegroundWebRtcAudioRelayEvidence(
      legs: <AndroidForegroundWebRtcAudioRelayLegEvidence>[
        turnUdp.asEvidence(),
        turnTcp.asEvidence(),
      ],
      sharedApkSha256: artifactSha256,
    );
    if (debugEmulatorPair) {
      final latency = relayProof['latencyMeasurement']! as Map<String, Object?>;
      throw _AudioProofBlocked(
        'debugOnly',
        'Isolated emulator-pair debug completed direct=passed, '
            'turnUdp=passed, turnTcp=passed, campaignP95Ms=${latency['p95Ms']}; '
            'no durable device-proof artifact was created.',
      );
    }
    final evidence = writeSimsArtifactEvidenceSync(
      directory: proofDirectory,
      capabilityId: simsAndroidForegroundWebRtcAudioScenarioId,
      validatorIds: const <String>[
        androidForegroundWebRtcAudioArtifactValidatorId,
      ],
      payload: androidForegroundWebRtcAudioArtifactPayload(
        canonical: canonicalProof,
        relay: relayProof,
      ),
    );
    final audit = auditSimsArtifactEvidence(
      evidence: evidence,
      expectedValidatorIds: const <String>[
        androidForegroundWebRtcAudioArtifactValidatorId,
      ],
    );
    if (!audit.isValid) {
      try {
        File(evidence.path).deleteSync();
      } on FileSystemException {
        // The typed result still fails closed and never binds this artifact.
      }
      throw const _AudioProofFailure(
        'harness',
        'Foreground WebRTC audio durable evidence failed its binding audit.',
      );
    }
    final durable = jsonDecode(File(evidence.path).readAsStringSync());
    var durableProofValid = false;
    if (durable is Map) {
      try {
        androidForegroundWebRtcAudioProofsFromArtifact(
          durable.map<String, Object?>((key, value) => MapEntry('$key', value)),
        );
        durableProofValid = true;
      } on FormatException {
        durableProofValid = false;
      }
    }
    if (!durableProofValid) {
      try {
        File(evidence.path).deleteSync();
      } on FileSystemException {
        // The typed result still fails closed and never binds this artifact.
      }
      throw const _AudioProofFailure(
        'harness',
        'Foreground WebRTC audio durable evidence failed validation.',
      );
    }
    return evidence;
  }

  Future<_AndroidForegroundWebRtcAudioTransportCase> _runTransportCase({
    required AndroidForegroundWebRtcAudioRelayMode mode,
  }) async {
    late final AndroidAppStateGuard stateGuard;
    try {
      stateGuard = await AndroidAppStateGuard.capture(
        devices: _devices,
        packageName: packageName,
        backupLabel: 'foreground-webrtc-audio-${mode.name}',
      );
    } on AndroidAppStateBlocked catch (blocked) {
      throw _AudioProofBlocked(
        'environment',
        debugEmulatorPair
            ? 'Debug relay app-state capture blocked '
                  '(${_appStateBlockCategory(blocked.detail)}).'
            : 'App-state capture could not prepare a relay transport case '
                  '(${_appStateBlockCategory(blocked.detail)}).',
      );
    } on AndroidAppStateFailure {
      throw const _AudioProofFailure(
        'restoration',
        'App-state capture failed before a relay transport case.',
      );
    }

    _LoopbackAudioRendezvous? rendezvous;
    final reverseMappedDevices = <String>{};
    SimsRuntimeInvocation? callerInvocation;
    SimsRuntimeInvocation? calleeInvocation;
    Map<String, Object?>? callerEndpoint;
    Map<String, Object?>? calleeEndpoint;
    Map<String, Object?>? wireSummary;
    Map<String, Object?>? controlSummary;
    Object? proofError;
    StackTrace? proofStack;
    late AndroidForegroundWebRtcAudioProtocolCleanupResult protocolCleanup;
    var appStateRestored = false;

    try {
      await stateGuard.prepareFreshInstall(
        device: physicalDevice,
        artifact: artifact,
      );
      await stateGuard.prepareFreshInstall(
        device: emulatorDevice,
        artifact: artifact,
      );
      await _pregrantMicrophone(physicalDevice);
      await _pregrantMicrophone(emulatorDevice);

      rendezvous = await _LoopbackAudioRendezvous.start();
      for (final device in _devices) {
        final reverse = await _adb(device, <String>[
          'reverse',
          'tcp:${rendezvous.port}',
          'tcp:${rendezvous.port}',
        ]);
        if (reverse.exitCode != 0) {
          throw const _AudioProofBlocked(
            'environment',
            'A relay transport reverse mapping could not be created.',
          );
        }
        reverseMappedDevices.add(device);
      }

      final credentials = turnFixture.mint(mode);
      final runId = _safeToken('audio-${mode.name}');
      callerInvocation = _invocation(
        role: simsForegroundWebRtcCallerRole,
        targetKind: 'physical',
        runId: runId,
        rendezvous: rendezvous,
        turnCredentials: credentials,
      );
      calleeInvocation = _invocation(
        role: simsForegroundWebRtcCalleeRole,
        targetKind: 'emulator',
        runId: runId,
        rendezvous: rendezvous,
        turnCredentials: credentials,
      );
      await _stageInvocation(physicalDevice, callerInvocation);
      await _stageInvocation(emulatorDevice, calleeInvocation);
      await Future.wait<void>(<Future<void>>[
        _launch(physicalDevice),
        _launch(emulatorDevice),
      ]);
      final acknowledgements = await Future.wait(<Future<Map<String, Object?>>>[
        _waitForPrivateJson(physicalDevice, simsRuntimeAckRelativePath),
        _waitForPrivateJson(emulatorDevice, simsRuntimeAckRelativePath),
      ]);
      if (!validateSimsRuntimeAck(
            acknowledgements.first,
            callerInvocation,
          ).accepted ||
          !validateSimsRuntimeAck(
            acknowledgements.last,
            calleeInvocation,
          ).accepted) {
        throw const _AudioProofFailure(
          'harness',
          'A relay dispatcher runtime acknowledgement was rejected.',
        );
      }

      DateTime? endpointFailedAt;
      final endpoints = await Future.wait(<Future<Map<String, Object?>>>[
        _waitForEndpointResult(
          physicalDevice,
          callerInvocation,
          shouldAbort: () =>
              endpointFailedAt != null &&
              DateTime.now().difference(endpointFailedAt!) >= _peerFailureGrace,
          markFailed: () => endpointFailedAt ??= DateTime.now(),
        ),
        _waitForEndpointResult(
          emulatorDevice,
          calleeInvocation,
          shouldAbort: () =>
              endpointFailedAt != null &&
              DateTime.now().difference(endpointFailedAt!) >= _peerFailureGrace,
          markFailed: () => endpointFailedAt ??= DateTime.now(),
        ),
      ]);
      callerEndpoint = endpoints.first;
      calleeEndpoint = endpoints.last;
      final failedDetails = <String>[];
      for (final entry in <(SimsRuntimeInvocation, Map<String, Object?>)>[
        (callerInvocation, callerEndpoint),
        (calleeInvocation, calleeEndpoint),
      ]) {
        final endpoint = entry.$2;
        if (endpoint['status'] == 'peerAborted') continue;
        if (endpoint['status'] != 'failed') continue;
        final validation = validateAndroidForegroundWebRtcAudioFailedEndpoint(
          endpoint,
          invocation: entry.$1,
        );
        if (!validation.ok) {
          throw const _AudioProofFailure(
            'harness',
            'A failed relay endpoint marker was rejected.',
          );
        }
        failedDetails.add(_failedEndpointDetail(entry.$1, endpoint));
      }
      if (failedDetails.isNotEmpty) {
        throw _AudioProofFailure('test', failedDetails.join(' '));
      }
      if (endpoints.any((endpoint) => endpoint['status'] == 'peerAborted')) {
        throw const _AudioProofFailure(
          'test',
          'A relay peer did not publish its result within the bounded failure '
              'grace period.',
        );
      }
      if (!validateAndroidForegroundWebRtcAudioRelayEndpoint(
            callerEndpoint,
            invocation: callerInvocation,
          ).ok ||
          !validateAndroidForegroundWebRtcAudioRelayEndpoint(
            calleeEndpoint,
            invocation: calleeInvocation,
          ).ok) {
        throw const _AudioProofFailure(
          'test',
          'A foreground WebRTC relay endpoint result was rejected.',
        );
      }
      wireSummary = rendezvous.wireSummary();
    } catch (error, stackTrace) {
      proofError = error;
      proofStack = stackTrace;
    } finally {
      wireSummary ??= rendezvous?.wireSummary();
      controlSummary ??= rendezvous?.controlSummary();
      protocolCleanup =
          await AndroidForegroundWebRtcAudioProtocolCleaner(
            processRunner: _processRunner,
          ).cleanup(
            devices: _devices,
            packageName: packageName,
            reversePort: rendezvous?.port,
            reverseMappedDevices: reverseMappedDevices,
            closeRendezvous: () async {
              final activeRendezvous = rendezvous;
              if (activeRendezvous != null) await activeRendezvous.close();
            },
          );
      try {
        await stateGuard.restoreAll();
        appStateRestored = true;
      } on AndroidAppStateFailure {
        appStateRestored = false;
      }
    }

    if (!protocolCleanup.ok || !appStateRestored) {
      throw const _AudioProofFailure(
        'restoration',
        'A relay transport case did not restore every host/device boundary.',
      );
    }
    if (proofError != null) {
      if (proofError case final _AudioProofFailure failure
          when wireSummary != null) {
        Error.throwWithStackTrace(
          _AudioProofFailure(
            failure.blocker,
            'relayMode=${mode.name}. ${failure.detail} '
            '${_wireFailureDetail(wireSummary)} '
            '${_controlFailureDetail(controlSummary)}',
          ),
          proofStack ?? StackTrace.current,
        );
      }
      Error.throwWithStackTrace(proofError, proofStack ?? StackTrace.current);
    }
    if (callerInvocation == null ||
        calleeInvocation == null ||
        callerEndpoint == null ||
        calleeEndpoint == null ||
        wireSummary == null) {
      throw const _AudioProofFailure(
        'harness',
        'A relay transport case produced no endpoint result.',
      );
    }
    return _AndroidForegroundWebRtcAudioTransportCase(
      mode: mode,
      callerEndpoint: callerEndpoint,
      calleeEndpoint: calleeEndpoint,
      callerInvocation: callerInvocation,
      calleeInvocation: calleeInvocation,
      wireSummary: wireSummary,
      cleanup: protocolCleanup,
      appStateRestored: appStateRestored,
    );
  }

  SimsRuntimeInvocation _invocation({
    required String role,
    required String targetKind,
    required String runId,
    required _LoopbackAudioRendezvous rendezvous,
    _TurnCredentialBundle? turnCredentials,
  }) {
    final invocation = SimsRuntimeInvocation(
      schema: simsRuntimeConfigSchema,
      profileId: simsAndroidStandardProfileId,
      scenarioId: simsAndroidForegroundWebRtcAudioScenarioId,
      role: role,
      runId: runId,
      nonce: _safeToken(role),
      values: <String, Object?>{
        'rendezvousUrl': 'http://127.0.0.1:${rendezvous.port}',
        'bearer': rendezvous.bearerFor(role),
        'targetKind': targetKind,
        'sharedApkSha256': artifactSha256,
        if (turnCredentials != null) ...<String, Object?>{
          'relayMode': turnCredentials.mode.name,
          'turnUrls': turnCredentials.urls,
          'turnUsername': turnCredentials.username,
          'turnPassword': turnCredentials.password,
          'turnExpiresAtMs': turnCredentials.expiresAtMs,
        },
      },
    );
    final parsed = SimsRuntimeInvocation.fromJson(invocation.toJson());
    if (!validateAndroidForegroundWebRtcAudioRuntimeInvocation(parsed).ok) {
      throw const _AudioProofFailure(
        'harness',
        'Foreground WebRTC audio invocation was invalid.',
      );
    }
    return parsed;
  }

  Future<void> _pregrantMicrophone(String device) async {
    final grant = await _adb(device, <String>[
      'shell',
      'pm',
      'grant',
      packageName,
      _recordAudioPermission,
    ]);
    if (grant.exitCode != 0) {
      throw const _AudioProofBlocked(
        'permissions',
        'RECORD_AUDIO could not be pregranted on one Android target.',
      );
    }
  }

  Future<void> _stageInvocation(
    String device,
    SimsRuntimeInvocation invocation,
  ) async {
    final process = await Process.start('adb', <String>[
      '-s',
      device,
      'shell',
      'run-as',
      packageName,
      'sh',
      '-c',
      "'mkdir -p files/$simsRuntimeDirectory && "
          'rm -f $simsRuntimeAckRelativePath '
          '$simsRuntimeResultRelativePath && '
          "umask 077 && cat > $simsRuntimeConfigRelativePath'",
    ], runInShell: false);
    final stdoutDone = process.stdout.drain<void>();
    final stderrDone = process.stderr.drain<void>();
    process.stdin.write(jsonEncode(invocation.toJson()));
    await process.stdin.close();
    final exitCode = await process.exitCode.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        process.kill();
        return 124;
      },
    );
    await Future.wait<void>(<Future<void>>[stdoutDone, stderrDone]);
    if (exitCode != 0) {
      throw const _AudioProofBlocked(
        'environment',
        'A private runtime invocation could not be staged.',
      );
    }
  }

  Future<void> _launch(String device) async {
    final launch = await _adb(device, <String>[
      'shell',
      'am',
      'start',
      '-W',
      '-n',
      // Application-ID overrides do not change the app's Kotlin namespace.
      '$packageName/com.mknoon.app.MainActivity',
    ]);
    if (launch.exitCode != 0) {
      throw const _AudioProofBlocked(
        'environment',
        'A runtime-dispatched APK could not be launched in the foreground.',
      );
    }
  }

  Future<Map<String, Object?>> _waitForPrivateJson(
    String device,
    String relativePath, {
    bool Function()? shouldAbort,
  }) async {
    final deadline = DateTime.now().add(_privateFileTimeout);
    while (DateTime.now().isBefore(deadline)) {
      final read = await _adb(device, <String>[
        'shell',
        'run-as',
        packageName,
        'cat',
        relativePath,
      ]);
      if (read.exitCode == 0) {
        final encoded = '${read.stdout}';
        if (utf8.encode(encoded).length > _maximumPrivateResultBytes) {
          throw const _AudioProofFailure(
            'harness',
            'A private runtime result exceeded its evidence bound.',
          );
        }
        try {
          final decoded = jsonDecode(encoded);
          if (decoded is Map) {
            return decoded.map<String, Object?>(
              (key, value) => MapEntry('$key', value),
            );
          }
        } on FormatException {
          // Atomic rename can be observed between polling iterations.
        }
      }
      if (shouldAbort?.call() == true) {
        return const <String, Object?>{'status': 'peerAborted'};
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw const _AudioProofFailure(
      'test',
      'A runtime-dispatched foreground WebRTC audio result timed out.',
    );
  }

  Future<Map<String, Object?>> _waitForEndpointResult(
    String device,
    SimsRuntimeInvocation invocation, {
    required bool Function() shouldAbort,
    required void Function() markFailed,
  }) async {
    final endpoint = await _waitForPrivateJson(
      device,
      simsRuntimeResultRelativePath,
      shouldAbort: shouldAbort,
    );
    if (endpoint['status'] != 'failed') return endpoint;
    markFailed();
    return endpoint;
  }

  Future<String> _shellText(String device, List<String> command) async {
    final result = await _adb(device, <String>['shell', ...command]);
    if (result.exitCode != 0) {
      throw const _AudioProofBlocked(
        'environment',
        'A pinned Android prerequisite query failed.',
      );
    }
    return '${result.stdout}';
  }

  Future<ProcessResult> _adb(String device, List<String> command) =>
      _processRunner.run('adb', <String>['-s', device, ...command]);
}

/// Cross-process advisory lease for one exact scenario/target-pair tuple.
///
/// The on-disk file is empty and its name contains only a SHA-256 digest. File
/// existence is never interpreted as ownership; the open OS lock is the sole
/// authority and is released automatically if the host process exits.
final class _AndroidForegroundWebRtcAudioTargetPairLease {
  _AndroidForegroundWebRtcAudioTargetPairLease._(this._handle);

  static Future<_AndroidForegroundWebRtcAudioTargetPairLease> acquire({
    required List<String> devices,
    required String scenarioId,
    Duration waitTimeout = const Duration(minutes: 5),
    Duration pollInterval = const Duration(milliseconds: 250),
  }) async {
    if (devices.length != 2 ||
        devices.toSet().length != devices.length ||
        scenarioId != simsAndroidForegroundWebRtcAudioScenarioId ||
        waitTimeout <= Duration.zero ||
        pollInterval <= Duration.zero) {
      throw const _AudioProofBlocked(
        'targetBusy',
        'The target-pair lease request was invalid.',
      );
    }
    final sortedDevices = List<String>.from(devices)..sort();
    final identity = sha256
        .convert(
          utf8.encode('$scenarioId\u0000${sortedDevices.join('\u0000')}'),
        )
        .toString();
    final leaseFile = File(
      '${Directory.systemTemp.path}/mknoon-sims-target-lease-$identity.lock',
    );
    final handle = await leaseFile.open(mode: FileMode.writeOnlyAppend);
    final deadline = DateTime.now().add(waitTimeout);
    while (true) {
      try {
        await handle.lock(FileLock.exclusive);
        return _AndroidForegroundWebRtcAudioTargetPairLease._(handle);
      } on FileSystemException {
        if (!DateTime.now().isBefore(deadline)) {
          await handle.close();
          throw const _AudioProofBlocked(
            'targetBusy',
            'The target pair remained leased by another host campaign.',
          );
        }
        await Future<void>.delayed(pollInterval);
      }
    }
  }

  final RandomAccessFile _handle;
  var _released = false;

  Future<void> release() async {
    if (_released) return;
    _released = true;
    try {
      await _handle.unlock();
    } finally {
      await _handle.close();
    }
  }

  @override
  String toString() => '_AndroidForegroundWebRtcAudioTargetPairLease(redacted)';
}

final class _TurnFixtureConfiguration {
  const _TurnFixtureConfiguration._({
    required this.udpAuthority,
    required this.tcpAuthority,
    required this.sharedSecret,
  });

  factory _TurnFixtureConfiguration.fromEnvironment(
    Map<String, String> environment,
  ) {
    final udpAuthority = environment[_turnAuthorityEnvironment]?.trim();
    final tcpAuthority = environment[_turnTcpAuthorityEnvironment]?.trim();
    final sharedSecret = environment[_turnSecretEnvironment];
    final udpAuthorityMatch = udpAuthority == null
        ? null
        : RegExp(r'^([A-Za-z0-9.-]+):([0-9]{1,5})$').firstMatch(udpAuthority);
    final tcpAuthorityMatch = tcpAuthority == null
        ? null
        : RegExp(r'^([A-Za-z0-9.-]+):([0-9]{1,5})$').firstMatch(tcpAuthority);
    final udpHost = udpAuthorityMatch?.group(1)?.toLowerCase();
    final tcpHost = tcpAuthorityMatch?.group(1)?.toLowerCase();
    final udpPort = int.tryParse(udpAuthorityMatch?.group(2) ?? '');
    final tcpPort = int.tryParse(tcpAuthorityMatch?.group(2) ?? '');
    final secretByteLength = sharedSecret == null
        ? 0
        : utf8.encode(sharedSecret).length;
    if (udpAuthority == null ||
        tcpAuthority == null ||
        udpAuthorityMatch == null ||
        tcpAuthorityMatch == null ||
        udpHost == null ||
        tcpHost == null ||
        udpHost != tcpHost ||
        !_isDeviceRoutableIpv4Host(udpHost) ||
        udpPort == null ||
        tcpPort == null ||
        udpPort < 1 ||
        udpPort > 65535 ||
        tcpPort < 1 ||
        tcpPort > 65535 ||
        udpPort == tcpPort ||
        sharedSecret == null ||
        secretByteLength < 8 ||
        secretByteLength > 256 ||
        RegExp(r'\s').hasMatch(sharedSecret)) {
      throw const _AudioProofBlocked(
        'environment',
        'A bounded device-reachable coturn REST fixture is required.',
      );
    }
    return _TurnFixtureConfiguration._(
      udpAuthority: udpAuthority,
      tcpAuthority: tcpAuthority,
      sharedSecret: sharedSecret,
    );
  }

  final String udpAuthority;
  final String tcpAuthority;
  final String sharedSecret;

  _TurnCredentialBundle mint(AndroidForegroundWebRtcAudioRelayMode mode) {
    final expiresAtSeconds =
        DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 10))
            .millisecondsSinceEpoch ~/
        1000;
    final username = '$expiresAtSeconds:vc203-${_randomUrlToken(8)}';
    final password = base64.encode(
      Hmac(
        sha1,
        utf8.encode(sharedSecret),
      ).convert(utf8.encode(username)).bytes,
    );
    final urls = switch (mode) {
      AndroidForegroundWebRtcAudioRelayMode.turnUdp => <String>[
        'turn:$udpAuthority?transport=udp',
      ],
      AndroidForegroundWebRtcAudioRelayMode.turnTcp => <String>[
        'turn:$tcpAuthority?transport=udp',
        'turn:$tcpAuthority?transport=tcp',
      ],
    };
    return _TurnCredentialBundle(
      mode: mode,
      urls: urls,
      username: username,
      password: password,
      expiresAtMs: expiresAtSeconds * 1000,
    );
  }

  @override
  String toString() => '_TurnFixtureConfiguration(redacted)';
}

final class _TurnCredentialBundle {
  _TurnCredentialBundle({
    required this.mode,
    required List<String> urls,
    required this.username,
    required this.password,
    required this.expiresAtMs,
  }) : urls = List<String>.unmodifiable(urls);

  final AndroidForegroundWebRtcAudioRelayMode mode;
  final List<String> urls;
  final String username;
  final String password;
  final int expiresAtMs;

  @override
  String toString() => '_TurnCredentialBundle(${mode.name}, redacted)';
}

final class _AndroidForegroundWebRtcAudioTransportCase {
  const _AndroidForegroundWebRtcAudioTransportCase({
    required this.mode,
    required this.callerEndpoint,
    required this.calleeEndpoint,
    required this.callerInvocation,
    required this.calleeInvocation,
    required this.wireSummary,
    required this.cleanup,
    required this.appStateRestored,
  });

  final AndroidForegroundWebRtcAudioRelayMode mode;
  final Map<String, Object?> callerEndpoint;
  final Map<String, Object?> calleeEndpoint;
  final SimsRuntimeInvocation callerInvocation;
  final SimsRuntimeInvocation calleeInvocation;
  final Map<String, Object?> wireSummary;
  final AndroidForegroundWebRtcAudioProtocolCleanupResult cleanup;
  final bool appStateRestored;

  AndroidForegroundWebRtcAudioRelayLegEvidence asEvidence() =>
      AndroidForegroundWebRtcAudioRelayLegEvidence(
        mode: mode,
        callerEndpoint: callerEndpoint,
        calleeEndpoint: calleeEndpoint,
        callerInvocation: callerInvocation,
        calleeInvocation: calleeInvocation,
        wireSummary: wireSummary,
        processesStopped: cleanup.processesStopped,
        runtimeFilesRemoved: cleanup.runtimeFilesRemoved,
        reverseMappingsRemoved: cleanup.reverseMappingsRemoved,
        rendezvousClosed: cleanup.rendezvousClosed,
        appStateRestored: appStateRestored,
      );

  @override
  String toString() =>
      '_AndroidForegroundWebRtcAudioTransportCase(${mode.name}, redacted)';
}

final class AndroidForegroundWebRtcAudioProtocolCleanupResult {
  const AndroidForegroundWebRtcAudioProtocolCleanupResult({
    required this.processesStopped,
    required this.runtimeFilesRemoved,
    required this.reverseMappingsRemoved,
    required this.rendezvousClosed,
  });

  final bool processesStopped;
  final bool runtimeFilesRemoved;
  final bool reverseMappingsRemoved;
  final bool rendezvousClosed;

  bool get ok =>
      processesStopped &&
      runtimeFilesRemoved &&
      reverseMappingsRemoved &&
      rendezvousClosed;
}

/// Fail-closed, injectable cleanup used by the real host and deterministic
/// protocol-cleanup tests. Every device command is pinned to its target.
final class AndroidForegroundWebRtcAudioProtocolCleaner {
  const AndroidForegroundWebRtcAudioProtocolCleaner({
    AndroidHostProcessRunner processRunner =
        const SystemAndroidHostProcessRunner(),
  }) : _processRunner = processRunner;

  final AndroidHostProcessRunner _processRunner;

  Future<AndroidForegroundWebRtcAudioProtocolCleanupResult> cleanup({
    required List<String> devices,
    required String packageName,
    required int? reversePort,
    required Set<String> reverseMappedDevices,
    required Future<void> Function() closeRendezvous,
  }) async {
    var processesStopped = true;
    var runtimeFilesRemoved = true;
    var reverseMappingsRemoved = true;
    var rendezvousClosed = true;

    for (final device in devices) {
      try {
        final stop = await _processRunner.run('adb', <String>[
          '-s',
          device,
          'shell',
          'am',
          'force-stop',
          packageName,
        ]);
        if (stop.exitCode != 0) processesStopped = false;
      } on Object {
        processesStopped = false;
      }
      try {
        final cleanup = await _processRunner.run('adb', <String>[
          '-s',
          device,
          'shell',
          'run-as',
          packageName,
          'rm',
          '-f',
          simsRuntimeConfigRelativePath,
          simsRuntimeAckRelativePath,
          simsRuntimeResultRelativePath,
        ]);
        if (cleanup.exitCode != 0) runtimeFilesRemoved = false;
      } on Object {
        runtimeFilesRemoved = false;
      }
    }
    if (reversePort != null) {
      for (final device in reverseMappedDevices) {
        try {
          final reverse = await _processRunner.run('adb', <String>[
            '-s',
            device,
            'reverse',
            '--remove',
            'tcp:$reversePort',
          ]);
          if (reverse.exitCode != 0) reverseMappingsRemoved = false;
        } on Object {
          reverseMappingsRemoved = false;
        }
      }
    }
    try {
      await closeRendezvous();
    } on Object {
      rendezvousClosed = false;
    }
    return AndroidForegroundWebRtcAudioProtocolCleanupResult(
      processesStopped: processesStopped,
      runtimeFilesRemoved: runtimeFilesRemoved,
      reverseMappingsRemoved: reverseMappingsRemoved,
      rendezvousClosed: rendezvousClosed,
    );
  }
}

final class _LoopbackAudioRendezvous {
  _LoopbackAudioRendezvous._(this._server, this._bearersByRole) {
    _subscription = _server.listen(_handleRequest);
  }

  static Future<_LoopbackAudioRendezvous> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _LoopbackAudioRendezvous._(server, <String, String>{
      simsForegroundWebRtcCallerRole: _randomUrlToken(32),
      simsForegroundWebRtcCalleeRole: _randomUrlToken(32),
    });
  }

  final HttpServer _server;
  final Map<String, String> _bearersByRole;
  final List<_RendezvousEvent> _events = <_RendezvousEvent>[];
  final Set<String> _joined = <String>{};
  final Map<String, List<String>> _wireDigestsByRole = <String, List<String>>{
    simsForegroundWebRtcCallerRole: <String>[],
    simsForegroundWebRtcCalleeRole: <String>[],
  };
  final Map<String, Map<String, int>> _controlCountsByRole =
      <String, Map<String, int>>{
        simsForegroundWebRtcCallerRole: <String, int>{},
        simsForegroundWebRtcCalleeRole: <String, int>{},
      };
  final Map<String, Map<String, int>> _controlDeliveryCountsByRole =
      <String, Map<String, int>>{
        simsForegroundWebRtcCallerRole: <String, int>{},
        simsForegroundWebRtcCalleeRole: <String, int>{},
      };
  late final StreamSubscription<HttpRequest> _subscription;
  var _nextSequence = 1;
  var _closed = false;

  int get port => _server.port;

  String bearerFor(String role) {
    final bearer = _bearersByRole[role];
    if (bearer == null) throw StateError('unsupported foreground audio role');
    return bearer;
  }

  Map<String, Object?> wireSummary() => <String, Object?>{
    'callerToCallee': _wireDirectionSummary(
      _wireDigestsByRole[simsForegroundWebRtcCallerRole]!,
    ),
    'calleeToCaller': _wireDirectionSummary(
      _wireDigestsByRole[simsForegroundWebRtcCalleeRole]!,
    ),
  };

  Map<String, Object?> controlSummary() => <String, Object?>{
    'calleeRingingReady':
        _controlCountsByRole[simsForegroundWebRtcCalleeRole]!['callee-ringing-ready'] ??
        0,
    'callerRingingObserved':
        _controlCountsByRole[simsForegroundWebRtcCallerRole]!['caller-ringing-observed'] ??
        0,
    'calleeRingingReadyDeliveredToCaller':
        _controlDeliveryCountsByRole[simsForegroundWebRtcCallerRole]!['callee-ringing-ready'] ??
        0,
    'callerRingingObservedDeliveredToCallee':
        _controlDeliveryCountsByRole[simsForegroundWebRtcCalleeRole]!['caller-ringing-observed'] ??
        0,
  };

  Future<void> _handleRequest(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    final role = _authenticatedRole(request);
    if (_closed || role == null) {
      await _respond(request, HttpStatus.unauthorized, const <String, Object?>{
        'accepted': false,
      });
      return;
    }
    try {
      if (request.method == 'POST' && request.uri.path == '/join') {
        final body = await _readObject(request);
        if (body.isNotEmpty) throw const FormatException('invalid join');
        _joined.add(role);
        await _respond(request, HttpStatus.ok, const <String, Object?>{
          'accepted': true,
        });
        return;
      }
      if (request.method == 'POST' && request.uri.path == '/event') {
        final body = await _readObject(request);
        final kind = body['kind'];
        final payload = _object(body['payload']);
        if (body.length != 2 ||
            !_joined.contains(role) ||
            kind is! String ||
            payload == null ||
            !validateAndroidForegroundWebRtcAudioRendezvousEvent(
              kind: kind,
              payload: payload,
            ) ||
            _events.length >= _maximumRendezvousEvents) {
          throw const FormatException('invalid event');
        }
        if (kind == 'envelope') {
          _wireDigestsByRole[role]!.add(
            sha256
                .convert(utf8.encode(payload['envelope']! as String))
                .toString(),
          );
        } else if (kind == 'control') {
          final name = payload['name']! as String;
          final counts = _controlCountsByRole[role]!;
          counts[name] = (counts[name] ?? 0) + 1;
        }
        _events.add(
          _RendezvousEvent(
            sequence: _nextSequence++,
            from: role,
            kind: kind,
            payload: payload,
          ),
        );
        await _respond(request, HttpStatus.ok, const <String, Object?>{
          'accepted': true,
        });
        return;
      }
      if (request.method == 'GET' && request.uri.path == '/events') {
        final cursor = int.tryParse(
          request.uri.queryParameters['cursor'] ?? '',
        );
        if (request.uri.queryParameters.length != 1 ||
            !_joined.contains(role) ||
            cursor == null ||
            cursor < 0) {
          throw const FormatException('invalid poll');
        }
        final selectedEvents = _events
            .where((event) => event.from != role && event.sequence > cursor)
            .take(64)
            .toList(growable: false);
        for (final event in selectedEvents) {
          if (event.kind != 'control') continue;
          final name = event.payload['name'];
          if (name is! String || !_foregroundAudioControlNames.contains(name)) {
            continue;
          }
          final counts = _controlDeliveryCountsByRole[role]!;
          counts[name] = (counts[name] ?? 0) + 1;
        }
        final events = selectedEvents
            .map((event) => event.toJson())
            .toList(growable: false);
        await _respond(request, HttpStatus.ok, <String, Object?>{
          'events': events,
        });
        return;
      }
      await _respond(request, HttpStatus.notFound, const <String, Object?>{
        'accepted': false,
      });
    } on Object {
      await _respond(request, HttpStatus.badRequest, const <String, Object?>{
        'accepted': false,
      });
    }
  }

  Future<Map<String, Object?>> _readObject(HttpRequest request) async {
    final bytes = await request.fold<List<int>>(<int>[], (buffer, chunk) {
      if (buffer.length + chunk.length > _maximumRendezvousRequestBytes) {
        throw const FormatException('request too large');
      }
      return buffer..addAll(chunk);
    });
    final decoded = jsonDecode(utf8.decode(bytes));
    final object = _object(decoded);
    if (object == null) throw const FormatException('invalid object');
    return object;
  }

  static Future<void> _respond(
    HttpRequest request,
    int status,
    Map<String, Object?> body,
  ) async {
    request.response.statusCode = status;
    request.response.write(jsonEncode(body));
    await request.response.close();
  }

  static bool _validRole(Object? role) =>
      role == simsForegroundWebRtcCallerRole ||
      role == simsForegroundWebRtcCalleeRole;

  String? _authenticatedRole(HttpRequest request) {
    final authorization = request.headers.value(
      HttpHeaders.authorizationHeader,
    );
    if (authorization == null || !authorization.startsWith('Bearer ')) {
      return null;
    }
    final bearer = authorization.substring('Bearer '.length);
    for (final entry in _bearersByRole.entries) {
      if (entry.value == bearer && _validRole(entry.key)) return entry.key;
    }
    return null;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _events.clear();
    _joined.clear();
    for (final digests in _wireDigestsByRole.values) {
      digests.clear();
    }
    for (final counts in _controlCountsByRole.values) {
      counts.clear();
    }
    for (final counts in _controlDeliveryCountsByRole.values) {
      counts.clear();
    }
    await _subscription.cancel();
    await _server.close(force: true);
  }
}

final class _RendezvousEvent {
  const _RendezvousEvent({
    required this.sequence,
    required this.from,
    required this.kind,
    required this.payload,
  });

  final int sequence;
  final String from;
  final String kind;
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() => <String, Object?>{
    'sequence': sequence,
    'kind': kind,
    'payload': payload,
  };
}

final class _AudioProofBlocked implements Exception {
  const _AudioProofBlocked(this.blocker, this.detail);

  final String blocker;
  final String detail;
}

final class _AudioProofFailure implements Exception {
  const _AudioProofFailure(this.blocker, this.detail);

  final String blocker;
  final String detail;
}

String _safeToken(String prefix) => '$prefix-${_randomUrlToken(18)}';

bool _isDeviceRoutableIpv4Host(String value) {
  final parts = value.split('.');
  if (parts.length != 4) return false;
  final octets = parts.map(int.tryParse).toList(growable: false);
  if (octets.any((octet) => octet == null || octet < 0 || octet > 255)) {
    return false;
  }
  final first = octets[0]!;
  final second = octets[1]!;
  final last = octets[3]!;
  return first != 0 &&
      first != 127 &&
      first < 224 &&
      !(first == 169 && second == 254) &&
      last != 0 &&
      last != 255;
}

String _appStateBlockCategory(String detail) {
  final normalized = detail.toLowerCase();
  if (normalized.contains('not debuggable')) return 'nonDebuggableInstalledApp';
  if (normalized.contains('backup policy')) return 'privateBackupBound';
  if (normalized.contains('structurally incomplete')) {
    return 'privateArchiveStructure';
  }
  if (normalized.contains('backup stream') ||
      normalized.contains('adb reconnect')) {
    return 'privateArchiveTransport';
  }
  if (normalized.contains('private app-data backup')) {
    return 'privateArchive';
  }
  if (normalized.contains('apk backup')) return 'apkBackup';
  if (normalized.contains('artifact custody')) return 'artifactCustody';
  if (normalized.contains('unsafe target')) return 'unsafeTarget';
  if (normalized.contains('adb')) return 'adbUnavailable';
  return 'unknown';
}

Map<String, Object?> _wireDirectionSummary(List<String> envelopeDigests) =>
    <String, Object?>{
      'count': envelopeDigests.length,
      'chainSha256': sha256
          .convert(utf8.encode(envelopeDigests.join(':')))
          .toString(),
    };

String _wireFailureDetail(Map<String, Object?>? wireSummary) {
  int countFor(String direction) {
    final summary = _object(wireSummary?[direction]);
    return switch (summary?['count']) {
      final int count when count >= 0 => count,
      _ => 0,
    };
  }

  return 'Opaque envelope counts: '
      'caller=${countFor('callerToCallee')}, '
      'callee=${countFor('calleeToCaller')}.';
}

String _controlFailureDetail(Map<String, Object?>? controlSummary) {
  int countFor(String name) => switch (controlSummary?[name]) {
    final int count when count >= 0 => count,
    _ => 0,
  };

  return 'Handshake controls: '
      'calleeRingingReady=${countFor('calleeRingingReady')}, '
      'callerRingingObserved=${countFor('callerRingingObserved')}, '
      'calleeRingingReadyDeliveredToCaller='
      '${countFor('calleeRingingReadyDeliveredToCaller')}, '
      'callerRingingObservedDeliveredToCallee='
      '${countFor('callerRingingObservedDeliveredToCallee')}.';
}

String _failedEndpointDetail(
  SimsRuntimeInvocation invocation,
  Map<String, Object?> endpoint,
) {
  final failure = _object(endpoint['failure'])!;
  return 'The ${invocation.role} foreground WebRTC audio endpoint failed at '
      '${failure['stage']} '
      '(state=${failure['state']}, endReason=${failure['endReason']}, '
      'effect=${failure['effect']}, followUp=${failure['followUp']}, '
      'probeStage=${failure['probeStage']}, '
      'turnConfigStage=${failure['turnConfigStage']}, '
      'engineError=${failure['engineError']}, '
      'descriptionSecurity=${failure['descriptionSecurity']}, '
      'descriptionCandidates=${failure['descriptionCandidates']}, '
      'readinessFailure=${failure['readinessFailure']}, '
      'selectedTransport=${failure['selectedTransport']}, '
      'selectedRelayProtocol=${failure['selectedRelayProtocol']}, '
      'clientStage=${failure['clientStage']}, '
      'inboundOutcome=${failure['inboundOutcome']}, '
      'controlsPublished=${failure['publishedControlCount']}, '
      'controlsReceived=${failure['receivedControlCount']}).';
}

String _randomUrlToken(int byteCount) {
  final random = Random.secure();
  return base64Url
      .encode(List<int>.generate(byteCount, (_) => random.nextInt(256)))
      .replaceAll('=', '');
}

Map<String, Object?>? _object(Object? value) => value is Map
    ? value.map<String, Object?>((key, entry) => MapEntry('$key', entry))
    : null;

Directory _proofDirectory(Map<String, String> environment) {
  final configured = environment['SIMS_PROOF_DIRECTORY']?.trim();
  if (configured != null && configured.isNotEmpty) {
    return Directory(configured).absolute;
  }
  return Directory(
    'build/sims/proofs/$simsAndroidForegroundWebRtcAudioScenarioId',
  ).absolute;
}
