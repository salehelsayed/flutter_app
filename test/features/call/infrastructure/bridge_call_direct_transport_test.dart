import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/call/infrastructure/bridge_call_direct_transport.dart';
import 'package:flutter_app/features/call/infrastructure/p2p_call_transport.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeBridge implements Bridge {
  final List<Map<String, dynamic>> requests = <Map<String, dynamic>>[];
  Map<String, Object?> response = const <String, Object?>{'ok': false};
  Object? failure;

  @override
  bool get isInitialized => true;

  @override
  Future<String> send(String message) async {
    requests.add(jsonDecode(message) as Map<String, dynamic>);
    final error = failure;
    if (error != null) throw error;
    return jsonEncode(response);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeBridge bridge;
  late BridgeCallDirectTransport transport;

  setUp(() {
    bridge = _FakeBridge();
    transport = BridgeCallDirectTransport(bridge: bridge, timeoutMs: 4000);
  });

  // Plan 404: the headless decline reply has no P2PService; its direct leg is
  // one bounded message:send through the Go bridge, mapped like P2PCallTransport.
  test('an acknowledged bridge send is an accepted direct leg', () async {
    bridge.response = const <String, Object?>{
      'ok': true,
      'sent': true,
      'acked': true,
      'transport': 'circuit-relay',
    };

    final result = await transport.send(
      recipientDevicePeerId: 'caller-device',
      envelopeJson: '{"opaque":true}',
    );

    expect(result.accepted, isTrue);
    expect(result.transportAcknowledged, isTrue);
    expect(result.route, CallDirectRoute.circuitRelay);
    expect(bridge.requests.single['cmd'], 'message:send');
    expect(bridge.requests.single['payload'], <String, Object?>{
      'peerId': 'caller-device',
      'message': '{"opaque":true}',
      'timeoutMs': 4000,
    });
  });

  test('an unacknowledged, refused, or failing send is not accepted', () async {
    for (final response in <Map<String, Object?>>[
      const <String, Object?>{'ok': true, 'sent': true, 'acked': false},
      const <String, Object?>{'ok': false, 'sent': false},
      const <String, Object?>{'ok': true},
    ]) {
      bridge.response = response;
      final result = await transport.send(
        recipientDevicePeerId: 'caller-device',
        envelopeJson: '{}',
      );
      expect(result.accepted, isFalse, reason: jsonEncode(response));
      expect(result.outcome, CallDirectTransportOutcome.failed);
    }

    bridge.failure = StateError('bridge gone');
    final failed = await transport.send(
      recipientDevicePeerId: 'caller-device',
      envelopeJson: '{}',
    );
    expect(failed.accepted, isFalse);
    expect(failed.route, CallDirectRoute.unknown);
  });

  test(
    'oversized envelopes and empty recipients never reach the bridge',
    () async {
      final oversized = await transport.send(
        recipientDevicePeerId: 'caller-device',
        envelopeJson: 'x' * (P2PCallTransport.maxSignalBytes + 1),
      );
      expect(oversized.outcome, CallDirectTransportOutcome.rejectedOversized);

      final empty = await transport.send(
        recipientDevicePeerId: ' ',
        envelopeJson: '{}',
      );
      expect(empty.outcome, CallDirectTransportOutcome.failed);
      expect(bridge.requests, isEmpty);
    },
  );
}
