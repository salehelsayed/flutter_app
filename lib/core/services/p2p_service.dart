import '../../features/p2p/domain/models/node_state.dart';
import '../../features/p2p/domain/models/chat_message.dart';
import '../../features/p2p/domain/models/discovered_peer.dart';
import '../../features/p2p/domain/models/send_message_result.dart';
import '../local_discovery/lan_ack.dart';
import '../local_discovery/local_discovery_service.dart';

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

/// Optional capability for local LAN senders that can distinguish a durable
/// committed receiver ack from a legacy parse-time ack.
abstract interface class DurableLanSender {
  Future<LanSendAck> sendLocalMessageDurable(
    String peerId,
    String message,
    String fromPeerId, {
    int? timeoutMs,
  });
}

/// FDC-08: the coarse, "online-ish, TTL-lagged" relay presence answer used as a
/// §6.3 emphasis HINT for the 1:1 send decision (direct-race-with-lazy-inbox vs
/// inbox-first). [reachable]/[unreachable] are §6.3's `online`/`offline`. It is
/// NEVER a foreground/background claim and NEVER load-bearing for delivery — the
/// durable inbox always fires regardless of the hint.
enum RelayPresence { reachable, unreachable, unknown }

/// Optional capability for services that can cheaply look up a peer's coarse
/// relay presence via the additive `presence_get` action (FDC-08).
///
/// Kept OFF the base [P2PService] interface — exactly like [DurableLanSender],
/// [ReadinessProofRecorder] and [DetailedInboxStore] — so the many hand-written
/// `implements P2PService` fakes do not all have to grow it. The send path
/// consults it via an `is RelayPresenceLookup` check and degrades to
/// [RelayPresence.unknown] (today's full concurrent race) when the service does
/// not implement it (graceful, NET-REL-07-aligned).
abstract interface class RelayPresenceLookup {
  /// Looks up [peerId]'s coarse relay presence WITHOUT dialing a circuit (unlike
  /// [P2PService.probeRelay]). Short-TTL cached; gated by the account-migration
  /// network gate (returns [RelayPresence.unknown] while a move has paused
  /// network side-effects). Never throws — any error degrades to
  /// [RelayPresence.unknown].
  Future<RelayPresence> lookupRelayPresence(String peerId);
}

/// FDC-09: the outcome of a `presence_set` self-publish. [published] = the relay
/// accepted it; [unsupported] = an OLD relay answered "Unknown action:
/// presence_set" (NET-REL-07 — degrade to skip, never retry/spam); [blocked] =
/// the account-migration gate paused network side-effects (a moving device must
/// not announce itself reachable); [failed] = a transient relay/bridge error.
enum PresenceSetResult { published, unsupported, blocked, failed }

/// FDC-09: optional capability for services that can SELF-PUBLISH the local
/// peer's coarse foreground/background presence to the relay via the additive
/// `presence_set` action — the WRITE twin of [RelayPresenceLookup]. The relay
/// provably cannot infer foreground from a TTL-lagged socket, so the peer must
/// announce it (FDC-S3 Option C).
///
/// Kept OFF the base [P2PService] interface — exactly like [RelayPresenceLookup]
/// — so the many hand-written `implements P2PService` fakes do not all have to
/// grow it. Callers consult it via an `is RelayPresenceSet` check and no-op when
/// the service does not implement it (graceful, NET-REL-07-aligned). Presence is
/// a best-effort HINT and NEVER load-bearing for delivery.
abstract interface class RelayPresenceSet {
  /// Self-publishes [state] (`foreground`|`background`) with a freshness
  /// [ttlMs]. Move-gated as its FIRST line (returns [PresenceSetResult.blocked]
  /// while a move has paused network side-effects — a moving device must not
  /// announce itself reachable). Never throws — any error degrades to
  /// [PresenceSetResult.failed]; an old relay degrades to
  /// [PresenceSetResult.unsupported].
  Future<PresenceSetResult> setPresence(String state, int ttlMs);
}

/// 183: optional capability for services that can actively PROBE the liveness of
/// a directly-connected 1:1 peer (a libp2p `ping`). It exists so the active-chat
/// keepalive ([ActivePeerKeepAliveUseCase]) can, while foreground + in a 1:1
/// chat, keep the warm connection alive and detect a drop in SECONDS rather than
/// waiting out the ~30 s QUIC idle / 30 s relay-health poll.
///
/// Kept OFF the base [P2PService] interface — exactly like [RelayPresenceSet] /
/// [RelayPresenceLookup] — so the many hand-written `implements P2PService` fakes
/// do not all have to grow it. Callers consult it via an `is PeerLivenessProbe`
/// check (or hold the concrete impl) and no-op otherwise. The probe is a
/// best-effort HINT and NEVER load-bearing: a failed/gated/thrown ping is just a
/// miss, never an exception and never a dropped send.
abstract interface class PeerLivenessProbe {
  /// Pings [peerId] and resolves `true` iff the peer answered within [timeoutMs].
  /// Move-gated as its FIRST line (returns `false` while a move has paused
  /// network side-effects — a migrating device must not probe). Never throws —
  /// any error / old bridge / unreachable peer degrades to `false`.
  Future<bool> pingPeer(String peerId, {required int timeoutMs});
}

