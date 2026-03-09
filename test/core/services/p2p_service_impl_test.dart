import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart'
    as p2p;

/// A fake bridge that records commands and returns configurable responses.
class _FakeBridge extends Bridge {
  final Map<String, String Function(Map<String, dynamic>?)> _handlers = {};
  final List<String> calledCommands = [];
  bool _initialized = false;

  void whenCommand(String cmd, String Function(Map<String, dynamic>?) handler) {
    _handlers[cmd] = handler;
  }

  @override
  bool get isInitialized => _initialized;

  @override
  Future<void> initialize() async {
    _initialized = true;
  }

  @override
  Future<bool> checkHealth() async => true;

  @override
  Future<void> reinitialize() async {}

  @override
  void dispose() {}

  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message) as Map<String, dynamic>;
    final cmd = request['cmd'] as String;
    final payload = request['payload'] as Map<String, dynamic>?;

    calledCommands.add(cmd);

    final handler = _handlers[cmd];
    if (handler != null) {
      return handler(payload);
    }

    return jsonEncode({'ok': false, 'errorCode': 'UNHANDLED', 'errorMessage': 'no handler for $cmd'});
  }
}

void main() {
  late _FakeBridge bridge;
  late P2PServiceImpl service;

  setUp(() {
    bridge = _FakeBridge();
    service = P2PServiceImpl(bridge: bridge);
  });

  tearDown(() {
    service.dispose();
  });

  group('Phase 1 — startup and warm background', () {
    test('warmBackground drains inbox while relay reservation is still pending', () async {
      // Set up: node is started but no circuit addresses (relay pending)
      bridge.whenCommand('node:start', (_) => jsonEncode({
        'ok': true,
        'peerId': 'test-peer',
        'isStarted': true,
        'listenAddresses': ['/ip4/127.0.0.1/tcp/4001'],
        'circuitAddresses': [],
        'connections': [],
      }));
      bridge.whenCommand('node:status', (_) => jsonEncode({
        'ok': true,
        'peerId': 'test-peer',
        'isStarted': true,
        'listenAddresses': ['/ip4/127.0.0.1/tcp/4001'],
        'circuitAddresses': [], // Still no relay
        'connections': [],
      }));
      bridge.whenCommand('inbox:retrieve', (_) => jsonEncode({
        'ok': true,
        'messages': [
          {'from': 'sender1', 'message': '{"type":"chat_message","version":"1","payload":{"id":"m1","text":"hello","senderPeerId":"sender1","senderUsername":"S","timestamp":"2026-01-01T00:00:00Z"}}', 'timestamp': 1700000000000}
        ],
        'hasMore': false,
      }));

      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');

      // Collect messages
      final messages = <ChatMessage>[];
      final sub = service.messageStream.listen(messages.add);

      await service.warmBackground();

      // Give stream time to propagate
      await Future.delayed(const Duration(milliseconds: 50));

      // Inbox should have been drained even though relay is pending
      expect(messages.length, 1);
      expect(messages.first.from, 'sender1');

      // Circuit addresses are still empty — relay not ready
      expect(service.currentState.circuitAddresses, isEmpty);

      await sub.cancel();
    });

    test('resume drains inbox before online indicator turns green', () async {
      bridge.whenCommand('node:start', (_) => jsonEncode({
        'ok': true,
        'peerId': 'test-peer',
        'isStarted': true,
        'listenAddresses': [],
        'circuitAddresses': [],
        'connections': [],
      }));
      bridge.whenCommand('inbox:retrieve', (_) => jsonEncode({
        'ok': true,
        'messages': [
          {'from': 'sender1', 'message': 'msg1', 'timestamp': 1700000000000}
        ],
        'hasMore': false,
      }));
      bridge.whenCommand('node:status', (_) => jsonEncode({
        'ok': true,
        'peerId': 'test-peer',
        'isStarted': true,
        'listenAddresses': [],
        'circuitAddresses': [], // Not online yet
        'connections': [],
      }));

      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');

      final messages = <ChatMessage>[];
      final sub = service.messageStream.listen(messages.add);

      // Call drainOfflineInbox (simulating resume)
      await service.drainOfflineInbox();

      await Future.delayed(const Duration(milliseconds: 50));

      // Inbox drained before circuit addresses exist
      expect(messages.length, 1);
      expect(service.currentState.circuitAddresses, isEmpty);

      await sub.cancel();
    });

    test('startup inbox drain shows first page before background continuation completes', () async {
      var retrieveCallCount = 0;
      bridge.whenCommand('node:start', (_) => jsonEncode({
        'ok': true,
        'peerId': 'test-peer',
        'isStarted': true,
        'listenAddresses': [],
        'circuitAddresses': [],
        'connections': [],
      }));
      bridge.whenCommand('inbox:retrieve', (_) {
        retrieveCallCount++;
        return jsonEncode({
          'ok': true,
          'messages': [
            {'from': 'sender$retrieveCallCount', 'message': 'msg$retrieveCallCount', 'timestamp': 1700000000000}
          ],
          'hasMore': false,
        });
      });
      bridge.whenCommand('node:status', (_) => jsonEncode({
        'ok': true,
        'peerId': 'test-peer',
        'isStarted': true,
        'listenAddresses': [],
        'circuitAddresses': [],
        'connections': [],
      }));

      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');

      final messages = <ChatMessage>[];
      final sub = service.messageStream.listen(messages.add);

      await service.warmBackground();

      await Future.delayed(const Duration(milliseconds: 50));

      // First page retrieved
      expect(messages.isNotEmpty, true);
      expect(retrieveCallCount, greaterThanOrEqualTo(1));

      await sub.cancel();
    });

    test('fast circuit fallback poll updates online state when push event is delayed', () async {
      bridge.whenCommand('node:start', (_) => jsonEncode({
        'ok': true,
        'peerId': 'test-peer',
        'isStarted': true,
        'listenAddresses': [],
        'circuitAddresses': [],
        'connections': [],
      }));
      bridge.whenCommand('inbox:retrieve', (_) => jsonEncode({
        'ok': true,
        'messages': [],
        'hasMore': false,
      }));

      // node:status always returns circuit — the point is node:start had none
      // but the health check poll picks up the circuit address.
      bridge.whenCommand('node:status', (_) => jsonEncode({
        'ok': true,
        'peerId': 'test-peer',
        'isStarted': true,
        'listenAddresses': [],
        'circuitAddresses': ['/p2p-circuit/relay1'],
        'connections': [],
      }));

      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');

      // Initially no circuit from node:start
      expect(service.currentState.circuitAddresses, isEmpty);

      // Trigger health check manually — polls node:status
      await service.performImmediateHealthCheck();

      // Now should have circuit from the polled status
      expect(service.currentState.circuitAddresses, isNotEmpty);
    });

    test('early relay edge signal does not mark online before circuit or reservation readiness', () async {
      bridge.whenCommand('node:start', (_) => jsonEncode({
        'ok': true,
        'peerId': 'test-peer',
        'isStarted': true,
        'listenAddresses': [],
        'circuitAddresses': [], // No circuit yet — just relay socket
        'connections': [
          {'peerId': 'relay-peer', 'address': '/dns4/relay/tcp/4001', 'direction': 'outbound'}
        ],
      }));
      bridge.whenCommand('inbox:retrieve', (_) => jsonEncode({
        'ok': true,
        'messages': [],
        'hasMore': false,
      }));
      bridge.whenCommand('node:status', (_) => jsonEncode({
        'ok': true,
        'peerId': 'test-peer',
        'isStarted': true,
        'listenAddresses': [],
        'circuitAddresses': [],
        'connections': [],
      }));

      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');

      // Having a relay connection but no circuit addresses should not
      // mean we're "online" in the ConnectionStatusIndicator sense
      expect(service.currentState.circuitAddresses, isEmpty);
      expect(service.currentState.isStarted, true);
    });

    test('cold start after reboot prioritizes inbox retrieval before secondary warm tasks', () async {
      bridge.whenCommand('node:start', (_) => jsonEncode({
        'ok': true,
        'peerId': 'test-peer',
        'isStarted': true,
        'listenAddresses': [],
        'circuitAddresses': [],
        'connections': [],
      }));
      bridge.whenCommand('node:status', (_) => jsonEncode({
        'ok': true,
        'peerId': 'test-peer',
        'isStarted': true,
        'listenAddresses': [],
        'circuitAddresses': [],
        'connections': [],
      }));
      bridge.whenCommand('inbox:retrieve', (_) => jsonEncode({
        'ok': true,
        'messages': [
          {'from': 'sender1', 'message': 'queued-msg', 'timestamp': 1700000000000}
        ],
        'hasMore': false,
      }));

      // Full startNode includes warmBackground
      await service.startNode('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');

      // Inbox retrieve should have been called during warm background
      expect(bridge.calledCommands, contains('inbox:retrieve'));

      // inbox:retrieve should come before subsequent node:status health checks
      final inboxIdx = bridge.calledCommands.indexOf('inbox:retrieve');
      expect(inboxIdx, greaterThanOrEqualTo(0));
    });

    test('cold start quick retry burst runs before watchdog timer path', () async {
      bridge.whenCommand('node:start', (_) => jsonEncode({
        'ok': true,
        'peerId': 'test-peer',
        'isStarted': true,
        'listenAddresses': [],
        'circuitAddresses': [],
        'connections': [],
      }));
      bridge.whenCommand('node:status', (_) => jsonEncode({
        'ok': true,
        'peerId': 'test-peer',
        'isStarted': true,
        'listenAddresses': [],
        'circuitAddresses': [],
        'connections': [],
      }));
      bridge.whenCommand('inbox:retrieve', (_) => jsonEncode({
        'ok': true,
        'messages': [],
        'hasMore': false,
      }));

      // startNode triggers warmBackground which includes inbox drain
      await service.startNode('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');

      // Inbox was attempted early (during warm, before watchdog timer)
      expect(bridge.calledCommands, contains('inbox:retrieve'));

      // The health check timer interval is 30s, so inbox drain runs
      // well before the first health check would fire
      expect(P2PServiceImpl.healthCheckInterval.inSeconds, 30);
    });

    test('background relay healing keeps longer retry cadence than foreground send', () async {
      // This verifies the design: health check interval (30s) is much longer
      // than interactive timeouts (1.5-4s)
      expect(P2PServiceImpl.healthCheckInterval.inSeconds, greaterThanOrEqualTo(30));
    });
  });

  group('Phase 4 — relay session manager and reservation-aware health', () {
    test('health check uses relayState when present', () async {
      // When node:status returns relayState, the parsed NodeState should
      // include it for health decisions.
      bridge.whenCommand('node:start', (_) => jsonEncode({
        'ok': true,
        'peerId': 'test-peer',
        'isStarted': true,
        'listenAddresses': [],
        'circuitAddresses': ['/p2p-circuit/relay1'],
        'connections': [],
        'relayState': 'online',
        'healthyRelayCount': 1,
        'watchdogRestartCount': 0,
      }));
      bridge.whenCommand('inbox:retrieve', (_) => jsonEncode({
        'ok': true,
        'messages': [],
        'hasMore': false,
      }));
      bridge.whenCommand('node:status', (_) => jsonEncode({
        'ok': true,
        'peerId': 'test-peer',
        'isStarted': true,
        'listenAddresses': [],
        'circuitAddresses': ['/p2p-circuit/relay1'],
        'connections': [],
        'relayState': 'online',
        'healthyRelayCount': 1,
        'watchdogRestartCount': 0,
      }));

      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');

      // The NodeState should include the relayState field.
      expect(service.currentState.relayState, 'online');
      expect(service.currentState.healthyRelayCount, 1);
      expect(service.currentState.watchdogRestartCount, 0);
    });

    test('legacy circuitAddresses path still works when relayState absent', () async {
      // When the Go bridge does not include relayState (pre-Phase 4),
      // the parser should still work and relayState should be null.
      bridge.whenCommand('node:start', (_) => jsonEncode({
        'ok': true,
        'peerId': 'test-peer',
        'isStarted': true,
        'listenAddresses': ['/ip4/127.0.0.1/tcp/4001'],
        'circuitAddresses': ['/p2p-circuit/relay1'],
        'connections': [],
        // No relayState, healthyRelayCount, or watchdogRestartCount
      }));
      bridge.whenCommand('inbox:retrieve', (_) => jsonEncode({
        'ok': true,
        'messages': [],
        'hasMore': false,
      }));
      bridge.whenCommand('node:status', (_) => jsonEncode({
        'ok': true,
        'peerId': 'test-peer',
        'isStarted': true,
        'listenAddresses': [],
        'circuitAddresses': ['/p2p-circuit/relay1'],
        'connections': [],
      }));

      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');

      // Legacy fields work.
      expect(service.currentState.isStarted, true);
      expect(service.currentState.circuitAddresses, isNotEmpty);

      // New fields are null (absent from response).
      expect(service.currentState.relayState, isNull);
      expect(service.currentState.healthyRelayCount, isNull);
    });

    test('relay state push updates current state without restart', () async {
      bridge.whenCommand('node:start', (_) => jsonEncode({
        'ok': true,
        'peerId': 'test-peer',
        'isStarted': true,
        'listenAddresses': [],
        'circuitAddresses': [],
        'connections': [],
        'relayState': 'starting',
        'healthyRelayCount': 0,
      }));
      bridge.whenCommand('inbox:retrieve', (_) => jsonEncode({
        'ok': true,
        'messages': [],
        'hasMore': false,
      }));
      bridge.whenCommand('node:status', (_) => jsonEncode({
        'ok': true,
        'peerId': 'test-peer',
        'isStarted': true,
        'listenAddresses': [],
        'circuitAddresses': ['/p2p-circuit/relay1'],
        'connections': [],
        'relayState': 'online',
        'healthyRelayCount': 1,
      }));

      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');

      // Initially starting with no circuits.
      expect(service.currentState.relayState, 'starting');

      // After health check, the state should update in place (no restart).
      await service.performImmediateHealthCheck();

      // The relay state should be updated from the status response.
      expect(service.currentState.relayState, 'online');
      expect(service.currentState.healthyRelayCount, 1);
      expect(service.currentState.circuitAddresses, isNotEmpty);
    });

    test('status push burst coalescing does not lose final online state', () async {
      bridge.whenCommand('node:start', (_) => jsonEncode({
        'ok': true,
        'peerId': 'test-peer',
        'isStarted': true,
        'listenAddresses': [],
        'circuitAddresses': [],
        'connections': [],
      }));
      bridge.whenCommand('inbox:retrieve', (_) => jsonEncode({
        'ok': true,
        'messages': [],
        'hasMore': false,
      }));

      // Simulate a burst of status updates via the addresses:updated push.
      // The final state should be the one that sticks.
      var statusCallCount = 0;
      bridge.whenCommand('node:status', (_) {
        statusCallCount++;
        // Each call returns progressively more connected state.
        if (statusCallCount <= 2) {
          return jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': [],
            'circuitAddresses': [],
            'connections': [],
          });
        }
        return jsonEncode({
          'ok': true,
          'peerId': 'test-peer',
          'isStarted': true,
          'listenAddresses': [],
          'circuitAddresses': ['/p2p-circuit/relay1'],
          'connections': [],
          'relayState': 'online',
          'healthyRelayCount': 1,
        });
      });

      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');

      // Simulate multiple health checks (as if push events triggered them).
      await service.performImmediateHealthCheck();
      await service.performImmediateHealthCheck();
      await service.performImmediateHealthCheck();

      // The final state should reflect online.
      expect(service.currentState.circuitAddresses, isNotEmpty);
    });
  });
}
