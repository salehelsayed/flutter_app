import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scripts/production_audio_call_local_fixture.dart';

const _shaA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _shaB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _shaC =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
const _shaD =
    'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
const _coturnDigest =
    'sha256:aa68aab64a3b929d57fc2924c98ea447bf996cf8dade2508e7b71eaf23f1f14e';
const _turnAuthoritySha =
    '8bc3322ed74bd971a9b544be19bec83e88ae4e80ca10ea786164e573f73bc729';

void main() {
  test('fixture host resolver accepts only an explicit private IPv4', () async {
    await expectLater(
      resolveProductionAudioCallLocalFixtureHostIp(const <String, String>{
        'PLAN399_FIXTURE_HOST_IP': '192.168.0.60',
      }),
      completion('192.168.0.60'),
    );
    await expectLater(
      resolveProductionAudioCallLocalFixtureHostIp(const <String, String>{
        'PLAN399_FIXTURE_HOST_IP': '203.0.113.9',
      }),
      throwsFormatException,
    );
    await expectLater(
      resolveProductionAudioCallLocalFixtureHostIp(const <String, String>{
        'PLAN399_FIXTURE_HOST_IP': '10.-1.0.1',
      }),
      throwsFormatException,
    );
  });

  test('strict readiness accepts one private combined fixture lease', () {
    final tempRoot = Directory.systemTemp.absolute.path;
    final parsed = validateProductionAudioCallLocalFixtureReadiness(
      _readiness('$tempRoot/plan399-fixture'),
      expectedHost: '192.168.0.60',
    );

    expect(parsed.multiaddr, contains('/ip4/192.168.0.60/tcp/'));
    expect(parsed.relayPort, 40123);
    expect(parsed.turnPort, 40125);
    expect(parsed.turnTransport, 'udp');
    expect(parsed.coturnVersion, '4.17.2-r0');
  });

  test('readiness rejects unknown fields and external authorities', () {
    final root = '${Directory.systemTemp.absolute.path}/plan399-fixture';
    expect(
      () => validateProductionAudioCallLocalFixtureReadiness(<String, Object?>{
        ..._readiness(root),
        'unexpected': true,
      }, expectedHost: '192.168.0.60'),
      throwsFormatException,
    );
    final remote = _readiness(root)..['turnHost'] = '203.0.113.4';
    expect(
      () => validateProductionAudioCallLocalFixtureReadiness(
        remote,
        expectedHost: '192.168.0.60',
      ),
      throwsFormatException,
    );
  });

  test('oracle DTO accepts only complete bidirectional relay proof', () {
    final result = validateProductionAudioCallOracleResult(
      _oracleResult(),
      expectedTransport: 'udp',
      expectedCoturnImage: 'coturn/coturn:4.17.2-r0',
      expectedCoturnDigest: _coturnDigest,
      expectedTurnAuthoritySha256: _turnAuthoritySha,
      expectedFixtureInstanceSha256: _shaD,
    );

    expect(result.aToB.passed, isTrue);
    expect(result.bToA.passed, isTrue);
    expect(result.peerARoute.passed, isTrue);
    expect(result.peerBRoute.passed, isTrue);
    expect(result.toSanitizedJson(), isNot(contains('turnUrl')));

    final oneWay = _oracleResult();
    (oneWay['b_to_a']! as Map<String, Object?>)['payload_hash_exact'] = false;
    expect(
      () => validateProductionAudioCallOracleResult(
        oneWay,
        expectedTransport: 'udp',
        expectedCoturnImage: 'coturn/coturn:4.17.2-r0',
        expectedCoturnDigest: _coturnDigest,
        expectedTurnAuthoritySha256: _turnAuthoritySha,
        expectedFixtureInstanceSha256: _shaD,
      ),
      throwsFormatException,
    );

    final replayed = _oracleResult()..['turn_authority_sha256'] = _shaD;
    expect(
      () => validateProductionAudioCallOracleResult(
        replayed,
        expectedTransport: 'udp',
        expectedCoturnImage: 'coturn/coturn:4.17.2-r0',
        expectedCoturnDigest: _coturnDigest,
        expectedTurnAuthoritySha256: _turnAuthoritySha,
        expectedFixtureInstanceSha256: _shaD,
      ),
      throwsFormatException,
    );

    final sameUrlOlderInstance = _oracleResult()
      ..['fixture_instance_sha256'] = _shaC;
    expect(
      () => validateProductionAudioCallOracleResult(
        sameUrlOlderInstance,
        expectedTransport: 'udp',
        expectedCoturnImage: 'coturn/coturn:4.17.2-r0',
        expectedCoturnDigest: _coturnDigest,
        expectedTurnAuthoritySha256: _turnAuthoritySha,
        expectedFixtureInstanceSha256: _shaD,
      ),
      throwsFormatException,
    );
  });

  test(
    'lease pins both Go children, probes both targets, and erases temp files',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'plan399-dart-fixture-contract-',
      );
      final fixtureRoot = Directory('${root.path}/fixture-private');
      final marker = File('${root.path}/stop-marker');
      final childLog = File('${root.path}/child.log');
      final adbLog = File('${root.path}/adb.log');
      final goShim = File('${root.path}/go');
      final adbShim = File('${root.path}/adb');
      final stopShim = File('${root.path}/stop');
      await goShim.writeAsString(_goShim);
      await adbShim.writeAsString(_adbShim);
      await stopShim.writeAsString(_stopShim);
      await Process.run('chmod', <String>[
        '+x',
        goShim.path,
        adbShim.path,
        stopShim.path,
      ]);

      ProductionAudioCallLocalFixtureLease? lease;
      try {
        lease = await ProductionAudioCallLocalFixtureLease.start(
          goExecutable: goShim.path,
          hostIp: '192.168.0.60',
          environment: <String, String>{
            ...Platform.environment,
            'GOTOOLCHAIN': 'wrong-toolchain',
            'TURN_CREDENTIAL_PRIMARY_SECRET_B64': 'must-not-propagate',
            'PLAN399_TEST_FIXTURE_ROOT': fixtureRoot.path,
            'PLAN399_TEST_STOP_MARKER': marker.path,
            'PLAN399_TEST_CHILD_LOG': childLog.path,
            'PLAN399_TEST_ADB_LOG': adbLog.path,
            'PLAN399_FIXTURE_STOP_EXECUTABLE': stopShim.path,
          },
        );
        await lease.verifyAndroidPairAndReachability(
          adbExecutable: adbShim.path,
          devices: const <String>['pixel-usb', 'emulator-5554'],
        );
        final result = await lease.runAudioOracle(goExecutable: goShim.path);
        expect(result.aToB.passed && result.bToA.passed, isTrue);
        expect(
          await File('${fixtureRoot.path}/oracle-credentials.json').exists(),
          isFalse,
        );
        await lease.stop();
        lease = null;

        final childCalls = await childLog.readAsLines();
        expect(childCalls, hasLength(2));
        expect(
          childCalls.every((line) => line.contains('toolchain=go1.25.0')),
          isTrue,
        );
        expect(childCalls.join('\n'), isNot(contains('must-not-propagate')));
        final adbCalls = await adbLog.readAsLines();
        expect(adbCalls, hasLength(6));
        expect(adbCalls.where((line) => line.contains('toybox nc')).length, 4);
        expect(await fixtureRoot.exists(), isFalse);
      } finally {
        if (lease != null) await lease.stop();
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'real combined fixture forwards the known Opus payload both ways',
    () async {
      final hostIp = Platform.environment['PLAN399_FIXTURE_HOST_IP']!;
      final lease = await ProductionAudioCallLocalFixtureLease.start(
        goExecutable: 'go',
        hostIp: hostIp,
        environment: Platform.environment,
      );
      try {
        final result = await lease.runAudioOracle();
        expect(result.aToB.passed, isTrue);
        expect(result.bToA.passed, isTrue);
        expect(result.peerARoute.passed, isTrue);
        expect(result.peerBRoute.passed, isTrue);
      } finally {
        await lease.stop();
      }
    },
    skip:
        Platform.environment['PLAN399_RUN_REAL_FIXTURE'] != '1' ||
        Platform.environment['PLAN399_FIXTURE_HOST_IP'] == null,
  );
}

