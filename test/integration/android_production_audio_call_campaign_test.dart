import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/debug/android_production_audio_call_e2e.dart'
    as app_observer;
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scripts/android_production_audio_call_campaign.dart';
import '../../integration_test/support/android_app_state_guard.dart';
import '../../integration_test/scripts/run_production_audio_call_sims.dart';
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

Map<String, Object?> _pionOracleResult({
  String fixtureInstanceSha256 = _coturnInstanceSha,
}) => <String, Object?>{
  'schema': 'mknoon.call_audio_oracle.result.v1',
  'version': 1,
  'passed': true,
  'pion_version': 'v4.2.19',
  'fixture_sha256': _knownFixtureSha,
  'turn_authority_sha256': _turnAuthoritySha,
  'fixture_instance_sha256': fixtureInstanceSha256,
  'coturn': <String, Object?>{
    'image': 'coturn/coturn:4.17.2-r0',
    'digest': androidProductionAudioCallCoturnImageDigest,
  },
  'expected_transport': 'udp',
  'a_to_b': <String, Object?>{
    'codec_valid': true,
    'payload_count_exact': true,
    'payload_order_exact': true,
    'payload_hash_exact': true,
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
  'cleanup_complete': true,
};

final AndroidProductionAudioCallPionOracleEvidence _pionOracle =
    AndroidProductionAudioCallPionOracleEvidence.fromResult(
      _pionOracleResult(),
    );

void main() {
  test('host constants remain exact with the read-only app observer', () {
    expect(
      androidProductionAudioCallObserverAction,
      app_observer.androidProductionAudioCallE2EAction,
    );
    expect(
      androidProductionAudioCallScenarioId,
      app_observer.androidProductionAudioCallE2EScenario,
    );
    expect(
      androidProductionAudioCallProfileId,
      app_observer.androidProductionAudioCallE2EBuildProfile,
    );
    expect(
      androidProductionAudioCallObservationRequestSchema,
      app_observer.androidProductionAudioCallE2ERequestSchema,
    );
    expect(
      androidProductionAudioCallObservationResultSchema,
      app_observer.androidProductionAudioCallE2EResultSchema,
    );
    expect(
      androidProductionAudioCallReadinessOperation,
      app_observer.androidProductionAudioCallReadinessOperation,
    );
  });

  test('campaign accepts only a bounded sanitized Pion oracle envelope', () {
    final encoded = base64Encode(utf8.encode(jsonEncode(_pionOracleResult())));
    final decoded = decodeAndroidProductionAudioCallPionOracleAttestation(
      encoded,
    );

    expect(decoded.toJson()['pionOraclePassed'], isTrue);
    expect(
      () => decodeAndroidProductionAudioCallPionOracleAttestation(''),
      throwsFormatException,
    );
    expect(
      () => decodeAndroidProductionAudioCallPionOracleAttestation(
        base64Encode(utf8.encode('{"password":"private"}')),
      ),
      throwsFormatException,
    );
  });

  test('topology requires physical first and distinct emulator second', () {
    expect(
      () => validateAndroidProductionAudioCallTopology(
        <AndroidProductionAudioCallTarget>[
          const AndroidProductionAudioCallTarget(
            deviceId: 'emulator-5554',
            kind: AndroidProductionAudioCallTargetKind.emulator,
          ),
          const AndroidProductionAudioCallTarget(
            deviceId: 'pixel',
            kind: AndroidProductionAudioCallTargetKind.physical,
          ),
        ],
      ),
      throwsFormatException,
    );
    expect(
      () => validateAndroidProductionAudioCallTopology(
        <AndroidProductionAudioCallTarget>[
          const AndroidProductionAudioCallTarget(
            deviceId: 'pixel',
            kind: AndroidProductionAudioCallTargetKind.physical,
          ),
          const AndroidProductionAudioCallTarget(
            deviceId: 'pixel',
            kind: AndroidProductionAudioCallTargetKind.emulator,
          ),
        ],
      ),
      throwsFormatException,
    );
  });

  test('production app semantic ownership cannot be overridden', () {
    expect(
      () => validateAndroidProductionAudioCallAppPackage('com.evil.overlay'),
      throwsFormatException,
    );
    expect(
      () => validateAndroidProductionAudioCallAppPackage('com.mknoon.app'),
      returnsNormally,
    );
  });

  test(
    'semantic selector accepts exactly one enabled clickable exact label',
    () {
      const xml = '''
<hierarchy>
  <node content-desc="Start voice call" clickable="true" enabled="true"
      visible-to-user="true" package="com.mknoon.app"
      bounds="[100,200][300,400]" />
  <node content-desc="Start voice calling help" clickable="true" enabled="true"
      visible-to-user="true" package="com.mknoon.app"
      bounds="[400,200][600,400]" />
</hierarchy>
''';

      final node = selectExactAndroidProductionAudioSemanticNode(
        xml,
        label: 'Start voice call',
        allowedPackages: const <String>{'com.mknoon.app'},
      );
      expect((node.centerX, node.centerY), (200, 300));
      expect(node.label, 'Start voice call');
    },
  );

  test(
    'semantic selector fails closed on ambiguity and has no text fallback',
    () {
      const ambiguous = '''
<hierarchy>
  <node content-desc="Answer" clickable="true" enabled="true"
      package="com.android.systemui" bounds="[0,0][100,100]" />
  <node content-desc="Answer" clickable="true" enabled="true"
      package="com.android.systemui" bounds="[100,0][200,100]" />
</hierarchy>
''';
      expect(
        () => selectExactAndroidProductionAudioSemanticNode(
          ambiguous,
          label: 'Answer',
          allowedPackages: const <String>{'com.android.systemui'},
        ),
        throwsA(
          isA<AndroidProductionAudioCallSelectorException>().having(
            (error) => error.message,
            'message',
            contains('found 2'),
          ),
        ),
      );

      const textOnly = '''
<hierarchy>
  <node text="Answer" content-desc="" clickable="true" enabled="true"
      package="com.android.systemui" bounds="[0,0][100,100]" />
</hierarchy>
''';
      expect(
        () => selectExactAndroidProductionAudioSemanticNode(
          textOnly,
          label: 'Answer',
          allowedPackages: const <String>{'com.android.systemui'},
        ),
        throwsA(isA<AndroidProductionAudioCallSelectorException>()),
      );
    },
  );

  test('semantic selector rejects exact labels owned by another package', () {
    const xml = '''
<hierarchy>
  <node content-desc="Answer" clickable="true" enabled="true"
      visible-to-user="true" package="com.evil.overlay"
      bounds="[0,0][100,100]" />
</hierarchy>
''';

    expect(
      () => selectExactAndroidProductionAudioSemanticNode(
        xml,
        label: 'Answer',
        allowedPackages: const <String>{
          'com.mknoon.app',
          'com.android.systemui',
        },
      ),
      throwsA(isA<AndroidProductionAudioCallSelectorException>()),
    );
  });

  test(
    'native Answer selector accepts an exact system notification text action',
    () {
      const xml = '''
<hierarchy>
  <node text="Answer" content-desc="" clickable="true" enabled="true"
      visible-to-user="true" package="com.android.systemui"
      bounds="[10,20][110,120]" />
</hierarchy>
''';

      final node = selectExactAndroidProductionAudioNativeAnswerNode(
        xml,
        allowedPackages: const <String>{'com.android.systemui'},
      );

      expect(node.label, 'Answer');
      expect(node.packageName, 'com.android.systemui');
      expect((node.centerX, node.centerY), (60, 70));
    },
  );

  test('native Answer selector rejects app ownership and ambiguity', () {
    const appOwned = '''
<hierarchy>
  <node text="Answer" content-desc="" clickable="true" enabled="true"
      visible-to-user="true" package="com.mknoon.app"
      bounds="[0,0][100,100]" />
</hierarchy>
''';
    expect(
      () => selectExactAndroidProductionAudioNativeAnswerNode(
        appOwned,
        allowedPackages: const <String>{'com.mknoon.app'},
      ),
      throwsA(isA<AndroidProductionAudioCallSelectorException>()),
    );

    const ambiguous = '''
<hierarchy>
  <node text="Answer" content-desc="" clickable="true" enabled="true"
      visible-to-user="true" package="com.android.systemui"
      bounds="[0,0][100,100]" />
  <node text="" content-desc="Answer" clickable="true" enabled="true"
      visible-to-user="true" package="com.android.systemui"
      bounds="[100,0][200,100]" />
</hierarchy>
''';
    expect(
      () => selectExactAndroidProductionAudioNativeAnswerNode(
        ambiguous,
        allowedPackages: const <String>{'com.android.systemui'},
      ),
      throwsA(isA<AndroidProductionAudioCallSelectorException>()),
    );
  });

  test('native semantic diagnostics expose only coarse safe markers', () {
    const xml = '''
<hierarchy>
  <node text="MKnoon call" package="com.android.systemui" />
  <node text="Incoming call" package="com.android.systemui" />
  <node text="Answer" package="com.android.systemui" />
  <node content-desc="Answer" package="com.mknoon.app" />
  <node text="Answer" package="com.evil.overlay" />
  <node text="private contact value" package="com.android.systemui" />
</hierarchy>
''';

    final diagnostic = inspectAndroidProductionAudioCallNativeSemanticSurface(
      xml,
    );

    expect(
      diagnostic.markers,
      unorderedEquals(<String>['title', 'incoming', 'answer']),
    );
    expect(
      diagnostic.answerOwnerClasses,
      unorderedEquals(<String>['native-candidate', 'app', 'other']),
    );
    expect('$diagnostic', isNot(contains('private contact value')));
    expect('$diagnostic', isNot(contains('com.evil.overlay')));
  });

  test(
    'native Answer driver reveals the system notification shade before tap',
    () async {
      final runner = _NotificationShadeAnswerRunner();
      final driver = SystemAndroidProductionAudioCallCampaignDriver(
        physicalDeviceId: 'pixel',
        emulatorDeviceId: 'emulator-5554',
        artifact: File('${Directory.systemTemp.path}/plan399-unused.apk'),
        artifactSha256: _apkSha,
        packageName: androidProductionAudioCallAppPackage,
        relayHost: '192.168.0.60',
        relayPort: 44001,
        proofDirectory: Directory.systemTemp,
        runner: runner,
      );

      expect(await driver.tapNativeAnswer('pixel'), 'com.android.systemui');
      expect(
        runner.invocations,
        contains(
          equals(<String>[
            '-s',
            'pixel',
            'shell',
            'cmd',
            'statusbar',
            'expand-notifications',
          ]),
        ),
      );
      expect(
        runner.invocations,
        contains(
          equals(<String>[
            '-s',
            'pixel',
            'shell',
            'cmd',
            'statusbar',
            'collapse',
          ]),
        ),
      );
      expect(
        runner.invocations,
        contains(
          equals(<String>['-s', 'pixel', 'shell', 'input', 'tap', '60', '70']),
        ),
      );
    },
  );

  test(
    'opening a conversation foregrounds the app-side navigated conversation without a UI tap or force-stop',
    () async {
      final runner = _ConversationForegroundRunner();
      final driver = SystemAndroidProductionAudioCallCampaignDriver(
        physicalDeviceId: 'pixel',
        emulatorDeviceId: 'emulator-5554',
        artifact: File('${Directory.systemTemp.path}/plan399-unused.apk'),
        artifactSha256: _apkSha,
        packageName: androidProductionAudioCallAppPackage,
        relayHost: '192.168.0.60',
        relayPort: 44001,
        proofDirectory: Directory.systemTemp,
        runner: runner,
      );

      await driver.openConversation(
        deviceId: 'emulator-5554',
        contactUsername: 'Plan399Callee',
      );

      expect(
        runner.invocations,
        contains(
          equals(<String>[
            '-s',
            'emulator-5554',
            'shell',
            'am',
            'start',
            '-W',
            '--activity-reorder-to-front',
            '-n',
            '$androidProductionAudioCallAppPackage/.MainActivity',
          ]),
        ),
      );
      expect(
        runner.invocations.expand((arguments) => arguments),
        isNot(contains('force-stop')),
      );
      expect(runner.tapCount, 0);
      expect(runner.timedInvocations, isEmpty);
    },
  );

  test('cold launch alone receives the extended host deadline', () async {
    final runner = _ColdLaunchTimeoutRunner();
    final driver = SystemAndroidProductionAudioCallCampaignDriver(
      physicalDeviceId: 'pixel',
      emulatorDeviceId: 'emulator-5554',
      artifact: File('${Directory.systemTemp.path}/plan399-unused.apk'),
      artifactSha256: _apkSha,
      packageName: androidProductionAudioCallAppPackage,
      relayHost: '192.168.0.60',
      relayPort: 44001,
      proofDirectory: Directory.systemTemp,
      runner: runner,
    );

    final identity = await driver.bootstrapIdentity(
      deviceId: 'emulator-5554',
      role: androidProductionAudioCallCallerRole,
    );

    expect(identity.username, 'Plan399Caller');
    expect(runner.timedInvocations, hasLength(1));
    final invocation = runner.timedInvocations.single;
    expect(invocation.arguments, <String>[
      '-s',
      'emulator-5554',
      'shell',
      'am',
      'start',
      '-W',
      '-n',
      '$androidProductionAudioCallAppPackage/.MainActivity',
    ]);
    expect(
      invocation.timeout.compareTo(const Duration(minutes: 5)),
      greaterThanOrEqualTo(0),
    );
    expect(
      runner.ordinaryInvocations,
      contains(
        equals(<String>[
          '-s',
          'emulator-5554',
          'shell',
          'am',
          'force-stop',
          androidProductionAudioCallAppPackage,
        ]),
      ),
    );
  });

  test(
    'contact setup foregrounds the bootstrapped app without a cold relaunch',
    () async {
      final runner = _LiveContactSetupRunner();
      final driver = SystemAndroidProductionAudioCallCampaignDriver(
        physicalDeviceId: 'pixel',
        emulatorDeviceId: 'emulator-5554',
        artifact: File('${Directory.systemTemp.path}/plan399-unused.apk'),
        artifactSha256: _apkSha,
        packageName: androidProductionAudioCallAppPackage,
        relayHost: '192.168.0.60',
        relayPort: 44001,
        proofDirectory: Directory.systemTemp,
        runner: runner,
      );

      await driver.establishContact(
        ownerDeviceId: 'emulator-5554',
        ownerRole: androidProductionAudioCallCallerRole,
        contact: const AndroidProductionAudioCallIdentity(
          username: 'Plan399Callee',
          peerId: 'peer-callee',
          qrPayload: '{"ns":"peer-callee","un":"Plan399Callee"}',
          mlKemPublicKey: 'mlkem-callee',
        ),
      );

      expect(runner.timedInvocations, isEmpty);
      expect(
        runner.ordinaryInvocations,
        contains(
          equals(<String>[
            '-s',
            'emulator-5554',
            'shell',
            'am',
            'start',
            '-W',
            '--activity-reorder-to-front',
            '-n',
            '$androidProductionAudioCallAppPackage/.MainActivity',
          ]),
        ),
      );
      expect(
        runner.ordinaryInvocations.expand((arguments) => arguments),
        isNot(contains('force-stop')),
      );
      expect(runner.configStagedAt, lessThan(runner.foregroundedAt));
      expect(runner.matchingResultReads, 1);
      expect(
        runner.stagedConfig['open_conversation_with_peer_id'],
        'peer-callee',
      );
      expect(
        runner.stagedConfig['send_contact_requests_for_added_contacts'],
        isTrue,
      );
      expect(runner.stagedConfig['require_exact_call_wake_receipt'], isTrue);
    },
  );

  test(
    'contact setup rejects a terminal receipt without the requested app navigation',
    () async {
      final runner = _LiveContactSetupRunner(
        uiNavigation: const <String, Object?>{
          'requestedPeerId': 'peer-callee',
          'opened': false,
        },
      );
      final driver = SystemAndroidProductionAudioCallCampaignDriver(
        physicalDeviceId: 'pixel',
        emulatorDeviceId: 'emulator-5554',
        artifact: File('${Directory.systemTemp.path}/plan399-unused.apk'),
        artifactSha256: _apkSha,
        packageName: androidProductionAudioCallAppPackage,
        relayHost: '192.168.0.60',
        relayPort: 44001,
        proofDirectory: Directory.systemTemp,
        runner: runner,
      );

      await expectLater(
        driver.establishContact(
          ownerDeviceId: 'emulator-5554',
          ownerRole: androidProductionAudioCallCallerRole,
          contact: const AndroidProductionAudioCallIdentity(
            username: 'Plan399Callee',
            peerId: 'peer-callee',
            qrPayload: '{"ns":"peer-callee","un":"Plan399Callee"}',
            mlKemPublicKey: 'mlkem-callee',
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('did not open the requested conversation'),
          ),
        ),
      );
      expect(
        runner.stagedConfig['open_conversation_with_peer_id'],
        'peer-callee',
      );
    },
  );

  test(
    'unchanged call UI reports semanticActionNotDispatched without downstream',
    () async {
      final runner = _StartDispatchRunner(
        postTapUi: const <String>[_startVoiceCallUi, _startVoiceCallUi],
      );
      final driver = _driverForStartDispatch(runner, maximumPolls: 2);

      final acknowledgement = await driver.dispatchStartVoiceCall(
        'emulator-5554',
      );

      expect(
        acknowledgement.status,
        AndroidProductionAudioCallStartDispatchStatus
            .semanticActionNotDispatched,
      );
      expect(acknowledgement.downstreamObserved, isFalse);
      expect(acknowledgement.observedSurfaces, isEmpty);
      expect(runner.tapCount, 1);
    },
  );

  test(
    'transient Starting voice call followed by Cancel acknowledges one tap',
    () async {
      final runner = _StartDispatchRunner(
        postTapUi: const <String>[_startingVoiceCallUi, _cancelCallUi],
      );
      final driver = _driverForStartDispatch(runner, maximumPolls: 2);

      final acknowledgement = await driver.dispatchStartVoiceCall(
        'emulator-5554',
      );

      expect(
        acknowledgement.status,
        AndroidProductionAudioCallStartDispatchStatus.acknowledged,
      );
      expect(acknowledgement.downstreamObserved, isTrue);
      expect(
        acknowledgement.observedSurfaces,
        <AndroidProductionAudioCallStartDispatchSurface>[
          AndroidProductionAudioCallStartDispatchSurface.starting,
          AndroidProductionAudioCallStartDispatchSurface.cancel,
        ],
      );
      expect(runner.tapCount, 1);
    },
  );

  test('Starting without Cancel is a typed downstream timeout', () async {
    final runner = _StartDispatchRunner(
      postTapUi: const <String>[_startingVoiceCallUi],
    );
    final driver = _driverForStartDispatch(runner, maximumPolls: 1);

    final acknowledgement = await driver.dispatchStartVoiceCall(
      'emulator-5554',
    );

    expect(
      acknowledgement.status,
      AndroidProductionAudioCallStartDispatchStatus.downstreamTimedOut,
    );
    expect(acknowledgement.downstreamObserved, isTrue);
    expect(
      acknowledgement.observedSurfaces,
      <AndroidProductionAudioCallStartDispatchSurface>[
        AndroidProductionAudioCallStartDispatchSurface.starting,
      ],
    );
    expect(runner.tapCount, 1);
  });

  test('call failure surface is a typed downstreamRejected result', () async {
    final runner = _StartDispatchRunner(
      postTapUi: const <String>[_startVoiceCallFailureUi],
    );
    final driver = _driverForStartDispatch(runner, maximumPolls: 1);

    final acknowledgement = await driver.dispatchStartVoiceCall(
      'emulator-5554',
    );

    expect(
      acknowledgement.status,
      AndroidProductionAudioCallStartDispatchStatus.downstreamRejected,
    );
    expect(acknowledgement.downstreamObserved, isTrue);
    expect(
      acknowledgement.observedSurfaces,
      <AndroidProductionAudioCallStartDispatchSurface>[
        AndroidProductionAudioCallStartDispatchSurface.failure,
      ],
    );
    expect(runner.tapCount, 1);
  });

  test(
    'failure diagnostic reads an exact app PID logcat and sanitizes it',
    () async {
      final runner = _AppPidLogcatRunner();
      final driver = SystemAndroidProductionAudioCallCampaignDriver(
        physicalDeviceId: 'pixel',
        emulatorDeviceId: 'emulator-5554',
        artifact: File('${Directory.systemTemp.path}/plan399-unused.apk'),
        artifactSha256: _apkSha,
        packageName: androidProductionAudioCallAppPackage,
        relayHost: '192.168.0.60',
        relayPort: 44001,
        proofDirectory: Directory.systemTemp,
        runner: runner,
      );

      final log = await driver.readSanitizedAppProcessLogcat('emulator-5554');

      expect(log, contains('safe production call marker'));
      expect(log, isNot(contains('rawPassword399')));
      expect(log, isNot(contains('192.168.0.44')));
      expect(
        runner.invocations,
        contains(
          equals(<String>[
            '-s',
            'emulator-5554',
            'shell',
            'pidof',
            '-s',
            androidProductionAudioCallAppPackage,
          ]),
        ),
      );
      expect(
        runner.invocations,
        contains(
          equals(<String>[
            '-s',
            'emulator-5554',
            'logcat',
            '-d',
            '--pid=4242',
            '-t',
            '2000',
            '-v',
            'threadtime',
          ]),
        ),
      );
    },
  );

  test('diagnostic sanitizer removes SDP, ICE, addresses, and counters', () {
    const privateDiagnostic = '''
v=0
a=ice-ufrag:rawUfrag399
a=ice-pwd:rawPassword399
a=candidate:1 1 UDP 2122260223 192.168.0.44 54321 typ host
stats={packetsSent:321, bytesReceived:654}
ui=<node text="a=ice-pwd&#58;encodedPassword399" />
''';

    final sanitized = sanitizeAndroidProductionAudioCallDiagnosticText(
      privateDiagnostic,
    );

    for (final forbidden in <String>[
      'rawUfrag399',
      'rawPassword399',
      'encodedPassword399',
      'a=ice-',
      'candidate:',
      '192.168.0.44',
      '54321',
      'packetsSent',
      'bytesReceived',
      '321',
      '654',
    ]) {
      expect(sanitized, isNot(contains(forbidden)));
    }
    expect(sanitized, contains('<redacted-private-line>'));
  });

  test('diagnostic sanitizer removes RTP identifier-only stats lines', () {
    const raw = '''
stats={ssrc:123456}
trackIdentifier=private-track
track_id=private-track-id
reportId=private-report
remote_id=private-remote
codecId=private-codec
mid=audio-0
rid=high
safe lifecycle marker
''';

    final sanitized = sanitizeAndroidProductionAudioCallDiagnosticText(raw);

    expect(sanitized, contains('safe lifecycle marker'));
    expect(sanitized, contains('<redacted-private-line>'));
    for (final privateValue in const <String>[
      '123456',
      'private-track',
      'private-track-id',
      'private-report',
      'private-remote',
      'private-codec',
      'audio-0',
      'high',
    ]) {
      expect(sanitized, isNot(contains(privateValue)));
    }
  });

  test('diagnostic sanitizer rejects whitespace-delimited ICE candidates', () {
    const privateDiagnostic =
        'candidate 1 1 UDP 2122260223 192.168.0.44 52705 typ host';

    final sanitized = sanitizeAndroidProductionAudioCallDiagnosticText(
      privateDiagnostic,
    );

    expect(sanitized, '<redacted-private-line>');
    for (final forbidden in <String>[
      'candidate',
      '2122260223',
      '192.168.0.44',
      '52705',
    ]) {
      expect(sanitized, isNot(contains(forbidden)));
    }
  });

  test('diagnostic sanitizer preserves safe nodes from one-line UI XML', () {
    const oneLineXml =
        '<hierarchy><node text="" content-desc="Answer" clickable="true" '
        'enabled="true" package="com.android.systemui" />'
        '<node text="candidate 1 1 UDP 1 192.168.0.44 52705 typ host" />'
        '</hierarchy>';

    final sanitized = sanitizeAndroidProductionAudioCallDiagnosticText(
      oneLineXml,
    );

    expect(sanitized, contains('content-desc="Answer"'));
    expect(sanitized, contains('package="com.android.systemui"'));
    expect(sanitized, contains('<redacted-private-line>'));
    expect(sanitized, isNot(contains('candidate 1')));
    expect(sanitized, isNot(contains('192.168.0.44')));
    expect(sanitized, isNot(contains('52705')));
  });

  test(
    'orchestrator overlaps independent peer work and uses fixed roles',
    () async {
      final driver = _FakeDriver();

      final proof = await executeAndroidProductionAudioCallCampaign(
        devices: const <String>['pixel', 'emulator-5554'],
        apkSha256: _apkSha,
        profileSha256: _profileSha,
        relayFixtureIdentitySha256: _fixtureSha,
        turnAuthoritySha256: _turnAuthoritySha,
        coturnInstanceIdentitySha256: _coturnInstanceSha,
        pionOracle: _pionOracle,
        driver: driver,
        runId: 'run-399',
        callerNonce: 'caller-nonce-399',
        calleeNonce: 'callee-nonce-399',
      );

      expect(validateAndroidProductionAudioCallEvidence(proof).ok, isTrue);
      final endpoints = proof['endpoints']! as Map<String, Object?>;
      for (final role in const <String>[
        androidProductionAudioCallCallerRole,
        androidProductionAudioCallCalleeRole,
      ]) {
        final endpoint = endpoints[role]! as Map<String, Object?>;
        expect(endpoint['inboundAudioRtpObserved'], isTrue);
        expect(endpoint['outboundAudioRtpObserved'], isTrue);
      }
      expect(
        (proof['mediaProof']! as Map<String, Object?>)['productionRtpClaimed'],
        isTrue,
      );
      expect(driver.maximumParallelClassifications, 2);
      expect(driver.maximumParallelPreparations, 2);
      expect(driver.maximumParallelBootstraps, 2);
      expect(driver.maximumParallelContacts, 1);
      expect(driver.contactEvents, <String>[
        'start:caller',
        'end:caller',
        'start:callee',
        'end:callee',
      ]);
      expect(driver.maximumParallelObserverOperations, 2);
      expect(driver.preparedApkDigests, <String>[_apkSha, _apkSha]);
      expect(driver.restoreCalls, 1);
      expect(
        driver.actions,
        containsAllInOrder(<String>[
          'tap:emulator-5554:Start voice call',
          'dispatch:emulator-5554:acknowledged',
          'observe:emulator-5554:readiness',
          'tap:pixel:Answer',
          'tap:emulator-5554:Mute',
          'tap:emulator-5554:Unmute',
          'tap:emulator-5554:Speaker',
          'tap:emulator-5554:End',
        ]),
      );
      expect(driver.actions, isNot(contains('wait:pixel:Answer')));
      expect(driver.readinessContactPeerIds, <String>['peer-callee']);
    },
  );

  test('caller wake readiness must be exact before native Answer', () async {
    final driver = _FakeDriver(wakeAuthorityReady: false);

    await expectLater(
      executeAndroidProductionAudioCallCampaign(
        devices: const <String>['pixel', 'emulator-5554'],
        apkSha256: _apkSha,
        profileSha256: _profileSha,
        relayFixtureIdentitySha256: _fixtureSha,
        turnAuthoritySha256: _turnAuthoritySha,
        coturnInstanceIdentitySha256: _coturnInstanceSha,
        pionOracle: _pionOracle,
        driver: driver,
        runId: 'run-399',
        callerNonce: 'caller-nonce-399',
        calleeNonce: 'callee-nonce-399',
      ),
      throwsFormatException,
    );

    expect(driver.actions, isNot(contains('tap:pixel:Answer')));
    expect(
      driver.actions,
      containsAllInOrder(<String>[
        'dispatch:emulator-5554:acknowledged',
        'observe:emulator-5554:readiness',
        'failure-artifacts:failure',
        'restore',
      ]),
    );
  });

  test(
    'campaign fails before acceptance when either RTP direction is absent',
    () async {
      for (final missingDirection in const <String>['inbound', 'outbound']) {
        final driver = _FakeDriver(missingRtpDirection: missingDirection);

        await expectLater(
          executeAndroidProductionAudioCallCampaign(
            devices: const <String>['pixel', 'emulator-5554'],
            apkSha256: _apkSha,
            profileSha256: _profileSha,
            relayFixtureIdentitySha256: _fixtureSha,
            turnAuthoritySha256: _turnAuthoritySha,
            coturnInstanceIdentitySha256: _coturnInstanceSha,
            pionOracle: _pionOracle,
            driver: driver,
            runId: 'run-399',
            callerNonce: 'caller-nonce-399',
            calleeNonce: 'callee-nonce-399',
            rtpObservationTimeout: Duration.zero,
            rtpObservationPollInterval: Duration.zero,
          ),
          throwsA(isA<TimeoutException>()),
          reason: '$missingDirection RTP must fail the campaign',
        );
        expect(driver.restoreCalls, 1);
      }
    },
  );

  test(
    'campaign polls both peers until sticky bidirectional RTP is observed',
    () async {
      final driver = _FakeDriver(rtpObservationFalseSamples: 1);

      final proof = await executeAndroidProductionAudioCallCampaign(
        devices: const <String>['pixel', 'emulator-5554'],
        apkSha256: _apkSha,
        profileSha256: _profileSha,
        relayFixtureIdentitySha256: _fixtureSha,
        turnAuthoritySha256: _turnAuthoritySha,
        coturnInstanceIdentitySha256: _coturnInstanceSha,
        pionOracle: _pionOracle,
        driver: driver,
        runId: 'run-399',
        callerNonce: 'caller-nonce-399',
        calleeNonce: 'callee-nonce-399',
        rtpObservationTimeout: const Duration(seconds: 1),
        rtpObservationPollInterval: Duration.zero,
      );

      expect(validateAndroidProductionAudioCallEvidence(proof).ok, isTrue);
      expect(driver.sampleObservationsByRole, <String, int>{
        androidProductionAudioCallCallerRole: 2,
        androidProductionAudioCallCalleeRole: 2,
      });
    },
  );

  test(
    'native Answer is not attempted without a downstream call acknowledgement',
    () async {
      final driver = _FakeDriver(
        startDispatchStatus: AndroidProductionAudioCallStartDispatchStatus
            .semanticActionNotDispatched,
      );

      await expectLater(
        executeAndroidProductionAudioCallCampaign(
          devices: const <String>['pixel', 'emulator-5554'],
          apkSha256: _apkSha,
          profileSha256: _profileSha,
          relayFixtureIdentitySha256: _fixtureSha,
          turnAuthoritySha256: _turnAuthoritySha,
          coturnInstanceIdentitySha256: _coturnInstanceSha,
          pionOracle: _pionOracle,
          driver: driver,
          runId: 'run-399',
          callerNonce: 'caller-nonce-399',
          calleeNonce: 'callee-nonce-399',
        ),
        throwsA(
          isA<AndroidProductionAudioCallStartDispatchException>().having(
            (error) => error.status,
            'status',
            AndroidProductionAudioCallStartDispatchStatus
                .semanticActionNotDispatched,
          ),
        ),
      );
      expect(driver.actions, isNot(contains('tap:pixel:Answer')));
      expect(
        driver.actions,
        containsAllInOrder(<String>[
          'tap:emulator-5554:Start voice call',
          'dispatch:emulator-5554:semanticActionNotDispatched',
          'failure-artifacts:failure',
          'restore',
        ]),
      );
    },
  );

  test('native Answer is not attempted after downstream timeout', () async {
    final driver = _FakeDriver(
      startDispatchStatus:
          AndroidProductionAudioCallStartDispatchStatus.downstreamTimedOut,
    );

    await expectLater(
      executeAndroidProductionAudioCallCampaign(
        devices: const <String>['pixel', 'emulator-5554'],
        apkSha256: _apkSha,
        profileSha256: _profileSha,
        relayFixtureIdentitySha256: _fixtureSha,
        turnAuthoritySha256: _turnAuthoritySha,
        coturnInstanceIdentitySha256: _coturnInstanceSha,
        pionOracle: _pionOracle,
        driver: driver,
        runId: 'run-399',
        callerNonce: 'caller-nonce-399',
        calleeNonce: 'callee-nonce-399',
      ),
      throwsA(
        isA<AndroidProductionAudioCallStartDispatchException>().having(
          (error) => error.status,
          'status',
          AndroidProductionAudioCallStartDispatchStatus.downstreamTimedOut,
        ),
      ),
    );
    expect(driver.actions, isNot(contains('tap:pixel:Answer')));
  });

  test('downstream call rejection also blocks native Answer', () async {
    final driver = _FakeDriver(
      startDispatchStatus:
          AndroidProductionAudioCallStartDispatchStatus.downstreamRejected,
    );

    await expectLater(
      executeAndroidProductionAudioCallCampaign(
        devices: const <String>['pixel', 'emulator-5554'],
        apkSha256: _apkSha,
        profileSha256: _profileSha,
        relayFixtureIdentitySha256: _fixtureSha,
        turnAuthoritySha256: _turnAuthoritySha,
        coturnInstanceIdentitySha256: _coturnInstanceSha,
        pionOracle: _pionOracle,
        driver: driver,
        runId: 'run-399',
        callerNonce: 'caller-nonce-399',
        calleeNonce: 'callee-nonce-399',
      ),
      throwsA(
        isA<AndroidProductionAudioCallStartDispatchException>().having(
          (error) => error.status,
          'status',
          AndroidProductionAudioCallStartDispatchStatus.downstreamRejected,
        ),
      ),
    );
    expect(driver.actions, isNot(contains('tap:pixel:Answer')));
  });

  test(
    'outer finally restores both apps exactly once after a UI failure',
    () async {
      final driver = _FakeDriver(failLabel: 'Answer');

      await expectLater(
        executeAndroidProductionAudioCallCampaign(
          devices: const <String>['pixel', 'emulator-5554'],
          apkSha256: _apkSha,
          profileSha256: _profileSha,
          relayFixtureIdentitySha256: _fixtureSha,
          turnAuthoritySha256: _turnAuthoritySha,
          coturnInstanceIdentitySha256: _coturnInstanceSha,
          pionOracle: _pionOracle,
          driver: driver,
          runId: 'run-399',
          callerNonce: 'caller-nonce-399',
          calleeNonce: 'callee-nonce-399',
        ),
        throwsStateError,
      );
      expect(driver.restoreCalls, 1);
      expect(
        driver.actions,
        containsAllInOrder(<String>[
          'tap:pixel:Answer',
          'failure-artifacts:failure',
          'restore',
        ]),
      );
    },
  );

  test('failure artifact capture cannot mask the original UI error', () async {
    final driver = _FakeDriver(
      failLabel: 'Start voice call',
      failFailureArtifactCapture: true,
    );

    await expectLater(
      executeAndroidProductionAudioCallCampaign(
        devices: const <String>['pixel', 'emulator-5554'],
        apkSha256: _apkSha,
        profileSha256: _profileSha,
        relayFixtureIdentitySha256: _fixtureSha,
        turnAuthoritySha256: _turnAuthoritySha,
        coturnInstanceIdentitySha256: _coturnInstanceSha,
        pionOracle: _pionOracle,
        driver: driver,
        runId: 'run-399',
        callerNonce: 'caller-nonce-399',
        calleeNonce: 'callee-nonce-399',
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'injected Start voice call failure',
        ),
      ),
    );
    expect(
      driver.actions,
      containsAllInOrder(<String>[
        'tap:emulator-5554:Start voice call',
        'failure-artifacts:failure',
        'restore',
      ]),
    );
  });

  test(
    'primary campaign failure remains authoritative when restoration fails',
    () async {
      final driver = _FakeDriver(failLabel: 'Answer', failRestore: true);

      await expectLater(
        executeAndroidProductionAudioCallCampaign(
          devices: const <String>['pixel', 'emulator-5554'],
          apkSha256: _apkSha,
          profileSha256: _profileSha,
          relayFixtureIdentitySha256: _fixtureSha,
          turnAuthoritySha256: _turnAuthoritySha,
          coturnInstanceIdentitySha256: _coturnInstanceSha,
          pionOracle: _pionOracle,
          driver: driver,
          runId: 'run-399',
          callerNonce: 'caller-nonce-399',
          calleeNonce: 'callee-nonce-399',
        ),
        throwsA(
          isA<AndroidProductionAudioCallPrimaryFailure>()
              .having(
                (error) => error.primaryError,
                'primaryError',
                isA<StateError>().having(
                  (error) => error.message,
                  'message',
                  'injected Answer failure',
                ),
              )
              .having(
                (error) => error.restorationError,
                'restorationError',
                isA<AndroidAppStateFailure>(),
              )
              .having(
                (error) => '$error',
                'diagnostic',
                allOf(
                  contains('injected Answer failure'),
                  contains('Secondary app-state restoration failure'),
                  contains('injected restoration failure'),
                ),
              ),
        ),
      );
      expect(driver.restoreCalls, 1);
    },
  );

  test(
    'restoration failure remains authoritative after a passing body',
    () async {
      final driver = _FakeDriver(failRestore: true);

      await expectLater(
        executeAndroidProductionAudioCallCampaign(
          devices: const <String>['pixel', 'emulator-5554'],
          apkSha256: _apkSha,
          profileSha256: _profileSha,
          relayFixtureIdentitySha256: _fixtureSha,
          turnAuthoritySha256: _turnAuthoritySha,
          coturnInstanceIdentitySha256: _coturnInstanceSha,
          pionOracle: _pionOracle,
          driver: driver,
          runId: 'run-399',
          callerNonce: 'caller-nonce-399',
          calleeNonce: 'callee-nonce-399',
        ),
        throwsA(
          isA<AndroidAppStateFailure>().having(
            (error) => error.detail,
            'detail',
            'injected restoration failure',
          ),
        ),
      );
      expect(driver.restoreCalls, 1);
    },
  );

  test('campaign rejects an app-owned Flutter Answer mutation', () async {
    final driver = _FakeDriver(
      nativeAnswerPackage: androidProductionAudioCallAppPackage,
    );

    await expectLater(
      executeAndroidProductionAudioCallCampaign(
        devices: const <String>['pixel', 'emulator-5554'],
        apkSha256: _apkSha,
        profileSha256: _profileSha,
        relayFixtureIdentitySha256: _fixtureSha,
        turnAuthoritySha256: _turnAuthoritySha,
        coturnInstanceIdentitySha256: _coturnInstanceSha,
        pionOracle: _pionOracle,
        driver: driver,
        runId: 'run-399',
        callerNonce: 'caller-nonce-399',
        calleeNonce: 'callee-nonce-399',
      ),
      throwsFormatException,
    );
    expect(driver.restoreCalls, 1);
  });

  test('sample and stop must retain the same opaque call binding', () async {
    final driver = _FakeDriver(mismatchStopBinding: true);

    await expectLater(
      executeAndroidProductionAudioCallCampaign(
        devices: const <String>['pixel', 'emulator-5554'],
        apkSha256: _apkSha,
        profileSha256: _profileSha,
        relayFixtureIdentitySha256: _fixtureSha,
        turnAuthoritySha256: _turnAuthoritySha,
        coturnInstanceIdentitySha256: _coturnInstanceSha,
        pionOracle: _pionOracle,
        driver: driver,
        runId: 'run-399',
        callerNonce: 'caller-nonce-399',
        calleeNonce: 'callee-nonce-399',
      ),
      throwsFormatException,
    );
    expect(driver.restoreCalls, 1);
  });

  test('native cleanup rejects an active package call only', () {
    expect(
      androidProductionAudioCallNativeStateReleased('''
Call TC@1:
  state=ACTIVE
  targetPhoneAccount=com.mknoon.app/.MknoonConnectionService
''', packageName: 'com.mknoon.app'),
      isFalse,
    );
    expect(
      androidProductionAudioCallNativeStateReleased('''
PhoneAccount: com.mknoon.app/.MknoonConnectionService
Calls:
''', packageName: 'com.mknoon.app'),
      isTrue,
    );
  });

  test(
    'native cleanup correlates distant state and account in one call block',
    () {
      final filler = List<String>.filled(
        24,
        '  unrelatedField=value',
      ).join('\n');
      expect(
        androidProductionAudioCallNativeStateReleased('''
Calls:
  Call TC@399:
    state=ACTIVE
$filler
    targetPhoneAccount=com.mknoon.app/.MknoonConnectionService
''', packageName: 'com.mknoon.app'),
        isFalse,
      );

      expect(
        androidProductionAudioCallNativeStateReleased('''
Calls:
  Call TC@other:
    state=ACTIVE
    targetPhoneAccount=com.example.other/.ConnectionService
  Call TC@399:
    state=DISCONNECTED
    targetPhoneAccount=com.mknoon.app/.MknoonConnectionService
''', packageName: 'com.mknoon.app'),
        isTrue,
      );
    },
  );

  test('native cleanup fails closed for every Android live call state', () {
    const liveStates = <String>[
      'NEW',
      'DIALING',
      'CONNECTING',
      'RINGING',
      'ACTIVE',
      'HOLDING',
      'SELECT_PHONE_ACCOUNT',
      'ANSWERED',
      'PULLING_CALL',
      'AUDIO_PROCESSING',
      'SIMULATED_RINGING',
      'DISCONNECTING',
    ];
    final distantFields = List<String>.filled(
      32,
      '    unrelatedField=value',
    ).join('\n');

    for (final state in liveStates) {
      expect(
        androidProductionAudioCallNativeStateReleased('''
Calls:
  Call TC@$state:
    mState=STATE_$state
$distantFields
    targetPhoneAccount=com.mknoon.app/.MknoonConnectionService
''', packageName: androidProductionAudioCallAppPackage),
        isFalse,
        reason: '$state must remain a live/nonterminal Telecom state',
      );
    }
  });

  test('native cleanup fails closed for an unknown owned call state', () {
    expect(
      androidProductionAudioCallNativeStateReleased('''
Calls:
  Call TC@future:
    state=FUTURE_ANDROID_CALL_STATE
    targetPhoneAccount=com.mknoon.app/.MknoonConnectionService
''', packageName: androidProductionAudioCallAppPackage),
      isFalse,
    );
  });

  test(
    'cleanup queries both targets concurrently and rejects either residue',
    () async {
      final driver = _FakeDriver(unreleasedDeviceId: 'emulator-5554');

      await expectLater(
        executeAndroidProductionAudioCallCampaign(
          devices: const <String>['pixel', 'emulator-5554'],
          apkSha256: _apkSha,
          profileSha256: _profileSha,
          relayFixtureIdentitySha256: _fixtureSha,
          turnAuthoritySha256: _turnAuthoritySha,
          coturnInstanceIdentitySha256: _coturnInstanceSha,
          pionOracle: _pionOracle,
          driver: driver,
          runId: 'run-399',
          callerNonce: 'caller-nonce-399',
          calleeNonce: 'callee-nonce-399',
        ),
        throwsStateError,
      );
      expect(
        driver.nativeCleanupDevices,
        unorderedEquals(<String>['pixel', 'emulator-5554']),
      );
      expect(driver.maximumParallelNativeCleanup, 2);
      expect(driver.restoreCalls, 1);
    },
  );

  test(
    'adapter pins every fixture and central build child to Go 1.25.0',
    () async {
      Map<String, String>? fixtureEnvironment;
      final centralEnvironments = <Map<String, String>>[];
      var fixtureStops = 0;
      final dependencies = AndroidProductionAudioCallSimsAdapterDependencies(
        resolveFixtureHostIp: (_) async => '192.168.0.60',
        startFixture:
            ({
              required String goExecutable,
              required String hostIp,
              required Map<String, String> environment,
            }) async {
              fixtureEnvironment = Map<String, String>.of(environment);
              return AndroidProductionAudioCallFixtureLease(
                multiaddr: '/ip4/192.168.0.60/tcp/44001/p2p/12D3KooWFixture399',
                fixtureIdentitySha256: _fixtureSha,
                turnAuthoritySha256: _turnAuthoritySha,
                coturnInstanceIdentitySha256: _coturnInstanceSha,
                pionOracleResult: _pionOracleResult(),
                stop: () async => fixtureStops += 1,
              );
            },
        runCentralSims:
            ({
              required String dartExecutable,
              required List<String> arguments,
              required Map<String, String> environment,
            }) async {
              centralEnvironments.add(Map<String, String>.of(environment));
              return 0;
            },
      );

      final result = await runAndroidProductionAudioCallSimsAdapter(
        mode: 'major',
        environment: const <String, String>{
          'GOTOOLCHAIN': 'auto',
          'RELIABILITY_MULTI_DEVICE_IDS': 'pixel,emulator-5554',
          'TURN_CREDENTIAL_URLS': 'turn:203.0.113.10:3478?transport=udp',
          'TURN_CREDENTIAL_PRIMARY_SECRET_B64':
              'MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=',
        },
        dependencies: dependencies,
      );

      expect(result, 0);
      expect(fixtureStops, 1);
      expect(centralEnvironments, hasLength(2));
      final everyChild = <Map<String, String>>[
        fixtureEnvironment!,
        ...centralEnvironments,
      ];
      expect(
        everyChild.map((environment) => environment['GOTOOLCHAIN']),
        everyElement(androidProductionAudioCallGoToolchain),
      );
      expect(
        centralEnvironments.first['TURN_CREDENTIAL_PRIMARY_SECRET_B64'],
        isNull,
      );
      expect(fixtureEnvironment!['TURN_CREDENTIAL_PRIMARY_SECRET_B64'], isNull);
      expect(fixtureEnvironment!['TURN_CREDENTIAL_URLS'], isNull);
      final encodedOracle = centralEnvironments
          .first[androidProductionAudioCallPionOracleEnvironment];
      expect(encodedOracle, isNotNull);
      expect(
        centralEnvironments.first['PLAN399_LOCAL_COTURN_INSTANCE_SHA256'],
        _coturnInstanceSha,
      );
      expect(
        decodeAndroidProductionAudioCallPionOracleAttestation(encodedOracle!),
        isA<AndroidProductionAudioCallPionOracleEvidence>(),
      );
    },
  );

  test(
    'adapter rejects a same-authority oracle from another coturn instance',
    () async {
      var fixtureStops = 0;
      var centralCalls = 0;
      final dependencies = AndroidProductionAudioCallSimsAdapterDependencies(
        resolveFixtureHostIp: (_) async => '192.168.0.60',
        startFixture:
            ({
              required String goExecutable,
              required String hostIp,
              required Map<String, String> environment,
            }) async => AndroidProductionAudioCallFixtureLease(
              multiaddr: '/ip4/192.168.0.60/tcp/44001/p2p/12D3KooWFixture399',
              fixtureIdentitySha256: _fixtureSha,
              turnAuthoritySha256: _turnAuthoritySha,
              coturnInstanceIdentitySha256: _coturnInstanceSha,
              pionOracleResult: _pionOracleResult(
                fixtureInstanceSha256:
                    '5555555555555555555555555555555555555555555555555555555555555555',
              ),
              stop: () async => fixtureStops += 1,
            ),
        runCentralSims:
            ({
              required String dartExecutable,
              required List<String> arguments,
              required Map<String, String> environment,
            }) async {
              centralCalls += 1;
              return 0;
            },
      );

      await expectLater(
        runAndroidProductionAudioCallSimsAdapter(
          mode: 'major',
          environment: const <String, String>{
            'RELIABILITY_MULTI_DEVICE_IDS': 'pixel,emulator-5554',
          },
          dependencies: dependencies,
        ),
        throwsFormatException,
      );
      expect(fixtureStops, 1);
      expect(centralCalls, 0);
    },
  );

  test(
    'adapter stops the combined fixture after every central terminal path',
    () async {
      for (final stopFails in <bool>[false, true]) {
        var fixtureStops = 0;
        var centralCalls = 0;
        final dependencies = AndroidProductionAudioCallSimsAdapterDependencies(
          resolveFixtureHostIp: (_) async => '192.168.0.60',
          startFixture:
              ({
                required String goExecutable,
                required String hostIp,
                required Map<String, String> environment,
              }) async => AndroidProductionAudioCallFixtureLease(
                multiaddr: '/ip4/192.168.0.60/tcp/44001/p2p/12D3KooWFixture399',
                fixtureIdentitySha256: _fixtureSha,
                turnAuthoritySha256: _turnAuthoritySha,
                coturnInstanceIdentitySha256: _coturnInstanceSha,
                pionOracleResult: _pionOracleResult(),
                stop: () async {
                  fixtureStops += 1;
                  if (stopFails) throw StateError('injected fixture stop');
                },
              ),
          runCentralSims:
              ({
                required String dartExecutable,
                required List<String> arguments,
                required Map<String, String> environment,
              }) async {
                centralCalls += 1;
                return 17;
              },
        );

        final result = await runAndroidProductionAudioCallSimsAdapter(
          mode: 'major',
          environment: const <String, String>{
            'RELIABILITY_MULTI_DEVICE_IDS': 'pixel,emulator-5554',
          },
          dependencies: dependencies,
        );

        expect(fixtureStops, 1);
        expect(centralCalls, 1);
        expect(result, stopFails ? 1 : 17);
      }
    },
  );

  test(
    'adapter delegates per-run coturn and Pion ownership to one fixture',
    () {
      final source = File(
        'integration_test/scripts/run_production_audio_call_sims.dart',
      ).readAsStringSync();
      expect(source, contains('ProductionAudioCallLocalFixtureLease.start'));
      expect(source, contains('verifyAndroidPairAndReachability'));
      expect(source, contains('runAudioOracle'));
      expect(source, contains('..remove(_turnSecretEnvironment)'));
      expect(source, isNot(contains('docker run')));
    },
  );
}

