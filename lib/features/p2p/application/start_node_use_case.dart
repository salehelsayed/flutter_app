import '../../../core/services/p2p_service.dart';
import '../../../core/utils/flow_event_emitter.dart';
import '../../identity/domain/repositories/identity_repository.dart';

/// Result of starting the P2P node.
enum StartNodeResult {
  /// Node started successfully.
  success,

  /// No identity found - cannot start node.
  noIdentity,

  /// Bridge or P2P layer error.
  bridgeError,

  /// Connection error (relay unavailable, etc).
  connectionError,
}

/// Use case for starting the P2P node.
///
/// This use case:
/// 1. Loads the user's identity from the repository
/// 2. Starts the P2P node with the identity's private key
/// 3. Auto-registers on rendezvous for discoverability
Future<StartNodeResult> startP2PNode({
  required IdentityRepository identityRepo,
  required P2PService p2pService,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_START_NODE_USE_CASE_BEGIN',
    details: {},
  );

  try {
    // Load identity from repository
    final identity = await identityRepo.loadIdentity();

    if (identity == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_START_NODE_USE_CASE_NO_IDENTITY',
        details: {},
      );
      return StartNodeResult.noIdentity;
    }

    // Start the P2P node
    // The service handles key conversion (BASE64 -> HEX) internally
    final success = await p2pService.startNode(
      identity.privateKey,
      identity.peerId,
    );

    if (success) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_START_NODE_USE_CASE_SUCCESS',
        details: {'peerId': identity.peerId},
      );
      return StartNodeResult.success;
    } else {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_START_NODE_USE_CASE_BRIDGE_ERROR',
        details: {},
      );
      return StartNodeResult.bridgeError;
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_START_NODE_USE_CASE_EXCEPTION',
      details: {'error': e.toString()},
    );
    return StartNodeResult.bridgeError;
  }
}
