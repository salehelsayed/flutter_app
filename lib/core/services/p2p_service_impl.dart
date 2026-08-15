import 'dart:async';
import 'dart:convert';
import 'package:clock/clock.dart';
import 'package:crypto/crypto.dart';
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
import 'protected_group_content_contract.dart';
import '../../features/account_migration/application/account_migration_runtime_network_gate.dart';
import '../../features/p2p/domain/models/node_state.dart';
import '../../features/p2p/domain/models/chat_message.dart';
import '../../features/p2p/domain/models/discovered_peer.dart';
import '../../features/p2p/domain/models/send_message_result.dart';
import '../../features/p2p/domain/models/connection_state.dart';
import '../../features/push/domain/push_token_store.dart';
import '../../features/push/domain/received_wake_token_store.dart';

part 'p2p_impl/p2p_inbox_coordinator.dart';
part 'p2p_impl/p2p_peer_transport_coordinator.dart';

const String _linkedGroupBootstrapInboxEnvelopeType =
    'linked_group_bootstrap_v1';
const String _protectedGroupAuthorityInboxEnvelopeType = 'group_authority_v1';
const String _protectedGroupContentInboxEnvelopeType = 'group_content_v1';
const String _unverifiedProtectedGroupContentInboxEnvelopeType =
    'unverified_group_content_v1';

enum RecoveredInboxChatDisposition {
  committed,
  retryable,
  rejected,
  quarantined,
}

enum ProtectedGroupReplayDisposition {
  applied,
  duplicate,
  terminalRejected,
  unverifiedRejected,
  retryable,
  prerequisiteWaiting,
}

typedef ProtectedGroupReplayOutcome = ({
  ProtectedGroupReplayDisposition disposition,
  String reasonCode,
  String? reasonDetail,
});

typedef ReplayRecoveredProtectedGroupEnvelope =
    Future<ProtectedGroupReplayOutcome> Function(ChatMessage message);

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

/// Debug/E2E-only observation of the accepted production `inbox:store`
/// attachment boundary. Only SHA-256 values cross this callback; the opaque
/// wake token, peer ID, and stored message remain inside this service method.
///
/// The callback is optional and never affects the store outcome. Production
/// construction leaves it null.
typedef AcceptedInboxWakeTokenHashObserver =
    void Function({
      required String toPeerIdSha256,
      required String messageSha256,
      required String wakeTokenSha256,
    });

