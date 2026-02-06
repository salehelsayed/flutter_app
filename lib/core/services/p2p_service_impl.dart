import 'dart:async';
import 'package:flutter/foundation.dart';
import 'p2p_service.dart';
import '../bridge/webview_js_bridge.dart';
import '../bridge/p2p_bridge_client.dart';
import '../utils/key_conversion.dart';
import '../utils/flow_event_emitter.dart';
import '../../features/p2p/domain/models/node_state.dart';
import '../../features/p2p/domain/models/chat_message.dart';
import '../../features/p2p/domain/models/discovered_peer.dart';
import '../../features/p2p/domain/models/connection_state.dart';

/// Implementation of P2PService using WebViewJsBridge.
class P2PServiceImpl implements P2PService {
  final WebViewJsBridge _bridge;

  final _stateController = StreamController<NodeState>.broadcast();
  final _messageController = StreamController<ChatMessage>.broadcast();

  NodeState _currentState = NodeState.stopped;

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

  @override
  Future<bool> stopNode() async {
    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_SERVICE_STOP_NODE_BEGIN',
      details: {},
    );

    try {
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
  Future<DiscoveredPeer?> discoverPeer(String peerId) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_SERVICE_DISCOVER_PEER_BEGIN',
      details: {'peerId': peerId},
    );

    try {
      final response = await callP2PRendezvousDiscover(
        _bridge,
        peerId: peerId,
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

  /// Handle incoming chat message from bridge event.
  void _handleMessageReceived(ChatMessage message) {
    debugPrint('[P2PService] Message received from ${message.from}');
    _messageController.add(message);
  }

  /// Handle peer connected event from bridge.
  void _handlePeerConnected(ConnectionState conn) {
    debugPrint('[P2PService] Peer connected: ${conn.peerId}');

    // Update current state with new connection
    final updatedConnections = List<ConnectionState>.from(_currentState.connections)
      ..add(conn);

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
  void dispose() {
    _stateController.close();
    _messageController.close();

    // Clear event handlers
    _bridge.onMessageReceived = null;
    _bridge.onPeerConnected = null;
    _bridge.onPeerDisconnected = null;
  }
}
