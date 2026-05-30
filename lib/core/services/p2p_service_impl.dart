import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'p2p_service.dart';
import '../bridge/bridge.dart';
import '../bridge/p2p_bridge_client.dart';
import '../debug/transport_metrics.dart';
import '../inbox/inbox_staging_entry.dart';
import '../inbox/inbox_staging_repository.dart';
import '../local_discovery/local_discovery_service.dart';
import '../local_discovery/local_p2p_service.dart';
import '../utils/key_conversion.dart';
import '../utils/chat_console_logger.dart';
import '../utils/flow_event_emitter.dart';
import '../utils/push_diagnostics_logger.dart';
import '../../features/p2p/domain/models/node_state.dart';
import '../../features/p2p/domain/models/chat_message.dart';
import '../../features/p2p/domain/models/discovered_peer.dart';
import '../../features/p2p/domain/models/send_message_result.dart';
import '../../features/p2p/domain/models/connection_state.dart';
import '../../features/push/domain/push_token_store.dart';

enum RecoveredInboxChatDisposition { committed, retryable, rejected }

typedef RecoveredInboxReplayOutcome = ({
  RecoveredInboxChatDisposition disposition,
  String reasonCode,
  String? reasonDetail,
});

typedef ReplayRecoveredInboxChatMessage =
    Future<RecoveredInboxReplayOutcome> Function(ChatMessage message);

typedef ReplayRecoveredInboxIntroductionMessage =
    Future<RecoveredInboxReplayOutcome> Function(ChatMessage message);

/// NET-REL-05 P3: a learned per-peer LIVE transport plus the time it was
/// recorded, for TTL-based expiry. `transport` is one of `'local'`, `'direct'`,
/// or `'relay'`.
class _LearnedTransport {
  final String transport;
  final DateTime at;
  const _LearnedTransport(this.transport, this.at);
}

/// Implementation of P2PService backed by the Go native bridge.
class P2PServiceImpl implements P2PService, ReadinessProofRecorder {
  final Bridge _bridge;
  final LocalP2PService? _localP2P;
  final PushTokenStore? _pushTokenStore;
  final InboxStagingRepository _inboxStagingRepository;
  final ReplayRecoveredInboxChatMessage? _replayRecoveredInboxChatMessage;
  final ReplayRecoveredInboxIntroductionMessage?
  _replayRecoveredInboxIntroductionMessage;
  final TransportMetrics? _transportMetrics;
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

  /// §24: Timestamp when startNodeCore() was called (for cold-start timing).
  DateTime? _nodeStartRequestedAt;

  /// §24: Timestamp when we last transitioned away from online (for recovery timing).
  DateTime? _lastWentOfflineAt;

  /// §24: Prevents duplicate cold-start events when multiple paths race.
  bool _coldStartOnlineEmitted = false;

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

  /// Maximum time budget for warm background tasks during startup.
  static const warmTaskTimeout = Duration(seconds: 5);

  /// Foreground budget for the first inbox page during startup and resume.
  static const foregroundInboxTimeout = Duration(seconds: 3);