SystemAndroidProductionAudioCallCampaignDriver _driverForStartDispatch(
  AndroidHostProcessRunner runner, {
  required int maximumPolls,
}) => SystemAndroidProductionAudioCallCampaignDriver(
  physicalDeviceId: 'pixel',
  emulatorDeviceId: 'emulator-5554',
  artifact: File('${Directory.systemTemp.path}/plan399-unused.apk'),
  artifactSha256: _apkSha,
  packageName: androidProductionAudioCallAppPackage,
  relayHost: '192.168.0.60',
  relayPort: 44001,
  proofDirectory: Directory.systemTemp,
  runner: runner,
  startDispatchMaximumPolls: maximumPolls,
  startDispatchPollInterval: Duration.zero,
);

const _startVoiceCallUi = '''
<hierarchy>
  <node text="" content-desc="Start voice call" clickable="true"
      enabled="true" visible-to-user="true" package="com.mknoon.app"
      bounds="[100,200][300,400]" />
</hierarchy>
''';

const _startingVoiceCallUi = '''
<hierarchy>
  <node text="" content-desc="Starting voice call" clickable="false"
      enabled="false" visible-to-user="true" package="com.mknoon.app"
      bounds="[100,200][300,400]" />
</hierarchy>
''';

const _cancelCallUi = '''
<hierarchy>
  <node text="" content-desc="Cancel call" clickable="true"
      enabled="true" visible-to-user="true" package="com.mknoon.app"
      bounds="[100,200][300,400]" />
</hierarchy>
''';

