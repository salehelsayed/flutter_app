import 'dart:convert';
import 'bridge.dart';
import '../utils/flow_event_emitter.dart';

/// Default rendezvous server address (WSS).
const String defaultRendezvousAddress =
    '/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g';

/// Default QUIC relay address (faster than WSS on most networks).
const String defaultQUICRelayAddress =
    '/dns4/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g';

/// Calls the bridge to start the P2P node.
///
/// Parameters:
///   - [bridge]: The Bridge instance to use for communication
///   - [privateKeyHex]: The Ed25519 private key in HEX format
///   - [relayAddresses]: Optional list of relay server multiaddrs
///   - [autoRegister]: Whether to auto-register on rendezvous (default true)
///   - [namespace]: Optional namespace for rendezvous registration
///
/// Returns a map with node state on success:
/// `{ "ok": true, "peerId": "...", "isStarted": true, ... }`
Future<Map<String, dynamic>> callP2PNodeStart(
  Bridge bridge, {
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

/// Calls the bridge to perform a full Stop() + Start() restart of the
/// libp2p node to recover circuit addresses. This is the correct recovery
/// path after the app returns from background and the relay connection has
/// dropped.
///
/// A full restart is needed because go-libp2p's AutoRelay does not
/// reliably re-reserve after disconnection.
///
/// Returns: `{ "ok": true }` on success.
Future<Map<String, dynamic>> callP2PRelayReconnect(Bridge bridge) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_RELAY_RECONNECT_REQUEST',
    details: {},
  );

  final request = {
    'cmd': 'relay:reconnect',
    'payload': <String, dynamic>{},
  };

  final responseJson = await bridge.send(jsonEncode(request));
  final response = jsonDecode(responseJson) as Map<String, dynamic>;

  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_RELAY_RECONNECT_RESPONSE',
    details: {'ok': response['ok']},
  );

  return response;
}

/// Calls the bridge to probe a peer via relay circuit.
///
/// This is a fast check (~100ms for offline, ~500ms for online) that
/// determines if a peer is reachable through the relay without a full
/// discover/dial cycle.
///
/// Parameters:
///   - [bridge]: The Bridge instance
///   - [peerId]: The peer ID to probe
///
/// Returns:
///   - `{ "ok": true }` if the peer is online (relay circuit established)
///   - `{ "ok": false, "errorCode": "NO_RESERVATION" }` if peer is offline
///   - `{ "ok": false, "errorCode": "RELAY_PROBE_ERROR" }` on other errors
Future<Map<String, dynamic>> callP2PRelayProbe(
  Bridge bridge, {
  required String peerId,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_RELAY_PROBE_REQUEST',
    details: {'peerId': peerId},
  );

  final request = {
    'cmd': 'relay:probe',
    'payload': {
      'peerId': peerId,
    },
  };

  final responseJson = await bridge.send(jsonEncode(request));
  final response = jsonDecode(responseJson) as Map<String, dynamic>;

  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_RELAY_PROBE_RESPONSE',
    details: {'ok': response['ok'], 'errorCode': response['errorCode']},
  );

  return response;
}