Map<String, Object?> _readiness(String root) => <String, Object?>{
  'schema': 'mknoon.plan399.production-audio-call-fixture.v1',
  'multiaddr': '/ip4/192.168.0.60/tcp/40123/p2p/12D3KooWFixture',
  'probeUrl':
      'http://192.168.0.60:40124/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
  'fixtureIdentitySha256': _shaA,
  'backend': 'redis',
  'ephemeral': true,
  'ackCustodyAdmissionEnabled': true,
  'mediaCustodyAdmissionEnabled': true,
  'relayVersion': 'relay-server v0.1.0+plan399-fixture',
  'relayBinarySha256': _shaB,
  'turnHost': '192.168.0.60',
  'turnPort': 40125,
  'turnTransport': 'udp',
  'turnUrl': 'turn:192.168.0.60:40125?transport=udp',
  'coturnImage': 'coturn/coturn:4.17.2-r0',
  'coturnDigest': _coturnDigest,
  'coturnVersion': '4.17.2-r0',
  'coturnLockSha256': _shaC,
  'coturnContainerIdentitySha256': _shaD,
  'oracleCredentialsFile': '$root/oracle-credentials.json',
  'oracleResultFile': '$root/oracle-result.json',
};

Map<String, Object?> _oracleResult() => <String, Object?>{
  'schema': 'mknoon.call_audio_oracle.result.v1',
  'version': 1,
  'passed': true,
  'pion_version': 'v4.2.19',
  'fixture_sha256': _shaA,
  'turn_authority_sha256': _turnAuthoritySha,
  'fixture_instance_sha256': _shaD,
  'coturn': <String, Object?>{
    'image': 'coturn/coturn:4.17.2-r0',
    'digest': _coturnDigest,
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

const _goShim = r'''#!/usr/bin/env bash
set -euo pipefail
printf 'kind=%s toolchain=%s secret=%s\n' \
  "${CALL_AUDIO_ORACLE_RESULT_FILE:+oracle}" \
  "${GOTOOLCHAIN-}" \
  "${TURN_CREDENTIAL_PRIMARY_SECRET_B64-}" >>"${PLAN399_TEST_CHILD_LOG:?}"
if [ -n "${CALL_AUDIO_ORACLE_RESULT_FILE-}" ]; then
  umask 077
  printf '%s\n' '{"schema":"mknoon.call_audio_oracle.result.v1","version":1,"passed":true,"pion_version":"v4.2.19","fixture_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","turn_authority_sha256":"8bc3322ed74bd971a9b544be19bec83e88ae4e80ca10ea786164e573f73bc729","fixture_instance_sha256":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","coturn":{"image":"coturn/coturn:4.17.2-r0","digest":"sha256:aa68aab64a3b929d57fc2924c98ea447bf996cf8dade2508e7b71eaf23f1f14e"},"expected_transport":"udp","a_to_b":{"codec_valid":true,"payload_count_exact":true,"payload_order_exact":true,"payload_hash_exact":true},"b_to_a":{"codec_valid":true,"payload_count_exact":true,"payload_order_exact":true,"payload_hash_exact":true},"peer_a_route":{"relay_selected":true,"transport_match":true},"peer_b_route":{"relay_selected":true,"transport_match":true},"cleanup_complete":true}' >"${CALL_AUDIO_ORACLE_RESULT_FILE:?}"
  exit 0
fi
mkdir -p "${PLAN399_TEST_FIXTURE_ROOT:?}"
chmod 700 "${PLAN399_TEST_FIXTURE_ROOT:?}"
umask 077
printf '{}\n' >"${PLAN399_TEST_FIXTURE_ROOT:?}/oracle-credentials.json"
printf '%s\n' "MKNOON_PRODUCTION_AUDIO_CALL_FIXTURE_READY={\"schema\":\"mknoon.plan399.production-audio-call-fixture.v1\",\"multiaddr\":\"/ip4/192.168.0.60/tcp/40123/p2p/12D3KooWFixture\",\"probeUrl\":\"http://192.168.0.60:40124/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"fixtureIdentitySha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"backend\":\"redis\",\"ephemeral\":true,\"ackCustodyAdmissionEnabled\":true,\"mediaCustodyAdmissionEnabled\":true,\"relayVersion\":\"relay-server v0.1.0+plan399-fixture\",\"relayBinarySha256\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"turnHost\":\"192.168.0.60\",\"turnPort\":40125,\"turnTransport\":\"udp\",\"turnUrl\":\"turn:192.168.0.60:40125?transport=udp\",\"coturnImage\":\"coturn/coturn:4.17.2-r0\",\"coturnDigest\":\"sha256:aa68aab64a3b929d57fc2924c98ea447bf996cf8dade2508e7b71eaf23f1f14e\",\"coturnVersion\":\"4.17.2-r0\",\"coturnLockSha256\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"coturnContainerIdentitySha256\":\"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"oracleCredentialsFile\":\"${PLAN399_TEST_FIXTURE_ROOT:?}/oracle-credentials.json\",\"oracleResultFile\":\"${PLAN399_TEST_FIXTURE_ROOT:?}/oracle-result.json\"}"
while [ ! -f "${PLAN399_TEST_STOP_MARKER:?}" ]; do sleep 0.01; done
rm -rf "${PLAN399_TEST_FIXTURE_ROOT:?}"
''';

const _adbShim = r'''#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${PLAN399_TEST_ADB_LOG:?}"
device=""
if [ "${1-}" = -s ]; then device="${2-}"; shift 2; fi
if [ "$*" = 'shell getprop ro.kernel.qemu' ]; then
  if [ "$device" = emulator-5554 ]; then printf '1\n'; else printf '0\n'; fi
fi
''';

const _stopShim = r'''#!/usr/bin/env bash
set -euo pipefail
[ "$#" -eq 1 ]
touch "${PLAN399_TEST_STOP_MARKER:?}"
''';
