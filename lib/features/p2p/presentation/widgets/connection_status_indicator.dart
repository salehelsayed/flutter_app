import 'package:flutter/material.dart';
import '../../../../core/services/p2p_service.dart';
import '../../domain/models/node_state.dart';

/// A compact indicator showing the P2P connection status.
///
/// Displays either "Online" (green) when the node is started,
/// or "Offline" (grey) when stopped.
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
        final isOnline = state.isStarted;
        final connectionCount = state.connections.length;

        final baseColor = isOnline ? Colors.green : Colors.grey;

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
                isOnline ? 'Online' : 'Offline',
                style: TextStyle(
                  color: isOnline ? Colors.green[300] : Colors.grey[400],
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (isOnline && connectionCount > 0) ...[
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