const _startVoiceCallFailureUi = '''
<hierarchy>
  <node text="Couldn&apos;t start voice call. Please try again."
      content-desc="" clickable="false" enabled="true"
      visible-to-user="true" package="com.mknoon.app"
      bounds="[10,20][600,120]" />
</hierarchy>
''';

final class _FakeDriver implements AndroidProductionAudioCallCampaignDriver {
  _FakeDriver({
    this.failLabel,
    this.mismatchStopBinding = false,
    this.unreleasedDeviceId,
    this.nativeAnswerPackage = 'com.android.systemui',
    this.failFailureArtifactCapture = false,
    this.failRestore = false,
    this.startDispatchStatus =
        AndroidProductionAudioCallStartDispatchStatus.acknowledged,
    this.wakeAuthorityReady = true,
    this.missingRtpDirection,
    this.rtpObservationFalseSamples = 0,
  });

  final String? failLabel;
  final bool mismatchStopBinding;
  final String? unreleasedDeviceId;
  final String nativeAnswerPackage;
  final bool failFailureArtifactCapture;
  final bool failRestore;
  final AndroidProductionAudioCallStartDispatchStatus startDispatchStatus;
  final bool wakeAuthorityReady;
  final String? missingRtpDirection;
  final int rtpObservationFalseSamples;
  final List<String> actions = <String>[];
  int restoreCalls = 0;
  int _parallelClassifications = 0;
  int maximumParallelClassifications = 0;
  int _parallelPreparations = 0;
  int maximumParallelPreparations = 0;
  final List<String> preparedApkDigests = <String>[];
  int _parallelBootstraps = 0;
  int maximumParallelBootstraps = 0;
  int _parallelContacts = 0;
  int maximumParallelContacts = 0;
  final List<String> contactEvents = <String>[];
  int _parallelObservers = 0;
  int maximumParallelObserverOperations = 0;
  int _parallelNativeCleanup = 0;
  int maximumParallelNativeCleanup = 0;
  final List<String> nativeCleanupDevices = <String>[];
  final List<String> readinessContactPeerIds = <String>[];
  final Map<String, int> sampleObservationsByRole = <String, int>{};

