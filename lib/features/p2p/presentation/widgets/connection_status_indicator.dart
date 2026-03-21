import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../../core/services/p2p_service.dart';
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
ConnectionHealth healthFromState(NodeState state) {
  if (!state.isStarted) return ConnectionHealth.offline;
  if (state.circuitAddresses.isNotEmpty) return ConnectionHealth.online;
  return ConnectionHealth.degraded;
}

/// A compact indicator showing the P2P connection status.
///
/// Displays one of three states:
/// - "Online" (green) — node started with circuit relay
/// - "Connecting" (amber) — node started but no relay yet
/// - "Offline" (grey) — node not started
class ConnectionStatusIndicator extends StatelessWidget {
  final P2PService p2pService;

  const ConnectionStatusIndicator({
    super.key,
    required this.p2pService,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<NodeState>(
      stream: p2pService.stateStream,
      initialData: p2pService.currentState,
      builder: (context, snapshot) {
        final state = snapshot.data ?? NodeState.stopped;
        final health = healthFromState(state);
        final connectionCount = state.connections.length;

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
              if (kDebugMode && health == ConnectionHealth.online && connectionCount > 0) ...[
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
      },
    );
  }
}
