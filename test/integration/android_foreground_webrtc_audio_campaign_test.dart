import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/features/call/infrastructure/webrtc_types.dart';
import 'package:flutter_app/features/call/infrastructure/call_stats_sampler.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/sims/artifact_evidence.dart';
import '../../tool/sims/verdict.dart';
import '../../integration_test/scripts/android_foreground_webrtc_audio_campaign.dart';
import '../../integration_test/support/android_app_state_guard.dart';
import '../../integration_test/support/android_foreground_webrtc_audio_evidence.dart';
import '../../integration_test/support/android_foreground_webrtc_audio_probe.dart';
import '../../integration_test/support/android_foreground_webrtc_audio_proof.dart';
import '../../integration_test/support/sims_runtime_protocol.dart';

const _apkDigest =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _physicalDigest =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _emulatorDigest =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
const _callBinding =
    'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
const _callerToCalleeChain =
    'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';
const _calleeToCallerChain =
    'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';
const _bearer = 'abcdefghijklmnopqrstuvwxyzABCDEFGH_123456789';
const _turnUsername = 'relay-proof-user';
const _turnPassword = 'relay-proof-password';

const List<String> _expectedAssertions = <String>[
  'call_audio.foreground_resumed',
  'call_audio.accepted_only',
  'call_audio.permission_granted',
  'call_audio.audio_only_structural_ready',
  'call_audio.both_muted',
  'call_audio.caller_to_callee_rtp_delta',
  'call_audio.callee_to_caller_rtp_delta',
  'call_audio.routes_exercised',
  'call_audio.cleanup_restored',
  'call_audio.canonical_place_invite',
  'call_audio.canonical_ringing',
  'call_audio.canonical_accept_both_reducers',
  'call_audio.encrypted_call_control_v1',
  'call_audio.no_preaccept_microphone_sdp_ice',
  'call_audio.connected_from_canonical_readiness',
  'call_audio.same_lan_direct_selected',
  'call_audio.canonical_end_terminate',
  'call_audio.cleanup_exactly_once',
];

SimsRuntimeInvocation _invocation(String role) => SimsRuntimeInvocation(
  schema: simsRuntimeConfigSchema,
  profileId: simsAndroidStandardProfileId,
  scenarioId: simsAndroidForegroundWebRtcAudioScenarioId,
  role: role,
  runId: 'audio-run-1',
  nonce: role == simsForegroundWebRtcCallerRole
      ? 'caller-nonce-1'
      : 'callee-nonce-1',
  values: <String, Object?>{
    'rendezvousUrl': 'http://127.0.0.1:43123',
    'bearer': _bearer,
    'targetKind': role == simsForegroundWebRtcCallerRole
        ? 'physical'
        : 'emulator',
    'sharedApkSha256': _apkDigest,
  },
);

SimsRuntimeInvocation _relayInvocation(
  String role,
  AndroidForegroundWebRtcAudioRelayMode mode,
) => SimsRuntimeInvocation(
  schema: simsRuntimeConfigSchema,
  profileId: simsAndroidStandardProfileId,
  scenarioId: simsAndroidForegroundWebRtcAudioScenarioId,
  role: role,
  runId: 'audio-${mode.name}-run-1',
  nonce: '${mode.name}-$role-nonce-1',
  values: <String, Object?>{
    'rendezvousUrl': 'http://127.0.0.1:43123',
    'bearer': _bearer,
    'targetKind': role == simsForegroundWebRtcCallerRole
        ? 'physical'
        : 'emulator',
    'sharedApkSha256': _apkDigest,
    'relayMode': mode.name,
    'turnUrls': mode == AndroidForegroundWebRtcAudioRelayMode.turnUdp
        ? <String>['turn:192.0.2.10:3478?transport=udp']
        : <String>[
            'turn:192.0.2.10:3479?transport=udp',
            'turn:192.0.2.10:3479?transport=tcp',
          ],
    'turnUsername': _turnUsername,
    'turnPassword': _turnPassword,
    'turnExpiresAtMs': DateTime.utc(
      2030,
    ).add(const Duration(minutes: 5)).millisecondsSinceEpoch,
  },
);

Map<String, Object?> _canonicalJourney() => <String, Object?>{
  'coordinatorDriven': true,
  'placeInvite': true,
  'ringing': true,
  'acceptApplied': true,
  'encryptedSignaling': true,
  'noPreAcceptMedia': true,
  'connectedByReducer': true,
  'canonicalEnd': true,
};

Map<String, Object?> _connectedReadiness() => <String, Object?>{
  'selectedPairSucceeded': true,
  'selectedPairNominated': true,
  'iceConnected': true,
  'dtlsReady': true,
  'audioSessionActive': true,
  'localAudioSenderAttached': true,
  'localAudioTrackLive': true,
  'remoteAudioReceiverAttached': true,
  'remoteAudioTrackLive': true,
};

Map<String, Object?> _outboundSignalCounts(String role) {
  final caller = role == simsForegroundWebRtcCallerRole;
  return <String, Object?>{
    'invite': caller ? 1 : 0,
    'ringing': caller ? 0 : 1,
    'accept': caller ? 0 : 1,
    'reject': 0,
    'offer': caller ? 1 : 0,
    'answer': caller ? 0 : 1,
    'ice': caller ? 2 : 1,
    'ice_restart': 0,
    'terminate': caller ? 1 : 0,
  };
}

int _outboundEnvelopeCount(String role) => _outboundSignalCounts(
  role,
).values.fold<int>(0, (sum, value) => sum + (value as int));

Map<String, Object?> _signalingTrace(String role) {
  final caller = role == simsForegroundWebRtcCallerRole;
  final oppositeRole = caller
      ? simsForegroundWebRtcCalleeRole
      : simsForegroundWebRtcCallerRole;
  return <String, Object?>{
    'reducerPathSha256': androidForegroundWebRtcAudioReducerPathSha256(role),
    'outboundEnvelopeCount': _outboundEnvelopeCount(role),
    'inboundEnvelopeCount': _outboundEnvelopeCount(oppositeRole),
    'outboundEnvelopeChainSha256': caller
        ? _callerToCalleeChain
        : _calleeToCallerChain,
    'inboundEnvelopeChainSha256': caller
        ? _calleeToCallerChain
        : _callerToCalleeChain,
    'outboundSignalCounts': _outboundSignalCounts(role),
  };
}

Map<String, Object?> _endpoint(String role) {
  final invocation = _invocation(role);
  final caller = role == simsForegroundWebRtcCallerRole;
  return <String, Object?>{
    'schema': androidForegroundWebRtcAudioEndpointSchema,
    'scenario': simsAndroidForegroundWebRtcAudioScenarioId,
    'status': 'passed',
    'role': role,
    'targetKind': caller ? 'physical' : 'emulator',
    'bindingSha256': androidForegroundWebRtcAudioBindingSha256(invocation),
    'callBindingSha256': _callBinding,
    'foregroundResumed': true,
    'locallyAccepted': true,
    'permissionGranted': true,
    'audioOnly': true,
    'mediaReady': true,
    'directSelected': true,
    'bothMuted': true,
    'canonicalJourney': _canonicalJourney(),
    'connectedReadiness': _connectedReadiness(),
    'signalingTrace': _signalingTrace(role),
    'route': <String, Object?>{
      'speakerSupported': true,
      'speakerSelected': true,
      'finalRoute': 'systemDefault',
    },
    'directionalRtpDelta': <String, Object?>{
      'callerToCalleeOutbound': caller,
      'callerToCalleeInbound': !caller,
      'calleeToCallerOutbound': !caller,
      'calleeToCallerInbound': caller,
    },
    'cleanup': <String, Object?>{
      'connectionClosed': true,
      'audioSessionReleased': true,
      'bundleClosedExactlyOnce': true,
      'coordinatorCleanupExactlyOnce': true,
      'historyProjectedExactlyOnce': true,
      'signalingContextPurged': true,
      'negotiationMaterialPurged': true,
    },
  };
}

Map<String, Object?> _wireSummary() => <String, Object?>{
  'callerToCallee': <String, Object?>{
    'count': _outboundEnvelopeCount(simsForegroundWebRtcCallerRole),
    'chainSha256': _callerToCalleeChain,
  },
  'calleeToCaller': <String, Object?>{
    'count': _outboundEnvelopeCount(simsForegroundWebRtcCalleeRole),
    'chainSha256': _calleeToCallerChain,
  },
};

