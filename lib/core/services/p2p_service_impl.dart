import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'p2p_service.dart';
import '../bridge/bridge.dart';
import '../bridge/p2p_bridge_client.dart';
import '../local_discovery/local_discovery_service.dart';
import '../local_discovery/local_p2p_service.dart';
import '../utils/key_conversion.dart';
import '../utils/chat_console_logger.dart';
import '../utils/flow_event_emitter.dart';
import '../../features/p2p/domain/models/node_state.dart';
import '../../features/p2p/domain/models/chat_message.dart';
import '../../features/p2p/domain/models/discovered_peer.dart';
import '../../features/p2p/domain/models/send_message_result.dart';
import '../../features/p2p/domain/models/connection_state.dart';

/// Implementation of P2PService backed by the Go native bridge.
class P2PServiceImpl implements P2PService {
  final Bridge _bridge;
  final LocalP2PService? _localP2P;
  StreamSubscription<LocalChatMessage>? _localMessageSub;

  final _stateController = StreamController<NodeState>.broadcast();
  final _messageController = StreamController<ChatMessage>.broadcast();

  NodeState _currentState = NodeState.stopped;
  Timer? _healthCheckTimer;
  String? _lastFcmToken;
  String? _lastFcmPlatform;
  bool _isStarting = false;
  DateTime? _startNodeTime;
  bool _hasEverBeenOnline = false;
  bool _isHealthChecking = false;
  bool _stopped = true; // starts stopped; cleared when node starts

  /// How often the health check polls node:status.
  static const healthCheckInterval = Duration(seconds: 30);

  /// Maximum time budget for warm background tasks during startup.
  static const warmTaskTimeout = Duration(seconds: 5);

  P2PServiceImpl({
    required Bridge bridge,
    LocalP2PService? localP2PService,
  })  : _bridge = bridge,
        _localP2P = localP2PService {
    // Register event handlers on the bridge
    _bridge.onMessageReceived = (msg) {
      _handleMessageReceived(msg.copyWith(transport: 'relay'));
    };
    _bridge.onPeerConnected = _handlePeerConnected;
    _bridge.onPeerDisconnected = _handlePeerDisconnected;
    _bridge.onAddressesUpdated = _handleAddressesUpdated;

    // Merge local WiFi messages into the unified message stream
    _localMessageSub = _localP2P?.localMessageStream.listen((localMsg) {
      _handleMessageReceived(ChatMessage(
        from: localMsg.from,
        to: localMsg.to,
        content: localMsg.content,
        timestamp: localMsg.timestamp.toIso8601String(),
        isIncoming: localMsg.isIncoming,
        transport: 'wifi',
      ));
    });
  }

  @override
  NodeState get currentState => _currentState;

  @override
  Stream<NodeState> get stateStream => _stateController.stream;

  @override
  Stream<ChatMessage> get messageStream => _messageController.stream;

