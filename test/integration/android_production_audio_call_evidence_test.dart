import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/android_production_audio_call_evidence.dart';

const _apkSha =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _profileSha =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _fixtureSha =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
const _turnAuthoritySha =
    '2222222222222222222222222222222222222222222222222222222222222222';
const _coturnInstanceSha =
    '4444444444444444444444444444444444444444444444444444444444444444';
const _knownFixtureSha =
    '3333333333333333333333333333333333333333333333333333333333333333';
const _coturnDigest =
    'sha256:aa68aab64a3b929d57fc2924c98ea447bf996cf8dade2508e7b71eaf23f1f14e';
const _callerBinding =
    'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
const _calleeBinding =
    'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';
const _callerIdentity =
    'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';
const _calleeIdentity =
    '1111111111111111111111111111111111111111111111111111111111111111';

AndroidProductionAudioCallPionOracleEvidence _oracle({
  bool aToBPayloadHashExact = true,
  bool cleanupComplete = true,
  bool includePrivateField = false,
  String turnAuthoritySha256 = _turnAuthoritySha,
  String fixtureInstanceSha256 = _coturnInstanceSha,
}) => AndroidProductionAudioCallPionOracleEvidence.fromResult(<String, Object?>{
  'schema': 'mknoon.call_audio_oracle.result.v1',
  'version': 1,
  'passed': true,
  'pion_version': 'v4.2.19',
  'fixture_sha256': _knownFixtureSha,
  'turn_authority_sha256': turnAuthoritySha256,
  'fixture_instance_sha256': fixtureInstanceSha256,
  'coturn': <String, Object?>{
    'image': 'coturn/coturn:4.17.2-r0',
    'digest': _coturnDigest,
  },
  'expected_transport': 'udp',
  'a_to_b': <String, Object?>{
    'codec_valid': true,
    'payload_count_exact': true,
    'payload_order_exact': true,
    'payload_hash_exact': aToBPayloadHashExact,
  },
  'b_to_a': <String, Object?>{
    'codec_valid': true,
    'payload_count_exact': true,
    'payload_order_exact': true,
    'payload_hash_exact': true,
  },
  'peer_a_route': <String, Object?>{
    'relay_selected': true,
    'transport_match': true,
  },
  'peer_b_route': <String, Object?>{
    'relay_selected': true,
    'transport_match': true,
  },
  'cleanup_complete': cleanupComplete,
  if (includePrivateField) 'password': 'must-not-escape',
});

Map<String, Object?> _receipt({required String role}) => <String, Object?>{
  'schema': androidProductionAudioCallObservationResultSchema,
  'scenario': androidProductionAudioCallScenarioId,
  'buildProfile': androidProductionAudioCallProfileId,
  'role': role,
  'operation': androidProductionAudioCallStopOperation,
  'stepId': 'production-call-$role-stop-run-399',
  'runId': 'run-399',
  'nonce': role == androidProductionAudioCallCallerRole
      ? 'caller-nonce-399'
      : 'callee-nonce-399',
  'profileSha256': _profileSha,
  'apkSha256': _apkSha,
  'callBindingSha256': role == androidProductionAudioCallCallerRole
      ? _callerBinding
      : _calleeBinding,
  'status': 'complete',
  'success': true,
  'stateSequence': role == androidProductionAudioCallCallerRole
      ? <String>['outgoing', 'ringing', 'accepted', 'connected', 'terminal']
      : <String>['ringing', 'accepted', 'connected', 'terminal'],
  'outgoingObserved': role == androidProductionAudioCallCallerRole,
  'ringingObserved': true,
  'acceptedObserved': true,
  'connectedObserved': true,
  'terminalObserved': true,
  'activeCallSurfaceObserved': true,
  'structuralMediaReadyObserved': true,
  'relayOnlyObserved': true,
  'selectedRelayTransport': 'turn_udp',
  'localAudioEnabledObserved': true,
  'inboundAudioRtpObserved': true,
  'outboundAudioRtpObserved': true,
  'wakeAuthorityReady': false,
  'containsPrivateMaterial': false,
};