Map<String, Object?> _failedEndpoint(String role) =>
    androidForegroundWebRtcAudioFailedEndpoint(
      invocation: _invocation(role),
      stage: AndroidForegroundWebRtcAudioFailureStage.mediaReadiness,
      state: 'ended',
      endReason: 'mediaFailed',
      effect: 'cleanup',
      followUp: 'negotiationFailed',
    );

Map<String, Object?> _relayEndpoint(
  String role,
  AndroidForegroundWebRtcAudioRelayMode mode,
) {
  final invocation = _relayInvocation(role, mode);
  final caller = role == simsForegroundWebRtcCallerRole;
  return <String, Object?>{
    'schema': androidForegroundWebRtcAudioRelayEndpointSchema,
    'scenario': simsAndroidForegroundWebRtcAudioScenarioId,
    'status': 'passed',
    'role': role,
    'targetKind': caller ? 'physical' : 'emulator',
    'relayMode': mode.name,
    'bindingSha256': androidForegroundWebRtcAudioBindingSha256(invocation),
    'callBindingSha256': mode == AndroidForegroundWebRtcAudioRelayMode.turnUdp
        ? _callBinding
        : _callerToCalleeChain,
    'foregroundResumed': true,
    'locallyAccepted': true,
    'permissionGranted': true,
    'audioOnly': true,
    'mediaReady': true,
    'bothMuted': true,
    'canonicalJourney': _canonicalJourney(),
    'connectedReadiness': _connectedReadiness(),
    'signalingTrace': _signalingTrace(role),
    'bridgeCredentialPath': <String, Object?>{
      'commandExact': true,
      'providerReadExactlyOnce': true,
      'preparerRequiredTurn': true,
      'modeBoundTransportOptions': true,
    },
    'relayPrivacy': <String, Object?>{
      'transportPolicyRelayOnly': true,
      'relayCandidateSignaled': true,
      'trickleNonRelayCountZero': true,
      'embeddedSdpNonRelayCountZero': true,
    },
    'selectedTransport': mode == AndroidForegroundWebRtcAudioRelayMode.turnUdp
        ? 'turnUdp'
        : 'turnTcpTls',
    'selectedRelayProtocol':
        mode == AndroidForegroundWebRtcAudioRelayMode.turnUdp ? 'udp' : 'tcp',
    'tcpFallbackPrecondition': <String, Object?>{
      'applied': mode == AndroidForegroundWebRtcAudioRelayMode.turnTcp,
      'udpProbeAttempts': mode == AndroidForegroundWebRtcAudioRelayMode.turnTcp
          ? 3
          : 0,
      'udpStunResponseAbsent':
          mode == AndroidForegroundWebRtcAudioRelayMode.turnTcp,
      'tcpReachable': mode == AndroidForegroundWebRtcAudioRelayMode.turnTcp,
    },
    'directionalRtpDelta': <String, Object?>{
      'callerToCalleeOutbound': caller,
      'callerToCalleeInbound': !caller,
      'calleeToCallerOutbound': !caller,
      'calleeToCallerInbound': caller,
    },
    'acceptToAudioMs': mode == AndroidForegroundWebRtcAudioRelayMode.turnUdp
        ? (caller ? 900 : 950)
        : (caller ? 1100 : 1150),
    'cleanup': <String, Object?>{
      'connectionClosed': true,
      'audioSessionReleased': true,
      'bundleClosedExactlyOnce': true,
      'coordinatorCleanupExactlyOnce': true,
      'historyProjectedExactlyOnce': true,
      'signalingContextPurged': true,
      'negotiationMaterialPurged': true,
    },
  };
}

Map<String, Object?> _aggregate({
  Map<String, Object?>? caller,
  Map<String, Object?>? callee,
  Map<String, Object?>? wireSummary,
  bool processesStopped = true,
  bool runtimeFilesRemoved = true,
  bool reverseMappingsRemoved = true,
  bool rendezvousClosed = true,
  bool appStateRestored = true,
}) => aggregateAndroidForegroundWebRtcAudioEvidence(
  callerEndpoint: caller ?? _endpoint(simsForegroundWebRtcCallerRole),
  calleeEndpoint: callee ?? _endpoint(simsForegroundWebRtcCalleeRole),
  callerInvocation: _invocation(simsForegroundWebRtcCallerRole),
  calleeInvocation: _invocation(simsForegroundWebRtcCalleeRole),
  wireSummary: wireSummary ?? _wireSummary(),
  sharedApkSha256: _apkDigest,
  physicalTargetDigest: _physicalDigest,
  emulatorTargetDigest: _emulatorDigest,
  processesStopped: processesStopped,
  runtimeFilesRemoved: runtimeFilesRemoved,
  reverseMappingsRemoved: reverseMappingsRemoved,
  rendezvousClosed: rendezvousClosed,
  appStateRestored: appStateRestored,
);

AndroidForegroundWebRtcAudioRelayLegEvidence _relayLeg(
  AndroidForegroundWebRtcAudioRelayMode mode,
) => AndroidForegroundWebRtcAudioRelayLegEvidence(
  mode: mode,
  callerEndpoint: _relayEndpoint(simsForegroundWebRtcCallerRole, mode),
  calleeEndpoint: _relayEndpoint(simsForegroundWebRtcCalleeRole, mode),
  callerInvocation: _relayInvocation(simsForegroundWebRtcCallerRole, mode),
  calleeInvocation: _relayInvocation(simsForegroundWebRtcCalleeRole, mode),
  wireSummary: _wireSummary(),
  processesStopped: true,
  runtimeFilesRemoved: true,
  reverseMappingsRemoved: true,
  rendezvousClosed: true,
  appStateRestored: true,
);

Map<String, Object?> _relayAggregate() =>
    aggregateAndroidForegroundWebRtcAudioRelayEvidence(
      legs: <AndroidForegroundWebRtcAudioRelayLegEvidence>[
        _relayLeg(AndroidForegroundWebRtcAudioRelayMode.turnUdp),
        _relayLeg(AndroidForegroundWebRtcAudioRelayMode.turnTcp),
      ],
      sharedApkSha256: _apkDigest,
    );