  Future<T> _overlap<T>(
    T value,
    void Function(int) setCurrent,
    int Function() current,
    void Function(int) setMaximum,
    int Function() maximum,
  ) async {
    setCurrent(current() + 1);
    setMaximum(current() > maximum() ? current() : maximum());
    await Future<void>.delayed(const Duration(milliseconds: 2));
    setCurrent(current() - 1);
    return value;
  }

  @override
  Future<AndroidProductionAudioCallTargetKind> classifyTarget(
    String deviceId,
  ) => _overlap(
    deviceId.startsWith('emulator-')
        ? AndroidProductionAudioCallTargetKind.emulator
        : AndroidProductionAudioCallTargetKind.physical,
    (value) => _parallelClassifications = value,
    () => _parallelClassifications,
    (value) => maximumParallelClassifications = value,
    () => maximumParallelClassifications,
  );

  @override
  Future<void> verifyRelayReachable(String deviceId) async {
    actions.add('relay:$deviceId');
  }

  @override
  Future<void> captureState() async => actions.add('capture');

  @override
  Future<void> prepareTarget({
    required String deviceId,
    required String expectedApkSha256,
  }) {
    preparedApkDigests.add(expectedApkSha256);
    return _overlap<void>(
      null,
      (value) => _parallelPreparations = value,
      () => _parallelPreparations,
      (value) => maximumParallelPreparations = value,
      () => maximumParallelPreparations,
    );
  }

