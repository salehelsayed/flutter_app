import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../../core/services/p2p_service.dart';
import '../../../../core/utils/flow_event_emitter.dart';
import '../../domain/models/node_state.dart';

/// Connection health derived from NodeState.
enum ConnectionHealth {
  /// Node is started and has circuit relay addresses.
  online,

  /// Node is started but has no circuit relay addresses.
  degraded,

  /// Node is not started.
  offline,
}

/// Derives [ConnectionHealth] from a [NodeState].
///
/// Considers both [relayState] and [circuitAddresses] — if either indicates
/// the relay is healthy, the node is online.  This avoids "Connecting" flashes
/// during the brief window where one signal arrives before the other.
ConnectionHealth healthFromState(NodeState state) {
  if (!state.isStarted) return ConnectionHealth.offline;
  if (state.relayState == 'online' || state.circuitAddresses.isNotEmpty) {
    return ConnectionHealth.online;
  }
  return ConnectionHealth.degraded;
}

/// How long we stay "Online" before visually downgrading to "Connecting".
/// Absorbs transient relay churn (address rotation, reconnect cycles).
const _downgradeDelay = Duration(seconds: 3);

/// A compact indicator showing the P2P connection status.
///
/// Displays one of three states:
/// - "Online" (green) — node started with circuit relay
/// - "Connecting" (amber) — node started but no relay yet
/// - "Offline" (grey) — node not started
///
/// Downgrades from Online → Connecting are delayed by [_downgradeDelay]
/// so that brief relay reconnections are invisible to the user.
class ConnectionStatusIndicator extends StatefulWidget {
  final P2PService p2pService;

  const ConnectionStatusIndicator({
    super.key,
    required this.p2pService,
  });

  @override
  State<ConnectionStatusIndicator> createState() =>
      _ConnectionStatusIndicatorState();
}

class _ConnectionStatusIndicatorState extends State<ConnectionStatusIndicator> {
  late ConnectionHealth _displayedHealth;
  late int _connectionCount;
  StreamSubscription<NodeState>? _sub;
  Timer? _downgradeTimer;

  /// §24: Timestamp when the last stateStream event arrived.
  DateTime? _lastStateReceivedAt;

  @override
  void initState() {
    super.initState();
    final initial = widget.p2pService.currentState;
    _displayedHealth = healthFromState(initial);
    _connectionCount = initial.connections.length;

    _sub = widget.p2pService.stateStream.listen(_onState);
  }

  void _onState(NodeState state) {
    final stateReceivedAt = DateTime.now();
    _lastStateReceivedAt = stateReceivedAt;
    final incoming = healthFromState(state);
    final count = state.connections.length;

    if (incoming == _displayedHealth) {
      // Health unchanged — just update connection count if needed.
      _downgradeTimer?.cancel();
      _downgradeTimer = null;
      if (count != _connectionCount) {
        setState(() => _connectionCount = count);
      }
      return;
    }

    // Upgrade (to online): apply immediately + emit widget timing.
    if (incoming == ConnectionHealth.online) {
      _downgradeTimer?.cancel();
      _downgradeTimer = null;

      final widgetTransitionMs =
          DateTime.now().difference(stateReceivedAt).inMilliseconds;
      emitFlowEvent(
        layer: 'FL',
        event: 'TIME_TO_ONLINE_BADGE_WIDGET',
        details: {
          'widgetTransitionMs': widgetTransitionMs,
          'previousHealth': _displayedHealth.name,
        },
      );

      setState(() {
        _displayedHealth = incoming;
        _connectionCount = count;
      });
      return;
    }

    // Downgrade from online → degraded: delay so transient relay churn
    // is invisible.  If we're already degraded/offline, apply immediately.
    if (_displayedHealth == ConnectionHealth.online &&
        incoming == ConnectionHealth.degraded) {
      _downgradeTimer ??= Timer(_downgradeDelay, () {
        _downgradeTimer = null;
        if (mounted) {
          setState(() {
            _displayedHealth = incoming;
            _connectionCount = count;
          });
        }
      });
      return;
    }

    // All other transitions (e.g. degraded → offline, online → offline):
    // apply immediately.
    _downgradeTimer?.cancel();
    _downgradeTimer = null;
    setState(() {
      _displayedHealth = incoming;
      _connectionCount = count;
    });
  }

  @override
  void dispose() {
    _downgradeTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final health = _displayedHealth;
    final connectionCount = _connectionCount;

    final Color baseColor;
    final Color textColor;
    final String label;

    switch (health) {
      case ConnectionHealth.online:
        baseColor = Colors.green;
        textColor = Colors.green[300]!;
        label = 'Online';
      case ConnectionHealth.degraded:
        baseColor = Colors.amber;
        textColor = Colors.amber[300]!;
        label = 'Connecting';
      case ConnectionHealth.offline:
        baseColor = Colors.grey;
        textColor = Colors.grey[400]!;
        label = 'Offline';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: baseColor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: baseColor.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: baseColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (kDebugMode &&
              health == ConnectionHealth.online &&
              connectionCount > 0) ...[
            const SizedBox(width: 4),
            Text(
              '($connectionCount)',
              style: TextStyle(
                color: Colors.green[300]?.withValues(alpha: 0.7),
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