/// Implementation of P2PService backed by the Go native bridge.
class P2PServiceImpl
    implements
        P2PService,
        DetailedInboxStore,
        AckOrExpiryInboxStore,
        MediaExpiryBoundedInboxStore,
        GroupContentExpiryBoundedInboxStore,
        ReadinessProofRecorder,
        P2PFullInboxDrain,
        DurableLanSender,
        RelayPresenceLookup,
        RelayPresenceSet,
        PeerLivenessProbe,
        PeerDropSignal,
        InboxAttentionSignal {
  final Bridge _bridge;
  final PushTokenStore? _pushTokenStore;

  /// Plan 320 P2: reads the CURRENT provider token. Relay-health re-registration
  /// must not replay a cached token the provider has already retired — the relay
  /// evicts dead tokens now (plan 320 P1), and replaying the cached value would
  /// silently undo that eviction on the next reconnect.
  final Future<String?> Function()? _liveFcmTokenReader;
  final AccountMigrationNetworkGate _accountMigrationNetworkGate;
  late final _P2PInboxCoordinator _inboxCoordinator;
  late final _P2PPeerTransportCoordinator _peerTransportCoordinator;
  final Duration? _keyRotationGracePeriodOverride;
  StreamSubscription<LocalChatMessage>? _localMessageSub;
  StreamSubscription<Map<String, LocalPeer>>? _localPeersSub;
  StreamSubscription<LocalMediaReady>? _localMediaSub;
  StreamSubscription<Map<String, dynamic>>? _transportDiagnosticSub;

  /// FDC-04 (RC4): injected WiFi<->cellular network-change signal. Default
  /// null/empty in tests + until the OS source is wired (connectivity_plus or a
  /// native NWPathMonitor/ConnectivityManager channel — a bounded follow-up).
  /// On each event, [onNetworkChanged] re-warms the ONE active peer.
  final Stream<void>? _networkChangeSignal;
  StreamSubscription<void>? _networkChangeSub;

  /// 360: the exact transport peer an ACTIVE linked-secondary credential
  /// names, or null on an ordinary primary installation.
  ///
  /// A linked secondary exists precisely so two installations of one account
  /// stop sharing a relay mailbox. If the Go node ever came up as a different
  /// peer than the credential names — a stale hot-restart node from a previous
  /// role, a bridge that ignored the supplied key — then continuing would put
  /// this installation back on the account's shared inbox while its contacts
  /// address a device peer nobody is listening on. So the qualification below
  /// STOPS the node rather than warming it.
  final String? Function()? _requiredTransportPeerId;

  /// 360: resolves the LOGICAL account peer while this installation runs a
  /// linked transport, or null on an ordinary primary.
  ///
  /// The account-migration side-effect gate decides on ACCOUNT authority. Handed
  /// a transport peer it would be asking about an identity that authority never
  /// covers, so a migrated-out account could keep transmitting from its linked
  /// device.
  final String? Function()? _logicalAccountPeerId;

  /// The peer the account-migration gate must be asked about for [peerId].
  ///
  /// Called from exactly one place — [_allowsAccountNetworkSideEffects] — so
  /// no gated operation can bypass it.
  String? _accountAuthorityPeerId(String? peerId) {
    final logical = _logicalAccountPeerId?.call()?.trim();
    if (logical == null || logical.isEmpty) return peerId;
    return logical;
  }

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

  /// Phase 5: Completer-based recovery coalescing.
  /// When non-null, a recovery is in progress and concurrent callers
  /// should await this instead of starting a new recovery.
  Completer<void>? _recoveryInProgress;

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

  /// 189 Fix B3: cap for the escalating recovery-backoff schedule, in skipped
  /// health-check ticks (8 ticks ≈ 4 min at the 30s cadence).
  static const int recoveryBackoffMaxSkipTicks = 8;

  /// 189 Fix B3: current backoff step (ticks to skip per failed attempt once
  /// [_consecutiveRefreshFailures] reaches [refreshFailureThreshold]; doubles
  /// per subsequent failure, capped). 0 = backoff disarmed.
  int _recoveryBackoffStep = 0;

  /// 189 Fix B3: health-check ticks left to skip before the next recovery
  /// attempt. Only ever delays recovery ATTEMPTS — never drains (INV-4).
  int _recoveryBackoffSkipsRemaining = 0;

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
    Future<String?> Function()? liveFcmTokenReader,
    ReceivedWakeTokenStore? receivedWakeTokenStore,
    AcceptedInboxWakeTokenHashObserver? acceptedInboxWakeTokenHashObserver,
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
    ReplayRecoveredProtectedGroupEnvelope?
    replayRecoveredProtectedGroupEnvelope,
    Future<String?> Function(ChatMessage message)? predecryptInboxChatEntry,
    TransportMetrics? transportMetrics,
    Duration? keyRotationGracePeriodOverride,
    // FDC-04: optional, default null keeps every existing call site unchanged.
    Stream<void>? networkChangeSignal,
    String? Function()? activePeerId,
    // 360: when this resolves a non-null peer, the node this service started
    // MUST be exactly that transport. Null (every existing call site) keeps the
    // incumbent primary contract byte-for-byte.
    String? Function()? requiredTransportPeerId,
    // 360: the LOGICAL account peer on a linked secondary. Account-migration
    // authority is an account-level fact and must never be evaluated against a
    // per-device transport peer.
    String? Function()? logicalAccountPeerId,
  }) : _bridge = bridge,
       _pushTokenStore = pushTokenStore,
       _liveFcmTokenReader = liveFcmTokenReader,
       _accountMigrationNetworkGate = accountMigrationNetworkGate,
       _keyRotationGracePeriodOverride = keyRotationGracePeriodOverride,
       _networkChangeSignal = networkChangeSignal,
       _requiredTransportPeerId = requiredTransportPeerId,
       _logicalAccountPeerId = logicalAccountPeerId {
    _inboxCoordinator = _P2PInboxCoordinator(
      port: _P2PInboxPort(
        readNodeState: () => _currentState,
        nodeStateStream: _stateController.stream,
        allowsAccountNetworkSideEffects: (String operation, {String? peerId}) =>
            _allowsAccountNetworkSideEffects(operation, peerId: peerId),
        confirmDirectMessage: ({required String nonce, required bool ok}) =>
            callP2PConfirmDirectMessage(_bridge, nonce: nonce, ok: ok),
        storeInbox:
            ({
              required String toPeerId,
              required String message,
              int? timeoutMs,
              String? wakeToken,
              String? custodyContract,
              String? custodyKind,
              int? custodyExpiresAtOrBeforeMs,
            }) => callP2PInboxStore(
              _bridge,
              toPeerId: toPeerId,
              message: message,
              timeoutMs: timeoutMs,
              wakeToken: wakeToken,
              custodyContract: custodyContract,
              custodyKind: custodyKind,
              custodyExpiresAtOrBeforeMs: custodyExpiresAtOrBeforeMs,
            ),
        retrieveInbox: ({int? timeoutMs}) =>
            callP2PInboxRetrieve(_bridge, timeoutMs: timeoutMs),
        retrievePendingInbox: ({int? timeoutMs, String? custodyContract}) =>
            callP2PInboxRetrievePending(
              _bridge,
              timeoutMs: timeoutMs,
              custodyContract: custodyContract,
            ),
        ackInbox:
            ({
              required List<String> entryIds,
              int? timeoutMs,
              String? custodyContract,
            }) => callP2PInboxAck(
              _bridge,
              entryIds: entryIds,
              timeoutMs: timeoutMs,
              custodyContract: custodyContract,
            ),
        emitIncomingMessage: _emitIncomingMessage,
        isMessageStreamClosed: () => _messageController.isClosed,
        recordTransport: (String transport) {
          _peerTransportCoordinator.recordTransport(transport);
        },
        recordSuccessfulInboxProof:
            ({required String source, required String trigger}) {
              _recordSuccessfulInboxProof(source: source, trigger: trigger);
            },
        recordInboxProofFailure:
            ({
              required String source,
              required String trigger,
              String? failureReason,
            }) {
              _recordCapabilityProofFailure(
                capability: 'inbox',
                source: source,
                trigger: trigger,
                failureReason: failureReason,
              );
            },
      ),
      inboxStagingRepository: inboxStagingRepository,
      receivedWakeTokenStore: receivedWakeTokenStore,
      acceptedInboxWakeTokenHashObserver: acceptedInboxWakeTokenHashObserver,
      replayRecoveredInboxChatMessage: replayRecoveredInboxChatMessage,
      replayLiveLanChatMessage: replayLiveLanChatMessage,
      replayLiveDirectChatMessage: replayLiveDirectChatMessage,
      replayRecoveredInboxIntroductionMessage:
          replayRecoveredInboxIntroductionMessage,
      replayRecoveredInboxContactRequest: replayRecoveredInboxContactRequest,
      replayRecoveredInboxReaction: replayRecoveredInboxReaction,
      replayRecoveredInboxMessageDeletion: replayRecoveredInboxMessageDeletion,
      replayRecoveredProtectedGroupEnvelope:
          replayRecoveredProtectedGroupEnvelope,
      predecryptInboxChatEntry: predecryptInboxChatEntry,
      maxInboxPages: maxInboxPages,
      maxRecoverableInboxReplayEntries: maxRecoverableInboxReplayEntries,
      maxConcurrentInboxDecrypts: maxConcurrentInboxDecrypts,
      foregroundInboxTimeout: foregroundInboxTimeout,
    );

    _peerTransportCoordinator = _P2PPeerTransportCoordinator(
      port: _P2PPeerTransportPort(
        readNodeState: () => _currentState,
        allowsAccountNetworkSideEffects: (String operation, {String? peerId}) =>
            _allowsAccountNetworkSideEffects(operation, peerId: peerId),
        dialPeer:
            (
              String peerId, {
              List<String>? addresses,
              int? timeoutMs,
              bool preferQuic = false,
            }) => dialPeer(
              peerId,
              addresses: addresses,
              timeoutMs: timeoutMs,
              preferQuic: preferQuic,
            ),
        drainOfflineInbox: drainOfflineInbox,
        probeRelay: ({required String peerId}) =>
            callP2PRelayProbe(_bridge, peerId: peerId),
        lookupRelayPresence: ({required String peerId}) =>
            callP2PRelayPresence(_bridge, peerId: peerId),
        setRelayPresence: ({required String state, required int ttlMs}) =>
            callP2PRelayPresenceSet(_bridge, state: state, ttlMs: ttlMs),
        pingPeer: ({required String peerId, required int timeoutMs}) =>
            callP2PPeerPing(_bridge, peerId: peerId, timeoutMs: timeoutMs),
        forwardLanPeer:
            ({required String peerId, required List<String> addresses}) =>
                callP2PLanPeerFound(
                  _bridge,
                  peerId: peerId,
                  addresses: addresses,
                ),
        sendLanMedia:
            ({
              required String id,
              required String toPeerId,
              required String fromPeerId,
              required String mime,
              required String filePath,
              required bool enc,
              String? encScheme,
              int? durationMs,
            }) => callP2PLanMediaSend(
              _bridge,
              id: id,
              toPeerId: toPeerId,
              fromPeerId: fromPeerId,
              mime: mime,
              filePath: filePath,
              enc: enc,
              encScheme: encScheme,
              durationMs: durationMs,
            ),
        emitEvent:
            ({
              required String layer,
              required String event,
              required Map<String, dynamic> details,
            }) => emitFlowEvent(layer: layer, event: event, details: details),
      ),
      localP2P: localP2PService,
      transportMetrics: transportMetrics,
      activePeerId: activePeerId,
    );

    // Register event handlers on the bridge
    _bridge.onMessageReceived = (msg) {
      final transport =
          msg.transport ??
          _peerTransportCoordinator._inferTransportForPeer(msg.from) ??
          'unknown';
      _peerTransportCoordinator.recordTransport(transport);
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
      unawaited(
        _inboxCoordinator._handleMessageReceived(
          msg.copyWith(transport: transport),
        ),
      );
    };
    _bridge.onPeerConnected = _handlePeerConnected;
    _bridge.onPeerDisconnected = _handlePeerDisconnected;
    _bridge.onAddressesUpdated = _handleAddressesUpdated;
    _bridge.onRelayStateChanged = _handleRelayStateChanged;

    // NET-REL-02 Option A: observe DCUtR hole-punch / relay->direct telemetry
    // emitted by the Go tracer to drive TransportMetrics counters and the
    // upgraded-peer set used to keep _inferTransportForPeer honest.
    _transportDiagnosticSub = transportDiagnosticEventStream.listen((event) {
      final eventName = event['event'] as String?;
      if (eventName == null) return;
      _peerTransportCoordinator.onTransportDiagnostic(
        _PeerTransportDiagnostic(
          eventName: eventName,
          step: event['step'],
          remotePeerShort: event['remotePeerShort'],
        ),
      );
    });

    localP2PService?.configureInboundChatCommitHandler(
      _inboxCoordinator._commitInboundLanChatMessage,
    );

    // Merge local WiFi messages into the unified message stream
    _localMessageSub = localP2PService?.localMessageStream.listen((localMsg) {
      _peerTransportCoordinator.recordTransport('wifi');
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
        _inboxCoordinator._handleMessageReceived(
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
    _localMediaSub = localP2PService?.mediaReadyStream?.listen((media) {
      _peerTransportCoordinator.recordTransport('wifi');
      _incomingLocalMediaController.add(media);
    });
    _localPeersSub = localP2PService?.discoveredPeersStream.listen((peers) {
      _peerTransportCoordinator.onDiscoveredPeersChanged(peers);
    });

    // FDC-04 (RC4): re-warm the active peer on a WiFi<->cellular change. Default
    // null signal ⇒ no subscription (tests + until the OS source lands).
    // onNetworkChanged is total/never-throws.
    _networkChangeSub = _networkChangeSignal?.listen(
      (_) => _peerTransportCoordinator.onNetworkChanged(),
    );

    unawaited(_restorePersistedPushTokenIfNeeded());
  }

  /// Installs the group bootstrap/authority handler after group services have
  /// been composed. The protected coordinator still owns stage-before-handler
  /// and handler-before-relay-ACK ordering.
  void setProtectedGroupReplayHandler(
    ReplayRecoveredProtectedGroupEnvelope? handler,
  ) {
    _inboxCoordinator.setProtectedGroupReplayHandler(handler);
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

  /// 360: EVERY account-migration authority question is asked about the
  /// LOGICAL account peer, never the per-device transport peer.
  ///
  /// Normalizing here rather than at call sites is deliberate. Node start is
  /// only the first of many gated operations — warm/background, send, inbox
  /// store/retrieve/ack, health checks and recovery all consult this gate, and
  /// most of them pass no peer at all and fall through to
  /// `_currentState.peerId`, which on a linked secondary IS the transport peer.
  /// Normalizing per call site left every one of those asking about an identity
  /// account authority does not cover, so a migrated-out account could keep
  /// transmitting from its linked device. A central choke point cannot be
  /// missed by a new caller.
  Future<bool> _allowsAccountNetworkSideEffects(
    String operation, {
    String? peerId,
  }) async {
    final effectivePeerId = _accountAuthorityPeerId(
      peerId ?? _currentState.peerId,
    );
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
      // 360: qualify the peer the node actually came up as BEFORE any Dart
      // warm/inbox/discovery work. This covers both `startNodeCore` branches —
      // the fresh `node:start` response and the hot-restart `node:status`
      // resync — because both publish through `_emitState`.
      if (!await _qualifyLinkedTransportPeer()) {
        return false;
      }
      // 361: an ACTIVE LINKED SECONDARY starts NO generic LAN discovery and
      // NO generic warm body from node start. Its restricted runtime owns the
      // exact inbox retrieve/replay work explicitly; everything broader stays
      // stopped for the linked role.
      final linkedRole =
          _requiredTransportPeerId?.call()?.trim().isNotEmpty ?? false;
      if (linkedRole) {
        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_LINKED_ROLE_GENERIC_START_SKIPPED',
          details: const {'skipped': 'early_local_discovery,warm_background'},
        );
        return success;
      }
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

  /// Returns true when this installation may proceed past node start.
  ///
  /// No-op (always true) on an ordinary primary, where
  /// [_requiredTransportPeerId] is null or resolves to null.
  Future<bool> _qualifyLinkedTransportPeer() async {
    final required = _requiredTransportPeerId?.call()?.trim();
    if (required == null || required.isEmpty) {
      return true;
    }
    final actual = _currentState.peerId?.trim() ?? '';
    if (actual == required) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_LINKED_TRANSPORT_PEER_QUALIFIED',
        details: {'peerId': actual},
      );
      return true;
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_SERVICE_LINKED_TRANSPORT_PEER_MISMATCH',
      details: {'expected': required, 'actual': actual},
    );
    try {
      await stopNode();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_LINKED_TRANSPORT_STOP_EXCEPTION',
        details: {'error': e.toString()},
      );
    }
    return false;
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
      _inboxCoordinator
          ._drainOfflineInbox()
          .then<void>((_) {})
          .timeout(warmTaskTimeout)
          .catchError((_) {}),
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
  Future<void> startEarlyLocalDiscovery() =>
      _peerTransportCoordinator.startEarlyLocalDiscovery();

  @visibleForTesting
  static int? debugLibp2pListenPort(
    List<String> listenAddresses, {
    required bool quic,
  }) => _P2PPeerTransportCoordinator._libp2pListenPort(
    listenAddresses,
    quic: quic,
  );

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

  void _emitIncomingMessage(ChatMessage message) {
    if (!_messageController.isClosed) {
      _messageController.add(message);
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
        await _peerTransportCoordinator.stopLocalService();
        _peerTransportCoordinator.setLocalDiscoveryInactive();
      } catch (e) {
        if (kDebugMode) debugPrint('[P2PService] Local P2P stop failed: $e');
        _peerTransportCoordinator.setLocalDiscoveryInactive();
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

  @override
  Future<void> warmPeer(String peerId, {bool preferQuic = false}) =>
      _peerTransportCoordinator.warmPeer(peerId, preferQuic: preferQuic);

  @visibleForTesting
  void onNetworkChanged() {
    _peerTransportCoordinator.onNetworkChanged();
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
        // 216: mirror the inbox→send readiness kick (`_recordSuccessfulInboxProof`
        // tail-calls `_retryProactiveSendProofIfNeeded('inbox_proof_success')`
        // above) in the send→inbox direction. On a real cold start the startup
        // drain races ahead of the relay reservation and records an inbox proof
        // FAILURE, so `inboxCapabilityReady` would otherwise wait for the first
        // 30s periodic health-check tick. The self-proof envelope we just stored
        // is guaranteed retrievable, so prove inbox capability now. Guarded on
        // `!inboxCapabilityReady` (mirrors the send side's `!sendCapabilityReady`
        // guard above) → fires at most once per readiness window, re-arms per
        // `_beginReadinessProofWindow`, and stays a no-op when the startup drain
        // already proved inbox (the fast-relay/sim case). Fire-and-forget so it
        // never blocks the send-proof `finally` retry chain below.
        if (!_currentState.inboxCapabilityReady) {
          unawaited(_inboxCoordinator._drainOfflineInbox());
        }
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

      // 189 Fix B2 (INV-2): 'ok' only means the bridge call did not error —
      // the Go recovery verdict rides the serialized 'success' field. Tolerate
      // an ABSENT field (older bridge), but never report success:false as
      // recovered: that lie reset the failure accounting and kept the 30s
      // restart loop invisible (spec 189 Defect B bookkeeping).
      if (reconnectResponse['ok'] == true &&
          reconnectResponse['success'] != false) {
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
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_HEALTH_CHECK_RECOVERY_FAILED',
        details: {
          'consecutiveRefreshFailures': _consecutiveRefreshFailures,
          if (reconnectResponse['errorCode'] != null)
            'errorCode': reconnectResponse['errorCode'],
          if (reconnectResponse['recoveryMode'] != null)
            'recoveryMode': reconnectResponse['recoveryMode'],
        },
      );
      if (kDebugMode) {
        debugPrint(
          '[HEALTH] relay:reconnect FAILED '
          '(failure #$_consecutiveRefreshFailures, took ${reconnectMs}ms)',
        );
      }
    } catch (e) {
      _consecutiveRefreshFailures++;
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_HEALTH_CHECK_RECOVERY_FAILED',
        details: {
          'consecutiveRefreshFailures': _consecutiveRefreshFailures,
          'error': e.toString(),
        },
      );
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

    final pendingStartupDrain = _inboxCoordinator.onNodeStateTransition(
      previousState,
      _currentState,
    );
    if (pendingStartupDrain != null) {
      unawaited(pendingStartupDrain);
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
        // 189 Fix B3: an observed-healthy relay breaks the failure streak even
        // when nothing on the Dart side recovered it (autorelay self-heal) —
        // otherwise the NEXT outage would inherit a stale skip budget and
        // start life backed-off.
        _consecutiveRefreshFailures = 0;
        _recoveryBackoffStep = 0;
        _recoveryBackoffSkipsRemaining = 0;
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

        // 189 Fix B3 (INV-4): once consecutive recovery failures reach the
        // threshold, periodic ticks skip the recovery ATTEMPT on an escalating
        // schedule instead of hard-dialing the relay every 30s forever.
        // User-visible refreshes keep their own recovery source (resume /
        // relay_state_push) and bypass the backoff; the drain below runs on
        // every tick regardless.
        final skipRecoveryForBackoff =
            !isStartupRelayRecovery &&
            recoverySource == 'health_check_poll' &&
            _recoveryBackoffSkipsRemaining > 0;
        if (skipRecoveryForBackoff) {
          _recoveryBackoffSkipsRemaining--;
          emitFlowEvent(
            layer: 'FL',
            event: 'RELAY_RECOVERY_BACKOFF_SKIP',
            details: {
              'backoffStep': _recoveryBackoffStep,
              'skipsRemaining': _recoveryBackoffSkipsRemaining,
              'consecutiveRefreshFailures': _consecutiveRefreshFailures,
            },
          );
          if (_stateMeaningfullyChanged(_currentState, freshState)) {
            _emitState(freshState, source: 'health_check_poll');
          }
        } else {
          if (!isStartupRelayRecovery) {
            _beginReadinessProofWindow(
              phase: _resumeStartedAt != null
                  ? 'background_resume'
                  : 'recovery',
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

          // 189 Fix B3: arm/escalate after a failed attempt, disarm on a
          // truthful success (which resets the counter inside the attempt).
          if (_consecutiveRefreshFailures >= refreshFailureThreshold) {
            final nextStep = _recoveryBackoffStep == 0
                ? 1
                : _recoveryBackoffStep * 2;
            _recoveryBackoffStep = nextStep > recoveryBackoffMaxSkipTicks
                ? recoveryBackoffMaxSkipTicks
                : nextStep;
            _recoveryBackoffSkipsRemaining = _recoveryBackoffStep;
          } else if (_consecutiveRefreshFailures == 0) {
            _recoveryBackoffStep = 0;
            _recoveryBackoffSkipsRemaining = 0;
          }

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
        }

        // 189 Fix A (INV-1): the recovery branch must never starve the
        // periodic drain — a degraded relay session can still serve
        // retrieve_pending, and for a foreground+idle device this is the ONLY
        // recurring drain. Runs after the recovery attempt so it rides the
        // freshly re-dialed session.
        await _inboxCoordinator._drainOfflineInbox();
        if (_stopped) return;

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
      await _inboxCoordinator._drainOfflineInbox();
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

    _peerTransportCoordinator.onPeerDisconnected(conn.peerId);

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

    _peerTransportCoordinator.onRelayHealthTransition(
      wasHealthy: wasHealthy,
      nowHealthy: nowHealthy,
    );

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

    _peerTransportCoordinator.onListenAddressesUpdated(listenAddresses);
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

    _peerTransportCoordinator.onRelayHealthTransition(
      wasHealthy: wasHealthy,
      nowHealthy: nowHealthy,
    );

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
    final platform = _lastFcmPlatform;
    if (platform == null) {
      return;
    }
    // Plan 320 P2: prefer the LIVE provider token. The cached value may be the
    // very token the relay just evicted as permanently unroutable; re-sending
    // it would resurrect a dead entry on every relay-health transition.
    var token = _lastFcmToken;
    final reader = _liveFcmTokenReader;
    if (reader != null) {
      try {
        final live = (await reader())?.trim();
        if (live != null && live.isNotEmpty) {
          token = live;
        } else {
          logPushDiagnostic(
            'live_push_token_unavailable_using_cached',
            details: {'platform': platform},
          );
        }
      } catch (e) {
        logPushDiagnostic(
          'live_push_token_read_failed_using_cached',
          details: {'platform': platform, 'error': e.toString()},
        );
      }
    }
    if (token == null) {
      return;
    }
    await registerPushToken(token, platform);
  }

  @override
  Future<bool> storeInInbox(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) => _inboxCoordinator.storeInInbox(toPeerId, message, timeoutMs: timeoutMs);

  @override
  Future<InboxStoreOutcome> storeInInboxDetailed(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) => _inboxCoordinator.storeInInboxDetailed(
    toPeerId,
    message,
    timeoutMs: timeoutMs,
  );

  @override
  Future<InboxStoreOutcome> storeInAckCustodyInboxDetailed(
    String toPeerId,
    String message, {
    required AckCustodyKind custodyKind,
    int? timeoutMs,
  }) => _inboxCoordinator.storeInAckCustodyInboxDetailed(
    toPeerId,
    message,
    custodyKind: custodyKind,
    timeoutMs: timeoutMs,
  );

  @override
  Future<InboxStoreOutcome> storeInMediaExpiryBoundedInboxDetailed(
    String toPeerId,
    String message, {
    required int custodyExpiresAtOrBeforeMs,
    int? timeoutMs,
  }) => _inboxCoordinator.storeInMediaExpiryBoundedInboxDetailed(
    toPeerId,
    message,
    custodyExpiresAtOrBeforeMs: custodyExpiresAtOrBeforeMs,
    timeoutMs: timeoutMs,
  );

  @override
  Future<InboxStoreOutcome> storeInGroupContentExpiryBoundedInboxDetailed(
    String toPeerId,
    String message, {
    required int custodyExpiresAtOrBeforeMs,
    int? timeoutMs,
  }) => _inboxCoordinator.storeInGroupContentExpiryBoundedInboxDetailed(
    toPeerId,
    message,
    custodyExpiresAtOrBeforeMs: custodyExpiresAtOrBeforeMs,
    timeoutMs: timeoutMs,
  );

  @override
  Future<List<Map<String, dynamic>>> retrieveInbox({int? timeoutMs}) =>
      _inboxCoordinator.retrieveInbox(timeoutMs: timeoutMs);

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
        await _peerTransportCoordinator.restartLocalAdvertising();
        _peerTransportCoordinator.setLocalDiscoveryActive();
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[P2PService] Local P2P restart advertising failed: $e');
        }
        _peerTransportCoordinator.setLocalDiscoveryInactive();
      }
    } finally {
      final completer = _recoveryInProgress;
      _recoveryInProgress = null;
      completer?.complete();
    }

    if (kDebugMode) debugPrint('[HEALTH] performImmediateHealthCheck() done');
  }

  @override
  Future<void> drainOfflineInbox() => _inboxCoordinator.drainOfflineInbox();

  @override
  Future<DirectInboxDrainOutcome> drainOfflineInboxFully() =>
      _inboxCoordinator.drainOfflineInboxFully();

  /// Stops new protected group-content applies and waits for the current apply
  /// callback to leave its durable transaction. Staged and relay-owned bytes
  /// remain untouched for the next resume pass.
  Future<void> pauseProtectedGroupContentAdmission() =>
      _inboxCoordinator.pauseProtectedGroupContentAdmission();

  /// Re-opens protected content replay immediately before the bounded resume
  /// fixed point begins.
  void resumeProtectedGroupContentAdmission() =>
      _inboxCoordinator.resumeProtectedGroupContentAdmission();

  /// Replays protected prerequisites until durable staging stops changing,
  /// bounded so a hostile relay cannot spin the lifecycle owner forever.
  Future<int> drainProtectedGroupContentFixedPoint({int maxPasses = 8}) =>
      _inboxCoordinator.drainProtectedGroupContentFixedPoint(
        maxPasses: maxPasses,
      );

  @override
  Future<RelayProbeResult> probeRelay(String peerId) =>
      _peerTransportCoordinator.probeRelay(peerId);

  @override
  Future<RelayPresence> lookupRelayPresence(String peerId) =>
      _peerTransportCoordinator.lookupRelayPresence(peerId);

  @override
  Future<PresenceSetResult> setPresence(String state, int ttlMs) =>
      _peerTransportCoordinator.setPresence(state, ttlMs);

  @override
  Future<bool> pingPeer(String peerId, {required int timeoutMs}) =>
      _peerTransportCoordinator.pingPeer(peerId, timeoutMs: timeoutMs);

  @override
  bool isPeerSuspectedDropped(String peerId) =>
      _peerTransportCoordinator.isPeerSuspectedDropped(peerId);

  @override
  void setPeerDropSuspected(String peerId, bool dropped) {
    _peerTransportCoordinator.setPeerDropSuspected(peerId, dropped);
  }

  // 172: InboxAttentionSignal — the conversation UI's count source for the
  // "couldn't display N messages" affordance (INV-2: a kept-but-undisplayed
  // staged entry is never silently invisible). Never throws: any repo/DB error
  // degrades to 0 (the affordance simply hides).
  @override
  Future<int> countNeedsAttentionInboxEntries() =>
      _inboxCoordinator.countNeedsAttentionInboxEntries();

  @override
  bool isConnectedToPeer(String peerId) =>
      _peerTransportCoordinator.isConnectedToPeer(peerId);

  @override
  bool isLocalPeer(String peerId) =>
      _peerTransportCoordinator.isLocalPeer(peerId);

  bool hasNonCircuitDirectConn(String peerId) =>
      _peerTransportCoordinator.hasNonCircuitDirectConn(peerId);

  @override
  String? lastKnownGoodTransport(String peerId) =>
      _peerTransportCoordinator.lastKnownGoodTransport(peerId);

  @override
  void recordSuccessfulTransport(String peerId, String transport) {
    _peerTransportCoordinator.recordSuccessfulTransport(peerId, transport);
  }

  @override
  Future<bool> discoverLocalPeer(String peerId, {required Duration timeout}) =>
      _peerTransportCoordinator.discoverLocalPeer(peerId, timeout: timeout);

  @override
  Future<LanSendAck> sendLocalMessageDurable(
    String peerId,
    String message,
    String fromPeerId, {
    int? timeoutMs,
  }) => _peerTransportCoordinator.sendLocalMessageDurable(
    peerId,
    message,
    fromPeerId,
    timeoutMs: timeoutMs,
  );

  @override
  Future<bool> sendLocalMessage(
    String peerId,
    String message,
    String fromPeerId, {
    int? timeoutMs,
  }) => _peerTransportCoordinator.sendLocalMessage(
    peerId,
    message,
    fromPeerId,
    timeoutMs: timeoutMs,
  );

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
  }) => _peerTransportCoordinator.sendLocalMedia(
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
    _peerTransportCoordinator.dispose();
    _peerTransportCoordinator.disposeLocalService();

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
