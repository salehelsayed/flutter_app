import 'dart:io';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/call/infrastructure/call_authority_client.dart';
import 'package:flutter_app/features/call/infrastructure/ios_voip_token_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native bridge buffering never logs raw event bytes or previews', () {
    final android = File(
      'android/app/src/main/kotlin/com/mknoon/app/GoBridge.kt',
    ).readAsStringSync();
    final ios = File('ios/Runner/GoBridge.swift').readAsStringSync();

    expect(android, isNot(contains(r'event=${json.take(80)}')));
    expect(ios, isNot(contains('String(json.prefix(80))')));
    expect(android, contains(r'eventLength=${json.length}'));
    expect(ios, contains('eventLength=%d'));
  });

  test('native bridges dispatch every dedicated call control command', () {
    final android = File(
      'android/app/src/main/kotlin/com/mknoon/app/GoBridge.kt',
    ).readAsStringSync();
    final ios = File('ios/Runner/GoBridge.swift').readAsStringSync();
    const methods = <String, String>{
      'callStoreV1': 'CallStoreV1',
      'callRetrieveV1': 'CallRetrieveV1',
      'callAckV1': 'CallAckV1',
      'callCancelV1': 'CallCancelV1',
      'callEndpointSetV1': 'CallEndpointSetV1',
      'callEndpointGetV1': 'CallEndpointGetV1',
      'callEndpointRevokeV1': 'CallEndpointRevokeV1',
      'callWakeHandleSetV1': 'CallWakeHandleSetV1',
      'callWakeHandleRevokeV1': 'CallWakeHandleRevokeV1',
      'callTokenSetV1': 'CallTokenSetV1',
      'callTokenRevokeV1': 'CallTokenRevokeV1',
    };

    for (final entry in methods.entries) {
      expect(
        android,
        contains(
          '"${entry.key}" -> runOnBackground({ '
          'GoMknoon.${entry.key}(args ?: "") }, result)',
        ),
        reason: 'Android must dispatch ${entry.key}',
      );
      expect(
        ios,
        contains(
          'case "${entry.key}":\n'
          '            runOnBackground({ Bridge${entry.value}'
          '(args ?? "") }, result: result)',
        ),
        reason: 'iOS must dispatch ${entry.key}',
      );
    }
  });

  test('VoIP tokens are redacted from Dart errors and diagnostics', () async {
    final token = List<String>.filled(64, 'd').join();
    try {
      IosVoipTokenSnapshot.parse(<String, Object?>{
        'version': 1,
        'token': token,
        'environment': 'development',
        'topic': 'com.mknoon.app.voip',
        'capabilityVersion': 1,
        'refreshEpoch': 1,
        'invalidated': false,
        'unexpected': token,
      });
      fail('malformed snapshot must fail');
    } catch (error) {
      expect(error.toString(), isNot(contains(token)));
      expect(error, isA<IosVoipTokenException>());
    }

    final authority = BridgeCallAuthorityClient(
      bridge: _PrivateFailureBridge(token),
    );
    try {
      await authority.publishToken(
        CallTokenRecord(
          kind: CallTokenKind.iosVoip,
          platform: CallEndpointPlatform.ios,
          token: token,
          expiresAtMs: 10_000,
          environment: 'sandbox',
          topic: 'com.mknoon.app.voip',
          capabilityVersion: 1,
          refreshEpoch: 1,
        ),
      );
      fail('private bridge failure must fail');
    } catch (error) {
      expect(error.toString(), isNot(contains(token)));
      expect(error, isA<CallAuthorityException>());
    }

    final coordinatorSource = File(
      'lib/features/call/infrastructure/ios_voip_token_coordinator.dart',
    ).readAsStringSync();
    expect(coordinatorSource, isNot(contains('debugPrint(')));
    expect(coordinatorSource, isNot(contains('emitFlowEvent(')));
    final bridgeSource = File(
      'lib/core/bridge/go_bridge_client.dart',
    ).readAsStringSync();
    expect(
      bridgeSource,
      contains("details: {'cmd': cmd, 'method': spec.methodName}"),
    );
  });
}

final class _PrivateFailureBridge implements Bridge {
  const _PrivateFailureBridge(this.token);

  final String token;

  @override
  bool get isInitialized => true;

  @override
  Future<String> send(String message) async =>
      '{"ok":false,"errorMessage":"$token"}';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
