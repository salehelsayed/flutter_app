import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'p2p_service.dart';
import '../bridge/webview_js_bridge.dart';
import '../bridge/p2p_bridge_client.dart';
import '../utils/key_conversion.dart';
import '../utils/chat_console_logger.dart';
import '../utils/flow_event_emitter.dart';
import '../../features/p2p/domain/models/node_state.dart';
import '../../features/p2p/domain/models/chat_message.dart';
import '../../features/p2p/domain/models/discovered_peer.dart';
import '../../features/p2p/domain/models/send_message_result.dart';
import '../../features/p2p/domain/models/connection_state.dart';

/// Implementation of P2PService using WebViewJsBridge.
class P2PServiceImpl implements P2PService {
  final WebViewJsBridge _bridge;

  final _stateController = StreamController<NodeState>.broadcast();
  final _messageController = StreamController<ChatMessage>.broadcast();

  NodeState _currentState = NodeState.stopped;
  Timer? _healthCheckTimer;

  /// How often the health check polls node:status.
  static const healthCheckInterval = Duration(seconds: 30);

  P2PServiceImpl({required WebViewJsBridge bridge}) : _bridge = bridge {
    // Register event handlers on the bridge
    _bridge.onMessageReceived = _handleMessageReceived;
    _bridge.onPeerConnected = _handlePeerConnected;
    _bridge.onPeerDisconnected = _handlePeerDisconnected;
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

    try {
      // Convert key format from BASE64 to HEX
      final privateKeyHex = base64ToHex(privateKeyBase64);

      // Build the namespace for this peer
      final namespace = 'mknoon:chat:$peerId';

      // Start the node via bridge
      final response = await callP2PNodeStart(
        _bridge,
        privateKeyHex: privateKeyHex,
        autoRegister: true,
        namespace: namespace,
      );

      if (response['ok'] == true) {
        _currentState = NodeState.fromJson(response);
        _stateController.add(_currentState);
        await _drainOfflineInbox();
        _startHealthCheck();

        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_START_NODE_SUCCESS',
          details: {'peerId': _currentState.peerId},
        );

        return true;
      } else {
        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_START_NODE_ERROR',
          details: {
            'errorCode': response['errorCode'],
            'errorMessage': response['errorMessage'],
          },
        );
        return false;
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_START_NODE_EXCEPTION',
        details: {'error': e.toString()},
      );
      return false;
    }
  }

  /// Drain queued offline inbox messages and inject them into message stream.
  Future<void> _drainOfflineInbox() async {
    try {
      final inboxMessages = await retrieveInbox();
      if (inboxMessages.isEmpty) {
        return;
      }

      final toPeerId = _currentState.peerId ?? '';
      var emitted = 0;

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
          ),
        );
        emitted++;
      }

      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_INBOX_DRAIN_SUCCESS',
        details: {
          'count': emitted,
          'note': 'messages consumed and deleted from relay memory',
        },
      );
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

    try {
      _stopHealthCheck();
      final response = await callP2PNodeStop(_bridge);

      if (response['ok'] == true) {
        _currentState = NodeState.stopped;
        _stateController.add(_currentState);

        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_STOP_NODE_SUCCESS',
          details: {},
        );

        return true;
      } else {
        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_STOP_NODE_ERROR',
          details: {'errorMessage': response['errorMessage']},
        );
        return false;
      }
    } catch (e) {
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

      if (response['ok'] == true && response['sent'] == true) {
        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_SEND_MESSAGE_SUCCESS',
          details: {'peerId': peerId},
        );
        return true;
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
    String message,
  ) async {
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
      );

      if (response['ok'] == true && response['sent'] == true) {
        final reply = response['reply'] as String?;
        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_SEND_MESSAGE_WITH_REPLY_SUCCESS',
          details: {'peerId': peerId, 'hasReply': reply != null},
        );
        return SendMessageResult(sent: true, reply: reply);
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
  Future<DiscoveredPeer?> discoverPeer(String peerId) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_SERVICE_DISCOVER_PEER_BEGIN',
      details: {'peerId': peerId},
    );

    try {
      final response = await callP2PRendezvousDiscover(_bridge, peerId: peerId);

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
  Future<bool> dialPeer(String peerId, {List<String>? addresses}) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_SERVICE_DIAL_PEER_BEGIN',
      details: {'peerId': peerId, 'hasAddresses': addresses != null},
    );

    try {
      final response = await callP2PPeerDial(
        _bridge,
        peerId: peerId,
        addresses: addresses,
      );

      if (response['ok'] == true && response['connected'] == true) {
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
    _healthCheckTimer = Timer.periodic(healthCheckInterval, (_) {
      _performHealthCheck();
    });
  }

  /// Stop the periodic health check timer.
  void _stopHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
  }

  /// Poll node:status, attempt recovery if degraded, and emit state changes.
  Future<void> _performHealthCheck() async {
    try {
      final response = await callP2PNodeStatus(_bridge);
      final freshState = NodeState.fromJson(response);

      // Recovery: node is started but has no relay circuit — re-dial the relay.
      // Registration alone won't help because registerOnce() requires circuit
      // addresses to already exist. We need to re-establish the relay connection
      // first, which triggers libp2p's circuit relay reservation.
      if (freshState.isStarted && freshState.circuitAddresses.isEmpty) {
        // Extract relay peer ID from the default address
        final relayPeerId = defaultRendezvousAddress.split('/p2p/').last;

        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_HEALTH_CHECK_RECOVERY_ATTEMPT',
          details: {'relayPeerId': relayPeerId},
        );

        try {
          await callP2PPeerDial(
            _bridge,
            peerId: relayPeerId,
            addresses: [defaultRendezvousAddress],
          );
        } catch (_) {
          // Relay still unreachable — will retry on next health check
        }

        // Re-poll status after dialing the relay
        final retryResponse = await callP2PNodeStatus(_bridge);
        final retryState = NodeState.fromJson(retryResponse);

        if (retryState.isStarted != _currentState.isStarted ||
            retryState.circuitAddresses.length !=
                _currentState.circuitAddresses.length ||
            retryState.connections.length != _currentState.connections.length) {
          _currentState = retryState;
          _stateController.add(_currentState);

          emitFlowEvent(
            layer: 'FL',
            event: 'P2P_HEALTH_CHECK_RECOVERY_RESULT',
            details: {
              'isStarted': retryState.isStarted,
              'circuitAddresses': retryState.circuitAddresses.length,
              'connections': retryState.connections.length,
            },
          );
        }
        return;
      }

      // Normal path: only emit if something meaningful changed
      if (freshState.isStarted != _currentState.isStarted ||
          freshState.circuitAddresses.length !=
              _currentState.circuitAddresses.length ||
          freshState.connections.length != _currentState.connections.length) {
        _currentState = freshState;
        _stateController.add(_currentState);

        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_HEALTH_CHECK_STATE_CHANGED',
          details: {
            'isStarted': freshState.isStarted,
            'circuitAddresses': freshState.circuitAddresses.length,
            'connections': freshState.connections.length,
          },
        );
      }
    } catch (e) {
      debugPrint('[P2PService] Health check failed: $e');

      // If the check itself fails, assume the node is down
      if (_currentState.isStarted) {
        _currentState = NodeState.stopped;
        _stateController.add(_currentState);

        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_HEALTH_CHECK_FAILED',
          details: {'error': e.toString()},
        );
      }
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
    logChatTransportIncoming(
      fromPeerId: message.from,
      toPeerId: message.to,
      contentLength: message.content.length,
      isIncoming: message.isIncoming,
      envelopeType: envelopeType,
    );
    debugPrint('[P2PService] Message received from ${message.from}');
    _messageController.add(message);
  }

  /// Handle peer connected event from bridge.
  void _handlePeerConnected(ConnectionState conn) {
    debugPrint('[P2PService] Peer connected: ${conn.peerId}');

    // Update current state with new connection
    final updatedConnections = List<ConnectionState>.from(
      _currentState.connections,
    )..add(conn);

    _currentState = _currentState.copyWith(connections: updatedConnections);
    _stateController.add(_currentState);
  }

  /// Handle peer disconnected event from bridge.
  void _handlePeerDisconnected(ConnectionState conn) {
    debugPrint('[P2PService] Peer disconnected: ${conn.peerId}');

    // Update current state by removing the connection
    final updatedConnections = _currentState.connections
        .where((c) => c.peerId != conn.peerId)
        .toList();

    _currentState = _currentState.copyWith(connections: updatedConnections);
    _stateController.add(_currentState);
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
  Future<List<Map<String, dynamic>>> retrieveInbox() async {
    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_SERVICE_INBOX_RETRIEVE_BEGIN',
      details: {},
    );

    try {
      final response = await callP2PInboxRetrieve(_bridge);
      if (response['ok'] == true) {
        final messages =
            (response['messages'] as List<dynamic>?)
                ?.cast<Map<String, dynamic>>() ??
            [];
        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_SERVICE_INBOX_RETRIEVE_SUCCESS',
          details: {
            'count': messages.length,
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
  void dispose() {
    _stopHealthCheck();
    _stateController.close();
    _messageController.close();

    // Clear event handlers
    _bridge.onMessageReceived = null;
    _bridge.onPeerConnected = null;
    _bridge.onPeerDisconnected = null;
  }
}
