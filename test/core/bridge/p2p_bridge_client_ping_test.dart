import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

// 183 (TC-183-30) — the Dart bridge client for the NEW additive `peer:ping`
// command. Mirrors the callP2PRelayPresenceSet test idiom (a _MockBridge
// capturing the request + a flow-event sink). The real round-trip is the
// device-proof; here we lock the cmd string, payload, and the no-throw
// degradation of an old/unknown bridge response.

class _MockBridge extends Bridge {
  Map<String, dynamic>? lastParsedRequest;
  Map<String, dynamic> nextResponse = {'ok': true};

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
    lastParsedRequest = jsonDecode(message) as Map<String, dynamic>;
    return jsonEncode(nextResponse);
  }
}

void main() {
  late _MockBridge bridge;
  late List<Map<String, dynamic>> flowEvents;

  setUp(() {
    flowEventLoggingEnabled = false;
    bridge = _MockBridge();
    flowEvents = [];
    debugSetFlowEventSink(
      (payload) => flowEvents.add(Map<String, dynamic>.from(payload)),
    );
  });

  tearDown(() => debugSetFlowEventSink(null));

  List<String> eventNames() =>
      flowEvents.map((e) => e['event'] as String).toList();

  // TC-183-30 — sends `peer:ping` with {peerId, timeoutMs} and parses {ok, rttMs}.
  test('callP2PPeerPing sends peer:ping with {peerId, timeoutMs}', () async {
    bridge.nextResponse = {'ok': true, 'rttMs': 12};

    final result = await callP2PPeerPing(
      bridge,
      peerId: 'peer-abc',
      timeoutMs: 4000,
    );

    expect(bridge.lastParsedRequest!['cmd'], 'peer:ping');
    final payload = bridge.lastParsedRequest!['payload'] as Map;
    expect(payload['peerId'], 'peer-abc');
    expect(payload['timeoutMs'], 4000);

    expect(result['ok'], isTrue);
    expect(result['rttMs'], 12);

    final names = eventNames();
    expect(names, contains('P2P_PEER_PING_REQUEST'));
    expect(names, contains('P2P_PEER_PING_RESPONSE'));
    expect(
      names.indexOf('P2P_PEER_PING_REQUEST'),
      lessThan(names.indexOf('P2P_PEER_PING_RESPONSE')),
    );
  });

  // TC-183-30 (degradation) — an old bridge that does not know `peer:ping`
  // (returns an Unknown-action / not-implemented envelope) maps to a typed
  // failure {ok:false} with NO throw, so the keepalive treats it as a miss
  // rather than crashing the loop.
  test('callP2PPeerPing maps an unknown/old-bridge response to ok:false (no throw)', () async {
    bridge.nextResponse = {
      'ok': false,
      'errorCode': 'UNKNOWN_COMMAND',
      'errorMessage': 'Unknown command: peer:ping',
    };

    final result = await callP2PPeerPing(
      bridge,
      peerId: 'peer-old',
      timeoutMs: 4000,
    );

    expect(result['ok'], isFalse);
    expect(result['rttMs'], isNull);
  });

  // A failed ping (peer unreachable) reported by the bridge maps to ok:false.
  test('callP2PPeerPing maps a ping failure to ok:false', () async {
    bridge.nextResponse = {'ok': false, 'error': 'ping failed: no route'};

    final result = await callP2PPeerPing(
      bridge,
      peerId: 'peer-gone',
      timeoutMs: 4000,
    );

    expect(result['ok'], isFalse);
  });
}
