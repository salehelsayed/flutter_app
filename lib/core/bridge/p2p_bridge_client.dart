import 'dart:convert';
import 'js_bridge_client.dart';
import '../utils/flow_event_emitter.dart';

/// Default rendezvous server address.
const String defaultRendezvousAddress =
    '/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g';

/// Calls the JS bridge to start the P2P node.
///
/// Parameters:
///   - [bridge]: The JsBridge instance to use for communication
///   - [privateKeyHex]: The Ed25519 private key in HEX format
///   - [relayAddresses]: Optional list of relay server multiaddrs
///   - [autoRegister]: Whether to auto-register on rendezvous (default true)
///   - [namespace]: Optional namespace for rendezvous registration
///
/// Returns a map with node state on success:
/// `{ "ok": true, "peerId": "...", "isStarted": true, ... }`
Future<Map<String, dynamic>> callP2PNodeStart(
  JsBridge bridge, {
  required String privateKeyHex,
  List<String>? relayAddresses,
  bool autoRegister = true,
  String? namespace,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_NODE_START_REQUEST',
    details: {'autoRegister': autoRegister},
  );

  final request = {
    'cmd': 'node:start',
    'payload': {
      'privateKeyHex': privateKeyHex,
      'relayAddresses': relayAddresses ?? [defaultRendezvousAddress],
      'autoRegister': autoRegister,
      if (namespace != null) 'namespace': namespace,
    },
  };

  final responseJson = await bridge.send(jsonEncode(request));
  final response = jsonDecode(responseJson) as Map<String, dynamic>;

  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_NODE_START_RESPONSE',
    details: {'ok': response['ok']},
  );

  return response;
}

/// Calls the JS bridge to stop the P2P node.
///
/// Returns: `{ "ok": true, "stopped": true }` on success.
Future<Map<String, dynamic>> callP2PNodeStop(JsBridge bridge) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_NODE_STOP_REQUEST',
    details: {},
  );

  final request = {
    'cmd': 'node:stop',
    'payload': <String, dynamic>{},
  };

  final responseJson = await bridge.send(jsonEncode(request));
  final response = jsonDecode(responseJson) as Map<String, dynamic>;

  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_NODE_STOP_RESPONSE',
    details: {'ok': response['ok']},
  );

  return response;
}

/// Calls the JS bridge to get the current P2P node status.
///
/// Returns: Node state including peerId, isStarted, connections, etc.
Future<Map<String, dynamic>> callP2PNodeStatus(JsBridge bridge) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_NODE_STATUS_REQUEST',
    details: {},
  );

  final request = {
    'cmd': 'node:status',
    'payload': <String, dynamic>{},
  };

  final responseJson = await bridge.send(jsonEncode(request));
  final response = jsonDecode(responseJson) as Map<String, dynamic>;

  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_NODE_STATUS_RESPONSE',
    details: {'ok': response['ok'], 'isStarted': response['isStarted']},
  );

  return response;
}

/// Calls the JS bridge to register on a rendezvous namespace.
///
/// Parameters:
///   - [bridge]: The JsBridge instance
///   - [namespace]: Optional namespace (defaults to mknoon:chat:<peerId>)
///   - [serverAddresses]: Optional list of rendezvous server addresses
///
/// Returns: `{ "ok": true, "registered": true, "namespace": "..." }`
Future<Map<String, dynamic>> callP2PRendezvousRegister(
  JsBridge bridge, {
  String? namespace,
  List<String>? serverAddresses,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_RENDEZVOUS_REGISTER_REQUEST',
    details: {'namespace': namespace},
  );

  final request = {
    'cmd': 'rendezvous:register',
    'payload': {
      if (namespace != null) 'namespace': namespace,
      if (serverAddresses != null) 'serverAddresses': serverAddresses,
    },
  };

  final responseJson = await bridge.send(jsonEncode(request));
  final response = jsonDecode(responseJson) as Map<String, dynamic>;

  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_RENDEZVOUS_REGISTER_RESPONSE',
    details: {'ok': response['ok']},
  );

  return response;
}

