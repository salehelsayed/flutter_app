import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart';

// ---------------------------------------------------------------------------
// Test constants
// ---------------------------------------------------------------------------

/// A valid base64 key (32 bytes = Ed25519 seed).
const _testBase64Key = 'AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA=';
const _testPeerId = '12D3KooWTestPeerId';

// ---------------------------------------------------------------------------
// _ReconnectGateBridge
// ---------------------------------------------------------------------------

/// A Bridge implementation with Completer-based gates for specific commands.
///
/// Unlike FakeBridge (which responds instantly) or _SlowBridge (which gates
/// one command), this bridge lets tests gate specific commands independently
/// and tracks every command issued for post-hoc inspection.
class _ReconnectGateBridge implements Bridge {
  bool _isInitialized = false;

  /// Every command sent through the bridge, in order.
  final List<String> commandLog = [];

  /// Number of times `node:status` has been called.
  int nodeStatusCallCount = 0;

  /// If non-null, the Nth call to `node:status` (1-indexed) will await this
  /// completer before returning. Only gates that specific call.
  int? gateNodeStatusOnCallNumber;
  Completer<void>? nodeStatusGate;

  /// If non-null, `relay:reconnect` will await this completer before returning.
  Completer<void>? relayReconnectGate;

  /// If non-null, `inbox:retrieve` will await this completer before returning.
  Completer<void>? inboxRetrieveGate;

  /// Pre-canned JSON responses keyed by command name.
  final Map<String, Map<String, dynamic>> responses = {};

  @override
  bool get isInitialized => _isInitialized;

  @override
  void Function(ChatMessage)? onMessageReceived;
  @override
  void Function(ConnectionState)? onPeerConnected;
  @override
  void Function(ConnectionState)? onPeerDisconnected;
  @override
  void Function(List<String>, List<String>)? onAddressesUpdated;
  @override
  void Function(Map<String, dynamic>)? onGroupMessageReceived;

  @override
  Future<void> initialize() async {
    _isInitialized = true;
  }

  @override
  Future<bool> checkHealth() async => true;

  @override
  Future<void> reinitialize() async {
    _isInitialized = true;
  }

  @override
  void dispose() {
    _isInitialized = false;
  }

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String;
    commandLog.add(cmd);

    // Gate: relay:reconnect
    if (cmd == 'relay:reconnect' && relayReconnectGate != null) {
      final gate = relayReconnectGate!;
      if (!gate.isCompleted) {
        await gate.future;
      }
    }

    // Gate: node:status on a specific call number
    if (cmd == 'node:status') {
      nodeStatusCallCount++;
      if (gateNodeStatusOnCallNumber != null &&
          nodeStatusCallCount == gateNodeStatusOnCallNumber &&
          nodeStatusGate != null) {
        final gate = nodeStatusGate!;
        if (!gate.isCompleted) {
          await gate.future;
        }
      }
    }

    // Gate: inbox:retrieve
    if (cmd == 'inbox:retrieve' && inboxRetrieveGate != null) {
      final gate = inboxRetrieveGate!;
      if (!gate.isCompleted) {
        await gate.future;
      }
    }

    // Return pre-canned response or default success
    if (responses.containsKey(cmd)) {
      return jsonEncode(responses[cmd]!);
    }
    return jsonEncode({'ok': true});
  }
}

// ---------------------------------------------------------------------------
// Response helpers
// ---------------------------------------------------------------------------

/// node:start response that is "started" but with EMPTY circuit addresses.
/// This puts the node in a degraded state so the health check enters recovery.
Map<String, dynamic> _nodeStartDegraded() => {
      'ok': true,
      'peerId': _testPeerId,
      'isStarted': true,
      'listenAddresses': ['/ip4/127.0.0.1/tcp/1234'],
      'circuitAddresses': <String>[], // empty = degraded
      'connections': <Map<String, dynamic>>[],
    };

/// node:start with full circuit addresses (healthy).
Map<String, dynamic> _nodeStartOk() => {
      'ok': true,
      'peerId': _testPeerId,
      'isStarted': true,
      'listenAddresses': ['/ip4/127.0.0.1/tcp/1234'],
      'circuitAddresses': ['/p2p-circuit/test'],
      'connections': <Map<String, dynamic>>[],
    };

/// node:status that returns started but empty circuits (degraded).
Map<String, dynamic> _nodeStatusDegraded() => {
      'ok': true,
      'peerId': _testPeerId,
      'isStarted': true,
      'listenAddresses': ['/ip4/127.0.0.1/tcp/1234'],
      'circuitAddresses': <String>[],
      'connections': <Map<String, dynamic>>[],
    };