  @override
  Future<AndroidProductionAudioCallIdentity> bootstrapIdentity({
    required String deviceId,
    required String role,
  }) => _overlap(
    AndroidProductionAudioCallIdentity(
      username: role == androidProductionAudioCallCallerRole
          ? 'Plan399Caller'
          : 'Plan399Callee',
      peerId: 'peer-$role',
      qrPayload: '{"ns":"peer-$role"}',
      mlKemPublicKey: 'mlkem-$role',
    ),
    (value) => _parallelBootstraps = value,
    () => _parallelBootstraps,
    (value) => maximumParallelBootstraps = value,
    () => maximumParallelBootstraps,
  );

  @override
  Future<void> establishContact({
    required String ownerDeviceId,
    required String ownerRole,
    required AndroidProductionAudioCallIdentity contact,
  }) async {
    contactEvents.add('start:$ownerRole');
    await _overlap<void>(
      null,
      (value) => _parallelContacts = value,
      () => _parallelContacts,
      (value) => maximumParallelContacts = value,
      () => maximumParallelContacts,
    );
    contactEvents.add('end:$ownerRole');
  }

  @override
  Future<void> openConversation({
    required String deviceId,
    required String contactUsername,
  }) async => actions.add('open:$deviceId:$contactUsername');

  @override
  Future<Map<String, Object?>> observe({
    required String deviceId,
    required String role,
    required String operation,
    required String runId,
    required String nonce,
    required String profileSha256,
    required String apkSha256,
    String? contactAccountPeerId,
  }) {
    actions.add('observe:$deviceId:$operation');
    if (operation == androidProductionAudioCallReadinessOperation) {
      readinessContactPeerIds.add(contactAccountPeerId!);
    }
    return _overlap(
      _receipt(role: role, operation: operation, nonce: nonce),
      (value) => _parallelObservers = value,
      () => _parallelObservers,
      (value) => maximumParallelObserverOperations = value,
      () => maximumParallelObserverOperations,
    );
  }