/// Calls the JS bridge to discover peers on a rendezvous namespace.
///
/// Parameters:
///   - [bridge]: The JsBridge instance
///   - [peerId]: Optional specific peer ID to discover
///   - [namespace]: Optional namespace (defaults to mknoon:chat:<peerId> if peerId provided)
///   - [serverAddresses]: Optional list of rendezvous server addresses
///   - [timeoutMs]: Optional discovery timeout in milliseconds
///
/// Returns: `{ "ok": true, "peers": [{ "id": "...", "addresses": [...] }] }`
Future<Map<String, dynamic>> callP2PRendezvousDiscover(
  JsBridge bridge, {
  String? peerId,
  String? namespace,
  List<String>? serverAddresses,
  int? timeoutMs,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_RENDEZVOUS_DISCOVER_REQUEST',
    details: {'peerId': peerId, 'namespace': namespace},
  );

  final request = {
    'cmd': 'rendezvous:discover',
    'payload': {
      if (peerId != null) 'peerId': peerId,
      if (namespace != null) 'namespace': namespace,
      if (serverAddresses != null) 'serverAddresses': serverAddresses,
      if (timeoutMs != null) 'timeoutMs': timeoutMs,
    },
  };

  final responseJson = await bridge.send(jsonEncode(request));
  final response = jsonDecode(responseJson) as Map<String, dynamic>;

  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_RENDEZVOUS_DISCOVER_RESPONSE',
    details: {
      'ok': response['ok'],
      'peerCount': (response['peers'] as List?)?.length ?? 0,
    },
  );

  return response;
}

/// Calls the JS bridge to dial (connect to) a peer.
///
/// Parameters:
///   - [bridge]: The JsBridge instance
///   - [peerId]: The peer ID to dial
///   - [addresses]: Optional list of multiaddrs (discovers if not provided)
///   - [timeoutMs]: Optional dial timeout in milliseconds
///
/// Returns: `{ "ok": true, "connected": true, "peerId": "..." }`
Future<Map<String, dynamic>> callP2PPeerDial(
  JsBridge bridge, {
  required String peerId,
  List<String>? addresses,
  int? timeoutMs,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_PEER_DIAL_REQUEST',
    details: {'peerId': peerId},
  );

  final request = {
    'cmd': 'peer:dial',
    'payload': {
      'peerId': peerId,
      if (addresses != null) 'addresses': addresses,
      if (timeoutMs != null) 'timeoutMs': timeoutMs,
    },
  };

  final responseJson = await bridge.send(jsonEncode(request));
  final response = jsonDecode(responseJson) as Map<String, dynamic>;

  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_PEER_DIAL_RESPONSE',
    details: {'ok': response['ok'], 'connected': response['connected']},
  );

  return response;
}

/// Calls the JS bridge to disconnect from a peer.
///
/// Parameters:
///   - [bridge]: The JsBridge instance
///   - [peerId]: The peer ID to disconnect from
///
/// Returns: `{ "ok": true, "disconnected": true, "peerId": "..." }`
Future<Map<String, dynamic>> callP2PPeerDisconnect(
  JsBridge bridge, {
  required String peerId,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_PEER_DISCONNECT_REQUEST',
    details: {'peerId': peerId},
  );

  final request = {
    'cmd': 'peer:disconnect',
    'payload': {
      'peerId': peerId,
    },
  };

  final responseJson = await bridge.send(jsonEncode(request));
  final response = jsonDecode(responseJson) as Map<String, dynamic>;

  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_PEER_DISCONNECT_RESPONSE',
    details: {'ok': response['ok']},
  );

  return response;
}

/// Calls the JS bridge to send a message to a peer.
///
/// Parameters:
///   - [bridge]: The JsBridge instance
///   - [peerId]: The peer ID to send the message to
///   - [message]: The message content
///   - [timeoutMs]: Optional send timeout in milliseconds
///
/// Returns: `{ "ok": true, "sent": true, "reply": "..." }`
Future<Map<String, dynamic>> callP2PMessageSend(
  JsBridge bridge, {
  required String peerId,
  required String message,
  int? timeoutMs,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_MESSAGE_SEND_REQUEST',
    details: {'peerId': peerId, 'messageLength': message.length},
  );

  final request = {
    'cmd': 'message:send',
    'payload': {
      'peerId': peerId,
      'message': message,
      if (timeoutMs != null) 'timeoutMs': timeoutMs,
    },
  };

  final responseJson = await bridge.send(jsonEncode(request));
  final response = jsonDecode(responseJson) as Map<String, dynamic>;

  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_MESSAGE_SEND_RESPONSE',
    details: {'ok': response['ok'], 'sent': response['sent']},
  );

  return response;
}
