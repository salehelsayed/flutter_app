import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/android_production_audio_call_evidence.dart';
import '../../integration_test/support/production_call_notification_evidence.dart';
import '../../tool/sims/artifact_evidence.dart';
import '../../tool/sims/production_call_back_criteria.dart';
import '../../tool/sims/production_call_regression_criteria.dart';

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
  bool emulatorPair = false,
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
  emulatorPair: emulatorPair,
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

Map<String, Object?> _callbackProof(String id) {
  final directory = Directory.systemTemp.createTempSync('callback-oracle-');
  addTearDown(() => directory.deleteSync(recursive: true));
  final baseline = writeSimsArtifactEvidenceSync(
    directory: directory,
    capabilityId: androidProductionAudioCallScenarioId,
    validatorIds: [androidProductionAudioCallArtifactValidatorId],
    payload: androidProductionAudioCallDurablePayload(_aggregate()),
  );
  final dual = id == 'kx0005' || id == 'kx0006';
  Map<String, Object?> submitted(String history) => {
    'stage': 'submitted',
    'historyCallSha256': history,
  };
  final submissions = [
    if (dual) submitted(_callerIdentity),
    submitted(_calleeIdentity),
  ];
  final events = <Map<String, Object?>>[
    ...submissions,
    {'stage': 'redialRequested', 'historyCallSha256': _calleeIdentity},
    {
      'stage': 'completed',
      'historyCallSha256': _calleeIdentity,
      'result': dual
          ? 'started'
          : id == 'kx0007'
          ? 'unavailable'
          : 'microphoneDenied',
    },
  ];
  Map<String, Object?> snapshot({
    bool active = false,
    bool held = false,
    bool unlocked = true,
    String call = _callerBinding,
    List<Map<String, Object?>>? observed,
  }) => {
    'sourceBound': true,
    'connectionReadSucceeded': true,
    'deviceUnlocked': unlocked,
    'inCall': active,
    'direction': active ? 'outgoing' : null,
    'callSha256': call,
    'contactSha256': _calleeBinding,
    'connectionPresent': active,
    'localAudioEnabled': active,
    'inboundAudioRtpObserved': active,
    'outboundAudioRtpObserved': active,
    'events': observed ?? <Map<String, Object?>>[],
    'readinessHeld': held,
  };
  final result = snapshot(
    active: id != 'kx0008',
    call: dual ? _fixtureSha : _callerBinding,
    observed: events,
  );
  final proof = <String, Object?>{
    'caseId': id,
    'attemptDirectory': directory.path,
    'baselineEvidence': baseline.toJson(),
    'emulatorPair': false,
    'invocations': [
      for (var i = 0; i < (id == 'kx0007' ? 1 : 2); i++)
        {
          'scenarioId': id,
          'role': 'alice',
          'profileId': 'android.e2e.production_call_local',
          'runId': 'synthetic-callback-run',
          'nonce': 'synthetic-invocation-$i',
        },
    ],
    'seed': {
      'posted': {'historyCallSha256': _callerIdentity},
      'b': {
        'historyCallSha256': _calleeIdentity,
        'contactSha256': _calleeBinding,
      },
    },
    'resultSnapshot': result,
    'verifiedOwnedProcessDeath': true,
    'unsecuredEmulatorKeyguard': true,
    'keyguardRestored': true,
    'phases': [
      {'label': 'ready', 'snapshot': snapshot()},
      {'label': 'baseline-active', 'snapshot': snapshot(active: true)},
      if (dual) ...[
        {
          'label': 'a-held',
          'snapshot': snapshot(
            held: true,
            observed: [submitted(_callerIdentity)],
          ),
        },
        {
          'label': 'b-held',
          'snapshot': snapshot(held: true, observed: submissions),
        },
        if (id == 'kx0006') ...[
          {
            'label': 'released-while-locked',
            'snapshot': snapshot(unlocked: false, observed: submissions),
          },
          {
            'label': 'still-locked',
            'snapshot': snapshot(unlocked: false, observed: submissions),
          },
        ],
      ],
      if (id == 'kx0007') {'label': 'after-busy', 'snapshot': result},
      if (id == 'kx0008')
        {'label': 'after-microphone-denial', 'snapshot': result},
    ],
  };
  if (id == 'kx0007') {
    final file = File('${directory.path}/message.xml')
      ..writeAsStringSync(
        '<hierarchy><node package="com.mknoon.sims.productionaudio" enabled="true" visible-to-user="true" '
        'content-desc="Voice calling is unavailable." bounds="[0,0][100,100]"/></hierarchy>',
      );
    proof['messageReceipt'] = {
      'path': file.path,
      'sha256': sha256.convert(file.readAsBytesSync()).toString(),
      'label': 'Voice calling is unavailable.',
      'packageName': 'com.mknoon.sims.productionaudio',
    };
  }
  if (id == 'kx0008') {
    proof['positiveCapture'] = {
      'captureReadSucceeded': true,
      'activeOwnedRecordClients': 1,
      'sourceDumpSha256': _profileSha,
    };
    proof['negativeCapture'] = {
      'captureReadSucceeded': true,
      'activeOwnedRecordClients': 0,
      'sourceDumpSha256': _apkSha,
    };
    final flow = File('${directory.path}/denial-flow.json')
      ..writeAsStringSync(
        jsonEncode({
          'status': 'PASS',
          'exit_status': 0,
          'flows': ['production_call_microphone_denial'],
        }),
      );
    proof['denialFlowReceipt'] = flow.path;
  }
  return proof;
}

