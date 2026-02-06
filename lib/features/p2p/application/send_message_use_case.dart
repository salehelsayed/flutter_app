import '../../../core/services/p2p_service.dart';
import '../../../core/utils/flow_event_emitter.dart';

/// Result of sending a message.
enum SendMessageResult {
  /// Message sent successfully.
  success,

  /// Node is not running.
  nodeNotRunning,

  /// Peer not found or not connected.
  peerNotFound,

  /// Error sending the message.
  error,
}

/// Use case for sending a message to a peer.
Future<SendMessageResult> sendP2PMessage({
  required P2PService p2pService,
  required String peerId,
  required String message,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_SEND_MESSAGE_USE_CASE_BEGIN',
    details: {'peerId': peerId, 'messageLength': message.length},
  );

  try {
    // Check if node is running
    if (!p2pService.currentState.isStarted) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SEND_MESSAGE_USE_CASE_NODE_NOT_RUNNING',
        details: {},
      );
      return SendMessageResult.nodeNotRunning;
    }

    // Send the message
    final success = await p2pService.sendMessage(peerId, message);

    if (success) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SEND_MESSAGE_USE_CASE_SUCCESS',
        details: {'peerId': peerId},
      );
      return SendMessageResult.success;
    } else {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SEND_MESSAGE_USE_CASE_ERROR',
        details: {},
      );
      return SendMessageResult.error;
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_SEND_MESSAGE_USE_CASE_EXCEPTION',
      details: {'error': e.toString()},
    );
    return SendMessageResult.error;
  }
}