  Map<String, Object?> _receipt({
    required String role,
    required String operation,
    required String nonce,
  }) {
    final readiness = operation == androidProductionAudioCallReadinessOperation;
    final emptyObservation =
        operation == androidProductionAudioCallArmOperation || readiness;
    final sampleObservation =
        operation == androidProductionAudioCallSampleOperation
        ? sampleObservationsByRole.update(
            role,
            (value) => value + 1,
            ifAbsent: () => 1,
          )
        : 0;
    final awaitingRtp =
        sampleObservation > 0 &&
        sampleObservation <= rtpObservationFalseSamples;
    return <String, Object?>{
      'schema': androidProductionAudioCallObservationResultSchema,
      'scenario': androidProductionAudioCallScenarioId,
      'buildProfile': androidProductionAudioCallProfileId,
      'role': role,
      'operation': operation,
      'stepId': 'production-call-$role-$operation-run-399',
      'runId': 'run-399',
      'nonce': nonce,
      'profileSha256': _profileSha,
      'apkSha256': _apkSha,
      'callBindingSha256':
          operation == androidProductionAudioCallArmOperation || readiness
          ? null
          : mismatchStopBinding &&
                operation == androidProductionAudioCallStopOperation &&
                role == androidProductionAudioCallCallerRole
          ? '9999999999999999999999999999999999999999999999999999999999999999'
          : role == androidProductionAudioCallCallerRole
          ? 'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd'
          : 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
      'status': readiness
          ? wakeAuthorityReady
                ? 'ready'
                : 'not_ready'
          : operation == androidProductionAudioCallArmOperation
          ? 'armed'
          : operation == androidProductionAudioCallSampleOperation
          ? 'observing'
          : 'complete',
      'success': true,
      'stateSequence': emptyObservation
          ? <String>[]
          : role == androidProductionAudioCallCallerRole
          ? <String>[
              'outgoing',
              'ringing',
              'accepted',
              'connected',
              if (operation == androidProductionAudioCallStopOperation)
                'terminal',
            ]
          : <String>[
              'ringing',
              'accepted',
              'connected',
              if (operation == androidProductionAudioCallStopOperation)
                'terminal',
            ],
      'outgoingObserved':
          !emptyObservation && role == androidProductionAudioCallCallerRole,
      'ringingObserved': !emptyObservation,
      'acceptedObserved': !emptyObservation,
      'connectedObserved': !emptyObservation,
      'terminalObserved': operation == androidProductionAudioCallStopOperation,
      'activeCallSurfaceObserved': !emptyObservation,
      'structuralMediaReadyObserved': !emptyObservation,
      'relayOnlyObserved': !emptyObservation,
      'selectedRelayTransport': emptyObservation ? 'unknown' : 'turn_udp',
      'localAudioEnabledObserved': !emptyObservation,
      'inboundAudioRtpObserved':
          !emptyObservation && !awaitingRtp && missingRtpDirection != 'inbound',
      'outboundAudioRtpObserved':
          !emptyObservation &&
          !awaitingRtp &&
          missingRtpDirection != 'outbound',
      'wakeAuthorityReady': readiness && wakeAuthorityReady,
      'containsPrivateMaterial': false,
    };
  }

