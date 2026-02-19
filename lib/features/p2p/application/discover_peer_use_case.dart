import '../../../core/services/p2p_service.dart';
import '../../../core/utils/flow_event_emitter.dart';
import '../domain/models/discovered_peer.dart';

/// Result of discovering a peer.
enum DiscoverPeerResult {
  /// Peer discovered successfully.
  success,

  /// Node is not running.
  nodeNotRunning,

  /// Peer not found on rendezvous.
  notFound,

  /// Error during discovery.
  error,
}

/// Use case for discovering a peer via rendezvous.
///
/// Returns a tuple of (result, peer) where peer is non-null on success.
Future<(DiscoverPeerResult, DiscoveredPeer?)> discoverP2PPeer({
  required P2PService p2pService,
  required String peerId,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_DISCOVER_PEER_USE_CASE_BEGIN',
    details: {'peerId': peerId},
  );

  try {
    // Check if node is running
    if (!p2pService.currentState.isStarted) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_DISCOVER_PEER_USE_CASE_NODE_NOT_RUNNING',
        details: {},
      );
      return (DiscoverPeerResult.nodeNotRunning, null);
    }

    // Discover the peer
    final peer = await p2pService.discoverPeer(peerId);

    if (peer != null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_DISCOVER_PEER_USE_CASE_SUCCESS',
        details: {'peerId': peerId, 'addressCount': peer.addresses.length},
      );
      return (DiscoverPeerResult.success, peer);
    } else {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_DISCOVER_PEER_USE_CASE_NOT_FOUND',
        details: {'peerId': peerId},
      );
      return (DiscoverPeerResult.notFound, null);
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_DISCOVER_PEER_USE_CASE_EXCEPTION',
      details: {'error': e.toString()},
    );
    return (DiscoverPeerResult.error, null);
  }
}

/// Use case for dialing (connecting to) a peer.
///
/// This will discover the peer if addresses are not provided.
Future<bool> dialP2PPeer({
  required P2PService p2pService,
  required String peerId,
  List<String>? addresses,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_DIAL_PEER_USE_CASE_BEGIN',
    details: {'peerId': peerId},
  );

  try {
    // Check if node is running
    if (!p2pService.currentState.isStarted) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_DIAL_PEER_USE_CASE_NODE_NOT_RUNNING',
        details: {},
      );
      return false;
    }

    // Dial the peer
    final success = await p2pService.dialPeer(peerId, addresses: addresses);

    if (success) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_DIAL_PEER_USE_CASE_SUCCESS',
        details: {'peerId': peerId},
      );
    } else {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_DIAL_PEER_USE_CASE_FAILED',
        details: {'peerId': peerId},
      );
    }

    return success;
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_DIAL_PEER_USE_CASE_EXCEPTION',
      details: {'error': e.toString()},
    );
    return false;
  }
}