void main() {
  test('latency failure reports the product gate without claiming success', () {
    final result = AndroidForegroundWebRtcAudioCampaignResult.latencyExceeded(
      const AndroidForegroundWebRtcAudioLatencyExceeded(3001),
    );
    expect(result.processExitCode, 1);
    expect(result.json['status'], 'FAIL');
    expect(result.json['blocker'], 'product');
    expect(result.json['artifactPresent'], isFalse);
    expect(result.json['assertionsAttempted'], 18);
    expect(result.json['detail'], contains('p95=3001ms exceeded 3000ms'));
  });

  test('selected relay probe cannot report complete campaign success', () {
    final result = AndroidForegroundWebRtcAudioCampaignResult.relayProbePassed(
      AndroidForegroundWebRtcAudioRelayMode.turnTcp,
    );
    expect(result.processExitCode, 78);
    expect(result.json['status'], 'BLOCKED');
    expect(result.json['selectedTransport'], 'turnTcp');
    expect(result.json['selectedTransportStatus'], 'PASS');
    expect(result.json['fullCampaignCompleted'], isFalse);
    expect(result.json['artifactPresent'], isFalse);
  });

  test('invalid relay probe fails before target or artifact work', () async {
    final result = await runAndroidForegroundWebRtcAudioCampaign(
      devices: const [],
      artifactPath: null,
      environment: const {'SIMS_FOREGROUND_WEBRTC_RELAY_PROBE': 'invalid'},
    );
    expect(result.processExitCode, 78);
    expect(result.json['detail'], contains('must name turnUdp or turnTcp'));
    expect(result.json['assertionsAttempted'], 0);
  });

  test('selected pair evidence keeps relationships without stats material', () {
    final evidence = androidForegroundSelectedPairDiagnostic([
      CallStatsRecord(
        id: 'private-transport-id',
        type: 'transport',
        values: {'selectedCandidatePairId': 'private-pair-id'},
      ),
      CallStatsRecord(
        id: 'private-pair-id',
        type: 'candidate-pair',
        values: {
          'state': 'in-progress',
          'nominated': true,
          'address': '192.0.2.99',
          'bytesSent': 9999,
        },
      ),
      CallStatsRecord(
        id: 'another-private-pair',
        type: 'candidate-pair',
        values: {'state': 'succeeded', 'nominated': true},
      ),
    ]);
    expect(evidence, {
      'transportSelectedPairs': 1,
      'missingSelectedReferences': 0,
      'selectedPairState': 'in-progress',
      'nominatedSucceeded': 1,
      'nominatedOther': 1,
    });
    expect(jsonEncode(evidence), isNot(contains('private')));
    expect(jsonEncode(evidence), isNot(contains('192.0.2.99')));
    expect(jsonEncode(evidence), isNot(contains('9999')));
  });
  test('generic artifact wrapper preserves canonical and relay proofs', () {
    final directory = Directory.systemTemp.createTempSync(
      'foreground-webrtc-audio-artifact-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final canonical = _aggregate();
    final relay = _relayAggregate();
    final artifact = writeSimsArtifactEvidenceSync(
      directory: directory,
      capabilityId: simsAndroidForegroundWebRtcAudioScenarioId,
      validatorIds: const <String>[
        androidForegroundWebRtcAudioArtifactValidatorId,
      ],
      payload: androidForegroundWebRtcAudioArtifactPayload(
        canonical: canonical,
        relay: relay,
      ),
    );
    final durable = (jsonDecode(File(artifact.path).readAsStringSync()) as Map)
        .map<String, Object?>((key, value) => MapEntry('$key', value));

    expect(durable['schema'], 'mknoon.sims.proof.v1');
    final proofs = androidForegroundWebRtcAudioProofsFromArtifact(durable);
    expect(proofs.canonical, canonical);
    expect(proofs.relay, relay);
    expect(validateAndroidForegroundWebRtcAudioEvidence(durable).ok, isFalse);
  });

  test('connected readiness watcher emits one bounded final pulse', () async {
    var samples = 0;
    var pulses = 0;
    final watcher = AndroidForegroundWebRtcReadinessPulse(
      sampleReady: () async => ++samples >= 2,
      emitReadyPulse: () => pulses++,
      pollInterval: Duration.zero,
      maximumSamples: 3,
    );
    addTearDown(watcher.close);

    watcher.observe(WebRtcConnectionState.connected);
    watcher.observe(WebRtcConnectionState.connected);
    await watcher.settled;
    expect(samples, 2);
    expect(pulses, 1);

    watcher.observe(WebRtcConnectionState.connected);
    await watcher.settled;
    expect(samples, 2);
    expect(pulses, 1);
  });

  test('created description candidate profile is enum-only', () {
    expect(
      classifyAndroidForegroundWebRtcAudioDescriptionCandidates(
        'v=0\r\na=fingerprint:sha-256 00:11\r\n',
      ),
      AndroidForegroundWebRtcAudioDescriptionCandidateProfile.none,
    );
    expect(
      classifyAndroidForegroundWebRtcAudioDescriptionCandidates(
        'v=0\r\na=candidate:1 1 udp 1 192.0.2.1 9 typ relay\r\n',
      ),
      AndroidForegroundWebRtcAudioDescriptionCandidateProfile.relayOnly,
    );
    expect(
      classifyAndroidForegroundWebRtcAudioDescriptionCandidates(
        'v=0\r\na=candidate:1 1 udp 1 192.0.2.1 9 typ host\r\n',
      ),
      AndroidForegroundWebRtcAudioDescriptionCandidateProfile.nonRelayPresent,
    );
  });

  test('created description security profile is enum-only', () {
    final fingerprintA = List<String>.filled(32, 'AA').join(':');
    final fingerprintB = List<String>.filled(32, 'BB').join(':');

    expect(
      classifyAndroidForegroundWebRtcAudioDescriptionSecurity(
        'v=0\r\na=fingerprint:sha-256 $fingerprintA\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n',
      ),
      AndroidForegroundWebRtcAudioDescriptionSecurityProfile
          .validAudioOnlySha256,
    );
    expect(
      classifyAndroidForegroundWebRtcAudioDescriptionSecurity(
        'v=0\r\na=fingerprint:SHA-256 $fingerprintA\r\n',
      ),
      AndroidForegroundWebRtcAudioDescriptionSecurityProfile.sha256CaseVariant,
    );
    expect(
      classifyAndroidForegroundWebRtcAudioDescriptionSecurity('v=0\r\n'),
      AndroidForegroundWebRtcAudioDescriptionSecurityProfile.fingerprintMissing,
    );
    expect(
      classifyAndroidForegroundWebRtcAudioDescriptionSecurity(
        'v=0\r\na=fingerprint:sha-256 AA:BB\r\n',
      ),
      AndroidForegroundWebRtcAudioDescriptionSecurityProfile
          .fingerprintMalformed,
    );
    expect(
      classifyAndroidForegroundWebRtcAudioDescriptionSecurity(
        'v=0\r\na=fingerprint:sha-256 $fingerprintA\r\n'
        'a=fingerprint:sha-256 $fingerprintB\r\n',
      ),
      AndroidForegroundWebRtcAudioDescriptionSecurityProfile
          .fingerprintAmbiguous,
    );
    expect(
      classifyAndroidForegroundWebRtcAudioDescriptionSecurity(
        'v=0\r\na=fingerprint:sha-256 $fingerprintA\r\n'
        'm=video 9 UDP/TLS/RTP/SAVPF 96\r\n',
      ),
      AndroidForegroundWebRtcAudioDescriptionSecurityProfile.videoPresent,
    );
  });

  test('TCP fallback precondition is bounded and endpoint-observed', () async {
    var udpCalls = 0;
    var tcpCalls = 0;
    final passing =
        await runAndroidForegroundWebRtcAudioTcpFallbackPrecondition(
          host: '192.0.2.10',
          port: 3479,
          udpProbe: ({required host, required port, required timeout}) async {
            udpCalls++;
            expect(host, '192.0.2.10');
            expect(port, 3479);
            expect(timeout, lessThanOrEqualTo(const Duration(seconds: 1)));
            return AndroidForegroundWebRtcAudioUdpProbeOutcome
                .noMatchingResponse;
          },
          tcpProbe: ({required host, required port, required timeout}) async {
            tcpCalls++;
            expect(timeout, lessThanOrEqualTo(const Duration(seconds: 2)));
            return true;
          },
        );
    expect(udpCalls, 3);
    expect(tcpCalls, 1);
    expect(passing.proven, isTrue);
    expect(passing.toEvidence(), <String, Object?>{
      'applied': true,
      'udpProbeAttempts': 3,
      'udpStunResponseAbsent': true,
      'tcpReachable': true,
    });

    final udpResponded =
        await runAndroidForegroundWebRtcAudioTcpFallbackPrecondition(
          host: '192.0.2.10',
          port: 3479,
          udpProbe: ({required host, required port, required timeout}) async =>
              AndroidForegroundWebRtcAudioUdpProbeOutcome.matchingResponse,
          tcpProbe: ({required host, required port, required timeout}) async =>
              true,
        );
    expect(udpResponded.proven, isFalse);

    final tcpFailed =
        await runAndroidForegroundWebRtcAudioTcpFallbackPrecondition(
          host: '192.0.2.10',
          port: 3479,
          udpProbe: ({required host, required port, required timeout}) async =>
              AndroidForegroundWebRtcAudioUdpProbeOutcome.noMatchingResponse,
          tcpProbe: ({required host, required port, required timeout}) async =>
              false,
        );
    expect(tcpFailed.proven, isFalse);

    final udpProbeErrored =
        await runAndroidForegroundWebRtcAudioTcpFallbackPrecondition(
          host: '192.0.2.10',
          port: 3479,
          udpProbe: ({required host, required port, required timeout}) async =>
              AndroidForegroundWebRtcAudioUdpProbeOutcome.probeError,
          tcpProbe: ({required host, required port, required timeout}) async =>
              true,
        );
    expect(udpProbeErrored.proven, isFalse);

    final bounded = Stopwatch()..start();
    final timedOut =
        await runAndroidForegroundWebRtcAudioTcpFallbackPrecondition(
          host: '192.0.2.10',
          port: 3479,
          udpTimeout: const Duration(milliseconds: 1),
          tcpTimeout: const Duration(milliseconds: 10),
          udpProbe: ({required host, required port, required timeout}) =>
              Completer<AndroidForegroundWebRtcAudioUdpProbeOutcome>().future,
          tcpProbe: ({required host, required port, required timeout}) =>
              Completer<bool>().future,
        );
    bounded.stop();
    expect(timedOut.proven, isFalse);
    expect(bounded.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test('native offer and answer use exact audio-only SDP constraints', () {
    final probeSource = File(
      'integration_test/support/android_foreground_webrtc_audio_probe.dart',
    ).readAsStringSync();
    final productionSource = File(
      'lib/features/call/infrastructure/flutter_webrtc_call_engine.dart',
    ).readAsStringSync();
    final typesSource = File(
      'lib/features/call/infrastructure/webrtc_types.dart',
    ).readAsStringSync();

    expect(typesSource, contains("'OfferToReceiveAudio': true"));
    expect(typesSource, contains("'OfferToReceiveVideo': false"));
    expect(
      probeSource,
      contains(
        'final description = await create(webRtcAudioOnlySdpConstraints);',
      ),
    );
    expect(
      RegExp(
        r'connection\.create(?:Offer|Answer)\(\s*webRtcAudioOnlySdpConstraints',
      ).allMatches(productionSource),
      hasLength(2),
    );
  });

  test(
    'foreground WebRTC leaves Android audio focus with the call session',
    () {
      final productionSource = File(
        'lib/features/call/infrastructure/flutter_webrtc_call_engine.dart',
      ).readAsStringSync();
      final probeSource = File(
        'integration_test/support/android_foreground_webrtc_audio_probe.dart',
      ).readAsStringSync();

      expect(productionSource, contains('manageAudioFocus: false'));
      final focusConfiguration = probeSource.indexOf(
        'await configureFlutterWebRtcForExternalAudioFocus();',
      );
      final peerCreation = probeSource.indexOf(
        'connection = await webrtc.createPeerConnection',
      );
      expect(focusConfiguration, greaterThanOrEqualTo(0));
      expect(peerCreation, greaterThan(focusConfiguration));
    },
  );

  test('captured audio uses addTrack so the callee reuses one transceiver', () {
    final productionSource = File(
      'lib/features/call/infrastructure/flutter_webrtc_call_engine.dart',
    ).readAsStringSync();
    final probeSource = File(
      'integration_test/support/android_foreground_webrtc_audio_probe.dart',
    ).readAsStringSync();

    for (final source in <String>[productionSource, probeSource]) {
      expect(
        RegExp(
          r'await connection\.addTrack\(\s*(?:localTrack|track),\s*'
          r'(?:localStream|stream),?\s*\);',
        ).hasMatch(source),
        isTrue,
      );
      expect(
        RegExp(r'connection\.addTransceiver\(\s*track:').hasMatch(source),
        isFalse,
      );
    }
  });

  test('device probe preserves the exact stats-derived relay protocol', () {
    final probeSource = File(
      'integration_test/support/android_foreground_webrtc_audio_probe.dart',
    ).readAsStringSync();

    expect(
      RegExp(
        r'selectedRelayProtocol:\s*_webRtcRelayProtocol\('
        r'\s*sample\.selectedRelayProtocol,?\s*\)',
      ).hasMatch(probeSource),
      isTrue,
    );
    for (final protocol in const <String>[
      'notRelay',
      'unknown',
      'udp',
      'tcp',
      'tls',
    ]) {
      expect(
        probeSource,
        contains(
          'CallRelayProtocol.$protocol => WebRtcRelayProtocol.$protocol',
        ),
        reason: protocol,
      );
    }
  });

  test(
    'failed endpoint marker is bounded, enum-only, and invocation-bound',
    () {
      final invocation = _invocation(simsForegroundWebRtcCallerRole);
      final failed = _failedEndpoint(simsForegroundWebRtcCallerRole);

      expect(
        validateAndroidForegroundWebRtcAudioFailedEndpoint(
          failed,
          invocation: invocation,
        ).ok,
        isTrue,
      );
      expect(jsonEncode(failed).length, lessThan(1024));
      final failure = failed['failure']! as Map<String, Object?>;
      expect(failure['turnConfigStage'], 'notRequested');
      expect(failure['descriptionCandidates'], 'notCreated');
      expect(failure['descriptionSecurity'], 'notCreated');
      expect(failure['engineError'], 'none');
      expect(failure['readinessFailure'], 'notCaptured');
      expect(failure['selectedTransport'], 'none');
      expect(failure['selectedRelayProtocol'], 'none');

      for (final readinessFailure in <String>[
        'permissionNotGranted',
        'audioCaptureMissing',
        'audioCaptureMultiple',
        'videoCapturePresent',
        'audioReceiveMissing',
        'audioReceiveMultiple',
        'videoTransceiverPresent',
        'mediaNotReady',
        'iceConnectionNotReady',
        'selectedPairNotSucceeded',
        'selectedPairNotNominated',
        'dtlsNotReady',
        'audioSessionInactive',
        'localAudioSenderMissing',
        'localAudioTrackNotLive',
        'remoteAudioReceiverMissing',
        'remoteAudioTrackNotLive',
        'transportUnknown',
        'relayProtocolUnknown',
        'transportMismatch',
        'ready',
      ]) {
        expect(
          validateAndroidForegroundWebRtcAudioFailedEndpoint(
            androidForegroundWebRtcAudioFailedEndpoint(
              invocation: invocation,
              stage: AndroidForegroundWebRtcAudioFailureStage.mediaReadiness,
              state: 'connected',
              endReason: 'none',
              effect: 'queueIceCandidate',
              followUp: 'none',
              readinessFailure: readinessFailure,
            ),
            invocation: invocation,
          ).ok,
          isTrue,
        );
      }

      final rawDetail = Map<String, Object?>.from(failed)
        ..['detail'] = 'candidate:raw-private-material';
      expect(
        validateAndroidForegroundWebRtcAudioFailedEndpoint(
          rawDetail,
          invocation: invocation,
        ).ok,
        isFalse,
      );

      final invalidEnum = Map<String, Object?>.from(failed);
      final invalidFailure = Map<String, Object?>.from(
        invalidEnum['failure']! as Map<String, Object?>,
      )..['state'] = 'candidate:raw-private-material';
      invalidEnum['failure'] = invalidFailure;
      expect(
        validateAndroidForegroundWebRtcAudioFailedEndpoint(
          invalidEnum,
          invocation: invocation,
        ).ok,
        isFalse,
      );

      final invalidProbeStage = Map<String, Object?>.from(failed);
      final invalidProbeFailure = Map<String, Object?>.from(
        invalidProbeStage['failure']! as Map<String, Object?>,
      )..['probeStage'] = 'raw-sdp-stage';
      invalidProbeStage['failure'] = invalidProbeFailure;
      expect(
        validateAndroidForegroundWebRtcAudioFailedEndpoint(
          invalidProbeStage,
          invocation: invocation,
        ).ok,
        isFalse,
      );

      final invalidTurnConfig = Map<String, Object?>.from(failed);
      final invalidTurnConfigFailure = Map<String, Object?>.from(
        invalidTurnConfig['failure']! as Map<String, Object?>,
      )..['turnConfigStage'] = 'turn:192.0.2.10:3478';
      invalidTurnConfig['failure'] = invalidTurnConfigFailure;
      expect(
        validateAndroidForegroundWebRtcAudioFailedEndpoint(
          invalidTurnConfig,
          invocation: invocation,
        ).ok,
        isFalse,
      );

      final invalidDescriptionCandidates = Map<String, Object?>.from(failed);
      final invalidDescriptionCandidatesFailure = Map<String, Object?>.from(
        invalidDescriptionCandidates['failure']! as Map<String, Object?>,
      )..['descriptionCandidates'] = 'candidate:raw-private-material';
      invalidDescriptionCandidates['failure'] =
          invalidDescriptionCandidatesFailure;
      expect(
        validateAndroidForegroundWebRtcAudioFailedEndpoint(
          invalidDescriptionCandidates,
          invocation: invocation,
        ).ok,
        isFalse,
      );

      final invalidDescriptionSecurity = Map<String, Object?>.from(failed);
      final invalidDescriptionSecurityFailure = Map<String, Object?>.from(
        invalidDescriptionSecurity['failure']! as Map<String, Object?>,
      )..['descriptionSecurity'] = 'fingerprint:raw-private-material';
      invalidDescriptionSecurity['failure'] = invalidDescriptionSecurityFailure;
      expect(
        validateAndroidForegroundWebRtcAudioFailedEndpoint(
          invalidDescriptionSecurity,
          invocation: invocation,
        ).ok,
        isFalse,
      );

      final invalidEngineError = Map<String, Object?>.from(failed);
      final invalidEngineErrorFailure = Map<String, Object?>.from(
        invalidEngineError['failure']! as Map<String, Object?>,
      )..['engineError'] = 'raw-engine-exception';
      invalidEngineError['failure'] = invalidEngineErrorFailure;
      expect(
        validateAndroidForegroundWebRtcAudioFailedEndpoint(
          invalidEngineError,
          invocation: invocation,
        ).ok,
        isFalse,
      );

      final invalidReadinessFailure = Map<String, Object?>.from(failed);
      final invalidReadiness = Map<String, Object?>.from(
        invalidReadinessFailure['failure']! as Map<String, Object?>,
      )..['readinessFailure'] = 'relay:raw-address';
      invalidReadinessFailure['failure'] = invalidReadiness;
      expect(
        validateAndroidForegroundWebRtcAudioFailedEndpoint(
          invalidReadinessFailure,
          invocation: invocation,
        ).ok,
        isFalse,
      );

      final invalidSelectedTransport = Map<String, Object?>.from(failed);
      final invalidTransport = Map<String, Object?>.from(
        invalidSelectedTransport['failure']! as Map<String, Object?>,
      )..['selectedTransport'] = 'udp://raw-address';
      invalidSelectedTransport['failure'] = invalidTransport;
      expect(
        validateAndroidForegroundWebRtcAudioFailedEndpoint(
          invalidSelectedTransport,
          invocation: invocation,
        ).ok,
        isFalse,
      );

      final invalidSelectedRelayProtocol = Map<String, Object?>.from(failed);
      final invalidRelayProtocol = Map<String, Object?>.from(
        invalidSelectedRelayProtocol['failure']! as Map<String, Object?>,
      )..['selectedRelayProtocol'] = 'udp://raw-address';
      invalidSelectedRelayProtocol['failure'] = invalidRelayProtocol;
      expect(
        validateAndroidForegroundWebRtcAudioFailedEndpoint(
          invalidSelectedRelayProtocol,
          invocation: invocation,
        ).ok,
        isFalse,
      );

      expect(
        validateAndroidForegroundWebRtcAudioFailedEndpoint(
          failed,
          invocation: _invocation(simsForegroundWebRtcCalleeRole),
        ).ok,
        isFalse,
      );
    },
  );

  test(
    'direct-engine v1 endpoint cannot satisfy canonical journey contract',
    () {
      final directEngineV1 = _endpoint(simsForegroundWebRtcCallerRole)
        ..['schema'] = 'mknoon.sims.android-foreground-webrtc-audio-endpoint.v1'
        ..remove('callBindingSha256')
        ..remove('canonicalJourney')
        ..remove('signalingTrace')
        ..['cleanup'] = <String, Object?>{
          'connectionClosed': true,
          'audioSessionReleased': true,
        };

      expect(
        validateAndroidForegroundWebRtcAudioEndpoint(
          directEngineV1,
          invocation: _invocation(simsForegroundWebRtcCallerRole),
        ).ok,
        isFalse,
      );
    },
  );

  test('registered proof is structurally pinned to the canonical call stack', () {
    final proofSource = File(
      'integration_test/support/android_foreground_webrtc_audio_proof.dart',
    ).readAsStringSync();
    final canonicalStackSource = File(
      'integration_test/support/android_foreground_webrtc_audio_canonical_stack.dart',
    ).readAsStringSync();
    final source = '$proofSource\n$canonicalStackSource';
    final diagnosticStart = canonicalStackSource.indexOf(
      'final class _ProofDiagnosticCallEngine',
    );
    final diagnosticEnd = canonicalStackSource.indexOf(
      'final class _AlwaysFailingProofCallMailbox',
      diagnosticStart,
    );
    expect(diagnosticStart, greaterThanOrEqualTo(0));
    expect(diagnosticEnd, greaterThan(diagnosticStart));
    final canonicalWithoutDiagnosticDelegate =
        canonicalStackSource.substring(0, diagnosticStart) +
        canonicalStackSource.substring(diagnosticEnd);
    final canonicalExecutionSource =
        '$proofSource\n$canonicalWithoutDiagnosticDelegate';

    for (final required in const <String>[
      'CallCoordinator(',
      'CallControlEffectExecutor(',
      'CallNegotiationEffectExecutor(',
      'CompositeCallEffectExecutor(',
      'CallSignalingContextStore(',
      'CallNegotiationMaterialStore(',
      'SecureCallEnvelopeCodec(',
      'HandleIncomingCallSignal(',
      'CallScopedMediaBundleOwner(',
      'CallSignalingService(',
      'ProductionCallControlSignalingAdapter(',
      'ProductionCallNegotiationSignalingAdapter(',
    ]) {
      expect(source, contains(required), reason: required);
    }
    for (final forbidden in const <String>[
      'locallyAccepted = true',
      '.createOffer(',
      '.createAnswer(',
      '.setLocalDescription(',
      '.setRemoteDescription(',
      '.addIceCandidates(',
      'publishDescription(',
      'publishCandidate(',
      "_publish('description'",
      "_publish('candidate'",
    ]) {
      expect(
        canonicalExecutionSource,
        isNot(contains(forbidden)),
        reason: forbidden,
      );
    }
  });

  test('campaign starts both endpoints inside one no-answer budget', () {
    final campaignSource = File(
      'integration_test/scripts/android_foreground_webrtc_audio_campaign.dart',
    ).readAsStringSync();

    expect(campaignSource, contains('await Future.wait<void>(<Future<void>>['));
    expect(campaignSource, contains('_launch(physicalDevice),'));
    expect(campaignSource, contains('_launch(emulatorDevice),'));
    expect(
      campaignSource,
      isNot(
        contains(
          'await _launch(physicalDevice);\n'
          '      await _launch(emulatorDevice);',
        ),
      ),
    );
  });

  test('canonical end acknowledgement permits the caller terminal state', () {
    final source = File(
      'integration_test/support/android_foreground_webrtc_audio_proof.dart',
    ).readAsStringSync();

    expect(
      RegExp(
        r"name:\s*'canonical-ended-observed',[\s\S]{0,180}"
        r'terminalIsExpected:\s*true,',
      ).hasMatch(source),
      isTrue,
    );
    expect(
      source,
      contains('if (!terminalIsExpected && last?.isTerminal == true)'),
    );
  });

  test('direct custody uses bounded per-command and archive deadlines', () {
    final campaignSource = File(
      'integration_test/scripts/android_foreground_webrtc_audio_campaign.dart',
    ).readAsStringSync();
    final directStart = campaignSource.indexOf(
      'Future<SimsArtifactEvidence> _runWithTargetPairLease()',
    );
    final relayStart = campaignSource.indexOf(
      'Future<_AndroidForegroundWebRtcAudioTransportCase> _runTransportCase',
    );
    expect(directStart, greaterThanOrEqualTo(0));
    expect(relayStart, greaterThan(directStart));
    final directSource = campaignSource.substring(directStart, relayStart);

    expect(
      directSource,
      contains(
        'runner: const SystemAndroidHostProcessRunner(\n'
        '          commandTimeout: Duration(minutes: 10),\n'
        '          terminationGrace: Duration(seconds: 5),\n'
        '        ),',
      ),
    );
    expect(
      directSource,
      contains('privateArchiveTimeout: const Duration(minutes: 10),'),
    );
    expect(
      RegExp(r'AndroidAppStateGuard\.capture\(').allMatches(directSource),
      hasLength(1),
    );
  });

  test('campaign runs fresh UDP then TCP relay cases before artifact write', () {
    final source = File(
      'integration_test/scripts/android_foreground_webrtc_audio_campaign.dart',
    ).readAsStringSync();
    final udp = source.indexOf(
      'mode: AndroidForegroundWebRtcAudioRelayMode.turnUdp',
    );
    final tcp = source.indexOf(
      'mode: AndroidForegroundWebRtcAudioRelayMode.turnTcp',
    );
    final debugOnlyGate = source.indexOf('if (debugEmulatorPair)');
    final artifactWrite = source.indexOf('writeSimsArtifactEvidenceSync(');

    expect(udp, greaterThan(0));
    expect(tcp, greaterThan(udp));
    expect(debugOnlyGate, greaterThan(tcp));
    expect(debugOnlyGate, lessThan(artifactWrite));
    expect(artifactWrite, greaterThan(tcp));
    expect(
      source,
      contains('Future<_AndroidForegroundWebRtcAudioTransportCase>'),
    );
    expect(source, contains('final credentials = turnFixture.mint(mode);'));
    expect(source, contains("'turn:\$tcpAuthority?transport=udp'"));
    expect(source, contains("'turn:\$tcpAuthority?transport=tcp'"));
    expect(source, contains('SIMS_FOREGROUND_WEBRTC_TURN_TCP_AUTHORITY'));
    expect(source, contains('Hmac('));
    expect(source, contains('utf8.encode(sharedSecret)'));
    expect(source, contains('androidForegroundWebRtcAudioProofsFromArtifact('));
    expect(
      source,
      contains('_AndroidForegroundWebRtcAudioTargetPairLease.acquire('),
    );
    expect(source, contains('return await _runWithTargetPairLease();'));
    expect(source, contains('await lease.release();'));
    expect(source, contains("sortedDevices.join('\\u0000')"));
    expect(source, contains('await handle.lock(FileLock.exclusive);'));
    expect(source, contains('FileMode.writeOnlyAppend'));
    expect(source, isNot(contains('leaseFile.write')));
  });

  test('campaign blocks when explicit coturn fixture is absent', () async {
    final directory = Directory.systemTemp.createTempSync(
      'foreground-webrtc-audio-turn-block-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final artifact = File('${directory.path}/app.apk')
      ..writeAsBytesSync(const <int>[1, 2, 3]);

    final result = await runAndroidForegroundWebRtcAudioCampaign(
      devices: const <String>['physical-target', 'emulator-target'],
      artifactPath: artifact.path,
      environment: const <String, String>{},
    );

    expect(result.processExitCode, 78);
    expect(result.json['status'], 'BLOCKED');
    expect(result.json['blocker'], 'environment');

    final nonRoutable = await runAndroidForegroundWebRtcAudioCampaign(
      devices: const <String>['physical-target', 'emulator-target'],
      artifactPath: artifact.path,
      environment: const <String, String>{
        'SIMS_FOREGROUND_WEBRTC_TURN_AUTHORITY': '0.0.0.0:3478',
        'SIMS_FOREGROUND_WEBRTC_TURN_TCP_AUTHORITY': '0.0.0.0:3479',
        'SIMS_FOREGROUND_WEBRTC_TURN_SHARED_SECRET': 'bounded-test-secret',
      },
    );
    expect(nonRoutable.processExitCode, 78);
    expect(nonRoutable.json['blocker'], 'environment');
  });

  test(
    'restoration failure serializes to a supported structured-result blocker',
    () {
      final restoration = AndroidForegroundWebRtcAudioCampaignResult.fail(
        blocker: 'restoration',
        detail: 'state restore failed',
        artifactPresent: false,
      );

      final parsed = SimsVerdict.fromJson(<String, Object?>{
        'capabilityId': simsAndroidForegroundWebRtcAudioScenarioId,
        ...restoration.json,
      });
      expect(parsed.blocker, SimsBlockerKind.restoration);

      final unknown = AndroidForegroundWebRtcAudioCampaignResult.fail(
        blocker: 'futureFailurePhase',
        detail: 'unknown failure phase',
        artifactPresent: false,
      );
      expect(
        () => SimsVerdict.fromJson(<String, Object?>{
          'capabilityId': simsAndroidForegroundWebRtcAudioScenarioId,
          ...unknown.json,
        }),
        throwsArgumentError,
      );
    },
  );

  test('rendezvous admits only fixed controls or opaque secure envelopes', () {
    final envelope = jsonEncode(<String, Object?>{
      'type': 'call_signal',
      'version': '1',
      'message_id': '11111111-1111-4111-8111-111111111111',
      'call_handle': '22222222-2222-4222-8222-222222222222',
      'expires_at_ms': 1,
      'kem': 'a2Vt',
      'ciphertext': 'Y2lwaGVydGV4dA==',
      'nonce': 'bm9uY2U=',
      'signature': 'c2lnbmF0dXJl',
    });
    expect(
      validateAndroidForegroundWebRtcAudioRendezvousEvent(
        kind: 'envelope',
        payload: <String, Object?>{'envelope': envelope},
      ),
      isTrue,
    );
    expect(
      validateAndroidForegroundWebRtcAudioRendezvousEvent(
        kind: 'control',
        payload: const <String, Object?>{'name': 'callee-ringing-ready'},
      ),
      isTrue,
    );
    expect(
      validateAndroidForegroundWebRtcAudioRendezvousEvent(
        kind: 'control',
        payload: const <String, Object?>{'name': 'canonical-endpoint-ready'},
      ),
      isTrue,
    );
    expect(
      validateAndroidForegroundWebRtcAudioRendezvousEvent(
        kind: 'description',
        payload: const <String, Object?>{'sdp': 'raw'},
      ),
      isFalse,
    );
    expect(
      validateAndroidForegroundWebRtcAudioRendezvousEvent(
        kind: 'candidate',
        payload: const <String, Object?>{'candidate': 'raw'},
      ),
      isFalse,
    );
    expect(
      validateAndroidForegroundWebRtcAudioRendezvousEvent(
        kind: 'control',
        payload: const <String, Object?>{'name': 'synthetic-pass'},
      ),
      isFalse,
    );
    final outerWithPlaintext = jsonDecode(envelope) as Map<String, Object?>
      ..['sdp'] = 'raw';
    expect(
      validateAndroidForegroundWebRtcAudioRendezvousEvent(
        kind: 'envelope',
        payload: <String, Object?>{'envelope': jsonEncode(outerWithPlaintext)},
      ),
      isFalse,
    );
  });

  test('both canonical endpoints rendezvous before the caller places', () {
    final source = File(
      'integration_test/support/android_foreground_webrtc_audio_proof.dart',
    ).readAsStringSync();
    final publishReady = source.indexOf(
      "await client.publishControl('canonical-endpoint-ready');",
    );
    final waitReady = source.indexOf("name: 'canonical-endpoint-ready',");
    final place = source.indexOf('await stack.place();');

    expect(publishReady, greaterThanOrEqualTo(0));
    expect(waitReady, greaterThan(publishReady));
    expect(place, greaterThan(waitReady));
  });

  test('SIMS registration has the exact canonical assertion contract', () {
    final registry =
        jsonDecode(File('tool/sims/critical_features.json').readAsStringSync())
            as Map<String, dynamic>;
    final capabilities = registry['capabilities']! as List<dynamic>;
    final capability = capabilities.cast<Map<String, dynamic>>().singleWhere(
      (entry) => entry['id'] == simsAndroidForegroundWebRtcAudioScenarioId,
    );
    final assertions = (capability['assertions']! as List<dynamic>)
        .cast<String>();

    expect(androidForegroundWebRtcAudioAssertionCount, 18);
    expect(assertions, _expectedAssertions);
    expect(assertions, hasLength(androidForegroundWebRtcAudioAssertionCount));
    expect(
      capability['artifactValidator'],
      androidForegroundWebRtcAudioArtifactValidatorId,
    );
  });

  test('campaign contract is pinned in both curated 1to1 arrays', () {
    const path =
        'test/integration/android_foreground_webrtc_audio_campaign_test.dart';
    for (final gate in const <String>[
      'scripts/run_host_test_gates.sh',
      'scripts/run_test_gates.sh',
    ]) {
      expect(File(gate).readAsStringSync(), contains('"$path"'), reason: gate);
    }
  });

  test('accepts exact v2 caller and callee runtime and endpoint bindings', () {
    for (final role in const <String>[
      simsForegroundWebRtcCallerRole,
      simsForegroundWebRtcCalleeRole,
    ]) {
      expect(
        validateAndroidForegroundWebRtcAudioInvocation(_invocation(role)).ok,
        isTrue,
      );
      expect(
        validateAndroidForegroundWebRtcAudioEndpoint(
          _endpoint(role),
          invocation: _invocation(role),
        ).ok,
        isTrue,
      );
    }

    final wrongKind = _invocation(simsForegroundWebRtcCallerRole).copyWith(
      values: <String, Object?>{
        ..._invocation(simsForegroundWebRtcCallerRole).values,
        'targetKind': 'emulator',
      },
    );
    expect(
      validateAndroidForegroundWebRtcAudioInvocation(wrongKind).ok,
      isFalse,
    );
  });

  test('relay runtime is exact, private, and mode-bound', () {
    for (final mode in AndroidForegroundWebRtcAudioRelayMode.values) {
      for (final role in const <String>[
        simsForegroundWebRtcCallerRole,
        simsForegroundWebRtcCalleeRole,
      ]) {
        final invocation = _relayInvocation(role, mode);
        expect(
          validateAndroidForegroundWebRtcAudioRelayInvocation(invocation).ok,
          isTrue,
        );
        expect(
          validateAndroidForegroundWebRtcAudioInvocation(invocation).ok,
          isFalse,
        );

        final wrongTransport = invocation.copyWith(
          values: <String, Object?>{
            ...invocation.values,
            'turnUrls': mode == AndroidForegroundWebRtcAudioRelayMode.turnUdp
                ? <String>['turn:192.0.2.10:3478?transport=tcp']
                : <String>['turn:192.0.2.10:3479?transport=tcp'],
          },
        );
        expect(
          validateAndroidForegroundWebRtcAudioRelayInvocation(
            wrongTransport,
          ).ok,
          isFalse,
        );

        if (mode == AndroidForegroundWebRtcAudioRelayMode.turnTcp) {
          for (final invalidUrls in <List<String>>[
            <String>['turn:192.0.2.10:3479?transport=udp'],
            <String>[
              'turn:192.0.2.10:3479?transport=udp',
              'turn:192.0.2.10:3479?transport=udp',
            ],
            <String>[
              'turn:192.0.2.10:3479?transport=udp',
              'turn:192.0.2.11:3479?transport=tcp',
            ],
          ]) {
            final invalid = invocation.copyWith(
              values: <String, Object?>{
                ...invocation.values,
                'turnUrls': invalidUrls,
              },
            );
            expect(
              validateAndroidForegroundWebRtcAudioRelayInvocation(invalid).ok,
              isFalse,
              reason: '$invalidUrls',
            );
          }
        }
      }
    }
  });

  test('relay endpoints prove exact transport and zero non-relay egress', () {
    for (final mode in AndroidForegroundWebRtcAudioRelayMode.values) {
      for (final role in const <String>[
        simsForegroundWebRtcCallerRole,
        simsForegroundWebRtcCalleeRole,
      ]) {
        final invocation = _relayInvocation(role, mode);
        final endpoint = _relayEndpoint(role, mode);
        expect(
          validateAndroidForegroundWebRtcAudioRelayEndpoint(
            endpoint,
            invocation: invocation,
          ).ok,
          isTrue,
        );

        final leaked = Map<String, Object?>.from(endpoint);
        leaked['relayPrivacy'] = <String, Object?>{
          ...(endpoint['relayPrivacy']! as Map<String, Object?>),
          'trickleNonRelayCountZero': false,
        };
        expect(
          validateAndroidForegroundWebRtcAudioRelayEndpoint(
            leaked,
            invocation: invocation,
          ).ok,
          isFalse,
        );

        final wrongSelection = Map<String, Object?>.from(endpoint)
          ..['selectedTransport'] =
              mode == AndroidForegroundWebRtcAudioRelayMode.turnUdp
              ? 'turnTcpTls'
              : 'turnUdp';
        expect(
          validateAndroidForegroundWebRtcAudioRelayEndpoint(
            wrongSelection,
            invocation: invocation,
          ).ok,
          isFalse,
        );

        final wrongProtocol = Map<String, Object?>.from(endpoint)
          ..['selectedRelayProtocol'] =
              mode == AndroidForegroundWebRtcAudioRelayMode.turnUdp
              ? 'tcp'
              : 'tls';
        expect(
          validateAndroidForegroundWebRtcAudioRelayEndpoint(
            wrongProtocol,
            invocation: invocation,
          ).ok,
          isFalse,
        );

        if (mode == AndroidForegroundWebRtcAudioRelayMode.turnTcp) {
          final udpAvailable = Map<String, Object?>.from(endpoint)
            ..['tcpFallbackPrecondition'] = <String, Object?>{
              'applied': true,
              'udpProbeAttempts': 3,
              'udpStunResponseAbsent': false,
              'tcpReachable': true,
            };
          expect(
            validateAndroidForegroundWebRtcAudioRelayEndpoint(
              udpAvailable,
              invocation: invocation,
            ).ok,
            isFalse,
          );
        }
      }
    }
  });

  test('relay failure marker remains bounded and invocation-bound', () {
    final invocation = _relayInvocation(
      simsForegroundWebRtcCallerRole,
      AndroidForegroundWebRtcAudioRelayMode.turnTcp,
    );
    final failed = androidForegroundWebRtcAudioFailedEndpoint(
      invocation: invocation,
      stage: AndroidForegroundWebRtcAudioFailureStage.mediaReadiness,
      state: 'ended',
      endReason: 'mediaFailed',
      effect: 'cleanup',
      followUp: 'negotiationFailed',
    );

    expect(
      validateAndroidForegroundWebRtcAudioFailedEndpoint(
        failed,
        invocation: invocation,
      ).ok,
      isTrue,
    );
    expect(jsonEncode(failed).length, lessThan(1024));
  });

  test('relay aggregate computes bounded campaign p95 without overclaim', () {
    final relay = _relayAggregate();
    expect(validateAndroidForegroundWebRtcAudioRelayEvidence(relay).ok, isTrue);
    expect(relay['latencyMeasurement'], <String, Object?>{
      'metric': 'acceptToBidirectionalRtpReady',
      'sampleCount': 4,
      'percentile': 95,
      'method': 'nearestRank',
      'p95Ms': 1150,
      'thresholdMs': 3000,
      'withinTarget': true,
      'confidence': 'campaignSampleLimited',
    });
    expect(relay['claimsBoundary'], <String, Object?>{
      'hostMintedAuthenticatedTurn': true,
      'nativeGoIssuanceProven': false,
      'turnEndpointUdpUnavailableProven': true,
      'selectedTcpRelayProven': true,
      'osUdpBlockingProven': false,
      'tlsProven': false,
    });
    final modes = relay['modes']! as Map<String, Object?>;
    for (final mode in AndroidForegroundWebRtcAudioRelayMode.values) {
      final caseEvidence = modes[mode.name]! as Map<String, Object?>;
      expect(
        (caseEvidence['cleanup']! as Map<String, Object?>)['appStateRestored'],
        isTrue,
      );
    }

    final forbidden = _relayAggregate();
    final forbiddenModes = forbidden['modes']! as Map<String, Object?>;
    final udp = forbiddenModes['turnUdp']! as Map<String, Object?>;
    (udp['relayPrivacy']! as Map<String, Object?>)['authority'] =
        '192.0.2.10:3478';
    expect(
      validateAndroidForegroundWebRtcAudioRelayEvidence(forbidden).ok,
      isFalse,
    );

    final slowTcpCaller = _relayEndpoint(
      simsForegroundWebRtcCallerRole,
      AndroidForegroundWebRtcAudioRelayMode.turnTcp,
    )..['acceptToAudioMs'] = 3001;
    final slowLeg = AndroidForegroundWebRtcAudioRelayLegEvidence(
      mode: AndroidForegroundWebRtcAudioRelayMode.turnTcp,
      callerEndpoint: slowTcpCaller,
      calleeEndpoint: _relayEndpoint(
        simsForegroundWebRtcCalleeRole,
        AndroidForegroundWebRtcAudioRelayMode.turnTcp,
      ),
      callerInvocation: _relayInvocation(
        simsForegroundWebRtcCallerRole,
        AndroidForegroundWebRtcAudioRelayMode.turnTcp,
      ),
      calleeInvocation: _relayInvocation(
        simsForegroundWebRtcCalleeRole,
        AndroidForegroundWebRtcAudioRelayMode.turnTcp,
      ),
      wireSummary: _wireSummary(),
      processesStopped: true,
      runtimeFilesRemoved: true,
      reverseMappingsRemoved: true,
      rendezvousClosed: true,
      appStateRestored: true,
    );
    expect(
      () => aggregateAndroidForegroundWebRtcAudioRelayEvidence(
        legs: <AndroidForegroundWebRtcAudioRelayLegEvidence>[
          _relayLeg(AndroidForegroundWebRtcAudioRelayMode.turnUdp),
          slowLeg,
        ],
        sharedApkSha256: _apkDigest,
      ),
      throwsA(
        isA<AndroidForegroundWebRtcAudioLatencyExceeded>().having(
          (error) => error.p95Ms,
          'p95Ms',
          3001,
        ),
      ),
    );
  });

  test('reducer path and outbound signal counts fail closed', () {
    final wrongReducer = _endpoint(simsForegroundWebRtcCallerRole);
    (wrongReducer['signalingTrace']!
            as Map<String, Object?>)['reducerPathSha256'] =
        '0' * 64;
    expect(
      validateAndroidForegroundWebRtcAudioEndpoint(
        wrongReducer,
        invocation: _invocation(simsForegroundWebRtcCallerRole),
      ).ok,
      isFalse,
    );

    final wrongCount = _endpoint(simsForegroundWebRtcCallerRole);
    (wrongCount['signalingTrace']!
            as Map<String, Object?>)['outboundEnvelopeCount'] =
        99;
    expect(
      validateAndroidForegroundWebRtcAudioEndpoint(
        wrongCount,
        invocation: _invocation(simsForegroundWebRtcCallerRole),
      ).ok,
      isFalse,
    );
  });

  test('aggregate rejects call binding mismatch', () {
    final callee = _endpoint(simsForegroundWebRtcCalleeRole)
      ..['callBindingSha256'] = '0' * 64;
    expect(() => _aggregate(callee: callee), throwsFormatException);
  });

  test('aggregate rejects wire chain and count mismatches', () {
    final wrongChain = _wireSummary();
    (wrongChain['callerToCallee']! as Map<String, Object?>)['chainSha256'] =
        '0' * 64;
    expect(() => _aggregate(wireSummary: wrongChain), throwsFormatException);

    final wrongCount = _wireSummary();
    final direction = wrongCount['calleeToCaller']! as Map<String, Object?>;
    direction['count'] = (direction['count']! as int) + 1;
    expect(() => _aggregate(wireSummary: wrongCount), throwsFormatException);
  });

  test('durable evidence contains only the v2 privacy allowlist', () {
    final evidence = _aggregate();
    expect(validateAndroidForegroundWebRtcAudioEvidence(evidence).ok, isTrue);
    final encoded = jsonEncode(evidence);
    expect(encoded.length, lessThan(4096));
    for (final forbidden in <String>[
      _bearer,
      '127.0.0.1',
      '43123',
      'physical-target',
      'emulator-target',
      'sdp',
      'candidate',
      'address',
      'identity',
      'bytesSent',
      'packetsReceived',
      'audioSamples',
    ]) {
      expect(encoded, isNot(contains(forbidden)), reason: forbidden);
    }
    expect(evidence['callBindingSha256'], _callBinding);
    expect((evidence['canonicalJourney']! as Map).values, everyElement(isTrue));
    expect(
      (evidence['connectedReadiness']! as Map).values,
      everyElement(isTrue),
    );
    expect(evidence['envelopeBindings'], _wireSummary());
    expect((evidence['directionalRtpDelta']! as Map)['callerToCallee'], isTrue);
    expect((evidence['directionalRtpDelta']! as Map)['calleeToCaller'], isTrue);
  });

  test('redaction and field bounds reject unknown or oversized material', () {
    final rawField = _aggregate()
      ..['rawEnvelope'] = <String, Object?>{'payload': 'private'};
    expect(validateAndroidForegroundWebRtcAudioEvidence(rawField).ok, isFalse);

    final oversizedBearer = _invocation(simsForegroundWebRtcCallerRole)
        .copyWith(
          values: <String, Object?>{
            ..._invocation(simsForegroundWebRtcCallerRole).values,
            'bearer': 'x' * 129,
          },
        );
    expect(
      validateAndroidForegroundWebRtcAudioInvocation(oversizedBearer).ok,
      isFalse,
    );

    final endpointWithCounter = _endpoint(simsForegroundWebRtcCallerRole)
      ..['rtpCounters'] = <String, Object?>{'raw': 1};
    expect(
      validateAndroidForegroundWebRtcAudioEndpoint(
        endpointWithCounter,
        invocation: _invocation(simsForegroundWebRtcCallerRole),
      ).ok,
      isFalse,
    );
  });

  test('directional proof and every cleanup boundary fail closed', () {
    final callee = _endpoint(simsForegroundWebRtcCalleeRole);
    (callee['directionalRtpDelta']!
            as Map<String, Object?>)['callerToCalleeInbound'] =
        false;
    expect(() => _aggregate(callee: callee), throwsFormatException);

    final caller = _endpoint(simsForegroundWebRtcCallerRole);
    (caller['cleanup']! as Map<String, Object?>)['bundleClosedExactlyOnce'] =
        false;
    expect(
      validateAndroidForegroundWebRtcAudioEndpoint(
        caller,
        invocation: _invocation(simsForegroundWebRtcCallerRole),
      ).ok,
      isFalse,
    );
    expect(() => _aggregate(caller: caller), throwsFormatException);

    expect(() => _aggregate(processesStopped: false), throwsFormatException);
    expect(() => _aggregate(rendezvousClosed: false), throwsFormatException);
    expect(() => _aggregate(runtimeFilesRemoved: false), throwsFormatException);
  });

  test('endpoint and aggregate require a proven direct selected pair', () {
    final caller = _endpoint(simsForegroundWebRtcCallerRole);
    expect(
      validateAndroidForegroundWebRtcAudioEndpoint(
        caller,
        invocation: _invocation(simsForegroundWebRtcCallerRole),
      ).ok,
      isTrue,
    );

    caller['directSelected'] = false;
    expect(
      validateAndroidForegroundWebRtcAudioEndpoint(
        caller,
        invocation: _invocation(simsForegroundWebRtcCallerRole),
      ).ok,
      isFalse,
    );
    expect(() => _aggregate(caller: caller), throwsFormatException);
  });

  test('every connected-readiness component fails closed', () {
    for (final key in _connectedReadiness().keys) {
      final caller = _endpoint(simsForegroundWebRtcCallerRole);
      (caller['connectedReadiness']! as Map<String, Object?>)[key] = false;
      expect(
        validateAndroidForegroundWebRtcAudioEndpoint(
          caller,
          invocation: _invocation(simsForegroundWebRtcCallerRole),
        ).ok,
        isFalse,
        reason: key,
      );
      expect(
        () => _aggregate(caller: caller),
        throwsFormatException,
        reason: key,
      );
    }
  });

  test(
    'protocol cleanup stays pinned and attempts every residue boundary',
    () async {
      final runner = _RecordingProcessRunner(failFirstStop: true);
      var rendezvousClosed = false;
      final result =
          await AndroidForegroundWebRtcAudioProtocolCleaner(
            processRunner: runner,
          ).cleanup(
            devices: const <String>['physical-target', 'emulator-target'],
            packageName: 'com.example.sims',
            reversePort: 43123,
            reverseMappedDevices: const <String>{
              'physical-target',
              'emulator-target',
            },
            closeRendezvous: () async => rendezvousClosed = true,
          );

      expect(result.processesStopped, isFalse);
      expect(result.runtimeFilesRemoved, isTrue);
      expect(result.reverseMappingsRemoved, isTrue);
      expect(result.rendezvousClosed, isTrue);
      expect(rendezvousClosed, isTrue);
      expect(runner.calls, hasLength(6));
      expect(
        runner.calls.every(
          (call) =>
              call.executable == 'adb' &&
              call.arguments.length >= 2 &&
              call.arguments.first == '-s' &&
              (call.arguments[1] == 'physical-target' ||
                  call.arguments[1] == 'emulator-target'),
        ),
        isTrue,
      );
      expect(
        runner.calls.where(
          (call) => call.arguments.contains(simsRuntimeResultRelativePath),
        ),
        hasLength(2),
      );
      expect(
        runner.calls.where(
          (call) =>
              call.arguments.contains('--remove') &&
              call.arguments.contains('tcp:43123'),
        ),
        hasLength(2),
      );
    },
  );
}

final class _RecordedCall {
  const _RecordedCall(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;
}

final class _RecordingProcessRunner implements AndroidHostProcessRunner {
  _RecordingProcessRunner({required this.failFirstStop});

  final bool failFirstStop;
  final List<_RecordedCall> calls = <_RecordedCall>[];
  var _failedStop = false;

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    calls.add(_RecordedCall(executable, List<String>.from(arguments)));
    final isStop = arguments.contains('force-stop');
    final shouldFail = failFirstStop && isStop && !_failedStop;
    if (shouldFail) _failedStop = true;
    return ProcessResult(1, shouldFail ? 1 : 0, '', '');
  }
}