  @override
  Future<void> tapSemantic(String deviceId, String label) async {
    actions.add('tap:$deviceId:$label');
    if (label == failLabel) throw StateError('injected $label failure');
  }

  @override
  Future<AndroidProductionAudioCallStartDispatchAcknowledgement>
  dispatchStartVoiceCall(String deviceId) async {
    const label = 'Start voice call';
    actions.add('tap:$deviceId:$label');
    if (label == failLabel) throw StateError('injected $label failure');
    actions.add('dispatch:$deviceId:${startDispatchStatus.name}');
    return AndroidProductionAudioCallStartDispatchAcknowledgement(
      status: startDispatchStatus,
      observedSurfaces: switch (startDispatchStatus) {
        AndroidProductionAudioCallStartDispatchStatus.acknowledged =>
          const <AndroidProductionAudioCallStartDispatchSurface>[
            AndroidProductionAudioCallStartDispatchSurface.starting,
            AndroidProductionAudioCallStartDispatchSurface.cancel,
          ],
        AndroidProductionAudioCallStartDispatchStatus.downstreamRejected =>
          const <AndroidProductionAudioCallStartDispatchSurface>[
            AndroidProductionAudioCallStartDispatchSurface.failure,
          ],
        AndroidProductionAudioCallStartDispatchStatus.downstreamTimedOut =>
          const <AndroidProductionAudioCallStartDispatchSurface>[
            AndroidProductionAudioCallStartDispatchSurface.starting,
          ],
        AndroidProductionAudioCallStartDispatchStatus
            .semanticActionNotDispatched =>
          const <AndroidProductionAudioCallStartDispatchSurface>[],
      },
    );
  }

  @override
  Future<String> tapNativeAnswer(String deviceId) async {
    const label = 'Answer';
    actions.add('tap:$deviceId:$label');
    if (label == failLabel) throw StateError('injected $label failure');
    return nativeAnswerPackage;
  }

  @override
  Future<void> waitForSemantic(String deviceId, String label) async {
    actions.add('wait:$deviceId:$label');
  }

  @override
  Future<void> waitForSemanticAbsent(String deviceId, String label) async {
    actions.add('absent:$deviceId:$label');
  }

  @override
  Future<List<AndroidProductionAudioCallArtifactDigest>> captureArtifacts(
    String stage,
  ) async => <AndroidProductionAudioCallArtifactDigest>[
    for (final role in const <String>[
      androidProductionAudioCallCallerRole,
      androidProductionAudioCallCalleeRole,
    ]) ...<AndroidProductionAudioCallArtifactDigest>[
      AndroidProductionAudioCallArtifactDigest(
        role: role,
        kind: '${stage}UiDump',
        sha256Digest: _apkSha,
        bounded: true,
        redacted: true,
      ),
      AndroidProductionAudioCallArtifactDigest(
        role: role,
        kind: '${stage}Logcat',
        sha256Digest: _apkSha,
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

  @override
  Future<void> captureFailureArtifacts(String stage) async {
    actions.add('failure-artifacts:$stage');
    if (failFailureArtifactCapture) {
      throw StateError('injected failure artifact capture failure');
    }
  }

  @override
  Future<bool> nativeCallReleased(String deviceId) {
    nativeCleanupDevices.add(deviceId);
    return _overlap<bool>(
      deviceId != unreleasedDeviceId,
      (value) => _parallelNativeCleanup = value,
      () => _parallelNativeCleanup,
      (value) => maximumParallelNativeCleanup = value,
      () => maximumParallelNativeCleanup,
    );
  }

  @override
  Future<void> restoreState() async {
    actions.add('restore');
    restoreCalls += 1;
    if (failRestore) {
      throw const AndroidAppStateFailure('injected restoration failure');
    }
  }
}

final class _TimedInvocation {
  const _TimedInvocation(this.arguments, this.timeout);

  final List<String> arguments;
  final Duration timeout;
}

final class _ColdLaunchTimeoutRunner
    implements AndroidHostProcessRunnerWithTimeout {
  final List<List<String>> ordinaryInvocations = <List<String>>[];
  final List<_TimedInvocation> timedInvocations = <_TimedInvocation>[];

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    ordinaryInvocations.add(List<String>.of(arguments));
    return _result(executable, arguments);
  }

  @override
  Future<ProcessResult> runWithTimeout(
    String executable,
    List<String> arguments, {
    required Duration timeout,
  }) async {
    timedInvocations.add(_TimedInvocation(List<String>.of(arguments), timeout));
    return _result(executable, arguments);
  }

  ProcessResult _result(String executable, List<String> arguments) {
    if (executable != 'adb') {
      return ProcessResult(1, 127, '', 'unexpected executable');
    }
    if (arguments.contains('cat') &&
        arguments.contains('app_flutter/intro_e2e_identity.json')) {
      return ProcessResult(
        1,
        0,
        jsonEncode(<String, Object?>{
          'qrPayload': jsonEncode(<String, String>{
            'ns': 'peer-caller',
            'un': 'Plan399Caller',
          }),
          'mlKemPublicKey': 'mlkem-caller',
        }),
        '',
      );
    }
    return ProcessResult(1, 0, '', '');
  }
}

final class _LiveContactSetupRunner
    implements AndroidHostProcessRunnerWithTimeout {
  _LiveContactSetupRunner({
    this.uiNavigation = const <String, Object?>{
      'requestedPeerId': 'peer-callee',
      'opened': true,
    },
  });

  final List<List<String>> ordinaryInvocations = <List<String>>[];
  final List<_TimedInvocation> timedInvocations = <_TimedInvocation>[];
  String? _stepId;
  Map<String, Object?> stagedConfig = const <String, Object?>{};
  var configStagedAt = -1;
  var foregroundedAt = -1;
  var matchingResultReads = 0;
  final Map<String, Object?> uiNavigation;

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    ordinaryInvocations.add(List<String>.of(arguments));
    return _result(executable, arguments, ordinaryInvocations.length - 1);
  }

  @override
  Future<ProcessResult> runWithTimeout(
    String executable,
    List<String> arguments, {
    required Duration timeout,
  }) async {
    timedInvocations.add(_TimedInvocation(List<String>.of(arguments), timeout));
    return _result(executable, arguments, ordinaryInvocations.length);
  }

  ProcessResult _result(
    String executable,
    List<String> arguments,
    int invocationIndex,
  ) {
    if (executable != 'adb') {
      return ProcessResult(1, 127, '', 'unexpected executable');
    }
    if (arguments.length >= 5 && arguments[2] == 'push') {
      final decoded = jsonDecode(File(arguments[3]).readAsStringSync());
      if (decoded is Map && decoded['add_contacts'] is List) {
        _stepId = '${decoded['stepId']}';
        stagedConfig = decoded.map<String, Object?>(
          (key, value) => MapEntry('$key', value),
        );
        configStagedAt = invocationIndex;
      }
      return ProcessResult(1, 0, '1 file pushed', '');
    }
    if (arguments.length >= 5 &&
        arguments[2] == 'shell' &&
        arguments[3] == 'am' &&
        arguments[4] == 'start') {
      foregroundedAt = invocationIndex;
      return ProcessResult(1, 0, 'Status: ok\n', '');
    }
    if (arguments.contains('cat') &&
        arguments.contains('app_flutter/intro_e2e_result.json')) {
      matchingResultReads += 1;
      return ProcessResult(
        1,
        0,
        jsonEncode(<String, Object?>{
          'stepId': _stepId,
          'status': 'complete',
          'success': true,
          'snapshot': <String, Object?>{
            'contacts': <Object?>[
              <String, Object?>{'peerId': 'peer-callee'},
            ],
          },
          'uiNavigation': uiNavigation,
        }),
        '',
      );
    }
    return ProcessResult(1, 0, '', '');
  }
}

final class _ConversationForegroundRunner
    implements AndroidHostProcessRunnerWithTimeout {
  final List<List<String>> invocations = <List<String>>[];
  final List<_TimedInvocation> timedInvocations = <_TimedInvocation>[];
  var tapCount = 0;

  @override
  Future<ProcessResult> runWithTimeout(
    String executable,
    List<String> arguments, {
    required Duration timeout,
  }) async {
    timedInvocations.add(_TimedInvocation(List<String>.of(arguments), timeout));
    return _result(executable, arguments);
  }

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    invocations.add(List<String>.of(arguments));
    return _result(executable, arguments);
  }