/// node:status that returns healthy with circuit addresses.
Map<String, dynamic> _nodeStatusOk() => {
      'ok': true,
      'peerId': _testPeerId,
      'isStarted': true,
      'listenAddresses': ['/ip4/127.0.0.1/tcp/1234'],
      'circuitAddresses': ['/p2p-circuit/test'],
      'connections': <Map<String, dynamic>>[],
    };

// ---------------------------------------------------------------------------
// Helper: wait for a command to appear in the log
// ---------------------------------------------------------------------------

/// Pumps the microtask queue until [commandLog] contains the expected command,
/// or until [maxIterations] is reached.
Future<void> _waitForCommand(
  List<String> commandLog,
  String command, {
  int maxIterations = 200,
}) async {
  for (var i = 0; i < maxIterations; i++) {
    if (commandLog.contains(command)) return;
    await Future<void>.delayed(Duration.zero);
  }
}

/// Pumps the microtask queue until [commandLog] contains at least [count]
/// occurrences of [command], or until [maxIterations] is reached.
Future<void> _waitForCommandCount(
  List<String> commandLog,
  String command,
  int count, {
  int maxIterations = 200,
}) async {
  for (var i = 0; i < maxIterations; i++) {
    final actual = commandLog.where((c) => c == command).length;
    if (actual >= count) return;
    await Future<void>.delayed(Duration.zero);
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // =========================================================================
  // Stop during in-flight reconnect
  // =========================================================================

  group('Stop during in-flight reconnect', () {
    test('stopNode during relay:reconnect does not resurrect started state',
        () async {
      // Setup: a bridge where relay:reconnect is gated by a Completer.
      final bridge = _ReconnectGateBridge();
      bridge.relayReconnectGate = Completer<void>();

      // node:start returns degraded so _hasEverBeenOnline won't be set yet.
      // We need to first get the node online, THEN degrade it.
      bridge.responses['node:start'] = _nodeStartOk();
      // First node:status call returns degraded to trigger recovery.
      bridge.responses['node:status'] = _nodeStatusDegraded();
      bridge.responses['node:stop'] = {'ok': true, 'stopped': true};
      bridge.responses['relay:reconnect'] = {'ok': true};
      bridge.responses['inbox:retrieve'] = {'ok': true, 'messages': []};

      final service = P2PServiceImpl(bridge: bridge);

      // Start the node in healthy state first (sets _hasEverBeenOnline = true).
      await service.startNodeCore(_testBase64Key, _testPeerId);
      expect(service.currentState.isStarted, isTrue);
      expect(service.currentState.circuitAddresses, isNotEmpty);

      // Now fire a health check. It will see degraded node:status (empty
      // circuits + _hasEverBeenOnline) and call relay:reconnect, which blocks.
      // Do NOT await — we want it in-flight.
      final healthCheckFuture = service.performImmediateHealthCheck();

      // Wait until relay:reconnect has been called (the gate is holding it).
      await _waitForCommand(bridge.commandLog, 'relay:reconnect');
      expect(bridge.commandLog, contains('relay:reconnect'));

      // Now call stopNode while relay:reconnect is still blocked.
      final stopResult = await service.stopNode();
      expect(stopResult, isTrue);
      expect(service.currentState.isStarted, isFalse);

      // Release the relay:reconnect gate so the health check can complete.
      bridge.relayReconnectGate!.complete();
      await healthCheckFuture;

      // The _stopped guard prevents the health check from resurrecting state.
      expect(service.currentState.isStarted, isFalse);

      service.dispose();
    });

    test(
        'stopNode during post-reconnect node:status does not resurrect state',
        () async {
      final bridge = _ReconnectGateBridge();

      // Gate the 2nd node:status call (the post-reconnect re-poll).
      // The 1st node:status is the initial poll inside _performHealthCheck.
      bridge.gateNodeStatusOnCallNumber = 2;
      bridge.nodeStatusGate = Completer<void>();

      bridge.responses['node:start'] = _nodeStartOk();
      bridge.responses['node:status'] = _nodeStatusDegraded();
      bridge.responses['node:stop'] = {'ok': true, 'stopped': true};
      bridge.responses['relay:reconnect'] = {'ok': true};
      bridge.responses['inbox:retrieve'] = {'ok': true, 'messages': []};

      final service = P2PServiceImpl(bridge: bridge);

      // Start healthy (sets _hasEverBeenOnline).
      await service.startNodeCore(_testBase64Key, _testPeerId);
      expect(service.currentState.isStarted, isTrue);

      // Fire health check (don't await). It will:
      //   1. call node:status (#1) -> degraded -> enters recovery
      //   2. call relay:reconnect -> ok
      //   3. call node:status (#2) -> GATED
      final healthCheckFuture = service.performImmediateHealthCheck();

      // Wait for the 2nd node:status call to appear (gated).
      await _waitForCommandCount(bridge.commandLog, 'node:status', 2);

      // Stop the node while the 2nd node:status is blocked.
      final stopResult = await service.stopNode();
      expect(stopResult, isTrue);
      expect(service.currentState.isStarted, isFalse);

      // Release the gate.
      bridge.nodeStatusGate!.complete();
      await healthCheckFuture;

      // The _stopped guard prevents the health check from resurrecting state.
      expect(service.currentState.isStarted, isFalse);

      service.dispose();
    });
  });

  // =========================================================================
  // Dispose during in-flight reconnect
  // =========================================================================

  group('Dispose during in-flight reconnect', () {
    test(
        'dispose during relay:reconnect does not throw on closed stream controller',
        () async {
      final bridge = _ReconnectGateBridge();
      bridge.relayReconnectGate = Completer<void>();

      bridge.responses['node:start'] = _nodeStartOk();
      bridge.responses['node:status'] = _nodeStatusDegraded();
      bridge.responses['relay:reconnect'] = {'ok': true};
      bridge.responses['inbox:retrieve'] = {'ok': true, 'messages': []};

      final service = P2PServiceImpl(bridge: bridge);

      // Start healthy.
      await service.startNodeCore(_testBase64Key, _testPeerId);

      // Fire health check (enters recovery, blocks on relay:reconnect).
      final healthCheckFuture = service.performImmediateHealthCheck();
      await _waitForCommand(bridge.commandLog, 'relay:reconnect');

      // Dispose the service while relay:reconnect is in-flight.
      // This closes _stateController and _messageController.
      service.dispose();

      // Release the gate. No exception should be thrown because
      // _emitState guards against closed controllers and _stopped
      // causes the health check to bail out.
      bridge.relayReconnectGate!.complete();
      await healthCheckFuture;

      // State remains not-started after dispose.
      expect(service.currentState.isStarted, isFalse);
    });

    test('double dispose is safe (idempotent)', () {
      final bridge = _ReconnectGateBridge();
      bridge.responses['node:start'] = _nodeStartOk();

      final service = P2PServiceImpl(bridge: bridge);

      // First dispose.
      service.dispose();

      // Second dispose should not throw because dispose() guards
      // against already-closed controllers.
      service.dispose();
    });

    test('dispose during initial node:status does not throw', () async {
      final bridge = _ReconnectGateBridge();

      // Gate the 1st node:status call.
      bridge.gateNodeStatusOnCallNumber = 1;
      bridge.nodeStatusGate = Completer<void>();

      bridge.responses['node:start'] = _nodeStartOk();
      bridge.responses['node:status'] = _nodeStatusOk();
      bridge.responses['inbox:retrieve'] = {'ok': true, 'messages': []};

      final service = P2PServiceImpl(bridge: bridge);

      // Start the node.
      await service.startNodeCore(_testBase64Key, _testPeerId);

      // Fire health check — it will gate on the 1st node:status.
      final healthCheckFuture = service.performImmediateHealthCheck();
      await _waitForCommand(bridge.commandLog, 'node:status');

      // Dispose while the node:status is gated.
      service.dispose();

      // Release the gate — should not throw.
      bridge.nodeStatusGate!.complete();
      await healthCheckFuture;

      expect(service.currentState.isStarted, isFalse);
    });
  });

  // =========================================================================
  // Bridge callbacks after stop
  // =========================================================================

  group('Bridge callbacks after stop', () {
    test('bridge callbacks after stopNode are ignored', () async {
      final bridge = _ReconnectGateBridge();
      bridge.responses['node:start'] = _nodeStartOk();
      bridge.responses['node:stop'] = {'ok': true, 'stopped': true};
      bridge.responses['inbox:retrieve'] = {'ok': true, 'messages': []};

      final service = P2PServiceImpl(bridge: bridge);

      // Start the node.
      await service.startNodeCore(_testBase64Key, _testPeerId);
      expect(service.currentState.isStarted, isTrue);

      // Stop the node.
      final stopResult = await service.stopNode();
      expect(stopResult, isTrue);
      expect(service.currentState.isStarted, isFalse);

      // Fire bridge callbacks after stop — they should be ignored.
      bridge.onPeerConnected?.call(
        const ConnectionState(
          peerId: 'peer1',
          multiaddrs: [],
          direction: 'outbound',
          status: 'connected',
        ),
      );
      bridge.onAddressesUpdated?.call(
        ['/ip4/1.2.3.4/tcp/5678'],
        ['/p2p-circuit/new'],
      );

      // State should remain stopped with no connections or circuits.
      expect(service.currentState.isStarted, isFalse);
      expect(service.currentState.connections, isEmpty);
      expect(service.currentState.circuitAddresses, isEmpty);

      service.dispose();
    });
  });

  // =========================================================================
  // stopNode failure reverts _stopped
  // =========================================================================

  group('stopNode failure reverts _stopped guard', () {
    test('stopNode failure reverts _stopped guard so health check can run',
        () async {
      final bridge = _ReconnectGateBridge();
      bridge.responses['node:start'] = _nodeStartOk();
      // node:stop returns failure
      bridge.responses['node:stop'] = {
        'ok': false,
        'errorMessage': 'stop failed',
      };
      bridge.responses['node:status'] = _nodeStatusOk();
      bridge.responses['inbox:retrieve'] = {'ok': true, 'messages': []};

      final service = P2PServiceImpl(bridge: bridge);

      // Start the node.
      await service.startNodeCore(_testBase64Key, _testPeerId);
      expect(service.currentState.isStarted, isTrue);

      // Attempt to stop — it will fail.
      final stopResult = await service.stopNode();
      expect(stopResult, isFalse);

      // The service should still be functional — health check can run.
      // (The _stopped flag was reverted to false on failure.)
      await service.performImmediateHealthCheck();

      // The node is still started because stop failed.
      expect(service.currentState.isStarted, isTrue);

      service.dispose();
    });
  });

  // =========================================================================
  // No leaked recovery loop after stop
  // =========================================================================

  group('No leaked recovery loop after stop', () {
    test('periodic health check does not fire after stopNode', () {
      fakeAsync((async) {
        final bridge = _ReconnectGateBridge();
        bridge.responses['node:start'] = _nodeStartOk();
        bridge.responses['node:status'] = _nodeStatusOk();
        bridge.responses['node:stop'] = {'ok': true, 'stopped': true};
        bridge.responses['inbox:retrieve'] = {'ok': true, 'messages': []};

        final service = P2PServiceImpl(bridge: bridge);

        // Start the node (also calls warmBackground which starts the timer).
        service.startNode(_testBase64Key, _testPeerId);
        async.flushMicrotasks();

        expect(service.currentState.isStarted, isTrue);

        // Note the status call count BEFORE stopping.
        // startNode -> startNodeCore -> warmBackground -> delayed callback etc.
        // may have already triggered some calls.
        final statusCountBeforeStop = bridge.nodeStatusCallCount;

        // Stop the node BEFORE the 30s health check timer fires.
        service.stopNode();
        async.flushMicrotasks();

        expect(service.currentState.isStarted, isFalse);

        final statusCountAfterStop = bridge.nodeStatusCallCount;

        // Advance time well past several health check intervals.
        async.elapse(const Duration(seconds: 120));

        // No new node:status calls should have been made after stop.
        expect(
          bridge.nodeStatusCallCount,
          statusCountAfterStop,
          reason: 'No health check should fire after stopNode cancelled the timer',
        );

        service.dispose();
      });
    });

    test('warmBackground delayed callback is harmless after stop', () {
      fakeAsync((async) {
        final bridge = _ReconnectGateBridge();

        // node:start returns degraded (empty circuits) — this means the 2s
        // delayed callback in warmBackground will fire because
        // circuitAddresses is empty.
        bridge.responses['node:start'] = _nodeStartDegraded();
        bridge.responses['node:status'] = _nodeStatusDegraded();
        bridge.responses['node:stop'] = {'ok': true, 'stopped': true};
        bridge.responses['inbox:retrieve'] = {'ok': true, 'messages': []};

        final service = P2PServiceImpl(bridge: bridge);

        // Start the node. warmBackground schedules a 2s delayed callback.
        service.startNode(_testBase64Key, _testPeerId);
        async.flushMicrotasks();

        expect(service.currentState.isStarted, isTrue);

        // Stop the node BEFORE the 2s delayed callback fires.
        service.stopNode();
        async.flushMicrotasks();

        expect(service.currentState.isStarted, isFalse);

        final statusCountAfterStop = bridge.nodeStatusCallCount;

        // Advance past the 2s delayed callback.
        async.elapse(const Duration(seconds: 5));

        // The _stopped guard prevents the delayed callback from calling
        // _performHealthCheck even if _currentState.isStarted were somehow true.
        expect(
          bridge.nodeStatusCallCount,
          statusCountAfterStop,
          reason:
              'warmBackground 2s delayed callback should not call _performHealthCheck '
              'after stopNode set _stopped = true',
        );

        service.dispose();
      });
    });
  });
}
