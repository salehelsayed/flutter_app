import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

// FDC-08 C1/C2 — the Dart bridge client for the additive `presence_get` action.
// Mirrors the callP2PRelayProbe test idiom (a _MockBridge capturing the
// request + a flow-event sink).

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

  // C1 — sends relay:presence_get with the to-peer and parses {presence, ageMs}.
  test(
    'callP2PRelayPresence sends relay:presence_get with to-peer and parses {presence, ageMs}',
    () async {
      bridge.nextResponse = {
        'ok': true,
        'presence': 'reachable',
        'ageMs': 1200,
      };

      final result = await callP2PRelayPresence(bridge, peerId: 'peer-abc');

      // The request shape is the NEW cmd, not the legacy probe.
      expect(bridge.lastParsedRequest!['cmd'], 'relay:presence_get');
      final payload = bridge.lastParsedRequest!['payload'] as Map;
      expect(payload['peerId'], 'peer-abc');

      // Parses the canonical schema + surfaces ageMs (so the cache/staleness
      // rule can see it).
      expect(result['presence'], 'reachable');
      expect(result['ageMs'], 1200);

      // Distinct REQUEST -> RESPONSE events fire (NOT the legacy probe events),
      // proving the new path ran.
      final names = eventNames();
      expect(names, contains('P2P_RELAY_PRESENCE_REQUEST'));
      expect(names, contains('P2P_RELAY_PRESENCE_RESPONSE'));
      expect(
        names.indexOf('P2P_RELAY_PRESENCE_REQUEST'),
        lessThan(names.indexOf('P2P_RELAY_PRESENCE_RESPONSE')),
      );
      expect(names, isNot(contains('P2P_RELAY_PROBE_REQUEST')));
      expect(names, isNot(contains('P2P_RELAY_PROBE_RESPONSE')));
    },
  );

  // C2 — an old relay's "Unknown action" ERROR degrades to unknown (NET-REL-07),
  // NOT unreachable.
  test(
    'callP2PRelayPresence maps Unknown action ERROR to unknown (never unreachable)',
    () async {
      bridge.nextResponse = {
        'status': 'ERROR',
        'error': 'Unknown action: presence_get',
      };

      final result = await callP2PRelayPresence(bridge, peerId: 'peer-old');

      expect(result['presence'], 'unknown');
      expect(result['presence'], isNot('unreachable'));
      expect(eventNames(), contains('P2P_RELAY_PRESENCE_UNKNOWN_ACTION'));
    },
  );
}