/// Calls the bridge to stop the P2P node.
///
/// Returns: `{ "ok": true, "stopped": true }` on success.
Future<Map<String, dynamic>> callP2PNodeStop(Bridge bridge) async {
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

/// Calls the bridge to get the current P2P node status.
///
/// Returns: Node state including peerId, isStarted, connections, etc.
Future<Map<String, dynamic>> callP2PNodeStatus(Bridge bridge) async {
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

/// Calls the bridge to register on a rendezvous namespace.
///
/// Parameters:
///   - [bridge]: The Bridge instance
///   - [namespace]: Optional namespace (defaults to mknoon:chat:<peerId>)
///   - [serverAddresses]: Optional list of rendezvous server addresses
///
/// Returns: `{ "ok": true, "registered": true, "namespace": "..." }`
Future<Map<String, dynamic>> callP2PRendezvousRegister(
  Bridge bridge, {
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

/// Calls the bridge to discover peers on a rendezvous namespace.
///
/// Parameters:
///   - [bridge]: The Bridge instance
///   - [peerId]: Optional specific peer ID to discover
///   - [namespace]: Optional namespace (defaults to mknoon:chat:<peerId> if peerId provided)
///   - [serverAddresses]: Optional list of rendezvous server addresses
///   - [timeoutMs]: Optional discovery timeout in milliseconds
///
/// Returns: `{ "ok": true, "peers": [{ "id": "...", "addresses": [...] }] }`
Future<Map<String, dynamic>> callP2PRendezvousDiscover(
  Bridge bridge, {
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

/// Calls the bridge to dial (connect to) a peer.
///
/// Parameters:
///   - [bridge]: The Bridge instance
///   - [peerId]: The peer ID to dial
///   - [addresses]: Optional list of multiaddrs (discovers if not provided)
///   - [timeoutMs]: Optional dial timeout in milliseconds
///
/// Returns: `{ "ok": true, "connected": true, "peerId": "..." }`
Future<Map<String, dynamic>> callP2PPeerDial(
  Bridge bridge, {
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

/// Calls the bridge to disconnect from a peer.
///
/// Parameters:
///   - [bridge]: The Bridge instance
///   - [peerId]: The peer ID to disconnect from
///
/// Returns: `{ "ok": true, "disconnected": true, "peerId": "..." }`
Future<Map<String, dynamic>> callP2PPeerDisconnect(
  Bridge bridge, {
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

/// Calls the bridge to store a message in the offline inbox.
///
/// Parameters:
///   - [bridge]: The Bridge instance
///   - [toPeerId]: The target peer ID
///   - [message]: The message content
///
/// Returns: `{ "ok": true, "stored": true }` (stub — JS not yet implemented)
Future<Map<String, dynamic>> callP2PInboxStore(
  Bridge bridge, {
  required String toPeerId,
  required String message,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_INBOX_STORE_REQUEST',
    details: {'toPeerId': toPeerId},
  );

  final request = {
    'cmd': 'inbox:store',
    'payload': {
      'toPeerId': toPeerId,
      'message': message,
    },
  };

  final responseJson = await bridge.send(jsonEncode(request));
  final response = jsonDecode(responseJson) as Map<String, dynamic>;

  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_INBOX_STORE_RESPONSE',
    details: {'ok': response['ok']},
  );

  return response;
}

/// Calls the bridge to register an FCM push token with the relay.
///
/// Parameters:
///   - [bridge]: The Bridge instance
///   - [token]: The FCM device token
///   - [platform]: The platform ('ios' or 'android')
///
/// Returns: `{ "ok": true, "registered": true }`
Future<Map<String, dynamic>> callP2PInboxRegisterToken(
  Bridge bridge, {
  required String token,
  required String platform,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_INBOX_REGISTER_TOKEN_REQUEST',
    details: {'platform': platform},
  );

  final request = {
    'cmd': 'inbox:register_token',
    'payload': {
      'token': token,
      'platform': platform,
    },
  };

  final responseJson = await bridge.send(jsonEncode(request));
  final response = jsonDecode(responseJson) as Map<String, dynamic>;

  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_INBOX_REGISTER_TOKEN_RESPONSE',
    details: {'ok': response['ok']},
  );

  return response;
}

/// Calls the bridge to retrieve messages from the offline inbox.
///
/// Returns: `{ "ok": true, "messages": [...] }` (stub — JS not yet implemented)
Future<Map<String, dynamic>> callP2PInboxRetrieve(Bridge bridge) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_INBOX_RETRIEVE_REQUEST',
    details: {},
  );

  final request = {
    'cmd': 'inbox:retrieve',
    'payload': <String, dynamic>{},
  };

  final responseJson = await bridge.send(jsonEncode(request));
  final response = jsonDecode(responseJson) as Map<String, dynamic>;

  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_INBOX_RETRIEVE_RESPONSE',
    details: {'ok': response['ok']},
  );

  return response;
}

// --- Media ---

/// Calls the bridge to upload a media blob to the relay.
///
/// Parameters:
///   - [bridge]: The Bridge instance
///   - [id]: Unique blob ID (UUID)
///   - [toPeerId]: The recipient peer ID
///   - [mime]: MIME type of the file
///   - [filePath]: Absolute path to the local file
///
/// Returns: `{ "ok": true, "id": "..." }`
Future<Map<String, dynamic>> callP2PMediaUpload(
  Bridge bridge, {
  required String id,
  required String toPeerId,
  required String mime,
  required String filePath,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_MEDIA_UPLOAD_REQUEST',
    details: {'id': id, 'toPeerId': toPeerId, 'mime': mime},
  );

  final request = {
    'cmd': 'media:upload',
    'payload': {
      'id': id,
      'to': toPeerId,
      'mime': mime,
      'filePath': filePath,
    },
  };

  final responseJson = await bridge
      .send(jsonEncode(request))
      .timeout(const Duration(minutes: 5));
  final response = jsonDecode(responseJson) as Map<String, dynamic>;

  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_MEDIA_UPLOAD_RESPONSE',
    details: {'ok': response['ok'], 'id': response['id']},
  );

  return response;
}

/// Calls the bridge to download a media blob from the relay.
///
/// Parameters:
///   - [bridge]: The Bridge instance
///   - [id]: The blob ID to download
///   - [outputPath]: Absolute path where the file will be written
///
/// Returns: `{ "ok": true, "id": "...", "mime": "...", "size": N }`
Future<Map<String, dynamic>> callP2PMediaDownload(
  Bridge bridge, {
  required String id,
  required String outputPath,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_MEDIA_DOWNLOAD_REQUEST',
    details: {'id': id},
  );

  final request = {
    'cmd': 'media:download',
    'payload': {
      'id': id,
      'outputPath': outputPath,
    },
  };

  final responseJson = await bridge
      .send(jsonEncode(request))
      .timeout(const Duration(minutes: 5));
  final response = jsonDecode(responseJson) as Map<String, dynamic>;

  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_MEDIA_DOWNLOAD_RESPONSE',
    details: {'ok': response['ok'], 'id': response['id']},
  );

  return response;
}

/// Calls the bridge to delete a media blob from the relay.
///
/// Parameters:
///   - [bridge]: The Bridge instance
///   - [id]: The blob ID to delete
///
/// Returns: `{ "ok": true }`
Future<Map<String, dynamic>> callP2PMediaDelete(
  Bridge bridge, {
  required String id,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_MEDIA_DELETE_REQUEST',
    details: {'id': id},
  );

  final request = {
    'cmd': 'media:delete',
    'payload': {
      'id': id,
    },
  };

  final responseJson = await bridge
      .send(jsonEncode(request))
      .timeout(const Duration(seconds: 15));
  final response = jsonDecode(responseJson) as Map<String, dynamic>;

  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_MEDIA_DELETE_RESPONSE',
    details: {'ok': response['ok']},
  );

  return response;
}

/// Calls the bridge to list media blobs available on the relay.
///
/// Returns: `{ "ok": true, "blobs": [...] }`
Future<Map<String, dynamic>> callP2PMediaList(Bridge bridge) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_MEDIA_LIST_REQUEST',
    details: {},
  );

  final request = {
    'cmd': 'media:list',
    'payload': <String, dynamic>{},
  };

  final responseJson = await bridge
      .send(jsonEncode(request))
      .timeout(const Duration(seconds: 15));
  final response = jsonDecode(responseJson) as Map<String, dynamic>;

  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_MEDIA_LIST_RESPONSE',
    details: {'ok': response['ok']},
  );

  return response;
}