Map<String, Object?> _surfaceProof(Directory directory, String id) {
  final baseline = writeSimsArtifactEvidenceSync(
    directory: directory,
    capabilityId: androidProductionAudioCallScenarioId,
    validatorIds: [androidProductionAudioCallArtifactValidatorId],
    payload: androidProductionAudioCallDurablePayload(_aggregate()),
  );
  final caller = {'kx0001', 'kx0002', 'kx0029', 'kx0030'}.contains(id);
  final actor = caller ? 'caller' : 'callee';
  final otherIdentity = caller ? _calleeIdentity : _callerIdentity;
  final nameHash = sha256
      .convert(utf8.encode(id == 'kx0017' ? 'MKnoon caller' : 'Fixture caller'))
      .toString();
  final inAppNameHash = sha256
      .convert(
        utf8.encode(id == 'kx0017' ? 'Unknown contact' : 'Fixture caller'),
      )
      .toString();
  final inAppPackageHash = sha256
      .convert(utf8.encode('com.example.call'))
      .toString();
  Map<String, Object?> current(bool subject) => {
    'sourceBound': true,
    'connectionReadSucceeded': true,
    'inCall': true,
    'callSha256': _callerBinding,
    'contactSha256': subject
        ? otherIdentity
        : (caller ? _callerIdentity : _calleeIdentity),
    'direction': caller == subject ? 'outgoing' : 'incoming',
    'state': 'connected',
    'connectionPresent': true,
    'localAudioEnabled': true,
  };
  final inAppRequired = id == 'kx0016' || id == 'kx0017';
  Map<String, Object?> observation(int id) => {
    'current': {...current(true), if (id == 504) 'state': 'ringing'},
    'otherCurrent': current(false),
    if (inAppRequired)
      'inAppIdentity': {
        'phase': id == 504 ? 'incoming' : 'connected',
        'packageSha256': inAppPackageHash,
        'sourceUiSha256': id == 504 ? _profileSha : _apkSha,
        'expectedNameSha256': inAppNameHash,
        'peerSha256s': [
          otherIdentity,
          caller ? _callerIdentity : _calleeIdentity,
        ],
        'nameNodeCount': 1,
        'ownedStatusNodeCount': 1,
        'statusMatches': true,
        'peerIdVisible': false,
        'before': {...current(true), if (id == 504) 'state': 'ringing'},
        'after': {...current(true), if (id == 504) 'state': 'ringing'},
      },
    'cards': [
      {
        'id': id,
        'titleSha256': nameHash,
        'peerIdVisible': false,
        'bodyKind': id == 504 ? 'incoming' : 'ongoing',
        'nativeKeySha256': _fixtureSha,
        'sourceDumpSha256': _apkSha,
        'quiet': true,
        'soundIsNull': true,
        'vibrationIsNull': true,
        'sdk': 37,
        'channelImportance': 2,
        'expectedOngoingChannel': true,
      },
    ],
  };
  String flow(String name) {
    final file = File('${directory.path}/$name.json')
      ..writeAsStringSync(
        jsonEncode({
          'status': 'PASS',
          'exit_status': 0,
          'flows': [name],
        }),
      );
    return file.path;
  }

  Map<String, Object?> output(String selected) => {
    'callSha256': _callerBinding,
    'audioActive': true,
    'selectedRoute': selected,
    'supportedRoutes': ['systemDefault', 'speaker'],
    'outputs': [
      for (var i = 0; i < 2; i++)
        {
          'index': i,
          'route': i == 0 ? 'systemDefault' : 'speaker',
          'selected': selected == (i == 0 ? 'systemDefault' : 'speaker'),
        },
    ],
  };
  return {
    'caseId': id,
    'actor': actor,
    'runId': 'surface-test-run',
    'attemptDirectory': directory.path,
    'baselineEvidence': baseline.toJson(),
    'emulatorPair': false,
    'otherPeerSha256': otherIdentity,
    'invocations': [
      for (final role in ['caller', 'callee'])
        {
          'scenarioId': id,
          'profileId': androidProductionAudioCallProfileId,
          'role': 'alice',
          'runId': 'surface-test-run',
          'nonce': 'surface-nonce-$role',
          'values': {'actor': role},
        },
    ],
    'expectedNameSha256': nameHash,
    if (inAppRequired) ...{
      'expectedInAppNameSha256': inAppNameHash,
      'inAppPackageSha256': inAppPackageHash,
    },
    'contactName': {
      'contactSha256': otherIdentity,
      'displayNameSha256': id == 'kx0017' ? otherIdentity : nameHash,
      'readableName': id != 'kx0017',
      'blocked': false,
    },
    if (id == 'kx0001') ...{
      'wireDeadlines': {
        'encodedInvites': [
          {
            'callSha256': _callerBinding,
            'wireSha256': _apkSha,
            'messageSha256': _profileSha,
            'signaturePresent': true,
            'createdAtMs': 1007000,
            'expiresAtMs': 1047000,
            'wireExpiresAtMs': 1047000,
          },
        ],
        'timers': [
          {
            'callSha256': _callerBinding,
            'kind': 'noAnswer',
            'scheduledAtMs': 1007000,
            'requestedDelayMs': 30000,
            'effectiveDelayMs': 30000,
            'deadlineMs': 1037000,
            'callStartedAtMs': 1000000,
          },
          {
            'callSha256': _callerBinding,
            'kind': 'inviteExpiry',
            'scheduledAtMs': 1007000,
            'requestedDelayMs': 45000,
            'effectiveDelayMs': 38000,
            'deadlineMs': 1045000,
            'callStartedAtMs': 1000000,
          },
        ],
      },
      'wireDeliveryGapMs': -2000,
      'wireOutlivesDeliveryDeadline': true,
    },
    if (id == 'kx0029') ...{
      'pickerInventory': {
        'provider': output('systemDefault'),
        'rows': output('systemDefault')['outputs'],
        'sourceUiSha256': _apkSha,
      },
      'speakerSelected': output('speaker'),
      'speakerReleased': output('systemDefault'),
      'expectedSpeakerRelease': 'systemDefault',
      'unavailableHardware': ['wiredHeadset', 'bluetooth'],
    },
    if (id == 'kx0030')
      'privacy': {
        'before': false,
        'afterToggle': true,
        'restored': false,
        'copyReceipt': flow('production_call_privacy_open'),
        'toggleReceipt': flow('production_call_privacy_toggle'),
        'restoreReceipt': flow('production_call_privacy_toggle'),
      },
    'observations': {
      'incoming': observation(504),
      for (final label in [
        'connected',
        'after-minimize',
        'after-home',
        'after-return',
      ])
        label: observation(505),
    },
    'peerIdUsernameFixture': {
      'peerSha256': otherIdentity,
      'afterUsernameEqualsPeerId': true,
      'beforeOtherColumnsSha256': _profileSha,
      'afterOtherColumnsSha256': _profileSha,
    },
    'minimizeReceipt': flow('production_call_minimize'),
    'returnReceipt': flow('production_call_return'),
    'notificationForegroundReceipt': {
      'ownedCallSurface': true,
      'sourceUiSha256': _apkSha,
    },
    'headsUpSamples': [
      for (var i = 0; i < 3; i++)
        {
          'sectionsObserved': 1,
          'ownedOngoingHeadsUpCount': 0,
          'sourceDumpSha256': _fixtureSha,
        },
    ],
    'incomingEventMarker': {
      'cursor': [_profileSha],
      'sourceDumpSha256': _profileSha,
      'events': [
        {'kind': 'posted', 'id': 504, 'eventSha256': _profileSha},
      ],
    },
    'handoverEvents': {
      'sourceDumpSha256': _apkSha,
      'events': [
        {'kind': 'posted', 'id': 505, 'eventSha256': _apkSha},
        {'kind': 'canceled', 'id': 504, 'eventSha256': _fixtureSha},
      ],
    },
  };
}

