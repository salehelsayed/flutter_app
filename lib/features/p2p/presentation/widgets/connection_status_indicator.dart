import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import '../../../../core/services/p2p_service.dart';
import '../../../../core/utils/flow_event_emitter.dart';
import '../../domain/models/node_state.dart';

/// Legacy relay-health helper derived from [NodeState].
///
/// Kept for existing transport benchmarks and integration tests until the
/// heavier Session 3 acceptance surfaces migrate to the Phase 6 contract.
enum ConnectionHealth {
  /// Node is started and has circuit relay addresses.
  online,

  /// Node is started but has no circuit relay addresses.
  degraded,

  /// Node is not started.
  offline,
}

/// Derives relay-only [ConnectionHealth] from a [NodeState].
ConnectionHealth healthFromState(NodeState state) {
  if (!state.isStarted) return ConnectionHealth.offline;
  if (state.relayState == 'online' || state.circuitAddresses.isNotEmpty) {
    return ConnectionHealth.online;
  }
  return ConnectionHealth.degraded;
}

bool _isReadyBadgeState(BadgeReadinessState state) {
  return state == BadgeReadinessState.online ||
      state == BadgeReadinessState.onlineDotted;
}

ConnectionHealth _legacyHealthForBadgeState(BadgeReadinessState state) {
  return switch (state) {
    BadgeReadinessState.offline => ConnectionHealth.offline,
    BadgeReadinessState.connecting => ConnectionHealth.degraded,
    BadgeReadinessState.online ||
    BadgeReadinessState.onlineDotted => ConnectionHealth.online,
  };
}

String _labelForBadgeState(BadgeReadinessState state) {
  return switch (state) {
    BadgeReadinessState.offline => 'Offline',
    BadgeReadinessState.connecting => 'Connecting',
    BadgeReadinessState.online => 'Online',
    BadgeReadinessState.onlineDotted => 'Online.',
  };
}

String _semanticsLabelForBadgeState(BadgeReadinessState state) {
  return switch (state) {
    BadgeReadinessState.offline => 'offline',
    BadgeReadinessState.connecting => 'connecting',
    BadgeReadinessState.online =>
      'online, send and inbox ready, relay reservation pending',
    BadgeReadinessState.onlineDotted =>
      'online, send and inbox ready, relay reservation ready',
  };
}

/// A compact indicator showing the P2P connection status.
///
/// Displays one of four states from the service-owned Phase 6 contract:
/// - "Offline"
/// - "Connecting"
/// - "Online"
/// - "Online."
class ConnectionStatusIndicator extends StatefulWidget {
  final P2PService p2pService;

  const ConnectionStatusIndicator({super.key, required this.p2pService});

  @override
  State<ConnectionStatusIndicator> createState() =>
      _ConnectionStatusIndicatorState();
}

class _ConnectionStatusIndicatorState extends State<ConnectionStatusIndicator> {
  late BadgeReadinessState _displayedBadgeState;
  late int _connectionCount;
  StreamSubscription<NodeState>? _sub;

  @override
  void initState() {
    super.initState();
    final initial = widget.p2pService.currentState;
    _displayedBadgeState = initial.badgeReadinessState;
    _connectionCount = initial.connections.length;

    _sub = widget.p2pService.stateStream.listen(_onState);
  }

  void _onState(NodeState state) {
    final incoming = state.badgeReadinessState;
    final count = state.connections.length;

    if (incoming == _displayedBadgeState) {
      if (count != _connectionCount) {
        setState(() => _connectionCount = count);
      }
      return;
    }

    final wasReady = _isReadyBadgeState(_displayedBadgeState);
    final isReady = _isReadyBadgeState(incoming);
    if (isReady && !wasReady) {
      emitFlowEvent(
        layer: 'FL',
        event: 'TIME_TO_ONLINE_BADGE_WIDGET',
        details: {
          'widgetTransitionMs': 0,
          'previousHealth': _legacyHealthForBadgeState(
            _displayedBadgeState,
          ).name,
        },
      );
    }

    setState(() {
      _displayedBadgeState = incoming;
      _connectionCount = count;
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final badgeState = _displayedBadgeState;
    final connectionCount = _connectionCount;
    final readableColors = context.backgroundReadableColors;
    final isLightSurface = readableColors.isLightSurface;

    final Color baseColor;
    final Color textColor;
    switch (badgeState) {
      case BadgeReadinessState.online:
      case BadgeReadinessState.onlineDotted:
        baseColor = Colors.green;
        textColor = isLightSurface
            ? const Color(0xFF157A39)
            : Colors.green[300]!;
      case BadgeReadinessState.connecting:
        baseColor = Colors.amber;
        textColor = isLightSurface
            ? const Color(0xFF8A5D00)
            : Colors.amber[300]!;
      case BadgeReadinessState.offline:
        baseColor = Colors.grey;
        textColor = isLightSurface
            ? readableColors.textMuted
            : Colors.grey[400]!;
    }
    final label = _labelForBadgeState(badgeState);
    final semanticsLabel = _semanticsLabelForBadgeState(badgeState);

    return Semantics(
      container: true,
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: baseColor.withValues(alpha: isLightSurface ? 0.12 : 0.2),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: baseColor.withValues(alpha: isLightSurface ? 0.32 : 0.4),
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
                  _isReadyBadgeState(badgeState) &&
                  connectionCount > 0) ...[
                const SizedBox(width: 4),
                Text(
                  '($connectionCount)',
                  style: TextStyle(
                    color: textColor.withValues(alpha: 0.7),
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
