import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_test/flutter_test.dart';

const _correlation =
    '8de60f1321300162dd4b0fed8d87b2017c4fa5b459cced3ec6d3a1d52241076d';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('TC-370-05 opaque outcome uses strict all-relay completion', () async {
    flowEventLoggingEnabled = false;
    debugSetFlowEventSink(null);
    addTearDown(() => debugSetFlowEventSink(null));

    expect(kWakeOutcomeCoordinatorAdmissionEnabled, isFalse);

    MethodCall? nativeCall;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const nativeChannel = MethodChannel('com.mknoon/go_bridge');
    messenger.setMockMethodCallHandler(nativeChannel, (call) async {
      nativeCall = call;
      return jsonEncode(const <String, dynamic>{
        'ok': true,
        'allParticipantsTerminal': true,
        'participantCount': 1,
        'acceptedCount': 1,
        'unsupportedCount': 0,
        'retryableCount': 0,
      });
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(nativeChannel, null);
    });
    await callP2PInboxWakeOutcome(GoBridgeClient(), correlation: _correlation);
    expect(nativeCall?.method, 'inboxWakeOutcome');
    expect(
      jsonDecode(nativeCall?.arguments as String),
      <String, dynamic>{'correlation': _correlation, 'wakeNotRequired': true},
      reason: 'the focused owner must cover the real Dart command router',
    );

    final bridge = _WakeOutcomeBridge();
    bridge.response = const <String, dynamic>{'ok': true};
    await callP2PInboxRegisterToken(
      bridge,
      token: 'default-token',
      platform: 'android',
    );
    var payload = bridge.lastPayload;
    expect(payload['capabilities'], <String>[
      directReactionPushCapability,
      groupReactionPushCapability,
    ]);

    await callP2PInboxRegisterToken(
      bridge,
      token: 'admitted-token',
      platform: 'android',
      wakeOutcomeCoordinatorAdmissionEnabled: true,
    );
    payload = bridge.lastPayload;
    expect(payload['capabilities'], <String>[
      directReactionPushCapability,
      groupReactionPushCapability,
      opaqueWakePushCapability,
      wakeOutcomePushCapability,
    ]);

    await expectLater(
      callP2PInboxRegisterToken(
        bridge,
        token: 'half-capable-token',
        platform: 'android',
        capabilities: const <String>[opaqueWakePushCapability],
      ),
      throwsA(isA<ArgumentError>()),
    );
    await expectLater(
      callP2PInboxRegisterToken(
        bridge,
        token: 'bypass-token',
        platform: 'android',
        capabilities: const <String>[
          opaqueWakePushCapability,
          wakeOutcomePushCapability,
        ],
      ),
      throwsA(isA<ArgumentError>()),
    );

    bridge.response = const <String, dynamic>{
      'ok': true,
      'allParticipantsTerminal': true,
      'participantCount': 2,
      'acceptedCount': 1,
      'unsupportedCount': 1,
      'retryableCount': 0,
    };
    final terminal = await callP2PInboxWakeOutcome(
      bridge,
      correlation: _correlation,
    );
    expect(terminal['allParticipantsTerminal'], isTrue);
    expect(bridge.lastRequest['cmd'], 'inbox:wake_outcome');
    expect(bridge.lastPayload, <String, dynamic>{
      'correlation': _correlation,
      'wakeNotRequired': true,
    });
    expect(
      bridge.lastPayload.keys,
      unorderedEquals(<String>['correlation', 'wakeNotRequired']),
    );

    bridge.response = const <String, dynamic>{
      'ok': false,
      'allParticipantsTerminal': false,
      'participantCount': 2,
      'acceptedCount': 1,
      'unsupportedCount': 0,
      'retryableCount': 1,
      'errorCode': 'INBOX_WAKE_OUTCOME_RETRYABLE',
      'errorMessage': 'one relay participant requires retry',
    };
    final partial = await callP2PInboxWakeOutcome(
      bridge,
      correlation: _correlation,
    );
    expect(partial['ok'], isFalse);
    expect(partial['allParticipantsTerminal'], isFalse);
    expect(partial['retryableCount'], 1);

    final sendsBeforeInvalid = bridge.sendCount;
    await expectLater(
      callP2PInboxWakeOutcome(bridge, correlation: _correlation.toUpperCase()),
      throwsA(isA<ArgumentError>()),
    );
    expect(bridge.sendCount, sendsBeforeInvalid);

    bridge.response = const <String, dynamic>{
      'ok': true,
      'allParticipantsTerminal': true,
      'participantCount': 2,
      'acceptedCount': 1,
      'unsupportedCount': 1,
      'retryableCount': 0,
      'unexpected': 'private-or-provider-detail',
    };
    await expectLater(
      callP2PInboxWakeOutcome(bridge, correlation: _correlation),
      throwsA(isA<FormatException>()),
    );
  });
}

final class _WakeOutcomeBridge extends Bridge {
  Map<String, dynamic> response = const <String, dynamic>{'ok': true};
  Map<String, dynamic> lastRequest = const <String, dynamic>{};
  int sendCount = 0;

  Map<String, dynamic> get lastPayload =>
      lastRequest['payload'] as Map<String, dynamic>;

  @override
  bool get isInitialized => true;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> checkHealth() async => true;

  @override
  Future<void> reinitialize() async {}

  @override
  void dispose() {}

  @override
  Future<String> send(String message) async {
    sendCount++;
    lastRequest = jsonDecode(message) as Map<String, dynamic>;
    return jsonEncode(response);
  }
}
