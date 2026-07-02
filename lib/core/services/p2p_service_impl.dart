import 'dart:async';
import 'dart:convert';
import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'p2p_service.dart';
import '../notifications/active_conversation_tracker.dart';
import '../bridge/bridge.dart';
import '../bridge/p2p_bridge_client.dart';
import '../debug/transport_metrics.dart';
import '../inbox/inbox_staging_entry.dart';
import '../inbox/inbox_staging_repository.dart';
import 'inbox_store_outcome.dart';
import '../local_discovery/lan_ack.dart';
import '../local_discovery/local_discovery_service.dart';
import '../local_discovery/local_p2p_service.dart';
import '../utils/key_conversion.dart';
import '../utils/chat_console_logger.dart';
import '../utils/flow_event_emitter.dart';
import '../utils/startup_timing.dart';
import '../utils/cold_start_notif_anchor.dart';
import '../utils/push_diagnostics_logger.dart';
import '../../features/account_migration/application/account_migration_runtime_network_gate.dart';
import '../../features/p2p/domain/models/node_state.dart';
import '../../features/p2p/domain/models/chat_message.dart';
import '../../features/p2p/domain/models/discovered_peer.dart';
import '../../features/p2p/domain/models/send_message_result.dart';
import '../../features/p2p/domain/models/connection_state.dart';
import '../../features/push/domain/push_token_store.dart';

enum RecoveredInboxChatDisposition {
  committed,
  retryable,
  rejected,
  quarantined,
}

/// Replay attempts allowed before a retryable staged entry is quarantined
/// instead of looping forever. Quarantine keeps the envelope (INV-1) but
/// excludes it from further replay.
const maxInboxReplayAttempts = 10;

typedef RecoveredInboxReplayOutcome = ({
  RecoveredInboxChatDisposition disposition,
  String reasonCode,
  String? reasonDetail,
});

typedef ReplayRecoveredInboxChatMessage =
    Future<RecoveredInboxReplayOutcome> Function(
      ChatMessage message, {
      String? stagedEntryId,
    });

typedef ReplayRecoveredInboxIntroductionMessage =
    Future<RecoveredInboxReplayOutcome> Function(ChatMessage message);

/// 171: relay-inbox replay of a contact_request runs the IDENTICAL listener
/// logic as the live broadcast (auto-add + reciprocal + confirm) for a cold
/// receiver whose ContactRequestListener was not yet subscribed. Same shape as
/// introduction (no stagedEntryId — the listener does not need it).
typedef ReplayRecoveredInboxContactRequestMessage =
    Future<RecoveredInboxReplayOutcome> Function(ChatMessage message);

/// NET-REL-05 P3: a learned per-peer LIVE transport plus the time it was
/// recorded, for TTL-based expiry. `transport` is one of `'local'`, `'direct'`,
/// or `'relay'`.
class _LearnedTransport {
  final String transport;
  final DateTime at;
  const _LearnedTransport(this.transport, this.at);
}

/// FDC-08: a cached relay-presence answer plus the time it was recorded, for
/// short-TTL read-time expiry (mirrors [_LearnedTransport]).
class _PresenceCacheEntry {
  final RelayPresence presence;
  final DateTime at;
  const _PresenceCacheEntry(this.presence, this.at);
}

/// FDC-04: per-peer eager-warm debounce/backoff bookkeeping. [inFlight] is set
/// SYNCHRONOUSLY at `warmPeer` entry (before the first await) so a same-tick
/// conv-open + notif-tap + resume burst collapses to ONE dial (DESIGN-4).
/// [nextEligibleAt] is the post-dial escalating cooldown floor; [failureCount]
/// drives the 5s->2x->…->ceil growth (CONSIST-1) — a thin Dart debounce layered
/// OVER libp2p's Go-owned per-`(peer,transport)` swarm backoff, not a
/// reimplementation of it. Keyed by FULL peerId (transport-agnostic).
class _WarmAttempt {
  bool inFlight = false;
  DateTime? nextEligibleAt;
  int failureCount = 0;
}

