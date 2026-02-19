import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/services/chat_message.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/bridge/js_bridge_client.dart';
import 'package:flutter_app/core/local_discovery/local_p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// P2P service backed by the Go native bridge.
///
/// Merges messages from two sources:
/// 1. Go bridge push events (via [onGoEvent])
/// 2. Local WiFi WebSocket server (optional [LocalP2PService])
class P2PServiceImpl implements P2PService {
  final JsBridge _bridge;
  final LocalP2PService? _localP2P;

  final _messageController = StreamController<ChatMessage>.broadcast();
  StreamSubscription? _localMessageSub;

  P2PServiceImpl({
    required JsBridge bridge,
    LocalP2PService? localP2PService,
  })  : _bridge = bridge,
        _localP2P = localP2PService {
    // Subscribe to local WiFi messages and merge into unified stream
    _localMessageSub = _localP2P?.localMessageStream.listen((localMsg) {
      final msg = ChatMessage.fromLocal(localMsg);
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_LOCAL_MESSAGE_RECEIVED',
        details: {'from': msg.from, 'to': msg.to},
      );
      _messageController.add(msg);
    });
  }

  /// Called by the platform event channel when Go pushes an event.
  /// This is the entry point for Go → Flutter push events.
  void onGoEvent(String jsonString) {
    try {
      final event = jsonDecode(jsonString) as Map<String, dynamic>;
      final eventName = event['event'] as String?;
      final data = event['data'] as Map<String, dynamic>?;

      if (eventName == 'message:received' && data != null) {
        final msg = ChatMessage.fromEventData(data);
        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_GO_MESSAGE_RECEIVED',
          details: {'from': msg.from, 'to': msg.to},
        );
        _messageController.add(msg);
      }
      // peer:connected and peer:disconnected are logged but not yet surfaced
      if (eventName == 'peer:connected') {
        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_PEER_CONNECTED',
          details: data ?? {},
        );
      }
      if (eventName == 'peer:disconnected') {
        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_PEER_DISCONNECTED',
          details: data ?? {},
        );
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_GO_EVENT_PARSE_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  @override
  Stream<ChatMessage> get messageStream => _messageController.stream;

  @override
  Future<void> startNode({
    required String privateKeyHex,
    String? namespace,
    bool autoRegister = true,
  }) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_START_NODE_REQUEST',
      details: {'autoRegister': autoRegister},
    );

    final request = jsonEncode({
      'cmd': 'node.start',
      'payload': {
        'privateKeyHex': privateKeyHex,
        if (namespace != null) 'namespace': namespace,
        'autoRegister': autoRegister,
        'listenPort': 0,
      },
    });

    final responseJson = await _bridge.send(request);
    final response = jsonDecode(responseJson) as Map<String, dynamic>;

    if (response['ok'] != true) {
      throw Exception(
          'StartNode failed: ${response['errorCode']} — ${response['errorMessage']}');
    }

    // Start local P2P if available
    final peerId = response['peerId'] as String?;
    final localP2P = _localP2P;
    if (peerId != null && localP2P != null) {
      await localP2P.start(peerId);
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_START_NODE_SUCCESS',
      details: {'peerId': peerId},
    );
  }

  @override
  Future<void> stopNode() async {
    await _localP2P?.stop();

    final request = jsonEncode({
      'cmd': 'node.stop',
      'payload': {},
    });

    final responseJson = await _bridge.send(request);
    final response = jsonDecode(responseJson) as Map<String, dynamic>;

    if (response['ok'] != true) {
      throw Exception(
          'StopNode failed: ${response['errorCode']} — ${response['errorMessage']}');
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_STOP_NODE_SUCCESS',
      details: {},
    );
  }

  @override
  Future<Map<String, dynamic>> nodeStatus() async {
    final request = jsonEncode({
      'cmd': 'node.status',
      'payload': {},
    });

    final responseJson = await _bridge.send(request);
    return jsonDecode(responseJson) as Map<String, dynamic>;
  }

  @override
  Future<String> sendMessage(String peerId, String message) async {
    final request = jsonEncode({
      'cmd': 'node.sendMessage',
      'payload': {
        'peerId': peerId,
        'message': message,
      },
    });

    final responseJson = await _bridge.send(request);
    final response = jsonDecode(responseJson) as Map<String, dynamic>;

    if (response['ok'] != true) {
      throw Exception(
          'SendMessage failed: ${response['errorCode']} — ${response['errorMessage']}');
    }

    return response['reply'] as String? ?? '';
  }

  @override
  Future<void> dialPeer(String peerId, {List<String>? addresses}) async {
    final request = jsonEncode({
      'cmd': 'node.dialPeer',
      'payload': {
        'peerId': peerId,
        if (addresses != null) 'addresses': addresses,
      },
    });

    final responseJson = await _bridge.send(request);
    final response = jsonDecode(responseJson) as Map<String, dynamic>;

    if (response['ok'] != true) {
      throw Exception(
          'DialPeer failed: ${response['errorCode']} — ${response['errorMessage']}');
    }
  }

  @override
  Future<void> disconnectPeer(String peerId) async {
    final request = jsonEncode({
      'cmd': 'node.disconnectPeer',
      'payload': {'peerId': peerId},
    });

    final responseJson = await _bridge.send(request);
    final response = jsonDecode(responseJson) as Map<String, dynamic>;

    if (response['ok'] != true) {
      throw Exception(
          'DisconnectPeer failed: ${response['errorCode']} — ${response['errorMessage']}');
    }
  }

  @override
  Future<List<Map<String, dynamic>>> discoverPeers({String? namespace}) async {
    final request = jsonEncode({
      'cmd': 'node.rendezvousDiscover',
      'payload': {
        if (namespace != null) 'namespace': namespace,
      },
    });

    final responseJson = await _bridge.send(request);
    final response = jsonDecode(responseJson) as Map<String, dynamic>;

    if (response['ok'] != true) {
      throw Exception(
          'DiscoverPeers failed: ${response['errorCode']} — ${response['errorMessage']}');
    }

    final peers = response['peers'] as List<dynamic>? ?? [];
    return peers.cast<Map<String, dynamic>>();
  }

  @override
  Future<void> rendezvousRegister({String? namespace}) async {
    final request = jsonEncode({
      'cmd': 'node.rendezvousRegister',
      'payload': {
        if (namespace != null) 'namespace': namespace,
      },
    });

    final responseJson = await _bridge.send(request);
    final response = jsonDecode(responseJson) as Map<String, dynamic>;

    if (response['ok'] != true) {
      throw Exception(
          'RendezvousRegister failed: ${response['errorCode']} — ${response['errorMessage']}');
    }
  }

  @override
  Future<void> inboxStore(String toPeerId, String message) async {
    final request = jsonEncode({
      'cmd': 'node.inboxStore',
      'payload': {
        'toPeerId': toPeerId,
        'message': message,
      },
    });

    final responseJson = await _bridge.send(request);
    final response = jsonDecode(responseJson) as Map<String, dynamic>;

    if (response['ok'] != true) {
      throw Exception(
          'InboxStore failed: ${response['errorCode']} — ${response['errorMessage']}');
    }
  }

  @override
  Future<List<Map<String, dynamic>>> inboxRetrieve() async {
    final request = jsonEncode({
      'cmd': 'node.inboxRetrieve',
      'payload': {},
    });

    final responseJson = await _bridge.send(request);
    final response = jsonDecode(responseJson) as Map<String, dynamic>;

    if (response['ok'] != true) {
      throw Exception(
          'InboxRetrieve failed: ${response['errorCode']} — ${response['errorMessage']}');
    }

    final messages = response['messages'] as List<dynamic>? ?? [];
    return messages.cast<Map<String, dynamic>>();
  }

  @override
  Future<void> inboxRegisterToken(String token, String platform) async {
    final request = jsonEncode({
      'cmd': 'node.inboxRegisterToken',
      'payload': {
        'token': token,
        'platform': platform,
      },
    });

    final responseJson = await _bridge.send(request);
    final response = jsonDecode(responseJson) as Map<String, dynamic>;

    if (response['ok'] != true) {
      throw Exception(
          'InboxRegisterToken failed: ${response['errorCode']} — ${response['errorMessage']}');
    }
  }

  @override
  void dispose() {
    _localMessageSub?.cancel();
    _localP2P?.dispose();
    _messageController.close();
  }
}