void main() {
  group('call notification regression counterexamples', () {
    late Directory directory;
    setUp(
      () => directory = Directory.systemTemp.createTempSync(
        'call-surface-oracle-',
      ),
    );
    tearDown(() => directory.deleteSync(recursive: true));
    Map<String, dynamic> clone(Map<String, Object?> proof) =>
        jsonDecode(jsonEncode(proof)) as Map<String, dynamic>;
    for (final id in [
      'kx0001',
      'kx0002',
      'kx0003',
      'kx0015',
      'kx0016',
      'kx0017',
      'kx0029',
      'kx0030',
    ]) {
      test('$id accepts its bound audio control and native evidence', () {
        expect(
          validateProductionCallRegression(_surfaceProof(directory, id)),
          isEmpty,
        );
      });
    }
    test(
      'signed-wire comparison preserves real origins instead of assuming five-second delivery headroom',
      () {
        final original = _surfaceProof(directory, 'kx0001');
        for (final mutate in <void Function(Map<String, dynamic>)>[
          (p) => p['wireDeadlines']['encodedInvites'][0]['wireExpiresAtMs'] =
              1052000,
          (p) => p['wireDeadlines']['encodedInvites'][0]['signaturePresent'] =
              false,
          (p) => p['wireDeadlines']['timers'][1]['deadlineMs'] = 1052000,
          (p) => p['wireDeadlines']['timers'][0]['effectiveDelayMs'] = 45000,
          (p) => p['wireDeadlines']['timers'][0]['callSha256'] = _fixtureSha,
          (p) => p['wireDeliveryGapMs'] = 5000,
          (p) => p['wireOutlivesDeliveryDeadline'] = false,
        ]) {
          final changed = clone(original);
          mutate(changed);
          expect(validateProductionCallRegression(changed), isNotEmpty);
        }
      },
    );
    test(
      'quiet flag cannot mask alerting channel, stale call or missing OS evidence',
      () {
        final original = _surfaceProof(directory, 'kx0002');
        for (final mutate in <void Function(Map<String, dynamic>)>[
          (p) =>
              p['observations']['connected']['cards'][0]['channelImportance'] =
                  4,
          (p) =>
              p['observations']['connected']['cards'][0]['sourceDumpSha256'] =
                  null,
          (p) => p['headsUpSamples'][0]['ownedOngoingHeadsUpCount'] = 1,
          (p) => p['headsUpSamples'][0]['sectionsObserved'] = 0,
          (p) => p['observations']['after-home']['current']['callSha256'] =
              _profileSha,
          (p) =>
              p['observations']['after-return']['cards'][0]['nativeKeySha256'] =
                  _apkSha,
          (p) => p['notificationForegroundReceipt']['ownedCallSurface'] = false,
          (p) => p['invocations'][1]['nonce'] = p['invocations'][0]['nonce'],
        ]) {
          final changed = clone(original);
          mutate(changed);
          expect(validateProductionCallRegression(changed), isNotEmpty);
        }
        final legacy = clone(original);
        for (final label in [
          'connected',
          'after-minimize',
          'after-home',
          'after-return',
        ]) {
          final card = legacy['observations'][label]['cards'][0];
          card['sdk'] = 24;
          card['channelImportance'] = null;
          card['priority'] = -1;
        }
        expect(validateProductionCallRegression(legacy), isEmpty);
        legacy['observations']['connected']['cards'][0]['priority'] = 0;
        expect(validateProductionCallRegression(legacy), isNotEmpty);
      },
    );
    test('final ongoing card cannot replace observed handover order', () {
      final original = _surfaceProof(directory, 'kx0003');
      final reversed = clone(original);
      reversed['handoverEvents']['events'] =
          (reversed['handoverEvents']['events'] as List).reversed.toList();
      expect(
        validateProductionCallRegression(reversed),
        contains('actual ongoing-before-ringing-cancel OS order missing'),
      );
      final noCursor = clone(original)..['incomingEventMarker'] = {};
      expect(validateProductionCallRegression(noCursor), isNotEmpty);
    });
    test('visible name must match the authenticated stored contact', () {
      final original = _surfaceProof(directory, 'kx0016');
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (p) => p['observations']['incoming']['cards'][0]['titleSha256'] =
            _profileSha,
        (p) => p['observations']['connected']['cards'][0]['titleSha256'] =
            _profileSha,
        (p) =>
            p['observations']['incoming']['cards'][0]['peerIdVisible'] = true,
        (p) => p['contactName']['contactSha256'] = _calleeIdentity,
        (p) => p['otherPeerSha256'] = _calleeIdentity,
      ]) {
        final changed = clone(original);
        mutate(changed);
        expect(validateProductionCallRegression(changed), isNotEmpty);
      }
    });
    test('peer-ID fallback preserves authority and excludes raw peer copy', () {
      final original = _surfaceProof(directory, 'kx0017');
      final authorityChanged = clone(original);
      authorityChanged['peerIdUsernameFixture']['afterOtherColumnsSha256'] =
          _apkSha;
      expect(validateProductionCallRegression(authorityChanged), isNotEmpty);
      final peerShown = clone(original);
      peerShown['observations']['connected']['cards'][0]['peerIdVisible'] =
          true;
      expect(validateProductionCallRegression(peerShown), isNotEmpty);
    });
    test(
      'picker availability and speaker fallback require current private-free provider evidence',
      () {
        final original = _surfaceProof(directory, 'kx0029');
        for (final mutate in <void Function(Map<String, dynamic>)>[
          (p) => p['pickerInventory']['rows'].removeLast(),
          (p) => p['pickerInventory']['provider']['outputs'][0]['id'] =
              'must-not-escape',
          (p) => p['speakerSelected']['selectedRoute'] = 'systemDefault',
          (p) => p['speakerReleased']['callSha256'] = _fixtureSha,
          (p) => p['speakerReleased']['selectedRoute'] = 'speaker',
          (p) => p['unavailableHardware'] = [],
        ]) {
          final changed = clone(original);
          mutate(changed);
          expect(validateProductionCallRegression(changed), isNotEmpty);
        }
      },
    );
    test(
      'preference proof needs actual toggle, truthful copy flow and restoration',
      () {
        final original = _surfaceProof(directory, 'kx0030');
        for (final mutate in <void Function(Map<String, dynamic>)>[
          (p) => p['privacy']['afterToggle'] = false,
          (p) => p['privacy']['restored'] = true,
          (p) => p['privacy']['copyReceipt'] = null,
          (p) => p['privacy']['restoreReceipt'] = null,
        ]) {
          final changed = clone(original);
          mutate(changed);
          expect(validateProductionCallRegression(changed), isNotEmpty);
        }
      },
    );
  });
  group('native call notification evidence', () {
    const packageName = 'com.mknoon.sims.productionaudio';
    test(
      'picker hierarchy exports coarse routes and rejects partial or foreign rows',
      () {
        String row({
          String package = packageName,
          int index = 0,
          String selected = 'true',
        }) =>
            '<node package="$package" resource-id="call-output-choice-bluetooth-$index" selected="$selected" enabled="true" bounds="[0,0][200,100]" text="Private headset label" />';
        List<Map<String, Object?>> parse(String nodes) =>
            productionCallOutputPickerRows(
              '<hierarchy>$nodes</hierarchy>',
              packageName: packageName,
            );
        final values = parse(row());
        expect(values.single['route'], 'bluetooth');
        expect(values.single['selected'], true);
        expect(jsonEncode(values), isNot(contains('Private headset')));
        expect(
          () => parse(row(package: 'foreign.fixture')),
          throwsFormatException,
        );
        expect(() => parse(row(index: 1)), throwsFormatException);
        expect(() => parse(row() + row()), throwsFormatException);
        expect(() => parse(row(selected: '')), throwsFormatException);
      },
    );
    String dump({
      int uid = 12001,
      String name = 'Fixture caller',
      int importance = 2,
      bool vibration = false,
      String sound = 'null',
      bool legacy = false,
    }) =>
        '''
Current Notification Manager state:
  NotificationRecord(synthetic: pkg=$packageName user=UserHandle{0} id=505 tag=null key=0|$packageName|505|null|$uid: Notification(${legacy ? 'pri=-1 contentView=null vibrate=null sound=null defaults=0x0' : 'channel=mknoon_calls_ongoing_v1'}))
    android.title=String ($name)
    android.text=String (Call in progress)
Ranking Config:
  AppSettings: $packageName ($uid)
    NotificationChannel{mId='mknoon_calls_ongoing_v1', mImportance=$importance, mSound=$sound, mVibrationEnabled=$vibration}
''';
    List<Map<String, Object?>> parse(String text, {int sdk = 37}) =>
        productionCallNotificationSnapshot(
          dump: text,
          packageName: packageName,
          uid: 12001,
          sdk: sdk,
          peerId: 'fixture-peer-identity',
        );
    test(
      'quiet ongoing evidence binds actual UID, channel settings and visible copy',
      () {
        final card = parse(dump()).single;
        expect(card['quiet'], isTrue);
        expect(card['channelImportance'], 2);
        expect(
          card['titleSha256'],
          sha256.convert(utf8.encode('Fixture caller')).toString(),
        );
        expect(card['peerIdVisible'], isFalse);
        expect(parse(dump(uid: 12002)), isEmpty);
        expect(parse(dump(importance: 4)).single['quiet'], isFalse);
        expect(parse(dump(vibration: true)).single['quiet'], isFalse);
        expect(
          parse(dump(sound: 'fixture-nonquiet-sound')).single['quiet'],
          isFalse,
        );
        expect(
          parse(dump(name: 'fixture-peer-identity')).single['peerIdVisible'],
          isTrue,
        );
        expect(
          () => parse(dump().replaceFirst('Ranking Config:', 'Incomplete:')),
          throwsFormatException,
        );
        expect(
          () => parse(
            dump().replaceFirst('pkg=$packageName', 'pkg=foreign.fixture'),
          ),
          throwsFormatException,
        );
      },
    );
    test('pre-channel priority evidence makes no channel claim', () {
      final card = parse(dump(legacy: true), sdk: 24).single;
      expect(card['quiet'], isTrue);
      expect(card['channelImportance'], isNull);
      expect(card['expectedOngoingChannel'], isNull);
      expect(
        parse(
          dump(legacy: true).replaceFirst('vibrate=null', 'vibrate=default'),
          sdk: 24,
        ).single['quiet'],
        isFalse,
      );
    });
    test('heads-up absence requires complete readable manager entries', () {
      String manager(String entry) =>
          'HeadsUpManager state:\n  mUser=0\n$entry\n  snoozed packages: 0\n';
      Map<String, Object?> read(String value) => productionCallHeadsUpSnapshot(
        value,
        packageName: packageName,
        uid: 12001,
      );
      expect(read(manager(''))['ownedOngoingHeadsUpCount'], 0);
      expect(
        read(
          manager('NotificationEntry{key=0|foreign.fixture|505|null|12002}'),
        )['ownedOngoingHeadsUpCount'],
        0,
      );
      expect(
        read(
          manager('NotificationEntry{key=0|$packageName|504|null|12001}'),
        )['ownedOngoingHeadsUpCount'],
        0,
      );
      expect(
        read(
          manager('NotificationEntry{key=0|$packageName|505|null|12001}'),
        )['ownedOngoingHeadsUpCount'],
        1,
      );
      expect(
        () => read(manager('UnrecognizedEntry@synthetic')),
        throwsFormatException,
      );
      expect(
        () => read(manager('').replaceFirst('snoozed packages:', 'Missing:')),
        throwsFormatException,
      );
    });
    test(
      'OS publication order excludes stale events, wrong UID and ignored posts',
      () {
        String post(String time, int id, {int status = 0, int uid = 12001}) =>
            '$time 11 12 I notification_enqueue: [$uid,13,$packageName,$id,null,0,Notification(channel=fixture),$status,1]';
        const cancel =
            '1002.000000 11 12 I notification_canceled: [0|$packageName|504|null|12001,8,0,0,0,0,0,fixture]';
        final initial = post('1000.000000', 504);
        final before = productionCallNotificationEvents(
          initial,
          packageName: packageName,
          uid: 12001,
        );
        final cursor = List<String>.from(before['cursor'] as List);
        final result = productionCallNotificationEvents(
          [
            initial,
            post('1001.000000', 505, uid: 12002),
            post('1001.100000', 505, status: 2),
            post('1001.200000', 505),
            cancel,
          ].join('\n'),
          packageName: packageName,
          uid: 12001,
          afterCursor: cursor,
        );
        expect((result['events'] as List).map((e) => [e['kind'], e['id']]), [
          ['posted', 505],
          ['canceled', 504],
        ]);
        final reversed = productionCallNotificationEvents(
          '$initial\n$cancel\n${post('1003.000000', 505)}',
          packageName: packageName,
          uid: 12001,
          afterCursor: cursor,
        );
        expect((reversed['events'] as List).first['kind'], 'canceled');
        for (final invalid in [cancel, '$initial\n$initial\n$cancel']) {
          expect(
            () => productionCallNotificationEvents(
              invalid,
              packageName: packageName,
              uid: 12001,
              afterCursor: cursor,
            ),
            throwsFormatException,
          );
        }
      },
    );
  });
  group('callback regression evidence', () {
    for (final id in ['kx0005', 'kx0006']) {
      test('$id requires actual A/B submission and B-only admission', () {
        final proof = _callbackProof(id);
        expect(validateProductionCallBack(proof), isEmpty);
        final result = proof['resultSnapshot'] as Map;
        (result['events'] as List).insert(1, {
          'stage': 'redialRequested',
          'historyCallSha256': _callerBinding,
        });
        expect(
          validateProductionCallBack(proof),
          contains('B-only admission/result not observed'),
        );
      });
    }
    test(
      'unlock requires an open readiness latch while native keyguard stays locked',
      () {
        final proof = _callbackProof('kx0006');
        expect(validateProductionCallBack(proof), isEmpty);
        final phases = proof['phases'] as List;
        ((phases.firstWhere((p) => p['label'] == 'still-locked'))['snapshot']
                as Map)['readinessHeld'] =
            true;
        expect(
          validateProductionCallBack(proof),
          contains('real unlock boundary/restoration missing'),
        );
      },
    );
    test(
      'busy requires the original canonical call and actual app-owned message',
      () {
        final proof = _callbackProof('kx0007');
        expect(validateProductionCallBack(proof), isEmpty);
        final phases = proof['phases'] as List;
        final after =
            phases.firstWhere((p) => p['label'] == 'after-busy')['snapshot']
                as Map;
        after['callSha256'] = _fixtureSha;
        expect(
          validateProductionCallBack(proof),
          contains(
            'busy callback changed the original call or its approved result',
          ),
        );
        after['callSha256'] = _callerBinding;
        final receipt = proof['messageReceipt'] as Map;
        final file = File(receipt['path'] as String);
        file.writeAsStringSync(
          file.readAsStringSync().replaceAll(
            'com.mknoon.sims.productionaudio',
            'foreign.fixture',
          ),
        );
        receipt['sha256'] = sha256.convert(file.readAsBytesSync()).toString();
        expect(
          validateProductionCallBack(proof),
          contains('actual unavailable message missing'),
        );
      },
    );
    test(
      'denial requires typed result, OS message flow and positive-to-zero native capture',
      () {
        final proof = _callbackProof('kx0008');
        expect(validateProductionCallBack(proof), isEmpty);
        final capture = proof['negativeCapture'] as Map;
        capture['captureReadSucceeded'] = false;
        expect(
          validateProductionCallBack(proof),
          contains('real positive-to-zero recording control missing'),
        );
        capture['captureReadSucceeded'] = true;
        capture['activeOwnedRecordClients'] = 1;
        expect(
          validateProductionCallBack(proof),
          contains('real positive-to-zero recording control missing'),
        );
        capture['activeOwnedRecordClients'] = 0;
        ((proof['resultSnapshot'] as Map)['events'] as List).last['result'] =
            'failed';
        expect(
          validateProductionCallBack(proof),
          contains('denied callback result or fresh runtime missing'),
        );
      },
    );
    test(
      'a valid audio control outside this attempt cannot certify the callback',
      () {
        final proof = _callbackProof('kx0005');
        expect(validateProductionCallBack(proof), isEmpty);
        proof['attemptDirectory'] = Directory.systemTemp
            .createTempSync('other-callback-proof-')
            .path;
        addTearDown(
          () => Directory(
            proof['attemptDirectory'] as String,
          ).deleteSync(recursive: true),
        );
        expect(
          validateProductionCallBack(proof),
          contains('current authenticated audio control/restoration missing'),
        );
      },
    );
    test(
      'native recording inventory distinguishes owned active input from inactive or foreign clients',
      () {
        const start =
            'AudioPolicyManager Dump: synthetic\n Inputs (1):\n  1. Port ID: 7; 0x0000; I/O handle: 9\n    AudioRecord Clients (1):\n';
        const client =
            '    Port ID: 8; Session ID: 6; uid 12001; State: Active\n    AUDIO_FORMAT_PCM_16_BIT; 48000; Channel mask: 0x10\n    Attributes: source=7\n    Source: 7; Flags: 00000000; is soundtrigger: 0\n';
        const end = '\n AllowedCapturePolicies:\n\nPolicy Engine dump:\n';
        expect(
          productionCallbackAudioCaptureSnapshot(
            '$start$client$end',
            uid: 12001,
          )['activeOwnedRecordClients'],
          1,
        );
        expect(
          productionCallbackAudioCaptureSnapshot(
            '$start$client$end',
            uid: 12002,
          )['activeOwnedRecordClients'],
          0,
        );
        expect(
          productionCallbackAudioCaptureSnapshot(
            '$start${client.replaceFirst('State: Active', 'State: Inactive')}$end',
            uid: 12001,
          )['activeOwnedRecordClients'],
          0,
        );
        expect(
          productionCallbackAudioCaptureSnapshot(
            'AudioPolicyManager Dump: synthetic\n Inputs (0):\n$end',
            uid: 12001,
          )['activeOwnedRecordClients'],
          0,
        );
        for (final invalid in [
          '$start$client',
          '$start${client.replaceFirst('Source:', 'UnknownSource:')}$end',
          '${start.replaceFirst('Clients (1)', 'Clients (2)')}$client$end',
        ]) {
          expect(
            () => productionCallbackAudioCaptureSnapshot(invalid, uid: 12001),
            throwsFormatException,
          );
        }
      },
    );
    test(
      'only a complete credential-free native keyguard state allows the unlock fixture',
      () {
        const dump =
            'KeyguardServiceDelegate\n  showing=false\n  secure=false\n  systemIsReady=true\n  deviceHasKeyguard=true\n';
        expect(productionCallbackKeyguardIsUnsecured(dump), isTrue);
        for (final invalid in [
          '',
          'secure=false',
          dump.replaceFirst('secure=false', 'secure=true'),
          dump.replaceFirst('systemIsReady=true', 'systemIsReady=false'),
        ]) {
          expect(productionCallbackKeyguardIsUnsecured(invalid), isFalse);
        }
      },
    );
    test('an API 37 keyguard dump without a secure line needs a disabled lock '
        'screen', () {
      const api37 =
          'KeyguardServiceDelegate\n  showing=false\n  inputRestricted=false\n'
          '  occluded=false\n  trusted=false\n  simSecure=false\n'
          '  dreaming=false\n  systemReady=true\n  deviceHasKeyguard=true\n'
          '  enabled=true\n  userId=0\n  bootCompleted=true\n';
      expect(
        productionCallbackKeyguardIsUnsecured(api37, lockscreenDisabled: true),
        isTrue,
      );
      expect(
        productionCallbackKeyguardIsUnsecured(api37, lockscreenDisabled: false),
        isFalse,
      );
      expect(productionCallbackKeyguardIsUnsecured(api37), isFalse);
      expect(
        productionCallbackKeyguardIsUnsecured(
          api37.replaceFirst('systemReady=true', 'systemReady=false'),
          lockscreenDisabled: true,
        ),
        isFalse,
      );
      expect(
        productionCallbackKeyguardIsUnsecured(
          api37.replaceFirst('simSecure=false', 'secure=true'),
          lockscreenDisabled: true,
        ),
        isFalse,
      );
    });
  });
  test(
    'emulator audio evidence cannot satisfy the original physical validator',
    () {
      final proof = _aggregate(emulatorPair: true);
      expect((proof['topology'] as Map)['calleeKind'], 'emulator');
      expect(validateAndroidProductionAudioCallEvidence(proof).ok, isFalse);
      expect(
        validateAndroidProductionAudioCallEvidence(
          proof,
          emulatorPair: true,
        ).ok,
        isTrue,
      );
      final physical = _aggregate();
      expect(
        validateAndroidProductionAudioCallEvidence(
          physical,
          emulatorPair: true,
        ).ok,
        isFalse,
      );
    },
  );
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
