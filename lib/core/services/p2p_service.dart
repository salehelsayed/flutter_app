import '../../features/p2p/domain/models/node_state.dart';
import '../../features/p2p/domain/models/chat_message.dart';
import '../../features/p2p/domain/models/discovered_peer.dart';
import '../../features/p2p/domain/models/send_message_result.dart';

/// Result of a relay probe attempt.
enum RelayProbeResult {
  connected, // Relay circuit established — peer is online
  noReservation, // Peer has no reservation — definitely offline
  error, // Network/bridge error — unknown state, fall through to dial
}

/// Narrow additive hook for Session 1 readiness-proof ownership.
///
/// Kept separate from [P2PService] so existing fake services do not all need
/// to grow Phase 6 behavior before the rollout is complete.
abstract interface class ReadinessProofRecorder {
  /// Whether a caller-owned resume assessment window is already active.
  bool get hasPendingResumeStarted;

  /// Marks the beginning of a resume assessment window.
  void markResumeStarted();

  /// Clears any outstanding resume assessment state.
  void clearResumeStarted();

  /// Starts a new proof window because the current transport session was reset.
  void noteTransportSessionReset({required String trigger});

  /// Records the first truthful successful send proof for the current window.
  void recordSuccessfulSendProof({
    required String source,
    required String trigger,
    String? sendPath,
  });
}

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
  ///   - [timeoutMs]: Optional timeout in milliseconds for stream write + ACK read
  ///
  /// Returns a [SendMessageResult] with sent status and optional reply/ack.
  Future<SendMessageResult> sendMessageWithReply(
    String peerId,
    String message, {
    int? timeoutMs,
  });

  /// Discover a peer by their ID via rendezvous.
  ///
  /// Parameters:
  ///   - [peerId]: The peer ID to discover
  ///   - [timeoutMs]: Optional discovery timeout in milliseconds
  ///
  /// Returns the discovered peer info, or null if not found.
  Future<DiscoveredPeer?> discoverPeer(String peerId, {int? timeoutMs});

  /// Dial (connect to) a peer.
  ///
  /// Parameters:
  ///   - [peerId]: The peer ID to dial
  ///   - [addresses]: Optional list of multiaddrs (discovers if not provided)
  ///   - [timeoutMs]: Optional dial timeout in milliseconds
  ///
  /// Returns true if connection was established.
  Future<bool> dialPeer(
    String peerId, {
    List<String>? addresses,
    int? timeoutMs,
  });

  /// Store a message in the offline inbox for a peer.
  ///
  /// Parameters:
  ///   - [toPeerId]: The target peer ID
  ///   - [message]: The message content
  ///
  /// Returns true if the message was stored successfully.
  Future<bool> storeInInbox(String toPeerId, String message, {int? timeoutMs});

  /// Retrieve messages from the offline inbox.
  ///
  /// Parameters:
  ///   - [timeoutMs]: Optional retrieval timeout in milliseconds
  ///
  /// Returns a list of message maps from the inbox.
  Future<List<Map<String, dynamic>>> retrieveInbox({int? timeoutMs});

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

  /// Returns true if we already have an active connection to the peer.
  ///
  /// Checks the current [NodeState.connections] for a matching peer with
  /// status 'connected'. Used by the send fast path to skip discover/dial.
  bool isConnectedToPeer(String peerId);

  /// Probe whether a peer is reachable via the relay circuit.
  ///
  /// Returns [RelayProbeResult.connected] if the relay circuit was established,
  /// [RelayProbeResult.noReservation] if the peer has no relay reservation
  /// (definitely offline), or [RelayProbeResult.error] on network/bridge errors.
  Future<RelayProbeResult> probeRelay(String peerId);

  /// Returns true if the peer is visible on the local WiFi network.
  bool isLocalPeer(String peerId);

  /// Try to send a message to a local peer via WiFi WebSocket.
  /// Returns true if the peer acknowledged receipt.
  Future<bool> sendLocalMessage(
    String peerId,
    String message,
    String fromPeerId, {
    int? timeoutMs,
  });

  /// Send a media file to a local peer via WiFi HTTP PUT.
  /// Returns true if uploaded and SHA-256 verified by receiver.
  Future<bool> sendLocalMedia({
    required String peerId,
    required String filePath,
    required String mime,
    required String mediaId,
    required String fromPeerId,
    int? durationMs,
    List<double>? waveform,
    String? filename,
  });

  /// The last recovery method used ('in_place', 'watchdog_restart', or null).
  /// Exposed so that resume handlers can decide whether to rejoin group topics.
  String? get lastRecoveryMethod;

  /// Dispose of the service and clean up resources.
  void dispose();
}