/// 187 — a positive, per-peer "suspected dropped" latch set by the 183 active-
/// chat keepalive (on its M-miss drop) and cleared on recovery / chat-close /
/// peer-switch / background. The send path reads it to SKIP the doomed direct
/// discover/dial WAN leg to a peer the keepalive already knows is down — the
/// concurrent durable inbox has already secured custody, so the ~1.5 s dial only
/// spends radio on both devices. It gates ONLY the WAN direct leg: the LAN leg
/// and the durable inbox are never affected, so a peer that dropped only its WAN
/// path can still be reached over LAN, and durability is never traded away.
///
/// Kept OFF the base [P2PService] interface — exactly like [PeerLivenessProbe] /
/// [RelayPresenceSet] — so the many hand-written `implements P2PService` fakes
/// do not all have to grow it. Callers consult it via an `is PeerDropSignal`
/// check and no-op otherwise. Both methods NORMALIZE [peerId] with
/// `ActiveConversationTracker.normalizeActiveKey` (the keepalive marks the
/// normalized active key; the send path queries the raw target — they must meet
/// in the middle). The signal is a best-effort HINT, never load-bearing.
abstract interface class PeerDropSignal {
  /// Whether [peerId] is currently latched as suspected-dropped (normalized).
  bool isPeerSuspectedDropped(String peerId);

  /// Set/clear [peerId]'s suspected-dropped latch: `true` on the keepalive drop,
  /// `false` on recovery / chat-close / peer-switch / background (normalized).
  void setPeerDropSuspected(String peerId, bool dropped);
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

  /// Stream of media files received over the local WiFi path.
  ///
  /// Kept separate from [messageStream] because [ChatMessage] carries no
  /// media fields. Defaults to an empty stream so non-local implementations
  /// (fakes/mocks) need no override.
  Stream<LocalMediaReady> get incomingLocalMediaStream => const Stream.empty();

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
  ///
  /// Note (FDC-04 / DESIGN-5): the concrete [P2PServiceImpl] override adds an
  /// optional `preferQuic` named param used ONLY internally by `warmPeer`'s
  /// network-change re-warm (Go-inert today). It is intentionally NOT on this
  /// interface — no caller dials with it through a [P2PService] reference, so
  /// keeping it off the interface avoids churning every fake's `dialPeer`.
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

  /// Bounded on-demand local discovery at send time. Returns true if the peer
  /// became visible on the LAN within [timeout]. Default no-op for non-local
  /// implementations (fakes/mocks) so they never report `local`.
  Future<bool> discoverLocalPeer(String peerId, {required Duration timeout}) async =>
      false;

  /// FDC-04: eager LAN-aware warm of a single peer (the open/active one — never
  /// the roster, PS-4). Overlaps connection setup with reading/typing so the
  /// first send hits the reuse fast-path. Speculative-only — it NEVER sends a
  /// message or deposits to the inbox (PS-1), is a no-op while the node is not
  /// started (PS-3), and is debounced per peer so repeated opens to an offline
  /// peer never tight-loop a failing dial. It awaits a bounded LAN seed first,
  /// then skips the speculative dial when the peer is already LAN-visible so a
  /// same-WiFi peer is never needlessly relay-dialed (INV-1). The contract is
  /// total/never-throws: all call sites fire it as bare `unawaited(...)`.
  ///
  /// [preferQuic] is threaded through to the dial on a network-change re-warm
  /// (Go-inert today — see [dialPeer]). Default no-op so implementations that
  /// have no node (fakes/mocks) need only override it when they assert warming.
  Future<void> warmPeer(String peerId, {bool preferQuic = false}) async {}

  /// NET-REL-05 P3 (sticky transport): the last successful LIVE transport
  /// (`'local'` | `'direct'` | `'relay'`) for [peerId], or null if none is
  /// known or it has expired/become stale. Session-scoped and never
  /// authoritative — callers consult it only to weight the send race toward a
  /// recently-good path and ALWAYS fall back to the full race on failure.
  /// Default null so every fake/mock compiles unchanged.
  String? lastKnownGoodTransport(String peerId) => null;

  /// NET-REL-05 P3 (sticky transport): record a successful LIVE [transport]
  /// (`'local'` | `'direct'` | `'relay'`) for [peerId]. `'inbox'` is a custody
  /// handoff, not a live transport, and is ignored. Default no-op.
  void recordSuccessfulTransport(String peerId, String transport) {}

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
  ///
  /// When [enc] is true (112 Phase 4), [filePath] is an encrypted blob
  /// artifact: the offer is enc-flagged with [encScheme] so the receiver
  /// stages the ciphertext for deferred decrypt instead of promoting it.
  Future<bool> sendLocalMedia({
    required String peerId,
    required String filePath,
    required String mime,
    required String mediaId,
    required String fromPeerId,
    int? durationMs,
    List<double>? waveform,
    String? filename,
    bool enc,
    String? encScheme,
  });

  /// The last recovery method used ('in_place', 'watchdog_restart', or null).
  /// Exposed so that resume handlers can decide whether to rejoin group topics.
  String? get lastRecoveryMethod;

  /// Dispose of the service and clean up resources.
  void dispose();
}

/// Optional capability for flows that must not proceed until all currently
/// available offline inbox pages have been replayed.
abstract class P2PFullInboxDrain {
  Future<void> drainOfflineInboxFully();
}
