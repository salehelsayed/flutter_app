import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart';

const testBase64Key = 'AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA=';
const testPeerId = '12D3KooWTestPeerId';
const relayPeerId =
    '12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g';

/// Simulates the Go bridge through connect → background → resume phases.
///
/// Phase progression:
///   [online]  → node:status returns circuit addresses
///   [degraded]→ node:status returns empty circuit addresses (relay dropped)
///   [recovering] → peer:dial succeeds but immediate status still degraded
///   [online]  → after simulated delay, addresses:updated fires
class LifecycleBridge implements Bridge {
  bool _initialized = false;

  /// Current phase of the simulated lifecycle.
  String phase = 'startup';

  /// Number of node:status calls in each phase (for debugging).
  int nodeStatusCallCount = 0;
  int peerDialCallCount = 0;
  int relayReconnectCallCount = 0;

  /// How many total recovery health check cycles before circuit appears.
  /// Simulates the real-world delay between first dial and circuit reservation.
  int pollsUntilCircuitReady = 2;
  int _recoveryAttempts = 0;

  /// Track whether addresses:updated push was fired during recovery.
  bool addressesPushFired = false;

  /// If true, simulate the EventChannel being dead (no push events).
  bool eventChannelDead = false;

  /// If true, checkHealth() returns false (bridge unresponsive).
  bool bridgeUnhealthy = false;

  /// If true, inbox:retrieve returns an error response.
  bool inboxRetrieveFails = false;

  /// If true, node:start returns "already started" error, then node:status
  /// returns the current phase. Use to test the resync branch.
  bool simulateAlreadyStarted = false;

  /// If set, relay:reconnect awaits this delay before responding.
  Duration? reconnectDelay;

  /// Set to true during reconnectDelay — makes message:send return error.
  bool isRestarting = false;

  /// Count of message:send calls.
  int messageSendCallCount = 0;

  // -- Fault-injection hooks --

  /// When true, relay:reconnect returns an error response.
  bool relayReservationLost = false;

  /// When true, peer:dial returns an error response.
  bool peerDialFails = false;

  /// Artificial delay on node:status responses.
  Duration? nodeStatusDelay;

  /// When true, node:start returns an error response.
  bool nodeStartFails = false;

  /// First N message:send calls return failure (independent of isRestarting).
  int messageSendFailCount = 0;
  int _messageSendAttempts = 0;

  // -- Phase 5: Structured recovery response fields --

  /// When true, relay:reconnect returns structured result fields
  /// (`recoveryMethod`, `refreshed`) instead of bare `{ok: true}`.
  bool useStructuredRecoveryResponse = false;

  /// The recovery method reported in structured relay:reconnect response.
  /// 'in_place_refresh' or 'watchdog_restart'.
  String structuredRecoveryMethod = 'in_place_refresh';

  /// Number of consecutive relay:reconnect failures before the bridge
  /// returns a 'watchdog_restart' result. Used for escalation testing.
  int refreshFailuresBeforeWatchdog = 3;
  int _consecutiveRefreshFailures = 0;

  /// When true, relay:reconnect fails (simulating refresh failure)
  /// until [refreshFailuresBeforeWatchdog] is reached, then succeeds
  /// with 'watchdog_restart' method.
  bool simulateRefreshEscalation = false;

  @override
  bool get isInitialized => _initialized;

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
  void Function(Map<String, dynamic>)? onGroupReactionReceived;

  @override
  Future<void> initialize() async {
    _initialized = true;
  }