  ProcessResult _result(String executable, List<String> arguments) {
    if (executable != 'adb') {
      return ProcessResult(1, 127, '', 'unexpected executable');
    }
    if (arguments.length >= 5 &&
        arguments[2] == 'shell' &&
        arguments[3] == 'am' &&
        arguments[4] == 'start') {
      return ProcessResult(1, 0, 'Status: ok\n', '');
    }
    if (arguments.length == 6 &&
        arguments[2] == 'shell' &&
        arguments[3] == 'uiautomator' &&
        arguments[4] == 'dump') {
      return ProcessResult(1, 0, 'UI hierchary dumped to file\n', '');
    }
    if (arguments.length == 5 &&
        arguments[2] == 'exec-out' &&
        arguments[3] == 'cat') {
      return ProcessResult(1, 0, _startVoiceCallUi, '');
    }
    if (arguments.length >= 5 &&
        arguments[2] == 'shell' &&
        arguments[3] == 'rm') {
      return ProcessResult(1, 0, '', '');
    }
    if (arguments.length == 7 &&
        arguments[2] == 'shell' &&
        arguments[3] == 'input' &&
        arguments[4] == 'tap') {
      tapCount += 1;
      return ProcessResult(1, 0, '', '');
    }
    return ProcessResult(1, 2, '', 'unexpected adb arguments');
  }
}

final class _StartDispatchRunner implements AndroidHostProcessRunner {
  _StartDispatchRunner({required this.postTapUi});

  final List<String> postTapUi;
  final List<List<String>> invocations = <List<String>>[];
  var tapCount = 0;
  var _postTapReads = 0;

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    invocations.add(List<String>.of(arguments));
    if (executable != 'adb') {
      return ProcessResult(1, 127, '', 'unexpected executable');
    }
    if (arguments.length == 6 &&
        arguments[2] == 'shell' &&
        arguments[3] == 'uiautomator' &&
        arguments[4] == 'dump') {
      return ProcessResult(1, 0, 'UI hierchary dumped to file\n', '');
    }
    if (arguments.length == 5 &&
        arguments[2] == 'exec-out' &&
        arguments[3] == 'cat') {
      if (tapCount == 0) return ProcessResult(1, 0, _startVoiceCallUi, '');
      final index = _postTapReads < postTapUi.length
          ? _postTapReads
          : postTapUi.length - 1;
      _postTapReads += 1;
      return ProcessResult(1, 0, postTapUi[index], '');
    }
    if (arguments.length >= 5 &&
        arguments[2] == 'shell' &&
        arguments[3] == 'rm') {
      return ProcessResult(1, 0, '', '');
    }
    if (arguments.length == 7 &&
        arguments[2] == 'shell' &&
        arguments[3] == 'input' &&
        arguments[4] == 'tap') {
      tapCount += 1;
      return ProcessResult(1, 0, '', '');
    }
    return ProcessResult(1, 2, '', 'unexpected adb arguments');
  }
}

final class _AppPidLogcatRunner implements AndroidHostProcessRunner {
  final List<List<String>> invocations = <List<String>>[];

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    invocations.add(List<String>.of(arguments));
    if (executable != 'adb') {
      return ProcessResult(1, 127, '', 'unexpected executable');
    }
    if (arguments.length == 6 &&
        arguments[2] == 'shell' &&
        arguments[3] == 'pidof' &&
        arguments[4] == '-s') {
      return ProcessResult(1, 0, '4242\n', '');
    }
    if (arguments.length == 9 &&
        arguments[2] == 'logcat' &&
        arguments[4] == '--pid=4242') {
      return ProcessResult(1, 0, '''
safe production call marker
a=ice-pwd:rawPassword399
a=candidate:1 1 UDP 1 192.168.0.44 52705 typ host
''', '');
    }
    return ProcessResult(1, 2, '', 'unexpected adb arguments');
  }
}

final class _NotificationShadeAnswerRunner implements AndroidHostProcessRunner {
  final List<List<String>> invocations = <List<String>>[];
  bool _notificationShadeExpanded = false;

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    invocations.add(List<String>.of(arguments));
    if (executable != 'adb') {
      return ProcessResult(1, 127, '', 'unexpected executable');
    }
    if (arguments.length == 6 &&
        arguments[2] == 'shell' &&
        arguments[3] == 'pm' &&
        arguments[4] == 'path') {
      return arguments[5] == 'com.android.systemui'
          ? ProcessResult(
              1,
              0,
              'package:/system/priv-app/SystemUI/SystemUI.apk\n',
              '',
            )
          : ProcessResult(1, 1, '', '');
    }
    if (arguments.length == 6 &&
        arguments[2] == 'shell' &&
        arguments[3] == 'cmd' &&
        arguments[4] == 'statusbar' &&
        arguments[5] == 'expand-notifications') {
      _notificationShadeExpanded = true;
      return ProcessResult(1, 0, '', '');
    }
    if (arguments.length == 6 &&
        arguments[2] == 'shell' &&
        arguments[3] == 'cmd' &&
        arguments[4] == 'statusbar' &&
        arguments[5] == 'collapse') {
      return ProcessResult(1, 0, '', '');
    }
    if (arguments.length == 6 &&
        arguments[2] == 'shell' &&
        arguments[3] == 'uiautomator' &&
        arguments[4] == 'dump') {
      return ProcessResult(1, 0, 'UI hierchary dumped to file\n', '');
    }
    if (arguments.length == 5 &&
        arguments[2] == 'exec-out' &&
        arguments[3] == 'cat') {
      if (!_notificationShadeExpanded) {
        return ProcessResult(1, 1, '', 'notification shade not expanded');
      }
      return ProcessResult(1, 0, '''
<hierarchy>
  <node text="Answer" content-desc="" clickable="true" enabled="true"
      visible-to-user="true" package="com.android.systemui"
      bounds="[10,20][110,120]" />
</hierarchy>
''', '');
    }
    if (arguments.length >= 5 &&
        arguments[2] == 'shell' &&
        arguments[3] == 'rm') {
      return ProcessResult(1, 0, '', '');
    }
    if (arguments.length == 7 &&
        arguments[2] == 'shell' &&
        arguments[3] == 'input' &&
        arguments[4] == 'tap') {
      return ProcessResult(1, 0, '', '');
    }
    return ProcessResult(1, 2, '', 'unexpected adb arguments');
  }
}