Map<String, Object?> _aggregate({
  Map<String, Object?>? caller,
  Map<String, Object?>? callee,
  String callerIdentitySha256 = _callerIdentity,
  String calleeIdentitySha256 = _calleeIdentity,
  bool nativeCallsReleasedBothEndpoints = true,
  List<AndroidProductionAudioCallArtifactDigest>? artifacts,
}) => aggregateAndroidProductionAudioCallEvidence(
  callerReceipt: caller ?? _receipt(role: androidProductionAudioCallCallerRole),
  calleeReceipt: callee ?? _receipt(role: androidProductionAudioCallCalleeRole),
  runId: 'run-399',
  callerNonce: 'caller-nonce-399',
  calleeNonce: 'callee-nonce-399',
  profileSha256: _profileSha,
  apkSha256: _apkSha,
  relayFixtureIdentitySha256: _fixtureSha,
  turnAuthoritySha256: _turnAuthoritySha,
  coturnInstanceIdentitySha256: _coturnInstanceSha,
  pionOracle: _oracle(),
  callerIdentitySha256: callerIdentitySha256,
  calleeIdentitySha256: calleeIdentitySha256,
  physicalDeviceId: 'pixel-physical',
  emulatorDeviceId: 'emulator-5554',
  semanticControls: const AndroidProductionAudioCallSemanticControls(
    callStarted: true,
    nativeAnswered: true,
    muteExercised: true,
    speakerExercised: true,
    hangupExercised: true,
  ),
  terminalSurfacesDismissed: true,
  nativeCallsReleasedBothEndpoints: nativeCallsReleasedBothEndpoints,
  appStateRestored: true,
  artifacts: artifacts ?? _expectedArtifacts(),
);

List<AndroidProductionAudioCallArtifactDigest> _expectedArtifacts() =>
    <AndroidProductionAudioCallArtifactDigest>[
      for (final role in const <String>[
        androidProductionAudioCallCallerRole,
        androidProductionAudioCallCalleeRole,
      ])
        for (final stage in const <String>[
          'active',
          'terminal',
        ]) ...<AndroidProductionAudioCallArtifactDigest>[
          AndroidProductionAudioCallArtifactDigest(
            role: role,
            kind: '${stage}UiDump',
            sha256Digest: _callerBinding,
            bounded: true,
            redacted: true,
          ),
          AndroidProductionAudioCallArtifactDigest(
            role: role,
            kind: '${stage}Logcat',
            sha256Digest: _calleeBinding,
            bounded: true,
            redacted: true,
          ),
          AndroidProductionAudioCallArtifactDigest(
            role: role,
            kind: '${stage}Screenshot',
            sha256Digest: _apkSha,
            bounded: true,
            redacted: false,
          ),
        ],
    ];

