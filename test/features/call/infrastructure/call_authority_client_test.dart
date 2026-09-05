import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/call/infrastructure/call_authority_client.dart';
import 'package:flutter_test/flutter_test.dart';

final class _AuthorityBridge implements Bridge {
  final List<Map<String, dynamic>> requests = <Map<String, dynamic>>[];
  final Map<String, Map<String, Object?>> responses =
      <String, Map<String, Object?>>{};
  Future<String>? pendingResponse;

  @override
  bool get isInitialized => true;

  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message) as Map<String, dynamic>;
    requests.add(request);
    final pending = pendingResponse;
    if (pending != null) return pending;
    final command = request['cmd'] as String;
    if (command == 'payload.sign') {
      return jsonEncode(const <String, Object?>{
        'ok': true,
        'signature': 'c2lnbmF0dXJl',
      });
    }
    if (command == 'payload.verify') {
      return jsonEncode(const <String, Object?>{'ok': true, 'valid': true});
    }
    return jsonEncode(
      responses[command] ?? const <String, Object?>{'ok': true},
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CallEndpointRecord _record() => const CallEndpointRecord(
  accountPeerId: 'contact-account',
  devicePeerId: 'contact-device',
  capabilities: <String>{'voice_call_v1'},
  platform: CallEndpointPlatform.android,
  expiresAtMs: 10_000,
  preferenceEpoch: 4,
  deviceKeyEpoch: 9,
  routingHandle: '0123456789abcdef0123456789abcdef',
);

const _relayCanonicalRecord =
    '{"schema":"mknoon.call_endpoint_set.v1","version":1,'
    '"accountPeerId":"contact-account","devicePeerId":"contact-device",'
    '"capabilities":["voice_call_v1"],"platform":"android",'
    '"expiresAtMs":10000,"preferenceEpoch":4,"deviceKeyEpoch":9,'
    '"routingHandle":"0123456789abcdef0123456789abcdef"}';

void main() {
  late _AuthorityBridge bridge;
  late BridgeCallAuthorityClient client;

  setUp(() {
    bridge = _AuthorityBridge();
    client = BridgeCallAuthorityClient(bridge: bridge);
  });

  test('matches relay canonical endpoint JSON byte order exactly', () {
    final record = CallEndpointRecord(
      accountPeerId: 'contact-account',
      devicePeerId: 'contact-device',
      capabilities: <String>{'voice_call_v1', 'audio_route_v1'},
      platform: CallEndpointPlatform.android,
      expiresAtMs: 10_000,
      preferenceEpoch: 4,
      deviceKeyEpoch: 9,
      routingHandle: '0123456789abcdef0123456789abcdef',
    );

    expect(
      record.canonicalRecordJson,
      '{"schema":"mknoon.call_endpoint_set.v1","version":1,'
      '"accountPeerId":"contact-account","devicePeerId":"contact-device",'
      '"capabilities":["audio_route_v1","voice_call_v1"],'
      '"platform":"android","expiresAtMs":10000,"preferenceEpoch":4,'
      '"deviceKeyEpoch":9,'
      '"routingHandle":"0123456789abcdef0123456789abcdef"}',
    );
  });

  test(
    'signs canonical endpoint bytes and publishes exact endpoint action',
    () async {
      final signed = await client.signEndpoint(
        record: _record(),
        senderSigningPrivateKey: 'private-key',
      );
      bridge.responses['call_endpoint_set_v1'] = const <String, Object?>{
        'ok': true,
      };

      expect(await client.setEndpoint(signed), isTrue);

      expect(bridge.requests[0]['cmd'], 'payload.sign');
      final signPayload = bridge.requests[0]['payload'] as Map<String, dynamic>;
      expect(signPayload['data'], signed.canonicalRecordJson);
      expect(bridge.requests[1]['cmd'], 'call_endpoint_set_v1');
      final setPayload = bridge.requests[1]['payload'] as Map<String, dynamic>;
      expect(setPayload.keys.toSet(), <String>{
        'accountPeerId',
        'devicePeerId',
        'capabilities',
        'platform',
        'expiresAtMs',
        'preferenceEpoch',
        'deviceKeyEpoch',
        'routingHandle',
        'signature',
      });
    },
  );

  test(
    'gets signed endpoint with relay canonical bytes for Dart verification',
    () async {
      bridge.responses['call_endpoint_get_v1'] = <String, Object?>{
        'ok': true,
        'found': true,
        'canonicalRecord': base64Encode(utf8.encode(_relayCanonicalRecord)),
        'endpoint': <String, Object?>{
          ..._record().toCanonicalMap(),
          'signature': 'c2lnbmF0dXJl',
        },
      };

      final endpoint = await client.getEndpoint('contact-account');

      expect(endpoint, isNotNull);
      expect(endpoint!.record.devicePeerId, 'contact-device');
      expect(endpoint.canonicalRecordJson, _relayCanonicalRecord);
      expect(
        await client.verifyEndpoint(
          endpoint,
          trustedDeviceSigningPublicKey: 'trusted-device-key',
        ),
        isTrue,
      );
      expect(
        bridge.requests.map((request) => request['cmd']),
        containsAllInOrder(<String>['call_endpoint_get_v1', 'payload.verify']),
      );
    },
  );

  test('uses distinct endpoint, wake, and token revoke/set actions', () async {
    for (final command in <String>[
      'call_endpoint_revoke_v1',
      'call_wake_handle_set_v1',
      'call_wake_handle_revoke_v1',
      'call_token_set_v1',
      'call_token_revoke_v1',
    ]) {
      bridge.responses[command] = <String, Object?>{
        'ok': true,
        if (command.contains('revoke')) 'revoked': true,
        if (command == 'call_token_set_v1') 'generation': 7,
        if (command == 'call_token_set_v1') 'refreshEpoch': 4,
      };
    }

    await client.revokeEndpoint(
      accountPeerId: 'contact-account',
      preferenceEpoch: 5,
    );
    await client.setWakeHandle(
      const CallWakeHandleRecord(
        authorizedSenderPeerId: 'sender-peer',
        wakeHandle: 'abcdef0123456789abcdef0123456789',
        expiresAtMs: 10_000,
      ),
    );
    await client.revokeWakeHandle(authorizedSenderPeerId: 'sender-peer');
    await client.setToken(
      CallTokenRecord(
        kind: CallTokenKind.standardCall,
        platform: CallEndpointPlatform.android,
        token: 'standard-token',
        expiresAtMs: 10_000,
      ),
    );
    await client.setToken(
      CallTokenRecord(
        kind: CallTokenKind.iosVoip,
        platform: CallEndpointPlatform.ios,
        token: 'voip-token',
        expiresAtMs: 10_000,
        environment: 'sandbox',
        topic: 'com.mknoon.app.voip',
        capabilityVersion: 1,
        refreshEpoch: 4,
      ),
    );
    await client.revokeToken(CallTokenKind.standardCall);
    await client.revokeToken(CallTokenKind.iosVoip, refreshEpoch: 4);

    final commands = bridge.requests.map((request) => request['cmd']).toList();
    expect(commands, <Object?>[
      'call_endpoint_revoke_v1',
      'call_wake_handle_set_v1',
      'call_wake_handle_revoke_v1',
      'call_token_set_v1',
      'call_token_set_v1',
      'call_token_revoke_v1',
      'call_token_revoke_v1',
    ]);
    final tokenPayloads = bridge.requests
        .where((request) => request['cmd'] == 'call_token_set_v1')
        .map((request) => request['payload'] as Map<String, dynamic>)
        .toList();
    expect(tokenPayloads[0]['tokenKind'], 'standard_call');
    expect(tokenPayloads[1]['tokenKind'], 'ios_voip');
    expect(tokenPayloads[0].containsKey('environment'), isFalse);
    expect(tokenPayloads[1], containsPair('environment', 'sandbox'));
    expect(tokenPayloads[1], containsPair('topic', 'com.mknoon.app.voip'));
    expect(tokenPayloads[1], containsPair('capabilityVersion', 1));
    expect(tokenPayloads[1], containsPair('refreshEpoch', 4));
    final revokePayloads = bridge.requests
        .where((request) => request['cmd'] == 'call_token_revoke_v1')
        .map((request) => request['payload'] as Map<String, dynamic>)
        .toList();
    expect(revokePayloads[0], <String, Object?>{'tokenKind': 'standard_call'});
    expect(revokePayloads[1], <String, Object?>{
      'tokenKind': 'ios_voip',
      'expectedRefreshEpoch': 4,
    });
  });

  test(
    'forbids cross-platform token-kind substitution and desktop endpoints',
    () {
      expect(
        () => CallTokenRecord(
          kind: CallTokenKind.iosVoip,
          platform: CallEndpointPlatform.android,
          token: 'wrong-token',
          expiresAtMs: 10_000,
        ),
        throwsArgumentError,
      );
      expect(
        () => CallTokenRecord(
          kind: CallTokenKind.iosVoip,
          platform: CallEndpointPlatform.ios,
          token: 'voip-token',
          expiresAtMs: 10_000,
        ),
        throwsArgumentError,
      );
      expect(
        () => CallTokenRecord(
          kind: CallTokenKind.standardCall,
          platform: CallEndpointPlatform.ios,
          token: 'wrong-token',
          expiresAtMs: 10_000,
        ),
        throwsArgumentError,
      );
      expect(CallEndpointPlatform.values, <CallEndpointPlatform>[
        CallEndpointPlatform.android,
        CallEndpointPlatform.ios,
      ]);
    },
  );

  test('bounds an unresponsive native authority bridge', () async {
    bridge.pendingResponse = Completer<String>().future;
    client = BridgeCallAuthorityClient(
      bridge: bridge,
      requestTimeout: const Duration(milliseconds: 1),
    );

    await expectLater(
      client.getEndpoint('contact-account'),
      throwsA(
        isA<CallAuthorityException>().having(
          (error) => error.code,
          'code',
          CallAuthorityErrorCode.bridgeFailure,
        ),
      ),
    );
  });

  test('reports only safe operation and bridge error code', () async {
    final diagnostics = <Map<String, dynamic>>[];
    debugSetFlowEventSink(diagnostics.add);
    addTearDown(() => debugSetFlowEventSink(null));
    bridge.responses['call_wake_handle_set_v1'] = const <String, Object?>{
      'ok': false,
      'errorCode': 'INVALID_INPUT',
      'errorMessage': 'must not be emitted',
    };

    await expectLater(
      client.setWakeHandle(
        const CallWakeHandleRecord(
          authorizedSenderPeerId: 'sender-peer',
          wakeHandle: 'abcdef0123456789abcdef0123456789',
          expiresAtMs: 10_000,
        ),
      ),
      throwsA(isA<CallAuthorityException>()),
    );

    final failure = diagnostics.singleWhere(
      (event) => event['event'] == 'CALL_AUTHORITY_BRIDGE_FAILURE',
    );
    expect(failure['details'], <String, Object?>{
      'operation': 'call_wake_handle_set_v1',
      'code': 'INVALID_INPUT',
    });
  });

  test('surfaces the safe relay error code on a bridge failure', () async {
    bridge.responses['call_token_set_v1'] = const <String, Object?>{
      'ok': false,
      'errorCode': 'CALL_STALE_EPOCH',
      'errorMessage': 'must not be emitted',
    };

    await expectLater(
      client.publishToken(_iosVoipToken()),
      throwsA(
        isA<CallAuthorityException>()
            .having(
              (error) => error.code,
              'code',
              CallAuthorityErrorCode.bridgeFailure,
            )
            .having(
              (error) => error.relayErrorCode,
              'relayErrorCode',
              'CALL_STALE_EPOCH',
            )
            .having((error) => error.isStaleEpoch, 'isStaleEpoch', isTrue)
            .having(
              (error) => '$error',
              'toString',
              'Call authority request failed: bridgeFailure',
            ),
      ),
    );

    bridge.responses['call_token_set_v1'] = const <String, Object?>{
      'ok': false,
      'errorCode': 'not a safe code!',
    };
    await expectLater(
      client.publishToken(_iosVoipToken()),
      throwsA(
        isA<CallAuthorityException>()
            .having((error) => error.relayErrorCode, 'relayErrorCode', isNull)
            .having((error) => error.isStaleEpoch, 'isStaleEpoch', isFalse),
      ),
    );
  });

  test('fails closed on malformed iOS token authority metadata', () async {
    bridge.responses['call_token_set_v1'] = const <String, Object?>{
      'ok': true,
      'generation': 1,
      'refreshEpoch': 8,
    };
    final record = CallTokenRecord(
      kind: CallTokenKind.iosVoip,
      platform: CallEndpointPlatform.ios,
      token: 'voip-token',
      expiresAtMs: 10_000,
      environment: 'production',
      topic: 'com.mknoon.app.voip',
      capabilityVersion: 1,
      refreshEpoch: 9,
    );

    await expectLater(
      client.publishToken(record),
      throwsA(
        isA<CallAuthorityException>().having(
          (error) => error.code,
          'code',
          CallAuthorityErrorCode.malformedResponse,
        ),
      ),
    );
    await expectLater(
      client.revokeToken(CallTokenKind.iosVoip),
      throwsA(
        isA<CallAuthorityException>().having(
          (error) => error.code,
          'code',
          CallAuthorityErrorCode.invalidRequest,
        ),
      ),
    );
  });

  test('strictly rejects malformed token revoke acknowledgements', () async {
    for (final response in <Map<String, Object?>>[
      const <String, Object?>{'ok': true},
      const <String, Object?>{'ok': true, 'revoked': 'true'},
    ]) {
      bridge.responses['call_token_revoke_v1'] = response;
      await expectLater(
        client.revokeToken(CallTokenKind.iosVoip, refreshEpoch: 9),
        throwsA(
          isA<CallAuthorityException>().having(
            (error) => error.code,
            'code',
            CallAuthorityErrorCode.malformedResponse,
          ),
        ),
      );
    }

    bridge.responses['call_token_revoke_v1'] = const <String, Object?>{
      'ok': true,
      'revoked': false,
    };
    expect(
      await client.revokeToken(CallTokenKind.iosVoip, refreshEpoch: 9),
      isFalse,
    );
  });
}

CallTokenRecord _iosVoipToken() => CallTokenRecord(
  kind: CallTokenKind.iosVoip,
  platform: CallEndpointPlatform.ios,
  token: List<String>.filled(64, 'a').join(),
  expiresAtMs: 10_000,
  environment: 'sandbox',
  topic: 'com.mknoon.app.voip',
  capabilityVersion: 1,
  refreshEpoch: 8,
);
