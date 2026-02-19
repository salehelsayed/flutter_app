import '../../features/p2p/domain/models/node_state.dart';
import '../../features/p2p/domain/models/chat_message.dart';
import '../../features/p2p/domain/models/discovered_peer.dart';
import '../../features/p2p/domain/models/send_message_result.dart';

/// Abstract interface for P2P networking service.
///
/// This service manages the P2P node lifecycle, peer connections,
/// and messaging. It provides streams for state changes and
/// incoming messages.
abstract class P2PService {
  /// Current node state.
  NodeState get currentState;

  /// Stream of node state changes.
  Stream<NodeState> get stateStream;

  /// Stream of incoming chat messages.
  Stream<ChatMessage> get messageStream;

  /// Start the P2P node with the given identity.
  ///
  /// Parameters:
  ///   - [privateKeyBase64]: Ed25519 private key in BASE64 format
  ///   - [peerId]: The peer ID associated with this identity
  ///
  /// Returns true if the node started successfully.
  Future<bool> startNode(String privateKeyBase64, String peerId);

  /// Start the P2P node (core only — state + relay connection).
  /// Does NOT perform warm tasks like inbox drain or local discovery.
  /// Returns true if the node started successfully.
  Future<bool> startNodeCore(String privateKeyBase64, String peerId);

  /// Run background warm tasks (inbox drain, local discovery, health check).
  /// Call after startNodeCore when the UI is ready.
  /// Safe to call if node is not started (no-op).
  Future<void> warmBackground();

  /// Stop the P2P node.
  ///
  /// Returns true if the node stopped successfully.
  Future<bool> stopNode();

  /// Send a message to a peer.
  ///
  /// Parameters:
  ///   - [peerId]: The target peer ID
  ///   - [message]: The message content
  ///
  /// Returns true if the message was sent successfully.
  Future<bool> sendMessage(String peerId, String message);

  /// Send a message to a peer and return the full result including reply.
  ///
  /// Parameters:
  ///   - [peerId]: The target peer ID
  ///   - [message]: The message content
  ///
  /// Returns a [SendMessageResult] with sent status and optional reply/ack.
  Future<SendMessageResult> sendMessageWithReply(String peerId, String message);

  /// Discover a peer by their ID via rendezvous.
  ///
  /// Parameters:
  ///   - [peerId]: The peer ID to discover
  ///
  /// Returns the discovered peer info, or null if not found.
  Future<DiscoveredPeer?> discoverPeer(String peerId);

  /// Dial (connect to) a peer.
  ///
  /// Parameters:
  ///   - [peerId]: The peer ID to dial
  ///   - [addresses]: Optional list of multiaddrs (discovers if not provided)
  ///
  /// Returns true if connection was established.
  Future<bool> dialPeer(String peerId, {List<String>? addresses});

  /// Store a message in the offline inbox for a peer.
  ///
  /// Parameters:
  ///   - [toPeerId]: The target peer ID
  ///   - [message]: The message content
  ///
  /// Returns true if the message was stored successfully.
  Future<bool> storeInInbox(String toPeerId, String message);

  /// Retrieve messages from the offline inbox.
  ///
  /// Returns a list of message maps from the inbox.
  Future<List<Map<String, dynamic>>> retrieveInbox();

  /// Register an FCM push token with the relay server.
  ///
  /// Parameters:
  ///   - [token]: The FCM device token
  ///   - [platform]: The platform ('ios' or 'android')
  ///
  /// Returns true if the token was registered successfully.
  Future<bool> registerPushToken(String token, String platform);

  /// Trigger an immediate health check (re-dials relay, re-registers FCM).
  Future<void> performImmediateHealthCheck();

  /// Drain any queued offline inbox messages into the message stream.
  Future<void> drainOfflineInbox();

  /// Returns true if the peer is visible on the local WiFi network.
  bool isLocalPeer(String peerId);

  /// Try to send a message to a local peer via WiFi WebSocket.
  /// Returns true if the peer acknowledged receipt.
  Future<bool> sendLocalMessage(String peerId, String message, String fromPeerId);

  /// Dispose of the service and clean up resources.
  void dispose();
}
