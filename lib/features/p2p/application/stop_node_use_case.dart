import '../../../core/services/p2p_service.dart';
import '../../../core/utils/flow_event_emitter.dart';

/// Result of stopping the P2P node.
enum StopNodeResult {
  /// Node stopped successfully.
  success,

  /// Node was not running.
  notRunning,

  /// Error stopping the node.
  error,
}

/// Use case for stopping the P2P node.
Future<StopNodeResult> stopP2PNode({
  required P2PService p2pService,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_STOP_NODE_USE_CASE_BEGIN',
    details: {},
  );

  try {
    // Check if node is running
    if (!p2pService.currentState.isStarted) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_STOP_NODE_USE_CASE_NOT_RUNNING',
        details: {},
      );
      return StopNodeResult.notRunning;
    }

    // Stop the node
    final success = await p2pService.stopNode();

    if (success) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_STOP_NODE_USE_CASE_SUCCESS',
        details: {},
      );
      return StopNodeResult.success;
    } else {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_STOP_NODE_USE_CASE_ERROR',
        details: {},
      );
      return StopNodeResult.error;
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_STOP_NODE_USE_CASE_EXCEPTION',
      details: {'error': e.toString()},
    );
    return StopNodeResult.error;
  }
}