void main() {
  test('accepts only nonce-bound bidirectional production RTP receipts', () {
    final proof = _aggregate();

    expect(validateAndroidProductionAudioCallEvidence(proof).ok, isTrue);
    expect(proof.toString(), isNot(contains('pixel-physical')));
    expect(proof.toString(), isNot(contains('emulator-5554')));
    expect(proof.toString().toLowerCase(), isNot(contains('peerid')));
    expect(proof.toString().toLowerCase(), isNot(contains('callid')));
    expect(proof.toString(), isNot(contains('directionalRtpDelta')));
    final caller =
        (proof['endpoints']! as Map<String, Object?>)['caller']!
            as Map<String, Object?>;
    final callee =
        (proof['endpoints']! as Map<String, Object?>)['callee']!
            as Map<String, Object?>;
    for (final endpoint in <Map<String, Object?>>[caller, callee]) {
      expect(endpoint['inboundAudioRtpObserved'], isTrue);
      expect(endpoint['outboundAudioRtpObserved'], isTrue);
      expect(endpoint.keys, isNot(contains('packetsReceived')));
      expect(endpoint.keys, isNot(contains('packetsSent')));
    }
    final mediaProof = proof['mediaProof']! as Map<String, Object?>;
    expect(mediaProof['productionRtpClaimed'], isTrue);
    expect(mediaProof['directionalMediaOracle'], 'production-stats-and-pion');
    expect(mediaProof['pionVersion'], 'v4.2.19');
    expect(mediaProof['knownFixtureSha256'], _knownFixtureSha);
    expect(mediaProof['fixtureInstanceSha256'], _coturnInstanceSha);
    expect(mediaProof['coturnVersion'], '4.17.2-r0');
    expect(mediaProof['coturnImageSha256'], _coturnDigest.substring(7));
    expect(proof.toString(), isNot(contains('must-not-escape')));
  });

  test('rejects incomplete or non-allowlisted Pion oracle evidence', () {
    expect(
      () => _aggregateWithOracle(_oracle(aToBPayloadHashExact: false)),
      throwsFormatException,
    );
    expect(
      () => _aggregateWithOracle(_oracle(cleanupComplete: false)),
      throwsFormatException,
    );
    expect(() => _oracle(includePrivateField: true), throwsFormatException);
    expect(
      () => _aggregateWithOracle(
        _oracle(
          turnAuthoritySha256:
              '4444444444444444444444444444444444444444444444444444444444444444',
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => _aggregateWithOracle(
        _oracle(
          fixtureInstanceSha256:
              '5555555555555555555555555555555555555555555555555555555555555555',
        ),
      ),
      throwsFormatException,
      reason:
          'an all-true result from an older coturn instance at the same TURN '
          'URL must not be replayable',
    );
  });

  test('requires both production peers to match the UDP oracle transport', () {
    for (final transport in const <String>['relay', 'turn_tcp_tls']) {
      final caller = _receipt(role: androidProductionAudioCallCallerRole)
        ..['selectedRelayTransport'] = transport;
      expect(() => _aggregate(caller: caller), throwsFormatException);
    }
  });

  test('rejects a stale nonce or receipt with an unexpected field', () {
    final stale = _receipt(role: androidProductionAudioCallCallerRole)
      ..['nonce'] = 'stale';
    expect(() => _aggregate(caller: stale), throwsFormatException);

    final leaking = _receipt(role: androidProductionAudioCallCallerRole)
      ..['peerId'] = '12D3KooWprivate';
    expect(() => _aggregate(caller: leaking), throwsFormatException);
  });

  test('rejects skipped canonical states and false structural readiness', () {
    final skipped = _receipt(role: androidProductionAudioCallCallerRole)
      ..['stateSequence'] = <String>['outgoing', 'connected', 'terminal'];
    expect(() => _aggregate(caller: skipped), throwsFormatException);

    final unready = _receipt(role: androidProductionAudioCallCalleeRole)
      ..['structuralMediaReadyObserved'] = false;
    expect(() => _aggregate(callee: unready), throwsFormatException);
  });

  test('rejects either missing RTP direction on either production peer', () {
    for (final role in const <String>[
      androidProductionAudioCallCallerRole,
      androidProductionAudioCallCalleeRole,
    ]) {
      for (final field in const <String>[
        'inboundAudioRtpObserved',
        'outboundAudioRtpObserved',
      ]) {
        final receipt = _receipt(role: role)..[field] = false;
        expect(
          () => role == androidProductionAudioCallCallerRole
              ? _aggregate(caller: receipt)
              : _aggregate(callee: receipt),
          throwsFormatException,
          reason: '$role/$field must be observed before claiming RTP',
        );
      }
    }
  });

  test('rejects incomplete host/native cleanup', () {
    expect(
      () => _aggregate(nativeCallsReleasedBothEndpoints: false),
      throwsFormatException,
    );
  });

  test('rejects one user identity presented as both call endpoints', () {
    expect(
      () => _aggregate(calleeIdentitySha256: _callerIdentity),
      throwsFormatException,
    );

    final proof = _aggregate();
    final endpoints = proof['endpoints']! as Map<String, Object?>;
    final caller = endpoints['caller']! as Map<String, Object?>;
    final callee = endpoints['callee']! as Map<String, Object?>;
    callee['identitySha256'] = caller['identitySha256'];

    expect(validateAndroidProductionAudioCallEvidence(proof).ok, isFalse);
  });

  test(
    'rejects arbitrary, incomplete, duplicate, or mis-redacted artifacts',
    () {
      final rawSdp = _expectedArtifacts();
      rawSdp[0] = const AndroidProductionAudioCallArtifactDigest(
        role: androidProductionAudioCallCallerRole,
        kind: 'rawSdp',
        sha256Digest: _callerBinding,
        bounded: true,
        redacted: false,
      );
      expect(() => _aggregate(artifacts: rawSdp), throwsFormatException);

      final missing = _expectedArtifacts()..removeLast();
      expect(() => _aggregate(artifacts: missing), throwsFormatException);

      final duplicate = _expectedArtifacts();
      duplicate[1] = duplicate.first;
      expect(() => _aggregate(artifacts: duplicate), throwsFormatException);

      final wrongRole = _expectedArtifacts();
      wrongRole[0] = const AndroidProductionAudioCallArtifactDigest(
        role: androidProductionAudioCallCalleeRole,
        kind: 'activeUiDump',
        sha256Digest: _callerBinding,
        bounded: true,
        redacted: true,
      );
      expect(() => _aggregate(artifacts: wrongRole), throwsFormatException);

      final wrongRedaction = _expectedArtifacts();
      wrongRedaction[0] = const AndroidProductionAudioCallArtifactDigest(
        role: androidProductionAudioCallCallerRole,
        kind: 'activeUiDump',
        sha256Digest: _callerBinding,
        bounded: true,
        redacted: false,
      );
      expect(
        () => _aggregate(artifacts: wrongRedaction),
        throwsFormatException,
      );
    },
  );

  test('durable schema is recursively allowlist-only', () {
    final proof = _aggregate();
    final poisoned = <String, Object?>{
      ...proof,
      'relay': <String, Object?>{
        ...(proof['relay']! as Map<String, Object?>),
        'ip': '192.168.0.60',
      },
    };
    expect(validateAndroidProductionAudioCallEvidence(poisoned).ok, isFalse);

    final rawCounter = <String, Object?>{
      ...proof,
      'endpoints': <String, Object?>{
        ...(proof['endpoints']! as Map<String, Object?>),
        'packetsSent': 10,
      },
    };
    expect(validateAndroidProductionAudioCallEvidence(rawCounter).ok, isFalse);
  });
}

Map<String, Object?> _aggregateWithOracle(
  AndroidProductionAudioCallPionOracleEvidence oracle,
) => aggregateAndroidProductionAudioCallEvidence(
  callerReceipt: _receipt(role: androidProductionAudioCallCallerRole),
  calleeReceipt: _receipt(role: androidProductionAudioCallCalleeRole),
  runId: 'run-399',
  callerNonce: 'caller-nonce-399',
  calleeNonce: 'callee-nonce-399',
  profileSha256: _profileSha,
  apkSha256: _apkSha,
  relayFixtureIdentitySha256: _fixtureSha,
  turnAuthoritySha256: _turnAuthoritySha,
  coturnInstanceIdentitySha256: _coturnInstanceSha,
  pionOracle: oracle,
  callerIdentitySha256: _callerIdentity,
  calleeIdentitySha256: _calleeIdentity,
  physicalDeviceId: 'pixel-physical',
  emulatorDeviceId: 'emulator-5554',
  semanticControls: const AndroidProductionAudioCallSemanticControls(
    callStarted: true,
    nativeAnswered: true,
    muteExercised: true,
    speakerExercised: true,
    hangupExercised: true,
  ),
  terminalSurfacesDismissed: true,
  nativeCallsReleasedBothEndpoints: true,
  appStateRestored: true,
  artifacts: _expectedArtifacts(),
);