// --- Profile ---

/// Calls the bridge to upload the user's profile picture to the relay.
///
/// Parameters:
///   - [bridge]: The Bridge instance
///   - [mime]: MIME type of the image (e.g. "image/jpeg")
///   - [filePath]: Absolute path to the local file
///
/// Returns: `{ "ok": true }`
Future<Map<String, dynamic>> callP2PProfileUpload(
  Bridge bridge, {
  required String mime,
  required String filePath,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_PROFILE_UPLOAD_REQUEST',
    details: {'mime': mime},
  );

  final request = {
    'cmd': 'profile:upload',
    'payload': {
      'mime': mime,
      'filePath': filePath,
    },
  };

  final responseJson = await bridge
      .send(jsonEncode(request))
      .timeout(const Duration(minutes: 5));
  final response = jsonDecode(responseJson) as Map<String, dynamic>;

  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_PROFILE_UPLOAD_RESPONSE',
    details: {'ok': response['ok']},
  );

  return response;
}

/// Calls the bridge to download a peer's profile picture from the relay.
///
/// Parameters:
///   - [bridge]: The Bridge instance
///   - [ownerPeerId]: The peer whose profile to download
///   - [outputPath]: Absolute path where the file will be written
///
/// Returns: `{ "ok": true, "mime": "...", "size": N }`
Future<Map<String, dynamic>> callP2PProfileDownload(
  Bridge bridge, {
  required String ownerPeerId,
  required String outputPath,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_PROFILE_DOWNLOAD_REQUEST',
    details: {'ownerPeerId': ownerPeerId},
  );

  final request = {
    'cmd': 'profile:download',
    'payload': {
      'ownerPeerId': ownerPeerId,
      'outputPath': outputPath,
    },
  };

  final responseJson = await bridge
      .send(jsonEncode(request))
      .timeout(const Duration(minutes: 5));
  final response = jsonDecode(responseJson) as Map<String, dynamic>;

  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_PROFILE_DOWNLOAD_RESPONSE',
    details: {'ok': response['ok']},
  );

  return response;
}

/// Calls the bridge to send a message to a peer.
///
/// Parameters:
///   - [bridge]: The Bridge instance
///   - [peerId]: The peer ID to send the message to
///   - [message]: The message content
///   - [timeoutMs]: Optional send timeout in milliseconds
///
/// Returns: `{ "ok": true, "sent": true, "reply": "..." }`
Future<Map<String, dynamic>> callP2PMessageSend(
  Bridge bridge, {
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