  @override
  Future<bool> startNode(String privateKeyBase64, String peerId) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_SERVICE_START_NODE_BEGIN',
      details: {'peerId': peerId},
    );

    final success = await startNodeCore(privateKeyBase64, peerId);
    if (success) {
      await warmBackground();
    }
    return success;
  }

  @override
  Future<bool> startNodeCore(String privateKeyBase64, String peerId) async {
    if (_isStarting) {
      debugPrint('[START] startNodeCore() skipped — already starting');
      return false;
    }
    _isStarting = true;
    _startNodeTime = DateTime.now();
    debugPrint('[START] startNodeCore() beginning for peerId=$peerId');

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
        _emitState(NodeState.fromJson(response));

        if (_currentState.circuitAddresses.isNotEmpty) {
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
        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_START_NODE_CORE_ALREADY_RUNNING',
          details: {},
        );

        final statusResponse = await callP2PNodeStatus(_bridge);
        if (statusResponse['ok'] == true) {
          _stopped = false;
          _emitState(NodeState.fromJson(statusResponse));

          if (_currentState.circuitAddresses.isNotEmpty) {
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

    debugPrint('[WARM] warmBackground() starting — '
        'circuitAddresses=${_currentState.circuitAddresses.length}');

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
      if (_currentState.isStarted && _currentState.circuitAddresses.isEmpty) {
        debugPrint('[WARM] Fast circuit check — still no circuit after 2s, polling...');
        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_FAST_CIRCUIT_CHECK',
          details: {'reason': 'no push event after 2s'},
        );
        _performHealthCheck();
      } else {
        debugPrint('[WARM] Fast circuit check — already have '
            '${_currentState.circuitAddresses.length} circuit addresses, skipping');
      }
    });

    // Run inbox drain and local discovery concurrently.
    final futures = <Future>[];
    futures.add(
      _drainOfflineInbox().timeout(warmTaskTimeout).catchError((_) {}),
    );

    final localPeerId = _currentState.peerId;
    if (_localP2P != null && localPeerId != null) {
      futures.add(
        _localP2P.start(localPeerId).timeout(warmTaskTimeout).catchError((_) {}),
      );
    }

    await Future.wait(futures);

    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_SERVICE_WARM_BACKGROUND_COMPLETE',
      details: {},
    );
  }

  /// Maximum number of inbox pages to drain in a single pass.
  /// Prevents infinite loops if the server keeps returning hasMore.
  static const int maxInboxPages = 10;

  /// Drain queued offline inbox messages and inject them into message stream.
  /// Loops through pages when the server indicates more messages are available.
  Future<void> _drainOfflineInbox() async {
    try {
      final toPeerId = _currentState.peerId ?? '';
      var totalEmitted = 0;

      for (var page = 0; page < maxInboxPages; page++) {
        final response = await callP2PInboxRetrieve(_bridge);
        if (response['ok'] != true) {
          break;
        }

        final inboxMessages =
            (response['messages'] as List<dynamic>?)
                ?.cast<Map<String, dynamic>>() ??
            [];
        if (inboxMessages.isEmpty) {
          break;
        }

        for (final raw in inboxMessages) {
          final from = raw['from']?.toString();
          final content = raw['message']?.toString();
          if (from == null || from.isEmpty || content == null || content.isEmpty) {
            continue;
          }

          final ts = raw['timestamp'];
          final timestamp = ts is int
              ? DateTime.fromMillisecondsSinceEpoch(ts, isUtc: true)
                    .toIso8601String()
              : (ts as String?) ?? DateTime.now().toUtc().toIso8601String();

          _handleMessageReceived(
            ChatMessage(
              from: from,
              to: toPeerId,
              content: content,
              timestamp: timestamp,
              isIncoming: true,
              transport: 'inbox',
            ),
          );
          totalEmitted++;
        }

        // Check if the server has more pages.
        final hasMore = response['hasMore'] == true;
        if (!hasMore) {
          break;
        }

        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_INBOX_DRAIN_PAGE',
          details: {'page': page + 1, 'emitted': totalEmitted},
        );
      }

      if (totalEmitted > 0) {
        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_INBOX_DRAIN_SUCCESS',
          details: {
            'count': totalEmitted,
            'note': 'messages consumed and deleted from relay memory',
          },
        );
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_INBOX_DRAIN_EXCEPTION',
        details: {'error': e.toString()},
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
      } catch (e) {
        debugPrint('[P2PService] Local P2P stop failed: $e');
      }

      _stopHealthCheck();
      final response = await callP2PNodeStop(_bridge);

      if (response['ok'] == true) {
        _hasEverBeenOnline = false;
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
        final acknowledged =
            acked ?? (reply != null && reply.isNotEmpty);

        if ((sent ?? true) && acknowledged) {
          emitFlowEvent(
            layer: 'FL',
            event: 'P2P_SERVICE_SEND_MESSAGE_SUCCESS',
            details: {'peerId': peerId, 'acked': acked, 'hasReply': reply != null},
          );
          return true;
        }

        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_SEND_MESSAGE_UNACKED',
          details: {'peerId': peerId, 'acked': acked, 'hasReply': reply != null},
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
        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_SEND_MESSAGE_WITH_REPLY_SUCCESS',
          details: {'peerId': peerId, 'hasReply': reply != null, 'acked': acked},
        );
        return SendMessageResult(sent: true, acked: acked, reply: reply);
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
    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_SERVICE_DISCOVER_PEER_BEGIN',
      details: {'peerId': peerId, if (timeoutMs != null) 'timeoutMs': timeoutMs},
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
  Future<bool> dialPeer(String peerId, {List<String>? addresses, int? timeoutMs}) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_SERVICE_DIAL_PEER_BEGIN',
      details: {'peerId': peerId, 'hasAddresses': addresses != null, if (timeoutMs != null) 'timeoutMs': timeoutMs},
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
    debugPrint('[HEALTH] Starting periodic health check timer '
        '(every ${healthCheckInterval.inSeconds}s)');
    _healthCheckTimer = Timer.periodic(healthCheckInterval, (_) {
      debugPrint('[HEALTH] Periodic health check firing...');
      _performHealthCheck();
    });
  }

  /// Stop the periodic health check timer.
  void _stopHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
  }

  /// Safely update [_currentState] and emit to [_stateController].
  /// No-op if the controller is closed.
  void _emitState(NodeState newState) {
    _currentState = newState;
    if (!_stateController.isClosed) {
      _stateController.add(_currentState);
    }
  }

  /// Poll node:status, attempt recovery if degraded, and emit state changes.
  Future<void> _performHealthCheck() async {
    if (_isHealthChecking || _stopped) {
      debugPrint('[HEALTH] _performHealthCheck() skipped — already in progress or stopped');
      return;
    }
    _isHealthChecking = true;
    final hcStart = DateTime.now();
    debugPrint('[HEALTH] _performHealthCheck() starting...');
    try {
      final statusStart = DateTime.now();
      final response = await callP2PNodeStatus(_bridge);
      if (_stopped) return;
      final statusMs = DateTime.now().difference(statusStart).inMilliseconds;
      final freshState = NodeState.fromJson(response);
      debugPrint('[HEALTH] node:status took ${statusMs}ms → '
          'isStarted=${freshState.isStarted}, '
          'circuitAddresses=${freshState.circuitAddresses.length}, '
          'connections=${freshState.connections.length}, '
          'peerId=${freshState.peerId}');

      // Recovery: node is started but has no relay circuit — reconnect relays.
      // relay:reconnect restarts the Go node to get fresh AutoRelay reservations.
      // Only trigger this for RECOVERY (was online before, lost circuits), not
      // during initial startup where the relay connection is still in progress.
      if (freshState.isStarted &&
          freshState.circuitAddresses.isEmpty &&
          _hasEverBeenOnline) {
        debugPrint('[HEALTH] DEGRADED — no circuit addresses (was online before). '
            'Calling relay:reconnect to restart node...');

        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_HEALTH_CHECK_RECOVERY_ATTEMPT',
          details: {'method': 'relay:reconnect'},
        );

        try {
          final reconnectStart = DateTime.now();
          await callP2PRelayReconnect(_bridge);
          final reconnectMs = DateTime.now().difference(reconnectStart).inMilliseconds;
          debugPrint('[HEALTH] relay:reconnect SUCCESS (took ${reconnectMs}ms)');
        } catch (e) {
          debugPrint('[HEALTH] relay:reconnect FAILED: $e');
          // Relay still unreachable — will retry on next health check
        }
        if (_stopped) return;

        // Re-poll status after dialing the relay
        final retryStatusStart = DateTime.now();
        final retryResponse = await callP2PNodeStatus(_bridge);
        if (_stopped) return;
        final retryStatusMs = DateTime.now().difference(retryStatusStart).inMilliseconds;
        final retryState = NodeState.fromJson(retryResponse);
        debugPrint('[HEALTH] Post-dial status (took ${retryStatusMs}ms) → '
            'circuitAddresses=${retryState.circuitAddresses.length}, '
            'connections=${retryState.connections.length}');

        if (retryState.circuitAddresses.isEmpty) {
          debugPrint('[HEALTH] Still no circuit addresses after re-dial! '
              'Circuit reservation may still be in progress. '
              'Next health check in ${healthCheckInterval.inSeconds}s');
        }

        if (retryState.isStarted != _currentState.isStarted ||
            retryState.circuitAddresses.length !=
                _currentState.circuitAddresses.length ||
            retryState.connections.length != _currentState.connections.length) {
          _emitState(retryState);

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
          if (retryState.circuitAddresses.isNotEmpty &&
              _lastFcmToken != null &&
              _lastFcmPlatform != null) {
            registerPushToken(_lastFcmToken!, _lastFcmPlatform!);
          }
        }

        final totalMs = DateTime.now().difference(hcStart).inMilliseconds;
        debugPrint('[HEALTH] Recovery health check done (total ${totalMs}ms)');
        return;
      } else if (freshState.isStarted &&
          freshState.circuitAddresses.isEmpty &&
          !_hasEverBeenOnline) {
        debugPrint('[HEALTH] DEGRADED — no circuit addresses yet (first startup, '
            'relay connection still in progress). Waiting...');
      }

      // Drain offline inbox on each health check so we pick up
      // messages stored while we were unreachable via direct dial.
      await _drainOfflineInbox();
      if (_stopped) return;

      // Normal path: only emit if something meaningful changed
      if (freshState.isStarted != _currentState.isStarted ||
          freshState.circuitAddresses.length !=
              _currentState.circuitAddresses.length ||
          freshState.connections.length != _currentState.connections.length) {
        _emitState(freshState);

        debugPrint('[HEALTH] State changed → '
            'isStarted=${freshState.isStarted}, '
            'circuitAddresses=${freshState.circuitAddresses.length}, '
            'connections=${freshState.connections.length}');

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
        debugPrint('[HEALTH] No state change (online, all good)');
      }
    } catch (e) {
      debugPrint('[HEALTH] _performHealthCheck EXCEPTION: $e');

      // If the check itself fails, assume the node is down
      if (_currentState.isStarted) {
        _emitState(NodeState.stopped);

        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_HEALTH_CHECK_FAILED',
          details: {'error': e.toString()},
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
    if (!_messageController.isClosed) {
      _messageController.add(message);
    }
  }

  /// Handle peer connected event from bridge.
  void _handlePeerConnected(ConnectionState conn) {
    if (_stopped) return;
    debugPrint('[CONN] peer:connected → ${conn.peerId} (${conn.status})');

    // Update current state with new connection
    final updatedConnections = List<ConnectionState>.from(
      _currentState.connections,
    )..add(conn);

    _emitState(_currentState.copyWith(connections: updatedConnections));
  }

  /// Handle peer disconnected event from bridge.
  void _handlePeerDisconnected(ConnectionState conn) {
    if (_stopped) return;
    debugPrint('[CONN] peer:disconnected → ${conn.peerId}');

    // Update current state by removing the connection
    final updatedConnections = _currentState.connections
        .where((c) => c.peerId != conn.peerId)
        .toList();

    _emitState(_currentState.copyWith(connections: updatedConnections));
  }

  /// Handle addresses:updated push event from Go.
  void _handleAddressesUpdated(
    List<String> listenAddresses,
    List<String> circuitAddresses,
  ) {
    if (_stopped) return;
    final flutterElapsedMs = _startNodeTime != null
        ? DateTime.now().difference(_startNodeTime!).inMilliseconds
        : -1;

    final wasConnecting = _currentState.circuitAddresses.isEmpty;
    final nowOnline = circuitAddresses.isNotEmpty;

    debugPrint('[ADDR] addresses:updated push event → '
        'listen=${listenAddresses.length}, circuit=${circuitAddresses.length}, '
        'elapsed=${flutterElapsedMs}ms'
        '${wasConnecting && nowOnline ? " TRANSITION connecting->online" : ""}');
    if (circuitAddresses.isNotEmpty) {
      debugPrint('[ADDR] circuit addresses: ${circuitAddresses.join(", ")}');
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

    _emitState(_currentState.copyWith(
      listenAddresses: listenAddresses,
      circuitAddresses: circuitAddresses,
    ));

    if (circuitAddresses.isNotEmpty) {
      _hasEverBeenOnline = true;
    }

    // Re-register push token when circuit addresses become available
    if (circuitAddresses.isNotEmpty &&
        _lastFcmToken != null &&
        _lastFcmPlatform != null) {
      registerPushToken(_lastFcmToken!, _lastFcmPlatform!);
    }
  }

  @override
  Future<bool> storeInInbox(String toPeerId, String message) async {
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
    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_SERVICE_INBOX_RETRIEVE_BEGIN',
      details: {if (timeoutMs != null) 'timeoutMs': timeoutMs},
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
        return messages;
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_INBOX_RETRIEVE_ERROR',
        details: {'errorMessage': response['errorMessage']},
      );
      return [];
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_INBOX_RETRIEVE_EXCEPTION',
        details: {'error': e.toString()},
      );
      return [];
    }
  }

  @override
  Future<bool> registerPushToken(String token, String platform) async {
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
      emitFlowEvent(
        layer: 'FL',
        event: ok
            ? 'P2P_SERVICE_REGISTER_PUSH_TOKEN_SUCCESS'
            : 'P2P_SERVICE_REGISTER_PUSH_TOKEN_ERROR',
        details: {'platform': platform},
      );
      return ok;
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_REGISTER_PUSH_TOKEN_EXCEPTION',
        details: {'error': e.toString()},
      );
      return false;
    }
  }

  @override
  Future<void> performImmediateHealthCheck() async {
    debugPrint('[HEALTH] performImmediateHealthCheck() called');
    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_SERVICE_IMMEDIATE_HEALTH_CHECK_BEGIN',
      details: {},
    );
    await _performHealthCheck();

    // Restart mDNS advertising (e.g. after iOS returns from background)
    try {
      await _localP2P?.restartAdvertising();
    } catch (e) {
      debugPrint('[P2PService] Local P2P restart advertising failed: $e');
    }

    debugPrint('[HEALTH] performImmediateHealthCheck() done');
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
  bool isConnectedToPeer(String peerId) =>
      _currentState.connections.any(
        (c) => c.peerId == peerId && c.status == 'connected',
      );

  @override
  bool isLocalPeer(String peerId) => _localP2P?.isLocalPeer(peerId) ?? false;

  @override
  Future<bool> sendLocalMessage(String peerId, String message, String fromPeerId) async {
    if (_localP2P == null) return false;
    return _localP2P.sendMessage(peerId, message, fromPeerId);
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
    _localP2P?.dispose();
    if (!_stateController.isClosed) _stateController.close();
    if (!_messageController.isClosed) _messageController.close();

    // Clear event handlers
    _bridge.onMessageReceived = null;
    _bridge.onPeerConnected = null;
    _bridge.onPeerDisconnected = null;
    _bridge.onAddressesUpdated = null;
  }
}