  P2PServiceImpl({
    required Bridge bridge,
    LocalP2PService? localP2PService,
    PushTokenStore? pushTokenStore,
    required InboxStagingRepository inboxStagingRepository,
    ReplayRecoveredInboxChatMessage? replayRecoveredInboxChatMessage,
    ReplayRecoveredInboxIntroductionMessage?
    replayRecoveredInboxIntroductionMessage,
    TransportMetrics? transportMetrics,
  }) : _bridge = bridge,
       _localP2P = localP2PService,
       _pushTokenStore = pushTokenStore,
       _inboxStagingRepository = inboxStagingRepository,
       _replayRecoveredInboxChatMessage = replayRecoveredInboxChatMessage,
       _replayRecoveredInboxIntroductionMessage =
           replayRecoveredInboxIntroductionMessage,
       _transportMetrics = transportMetrics {
    // Register event handlers on the bridge
    _bridge.onMessageReceived = (msg) {
      final transport =
          msg.transport ?? _inferTransportForPeer(msg.from) ?? 'unknown';
      _transportMetrics?.recordTransport(transport);
      _handleMessageReceived(msg.copyWith(transport: transport));
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

    // Merge local WiFi messages into the unified message stream
    _localMessageSub = _localP2P?.localMessageStream.listen((localMsg) {
      _transportMetrics?.recordTransport('wifi');
      _handleMessageReceived(
        ChatMessage(
          from: localMsg.from,
          to: localMsg.to,
          content: localMsg.content,
          timestamp: localMsg.timestamp.toIso8601String(),
          isIncoming: localMsg.isIncoming,
          transport: 'wifi',
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
      // P4: a peer appearing clears any suspected-permission-denied state and
      // stops the heuristic timer (a peer was seen → permission is not denied).
      if (peers.isNotEmpty) {
        _lanPermProbeTimer?.cancel();
        _lanPermProbeTimer = null;
      }
      _recordLanAvailability(
        discoveryActive: _localDiscoveryActive,
        discoveredPeerCount: peers.length,
      );
    });
    _recordLanAvailability(
      discoveryActive: false,
      discoveredPeerCount: _localP2P?.discoveredPeers.length ?? 0,
    );

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

  @override
  Future<bool> startNode(String privateKeyBase64, String peerId) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_SERVICE_START_NODE_BEGIN',
      details: {'peerId': peerId},
    );

    final success = await startNodeCore(privateKeyBase64, peerId);
    if (success) {
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
    _isHotRestart = false;
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
      );

      if (response['ok'] == true) {
        _stopped = false;
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

    // Run inbox drain and local discovery concurrently.
    final futures = <Future>[];
    futures.add(_attemptProactiveSendProofIfNeeded(trigger: 'warm_background'));
    futures.add(
      _drainOfflineInbox().timeout(warmTaskTimeout).catchError((_) {}),
    );

    final localPeerId = _currentState.peerId;
    if (_localP2P != null && localPeerId != null) {
      futures.add(
        _startLocalDiscovery(
          localPeerId,
        ).timeout(warmTaskTimeout).catchError((_) {}),
      );
    }

    await Future.wait(futures);

    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_SERVICE_WARM_BACKGROUND_COMPLETE',
      details: {},
    );
  }

  Future<void> _startLocalDiscovery(String localPeerId) async {
    final localP2P = _localP2P;
    if (localP2P == null) return;

    try {
      await localP2P.start(localPeerId);
      _setLocalDiscoveryActive();
    } catch (_) {
      _setLocalDiscoveryInactive();
      rethrow;
    }
  }

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

  /// Maximum number of inbox pages to drain in a single pass.
  /// Prevents infinite loops if the server keeps returning hasMore.
  static const int maxInboxPages = 10;

  static const int maxRecoverableInboxReplayEntries = 500;

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

  bool _shouldDurablyStageDeferredDirectChat(
    ChatMessage message, {
    required String? envelopeType,
  }) {
    final nonce = message.confirmNonce;
    return message.isIncoming &&
        envelopeType == 'chat_message' &&
        nonce != null &&
        nonce.isNotEmpty &&
        _replayRecoveredInboxChatMessage != null;
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
    final replayRecoveredInboxChatMessage = _replayRecoveredInboxChatMessage;
    if (replayRecoveredInboxChatMessage == null) {
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
      final outcome = await replayRecoveredInboxChatMessage(replayMessage);
      await _applyRecoveredInboxOutcome(
        repo: repo,
        entry: entry,
        outcome: outcome,
        committedEvent: 'P2P_SERVICE_DIRECT_STAGED_CHAT_COMMITTED',
        retryableEvent: 'P2P_SERVICE_DIRECT_STAGED_CHAT_RETRYABLE',
        rejectedEvent: 'P2P_SERVICE_DIRECT_STAGED_CHAT_REJECTED',
      );
    } catch (e) {
      await repo.markRetryable(
        entry.entryId,
        reasonCode: 'processing_error',
        reasonDetail: e.toString(),
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_DIRECT_STAGED_CHAT_EXCEPTION',
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

  Future<int> _replayStagedInboxEntries({List<String>? entryIds}) async {
    final repo = _inboxStagingRepository;

    final entries = entryIds == null
        ? await repo.getRecoverableEntries(
            limit: maxRecoverableInboxReplayEntries,
          )
        : await repo.getRecoverableEntriesByIds(entryIds);
    var replayed = 0;

    for (final entry in entries) {
      final entryStopwatch = Stopwatch()..start();
      final message = entry.toChatMessage();
      try {
        final replayRecoveredInboxChatMessage =
            _replayRecoveredInboxChatMessage;
        if (entry.messageType == 'chat_message' &&
            replayRecoveredInboxChatMessage != null) {
          final outcome = await replayRecoveredInboxChatMessage(message);
          if (await _applyRecoveredInboxOutcome(
            repo: repo,
            entry: entry,
            outcome: outcome,
            committedEvent: 'P2P_SERVICE_INBOX_STAGED_CHAT_COMMITTED',
            retryableEvent: 'P2P_SERVICE_INBOX_STAGED_CHAT_RETRYABLE',
            rejectedEvent: 'P2P_SERVICE_INBOX_STAGED_CHAT_REJECTED',
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

        _handleMessageReceived(message);
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

  Future<bool> _applyRecoveredInboxOutcome({
    required InboxStagingRepository repo,
    required InboxStagingEntry entry,
    required RecoveredInboxReplayOutcome outcome,
    required String committedEvent,
    required String retryableEvent,
    required String rejectedEvent,
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
    }
  }

  Future<
    ({
      int replayed,
      int staged,
      bool hasMore,
      bool retrieveSucceeded,
      String? failureReason,
    })
  >
  _retrievePendingInboxPage({required String toPeerId, int? timeoutMs}) async {
    final repo = _inboxStagingRepository;

    Map<String, dynamic> response;
    try {
      response = await callP2PInboxRetrievePending(
        _bridge,
        timeoutMs: timeoutMs,
      );
    } catch (e) {
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
      );
    }

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
      );
    }

    final ackableEntryIds = await repo.stageEntries(entries);
    if (ackableEntryIds.isNotEmpty) {
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
    }

    final replayed = ackableEntryIds.isEmpty
        ? 0
        : await _replayStagedInboxEntries(entryIds: ackableEntryIds);

    return (
      replayed: replayed,
      staged: ackableEntryIds.length,
      hasMore: response['hasMore'] == true,
      retrieveSucceeded: true,
      failureReason: null,
    );
  }

  /// Drain queued offline inbox messages and inject them into message stream.
  /// Retrieves the first page on the foreground budget, then continues in the
  /// background when the relay reports remaining backlog.
  Future<void> _drainOfflineInbox() async {
    await _drainOfflineInboxDurably();
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

  Future<void> _drainOfflineInboxDurably() async {
    try {
      final toPeerId = _currentState.peerId ?? '';
      final replayedExisting = await _replayStagedInboxEntries();
      final firstPage = await _retrievePendingInboxPage(
        toPeerId: toPeerId,
        timeoutMs: foregroundInboxTimeout.inMilliseconds,
      );

      final totalReplayed = replayedExisting + firstPage.replayed;
      final totalStaged = firstPage.staged;

      if (firstPage.hasMore && totalStaged > 0) {
        unawaited(
          _continueDrainingOfflineInboxDurably(
            toPeerId: toPeerId,
            totalReplayed: totalReplayed,
            totalStaged: totalStaged,
          ),
        );
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
  }) async {
    final details = <String, dynamic>{
      'peerId': peerId,
      'hasAddresses': addresses != null,
    };
    if (timeoutMs != null) {
      details['timeoutMs'] = timeoutMs;
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
    _activeReadinessProofWindowId =
        'readiness_${_readinessProofWindowSequence}';
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
          if (sendPath != null) 'sendPath': sendPath,
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
        if (trigger != null) 'trigger': trigger,
        if (sendPath != null) 'sendPath': sendPath,
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
            if (foregroundRecoveryPath != null)
              'foregroundRecoveryPath': foregroundRecoveryPath,
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

    _currentState = mergeServiceOwnedReadiness
        ? _stateWithReadinessProjection(newState)
        : newState;
    if (!_stateController.isClosed) {
      _stateController.add(_currentState);
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

  bool _stateNeedsRelayRecovery(NodeState state) {
    if (!state.isStarted) return false;

    final relayState = state.relayState;
    if (relayState != null) {
      return relayState != 'online';
    }
    return state.circuitAddresses.isEmpty;
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
        _transportMetrics?.recordRelayToDirectUpgrade();
        _recordPeerUpgrade(event['remotePeerShort'] as String?);
        break;
    }
  }

  void _recordPeerUpgrade(String? remotePeerShort) {
    if (remotePeerShort != null && remotePeerShort.isNotEmpty) {
      _peersUpgradedToDirect.add(remotePeerShort);
    }
  }

  String? _inferTransportForPeer(String peerId) {
    // A peer that genuinely upgraded relay->direct (observed via the DCUtR
    // tracer) is direct, even if _currentState still holds a stale
    // /p2p-circuit multiaddr for it (libp2p does not re-fire connectedness on
    // an upgrade).
    if (_peersUpgradedToDirect.contains(_shortId(peerId))) {
      return 'direct';
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
      if (_stateNeedsRelayRecovery(freshState) && _hasEverBeenOnline) {
        _outageDetectedAt ??= DateTime.now();
        final detectionMs = _lastHealthyRelayAt != null
            ? DateTime.now().difference(_lastHealthyRelayAt!).inMilliseconds
            : -1;
        final recoverySource =
            _pendingRecoverySource ??
            (_resumeStartedAt != null ? 'resume_trigger' : 'health_check_poll');
        _pendingRecoverySource = null;
        _beginReadinessProofWindow(
          phase: _resumeStartedAt != null ? 'background_resume' : 'recovery',
          trigger: recoverySource,
          startedAt: _resumeStartedAt ?? DateTime.now(),
        );
        emitFlowEvent(
          layer: 'FL',
          event: 'RELAY_OUTAGE_TIMING',
          details: {
            'phase': 'detected',
            'detectionMs': detectionMs,
            'detectionSource': 'poll',
          },
        );
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
          !_stateHasHealthyRelay(freshState) &&
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

  /// Handle incoming chat message from bridge event.
  void _handleMessageReceived(ChatMessage message) {
    String? envelopeType;
    try {
      final decoded = jsonDecode(message.content);
      if (decoded is Map<String, dynamic>) {
        envelopeType = decoded['type'] as String?;
      }
    } catch (_) {
      envelopeType = null;
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
        return;
      }
    }

    _emitIncomingMessage(message);
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
      final ok = response['ok'] == true;
      emitFlowEvent(
        layer: 'FL',
        event: ok
            ? 'P2P_SERVICE_INBOX_STORE_SUCCESS'
            : 'P2P_SERVICE_INBOX_STORE_ERROR',
        details: {'toPeerId': toPeerId},
      );
      return ok;
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_INBOX_STORE_EXCEPTION',
        details: {'error': e.toString()},
      );
      return false;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> retrieveInbox({int? timeoutMs}) async {
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
    if (!_currentState.isStarted) return;

    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_SERVICE_DRAIN_OFFLINE_INBOX_BEGIN',
      details: {},
    );
    await _drainOfflineInbox();
  }

  @override
  Future<RelayProbeResult> probeRelay(String peerId) async {
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
  bool isConnectedToPeer(String peerId) => _currentState.connections.any(
    (c) => c.peerId == peerId && c.status == 'connected',
  );

  @override
  bool isLocalPeer(String peerId) => _localP2P?.isLocalPeer(peerId) ?? false;

  @override
  String? lastKnownGoodTransport(String peerId) {
    final e = _learnedTransport[peerId];
    if (e == null) return null;
    final age = DateTime.now().difference(e.at);
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
      _learnedTransport[peerId] = _LearnedTransport(transport, DateTime.now());
    }
  }

  @override
  Future<bool> discoverLocalPeer(
    String peerId, {
    required Duration timeout,
  }) async {
    final localP2P = _localP2P;
    if (localP2P == null) return false;
    return localP2P.discoverLocalPeer(peerId, timeout: timeout);
  }

  @override
  Future<bool> sendLocalMessage(
    String peerId,
    String message,
    String fromPeerId, {
    int? timeoutMs,
  }) async {
    if (_localP2P == null) return false;
    return _localP2P.sendMessage(
      peerId,
      message,
      fromPeerId,
      timeoutMs: timeoutMs,
    );
  }

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
  }) async {
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
    );
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