  @override
  Future<bool> checkHealth() async {
    if (bridgeUnhealthy) return false;
    return true;
  }

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
        return jsonEncode(_nodeStartResponse());
      case 'node:status':
        nodeStatusCallCount++;
        if (nodeStatusDelay != null) {
          await Future.delayed(nodeStatusDelay!);
        }
        return jsonEncode(_nodeStatusResponse());
      case 'peer:dial':
        peerDialCallCount++;
        return jsonEncode(_peerDialResponse(request));
      case 'relay:reconnect':
        relayReconnectCallCount++;
        return jsonEncode(await _relayReconnectResponse());
      case 'node:stop':
        return jsonEncode({'ok': true, 'stopped': true});
      case 'inbox:retrieve':
        return jsonEncode(_inboxRetrieveResponse());
      case 'message:send':
        messageSendCallCount++;
        return jsonEncode(_messageSendResponse());
      default:
        return jsonEncode({'ok': true});
    }
  }

  Map<String, dynamic> _nodeStartResponse() {
    if (nodeStartFails) {
      return {
        'ok': false,
        'errorMessage': 'node start failed (injected fault)',
      };
    }

    if (simulateAlreadyStarted) {
      return {
        'ok': false,
        'errorMessage': 'node already started',
      };
    }

    // Phase-aware: if phase is 'degraded', start succeeds but with no
    // circuits yet (simulates fresh start before relay connects).
    if (phase == 'degraded') {
      return {
        'ok': true,
        'peerId': testPeerId,
        'isStarted': true,
        'listenAddresses': ['/ip4/127.0.0.1/tcp/1234'],
        'circuitAddresses': <String>[],
        'connections': <Map<String, dynamic>>[],
      };
    }

    phase = 'online';
    return {
      'ok': true,
      'peerId': testPeerId,
      'isStarted': true,
      'listenAddresses': ['/ip4/127.0.0.1/tcp/1234'],
      'circuitAddresses': ['/p2p-circuit/p2p/$relayPeerId'],
      'connections': <Map<String, dynamic>>[],
    };
  }

  Map<String, dynamic> _nodeStatusResponse() {
    switch (phase) {
      case 'online':
        return {
          'ok': true,
          'peerId': testPeerId,
          'isStarted': true,
          'listenAddresses': ['/ip4/127.0.0.1/tcp/1234'],
          'circuitAddresses': ['/p2p-circuit/p2p/$relayPeerId'],
          'connections': <Map<String, dynamic>>[],
        };

      case 'degraded':
        return {
          'ok': true,
          'peerId': testPeerId,
          'isStarted': true,
          'listenAddresses': ['/ip4/127.0.0.1/tcp/1234'],
          'circuitAddresses': <String>[],
          'connections': <Map<String, dynamic>>[],
        };

      case 'recovering':
        _recoveryAttempts++;
        if (_recoveryAttempts >= pollsUntilCircuitReady) {
          phase = 'online';

          if (!eventChannelDead && !addressesPushFired) {
            addressesPushFired = true;
            _fireAddressesUpdated();
          }

          return {
            'ok': true,
            'peerId': testPeerId,
            'isStarted': true,
            'listenAddresses': ['/ip4/127.0.0.1/tcp/1234'],
            'circuitAddresses': ['/p2p-circuit/p2p/$relayPeerId'],
            'connections': <Map<String, dynamic>>[],
          };
        }

        return {
          'ok': true,
          'peerId': testPeerId,
          'isStarted': true,
          'listenAddresses': ['/ip4/127.0.0.1/tcp/1234'],
          'circuitAddresses': <String>[],
          'connections': <Map<String, dynamic>>[],
        };

      default:
        return {'ok': false, 'isStarted': false};
    }
  }

  Map<String, dynamic> _peerDialResponse(Map<String, dynamic> request) {
    if (peerDialFails) {
      return {
        'ok': false,
        'connected': false,
        'errorMessage': 'peer dial failed (injected fault)',
      };
    }
    if (phase == 'degraded') {
      phase = 'recovering';
    }
    return {'ok': true, 'connected': true, 'peerId': relayPeerId};
  }

  /// Simulates relay:reconnect which in production restarts the node.
  Future<Map<String, dynamic>> _relayReconnectResponse() async {
    if (relayReservationLost) {
      // Phase 5: escalation simulation — after enough failures, switch to
      // watchdog restart and succeed.
      if (simulateRefreshEscalation) {
        _consecutiveRefreshFailures++;
        if (_consecutiveRefreshFailures >= refreshFailuresBeforeWatchdog) {
          // Watchdog kicks in and succeeds
          relayReservationLost = false;
          if (phase == 'degraded') {
            phase = 'recovering';
          }
          return {
            'ok': true,
            if (useStructuredRecoveryResponse) ...{
              'recoveryMethod': 'watchdog_restart',
              'refreshed': true,
            },
          };
        }
      }
      return {
        'ok': false,
        'errorMessage': 'relay reservation lost (injected fault)',
      };
    }
    if (phase == 'degraded') {
      phase = 'recovering';
    }
    if (reconnectDelay != null) {
      isRestarting = true;
      await Future.delayed(reconnectDelay!);
      isRestarting = false;
    }

    // Phase 5: structured recovery response
    if (useStructuredRecoveryResponse) {
      _consecutiveRefreshFailures = 0;
      return {
        'ok': true,
        'recoveryMethod': structuredRecoveryMethod,
        'refreshed': true,
      };
    }
    return {'ok': true};
  }

  Map<String, dynamic> _inboxRetrieveResponse() {
    if (inboxRetrieveFails) {
      return {'ok': false, 'errorMessage': 'inbox unavailable'};
    }
    return {'ok': true, 'messages': <dynamic>[]};
  }

  Map<String, dynamic> _messageSendResponse() {
    if (isRestarting) {
      return {'ok': false, 'errorMessage': 'node restarting'};
    }
    _messageSendAttempts++;
    if (_messageSendAttempts <= messageSendFailCount) {
      return {
        'ok': false,
        'errorMessage': 'message send failed (injected fault, attempt $_messageSendAttempts)',
      };
    }
    return {'ok': true, 'sent': true, 'reply': 'ack'};
  }

  void _fireAddressesUpdated() {
    onAddressesUpdated?.call(
      ['/ip4/127.0.0.1/tcp/1234'],
      ['/p2p-circuit/p2p/$relayPeerId'],
    );
  }

  // -- Test helpers --

  /// Simulate backgrounding: relay drops, circuit addresses disappear.
  void simulateBackground() {
    phase = 'degraded';
    addressesPushFired = false;
    _recoveryAttempts = 0;
    _recoveryStartedAt = null;
    _lastRecoveryDuration = null;
  }

  /// Alias for [simulateBackground] — more descriptive when testing relay drop.
  void simulateRelayDrop() => simulateBackground();

  /// Simulate WiFi becoming available (no-op on bridge itself; callers
  /// should also add target to [FakeP2PService.localPeers]).
  /// Sets phase to 'online' if it was already online (WiFi is additive).
  void simulateWifiAvailable() {
    // WiFi availability doesn't change the relay/circuit state.
    // It's tracked at the P2PService level via localPeers.
  }

  /// Simulate WiFi being lost (no-op on bridge itself; callers
  /// should also remove target from [FakeP2PService.localPeers]).
  void simulateWifiLost() {
    // WiFi loss doesn't change the relay/circuit state.
    // It's tracked at the P2PService level via localPeers.
  }

  /// Simulate recovery completing: transitions to 'online' and fires
  /// onAddressesUpdated. Records recovery duration if [_recoveryStartedAt]
  /// was set.
  void simulateRecoveryComplete() {
    phase = 'online';
    addressesPushFired = true;

    if (_recoveryStartedAt != null) {
      _lastRecoveryDuration = DateTime.now().difference(_recoveryStartedAt!);
      _recoveryStartedAt = null;
    }

    _fireAddressesUpdated();
  }

  // -- Recovery timing --

  DateTime? _recoveryStartedAt;
  Duration? _lastRecoveryDuration;

  /// Start the recovery timer. Call this when simulating resume to measure
  /// how long recovery takes.
  void markRecoveryStart() {
    _recoveryStartedAt = DateTime.now();
  }

  /// Duration of the last completed recovery (from [markRecoveryStart] to
  /// [simulateRecoveryComplete]). Null if no recovery has completed.
  Duration? get lastRecoveryDuration => _lastRecoveryDuration;

  /// Simulate relay reservation being lost: sets fault flag and moves to degraded.
  void simulateRelayReservationLost() {
    relayReservationLost = true;
    phase = 'degraded';
    addressesPushFired = false;
    _recoveryAttempts = 0;
  }

  /// Simulate full recovery: resets all faults, moves to online, fires addresses updated.
  void simulateFullRecovery() {
    relayReservationLost = false;
    peerDialFails = false;
    nodeStartFails = false;
    nodeStatusDelay = null;
    messageSendFailCount = 0;
    _messageSendAttempts = 0;
    bridgeUnhealthy = false;
    inboxRetrieveFails = false;
    isRestarting = false;

    phase = 'online';
    addressesPushFired = true;
    _fireAddressesUpdated();
  }

  /// Simulate a relay-state push event showing degradation.
  /// This fires onAddressesUpdated with empty circuit addresses,
  /// simulating Go pushing a relay:state event when the relay connection drops.
  void simulateRelayStatePush({bool degraded = true}) {
    if (degraded) {
      phase = 'degraded';
      addressesPushFired = false;
      _recoveryAttempts = 0;
      onAddressesUpdated?.call(
        ['/ip4/127.0.0.1/tcp/1234'],
        <String>[], // empty = relay lost
      );
    } else {
      phase = 'online';
      addressesPushFired = true;
      _fireAddressesUpdated();
    }
  }

  /// Resets all counters and fault flags to defaults.
  void reset() {
    phase = 'startup';
    nodeStatusCallCount = 0;
    peerDialCallCount = 0;
    relayReconnectCallCount = 0;
    messageSendCallCount = 0;
    pollsUntilCircuitReady = 2;
    _recoveryAttempts = 0;
    addressesPushFired = false;
    eventChannelDead = false;
    bridgeUnhealthy = false;
    inboxRetrieveFails = false;
    simulateAlreadyStarted = false;
    reconnectDelay = null;
    isRestarting = false;

    // Fault-injection hooks
    relayReservationLost = false;
    peerDialFails = false;
    nodeStatusDelay = null;
    nodeStartFails = false;
    messageSendFailCount = 0;
    _messageSendAttempts = 0;

    // Phase 5: structured recovery
    useStructuredRecoveryResponse = false;
    structuredRecoveryMethod = 'in_place_refresh';
    refreshFailuresBeforeWatchdog = 3;
    _consecutiveRefreshFailures = 0;
    simulateRefreshEscalation = false;

    // Recovery timing
    _recoveryStartedAt = null;
    _lastRecoveryDuration = null;
  }
}