/// Implementation of P2PService backed by the Go native bridge.
class P2PServiceImpl
    implements
        P2PService,
        DetailedInboxStore,
        ReadinessProofRecorder,
        P2PFullInboxDrain,
        DurableLanSender,
        RelayPresenceLookup,
        RelayPresenceSet,
        PeerLivenessProbe,
        PeerDropSignal,
        InboxAttentionSignal {
  final Bridge _bridge;
  final LocalP2PService? _localP2P;
  final PushTokenStore? _pushTokenStore;
  final AccountMigrationNetworkGate _accountMigrationNetworkGate;
  final InboxStagingRepository _inboxStagingRepository;
  final ReplayRecoveredInboxChatMessage? _replayRecoveredInboxChatMessage;
  final ReplayRecoveredInboxChatMessage? _replayLiveLanChatMessage;
  // 118: a freshly-staged-and-immediately-replayed LIVE direct (1:1) message
  // routes here (suppressNotification:false), NOT through the suppressing
  // recovery callback. Wired hard (non-null) in production — see main.dart.
  final ReplayRecoveredInboxChatMessage? _replayLiveDirectChatMessage;
  final ReplayRecoveredInboxIntroductionMessage?
  _replayRecoveredInboxIntroductionMessage;
  // 171: relay-inbox replay arm for a cold-receiver contact_request — wired in
  // main.dart to contactRequestListener.processIncomingMessage so the inbox
  // path reaches the SAME mutual outcome (add + reciprocal) as the live path.
  // Optional so existing test constructors keep compiling; absent → legacy
  // fall-through (bare emit + immediate delete, NOT mutual).
  final ReplayRecoveredInboxContactRequestMessage?
  _replayRecoveredInboxContactRequest;
  // F7: reactions/deletions get the SAME stage-before-ack/commit durability as
  // chat. Both share the chat replay shape `(ChatMessage, {stagedEntryId})` →
  // a `RecoveredInboxReplayOutcome`. Optional (nullable) so existing test
  // constructors keep compiling; when absent the entry falls through to the
  // legacy fire-and-forget emit (pre-F7 behavior).
  final ReplayRecoveredInboxChatMessage? _replayRecoveredInboxReaction;
  final ReplayRecoveredInboxChatMessage? _replayRecoveredInboxMessageDeletion;
  // 147: optional decrypt-prefetch fn (wired in main.dart to the same bridge
  // decrypt + ML-KEM ring the chat handler uses). When present, the inbox-drain
  // replay decrypts a page's chat entries concurrently (bounded by
  // [maxConcurrentInboxDecrypts]) BEFORE the serial commit loop and threads each
  // plaintext into the replay. When null (the default), no prefetch runs and the
  // drain is byte-identical to HEAD — a safe default-off rollback + test seam.
  final Future<String?> Function(ChatMessage message)? _predecryptInboxChatEntry;
  final TransportMetrics? _transportMetrics;
  final Duration? _keyRotationGracePeriodOverride;
  StreamSubscription<LocalChatMessage>? _localMessageSub;
  StreamSubscription<Map<String, LocalPeer>>? _localPeersSub;
  StreamSubscription<LocalMediaReady>? _localMediaSub;
  StreamSubscription<Map<String, dynamic>>? _transportDiagnosticSub;

  /// NET-REL-02 Option A: short peer IDs (last 8 chars, matching the Go
  /// tracer's `remotePeerShort`) that genuinely upgraded relay->direct via a
  /// DCUtR hole punch. Session-scoped telemetry only — never used for any
  /// security/routing decision.
  final Set<String> _peersUpgradedToDirect = {};

  /// NET-REL-05 P3 (sticky transport): last-known-good LIVE transport per peer,
  /// keyed by FULL peerId. Session-scoped, in-memory only (never authoritative).
  /// Consulted by the send race to weight toward a recently-good path; expired
  /// via TTL (`'local'` = 30s to match NET-REL-01 LAN TTL, re-validated against
  /// live LAN visibility; `'direct'`/`'relay'` = 10min) and invalidated on
  /// disconnect / addresses-updated. The race always falls back to the full
  /// race on any sticky-leg failure, so a stale entry can never trap a send.
  final Map<String, _LearnedTransport> _learnedTransport = {};

  /// FDC-08 short-TTL presence cache (≈10–15s, FDC-S3-locked / device-tunable),
  /// keyed by FULL peerId. Read-time TTL eviction mirrors [lastKnownGoodTransport]
  /// (`clock.now()`-based, withClock-testable). Intentionally non-durable and
  /// re-derived: it is never carried across a resume / WiFi↔cellular switch, so a
  /// stale `reachable` can never bias a send (C4).
  final Map<String, _PresenceCacheEntry> _presenceCache = {};
  static const Duration _presenceCacheTtl = Duration(seconds: 12);

  /// FDC-04: per-peer eager-warm debounce/backoff state, keyed by FULL peerId
  /// (transport-agnostic — CONSIST-1). Session-scoped, in-memory only; lost on
  /// restart (a restart is a fresh warm). The first warm-bookkeeping map here.
  final Map<String, _WarmAttempt> _warmAttempts = {};

  /// FDC-04 (RC4): injected WiFi<->cellular network-change signal. Default
  /// null/empty in tests + until the OS source is wired (connectivity_plus or a
  /// native NWPathMonitor/ConnectivityManager channel — a bounded follow-up).
  /// On each event, [onNetworkChanged] re-warms the ONE active peer.
  final Stream<void>? _networkChangeSignal;
  StreamSubscription<void>? _networkChangeSub;

  /// FDC-04 (DESIGN-3): resolves the single active conversation peer to re-warm
  /// on a network change (PS-4 — never the roster). In production wired to
  /// `ActiveConversationTracker.activePeerId`. Null / null-return ⇒ no re-warm.
  final String? Function()? _activePeerId;

  /// FDC-04 (DESIGN-2): self-debounce floor for the network-change re-warm so
  /// WiFi<->cellular flapping coalesces to ONE re-warm instead of tight-looping
  /// a failing QUIC dial and tripping the libp2p 5s->5min swarm backoff. Kept
  /// DISTINCT from the per-peer [_WarmAttempt.nextEligibleAt] cooldown.
  DateTime? _lastNetworkRewarmAt;

  final _stateController = StreamController<NodeState>.broadcast();
  final _messageController = StreamController<ChatMessage>.broadcast();
  final _incomingLocalMediaController =
      StreamController<LocalMediaReady>.broadcast();

  NodeState _currentState = NodeState.stopped;
  Timer? _healthCheckTimer;
  String? _lastFcmToken;
  String? _lastFcmPlatform;
  Future<void>? _restorePushTokenFuture;
  bool _isStarting = false;
  DateTime? _startNodeTime;
  bool _hasEverBeenOnline = false;
  bool _isHealthChecking = false;
  int _consecutiveHealthCheckExceptions = 0;
  bool _stopped = true; // starts stopped; cleared when node starts
  bool _localDiscoveryActive = false;

  /// FDC-11: peers already forwarded to the Go libp2p LAN-direct dial, so a
  /// re-emitted discovery snapshot (the stream re-fires on every change) does
  /// not re-cross the bridge for the same peer. The Go side also debounces via
  /// its per-peer cooldown, so this is a cheap front-line dedup.
  final Set<String> _lanDialForwardedPeerIds = <String>{};

  /// 179 (CV-34): LAN peers currently in an "empty libp2pAddresses" episode —
  /// resolved over mDNS but advertised a portless TXT, so they were dropped at
  /// the forward gate. Guards BOTH the resolved-but-empty diagnostic and the
  /// bounded on-demand re-resolve to once per episode, so the ~20s
  /// LOST_RETAINED/FOUND flap cannot drive a re-resolve storm. Cleared when the
  /// peer heals (gains addresses) or drops out of the discovery snapshot.
  final Set<String> _lanEmptyReResolvedPeerIds = <String>{};

  /// FDC-11 (174): the libp2p QUIC/TCP LAN ports most recently derived from the
  /// host's listen addresses (`addresses:updated`). The bonsoir advert is
  /// re-published with these so a same-WiFi peer can build a non-empty
  /// `libp2pAddresses`, but ONLY once Local Network is proven working — see
  /// [_maybePublishLibp2pAdvertPorts].
  int? _resolvedAdvertQuicPort;
  int? _resolvedAdvertTcpPort;

  /// FDC-11 (174): true once any same-WiFi peer has resolved over mDNS. A
  /// resolve proves the OS granted Local Network access, so a bonsoir
  /// re-advertise (native stop+start) can no longer block the iOS main thread
  /// past the scene-update watchdog. Sticky for the process: permission does not
  /// get revoked mid-session, and once proven every re-advertise is safe.
  bool _localNetworkProven = false;

  /// P4: one-shot heuristic timer for suspected iOS Local-Network permission
  /// denial. Started on discovery activation; fires after 12s with zero peers
  /// to re-record the snapshot with `suspectedPermissionDenied: true`. Cancelled
  /// (and the flag cleared) the moment any peer appears or discovery stops.
  /// Never authoritative — bonsoir 5.1.0 surfaces no permission status.
  Timer? _lanPermProbeTimer;

  /// Phase 5: Completer-based recovery coalescing.
  /// When non-null, a recovery is in progress and concurrent callers
  /// should await this instead of starting a new recovery.
  Completer<void>? _recoveryInProgress;

  /// F3 step 2: when non-null, an offline-inbox drain is in progress. Concurrent
  /// callers coalesce onto it instead of each fetching the SAME un-acked relay
  /// page (`inbox:retrieve_pending` is a non-destructive read) and each running
  /// the recoverable sweep — which would double-ack / double-replay / double-
  /// notify the same entry across the multi-await gate→save window.
  Completer<void>? _drainInProgress;

  /// Whether the in-flight drain ([_drainInProgress]) drains ALL backlog pages.
  /// A partial drain cannot satisfy a caller that needs the full guarantee.
  bool _drainInProgressWaitsAllPages = false;

  /// 141: One-shot latch for a notif-open opportunistic drain requested while
  /// the node had not yet started. The public [drainOfflineInbox] /
  /// [drainOfflineInboxFully] used to hard-early-return when `!isStarted`,
  /// silently dropping a notif-open catch-up. Instead the request is now
  /// DEFERRED here and fired exactly once on the next stopped->started
  /// transition observed in [_emitState] — mirroring the relay-healthy push-
  /// token re-register precedent. The account-migration network gate is
  /// re-checked at fire time (the public entry point is re-run), never bypassed.
  bool _pendingStartupDrain = false;

  /// Whether the deferred startup drain ([_pendingStartupDrain]) must drain ALL
  /// backlog pages. The stronger all-pages variant wins if any pending request
  /// while-stopped needed it.
  bool _pendingStartupDrainWaitForAllPages = false;

  /// Phase 5: Count of consecutive in-place refresh failures.
  /// Reset to 0 on successful recovery.
  int _consecutiveRefreshFailures = 0;

  /// Phase 5: The recovery mode used by the last successful recovery.
  /// 'in_place', 'watchdog_restart', or null if no recovery yet.
  String? _lastRecoveryMethod;

  /// Timing instrumentation: last confirmed-healthy relay poll timestamp.
  DateTime? _lastHealthyRelayAt;

  /// Timing instrumentation: when degradation was first detected (for outage timing).
  DateTime? _outageDetectedAt;

  /// Cold-start relay recovery is allowed only after the normal startup grace
  /// period, so a relay reservation that is merely still settling is not
  /// treated as a failure.
  DateTime? _lastStartupRelayRecoveryAttemptAt;

  /// §24: Timestamp when startNodeCore() was called (for cold-start timing).
  DateTime? _nodeStartRequestedAt;

  /// §24: Timestamp when we last transitioned away from online (for recovery timing).
  DateTime? _lastWentOfflineAt;

  /// §24: Prevents duplicate cold-start events when multiple paths race.
  bool _coldStartOnlineEmitted = false;

  /// FDC-S1 (b): one-shot latch so `FDC_COLDSTART_FIRST_CIRCUIT_TIMING` fires
  /// only on the first non-empty circuitAddresses push per start (addresses
  /// update repeatedly). Observation-only.
  bool _coldStartFirstCircuitEmitted = false;

  /// §24: True when startNodeCore detected an 'already started' hot-restart.
  bool _isHotRestart = false;

  /// §24: Timestamp when the app resumed from background (for background_resume timing).
  DateTime? _resumeStartedAt;

  /// Phase 6: monotonically increasing proof-window sequence.
  int _readinessProofWindowSequence = 0;

  /// Phase 6: current proof-window identity and phase.
  String? _activeReadinessProofWindowId;
  String? _activeReadinessPhase;
  DateTime? _activeReadinessProofWindowStartedAt;

  /// Phase 6: first-attempt timing for each capability inside the current window.
  DateTime? _sendProofAttemptStartedAt;
  DateTime? _inboxProofAttemptStartedAt;

  /// Phase 6: source attribution for the first successful proof in the window.
  String? _sendProofSource;
  String? _inboxProofSource;

  /// Phase 6: emit first-success events only once per window.
  bool _sendSuccessEventEmitted = false;
  bool _inboxSuccessEventEmitted = false;

  /// Phase 6: tracks whether the current trigger already fired a proactive
  /// send proof attempt. Failures may clear this so later system triggers can
  /// retry within the same proof window.
  bool _proactiveSendProofAttemptedInWindow = false;
  bool _proactiveSendProofInFlight = false;
  String? _pendingProactiveSendProofTrigger;

  /// Section 8: source that triggered the next relay recovery attempt.
  String? _pendingRecoverySource;

  /// Section 8: source currently attributed to the in-flight recovery attempt.
  String? _activeRecoverySource;

  /// Phase 5: Threshold for escalating from in-place refresh to watchdog.
  static const int refreshFailureThreshold = 3;

  /// How often the health check polls node:status.
  static const healthCheckInterval = Duration(seconds: 30);

  /// How long cold start may remain relay-degraded before actively recovering.
  static const startupRelayRecoveryDelay = Duration(seconds: 2);

  /// Minimum spacing between cold-start relay recovery attempts.
  static const startupRelayRecoveryRetryInterval = Duration(seconds: 15);

  /// Maximum time budget for warm background tasks during startup.
  static const warmTaskTimeout = Duration(seconds: 5);

  /// Foreground budget for the first inbox page during startup and resume.
  static const foregroundInboxTimeout = Duration(seconds: 3);

  P2PServiceImpl({
    required Bridge bridge,
    LocalP2PService? localP2PService,
    PushTokenStore? pushTokenStore,
    AccountMigrationNetworkGate accountMigrationNetworkGate =
        allowAccountMigrationNetworkSideEffects,
    required InboxStagingRepository inboxStagingRepository,
    ReplayRecoveredInboxChatMessage? replayRecoveredInboxChatMessage,
    ReplayRecoveredInboxChatMessage? replayLiveLanChatMessage,
    ReplayRecoveredInboxChatMessage? replayLiveDirectChatMessage,
    ReplayRecoveredInboxIntroductionMessage?
    replayRecoveredInboxIntroductionMessage,
    ReplayRecoveredInboxContactRequestMessage?
    replayRecoveredInboxContactRequest,
    ReplayRecoveredInboxChatMessage? replayRecoveredInboxReaction,
    ReplayRecoveredInboxChatMessage? replayRecoveredInboxMessageDeletion,
    Future<String?> Function(ChatMessage message)? predecryptInboxChatEntry,
    TransportMetrics? transportMetrics,
    Duration? keyRotationGracePeriodOverride,
    // FDC-04: optional, default null keeps every existing call site unchanged.
    Stream<void>? networkChangeSignal,
    String? Function()? activePeerId,
  }) : _bridge = bridge,
       _localP2P = localP2PService,
       _pushTokenStore = pushTokenStore,
       _accountMigrationNetworkGate = accountMigrationNetworkGate,
       _inboxStagingRepository = inboxStagingRepository,
       _replayRecoveredInboxChatMessage = replayRecoveredInboxChatMessage,
       _replayLiveLanChatMessage = replayLiveLanChatMessage,
       _replayLiveDirectChatMessage = replayLiveDirectChatMessage,
       _replayRecoveredInboxIntroductionMessage =
           replayRecoveredInboxIntroductionMessage,
       _replayRecoveredInboxContactRequest =
           replayRecoveredInboxContactRequest,
       _replayRecoveredInboxReaction = replayRecoveredInboxReaction,
       _replayRecoveredInboxMessageDeletion =
           replayRecoveredInboxMessageDeletion,
       _predecryptInboxChatEntry = predecryptInboxChatEntry,
       _transportMetrics = transportMetrics,
       _keyRotationGracePeriodOverride = keyRotationGracePeriodOverride,
       _networkChangeSignal = networkChangeSignal,
       _activePeerId = activePeerId {
    // Register event handlers on the bridge
    _bridge.onMessageReceived = (msg) {
      final transport =
          msg.transport ?? _inferTransportForPeer(msg.from) ?? 'unknown';
      _transportMetrics?.recordTransport(transport);
      // NET-REL-01 I3: greppable receiver-side transport readout (replaces having
      // to read the kDebugMode diagnostics card). LAN messages arrive on the local
      // path below ('wifi'); direct/relay/unknown arrive here.
      emitFlowEvent(
        layer: 'FL',
        event: 'MSG_RECEIVED_TRANSPORT',
        details: {
          'from': msg.from.length > 10 ? msg.from.substring(0, 10) : msg.from,
          'transport': transport,
        },
      );
      unawaited(_handleMessageReceived(msg.copyWith(transport: transport)));
    };
    _bridge.onPeerConnected = _handlePeerConnected;
    _bridge.onPeerDisconnected = _handlePeerDisconnected;
    _bridge.onAddressesUpdated = _handleAddressesUpdated;
    _bridge.onRelayStateChanged = _handleRelayStateChanged;

    // NET-REL-02 Option A: observe DCUtR hole-punch / relay->direct telemetry
    // emitted by the Go tracer to drive TransportMetrics counters and the
    // upgraded-peer set used to keep _inferTransportForPeer honest.
    _transportDiagnosticSub = transportDiagnosticEventStream.listen(
      _handleTransportDiagnosticEvent,
    );

    _localP2P?.configureInboundChatCommitHandler(_commitInboundLanChatMessage);

    // Merge local WiFi messages into the unified message stream
    _localMessageSub = _localP2P?.localMessageStream.listen((localMsg) {
      _transportMetrics?.recordTransport('wifi');
      // NET-REL-01 I3: this is the LAN path — a same-WiFi received message. The
      // 'wifi' transport here is the path-pinned proof I3 looks for.
      emitFlowEvent(
        layer: 'FL',
        event: 'MSG_RECEIVED_TRANSPORT',
        details: {
          'from': localMsg.from.length > 10
              ? localMsg.from.substring(0, 10)
              : localMsg.from,
          'transport': 'wifi',
        },
      );
      unawaited(
        _handleMessageReceived(
          ChatMessage(
            from: localMsg.from,
            to: localMsg.to,
            content: localMsg.content,
            timestamp: localMsg.timestamp.toIso8601String(),
            isIncoming: localMsg.isIncoming,
            transport: 'wifi',
          ),
        ),
      );
    });
    // Merge inbound local WiFi media onto a typed stream (NOT messageStream —
    // ChatMessage has no media fields). Null when the media server is
    // unconfigured (e.g. test builds), so use ?.listen.
    _localMediaSub = _localP2P?.mediaReadyStream?.listen((media) {
      _transportMetrics?.recordTransport('wifi');
      _incomingLocalMediaController.add(media);
    });
    _localPeersSub = _localP2P?.discoveredPeersStream.listen((peers) {
      // 179 (CV-34, INV-2): a peer that dropped out of the snapshot must be
      // re-armed so a later (healed) reappearance re-crosses the LAN-dial
      // forward. The dedup set was previously never cleared, so once a peer was
      // forwarded — or once the iPhone finally re-advertised ports after a flap —
      // the reappearance was silently deduped. Clear departed peers from both the
      // forward dedup and the empty-resolve guard.
      _lanDialForwardedPeerIds.removeWhere((id) => !peers.containsKey(id));
      _lanEmptyReResolvedPeerIds.removeWhere((id) => !peers.containsKey(id));
      // P4: a peer appearing clears any suspected-permission-denied state and
      // stops the heuristic timer (a peer was seen → permission is not denied).
      if (peers.isNotEmpty) {
        _lanPermProbeTimer?.cancel();
        _lanPermProbeTimer = null;
        // FDC-11 (174): a resolved peer proves Local Network works → it is now
        // safe to (re)publish the libp2p advert ports, and a peer now exists to
        // dial. Flush any ports that were derived earlier but held back during
        // the cold-start window (see [_maybePublishLibp2pAdvertPorts]).
        _localNetworkProven = true;
        _maybePublishLibp2pAdvertPorts(source: 'peer_resolved');
      }
      _recordLanAvailability(
        discoveryActive: _localDiscoveryActive,
        discoveredPeerCount: peers.length,
      );
      // FDC-11: forward newly-discovered same-WiFi peers (carrying libp2p
      // QUIC/TCP multiaddrs) to the Go LAN-direct dial. Fire-and-forget so the
      // metrics path above is never blocked on the migration gate.
      unawaited(_forwardLanPeersToLibp2pDial(peers));
    });
    _recordLanAvailability(
      discoveryActive: false,
      discoveredPeerCount: _localP2P?.discoveredPeers.length ?? 0,
    );

    // FDC-04 (RC4): re-warm the active peer on a WiFi<->cellular change. Default
    // null signal ⇒ no subscription (tests + until the OS source lands).
    // onNetworkChanged is total/never-throws.
    _networkChangeSub = _networkChangeSignal?.listen((_) => onNetworkChanged());

    unawaited(_restorePersistedPushTokenIfNeeded());
  }

  @override
  NodeState get currentState => _currentState;

  @override
  Stream<NodeState> get stateStream => _stateController.stream;

  @override
  Stream<ChatMessage> get messageStream => _messageController.stream;

  @override
  Stream<LocalMediaReady> get incomingLocalMediaStream =>
      _incomingLocalMediaController.stream;

  Future<bool> _allowsAccountNetworkSideEffects(
    String operation, {
    String? peerId,
  }) async {
    final effectivePeerId = peerId ?? _currentState.peerId;
    final allowed = await _accountMigrationNetworkGate(
      peerId: effectivePeerId,
      operation: operation,
    );
    if (!allowed) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_ACCOUNT_MIGRATION_NETWORK_BLOCKED',
        details: {'operation': operation, 'peerId': ?effectivePeerId},
      );
    }
    return allowed;
  }

  @override
  Future<bool> startNode(String privateKeyBase64, String peerId) async {
    if (!await _allowsAccountNetworkSideEffects(
      'p2p_start_node',
      peerId: peerId,
    )) {
      return false;
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_SERVICE_START_NODE_BEGIN',
      details: {'peerId': peerId},
    );

    final success = await startNodeCore(privateKeyBase64, peerId);
    if (success) {
      // FDC-07: kick off LAN mDNS discovery EARLY — before the warmBackground
      // inbox-drain body — so a same-WiFi peer can populate the LAN map ahead of
      // the first send window. Fire-and-forget + opportunistic: never blocks
      // node-start or the send race, and idempotent with the warm-body and
      // StartupRouter triggers.
      unawaited(startEarlyLocalDiscovery());
      unawaited(_warmBackgroundSafely());
    }
    return success;
  }

  Future<void> _warmBackgroundSafely() async {
    try {
      await warmBackground();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_WARM_BACKGROUND_EXCEPTION',
        details: {'error': e.toString()},
      );
    }
  }

  @override
  Future<bool> startNodeCore(String privateKeyBase64, String peerId) async {
    if (!await _allowsAccountNetworkSideEffects(
      'p2p_start_node_core',
      peerId: peerId,
    )) {
      return false;
    }

    if (_isStarting) {
      if (kDebugMode) {
        debugPrint('[START] startNodeCore() skipped — already starting');
      }
      return false;
    }
    _isStarting = true;
    _startNodeTime = DateTime.now();
    _nodeStartRequestedAt = DateTime.now();
    _coldStartOnlineEmitted = false;
    _coldStartFirstCircuitEmitted = false;
    _isHotRestart = false;
    _lastStartupRelayRecoveryAttemptAt = null;
    if (kDebugMode) {
      debugPrint('[START] startNodeCore() beginning for peerId=$peerId');
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_SERVICE_START_NODE_CORE_BEGIN',
      details: {'peerId': peerId},
    );

    try {
      final privateKeyHex = base64ToHex(privateKeyBase64);
      final namespace = 'mknoon:chat:$peerId';

      final response = await callP2PNodeStart(
        _bridge,
        privateKeyHex: privateKeyHex,
        autoRegister: true,
        namespace: namespace,
        keyRotationGracePeriod: _keyRotationGracePeriodOverride,
        // FDC-S1 (observation-only): thread the canonical process-start epoch
        // so Go can stamp sinceProcessStartMs on its cold-start timing emits.
        processStartEpochMs: StartupTiming.instance.processStartEpochMs,
      );

      if (response['ok'] == true) {
        _stopped = false;
        // FDC-S1 (a): process-start → node:start returns (Dart-clock view; Go
        // emits its own host_ready sinceProcessStartMs on the same anchor).
        emitFlowEvent(
          layer: 'FL',
          event: 'FDC_COLDSTART_NODE_START_RETURN_TIMING',
          details: {
            'sinceProcessStartMs':
                StartupTiming.instance.sinceProcessStartMs() ?? -1,
          },
        );
        // FDC-S1 (d): node is ready on the main isolate — the floor a warm dial
        // on a cold notif-tap must respect. Emits the correlation event iff this
        // launch was also a notification tap (see ColdStartNotifAnchor).
        ColdStartNotifAnchor.instance.recordNodeReady();
        _emitState(NodeState.fromJson(response), source: 'start_response');
        _beginReadinessProofWindow(
          phase: 'cold_start',
          trigger: 'start_response',
          startedAt: _nodeStartRequestedAt ?? DateTime.now(),
        );

        if (_stateHasHealthyRelay(_currentState)) {
          _hasEverBeenOnline = true;
        }

        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_START_NODE_CORE_SUCCESS',
          details: {'peerId': _currentState.peerId},
        );

        return true;
      }

      // Handle hot restart: Go node is already running but Dart state was reset.
      // Query node:status to sync Dart state with the running Go node.
      final errorMsg = response['errorMessage']?.toString() ?? '';
      if (errorMsg.contains('already started')) {
        _isHotRestart = true;
        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_START_NODE_CORE_ALREADY_RUNNING',
          details: {},
        );

        final statusResponse = await callP2PNodeStatus(_bridge);
        if (statusResponse['ok'] == true) {
          _stopped = false;
          _emitState(
            NodeState.fromJson(statusResponse),
            source: 'start_response',
          );
          _beginReadinessProofWindow(
            phase: 'hot_restart',
            trigger: 'already_started_resync',
            startedAt: _nodeStartRequestedAt ?? DateTime.now(),
          );

          if (_stateHasHealthyRelay(_currentState)) {
            _hasEverBeenOnline = true;
          }

          emitFlowEvent(
            layer: 'FL',
            event: 'P2P_SERVICE_START_NODE_CORE_RESYNCED',
            details: {'peerId': _currentState.peerId},
          );

          return true;
        }
      }

      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_START_NODE_CORE_ERROR',
        details: {
          'errorCode': response['errorCode'],
          'errorMessage': response['errorMessage'],
        },
      );
      return false;
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_START_NODE_CORE_EXCEPTION',
        details: {'error': e.toString()},
      );
      return false;
    } finally {
      _isStarting = false;
    }
  }

  @override
  Future<void> warmBackground() async {
    if (!_currentState.isStarted) return;
    if (!await _allowsAccountNetworkSideEffects('p2p_warm_background')) {
      return;
    }

    if (kDebugMode) {
      debugPrint(
        '[WARM] warmBackground() starting — '
        'circuitAddresses=${_currentState.circuitAddresses.length}',
      );
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_SERVICE_WARM_BACKGROUND_BEGIN',
      details: {},
    );

    _startHealthCheck();

    // Fast circuit detection: if the push event from Go hasn't delivered
    // circuit addresses within 2s, poll node:status directly. This is a
    // fallback for cases where the EventChannel delivery is delayed.
    Future.delayed(const Duration(seconds: 2), () {
      if (_stopped) return;
      if (_currentState.isStarted && !_stateHasHealthyRelay(_currentState)) {
        if (kDebugMode) {
          debugPrint(
            '[WARM] Fast relay check — still not healthy after 2s, polling...',
          );
        }
        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_FAST_CIRCUIT_CHECK',
          details: {
            'reason': 'relay not healthy after 2s',
            'relayState': _currentState.relayState,
            // FDC-S1 (b): anchor the 2s fallback poll to process start.
            'sinceProcessStartMs':
                StartupTiming.instance.sinceProcessStartMs() ?? -1,
            'circuitReady': _currentState.circuitAddresses.isNotEmpty,
          },
        );
        _performHealthCheck();
      } else {
        if (kDebugMode) {
          debugPrint(
            '[WARM] Fast relay check — already healthy '
            '(relayState=${_currentState.relayState}, '
            'circuitAddresses=${_currentState.circuitAddresses.length}), skipping',
          );
        }
      }
    });

    // FDC-07: LAN discovery is hoisted ahead of the inbox-drain body. On the
    // cold-start path startNode already kicked it off; this idempotent trigger
    // covers any standalone warmBackground caller (e.g. integration harnesses /
    // resume re-warm). Opportunistic — never folded into the drain barrier.
    unawaited(startEarlyLocalDiscovery());

    // Run proactive-send-proof and inbox drain concurrently.
    final futures = <Future>[];
    futures.add(_attemptProactiveSendProofIfNeeded(trigger: 'warm_background'));
    futures.add(
      _drainOfflineInbox().timeout(warmTaskTimeout).catchError((_) {}),
    );

    await Future.wait(futures);

    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_SERVICE_WARM_BACKGROUND_COMPLETE',
      details: {},
    );
  }

  /// FDC-07: cold-start early mDNS advertise/discover seam. Hoisted out of the
  /// warmBackground futures list (where it raced the inbox drain) so a same-WiFi
  /// peer can populate the LAN map before the first send window. Triggered by
  /// [startNode] (service-level) and by the cold-start orchestrator
  /// (StartupRouter) — the [_startLocalDiscovery] entry guard collapses the two
  /// seams to a single start. Strictly opportunistic: it never blocks the
  /// send/relay race. Re-asserts the account-move network gate that
  /// warmBackground used to provide transitively (hoisting out of that body must
  /// not leak a wire op during an account move).
  Future<void> startEarlyLocalDiscovery() async {
    if (_localDiscoveryActive) return;
    if (!await _allowsAccountNetworkSideEffects('p2p_lan_discovery')) {
      return;
    }
    final localPeerId = _currentState.peerId;
    if (_localP2P == null || localPeerId == null) return;
    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_SERVICE_EARLY_LOCAL_DISCOVERY_START',
      details: {},
    );
    await _startLocalDiscovery(localPeerId);
  }

  Future<void> _startLocalDiscovery(String localPeerId) async {
    // FDC-07: idempotency entry guard. `_localDiscoveryActive` is only set AFTER
    // localP2P.start() returns, so without this guard the early seam + the
    // warm-body trigger could both reach localP2P.start() before either flips
    // the flag, double-starting bonsoir.
    if (_localDiscoveryActive) return;
    final localP2P = _localP2P;
    if (localP2P == null) return;

    try {
      // FDC-11: thread the libp2p host's own LAN listen ports (from the node
      // state) into the bonsoir advert so a same-WiFi peer can build the libp2p
      // LAN-direct multiaddr. Null when the host has not yet reported its listen
      // addresses (cold-start early seam) — a later restartAdvertising
      // re-publishes once they are known.
      final listenAddresses = _currentState.listenAddresses;
      await localP2P.start(
        localPeerId,
        quicPort: _libp2pListenPort(listenAddresses, quic: true),
        tcpPort: _libp2pListenPort(listenAddresses, quic: false),
      );
      _setLocalDiscoveryActive();
    } catch (_) {
      _setLocalDiscoveryInactive();
      rethrow;
    }
  }

  /// FDC-11: extracts the libp2p QUIC (`/udp/<p>/quic-v1`) or plain-TCP
  /// (`/tcp/<p>`, excluding the WS lane) LAN listen port from the host's
  /// reported listen multiaddrs. Returns null if none is present.
  static int? _libp2pListenPort(
    List<String> listenAddresses, {
    required bool quic,
  }) {
    for (final addr in listenAddresses) {
      if (quic) {
        final m = RegExp(r'/udp/(\d+)/quic-v1').firstMatch(addr);
        if (m != null) return int.tryParse(m.group(1)!);
      } else {
        // Plain libp2p TCP transport — skip the WS lane and the QUIC addr.
        if (addr.contains('/ws') || addr.contains('quic')) continue;
        final m = RegExp(r'/tcp/(\d+)').firstMatch(addr);
        if (m != null) return int.tryParse(m.group(1)!);
      }
    }
    return null;
  }

  /// 179: test seam over [_libp2pListenPort] so the advert port-derivation
  /// (the A′ branch of the CV-34 Pixel→iPhone forward-chain root cause) can be
  /// characterization-locked directly, without standing up the node-start +
  /// discovery-active machinery. Behaviour-neutral; production never calls it.
  @visibleForTesting
  static int? debugLibp2pListenPort(
    List<String> listenAddresses, {
    required bool quic,
  }) =>
      _libp2pListenPort(listenAddresses, quic: quic);

  void _setLocalDiscoveryActive() {
    _localDiscoveryActive = true;
    _recordLanAvailability(
      discoveryActive: true,
      discoveredPeerCount: _localP2P?.discoveredPeers.length ?? 0,
    );
    _startLanPermProbe();
  }

  void _setLocalDiscoveryInactive() {
    _localDiscoveryActive = false;
    // P4: discovery stopping clears any suspected-denied state (the heuristic
    // only holds while discovery is active).
    _lanPermProbeTimer?.cancel();
    _lanPermProbeTimer = null;
    _recordLanAvailability(discoveryActive: false, discoveredPeerCount: 0);
  }

  /// P4: (re)arm the one-shot suspected-permission-denied heuristic. Cancels any
  /// in-flight timer and starts a fresh 12s probe; if discovery is still active
  /// with zero discovered peers when it fires, re-records the snapshot with
  /// `suspectedPermissionDenied: true`. Labelled "suspected" because a user
  /// genuinely alone on the LAN produces the same zero-peers signal.
  void _startLanPermProbe() {
    _lanPermProbeTimer?.cancel();
    _lanPermProbeTimer = Timer(const Duration(seconds: 12), () {
      _lanPermProbeTimer = null;
      final peerCount = _localP2P?.discoveredPeers.length ?? 0;
      if (_localDiscoveryActive && peerCount == 0) {
        emitFlowEvent(
          layer: 'FL',
          event: 'LOCAL_MDNS_SUSPECTED_PERMISSION_DENIED',
          details: {'discoveryActive': true, 'discoveredPeerCount': 0},
        );
        _recordLanAvailability(
          discoveryActive: true,
          discoveredPeerCount: 0,
          suspectedPermissionDenied: true,
        );
      }
    });
  }

  void _recordLanAvailability({
    required bool discoveryActive,
    required int discoveredPeerCount,
    bool suspectedPermissionDenied = false,
  }) {
    _transportMetrics?.updateLanAvailability(
      LanAvailabilitySnapshot(
        discoveryActive: discoveryActive,
        discoveredPeerCount: discoveryActive ? discoveredPeerCount : 0,
        suspectedPermissionDenied: suspectedPermissionDenied,
      ),
    );
  }

  /// FDC-11: forward bonsoir-discovered same-WiFi peers carrying libp2p QUIC/TCP
  /// multiaddrs to the Go LAN-direct dial (`lan:peer_found`). Each peer is
  /// forwarded at most once (the Go side also debounces per-peer). Gated by the
  /// `'p2p_lan_dial'` account-migration runtime gate: because bonsoir emits
  /// peer-found events continuously for the app lifetime, a delivered event can
  /// land AFTER a migration starts — so this needs its own runtime gate at the
  /// forward point (the `'p2p_lan_discovery'` startup gate fires only once).
  Future<void> _forwardLanPeersToLibp2pDial(
    Map<String, LocalPeer> peers,
  ) async {
    for (final peer in peers.values) {
      if (peer.libp2pAddresses.isEmpty) {
        // 179 (CV-34): resolved-but-empty libp2pAddresses — the remote (the
        // iPhone, in the device repro) advertised a portless TXT, so the Go LAN
        // dial can't fire. On HEAD this was a SILENT `continue`, indistinguishable
        // on device from "never resolved". Make it observable AND re-read the
        // peer's possibly-healed TXT, both bounded to once per empty episode so
        // the ~20s flap can't storm. The guard resets when the peer heals (below)
        // or drops from the snapshot (the discovery listener).
        if (_lanEmptyReResolvedPeerIds.add(peer.peerId)) {
          emitFlowEvent(
            layer: 'FL',
            event: 'LOCAL_MDNS_PEER_SKIPPED_NO_LIBP2P_ADDR',
            details: {'peerId': peer.peerId, 'host': peer.host},
          );
          unawaited(_reResolveEmptyLanPeer(peer.peerId));
        }
        continue;
      }
      // Has addresses → it healed; allow a future empty episode to re-fire.
      _lanEmptyReResolvedPeerIds.remove(peer.peerId);
      if (_lanDialForwardedPeerIds.contains(peer.peerId)) continue;
      if (!await _allowsAccountNetworkSideEffects(
        'p2p_lan_dial',
        peerId: peer.peerId,
      )) {
        // Gate paused (migration in progress): drop this event and leave the
        // peer un-forwarded so a later snapshot retries once the gate reopens.
        continue;
      }
      _lanDialForwardedPeerIds.add(peer.peerId);
      try {
        await callP2PLanPeerFound(
          _bridge,
          peerId: peer.peerId,
          addresses: peer.libp2pAddresses,
        );
      } catch (e) {
        // Transient bridge failure — allow a later snapshot to retry.
        _lanDialForwardedPeerIds.remove(peer.peerId);
        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_LAN_PEER_FOUND_FORWARD_ERROR',
          details: {'error': e.toString()},
        );
      }
    }
  }

  /// 179 (CV-34): re-read an empty-address LAN peer's TXT on demand so a healed
  /// advert (the remote re-advertised its libp2p ports) is picked up without
  /// waiting on the discoverer's retained stale cache. The resolved peer flows
  /// back through `discoveredPeersStream`, re-driving the forward. RESOLVE/browse
  /// only — it never advertises, so it cannot reopen the iOS broadcast watchdog
  /// gate. Bounded by the caller via [_lanEmptyReResolvedPeerIds].
  Future<void> _reResolveEmptyLanPeer(String peerId) async {
    final localP2P = _localP2P;
    if (localP2P == null) return;
    try {
      await localP2P.discoverLocalPeer(
        peerId,
        timeout: const Duration(seconds: 3),
      );
    } catch (_) {
      // Best-effort: a later snapshot retries once the empty-episode guard resets.
    }
  }

  /// Maximum number of inbox pages to drain in a single pass.
  /// Prevents infinite loops if the server keeps returning hasMore.
  static const int maxInboxPages = 10;

  static const int maxRecoverableInboxReplayEntries = 500;

  /// 147: upper bound on how many staged `chat_message` entries are decrypted
  /// CONCURRENTLY by the inbox-drain pre-decrypt pass before the serial commit
  /// loop. Decrypt is stateless ML-KEM-768 + AES-GCM on lock-free, genuinely
  /// concurrent native threads, so overlapping N round-trips is safe and faster
  /// than serializing them — but the native pools are UNBOUNDED, so the fan-out
  /// must be capped here (never one thread per inbox entry). Commit/persist
  /// still runs serially and in arrival order.
  static const int maxConcurrentInboxDecrypts = 6;

  String _normalizeInboxTimestamp(dynamic ts) {
    if (ts is int) {
      return DateTime.fromMillisecondsSinceEpoch(
        ts,
        isUtc: true,
      ).toIso8601String();
    }
    if (ts is String && ts.isNotEmpty) {
      return ts;
    }
    return DateTime.now().toUtc().toIso8601String();
  }

  String? _messageTypeFromEnvelope(String envelope) {
    try {
      final decoded = jsonDecode(envelope) as Map<String, dynamic>;
      return decoded['type']?.toString();
    } catch (_) {
      return null;
    }
  }

  InboxStagingEntry? _stagingEntryFromRawInboxMessage(
    Map<String, dynamic> raw,
    String ownerPeerId,
  ) {
    final entryId = raw['id']?.toString();
    final from = raw['from']?.toString();
    final envelope = raw['message']?.toString();
    if (entryId == null ||
        entryId.isEmpty ||
        from == null ||
        from.isEmpty ||
        envelope == null ||
        envelope.isEmpty) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_INBOX_STAGE_SKIP_MALFORMED',
        details: {
          'hasEntryId': entryId != null && entryId.isNotEmpty,
          'hasFrom': from != null && from.isNotEmpty,
          'hasEnvelope': envelope != null && envelope.isNotEmpty,
        },
      );
      return null;
    }

    return InboxStagingEntry(
      entryId: entryId,
      ownerPeerId: ownerPeerId,
      senderPeerId: from,
      messageType: _messageTypeFromEnvelope(envelope),
      relayTimestamp: _normalizeInboxTimestamp(raw['timestamp']),
      envelope: envelope,
      stagedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  InboxStagingEntry? _stagingEntryFromDirectMessage(
    ChatMessage message, {
    String? messageType,
  }) {
    final nonce = message.confirmNonce;
    final ownerPeerId = message.to.isNotEmpty
        ? message.to
        : (_currentState.peerId ?? '');
    if (nonce == null ||
        nonce.isEmpty ||
        ownerPeerId.isEmpty ||
        message.from.isEmpty ||
        message.content.isEmpty) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_DIRECT_STAGE_SKIP_MALFORMED',
        details: {
          'hasNonce': nonce != null && nonce.isNotEmpty,
          'hasOwner': ownerPeerId.isNotEmpty,
          'hasFrom': message.from.isNotEmpty,
          'hasEnvelope': message.content.isNotEmpty,
        },
      );
      return null;
    }

    return InboxStagingEntry(
      entryId: 'direct:$nonce',
      ownerPeerId: ownerPeerId,
      senderPeerId: message.from,
      messageType: messageType ?? _messageTypeFromEnvelope(message.content),
      relayTimestamp: _normalizeInboxTimestamp(message.timestamp),
      envelope: message.content,
      stagedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  InboxStagingEntry? _stagingEntryFromLanMessage(
    LocalChatMessage message, {
    required String nonce,
    String? messageType,
  }) {
    final ownerPeerId = message.to.isNotEmpty
        ? message.to
        : (_currentState.peerId ?? '');
    if (nonce.isEmpty ||
        ownerPeerId.isEmpty ||
        message.from.isEmpty ||
        message.content.isEmpty) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_LAN_STAGE_SKIP_MALFORMED',
        details: {
          'hasNonce': nonce.isNotEmpty,
          'hasOwner': ownerPeerId.isNotEmpty,
          'hasFrom': message.from.isNotEmpty,
          'hasEnvelope': message.content.isNotEmpty,
        },
      );
      return null;
    }

    return InboxStagingEntry(
      entryId: 'lan:$nonce',
      ownerPeerId: ownerPeerId,
      senderPeerId: message.from,
      messageType: messageType ?? _messageTypeFromEnvelope(message.content),
      relayTimestamp: message.timestamp.toUtc().toIso8601String(),
      envelope: message.content,
      stagedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  bool _shouldDurablyStageDeferredDirectChat(
    ChatMessage message, {
    required String? envelopeType,
  }) {
    final nonce = message.confirmNonce;
    if (!message.isIncoming || nonce == null || nonce.isEmpty) {
      return false;
    }
    // F7: reactions/deletions join chat in the live-direct stage-before-ack
    // path when their replay callback is wired (else fall through to emit).
    switch (envelopeType) {
      case 'chat_message':
        return _replayRecoveredInboxChatMessage != null;
      case 'message_reaction':
        return _replayRecoveredInboxReaction != null;
      case 'message_deletion':
        return _replayRecoveredInboxMessageDeletion != null;
      default:
        return false;
    }
  }

  ChatMessage _messageWithoutConfirmNonce(ChatMessage message) {
    return ChatMessage(
      from: message.from,
      to: message.to,
      content: message.content,
      timestamp: message.timestamp,
      isIncoming: message.isIncoming,
      transport: message.transport,
    );
  }

  Future<void> _processDurablyStagedDirectChat(
    ChatMessage message, {
    required InboxStagingEntry entry,
  }) async {
    final repo = _inboxStagingRepository;
    // 118: a LIVE direct chat message routes through the notify-capable callback,
    // never the suppressing recovery callback. Deliberately NO `?? recovery`
    // fallback (unlike the LAN path) — if the live-direct callback is somehow
    // absent we emit the un-staged, notify-capable stream message rather than
    // silently re-suppressing via the recovery callback.
    // F7: reactions/deletions select their own recovery callback by messageType;
    // the event-name suffix follows so flow logs stay disambiguable per family.
    final ReplayRecoveredInboxChatMessage? selectedReplay;
    final String eventSuffix;
    switch (entry.messageType) {
      case 'message_reaction':
        selectedReplay = _replayRecoveredInboxReaction;
        eventSuffix = 'REACTION';
        break;
      case 'message_deletion':
        selectedReplay = _replayRecoveredInboxMessageDeletion;
        eventSuffix = 'DELETION';
        break;
      default:
        selectedReplay = _replayLiveDirectChatMessage;
        eventSuffix = 'CHAT';
        break;
    }
    final replayLiveDirectChatMessage = selectedReplay;
    if (replayLiveDirectChatMessage == null) {
      _emitIncomingMessage(message);
      return;
    }

    try {
      await repo.stageEntries([entry]);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_DIRECT_STAGE_ERROR',
        details: {
          'entryId': entry.entryId.length > 8
              ? entry.entryId.substring(0, 8)
              : entry.entryId,
          'error': e.toString(),
        },
      );
      _emitIncomingMessage(message);
      return;
    }

    final nonce = message.confirmNonce!;
    try {
      await callP2PConfirmDirectMessage(_bridge, nonce: nonce, ok: true);
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_DIRECT_STAGE_CONFIRM_SUCCESS',
        details: {
          'entryId': entry.entryId.length > 8
              ? entry.entryId.substring(0, 8)
              : entry.entryId,
        },
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_DIRECT_STAGE_CONFIRM_ERROR',
        details: {
          'entryId': entry.entryId.length > 8
              ? entry.entryId.substring(0, 8)
              : entry.entryId,
          'error': e.toString(),
        },
      );
    }

    final replayMessage = _messageWithoutConfirmNonce(message);
    try {
      final outcome = await replayLiveDirectChatMessage(
        replayMessage,
        stagedEntryId: entry.entryId,
      );
      await _applyRecoveredInboxOutcome(
        repo: repo,
        entry: entry,
        outcome: outcome,
        committedEvent: 'P2P_SERVICE_DIRECT_STAGED_${eventSuffix}_COMMITTED',
        retryableEvent: 'P2P_SERVICE_DIRECT_STAGED_${eventSuffix}_RETRYABLE',
        rejectedEvent: 'P2P_SERVICE_DIRECT_STAGED_${eventSuffix}_REJECTED',
        quarantinedEvent:
            'P2P_SERVICE_DIRECT_STAGED_${eventSuffix}_QUARANTINED',
      );
    } catch (e) {
      await repo.markRetryable(
        entry.entryId,
        reasonCode: 'processing_error',
        reasonDetail: e.toString(),
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_DIRECT_STAGED_${eventSuffix}_EXCEPTION',
        details: {
          'entryId': entry.entryId.length > 8
              ? entry.entryId.substring(0, 8)
              : entry.entryId,
          'error': e.toString(),
        },
      );
    }
  }

  Future<void> _replayDurablyStagedLanChat(
    ChatMessage message, {
    required InboxStagingEntry entry,
  }) async {
    final repo = _inboxStagingRepository;
    // F7: select the replay callback + event-name suffix per family (mirrors the
    // live-direct path). Chat keeps its `?? recovery` fallback; reaction/deletion
    // use their dedicated recovery callbacks.
    final ReplayRecoveredInboxChatMessage? replayLanChatMessage;
    final String eventSuffix;
    switch (entry.messageType) {
      case 'message_reaction':
        replayLanChatMessage = _replayRecoveredInboxReaction;
        eventSuffix = 'REACTION';
        break;
      case 'message_deletion':
        replayLanChatMessage = _replayRecoveredInboxMessageDeletion;
        eventSuffix = 'DELETION';
        break;
      default:
        replayLanChatMessage =
            _replayLiveLanChatMessage ?? _replayRecoveredInboxChatMessage;
        eventSuffix = 'CHAT';
        break;
    }
    if (replayLanChatMessage == null) {
      _emitIncomingMessage(message);
      return;
    }

    try {
      final outcome = await replayLanChatMessage(
        message,
        stagedEntryId: entry.entryId,
      );
      await _applyRecoveredInboxOutcome(
        repo: repo,
        entry: entry,
        outcome: outcome,
        committedEvent: 'P2P_SERVICE_LAN_STAGED_${eventSuffix}_COMMITTED',
        retryableEvent: 'P2P_SERVICE_LAN_STAGED_${eventSuffix}_RETRYABLE',
        rejectedEvent: 'P2P_SERVICE_LAN_STAGED_${eventSuffix}_REJECTED',
        quarantinedEvent: 'P2P_SERVICE_LAN_STAGED_${eventSuffix}_QUARANTINED',
      );
    } catch (e) {
      await repo.markRetryable(
        entry.entryId,
        reasonCode: 'processing_error',
        reasonDetail: e.toString(),
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_LAN_STAGED_${eventSuffix}_EXCEPTION',
        details: {
          'entryId': entry.entryId.length > 8
              ? entry.entryId.substring(0, 8)
              : entry.entryId,
          'error': e.toString(),
        },
      );
    }
  }

  void _emitIncomingMessage(ChatMessage message) {
    if (!_messageController.isClosed) {
      _messageController.add(message);
    }
  }

  /// 147: bounded-concurrent decrypt fan-out for one page of staged inbox
  /// entries. Decrypts each `chat_message` entry's v2 envelope via the injected
  /// [_predecryptInboxChatEntry] fn, returning a `{entryId -> inner plaintext}`
  /// map the serial commit loop threads into each replay. Concurrency is capped
  /// at [maxConcurrentInboxDecrypts] using the index-counter + `Future.wait`
  /// worker pattern (mirrors `drainGroupOfflineInbox`) so the unbounded native
  /// pools never get one thread per entry. Per-entry failures are swallowed (the
  /// entry is omitted → it decrypts in-handler, never dropped). Returns an empty
  /// map when the fn is unwired (default-off, byte-identical to HEAD).
  Future<Map<String, String>> _predecryptInboxChatEntries(
    List<InboxStagingEntry> entries,
  ) async {
    final predecrypt = _predecryptInboxChatEntry;
    if (predecrypt == null) return const {};
    final chatEntries = entries
        .where((e) => e.messageType == 'chat_message')
        .toList(growable: false);
    if (chatEntries.isEmpty) return const {};

    final plaintextByEntryId = <String, String>{};
    var nextIndex = 0;

    Future<void> decryptNext() async {
      while (true) {
        final index = nextIndex;
        nextIndex++;
        if (index >= chatEntries.length) return;
        final entry = chatEntries[index];
        try {
          final plaintext = await predecrypt(entry.toChatMessage());
          if (plaintext != null) {
            plaintextByEntryId[entry.entryId] = plaintext;
          }
        } catch (e) {
          // A prefetch decrypt failure is non-fatal: omit the entry so the
          // serial loop's handler decrypts it itself (with full disposition).
          emitFlowEvent(
            layer: 'FL',
            event: 'P2P_SERVICE_INBOX_PREDECRYPT_ERROR',
            details: {
              'entryId': entry.entryId.length > 8
                  ? entry.entryId.substring(0, 8)
                  : entry.entryId,
              'error': e.toString(),
            },
          );
        }
      }
    }

    final workerCount = chatEntries.length < maxConcurrentInboxDecrypts
        ? chatEntries.length
        : maxConcurrentInboxDecrypts;
    await Future.wait(
      List<Future<void>>.generate(workerCount, (_) => decryptNext()),
    );
    return plaintextByEntryId;
  }

  Future<int> _replayStagedInboxEntries({List<String>? entryIds}) async {
    final repo = _inboxStagingRepository;

    final entries = entryIds == null
        ? await repo.getRecoverableEntries(
            limit: maxRecoverableInboxReplayEntries,
          )
        : await repo.getRecoverableEntriesByIds(entryIds);

    // 147: bounded-concurrent pre-decrypt pass. Overlaps the per-message
    // decrypt (the expensive, stateless, order-independent part) for this page's
    // chat entries BEFORE the serial commit loop below. The map carries each
    // entry's plaintext into its (unchanged, in-arrival-order) chatReplay; a
    // prefetch miss/failure simply leaves the entry out → it decrypts in-handler.
    final predecryptedByEntryId = await _predecryptInboxChatEntries(entries);
    var replayed = 0;

    for (final entry in entries) {
      final entryStopwatch = Stopwatch()..start();
      final message = entry.toChatMessage();
      try {
        // 118 Phase 1B: keep retried `direct:`/`lan:` entries notify-capable on
        // the recovery sweep. The sweep is otherwise prefix-blind, so a
        // once-live message that fell to `retryable` and is later swept would
        // be silently re-suppressed through the recovery callback. Route by
        // entry-id prefix, falling back to the recovery callback only when the
        // matching live callback is absent. A genuine relay-inbox-recovered
        // entry (no `direct:`/`lan:` prefix) keeps the suppressing callback.
        final ReplayRecoveredInboxChatMessage? chatReplay;
        if (entry.entryId.startsWith('direct:')) {
          chatReplay =
              _replayLiveDirectChatMessage ?? _replayRecoveredInboxChatMessage;
        } else if (entry.entryId.startsWith('lan:')) {
          chatReplay =
              _replayLiveLanChatMessage ?? _replayRecoveredInboxChatMessage;
        } else {
          chatReplay = _replayRecoveredInboxChatMessage;
        }
        if (entry.messageType == 'chat_message' && chatReplay != null) {
          final predecryptedText = predecryptedByEntryId[entry.entryId];
          final outcome = await chatReplay(
            predecryptedText != null
                ? message.copyWith(predecryptedText: predecryptedText)
                : message,
            stagedEntryId: entry.entryId,
          );
          if (await _applyRecoveredInboxOutcome(
            repo: repo,
            entry: entry,
            outcome: outcome,
            committedEvent: 'P2P_SERVICE_INBOX_STAGED_CHAT_COMMITTED',
            retryableEvent: 'P2P_SERVICE_INBOX_STAGED_CHAT_RETRYABLE',
            rejectedEvent: 'P2P_SERVICE_INBOX_STAGED_CHAT_REJECTED',
            quarantinedEvent: 'P2P_SERVICE_INBOX_STAGED_CHAT_QUARANTINED',
          )) {
            replayed++;
            entryStopwatch.stop();
            emitFlowEvent(
              layer: 'FL',
              event: 'INBOX_DELIVERY_TIMING',
              details: {
                'deliveryMs': entryStopwatch.elapsedMilliseconds,
                'messageId': entry.entryId.length > 8
                    ? entry.entryId.substring(0, 8)
                    : entry.entryId,
              },
            );
          }
          continue;
        }

        final replayRecoveredInboxIntroductionMessage =
            _replayRecoveredInboxIntroductionMessage;
        if (entry.messageType == 'introduction' &&
            replayRecoveredInboxIntroductionMessage != null) {
          final outcome = await replayRecoveredInboxIntroductionMessage(
            message,
          );
          if (await _applyRecoveredInboxOutcome(
            repo: repo,
            entry: entry,
            outcome: outcome,
            committedEvent: 'P2P_SERVICE_INBOX_STAGED_INTRO_COMMITTED',
            retryableEvent: 'P2P_SERVICE_INBOX_STAGED_INTRO_RETRYABLE',
            rejectedEvent: 'P2P_SERVICE_INBOX_STAGED_INTRO_REJECTED',
            quarantinedEvent: 'P2P_SERVICE_INBOX_STAGED_INTRO_QUARANTINED',
          )) {
            replayed++;
            entryStopwatch.stop();
            emitFlowEvent(
              layer: 'FL',
              event: 'INBOX_DELIVERY_TIMING',
              details: {
                'deliveryMs': entryStopwatch.elapsedMilliseconds,
                'messageId': entry.entryId.length > 8
                    ? entry.entryId.substring(0, 8)
                    : entry.entryId,
              },
            );
          }
          continue;
        }

        // 171: relay-inbox replay of a cold-receiver contact_request. Runs the
        // SAME listener processing (auto-add + reciprocal + confirm) as the
        // live broadcast — the dominant-bug fix — and the durable contact/
        // request row is written by the callback BEFORE _applyRecoveredInbox
        // Outcome deletes the staged entry (INV-1). MUST route through
        // processIncomingMessage (NOT handleIncomingMessage directly), or a
        // cold B commits-and-deletes but never becomes mutual.
        final replayRecoveredInboxContactRequest =
            _replayRecoveredInboxContactRequest;
        if (entry.messageType == 'contact_request' &&
            replayRecoveredInboxContactRequest != null) {
          final outcome = await replayRecoveredInboxContactRequest(message);
          if (await _applyRecoveredInboxOutcome(
            repo: repo,
            entry: entry,
            outcome: outcome,
            committedEvent:
                'P2P_SERVICE_INBOX_STAGED_CONTACT_REQUEST_COMMITTED',
            retryableEvent:
                'P2P_SERVICE_INBOX_STAGED_CONTACT_REQUEST_RETRYABLE',
            rejectedEvent: 'P2P_SERVICE_INBOX_STAGED_CONTACT_REQUEST_REJECTED',
            quarantinedEvent:
                'P2P_SERVICE_INBOX_STAGED_CONTACT_REQUEST_QUARANTINED',
          )) {
            replayed++;
            entryStopwatch.stop();
            emitFlowEvent(
              layer: 'FL',
              event: 'INBOX_DELIVERY_TIMING',
              details: {
                'deliveryMs': entryStopwatch.elapsedMilliseconds,
                'messageId': entry.entryId.length > 8
                    ? entry.entryId.substring(0, 8)
                    : entry.entryId,
              },
            );
          }
          continue;
        }

        // F7: reactions/deletions get the chat machinery — stage stays put until
        // the listener's saveReaction / saveMessage(tombstone) commits. Without
        // these arms the entry takes the generic fall-through below: a bare emit
        // then immediate deleteEntry BEFORE the listener persisted, so a kill in
        // that window loses the reaction/deletion permanently. When the callback
        // is null we preserve the legacy fall-through (existing tests).
        final replayRecoveredInboxReaction = _replayRecoveredInboxReaction;
        if (entry.messageType == 'message_reaction' &&
            replayRecoveredInboxReaction != null) {
          final outcome = await replayRecoveredInboxReaction(
            message,
            stagedEntryId: entry.entryId,
          );
          if (await _applyRecoveredInboxOutcome(
            repo: repo,
            entry: entry,
            outcome: outcome,
            committedEvent: 'P2P_SERVICE_INBOX_STAGED_REACTION_COMMITTED',
            retryableEvent: 'P2P_SERVICE_INBOX_STAGED_REACTION_RETRYABLE',
            rejectedEvent: 'P2P_SERVICE_INBOX_STAGED_REACTION_REJECTED',
            quarantinedEvent: 'P2P_SERVICE_INBOX_STAGED_REACTION_QUARANTINED',
          )) {
            replayed++;
            entryStopwatch.stop();
            emitFlowEvent(
              layer: 'FL',
              event: 'INBOX_DELIVERY_TIMING',
              details: {
                'deliveryMs': entryStopwatch.elapsedMilliseconds,
                'messageId': entry.entryId.length > 8
                    ? entry.entryId.substring(0, 8)
                    : entry.entryId,
              },
            );
          }
          continue;
        }

        final replayRecoveredInboxMessageDeletion =
            _replayRecoveredInboxMessageDeletion;
        if (entry.messageType == 'message_deletion' &&
            replayRecoveredInboxMessageDeletion != null) {
          final outcome = await replayRecoveredInboxMessageDeletion(
            message,
            stagedEntryId: entry.entryId,
          );
          if (await _applyRecoveredInboxOutcome(
            repo: repo,
            entry: entry,
            outcome: outcome,
            committedEvent: 'P2P_SERVICE_INBOX_STAGED_DELETION_COMMITTED',
            retryableEvent: 'P2P_SERVICE_INBOX_STAGED_DELETION_RETRYABLE',
            rejectedEvent: 'P2P_SERVICE_INBOX_STAGED_DELETION_REJECTED',
            quarantinedEvent: 'P2P_SERVICE_INBOX_STAGED_DELETION_QUARANTINED',
          )) {
            replayed++;
            entryStopwatch.stop();
            emitFlowEvent(
              layer: 'FL',
              event: 'INBOX_DELIVERY_TIMING',
              details: {
                'deliveryMs': entryStopwatch.elapsedMilliseconds,
                'messageId': entry.entryId.length > 8
                    ? entry.entryId.substring(0, 8)
                    : entry.entryId,
              },
            );
          }
          continue;
        }

        final forwarded = await _handleMessageReceived(message);
        if (!forwarded) {
          continue;
        }
        await repo.deleteEntry(entry.entryId);
        replayed++;

        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_INBOX_STAGED_FORWARD_COMPLETE',
          details: {
            'entryId': entry.entryId.length > 8
                ? entry.entryId.substring(0, 8)
                : entry.entryId,
            'messageType': entry.messageType,
          },
        );
        entryStopwatch.stop();
        emitFlowEvent(
          layer: 'FL',
          event: 'INBOX_DELIVERY_TIMING',
          details: {
            'deliveryMs': entryStopwatch.elapsedMilliseconds,
            'messageId': entry.entryId.length > 8
                ? entry.entryId.substring(0, 8)
                : entry.entryId,
          },
        );
      } catch (e) {
        await repo.markRetryable(
          entry.entryId,
          reasonCode: 'processing_error',
          reasonDetail: e.toString(),
        );
        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_INBOX_STAGED_REPLAY_EXCEPTION',
          details: {
            'entryId': entry.entryId.length > 8
                ? entry.entryId.substring(0, 8)
                : entry.entryId,
            'error': e.toString(),
          },
        );
      }
    }

    return replayed;
  }

  Future<void> _quarantineRecoveredInboxEntry({
    required InboxStagingRepository repo,
    required InboxStagingEntry entry,
    required String quarantinedEvent,
    required String reasonCode,
    String? reasonDetail,
  }) async {
    await repo.markQuarantined(
      entry.entryId,
      reasonCode: reasonCode,
      reasonDetail: reasonDetail,
    );
    final entryIdShort = entry.entryId.length > 8
        ? entry.entryId.substring(0, 8)
        : entry.entryId;
    emitFlowEvent(
      layer: 'FL',
      event: 'INBOX_STAGING_QUARANTINED',
      details: {
        'entryId': entryIdShort,
        'reasonCode': reasonCode,
        'attemptCount': entry.attemptCount + 1,
      },
    );
    emitFlowEvent(
      layer: 'FL',
      event: quarantinedEvent,
      details: {'entryId': entryIdShort, 'reasonCode': reasonCode},
    );
  }

  Future<bool> _applyRecoveredInboxOutcome({
    required InboxStagingRepository repo,
    required InboxStagingEntry entry,
    required RecoveredInboxReplayOutcome outcome,
    required String committedEvent,
    required String retryableEvent,
    required String rejectedEvent,
    required String quarantinedEvent,
  }) async {
    switch (outcome.disposition) {
      case RecoveredInboxChatDisposition.committed:
        await repo.deleteEntry(entry.entryId);
        emitFlowEvent(
          layer: 'FL',
          event: committedEvent,
          details: {
            'entryId': entry.entryId.length > 8
                ? entry.entryId.substring(0, 8)
                : entry.entryId,
            'reasonCode': outcome.reasonCode,
          },
        );
        return true;
      case RecoveredInboxChatDisposition.retryable:
        if (entry.attemptCount >= maxInboxReplayAttempts) {
          await _quarantineRecoveredInboxEntry(
            repo: repo,
            entry: entry,
            quarantinedEvent: quarantinedEvent,
            reasonCode: 'attempt_cap_exceeded',
            reasonDetail:
                'still ${outcome.reasonCode} after ${entry.attemptCount} attempts',
          );
          return false;
        }
        await repo.markRetryable(
          entry.entryId,
          reasonCode: outcome.reasonCode,
          reasonDetail: outcome.reasonDetail,
        );
        emitFlowEvent(
          layer: 'FL',
          event: retryableEvent,
          details: {
            'entryId': entry.entryId.length > 8
                ? entry.entryId.substring(0, 8)
                : entry.entryId,
            'reasonCode': outcome.reasonCode,
          },
        );
        return false;
      case RecoveredInboxChatDisposition.rejected:
        await repo.markRejected(
          entry.entryId,
          reasonCode: outcome.reasonCode,
          reasonDetail: outcome.reasonDetail,
        );
        emitFlowEvent(
          layer: 'FL',
          event: rejectedEvent,
          details: {
            'entryId': entry.entryId.length > 8
                ? entry.entryId.substring(0, 8)
                : entry.entryId,
            'reasonCode': outcome.reasonCode,
          },
        );
        return false;
      case RecoveredInboxChatDisposition.quarantined:
        await _quarantineRecoveredInboxEntry(
          repo: repo,
          entry: entry,
          quarantinedEvent: quarantinedEvent,
          reasonCode: outcome.reasonCode,
          reasonDetail: outcome.reasonDetail,
        );
        return false;
    }
  }

  Future<
    ({
      int replayed,
      int staged,
      bool hasMore,
      bool retrieveSucceeded,
      String? failureReason,
      // 145: per-segment durations of the relay round-trip (additive). Early
      // returns measure only the segments they reached; later ones are 0.
      int retrieveMs,
      int ackMs,
      int replayMs,
    })
  >
  _retrievePendingInboxPage({required String toPeerId, int? timeoutMs}) async {
    final repo = _inboxStagingRepository;

    final retrieveSw = Stopwatch()..start();
    Map<String, dynamic> response;
    try {
      response = await callP2PInboxRetrievePending(
        _bridge,
        timeoutMs: timeoutMs,
      );
    } catch (e) {
      retrieveSw.stop();
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_INBOX_RETRIEVE_PENDING_ERROR',
        details: {
          'reasonCode': 'retrieve_pending_exception',
          'error': e.toString(),
        },
      );
      return (
        replayed: 0,
        staged: 0,
        hasMore: false,
        retrieveSucceeded: false,
        failureReason: e.toString(),
        retrieveMs: retrieveSw.elapsedMilliseconds,
        ackMs: 0,
        replayMs: 0,
      );
    }
    retrieveSw.stop();

    if (response['ok'] != true) {
      final failureReason =
          response['errorMessage']?.toString() ??
          response['errorCode']?.toString() ??
          'retrieve_pending_failed';
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_INBOX_RETRIEVE_PENDING_ERROR',
        details: {
          'reasonCode': 'retrieve_pending_error',
          'errorMessage': response['errorMessage']?.toString(),
        },
      );
      return (
        replayed: 0,
        staged: 0,
        hasMore: false,
        retrieveSucceeded: false,
        failureReason: failureReason,
        retrieveMs: retrieveSw.elapsedMilliseconds,
        ackMs: 0,
        replayMs: 0,
      );
    }

    final rawMessages =
        (response['messages'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        const <Map<String, dynamic>>[];
    if (rawMessages.isEmpty) {
      return (
        replayed: 0,
        staged: 0,
        hasMore: false,
        retrieveSucceeded: true,
        failureReason: null,
        retrieveMs: retrieveSw.elapsedMilliseconds,
        ackMs: 0,
        replayMs: 0,
      );
    }

    final entries = <InboxStagingEntry>[];
    var skippedMalformed = 0;
    for (final raw in rawMessages) {
      final entry = _stagingEntryFromRawInboxMessage(raw, toPeerId);
      if (entry == null) {
        skippedMalformed++;
        continue;
      }
      entries.add(entry);
    }
    if (skippedMalformed > 0) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_INBOX_STAGE_SKIPPED_MALFORMED',
        details: {
          'rawCount': rawMessages.length,
          'stagedCount': entries.length,
          'skippedCount': skippedMalformed,
        },
      );
    }
    if (entries.isEmpty) {
      return (
        replayed: 0,
        staged: 0,
        hasMore: response['hasMore'] == true,
        retrieveSucceeded: true,
        failureReason: null,
        retrieveMs: retrieveSw.elapsedMilliseconds,
        ackMs: 0,
        replayMs: 0,
      );
    }

    final ackableEntryIds = await repo.stageEntries(entries);
    // Re-check the migration gate at the ACK boundary: a drain that passed
    // the entry gate before a Move Account export pause landed must not
    // ACK-delete relay entries afterwards — the relay copy is the only one
    // the new phone can ever receive. Staged-but-unacked entries are
    // deduplicated on a later drain, so skipping the ACK is safe.
    if (ackableEntryIds.isNotEmpty &&
        !await _allowsAccountNetworkSideEffects('p2p_inbox_ack_after_stage')) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_INBOX_ACK_SKIPPED_GATED',
        details: {'requested': ackableEntryIds.length},
      );
      return (
        replayed: 0,
        staged: ackableEntryIds.length,
        hasMore: false,
        retrieveSucceeded: true,
        failureReason: null,
        retrieveMs: retrieveSw.elapsedMilliseconds,
        ackMs: 0,
        replayMs: 0,
      );
    }
    final ackSw = Stopwatch();
    if (ackableEntryIds.isNotEmpty) {
      ackSw.start();
      try {
        final ackResponse = await callP2PInboxAck(
          _bridge,
          entryIds: ackableEntryIds,
        );
        emitFlowEvent(
          layer: 'FL',
          event: ackResponse['ok'] == true
              ? 'P2P_SERVICE_INBOX_ACK_AFTER_STAGE_SUCCESS'
              : 'P2P_SERVICE_INBOX_ACK_AFTER_STAGE_ERROR',
          details: {
            'requested': ackableEntryIds.length,
            'acked': ackResponse['acked'],
            if (ackResponse['ok'] != true)
              'errorMessage': ackResponse['errorMessage'],
          },
        );
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_INBOX_ACK_AFTER_STAGE_EXCEPTION',
          details: {'requested': ackableEntryIds.length, 'error': e.toString()},
        );
      }
      ackSw.stop();
    }

    final replaySw = Stopwatch()..start();
    final replayed = ackableEntryIds.isEmpty
        ? 0
        : await _replayStagedInboxEntries(entryIds: ackableEntryIds);
    replaySw.stop();

    return (
      replayed: replayed,
      staged: ackableEntryIds.length,
      hasMore: response['hasMore'] == true,
      retrieveSucceeded: true,
      failureReason: null,
      retrieveMs: retrieveSw.elapsedMilliseconds,
      ackMs: ackSw.elapsedMilliseconds,
      replayMs: replaySw.elapsedMilliseconds,
    );
  }

  /// Drain queued offline inbox messages and inject them into message stream.
  /// Retrieves the first page on the foreground budget, then continues in the
  /// background when the relay reports remaining backlog.
  Future<void> _drainOfflineInbox({bool waitForAllPages = false}) async {
    // F3 step 2: coalesce concurrent drains onto a single in-flight drain.
    // Loop so that a caller needing the all-pages guarantee, which an in-flight
    // PARTIAL drain cannot satisfy, waits for it and then (re-checking for a
    // newer in-flight drain) runs its own — never two drains in parallel.
    while (true) {
      final inFlight = _drainInProgress;
      if (inFlight == null) break;
      final inFlightCoversUs =
          _drainInProgressWaitsAllPages || !waitForAllPages;
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_INBOX_DRAIN_COALESCED',
        details: {'waitForAllPages': waitForAllPages},
      );
      await inFlight.future;
      if (inFlightCoversUs) return;
    }

    final completer = Completer<void>();
    _drainInProgress = completer;
    _drainInProgressWaitsAllPages = waitForAllPages;
    try {
      await _drainOfflineInboxDurably(waitForAllPages: waitForAllPages);
    } finally {
      _drainInProgress = null;
      _drainInProgressWaitsAllPages = false;
      completer.complete();
    }
  }

  Future<void> _continueDrainingOfflineInboxDurably({
    required String toPeerId,
    required int totalReplayed,
    required int totalStaged,
  }) async {
    var replayed = totalReplayed;
    var staged = totalStaged;

    try {
      for (var page = 1; page < maxInboxPages; page++) {
        // The continuation runs unawaited in the background, so re-check the
        // migration gate per page: a Move Account export pause must stop the
        // drain mid-backlog, not only at the next top-level entry point.
        if (!await _allowsAccountNetworkSideEffects(
          'p2p_drain_offline_inbox_page',
        )) {
          emitFlowEvent(
            layer: 'FL',
            event: 'P2P_SERVICE_INBOX_STAGED_DRAIN_GATED',
            details: {'page': page + 1, 'staged': staged},
          );
          break;
        }
        final result = await _retrievePendingInboxPage(toPeerId: toPeerId);
        replayed += result.replayed;
        staged += result.staged;

        if (!result.retrieveSucceeded) {
          break;
        }

        if (result.staged == 0) {
          break;
        }

        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_INBOX_STAGED_DRAIN_PAGE',
          details: {'page': page + 1, 'staged': staged, 'replayed': replayed},
        );

        if (!result.hasMore) {
          break;
        }
      }

      if (staged > 0 || replayed > 0) {
        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_INBOX_STAGED_DRAIN_BACKGROUND_COMPLETE',
          details: {'staged': staged, 'replayed': replayed},
        );
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_INBOX_STAGED_DRAIN_EXCEPTION',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _drainOfflineInboxDurably({bool waitForAllPages = false}) async {
    try {
      final toPeerId = _currentState.peerId ?? '';
      final replayExistingSw = Stopwatch()..start();
      final replayedExisting = await _replayStagedInboxEntries();
      replayExistingSw.stop();
      final firstPage = await _retrievePendingInboxPage(
        toPeerId: toPeerId,
        timeoutMs: foregroundInboxTimeout.inMilliseconds,
      );

      final totalReplayed = replayedExisting + firstPage.replayed;
      final totalStaged = firstPage.staged;

      if (firstPage.hasMore && totalStaged > 0) {
        final continuation = _continueDrainingOfflineInboxDurably(
          toPeerId: toPeerId,
          totalReplayed: totalReplayed,
          totalStaged: totalStaged,
        );
        if (waitForAllPages) {
          await continuation;
        } else {
          unawaited(continuation);
        }
      }

      if (replayedExisting > 0) {
        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_INBOX_STAGED_REPLAY_RECOVERED',
          details: {'count': replayedExisting},
        );
      }

      if (totalReplayed > 0 || totalStaged > 0) {
        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_INBOX_STAGED_DRAIN_SUCCESS',
          details: {
            'staged': totalStaged,
            'replayed': totalReplayed,
            'note': 'relay entries were staged locally before ack',
            // 145: per-segment durations. replayMs sums the existing-row replay
            // (this method) and the first page's own replay.
            'retrieveMs': firstPage.retrieveMs,
            'ackMs': firstPage.ackMs,
            'replayMs': replayExistingSw.elapsedMilliseconds + firstPage.replayMs,
          },
        );
      }
      if (firstPage.retrieveSucceeded) {
        _recordSuccessfulInboxProof(
          source: 'drain_offline_inbox',
          trigger: 'system_action',
        );
      } else {
        _recordCapabilityProofFailure(
          capability: 'inbox',
          source: 'drain_offline_inbox',
          trigger: 'system_action',
          failureReason: firstPage.failureReason,
        );
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_INBOX_STAGED_DRAIN_EXCEPTION',
        details: {'error': e.toString()},
      );
      _recordCapabilityProofFailure(
        capability: 'inbox',
        source: 'drain_offline_inbox',
        trigger: 'system_action',
        failureReason: e.toString(),
      );
    }
  }

  @override
  Future<bool> stopNode() async {
    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_SERVICE_STOP_NODE_BEGIN',
      details: {},
    );

    _stopped = true;
    try {
      // Stop local WiFi discovery before stopping the relay node
      try {
        await _localP2P?.stop();
        _setLocalDiscoveryInactive();
      } catch (e) {
        if (kDebugMode) debugPrint('[P2PService] Local P2P stop failed: $e');
        _setLocalDiscoveryInactive();
      }

      _stopHealthCheck();
      final response = await callP2PNodeStop(_bridge);

      if (response['ok'] == true) {
        _hasEverBeenOnline = false;
        _lastStartupRelayRecoveryAttemptAt = null;
        _clearActiveReadinessProofWindow();
        _emitState(NodeState.stopped);

        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_STOP_NODE_SUCCESS',
          details: {},
        );

        return true;
      } else {
        _stopped = false;
        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_STOP_NODE_ERROR',
          details: {'errorMessage': response['errorMessage']},
        );
        return false;
      }
    } catch (e) {
      _stopped = false;
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_STOP_NODE_EXCEPTION',
        details: {'error': e.toString()},
      );
      return false;
    }
  }

  @override
  Future<bool> sendMessage(String peerId, String message) async {
    if (!await _allowsAccountNetworkSideEffects('p2p_send_message')) {
      return false;
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_SERVICE_SEND_MESSAGE_BEGIN',
      details: {'peerId': peerId, 'messageLength': message.length},
    );

    try {
      final response = await callP2PMessageSend(
        _bridge,
        peerId: peerId,
        message: message,
      );

      if (response['ok'] == true) {
        final sent = response['sent'] as bool?;
        final acked = response['acked'] as bool?;
        final reply = response['reply'] as String?;
        final acknowledged = acked ?? (reply != null && reply.isNotEmpty);

        if ((sent ?? true) && acknowledged) {
          emitFlowEvent(
            layer: 'FL',
            event: 'P2P_SERVICE_SEND_MESSAGE_SUCCESS',
            details: {
              'peerId': peerId,
              'acked': acked,
              'hasReply': reply != null,
            },
          );
          return true;
        }

        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_SEND_MESSAGE_UNACKED',
          details: {
            'peerId': peerId,
            'acked': acked,
            'hasReply': reply != null,
          },
        );
        return false;
      } else {
        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_SEND_MESSAGE_ERROR',
          details: {'errorMessage': response['errorMessage']},
        );
        return false;
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_SEND_MESSAGE_EXCEPTION',
        details: {'error': e.toString()},
      );
      return false;
    }
  }

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String peerId,
    String message, {
    int? timeoutMs,
  }) async {
    if (!await _allowsAccountNetworkSideEffects(
      'p2p_send_message_with_reply',
    )) {
      return const SendMessageResult(sent: false);
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_SERVICE_SEND_MESSAGE_WITH_REPLY_BEGIN',
      details: {'peerId': peerId, 'messageLength': message.length},
    );

    try {
      final response = await callP2PMessageSend(
        _bridge,
        peerId: peerId,
        message: message,
        timeoutMs: timeoutMs,
      );

      if (response['ok'] == true) {
        final reply = response['reply'] as String?;
        final acked = response['acked'] as bool?;
        final transport = response['transport']?.toString();
        final streamOpenMs = response['streamOpenMs'] as int?;
        final writeMs = response['writeMs'] as int?;
        final ackWaitMs = response['ackWaitMs'] as int?;
        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_SEND_MESSAGE_WITH_REPLY_SUCCESS',
          details: {
            'peerId': peerId,
            'hasReply': reply != null,
            'acked': acked,
            'transport': transport,
          },
        );
        return SendMessageResult(
          sent: true,
          acked: acked,
          reply: reply,
          transport: transport,
          streamOpenMs: streamOpenMs,
          writeMs: writeMs,
          ackWaitMs: ackWaitMs,
        );
      } else {
        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_SEND_MESSAGE_WITH_REPLY_ERROR',
          details: {'errorMessage': response['errorMessage']},
        );
        return const SendMessageResult(sent: false);
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_SEND_MESSAGE_WITH_REPLY_EXCEPTION',
        details: {'error': e.toString()},
      );
      return const SendMessageResult(sent: false);
    }
  }

  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId, {int? timeoutMs}) async {
    if (!await _allowsAccountNetworkSideEffects('p2p_discover_peer')) {
      return null;
    }

    final details = <String, dynamic>{'peerId': peerId};
    if (timeoutMs != null) {
      details['timeoutMs'] = timeoutMs;
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_SERVICE_DISCOVER_PEER_BEGIN',
      details: details,
    );

    try {
      final namespace = 'mknoon:chat:$peerId';
      final response = await callP2PRendezvousDiscover(
        _bridge,
        peerId: peerId,
        namespace: namespace,
        timeoutMs: timeoutMs,
      );

      if (response['ok'] == true) {
        final peers = response['peers'] as List<dynamic>?;
        if (peers != null && peers.isNotEmpty) {
          final peerData = peers.first as Map<String, dynamic>;
          final peer = DiscoveredPeer.fromJson(peerData);

          emitFlowEvent(
            layer: 'FL',
            event: 'P2P_SERVICE_DISCOVER_PEER_SUCCESS',
            details: {'peerId': peerId, 'addressCount': peer.addresses.length},
          );

          return peer;
        }
      }

      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_DISCOVER_PEER_NOT_FOUND',
        details: {'peerId': peerId},
      );

      return null;
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_DISCOVER_PEER_EXCEPTION',
        details: {'error': e.toString()},
      );
      return null;
    }
  }

  @override
  Future<bool> dialPeer(
    String peerId, {
    List<String>? addresses,
    int? timeoutMs,
    bool preferQuic = false,
  }) async {
    if (!await _allowsAccountNetworkSideEffects('p2p_dial_peer')) {
      return false;
    }

    final details = <String, dynamic>{
      'peerId': peerId,
      'hasAddresses': addresses != null,
    };
    if (timeoutMs != null) {
      details['timeoutMs'] = timeoutMs;
    }
    // FDC-04 (DESIGN-5): host-observable threading of the QUIC-first intent.
    // INERT on the wire — Go's peer:dial drops unknown JSON fields.
    if (preferQuic) {
      details['preferQuic'] = true;
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_SERVICE_DIAL_PEER_BEGIN',
      details: details,
    );

    try {
      final response = await callP2PPeerDial(
        _bridge,
        peerId: peerId,
        addresses: addresses,
        timeoutMs: timeoutMs,
        preferQuic: preferQuic,
      );

      if (response['ok'] == true) {
        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_DIAL_PEER_SUCCESS',
          details: {'peerId': peerId},
        );
        return true;
      } else {
        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_DIAL_PEER_ERROR',
          details: {'errorMessage': response['errorMessage']},
        );
        return false;
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_DIAL_PEER_EXCEPTION',
        details: {'error': e.toString()},
      );
      return false;
    }
  }

  // ─── FDC-04: LAN-aware eager warm ──────────────────────────────────────────

  /// FDC-04 warm budgets. Conservative defaults pending FDC-S1's measured
  /// numbers (swap when S1 lands; record the assumption inline).
  /// - [_warmLanTimeout] bounds the LAN seed (= interactiveLocalBudget 1500ms).
  /// - [_warmDialTimeout] bounds the speculative dial (= the foreground
  ///   InteractiveDialTimeout 4s).
  /// - [_warmCooldownFloor]/[_warmCooldownCeil] bound the per-peer escalating
  ///   debounce (libp2p's own per-`(peer,transport)` swarm backoff is 5s->5min).
  static const _warmLanTimeout = Duration(milliseconds: 1500);
  static const _warmDialTimeout = Duration(seconds: 4);
  static const _warmCooldownFloor = Duration(seconds: 5);
  static const _warmCooldownCeil = Duration(minutes: 5);

  static String _shortPeer(String peerId) =>
      peerId.length > 10 ? peerId.substring(0, 10) : peerId;

  @override
  Future<void> warmPeer(String peerId, {bool preferQuic = false}) async {
    // ROBUST-1: total/never-throws. Every call site fires `unawaited(...)` with
    // NO error handler, so any throw from the gate/emit/_warmAttempts body would
    // otherwise leak as an unhandled async error (test-zone failure / prod
    // PlatformDispatcher.onError). Wrap the whole body; clear the in-flight
    // sentinel on any thrown path so a failed warm cannot wedge the debounce.
    final attempt = _warmAttempts.putIfAbsent(peerId, () => _WarmAttempt());
    try {
      // PS-3 / FDC-S5 (INV-4): a strict no-op while the node is not started — it
      // must never contend for the Node.Start write lock. The cold notif-tap
      // win is FDC-07's, not this plan's.
      if (!_currentState.isStarted) {
        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_WARM_PEER_SKIPPED',
          details: {'reason': 'not_started'},
        );
        return;
      }

      // DESIGN-4 + RC3 (INV-3): the in-flight + escalating-cooldown debounce is
      // read AND the in-flight sentinel set SYNCHRONOUSLY here, BEFORE the first
      // await below — so a same-tick conv-open + notif-tap + resume burst
      // collapses to ONE dial, not just sequential repeats.
      final now = clock.now();
      if (attempt.inFlight ||
          (attempt.nextEligibleAt != null &&
              now.isBefore(attempt.nextEligibleAt!))) {
        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_WARM_PEER_DEBOUNCED',
          details: {'peerId': _shortPeer(peerId)},
        );
        return;
      }
      attempt.inFlight = true;

      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_WARM_PEER_BEGIN',
        details: {
          'peerId': _shortPeer(peerId),
          if (preferQuic) 'preferQuic': true,
        },
      );

      // GATE-1: mirror dialPeer's account gate (`p2p_dial_peer`). A denied gate
      // ⇒ no seed/dial, the same observable as PS-3 (no independent TC).
      if (!await _allowsAccountNetworkSideEffects('p2p_warm_peer')) {
        attempt.inFlight = false;
        return;
      }

      // DESIGN-1 / INV-1: AWAIT the bounded LAN seed FIRST, then re-read
      // isLocalPeer to gate the speculative dial. Evaluating isLocalPeer at
      // warm-START would speculative-dial every same-WiFi peer whose LAN entry
      // isn't seeded yet — landing a wasteful /p2p-circuit relay conn and
      // accruing relay backoff. discoverLocalPeer returns as soon as the peer is
      // found, and warm overlaps reading/typing, so the bounded wait is free.
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_WARM_PEER_LAN_SEED',
        details: {'peerId': _shortPeer(peerId)},
      );
      final seededLocal = await discoverLocalPeer(
        peerId,
        timeout: _warmLanTimeout,
      ).catchError((Object _) => false);

      if (seededLocal || isLocalPeer(peerId)) {
        // The LAN lane is viable — leave it for the send-path ranked race to win
        // (INV-2 is the correctness backstop); never relay-dial a same-WiFi peer.
        attempt.inFlight = false;
        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_WARM_PEER_DIAL_SKIPPED',
          details: {'peerId': _shortPeer(peerId), 'reason': 'is_local'},
        );
        return;
      }

      // Non-blocking speculative dial: the call site is never delayed beyond the
      // LAN seed. libp2p coalesces this with the real send dial (FDC-S5 §7), so
      // it is not a wasted connection on the happy path. The outcome handler
      // clears the in-flight sentinel and sets the escalating cooldown.
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_WARM_PEER_DIAL',
        details: {
          'peerId': _shortPeer(peerId),
          if (preferQuic) 'preferQuic': true,
        },
      );
      unawaited(
        dialPeer(
          peerId,
          timeoutMs: _warmDialTimeout.inMilliseconds,
          preferQuic: preferQuic,
        ).then((ok) => _onWarmDialOutcome(peerId, ok)).catchError((Object _) {
          _onWarmDialOutcome(peerId, false);
        }),
      );
    } catch (_) {
      attempt.inFlight = false;
    }
  }

  /// FDC-04: resolves a completed (or failed) speculative warm dial. Success
  /// clears the per-peer entry (next open warms fresh); failure escalates the
  /// cooldown 5s->2x->…->ceil. Always clears the in-flight sentinel.
  void _onWarmDialOutcome(String peerId, bool ok) {
    final attempt = _warmAttempts[peerId];
    if (attempt == null) return;
    attempt.inFlight = false;
    if (ok) {
      _warmAttempts.remove(peerId);
      return;
    }
    attempt.failureCount += 1;
    var interval = _warmCooldownFloor;
    for (var i = 1; i < attempt.failureCount; i++) {
      interval *= 2;
      if (interval >= _warmCooldownCeil) {
        interval = _warmCooldownCeil;
        break;
      }
    }
    attempt.nextEligibleAt = clock.now().add(interval);
  }

  /// FDC-04 (RC4, DESIGN-2/3, INV-6): WiFi<->cellular re-warm of the ONE active
  /// peer (never the roster — PS-4). Total/never-throws (driven by a stream
  /// listener). Resets only [_WarmAttempt.nextEligibleAt] (preserving the
  /// escalation count so a still-failing peer keeps escalating), drops a learned
  /// `local` transport (the network switch closed it), self-debounces flap
  /// bursts to ONE re-warm, and re-fires `warmPeer` preferring QUIC.
  @visibleForTesting
  void onNetworkChanged() {
    try {
      // DESIGN-2: coalesce flap-bursts. A timestamp DISTINCT from the per-peer
      // cooldown — WiFi<->cellular flapping (elevators/transit) must not
      // tight-loop a failing QUIC re-warm and trip the libp2p swarm backoff.
      final now = clock.now();
      if (_lastNetworkRewarmAt != null &&
          now.difference(_lastNetworkRewarmAt!) < _warmCooldownFloor) {
        return;
      }
      _lastNetworkRewarmAt = now;

      // 182: connectivity restored → pull the relay's stored offline inbox
      // IMMEDIATELY, instead of waiting for the next ~30s health-check poll or
      // an app resume. Placed AFTER the flap floor (so a WiFi flap-burst
      // coalesces to ONE drain) but BEFORE the active-peer return below: the
      // inbox drain is roster-wide / account-scoped and must fire even with no
      // conversation open, whereas the warmPeer re-warm is peer-scoped. The
      // PUBLIC drainOfflineInbox inherits the 141 not-started defer, the
      // account-migration network gate, and single-in-flight coalescing, and
      // uses the durable inbox:retrieve_pending path (never the destructive
      // read removed in report 48). Fire-and-forget: a drain failure must not
      // abort the re-warm below (onNetworkChanged is total/never-throws).
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_NETWORK_CHANGE_DRAIN_BEGIN',
        details: {},
      );
      unawaited(drainOfflineInbox().catchError((Object _) {}));

      // PS-4: re-warm only the ONE active peer, never _warmAttempts.keys.
      final peerId = _activePeerId?.call();
      if (peerId == null || peerId.isEmpty) return;

      // Reset the per-peer cooldown to permit an immediate re-warm, but PRESERVE
      // the escalation count (failureCount) so a still-failing peer keeps
      // escalating from where it was.
      _warmAttempts[peerId]?.nextEligibleAt = null;

      // The network switch closed every non-QUIC connection: a learned 'local'
      // transport now points at a dead path. Drop it — an ADDITIVE invalidation
      // trigger, NOT a TTL change (consistent with the disconnect/addresses
      // invalidations that p2p_service_learned_transport_invalidation_test locks).
      final learned = _learnedTransport[peerId];
      if (learned != null && learned.transport == 'local') {
        _learnedTransport.remove(peerId);
      }

      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_WARM_PEER_NETWORK_CHANGE_REWARM',
        details: {'peerId': _shortPeer(peerId)},
      );

      // Prefer QUIC on the re-warm (Go-inert today — DESIGN-5).
      unawaited(warmPeer(peerId, preferQuic: true));
    } catch (_) {
      // total/never-throws
    }
  }

  /// Start the periodic health check timer.
  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    if (kDebugMode) {
      debugPrint(
        '[HEALTH] Starting periodic health check timer '
        '(every ${healthCheckInterval.inSeconds}s)',
      );
    }
    _healthCheckTimer = Timer.periodic(healthCheckInterval, (_) {
      if (kDebugMode) debugPrint('[HEALTH] Periodic health check firing...');
      _performHealthCheck();
    });
  }

  /// Stop the periodic health check timer.
  void _stopHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
  }

  NodeState _stateWithReadinessProjection(
    NodeState state, {
    bool? sendCapabilityReady,
    bool? inboxCapabilityReady,
  }) {
    if (!state.isStarted) {
      return state.copyWith(
        sendCapabilityReady: false,
        inboxCapabilityReady: false,
      );
    }

    return state.copyWith(
      sendCapabilityReady:
          sendCapabilityReady ?? _currentState.sendCapabilityReady,
      inboxCapabilityReady:
          inboxCapabilityReady ?? _currentState.inboxCapabilityReady,
    );
  }

  void _ensureActiveReadinessProofWindow({
    required String phase,
    required String trigger,
    DateTime? startedAt,
  }) {
    if (_activeReadinessProofWindowId != null) {
      return;
    }
    _beginReadinessProofWindow(
      phase: phase,
      trigger: trigger,
      startedAt: startedAt,
    );
  }

  void _beginReadinessProofWindow({
    required String phase,
    required String trigger,
    DateTime? startedAt,
  }) {
    if (!_currentState.isStarted) {
      return;
    }

    final alreadyResetForPhase =
        _activeReadinessPhase == phase &&
        !_currentState.sendCapabilityReady &&
        !_currentState.inboxCapabilityReady;
    if (alreadyResetForPhase) {
      return;
    }

    _readinessProofWindowSequence += 1;
    _activeReadinessProofWindowId = 'readiness_$_readinessProofWindowSequence';
    _activeReadinessPhase = phase;
    _activeReadinessProofWindowStartedAt = startedAt ?? DateTime.now();
    _sendProofAttemptStartedAt = _activeReadinessProofWindowStartedAt;
    _inboxProofAttemptStartedAt = _activeReadinessProofWindowStartedAt;
    _sendProofSource = null;
    _inboxProofSource = null;
    _sendSuccessEventEmitted = false;
    _inboxSuccessEventEmitted = false;
    _proactiveSendProofAttemptedInWindow = false;
    _pendingProactiveSendProofTrigger = null;

    emitFlowEvent(
      layer: 'FL',
      event: 'READINESS_PROOF_WINDOW_START',
      details: {
        'proofWindowId': _activeReadinessProofWindowId,
        'phase': phase,
        'trigger': trigger,
      },
    );

    final resetState = _stateWithReadinessProjection(
      _currentState,
      sendCapabilityReady: false,
      inboxCapabilityReady: false,
    );
    if (_stateMeaningfullyChanged(_currentState, resetState)) {
      _emitState(
        resetState,
        source: 'readiness_window_start',
        mergeServiceOwnedReadiness: false,
      );
    }
  }

  void _clearActiveReadinessProofWindow() {
    _activeReadinessProofWindowId = null;
    _activeReadinessPhase = null;
    _activeReadinessProofWindowStartedAt = null;
    _sendProofAttemptStartedAt = null;
    _inboxProofAttemptStartedAt = null;
    _sendProofSource = null;
    _inboxProofSource = null;
    _sendSuccessEventEmitted = false;
    _inboxSuccessEventEmitted = false;
    _proactiveSendProofAttemptedInWindow = false;
    _pendingProactiveSendProofTrigger = null;
  }

  String _phaseForImplicitReadinessWindow() {
    if (_resumeStartedAt != null) {
      return 'background_resume';
    }
    if (_nodeStartRequestedAt != null && !_hasEverBeenOnline) {
      return _isHotRestart ? 'hot_restart' : 'cold_start';
    }
    return 'recovery';
  }

  DateTime _startedAtForImplicitReadinessWindow() {
    return _resumeStartedAt ??
        _nodeStartRequestedAt ??
        _lastWentOfflineAt ??
        DateTime.now();
  }

  void _emitCapabilitySuccessIfNeeded({
    required String capability,
    required String source,
    required String trigger,
    String? sendPath,
  }) {
    final proofWindowId = _activeReadinessProofWindowId;
    final phase = _activeReadinessPhase;
    final startedAt = _activeReadinessProofWindowStartedAt;
    if (proofWindowId == null || phase == null || startedAt == null) {
      return;
    }

    final totalMs = DateTime.now().difference(startedAt).inMilliseconds;
    if (capability == 'send' && !_sendSuccessEventEmitted) {
      _sendSuccessEventEmitted = true;
      emitFlowEvent(
        layer: 'FL',
        event: 'FIRST_SEND_SUCCESS_IN_WINDOW',
        details: {
          'proofWindowId': proofWindowId,
          'phase': phase,
          'totalMs': totalMs,
          'source': source,
          'sendPath': ?sendPath,
          'trigger': trigger,
        },
      );
      return;
    }

    if (capability == 'inbox' && !_inboxSuccessEventEmitted) {
      _inboxSuccessEventEmitted = true;
      emitFlowEvent(
        layer: 'FL',
        event: 'FIRST_INBOX_SUCCESS_IN_WINDOW',
        details: {
          'proofWindowId': proofWindowId,
          'phase': phase,
          'totalMs': totalMs,
          'source': source,
          'trigger': trigger,
        },
      );
    }
  }

  void _recordCapabilityProofResult({
    required String capability,
    required bool success,
    required String proofSource,
    String? trigger,
    String? sendPath,
    String? failureReason,
  }) {
    _ensureActiveReadinessProofWindow(
      phase: _phaseForImplicitReadinessWindow(),
      trigger: trigger ?? 'implicit_$capability',
      startedAt: _startedAtForImplicitReadinessWindow(),
    );

    final proofWindowId = _activeReadinessProofWindowId;
    final phase = _activeReadinessPhase;
    if (proofWindowId == null || phase == null) {
      return;
    }

    final attemptStartedAt = capability == 'send'
        ? (_sendProofAttemptStartedAt ?? _activeReadinessProofWindowStartedAt)
        : (_inboxProofAttemptStartedAt ?? _activeReadinessProofWindowStartedAt);
    final elapsedMs = attemptStartedAt == null
        ? 0
        : DateTime.now().difference(attemptStartedAt).inMilliseconds;

    emitFlowEvent(
      layer: 'FL',
      event: 'READINESS_PROOF_RESULT',
      details: {
        'proofWindowId': proofWindowId,
        'phase': phase,
        'capability': capability,
        'success': success,
        'proofSource': proofSource,
        'elapsedMs': elapsedMs,
        'trigger': ?trigger,
        'sendPath': ?sendPath,
        if (!success && failureReason != null) 'failureReason': failureReason,
      },
    );

    if (capability == 'send') {
      _sendProofAttemptStartedAt = null;
    } else {
      _inboxProofAttemptStartedAt = null;
    }
  }

  /// Records when the app resumed from background.
  /// Called by lifecycle handler before health check.
  @override
  bool get hasPendingResumeStarted => _resumeStartedAt != null;

  /// Records when the app resumed from background.
  /// Called by lifecycle handler before health check.
  @override
  void markResumeStarted() {
    _resumeStartedAt = DateTime.now();
  }

  /// Clears any unconsumed resume timestamp.
  /// Called in finally block to prevent stale timestamps.
  @override
  void clearResumeStarted() {
    _resumeStartedAt = null;
  }

  @override
  void noteTransportSessionReset({required String trigger}) {
    _beginReadinessProofWindow(
      phase: _resumeStartedAt != null ? 'background_resume' : 'recovery',
      trigger: trigger,
      startedAt: _resumeStartedAt ?? DateTime.now(),
    );
  }

  @override
  void recordSuccessfulSendProof({
    required String source,
    required String trigger,
    String? sendPath,
  }) {
    _recordCapabilityProofResult(
      capability: 'send',
      success: true,
      proofSource: source,
      trigger: trigger,
      sendPath: sendPath,
    );
    _sendProofSource = source;
    _emitCapabilitySuccessIfNeeded(
      capability: 'send',
      source: source,
      trigger: trigger,
      sendPath: sendPath,
    );

    final updatedState = _stateWithReadinessProjection(
      _currentState,
      sendCapabilityReady: true,
    );
    if (_stateMeaningfullyChanged(_currentState, updatedState)) {
      _emitState(
        updatedState,
        source: 'send_proof_success',
        mergeServiceOwnedReadiness: false,
      );
    }
  }

  void _recordSuccessfulInboxProof({
    required String source,
    required String trigger,
  }) {
    _recordCapabilityProofResult(
      capability: 'inbox',
      success: true,
      proofSource: source,
      trigger: trigger,
    );
    _inboxProofSource = source;
    _emitCapabilitySuccessIfNeeded(
      capability: 'inbox',
      source: source,
      trigger: trigger,
    );

    final updatedState = _stateWithReadinessProjection(
      _currentState,
      inboxCapabilityReady: true,
    );
    if (_stateMeaningfullyChanged(_currentState, updatedState)) {
      _emitState(
        updatedState,
        source: 'inbox_proof_success',
        mergeServiceOwnedReadiness: false,
      );
    }

    _retryProactiveSendProofIfNeeded(trigger: 'inbox_proof_success');
  }

  void _recordCapabilityProofFailure({
    required String capability,
    required String source,
    required String trigger,
    String? failureReason,
  }) {
    _recordCapabilityProofResult(
      capability: capability,
      success: false,
      proofSource: source,
      trigger: trigger,
      failureReason: failureReason,
    );

    final updatedState = capability == 'send'
        ? _stateWithReadinessProjection(
            _currentState,
            sendCapabilityReady: false,
          )
        : _stateWithReadinessProjection(
            _currentState,
            inboxCapabilityReady: false,
          );
    if (_stateMeaningfullyChanged(_currentState, updatedState)) {
      _emitState(
        updatedState,
        source: '${capability}_proof_failure',
        mergeServiceOwnedReadiness: false,
      );
    }
  }

  void _retryProactiveSendProofIfNeeded({required String trigger}) {
    if (!_currentState.isStarted ||
        _currentState.sendCapabilityReady ||
        _activeReadinessProofWindowId == null) {
      return;
    }
    if (_proactiveSendProofInFlight) {
      _pendingProactiveSendProofTrigger = trigger;
      return;
    }
    unawaited(_attemptProactiveSendProofIfNeeded(trigger: trigger));
  }

  /// If the badge is already green when resume fires, emit immediately.
  /// Called after handleAppResumed completes.
  void checkResumeAlreadyOnline() {
    if (_resumeStartedAt == null) return;
    if (_stateHasHealthyRelay(_currentState)) {
      emitFlowEvent(
        layer: 'FL',
        event: 'TIME_TO_ONLINE_BADGE',
        details: {
          'totalMs': DateTime.now()
              .difference(_resumeStartedAt!)
              .inMilliseconds,
          'phase': 'background_resume_already_online',
          'source': 'resume_check',
        },
      );
      _resumeStartedAt = null;
    }
  }

  String _buildReadinessSendProbeEnvelope() {
    return jsonEncode({
      'type': 'readiness_proof',
      'version': '1',
      'proofWindowId': _activeReadinessProofWindowId,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Future<void> _attemptProactiveSendProofIfNeeded({
    required String trigger,
  }) async {
    if (!_currentState.isStarted ||
        _currentState.sendCapabilityReady ||
        _activeReadinessProofWindowId == null ||
        _proactiveSendProofAttemptedInWindow ||
        _proactiveSendProofInFlight) {
      return;
    }

    final peerId = _currentState.peerId;
    if (peerId == null || peerId.isEmpty) {
      return;
    }

    if (!await _allowsAccountNetworkSideEffects(
      'p2p_readiness_send_probe',
      peerId: peerId,
    )) {
      return;
    }

    _proactiveSendProofAttemptedInWindow = true;
    _proactiveSendProofInFlight = true;
    _sendProofAttemptStartedAt ??= DateTime.now();
    try {
      final stored = await storeInInbox(
        peerId,
        _buildReadinessSendProbeEnvelope(),
        timeoutMs: foregroundInboxTimeout.inMilliseconds,
      );
      if (stored) {
        recordSuccessfulSendProof(
          source: 'system_inbox_store_probe',
          trigger: 'system_action',
          sendPath: 'inbox',
        );
      } else {
        _proactiveSendProofAttemptedInWindow = false;
        _recordCapabilityProofFailure(
          capability: 'send',
          source: 'system_inbox_store_probe',
          trigger: trigger,
          failureReason: 'store_returned_false',
        );
      }
    } catch (e) {
      _proactiveSendProofAttemptedInWindow = false;
      _recordCapabilityProofFailure(
        capability: 'send',
        source: 'system_inbox_store_probe',
        trigger: trigger,
        failureReason: e.toString(),
      );
    } finally {
      _proactiveSendProofInFlight = false;
      final pendingTrigger = _pendingProactiveSendProofTrigger;
      _pendingProactiveSendProofTrigger = null;
      if (pendingTrigger != null) {
        _retryProactiveSendProofIfNeeded(trigger: pendingTrigger);
      }
    }
  }

  void _beginRecoveryInstrumentation(String recoverySource) {
    _activeRecoverySource = recoverySource;
    final details = <String, dynamic>{'recoverySource': recoverySource};
    final resumeStartedAt = _resumeStartedAt;
    if (resumeStartedAt != null) {
      details['resumeToRecoveryStartMs'] = DateTime.now()
          .difference(resumeStartedAt)
          .inMilliseconds;
    }
    emitFlowEvent(layer: 'FL', event: 'RELAY_RECOVERY_START', details: details);
  }

  void _clearRecoveryInstrumentation() {
    _activeRecoverySource = null;
  }

  Future<void> _attemptRelayRecovery({required String recoverySource}) async {
    if (!await _allowsAccountNetworkSideEffects('p2p_relay_recovery')) {
      return;
    }

    _beginRecoveryInstrumentation(recoverySource);

    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_HEALTH_CHECK_RECOVERY_ATTEMPT',
      details: {
        'method': 'relay:reconnect',
        'consecutiveRefreshFailures': _consecutiveRefreshFailures,
      },
    );

    try {
      final reconnectStart = DateTime.now();
      final reconnectResponse = await callP2PRelayReconnect(_bridge);
      final reconnectMs = DateTime.now()
          .difference(reconnectStart)
          .inMilliseconds;
      final relayRefreshMs =
          (reconnectResponse['relayRefreshMs'] as num?)?.toInt() ?? reconnectMs;
      final relayWarmMs =
          (reconnectResponse['relayWarmMs'] as num?)?.toInt() ?? 0;
      final reserveRpcMs =
          (reconnectResponse['reserveRpcMs'] as num?)?.toInt() ?? 0;
      final relayWarmParallelism =
          (reconnectResponse['relayWarmParallelism'] as num?)?.toInt() ?? 0;
      final foregroundRecoveryPath =
          reconnectResponse['foregroundRecoveryPath'] as String?;
      final foregroundRelayDialTimeoutMs =
          (reconnectResponse['foregroundRelayDialTimeoutMs'] as num?)
              ?.toInt() ??
          0;
      final autorelayRetryCadenceMs =
          (reconnectResponse['autorelayRetryCadenceMs'] as num?)?.toInt() ?? 0;
      final circuitAddressWaitMs =
          (reconnectResponse['circuitAddressWaitMs'] as num?)?.toInt() ?? 0;
      final personalReregisterMs =
          (reconnectResponse['personalReregisterMs'] as num?)?.toInt() ?? 0;
      final coalescedRecoveryRequests =
          (reconnectResponse['coalescedRecoveryRequests'] as num?)?.toInt() ??
          0;

      if (reconnectResponse['ok'] == true) {
        final recoveryMode = reconnectResponse['recoveryMode'] as String?;
        final reusedHost =
            reconnectResponse['reusedHost'] as bool? ??
            recoveryMode != 'watchdog_restart';
        final recoveredSource = recoveryMode == 'watchdog_restart'
            ? 'watchdog_restart'
            : recoverySource;
        if (recoveryMode != null) {
          _lastRecoveryMethod = recoveryMode;
          if (kDebugMode) {
            debugPrint(
              '[HEALTH] relay:reconnect SUCCESS via $recoveryMode '
              '(took ${reconnectMs}ms)',
            );
          }
        } else {
          _lastRecoveryMethod = 'in_place';
          if (kDebugMode) {
            debugPrint(
              '[HEALTH] relay:reconnect SUCCESS (took ${reconnectMs}ms)',
            );
          }
        }
        final totalOutageMs = _outageDetectedAt != null
            ? DateTime.now().difference(_outageDetectedAt!).inMilliseconds
            : reconnectMs;
        emitFlowEvent(
          layer: 'FL',
          event: 'RELAY_OUTAGE_TIMING',
          details: {
            'phase': 'recovered',
            'recoveryMs': reconnectMs,
            'totalOutageMs': totalOutageMs,
            'recoveryMode': reconnectResponse['recoveryMode'],
            'recoverySource': recoveredSource,
            'recoveryTriggerSource': recoverySource,
            'reusedHost': reusedHost,
            'coalescedRecoveryRequests': coalescedRecoveryRequests,
            'relayRefreshMs': relayRefreshMs,
            'relayWarmMs': relayWarmMs,
            'reserveRpcMs': reserveRpcMs,
            'relayWarmParallelism': relayWarmParallelism,
            'foregroundRecoveryPath': ?foregroundRecoveryPath,
            'foregroundRelayDialTimeoutMs': foregroundRelayDialTimeoutMs,
            'autorelayRetryCadenceMs': autorelayRetryCadenceMs,
            'circuitAddressWaitMs': circuitAddressWaitMs,
            'reservationPath': reconnectResponse['reservationPath'],
            if (reconnectResponse['reservationWinnerPeer'] != null)
              'reservationWinnerPeer':
                  reconnectResponse['reservationWinnerPeer'],
            'personalReregisterMs': personalReregisterMs,
          },
        );
        _outageDetectedAt = null;
        _consecutiveRefreshFailures = 0;
        return;
      }

      _consecutiveRefreshFailures++;
      if (kDebugMode) {
        debugPrint(
          '[HEALTH] relay:reconnect FAILED '
          '(failure #$_consecutiveRefreshFailures, took ${reconnectMs}ms)',
        );
      }
    } catch (e) {
      _consecutiveRefreshFailures++;
      if (kDebugMode) {
        debugPrint(
          '[HEALTH] relay:reconnect FAILED: $e '
          '(failure #$_consecutiveRefreshFailures)',
        );
      }
      // Relay still unreachable — will retry on next health check.
    } finally {
      _clearRecoveryInstrumentation();
    }
  }

  /// Safely update [_currentState] and emit to [_stateController].
  /// No-op if the controller is closed.
  ///
  /// [source] tags the caller for §24 TIME_TO_ONLINE_BADGE instrumentation:
  /// 'start_response', 'relay_state_push', 'health_check_poll', 'addresses_push'.
  void _emitState(
    NodeState newState, {
    String? source,
    bool mergeServiceOwnedReadiness = true,
  }) {
    final previousState = _currentState;
    final wasOnline = _stateHasHealthyRelay(previousState);
    final wasSendable = previousState.usabilityReady;
    final wasRelayReadyBadge =
        previousState.badgeReadinessState == BadgeReadinessState.onlineDotted;

    final baseState = mergeServiceOwnedReadiness
        ? _stateWithReadinessProjection(newState)
        : newState;
    _currentState = baseState.copyWith(
      directReady: _computeDirectReady(baseState.connections),
    );
    if (!_stateController.isClosed) {
      _stateController.add(_currentState);
    }

    // 141: Fire a deferred notif-open drain exactly once when the node reaches
    // started. Placed before the §24 early-returning branches below so a
    // cold-start online transition cannot skip it. Re-runs the public entry
    // point so the account-migration gate is re-checked at fire time and the
    // started-path drain semantics are reused; the one-shot latch (cleared
    // here) prevents any double-fire across state flaps.
    if (!previousState.isStarted &&
        _currentState.isStarted &&
        _pendingStartupDrain) {
      final waitForAllPages = _pendingStartupDrainWaitForAllPages;
      _pendingStartupDrain = false;
      _pendingStartupDrainWaitForAllPages = false;
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_PENDING_STARTUP_DRAIN_FIRED',
        details: {'waitForAllPages': waitForAllPages},
      );
      unawaited(
        waitForAllPages ? drainOfflineInboxFully() : drainOfflineInbox(),
      );
    }

    final nowOnline = _stateHasHealthyRelay(_currentState);
    final nowSendable = _currentState.usabilityReady;
    final nowRelayReadyBadge =
        _currentState.badgeReadinessState == BadgeReadinessState.onlineDotted;

    final readinessStartedAt = _activeReadinessProofWindowStartedAt;
    final readinessPhase = _activeReadinessPhase;
    final proofWindowId = _activeReadinessProofWindowId;
    if (proofWindowId != null &&
        readinessPhase != null &&
        readinessStartedAt != null &&
        nowSendable &&
        !wasSendable) {
      emitFlowEvent(
        layer: 'FL',
        event: 'TIME_TO_SENDABLE_BADGE',
        details: {
          'proofWindowId': proofWindowId,
          'phase': readinessPhase,
          'totalMs': DateTime.now()
              .difference(readinessStartedAt)
              .inMilliseconds,
          'source': source ?? 'readiness_state_transition',
          'sendProofSource': _sendProofSource,
          'inboxProofSource': _inboxProofSource,
        },
      );
    }

    if (proofWindowId != null &&
        readinessPhase != null &&
        readinessStartedAt != null &&
        nowRelayReadyBadge &&
        !wasRelayReadyBadge) {
      emitFlowEvent(
        layer: 'FL',
        event: 'TIME_TO_RELAY_READY_BADGE',
        details: {
          'proofWindowId': proofWindowId,
          'phase': readinessPhase,
          'totalMs': DateTime.now()
              .difference(readinessStartedAt)
              .inMilliseconds,
          'source': source ?? 'readiness_state_transition',
        },
      );
    }

    // §24: Cold start / hot restart — first time reaching online after node start.
    if (nowOnline &&
        !wasOnline &&
        !_coldStartOnlineEmitted &&
        _nodeStartRequestedAt != null) {
      _coldStartOnlineEmitted = true;
      final totalMs = DateTime.now()
          .difference(_nodeStartRequestedAt!)
          .inMilliseconds;
      final String phase;
      if (_lastWentOfflineAt != null) {
        phase = 'recovery';
      } else if (_isHotRestart) {
        phase = 'hot_restart';
      } else {
        phase = 'cold_start';
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'TIME_TO_ONLINE_BADGE',
        details: {
          'totalMs': totalMs,
          'phase': phase,
          'source': source ?? 'unknown',
        },
      );
      _lastWentOfflineAt = null;
      return;
    }

    final wasOnlineDirectBadge =
        previousState.badgeReadinessState == BadgeReadinessState.onlineDirect;
    final nowOnlineDirectBadge =
        _currentState.badgeReadinessState == BadgeReadinessState.onlineDirect;
    if (nowOnlineDirectBadge &&
        !wasOnlineDirectBadge &&
        !_coldStartOnlineEmitted &&
        _nodeStartRequestedAt != null) {
      _coldStartOnlineEmitted = true;
      final totalMs = DateTime.now()
          .difference(_nodeStartRequestedAt!)
          .inMilliseconds;
      emitFlowEvent(
        layer: 'FL',
        event: 'TIME_TO_ONLINE_BADGE',
        details: {
          'totalMs': totalMs,
          'phase': _isHotRestart ? 'hot_restart' : 'cold_start',
          'source': source ?? 'unknown',
        },
      );
      _lastWentOfflineAt = null;
      return;
    }

    // §24: Recovery — was online, went offline, now back online.
    if (nowOnline &&
        !wasOnline &&
        _coldStartOnlineEmitted &&
        _lastWentOfflineAt != null) {
      // If this recovery was triggered by a background resume, emit
      // background_resume phase instead of (in addition to) recovery.
      final String phase;
      final int totalMs;
      if (_resumeStartedAt != null) {
        phase = 'background_resume';
        totalMs = DateTime.now().difference(_resumeStartedAt!).inMilliseconds;
        _resumeStartedAt = null;
      } else {
        phase = 'recovery';
        totalMs = DateTime.now().difference(_lastWentOfflineAt!).inMilliseconds;
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'TIME_TO_ONLINE_BADGE',
        details: {
          'totalMs': totalMs,
          'phase': phase,
          'source': source ?? 'unknown',
        },
      );
      _lastWentOfflineAt = null;
    }

    // §24: Track when we lose online status (for recovery timing).
    if (!nowOnline && wasOnline) {
      _lastWentOfflineAt = DateTime.now();
    }
  }

  bool _stateHasHealthyRelay(NodeState state) {
    final relayState = state.relayState;
    if (relayState != null) {
      return relayState == 'online';
    }
    return state.circuitAddresses.isNotEmpty;
  }

  static bool _connHasDirectAddr(ConnectionState connection) {
    return connection.multiaddrs.any(
      (multiaddr) =>
          multiaddr.isNotEmpty && !multiaddr.contains('/p2p-circuit'),
    );
  }

  static bool _computeDirectReady(List<ConnectionState> connections) {
    return connections.any(
      (connection) => !connection.isRelay && _connHasDirectAddr(connection),
    );
  }

  bool _stateNeedsRelayRecovery(NodeState state) {
    if (!state.isStarted) return false;

    final relayState = state.relayState;
    if (relayState != null) {
      return relayState != 'online';
    }
    return state.circuitAddresses.isEmpty;
  }

  bool _shouldAttemptStartupRelayRecovery(NodeState state) {
    if (_hasEverBeenOnline || !_stateNeedsRelayRecovery(state)) {
      return false;
    }

    final startedAt = _nodeStartRequestedAt;
    if (startedAt == null) return true;

    final now = DateTime.now();
    if (now.difference(startedAt) < startupRelayRecoveryDelay) {
      return false;
    }

    final lastAttemptAt = _lastStartupRelayRecoveryAttemptAt;
    return lastAttemptAt == null ||
        now.difference(lastAttemptAt) >= startupRelayRecoveryRetryInterval;
  }

  /// NET-REL-02 Option A: short peer ID (last 8 chars) matching the Go tracer's
  /// `remotePeerShort`, for correlating upgrade telemetry against a peer ID.
  String _shortId(String peerId) =>
      peerId.length <= 8 ? peerId : peerId.substring(peerId.length - 8);

  /// Handles DCUtR hole-punch / relay->direct telemetry from the Go tracer.
  void _handleTransportDiagnosticEvent(Map<String, dynamic> event) {
    final eventName = event['event'] as String?;
    switch (eventName) {
      case 'holepunch:attempt':
        // Only HolePunchAttemptEvt (`step: attempt`) is a counted attempt;
        // `started` and `direct_dial` are breadcrumbs.
        final step = event['step'] as String?;
        if (step == 'attempt') {
          _transportMetrics?.recordHolePunchAttempt();
        }
        break;
      case 'holepunch:success':
        _transportMetrics?.recordHolePunchSuccess();
        _recordPeerUpgrade(event['remotePeerShort'] as String?);
        break;
      case 'holepunch:failure':
        _transportMetrics?.recordHolePunchFailure();
        break;
      case 'transport:upgraded':
        {
          _transportMetrics?.recordRelayToDirectUpgrade();
          final short = event['remotePeerShort'] as String?;
          // FDC-13: surface the relay->direct UPGRADE as the distinct 'upgraded'
          // per-message badge.
          _recordPeerUpgrade(short);
          // FDC-12: ALSO prime the sticky transport cache so the next send's
          // sticky/reuse fast-path reuses the direct conn. The telemetry carries
          // only the sanitized short id; _learnedTransport is keyed by full peer
          // id, so resolve short->full from the live connection set.
          final fullId = _resolveFullPeerId(short);
          if (fullId != null) {
            recordSuccessfulTransport(fullId, 'direct');
          }
        }
        break;
      case 'transport:downgraded':
        {
          // FDC-12: the direct leg died (a relay/circuit leg may survive). Revert
          // the FDC-13 'upgraded' badge so it stops lying, and clear the sticky
          // direct preference so the next send re-probes instead of reusing a
          // dead direct leg. Distinct from peer:disconnected (the peer stays
          // connected via the surviving leg).
          final short = event['remotePeerShort'] as String?;
          _recordPeerDowngrade(short);
          final fullId = _resolveFullPeerId(short);
          if (fullId != null) {
            _learnedTransport.remove(fullId);
          }
        }
        break;
    }
  }

  void _recordPeerUpgrade(String? remotePeerShort) {
    if (remotePeerShort != null && remotePeerShort.isNotEmpty) {
      _peersUpgradedToDirect.add(remotePeerShort);
    }
  }

  /// FDC-12: reverts a peer's relay->direct upgrade badge when its direct leg
  /// dies (transport:downgraded). Mirrors [_recordPeerUpgrade] in reverse.
  void _recordPeerDowngrade(String? remotePeerShort) {
    if (remotePeerShort != null && remotePeerShort.isNotEmpty) {
      _peersUpgradedToDirect.remove(remotePeerShort);
    }
  }

  /// FDC-12: resolves a sanitized short peer id (last 8 chars, as carried by the
  /// transport-diagnostic telemetry) to the full peer id of a currently-connected
  /// peer. The sticky cache ([_learnedTransport]) is keyed by full peer id, but
  /// the upgrade/downgrade events carry only the short id (privacy), so the
  /// session-scoped sticky write/clear resolves through the live connection set.
  ///
  /// Returns null when ZERO or MORE THAN ONE live connections share the short id
  /// (a last-8-char collision). The sticky cache is a non-authoritative
  /// optimization (the send race always falls back to the full race), so on an
  /// ambiguous short id it is correct to skip the write/clear rather than risk
  /// priming the WRONG peer's sticky entry.
  String? _resolveFullPeerId(String? remotePeerShort) {
    if (remotePeerShort == null || remotePeerShort.isEmpty) return null;
    String? match;
    for (final c in _currentState.connections) {
      if (_shortId(c.peerId) == remotePeerShort) {
        if (match != null && match != c.peerId)
          return null; // collision → fail-safe
        match = c.peerId;
      }
    }
    return match;
  }

  String? _inferTransportForPeer(String peerId) {
    // A peer that genuinely upgraded relay->direct (observed via the DCUtR
    // tracer) is direct, even if _currentState still holds a stale
    // /p2p-circuit multiaddr for it (libp2p does not re-fire connectedness on
    // an upgrade).
    if (_peersUpgradedToDirect.contains(_shortId(peerId))) {
      // FDC-13: surface the relay->direct UPGRADE as a distinct 'upgraded'
      // value (not flattened to plain 'direct') so the per-message badge can
      // show the upgrade. The aggregate census still counts it as 'direct' via
      // the TransportMetrics._canonicalTransport 'upgraded'->'direct' alias.
      return 'upgraded';
    }
    var sawDirectConnection = false;
    for (final connection in _currentState.connections) {
      if (connection.peerId != peerId) continue;
      for (final multiaddr in connection.multiaddrs) {
        if (multiaddr.contains('/p2p-circuit')) {
          return 'relay';
        }
        if (multiaddr.isNotEmpty) {
          sawDirectConnection = true;
        }
      }
    }
    return sawDirectConnection ? 'direct' : null;
  }

  bool _stateMeaningfullyChanged(NodeState previous, NodeState next) {
    return previous.peerId != next.peerId ||
        previous.isStarted != next.isStarted ||
        !listEquals(previous.listenAddresses, next.listenAddresses) ||
        !listEquals(previous.circuitAddresses, next.circuitAddresses) ||
        previous.connections.length != next.connections.length ||
        previous.relayState != next.relayState ||
        previous.healthyRelayCount != next.healthyRelayCount ||
        previous.watchdogRestartCount != next.watchdogRestartCount ||
        previous.needsGroupRecovery != next.needsGroupRecovery ||
        previous.sendCapabilityReady != next.sendCapabilityReady ||
        previous.inboxCapabilityReady != next.inboxCapabilityReady;
  }

  /// Poll node:status, attempt recovery if degraded, and emit state changes.
  Future<void> _performHealthCheck() async {
    if (_isHealthChecking || _stopped) {
      if (kDebugMode) {
        debugPrint(
          '[HEALTH] _performHealthCheck() skipped — already in progress or stopped',
        );
      }
      return;
    }
    if (!await _allowsAccountNetworkSideEffects('p2p_health_check')) {
      return;
    }
    _isHealthChecking = true;
    final hcStart = DateTime.now();
    if (kDebugMode) debugPrint('[HEALTH] _performHealthCheck() starting...');
    try {
      final statusStart = DateTime.now();
      final response = await callP2PNodeStatus(_bridge);
      if (_stopped) return;
      final statusMs = DateTime.now().difference(statusStart).inMilliseconds;
      final freshState = NodeState.fromJson(response);
      _consecutiveHealthCheckExceptions = 0; // successful poll — reset
      if (kDebugMode) {
        debugPrint(
          '[HEALTH] node:status took ${statusMs}ms → '
          'isStarted=${freshState.isStarted}, '
          'circuitAddresses=${freshState.circuitAddresses.length}, '
          'connections=${freshState.connections.length}, '
          'relayState=${freshState.relayState}, '
          'peerId=${freshState.peerId}',
        );
      }
      if (_stateHasHealthyRelay(freshState)) {
        _hasEverBeenOnline = true;
        _lastHealthyRelayAt = DateTime.now();
      }

      // Recovery: when reservation-aware relay health says we are degraded,
      // reconnect relays. If relayState is absent, fall back to circuit
      // addresses for compatibility with older bridges.
      final needsRelayRecovery = _stateNeedsRelayRecovery(freshState);
      final isStartupRelayRecovery =
          freshState.isStarted &&
          needsRelayRecovery &&
          !_hasEverBeenOnline &&
          _shouldAttemptStartupRelayRecovery(freshState);
      if (needsRelayRecovery &&
          (_hasEverBeenOnline || isStartupRelayRecovery)) {
        if (isStartupRelayRecovery) {
          _lastStartupRelayRecoveryAttemptAt = DateTime.now();
          emitFlowEvent(
            layer: 'FL',
            event: 'P2P_STARTUP_RELAY_RECOVERY_TRIGGERED',
            details: {
              'relayState': freshState.relayState,
              'circuitAddresses': freshState.circuitAddresses.length,
              'elapsedMs': _nodeStartRequestedAt == null
                  ? -1
                  : DateTime.now()
                        .difference(_nodeStartRequestedAt!)
                        .inMilliseconds,
            },
          );
        } else {
          _outageDetectedAt ??= DateTime.now();
          final detectionMs = _lastHealthyRelayAt != null
              ? DateTime.now().difference(_lastHealthyRelayAt!).inMilliseconds
              : -1;
          emitFlowEvent(
            layer: 'FL',
            event: 'RELAY_OUTAGE_TIMING',
            details: {
              'phase': 'detected',
              'detectionMs': detectionMs,
              'detectionSource': 'poll',
            },
          );
        }
        final recoverySource =
            _pendingRecoverySource ??
            (isStartupRelayRecovery
                ? 'cold_start_health_check'
                : (_resumeStartedAt != null
                      ? 'resume_trigger'
                      : 'health_check_poll'));
        _pendingRecoverySource = null;
        if (!isStartupRelayRecovery) {
          _beginReadinessProofWindow(
            phase: _resumeStartedAt != null ? 'background_resume' : 'recovery',
            trigger: recoverySource,
            startedAt: _resumeStartedAt ?? DateTime.now(),
          );
        }
        if (kDebugMode) {
          debugPrint(
            '[HEALTH] DEGRADED — relay not healthy '
            '(relayState=${freshState.relayState}, '
            'circuitAddresses=${freshState.circuitAddresses.length}). '
            'Attempting recovery via relay:reconnect...',
          );
        }
        await _attemptRelayRecovery(recoverySource: recoverySource);
        if (_stopped) return;

        // Re-poll status after dialing the relay
        final retryStatusStart = DateTime.now();
        final retryResponse = await callP2PNodeStatus(_bridge);
        if (_stopped) return;
        final retryStatusMs = DateTime.now()
            .difference(retryStatusStart)
            .inMilliseconds;
        final retryState = NodeState.fromJson(retryResponse);
        if (_stateHasHealthyRelay(retryState)) {
          _hasEverBeenOnline = true;
        }
        if (kDebugMode) {
          debugPrint(
            '[HEALTH] Post-dial status (took ${retryStatusMs}ms) → '
            'circuitAddresses=${retryState.circuitAddresses.length}, '
            'connections=${retryState.connections.length}, '
            'relayState=${retryState.relayState}',
          );
        }

        if (!_stateHasHealthyRelay(retryState)) {
          if (kDebugMode) {
            debugPrint(
              '[HEALTH] Relay still not healthy after re-dial. '
              'Next health check in ${healthCheckInterval.inSeconds}s',
            );
          }
        }

        if (_stateMeaningfullyChanged(_currentState, retryState)) {
          _emitState(retryState, source: 'health_check_poll');

          emitFlowEvent(
            layer: 'FL',
            event: 'P2P_HEALTH_CHECK_RECOVERY_RESULT',
            details: {
              'isStarted': retryState.isStarted,
              'circuitAddresses': retryState.circuitAddresses.length,
              'connections': retryState.connections.length,
            },
          );

          // Re-register push token after relay reconnection
          if (_stateHasHealthyRelay(retryState) &&
              _lastFcmToken != null &&
              _lastFcmPlatform != null) {
            unawaited(_reregisterStoredPushTokenIfAvailable());
          }
        }

        final totalMs = DateTime.now().difference(hcStart).inMilliseconds;
        if (kDebugMode) {
          debugPrint(
            '[HEALTH] Recovery health check done (total ${totalMs}ms)',
          );
        }
        return;
      } else if (freshState.isStarted &&
          needsRelayRecovery &&
          !_hasEverBeenOnline) {
        _pendingRecoverySource = null;
        if (kDebugMode) {
          debugPrint(
            '[HEALTH] DEGRADED — relay not healthy yet '
            '(relayState=${freshState.relayState}, first startup). Waiting...',
          );
        }
      } else {
        _pendingRecoverySource = null;
      }

      // Drain offline inbox on each health check so we pick up
      // messages stored while we were unreachable via direct dial.
      await _drainOfflineInbox();
      if (_stopped) return;

      // Normal path: only emit if something meaningful changed
      if (_stateMeaningfullyChanged(_currentState, freshState)) {
        _emitState(freshState, source: 'health_check_poll');

        if (kDebugMode) {
          debugPrint(
            '[HEALTH] State changed → '
            'isStarted=${freshState.isStarted}, '
            'circuitAddresses=${freshState.circuitAddresses.length}, '
            'connections=${freshState.connections.length}, '
            'relayState=${freshState.relayState}',
          );
        }

        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_HEALTH_CHECK_STATE_CHANGED',
          details: {
            'isStarted': freshState.isStarted,
            'circuitAddresses': freshState.circuitAddresses.length,
            'connections': freshState.connections.length,
          },
        );
      } else {
        if (kDebugMode) {
          debugPrint('[HEALTH] No state change (online, all good)');
        }
      }
    } catch (e) {
      _consecutiveHealthCheckExceptions++;
      if (kDebugMode) {
        debugPrint(
          '[HEALTH] _performHealthCheck EXCEPTION '
          '(#$_consecutiveHealthCheckExceptions): $e',
        );
      }

      // Only assume the node is down after 3 consecutive poll failures.
      // A single transient error should not flash "Offline".
      if (_currentState.isStarted && _consecutiveHealthCheckExceptions >= 3) {
        _emitState(NodeState.stopped);

        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_HEALTH_CHECK_FAILED',
          details: {
            'error': e.toString(),
            'consecutiveFailures': _consecutiveHealthCheckExceptions,
          },
        );
      }
    } finally {
      _isHealthChecking = false;
    }
  }

  Future<LanInboundDecision> _commitInboundLanChatMessage(
    LocalChatMessage localMsg, {
    required String? nonce,
  }) async {
    _transportMetrics?.recordTransport('wifi');
    emitFlowEvent(
      layer: 'FL',
      event: 'MSG_RECEIVED_TRANSPORT',
      details: {
        'from': localMsg.from.length > 10
            ? localMsg.from.substring(0, 10)
            : localMsg.from,
        'transport': 'wifi',
      },
    );

    String? envelopeType;
    try {
      final decoded = jsonDecode(localMsg.content);
      if (decoded is Map<String, dynamic>) {
        envelopeType = decoded['type']?.toString();
      }
    } catch (_) {
      envelopeType = null;
    }

    final message = ChatMessage(
      from: localMsg.from,
      to: localMsg.to,
      content: localMsg.content,
      timestamp: localMsg.timestamp.toUtc().toIso8601String(),
      isIncoming: localMsg.isIncoming,
      transport: 'wifi',
    );

    if (!await _allowsAccountNetworkSideEffects(
      'p2p_inbound_message',
      peerId: localMsg.to.trim().isEmpty ? null : localMsg.to,
    )) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_INBOUND_EVENT_BLOCKED',
        details: {
          'operation': 'p2p_inbound_message',
          'family': 'direct_chat',
          'from': localMsg.from.length > 10
              ? localMsg.from.substring(0, 10)
              : localMsg.from,
          'envelopeType': ?envelopeType,
        },
      );
      return LanInboundDecision.rejected('account_migration_blocked');
    }

    final safeNonce = nonce?.trim();
    // F7: reactions/deletions join chat on the LAN stage-before-ack path. The
    // replay callback is selected per family (see _replayDurablyStagedLanChat);
    // here we only need to know one exists so we don't stage an undeliverable
    // entry. Any other type (or a missing callback) takes the legacy emit.
    final ReplayRecoveredInboxChatMessage? lanReplay;
    switch (envelopeType) {
      case 'chat_message':
        lanReplay =
            _replayLiveLanChatMessage ?? _replayRecoveredInboxChatMessage;
        break;
      case 'message_reaction':
        lanReplay = _replayRecoveredInboxReaction;
        break;
      case 'message_deletion':
        lanReplay = _replayRecoveredInboxMessageDeletion;
        break;
      default:
        lanReplay = null;
        break;
    }
    if (lanReplay == null || safeNonce == null || safeNonce.isEmpty) {
      _emitIncomingMessage(message);
      return const LanInboundDecision.accepted();
    }

    final entry = _stagingEntryFromLanMessage(
      localMsg,
      nonce: safeNonce,
      messageType: envelopeType,
    );
    if (entry == null) {
      _emitIncomingMessage(message);
      return const LanInboundDecision.accepted();
    }

    try {
      await _inboxStagingRepository.stageEntries([entry]);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_LAN_STAGE_ERROR',
        details: {
          'entryId': entry.entryId.length > 8
              ? entry.entryId.substring(0, 8)
              : entry.entryId,
          'error': e.toString(),
        },
      );
      _emitIncomingMessage(message);
      return LanInboundDecision.rejected('staging_error');
    }

    unawaited(_replayDurablyStagedLanChat(message, entry: entry));
    return const LanInboundDecision.committed();
  }

  /// Handle incoming chat message from bridge event.
  Future<bool> _handleMessageReceived(ChatMessage message) async {
    String? envelopeType;
    try {
      final decoded = jsonDecode(message.content);
      if (decoded is Map<String, dynamic>) {
        envelopeType = decoded['type'] as String?;
      }
    } catch (_) {
      envelopeType = null;
    }
    if (!await _allowsAccountNetworkSideEffects(
      'p2p_inbound_message',
      peerId: message.to.trim().isEmpty ? null : message.to,
    )) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_INBOUND_EVENT_BLOCKED',
        details: {
          'operation': 'p2p_inbound_message',
          'family': 'direct_chat',
          'from': message.from.length > 10
              ? message.from.substring(0, 10)
              : message.from,
          'envelopeType': ?envelopeType,
        },
      );
      return false;
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_SERVICE_MESSAGE_RECEIVED',
      details: {
        'from': message.from.length > 10
            ? message.from.substring(0, 10)
            : message.from,
        'isIncoming': message.isIncoming,
        'contentLength': message.content.length,
        'envelopeType': envelopeType,
        'streamClosed': _messageController.isClosed,
      },
    );
    logChatTransportIncoming(
      fromPeerId: message.from,
      toPeerId: message.to,
      contentLength: message.content.length,
      isIncoming: message.isIncoming,
      envelopeType: envelopeType,
    );

    if (_shouldDurablyStageDeferredDirectChat(
      message,
      envelopeType: envelopeType,
    )) {
      final entry = _stagingEntryFromDirectMessage(
        message,
        messageType: envelopeType,
      );
      if (entry != null) {
        unawaited(_processDurablyStagedDirectChat(message, entry: entry));
        return true;
      }
    }

    _emitIncomingMessage(message);
    return true;
  }

  /// Handle peer connected event from bridge.
  void _handlePeerConnected(ConnectionState conn) {
    if (_stopped) return;
    if (kDebugMode) {
      debugPrint('[CONN] peer:connected → ${conn.peerId} (${conn.status})');
    }

    // Update current state with new connection
    final updatedConnections = List<ConnectionState>.from(
      _currentState.connections,
    )..add(conn);

    _emitState(_currentState.copyWith(connections: updatedConnections));
  }

  /// Handle peer disconnected event from bridge.
  void _handlePeerDisconnected(ConnectionState conn) {
    if (_stopped) return;
    if (kDebugMode) debugPrint('[CONN] peer:disconnected → ${conn.peerId}');

    // Update current state by removing the connection
    final updatedConnections = _currentState.connections
        .where((c) => c.peerId != conn.peerId)
        .toList();

    // NET-REL-05 P3: a disconnected peer's learned transport is no longer
    // trustworthy — drop it so the next send re-races instead of weighting a
    // dead path.
    _learnedTransport.remove(conn.peerId);

    _emitState(_currentState.copyWith(connections: updatedConnections));
  }

  /// Handle addresses:updated push event from Go.
  void _handleAddressesUpdated(
    List<String> listenAddresses,
    List<String> circuitAddresses,
  ) {
    if (_stopped) return;
    final previousState = _currentState;
    final flutterElapsedMs = _startNodeTime != null
        ? DateTime.now().difference(_startNodeTime!).inMilliseconds
        : -1;

    final updatedState = previousState.copyWith(
      listenAddresses: listenAddresses,
      circuitAddresses: circuitAddresses,
    );
    final wasHealthy = _stateHasHealthyRelay(previousState);
    final nowHealthy = _stateHasHealthyRelay(updatedState);
    final wasConnecting = !wasHealthy;
    final nowOnline = nowHealthy;

    // NET-REL-05 P3: a relay-health transition signals a likely network change,
    // so drop non-local learned transports ('direct'/'relay' may no longer be
    // reachable). 'local' keeps its own 30s/isLocalPeer revalidation and
    // self-corrects, so leave it intact.
    if (wasHealthy != nowHealthy) {
      _learnedTransport.removeWhere((_, v) => v.transport != 'local');
    }

    if (kDebugMode) {
      debugPrint(
        '[ADDR] addresses:updated push event → '
        'listen=${listenAddresses.length}, circuit=${circuitAddresses.length}, '
        'relayState=${previousState.relayState}, '
        'elapsed=${flutterElapsedMs}ms'
        '${wasConnecting && nowOnline ? " TRANSITION connecting->online" : ""}',
      );
      if (circuitAddresses.isNotEmpty) {
        debugPrint('[ADDR] circuit addresses: ${circuitAddresses.join(", ")}');
      }
    }

    // FDC-S1 (b): process-start → first circuit address available (Dart view of
    // the EventChannel circuit-address push). One-shot per start.
    if (!_coldStartFirstCircuitEmitted && circuitAddresses.isNotEmpty) {
      _coldStartFirstCircuitEmitted = true;
      emitFlowEvent(
        layer: 'FL',
        event: 'FDC_COLDSTART_FIRST_CIRCUIT_TIMING',
        details: {
          'sinceProcessStartMs':
              StartupTiming.instance.sinceProcessStartMs() ?? -1,
          'circuitCount': circuitAddresses.length,
        },
      );
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_SERVICE_ADDRESSES_UPDATED',
      details: {
        'listenCount': listenAddresses.length,
        'circuitCount': circuitAddresses.length,
        'flutterElapsedMs': flutterElapsedMs,
        if (wasConnecting && nowOnline) 'transition': 'connecting->online',
      },
    );

    if (_stateMeaningfullyChanged(previousState, updatedState)) {
      _emitState(updatedState, source: 'addresses_push');
    }

    if (nowHealthy) {
      _hasEverBeenOnline = true;
    }

    // Re-register push token when the relay becomes healthy.
    if (!wasHealthy &&
        nowHealthy &&
        _lastFcmToken != null &&
        _lastFcmPlatform != null) {
      unawaited(_reregisterStoredPushTokenIfAvailable());
    }

    if (!wasHealthy && nowHealthy) {
      _retryProactiveSendProofIfNeeded(trigger: 'addresses_became_healthy');
    }

    // Keep the older addresses-based fallback only for legacy bridges that
    // still do not publish relay:state. Event-driven recovery now prefers the
    // real relay:state push path.
    if (previousState.relayState == null &&
        wasHealthy &&
        !nowHealthy &&
        _hasEverBeenOnline) {
      _beginReadinessProofWindow(
        phase: _resumeStartedAt != null ? 'background_resume' : 'recovery',
        trigger: 'addresses_push',
        startedAt: _resumeStartedAt ?? DateTime.now(),
      );
      if (kDebugMode) {
        debugPrint(
          '[ADDR] Legacy addresses push shows degradation — '
          'triggering immediate recovery',
        );
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_RELAY_STATE_PUSH_RECOVERY',
        details: {},
      );
      _pendingRecoverySource ??= 'relay_state_push';
      // Fire-and-forget: don't block the push event handler.
      // performImmediateHealthCheck handles coalescing internally.
      unawaited(performImmediateHealthCheck());
    }

    // FDC-11 (174): re-derive the libp2p LAN advert ports once the host surfaces
    // its resolved listen addresses (the FDC-07 cold-start early seam advertised
    // null because they were not yet known). Publishing is gated on Local
    // Network being proven so the re-advertise can never reopen the iOS
    // main-thread watchdog crash vector — see [_maybePublishLibp2pAdvertPorts].
    _resolvedAdvertQuicPort = _libp2pListenPort(listenAddresses, quic: true);
    _resolvedAdvertTcpPort = _libp2pListenPort(listenAddresses, quic: false);
    _maybePublishLibp2pAdvertPorts(source: 'addresses_updated');
  }

  /// FDC-11 (174): self-heals the bonsoir advert with the resolved libp2p
  /// QUIC/TCP LAN ports so a same-WiFi peer can build a non-empty
  /// `libp2pAddresses` and the Go LAN-direct dial can fire (CV-08).
  ///
  /// A re-advertise is a native bonsoir stop+start, whose SYNCHRONOUS
  /// main-thread DNS-SD read SIGKILLs iOS (0x8BADF00D scene-update watchdog)
  /// when Local Network is denied or its prompt is pending. The bonsoir
  /// suspected-denied gate only skips that re-start AFTER a 12s zero-peer probe
  /// latches, so a re-advertise fired in the cold-start window (the first
  /// `addresses:updated`, seconds after launch) would be UNGATED and could
  /// re-block the main thread. We therefore defer publishing until a peer has
  /// resolved over mDNS ([_localNetworkProven]) — which is simultaneously the
  /// moment Local Network is provably working (re-advertise is safe) AND the
  /// only moment the ports are actually needed (a peer exists to dial). If no
  /// peer is ever discovered we never re-advertise, which is correct (nobody to
  /// dial) and harmless. Called from both the `addresses:updated` re-derive and
  /// the peer-resolved flush so either ordering converges. Advert-only: it never
  /// touches `_localDiscoveryActive` or the suspected-permission-denied probe.
  void _maybePublishLibp2pAdvertPorts({required String source}) {
    final localP2P = _localP2P;
    if (localP2P == null || !_localDiscoveryActive) return;
    final quicPort = _resolvedAdvertQuicPort;
    final tcpPort = _resolvedAdvertTcpPort;
    if (quicPort == null && tcpPort == null) return;

    if (!_localNetworkProven) {
      // Cold-start window: re-advertising now could block the iOS main thread on
      // a denied/pending Local Network prompt. Hold the ports; the peer-resolved
      // flush publishes them once Local Network is provably working.
      emitFlowEvent(
        layer: 'FL',
        event: 'FDC_LAN_ADVERT_PORTS_DEFERRED',
        details: {
          'quicPort': quicPort ?? -1,
          'tcpPort': tcpPort ?? -1,
          'source': source,
        },
      );
      return;
    }

    unawaited(
      localP2P.updateLibp2pPorts(quicPort: quicPort, tcpPort: tcpPort),
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'FDC_LAN_ADVERT_PORTS',
      details: {
        'quicPort': quicPort ?? -1,
        'tcpPort': tcpPort ?? -1,
        'source': source,
      },
    );
  }

  void _handleRelayStateChanged(Map<String, dynamic> data) {
    if (_stopped) return;

    final previousState = _currentState;
    final relayState = data['relayState'] as String?;
    final healthyRelayCount = (data['healthyRelayCount'] as num?)?.toInt();
    final watchdogRestartCount = (data['watchdogRestartCount'] as num?)
        ?.toInt();
    final needsGroupRecovery = data['needsGroupRecovery'] as bool?;
    final updatedState = previousState.copyWith(
      relayState: relayState,
      healthyRelayCount: healthyRelayCount,
      watchdogRestartCount: watchdogRestartCount,
      needsGroupRecovery: needsGroupRecovery,
    );

    if (!_stateMeaningfullyChanged(previousState, updatedState)) {
      return;
    }

    final wasHealthy = _stateHasHealthyRelay(previousState);
    final nowHealthy = _stateHasHealthyRelay(updatedState);

    // NET-REL-05 P3: the relay:state push is the modern, preferred relay-health
    // transition signal (the addresses-updated path is a legacy fallback). A
    // health transition signals a likely network change, so drop non-local
    // learned transports here too ('direct'/'relay' may no longer be
    // reachable). 'local' keeps its own 30s/isLocalPeer revalidation and
    // self-corrects, so leave it intact. Without this, a transition delivered
    // only via relay:state (the common path) would leave a stale 'direct'/
    // 'relay' preference in place.
    if (wasHealthy != nowHealthy) {
      _learnedTransport.removeWhere((_, v) => v.transport != 'local');
    }

    if (kDebugMode) {
      debugPrint(
        '[RELAY] relay:state push event → '
        'relayState=${updatedState.relayState}, '
        'healthyRelayCount=${updatedState.healthyRelayCount}, '
        'watchdogRestartCount=${updatedState.watchdogRestartCount}, '
        'needsGroupRecovery=${updatedState.needsGroupRecovery}',
      );
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_SERVICE_RELAY_STATE_UPDATED',
      details: {
        'relayState': updatedState.relayState,
        'healthyRelayCount': updatedState.healthyRelayCount,
        'watchdogRestartCount': updatedState.watchdogRestartCount,
        'needsGroupRecovery': updatedState.needsGroupRecovery,
      },
    );

    _emitState(updatedState, source: 'relay_state_push');

    if (nowHealthy) {
      _hasEverBeenOnline = true;
      _lastHealthyRelayAt = DateTime.now();
    }

    if (!wasHealthy &&
        nowHealthy &&
        _lastFcmToken != null &&
        _lastFcmPlatform != null) {
      unawaited(_reregisterStoredPushTokenIfAvailable());
    }

    if (!wasHealthy && nowHealthy) {
      _retryProactiveSendProofIfNeeded(trigger: 'relay_became_healthy');
    }

    if (wasHealthy && !nowHealthy && _hasEverBeenOnline) {
      _outageDetectedAt ??= DateTime.now();
      final detectionMs = _lastHealthyRelayAt != null
          ? DateTime.now().difference(_lastHealthyRelayAt!).inMilliseconds
          : -1;
      _beginReadinessProofWindow(
        phase: _resumeStartedAt != null ? 'background_resume' : 'recovery',
        trigger: 'relay_state_push',
        startedAt: _resumeStartedAt ?? DateTime.now(),
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'RELAY_OUTAGE_TIMING',
        details: {
          'phase': 'detected',
          'detectionMs': detectionMs,
          'detectionSource': 'push',
        },
      );
      if (kDebugMode) {
        debugPrint(
          '[RELAY] relay:state shows degradation — triggering immediate recovery',
        );
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_RELAY_STATE_PUSH_RECOVERY',
        details: {
          'relayState': updatedState.relayState,
          if (data['reason'] != null) 'reason': data['reason'],
        },
      );
      _pendingRecoverySource ??= 'relay_state_push';
      unawaited(performImmediateHealthCheck());
    }
  }

  Future<void> _restorePersistedPushTokenIfNeeded() {
    if (_lastFcmToken != null && _lastFcmPlatform != null) {
      return Future<void>.value();
    }

    final pushTokenStore = _pushTokenStore;
    if (pushTokenStore == null) {
      return Future<void>.value();
    }

    final inFlight = _restorePushTokenFuture;
    if (inFlight != null) {
      return inFlight;
    }

    final restore = () async {
      try {
        final stored = await pushTokenStore.readToken();
        if (stored == null) {
          return;
        }
        _lastFcmToken = stored.token;
        _lastFcmPlatform = stored.platform;
        logPushDiagnostic(
          'persisted_push_token_restored',
          details: {
            'platform': stored.platform,
            'token': summarizePushToken(stored.token),
          },
        );
        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_PUSH_TOKEN_RESTORED',
          details: {'platform': stored.platform},
        );
      } catch (e) {
        logPushDiagnostic(
          'persisted_push_token_restore_failed',
          details: {'error': e.toString()},
        );
        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_PUSH_TOKEN_RESTORE_FAILED',
          details: {'error': e.toString()},
        );
      }
    }();

    _restorePushTokenFuture = restore.whenComplete(() {
      _restorePushTokenFuture = null;
    });
    return _restorePushTokenFuture!;
  }

  Future<void> _reregisterStoredPushTokenIfAvailable() async {
    await _restorePersistedPushTokenIfNeeded();
    final token = _lastFcmToken;
    final platform = _lastFcmPlatform;
    if (token == null || platform == null) {
      return;
    }
    await registerPushToken(token, platform);
  }

  @override
  Future<bool> storeInInbox(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    final outcome = await storeInInboxDetailed(
      toPeerId,
      message,
      timeoutMs: timeoutMs,
    );
    return outcome.accepted;
  }

  @override
  Future<InboxStoreOutcome> storeInInboxDetailed(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    if (!await _allowsAccountNetworkSideEffects('p2p_store_inbox')) {
      return const InboxStoreOutcome(status: InboxStoreStatus.failed);
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_SERVICE_INBOX_STORE_BEGIN',
      details: {'toPeerId': toPeerId},
    );

    try {
      final response = await callP2PInboxStore(
        _bridge,
        toPeerId: toPeerId,
        message: message,
        timeoutMs: timeoutMs,
      );
      final outcome = InboxStoreOutcome.fromBridgeResponse(response);
      emitFlowEvent(
        layer: 'FL',
        event: outcome.accepted
            ? 'P2P_SERVICE_INBOX_STORE_SUCCESS'
            : 'P2P_SERVICE_INBOX_STORE_ERROR',
        details: {
          'toPeerId': toPeerId,
          'status': outcome.status.name,
          if (outcome.errorCode != null) 'errorCode': outcome.errorCode,
          if (outcome.expiresAtMs != null) 'expiresAtMs': outcome.expiresAtMs,
        },
      );
      return outcome;
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_INBOX_STORE_EXCEPTION',
        details: {'error': e.toString()},
      );
      return InboxStoreOutcome(
        status: InboxStoreStatus.failed,
        errorMessage: e.toString(),
      );
    }
  }

  @override
  Future<List<Map<String, dynamic>>> retrieveInbox({int? timeoutMs}) async {
    if (!await _allowsAccountNetworkSideEffects('p2p_retrieve_inbox')) {
      return const [];
    }

    final details = <String, dynamic>{};
    if (timeoutMs != null) {
      details['timeoutMs'] = timeoutMs;
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_SERVICE_INBOX_RETRIEVE_BEGIN',
      details: details,
    );

    try {
      final response = await callP2PInboxRetrieve(
        _bridge,
        timeoutMs: timeoutMs,
      );
      if (response['ok'] == true) {
        final messages =
            (response['messages'] as List<dynamic>?)
                ?.cast<Map<String, dynamic>>() ??
            [];
        final hasMore = response['hasMore'] == true;
        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_INBOX_RETRIEVE_SUCCESS',
          details: {
            'count': messages.length,
            'hasMore': hasMore,
            'note': 'server deleted retrieved messages from memory',
          },
        );
        _recordSuccessfulInboxProof(
          source: 'retrieve_inbox',
          trigger: 'user_action',
        );
        return messages;
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_INBOX_RETRIEVE_ERROR',
        details: {'errorMessage': response['errorMessage']},
      );
      _recordCapabilityProofFailure(
        capability: 'inbox',
        source: 'retrieve_inbox',
        trigger: 'user_action',
        failureReason: response['errorMessage']?.toString(),
      );
      return [];
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_INBOX_RETRIEVE_EXCEPTION',
        details: {'error': e.toString()},
      );
      _recordCapabilityProofFailure(
        capability: 'inbox',
        source: 'retrieve_inbox',
        trigger: 'user_action',
        failureReason: e.toString(),
      );
      return [];
    }
  }

  @override
  Future<bool> registerPushToken(String token, String platform) async {
    if (!await _allowsAccountNetworkSideEffects('p2p_register_push_token')) {
      return false;
    }

    logPushDiagnostic(
      'bridge_register_push_token_begin',
      details: {'platform': platform, 'token': summarizePushToken(token)},
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_SERVICE_REGISTER_PUSH_TOKEN_BEGIN',
      details: {'platform': platform},
    );

    try {
      final response = await callP2PInboxRegisterToken(
        _bridge,
        token: token,
        platform: platform,
      );
      final ok = response['ok'] == true;
      if (ok) {
        _lastFcmToken = token;
        _lastFcmPlatform = platform;
      }
      logPushDiagnostic(
        ok
            ? 'bridge_register_push_token_success'
            : 'bridge_register_push_token_error',
        details: {'platform': platform},
      );
      emitFlowEvent(
        layer: 'FL',
        event: ok
            ? 'P2P_SERVICE_REGISTER_PUSH_TOKEN_SUCCESS'
            : 'P2P_SERVICE_REGISTER_PUSH_TOKEN_ERROR',
        details: {'platform': platform},
      );
      return ok;
    } catch (e) {
      logPushDiagnostic(
        'bridge_register_push_token_exception',
        details: {'platform': platform, 'error': e.toString()},
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_REGISTER_PUSH_TOKEN_EXCEPTION',
        details: {'error': e.toString()},
      );
      return false;
    }
  }

  /// Phase 5: The mode used by the last successful recovery.
  /// 'in_place' or 'watchdog_restart'. Null if no recovery yet.
  @override
  String? get lastRecoveryMethod => _lastRecoveryMethod;

  /// Phase 5: Number of consecutive in-place refresh failures.
  int get consecutiveRefreshFailures => _consecutiveRefreshFailures;

  @override
  Future<void> performImmediateHealthCheck() async {
    if (!await _allowsAccountNetworkSideEffects('p2p_immediate_health_check')) {
      return;
    }

    if (kDebugMode) debugPrint('[HEALTH] performImmediateHealthCheck() called');
    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_SERVICE_IMMEDIATE_HEALTH_CHECK_BEGIN',
      details: {},
    );

    // Phase 5: Coalesce concurrent recovery attempts.
    // If a recovery is already running, just wait for it to complete.
    if (_recoveryInProgress != null) {
      if (kDebugMode) {
        debugPrint('[HEALTH] Recovery already in progress — coalescing');
      }
      _pendingRecoverySource = null;
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_RECOVERY_COALESCED',
        details: {
          if (_activeRecoverySource != null)
            'recoverySource': _activeRecoverySource,
        },
      );
      await _recoveryInProgress!.future;
      return;
    }

    _recoveryInProgress = Completer<void>();
    try {
      await _performHealthCheck();
      await _attemptProactiveSendProofIfNeeded(
        trigger: 'immediate_health_check',
      );

      // Restart mDNS advertising (e.g. after iOS returns from background)
      try {
        await _localP2P?.restartAdvertising();
        _setLocalDiscoveryActive();
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[P2PService] Local P2P restart advertising failed: $e');
        }
        _setLocalDiscoveryInactive();
      }
    } finally {
      final completer = _recoveryInProgress;
      _recoveryInProgress = null;
      completer?.complete();
    }

    if (kDebugMode) debugPrint('[HEALTH] performImmediateHealthCheck() done');
  }

  @override
  Future<void> drainOfflineInbox() async {
    // 141: If the node has not yet started (cold notif-open, or warm where the
    // node was stopped while backgrounded), do NOT silently drop this
    // opportunistic catch-up — defer it and fire once on stopped->started.
    if (!_currentState.isStarted) {
      _scheduleStartupDrain(waitForAllPages: false);
      return;
    }
    if (!await _allowsAccountNetworkSideEffects('p2p_drain_offline_inbox')) {
      return;
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_SERVICE_DRAIN_OFFLINE_INBOX_BEGIN',
      details: {},
    );
    await _drainOfflineInbox();
  }

  @override
  Future<void> drainOfflineInboxFully() async {
    // 141: see [drainOfflineInbox] — defer (don't drop) when not yet started.
    if (!_currentState.isStarted) {
      _scheduleStartupDrain(waitForAllPages: true);
      return;
    }
    if (!await _allowsAccountNetworkSideEffects(
      'p2p_drain_offline_inbox_full',
    )) {
      return;
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_SERVICE_DRAIN_OFFLINE_INBOX_FULL_BEGIN',
      details: {},
    );
    await _drainOfflineInbox(waitForAllPages: true);
  }

  /// 141: Defer (do NOT drop) an opportunistic offline-inbox drain requested
  /// before the node finished starting. The latch fires once on the next
  /// stopped->started transition in [_emitState]; the account-migration network
  /// gate is (re-)checked then (the public entry point is re-run), not here. If
  /// multiple requests arrive while stopped, the stronger all-pages variant
  /// wins. Setting a bool latch has no network side effect, so it is safe to
  /// schedule unconditionally — the gate guards the actual drain at fire time.
  void _scheduleStartupDrain({required bool waitForAllPages}) {
    final wasScheduled = _pendingStartupDrain;
    _pendingStartupDrain = true;
    if (waitForAllPages) {
      _pendingStartupDrainWaitForAllPages = true;
    }
    if (!wasScheduled) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_PENDING_STARTUP_DRAIN_SCHEDULED',
        details: {'waitForAllPages': _pendingStartupDrainWaitForAllPages},
      );
    }
  }

  @override
  Future<RelayProbeResult> probeRelay(String peerId) async {
    if (!await _allowsAccountNetworkSideEffects('p2p_probe_relay')) {
      return RelayProbeResult.error;
    }

    try {
      final result = await callP2PRelayProbe(_bridge, peerId: peerId);
      if (result['ok'] == true) return RelayProbeResult.connected;
      if (result['errorCode'] == 'NO_RESERVATION') {
        return RelayProbeResult.noReservation;
      }
      return RelayProbeResult.error;
    } catch (e) {
      return RelayProbeResult.error;
    }
  }

  @override
  Future<RelayPresence> lookupRelayPresence(String peerId) async {
    // Move-feature gate FIRST (account-migration safety): a paused / migrating /
    // migrated-out device must not emit a presence round-trip. The token is a
    // log label only — never validated against an allowlist (mirrors
    // probeRelay's 'p2p_probe_relay'). Degrade to unknown when paused.
    if (!await _allowsAccountNetworkSideEffects('p2p_get_presence')) {
      return RelayPresence.unknown;
    }

    // Short-TTL cache (read-time eviction, mirrors lastKnownGoodTransport):
    // clock.now()-based so it is withClock-testable. A stale entry is evicted
    // and re-queried — a `reachable` is NEVER trusted past the TTL (C4).
    final cached = _presenceCache[peerId];
    if (cached != null) {
      if (clock.now().difference(cached.at) <= _presenceCacheTtl) {
        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_RELAY_PRESENCE_CACHE_HIT',
          details: {'peerId': peerId, 'presence': cached.presence.name},
        );
        return cached.presence;
      }
      _presenceCache.remove(peerId);
    }

    try {
      final result = await callP2PRelayPresence(_bridge, peerId: peerId);
      final presence = _relayPresenceFromString(result['presence'] as String?);
      _presenceCache[peerId] = _PresenceCacheEntry(presence, clock.now());
      return presence;
    } catch (_) {
      // Best-effort hint: any failure degrades to unknown (today's full race).
      return RelayPresence.unknown;
    }
  }

  RelayPresence _relayPresenceFromString(String? s) {
    switch (s) {
      case 'reachable':
        return RelayPresence.reachable;
      case 'unreachable':
        return RelayPresence.unreachable;
      default:
        return RelayPresence.unknown;
    }
  }

  @override
  Future<PresenceSetResult> setPresence(String state, int ttlMs) async {
    // Move-feature gate FIRST (account-migration safety): a paused / migrating /
    // migrated-out device must NOT announce itself reachable while ceding the
    // account (mirrors lookupRelayPresence's 'p2p_get_presence' / registerPush
    // Token's 'p2p_register_push_token'). The token is a log label only — never
    // validated against an allowlist. CRITICAL: this self-gates the primitive
    // because the PAUSE caller (handle_app_paused) is itself UNgated, unlike the
    // resume path. Skip (no bridge call) when paused.
    if (!await _allowsAccountNetworkSideEffects('p2p_set_presence')) {
      return PresenceSetResult.blocked;
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_SERVICE_SET_PRESENCE_BEGIN',
      details: {'state': state, 'ttlMs': ttlMs},
    );

    try {
      final result = await callP2PRelayPresenceSet(
        _bridge,
        state: state,
        ttlMs: ttlMs,
      );
      if (result['unsupported'] == true) {
        // Old relay (NET-REL-07): degrade to skip, never retry/spam.
        return PresenceSetResult.unsupported;
      }
      final ok = result['ok'] == true;
      emitFlowEvent(
        layer: 'FL',
        event: ok
            ? 'P2P_SERVICE_SET_PRESENCE_SUCCESS'
            : 'P2P_SERVICE_SET_PRESENCE_FAILED',
        details: {'state': state, 'ok': ok},
      );
      return ok ? PresenceSetResult.published : PresenceSetResult.failed;
    } catch (e) {
      // Best-effort hint: any failure degrades to `failed` (never throws).
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_SET_PRESENCE_EXCEPTION',
        details: {'state': state, 'error': e.toString()},
      );
      return PresenceSetResult.failed;
    }
  }

  // 183: PeerLivenessProbe — actively ping the active 1:1 peer so the keepalive
  // can detect a drop in SECONDS. Move-gated FIRST (a migrating device must not
  // probe); never throws — an old bridge / unreachable peer / any error all
  // degrade to `false` (a miss), so the keepalive loop never crashes and a failed
  // probe never throws away a send.
  @override
  Future<bool> pingPeer(String peerId, {required int timeoutMs}) async {
    if (!await _allowsAccountNetworkSideEffects(
      'p2p_peer_ping',
      peerId: peerId,
    )) {
      return false;
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_SERVICE_PEER_PING_BEGIN',
      details: {'peerId': _shortPeer(peerId)},
    );

    try {
      final result = await callP2PPeerPing(
        _bridge,
        peerId: peerId,
        timeoutMs: timeoutMs,
      );
      final ok = result['ok'] == true;
      emitFlowEvent(
        layer: 'FL',
        event: ok
            ? 'P2P_SERVICE_PEER_PING_SUCCESS'
            : 'P2P_SERVICE_PEER_PING_FAILED',
        details: {'peerId': _shortPeer(peerId), 'ok': ok},
      );
      return ok;
    } catch (e) {
      // Non-load-bearing: any failure degrades to a miss (never throws).
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_PEER_PING_EXCEPTION',
        details: {'peerId': _shortPeer(peerId), 'error': e.toString()},
      );
      return false;
    }
  }

  // 187: PeerDropSignal — the read-only per-peer drop latch the send path
  // consults to skip the doomed direct dial. The 183 keepalive sets it (true on
  // its M-miss drop, false on recovery / chat-close / peer-switch / background)
  // via [setPeerDropSuspected]; `sendChatMessage` reads it via
  // [isPeerSuspectedDropped]. Keyed by the NORMALIZED active key so the
  // keepalive's normalized mark meets the send path's raw target — both methods
  // normalize their arg. Best-effort in-memory hint; nothing here is durable
  // (an app restart clears it) and nothing here is load-bearing.
  final Set<String> _suspectedDroppedPeers = {};

  @override
  bool isPeerSuspectedDropped(String peerId) => _suspectedDroppedPeers.contains(
    ActiveConversationTracker.normalizeActiveKey(peerId),
  );

  @override
  void setPeerDropSuspected(String peerId, bool dropped) {
    final key = ActiveConversationTracker.normalizeActiveKey(peerId);
    if (dropped) {
      _suspectedDroppedPeers.add(key);
    } else {
      _suspectedDroppedPeers.remove(key);
    }
  }

  // 172: InboxAttentionSignal — the conversation UI's count source for the
  // "couldn't display N messages" affordance (INV-2: a kept-but-undisplayed
  // staged entry is never silently invisible). Never throws: any repo/DB error
  // degrades to 0 (the affordance simply hides).
  @override
  Future<int> countNeedsAttentionInboxEntries() async {
    try {
      return await _inboxStagingRepository.countNeedsAttentionEntries();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_INBOX_NEEDS_ATTENTION_COUNT_ERROR',
        details: {'error': e.toString()},
      );
      return 0;
    }
  }

  @override
  bool isConnectedToPeer(String peerId) => _currentState.connections.any(
    (c) => c.peerId == peerId && c.status == 'connected',
  );

  @override
  bool isLocalPeer(String peerId) => _localP2P?.isLocalPeer(peerId) ?? false;

  /// FDC-15: true iff [peerId] holds at least one NON-`/p2p-circuit` (direct)
  /// multiaddr. The libp2p-LAN media gate is "has a direct conn", NOT "has no
  /// circuit conn": a peer can simultaneously hold a relay circuit reservation
  /// AND a fresh FDC-11 LAN-direct conn (the exact FDC-15 window), and that case
  /// MUST stream over the direct.
  ///
  /// NOTE: this deliberately does NOT reuse [_inferTransportForPeer], which
  /// short-circuits to `'relay'` on the FIRST `/p2p-circuit` addr and would
  /// false-negative the coexisting case (TD7 locks this). Host fakes fabricate
  /// the connections list; whether the live node:status surfaces the direct
  /// multiaddr (vs a stale circuit addr that libp2p does not re-fire on upgrade)
  /// is the D1 device-proof.
  bool hasNonCircuitDirectConn(String peerId) {
    if (!isConnectedToPeer(peerId)) return false;
    return _currentState.connections.any(
      (c) => c.peerId == peerId && _connHasDirectAddr(c),
    );
  }

  /// FDC-15: whether the libp2p-LAN media lane is enabled, read back from the
  /// Go-effective feature flags surfaced on the node state (the SAME
  /// `enableLibp2pLANMedia` value handed to the bridge at node:start). Off until
  /// the D1 two-phone media gate is GREEN.
  bool get _libp2pLanMediaEnabled =>
      _currentState.featureFlags?['enableLibp2pLANMedia'] ?? false;

  @override
  String? lastKnownGoodTransport(String peerId) {
    final e = _learnedTransport[peerId];
    if (e == null) return null;
    // clock.now() (defaults to DateTime.now() in production) so the read-time
    // TTL eviction below is directly testable via withClock().
    final age = clock.now().difference(e.at);
    // 'local' shares NET-REL-01's 30s LAN TTL; 'direct'/'relay' last longer.
    final ttl = e.transport == 'local'
        ? const Duration(seconds: 30)
        : const Duration(minutes: 10);
    if (age > ttl) {
      _learnedTransport.remove(peerId);
      return null;
    }
    // A learned 'local' transport must still be backed by live LAN visibility:
    // the peer may have left WiFi inside the TTL. Never trust a stale-by-
    // departure local preference.
    if (e.transport == 'local' && !isLocalPeer(peerId)) {
      _learnedTransport.remove(peerId);
      return null;
    }
    return e.transport;
  }

  @override
  void recordSuccessfulTransport(String peerId, String transport) {
    if (transport == 'local' || transport == 'direct' || transport == 'relay') {
      _learnedTransport[peerId] = _LearnedTransport(transport, clock.now());
    }
  }

  @override
  Future<bool> discoverLocalPeer(
    String peerId, {
    required Duration timeout,
  }) async {
    if (!await _allowsAccountNetworkSideEffects('p2p_discover_local_peer')) {
      return false;
    }

    final localP2P = _localP2P;
    if (localP2P == null) return false;
    return localP2P.discoverLocalPeer(peerId, timeout: timeout);
  }

  @override
  Future<LanSendAck> sendLocalMessageDurable(
    String peerId,
    String message,
    String fromPeerId, {
    int? timeoutMs,
  }) async {
    if (!await _allowsAccountNetworkSideEffects(
      'p2p_send_local_message',
      peerId: fromPeerId,
    )) {
      return LanSendAck.failed;
    }

    if (_localP2P == null) return LanSendAck.failed;
    return _localP2P.sendMessageDetailed(
      peerId,
      message,
      fromPeerId,
      timeoutMs: timeoutMs,
    );
  }

  @override
  Future<bool> sendLocalMessage(
    String peerId,
    String message,
    String fromPeerId, {
    int? timeoutMs,
  }) async =>
      await sendLocalMessageDurable(
        peerId,
        message,
        fromPeerId,
        timeoutMs: timeoutMs,
      ) ==
      LanSendAck.committed;

  @override
  Future<bool> sendLocalMedia({
    required String peerId,
    required String filePath,
    required String mime,
    required String mediaId,
    required String fromPeerId,
    int? durationMs,
    List<double>? waveform,
    String? filename,
    bool enc = false,
    String? encScheme,
  }) async {
    if (!await _allowsAccountNetworkSideEffects(
      'p2p_send_local_media',
      peerId: fromPeerId,
    )) {
      return false;
    }

    // FDC-15: additive libp2p-LAN leg — stream the SAME ciphertext over a
    // peer-authenticated direct conn IN ADDITION to the WS leg, when the lane is
    // enabled AND a non-circuit direct conn exists. Fire-and-forget (best-effort
    // acceleration): it must never block the WS leg, gate sendLocalMedia's
    // result, or head-of-line-block the bridge — the unconditional relay-CDN
    // upload at the caller remains the durable copy. Fail-closed: the leg fires
    // ONLY when `enc` (so `filePath` is the ciphertext artifact, never a
    // plaintext source) — invariant 6, "ciphertext only, never plaintext".
    final hasDirectConn = hasNonCircuitDirectConn(peerId);
    if (_libp2pLanMediaEnabled && enc && hasDirectConn) {
      unawaited(
        _sendLibp2pLanMedia(
          peerId: peerId,
          filePath: filePath,
          mime: mime,
          mediaId: mediaId,
          fromPeerId: fromPeerId,
          enc: enc,
          encScheme: encScheme,
          durationMs: durationMs,
        ),
      );
    } else {
      // FDC-15 / CV-34 diagnostic: the additive LAN-media leg skips SILENTLY when
      // any gate condition is false, which is indistinguishable from a WS/relay
      // fallback in the logs. Surface WHICH condition blocked it so the device
      // proof (and the eventual media soak) can attribute a non-fire.
      emitFlowEvent(
        layer: 'FL',
        event: 'LIBP2P_LAN_MEDIA_SEND_SKIPPED',
        details: {
          'id': mediaId,
          'flagEnabled': _libp2pLanMediaEnabled,
          'enc': enc,
          'hasDirectConn': hasDirectConn,
        },
      );
    }

    if (_localP2P == null) return false;
    return _localP2P.sendMedia(
      peerId: peerId,
      filePath: filePath,
      mime: mime,
      mediaId: mediaId,
      fromPeerId: fromPeerId,
      durationMs: durationMs,
      waveform: waveform,
      filename: filename,
      enc: enc,
      encScheme: encScheme,
    );
  }

  /// FDC-15: invoke the libp2p-LAN media bridge leg. Errors are swallowed
  /// (logged) — a failed acceleration leg must never affect the WS leg or the
  /// unconditional relay-CDN upload.
  Future<void> _sendLibp2pLanMedia({
    required String peerId,
    required String filePath,
    required String mime,
    required String mediaId,
    required String fromPeerId,
    required bool enc,
    String? encScheme,
    int? durationMs,
  }) async {
    try {
      await callP2PLanMediaSend(
        _bridge,
        id: mediaId,
        toPeerId: peerId,
        fromPeerId: fromPeerId,
        mime: mime,
        filePath: filePath,
        enc: enc,
        encScheme: encScheme,
        durationMs: durationMs,
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'LIBP2P_LAN_MEDIA_SEND_ERROR',
        details: {'id': mediaId, 'error': e.toString()},
      );
    }
  }

  @override
  void dispose() {
    _stopped = true;
    _currentState = NodeState.stopped;
    _stopHealthCheck();
    _localMessageSub?.cancel();
    _localPeersSub?.cancel();
    _localMediaSub?.cancel();
    _transportDiagnosticSub?.cancel();
    _networkChangeSub?.cancel();
    _lanPermProbeTimer?.cancel();
    _setLocalDiscoveryInactive();
    _localP2P?.dispose();

    // Phase 5: Complete any pending recovery so awaiters don't hang.
    if (_recoveryInProgress != null && !_recoveryInProgress!.isCompleted) {
      _recoveryInProgress!.complete();
    }
    _recoveryInProgress = null;

    if (!_stateController.isClosed) _stateController.close();
    if (!_messageController.isClosed) _messageController.close();
    if (!_incomingLocalMediaController.isClosed) {
      _incomingLocalMediaController.close();
    }

    // Clear event handlers
    _bridge.onMessageReceived = null;
    _bridge.onPeerConnected = null;
    _bridge.onPeerDisconnected = null;
    _bridge.onAddressesUpdated = null;
    _bridge.onRelayStateChanged = null;
  }
}
