import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart';

// ---------------------------------------------------------------------------
// Test-only fake bridge
// ---------------------------------------------------------------------------

/// A controllable fake bridge for P2PServiceImpl tests.
///
/// Returns pre-configured responses for each bridge command. Supports
/// injecting extra fields into node:status responses to test forward
/// compatibility with future Go relay-state diagnostics.
class _FakeBridge implements Bridge {
  bool _initialized = true;

  /// Extra fields injected into every node:status response.
  /// Used to verify that the Dart parser tolerates unknown keys.
  Map<String, dynamic> extraStatusFields = {};

  /// The node:start response. Defaults to a successful started state.
  Map<String, dynamic> startResponse = {
    'ok': true,
    'peerId': '12D3KooWTestPeerId',
    'isStarted': true,
    'listenAddresses': ['/ip4/127.0.0.1/tcp/1234'],
    'circuitAddresses': ['/p2p-circuit/p2p/12D3KooWRelay'],
    'connections': <Map<String, dynamic>>[],
  };

  /// The node:status response. Defaults to the same online state.
  Map<String, dynamic> statusResponse = {
    'ok': true,
    'peerId': '12D3KooWTestPeerId',
    'isStarted': true,
    'listenAddresses': ['/ip4/127.0.0.1/tcp/1234'],
    'circuitAddresses': ['/p2p-circuit/p2p/12D3KooWRelay'],
    'connections': <Map<String, dynamic>>[],
  };

  /// The inbox:retrieve response.
  Map<String, dynamic> inboxRetrieveResponse = {
    'ok': true,
    'messages': <dynamic>[],
  };

  int nodeStartCallCount = 0;
  int nodeStatusCallCount = 0;
  int peerDialCallCount = 0;

  @override
  bool get isInitialized => _initialized;

  @override
  void Function(ChatMessage)? onMessageReceived;
  @override
  void Function(ConnectionState)? onPeerConnected;
  @override
  void Function(ConnectionState)? onPeerDisconnected;
  @override
  void Function(List<String> listenAddresses, List<String> circuitAddresses)?
      onAddressesUpdated;
  @override
  void Function(Map<String, dynamic>)? onGroupMessageReceived;
  @override
  void Function(Map<String, dynamic>)? onGroupReactionReceived;

  @override
  Future<void> initialize() async {
    _initialized = true;
  }

  @override
  Future<bool> checkHealth() async => true;

  @override
  Future<void> reinitialize() async {
    _initialized = true;
  }

  @override
  void dispose() {
    _initialized = false;
  }

  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message) as Map<String, dynamic>;
    final cmd = request['cmd'] as String;

    switch (cmd) {
      case 'node:start':
        nodeStartCallCount++;
        return jsonEncode(startResponse);
      case 'node:status':
        nodeStatusCallCount++;
        // Merge extra fields into status to simulate future Go additions.
        final response = Map<String, dynamic>.from(statusResponse)
          ..addAll(extraStatusFields);
        return jsonEncode(response);
      case 'node:stop':
        return jsonEncode({'ok': true, 'stopped': true});
      case 'peer:dial':
        peerDialCallCount++;
        return jsonEncode({'ok': true, 'connected': true});
      case 'inbox:retrieve':
        return jsonEncode(inboxRetrieveResponse);
      default:
        return jsonEncode({'ok': true});
    }
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

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

  // -------------------------------------------------------------------------
  // Phase 0: Baseline contract-locking tests
  // -------------------------------------------------------------------------

  group('Phase 0 — backward-compatible status parsing', () {
    test(
        'startNode preserves legacy status parsing when extra fields exist',
        () async {
      // Simulate a future Go build that adds relay-state diagnostics
      // to the node:start response. The Dart parser must tolerate and
      // ignore these unknown fields.
      bridge.startResponse = {
        'ok': true,
        'peerId': '12D3KooWTestPeerId',
        'isStarted': true,
        'listenAddresses': ['/ip4/127.0.0.1/tcp/1234'],
        'circuitAddresses': ['/p2p-circuit/p2p/12D3KooWRelay'],
        'connections': <Map<String, dynamic>>[],
        // Future additive fields (Phase 2+):
        'relayState': 'reserved',
        'relayStates': [
          {'address': '/dns4/relay1/tcp/4001', 'state': 'reserved'},
        ],
        'healthyRelayCount': 1,
        'lastReservationAt': '2026-03-09T00:00:00Z',
        'watchdogRestartCount': 0,
        'needsGroupRecovery': false,
      };

      // Also set status response with extra fields so the "already started"
      // resync path is covered.
      bridge.statusResponse = Map<String, dynamic>.from(bridge.startResponse);

      final result = await service.startNodeCore(
        'AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA=',
        '12D3KooWTestPeerId',
      );

      expect(result, isTrue, reason: 'startNodeCore should succeed');
      expect(service.currentState.isStarted, isTrue);
      expect(service.currentState.peerId, equals('12D3KooWTestPeerId'));
      expect(service.currentState.circuitAddresses, isNotEmpty);
      expect(service.currentState.listenAddresses, isNotEmpty);
    });

    test(
        'performImmediateHealthCheck ignores unknown relay fields before migration',
        () async {
      // Start the node normally first.
      final started = await service.startNodeCore(
        'AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA=',
        '12D3KooWTestPeerId',
      );
      expect(started, isTrue);

      // Now inject future relay-state fields into node:status responses.
      // The health check polls node:status and must parse without error.
      bridge.extraStatusFields = {
        'relayState': 'reserved',
        'relayStates': [
          {
            'address': '/dns4/relay1/tcp/4001',
            'state': 'reserved',
            'lastReservationAt': '2026-03-09T00:00:00Z',
          },
          {
            'address': '/dns4/relay2/tcp/4001',
            'state': 'disconnected',
          },
        ],
        'healthyRelayCount': 1,
        'lastReservationAt': '2026-03-09T00:00:00Z',
        'watchdogRestartCount': 0,
        'needsGroupRecovery': false,
      };

      // performImmediateHealthCheck should complete without errors.
      // It calls _performHealthCheck internally which parses node:status.
      await service.performImmediateHealthCheck();

      // Verify the node state is still valid after parsing the response
      // with unknown fields.
      expect(service.currentState.isStarted, isTrue);
      expect(service.currentState.peerId, equals('12D3KooWTestPeerId'));
      expect(service.currentState.circuitAddresses, isNotEmpty);

      // Verify that the health check actually ran (called node:status).
      // startNodeCore calls node:start (1 call), health check calls
      // node:status at least once.
      expect(bridge.nodeStatusCallCount, greaterThanOrEqualTo(1));
    });
  });
}
