import 'dart:async';
import 'dart:convert';
import 'bridge.dart';
import '../local_discovery/lan_address_classifier.dart';
import '../utils/flow_event_emitter.dart';

/// Extra time given to the Dart bridge boundary beyond a native operation's
/// own deadline. This margin detects a stalled MethodChannel/gomobile await
/// without racing the native timeout itself.
const Duration p2pBridgeWatchdogMargin = Duration(milliseconds: 500);

/// Default rendezvous server address (WSS).
/// Uses /dns/ (not /dns4/) to resolve both A and AAAA records for dual-stack.
const String defaultRendezvousAddress =
    '/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g';

/// Default QUIC relay address (faster than WSS on most networks).
/// Uses /dns/ (not /dns4/) to resolve both A and AAAA records for dual-stack.
const String defaultQUICRelayAddress =
    '/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g';

List<String> defaultRelayAddresses({String? relayAddressesCsv}) {
  final csv =
      relayAddressesCsv ??
      const String.fromEnvironment('MKNOON_RELAY_ADDRESSES', defaultValue: '');
  final configured = csv
      .split(',')
      .map((entry) => entry.trim())
      .where((entry) => entry.isNotEmpty)
      .toList(growable: false);
  if (configured.isNotEmpty) {
    return configured;
  }
  return const [defaultRendezvousAddress, defaultQUICRelayAddress];
}

Map<String, bool> defaultResilienceFeatureFlags() {
  return {
    'enableSharedRelayBackend': const bool.fromEnvironment(
      'MKNOON_ENABLE_SHARED_RELAY_BACKEND',
      defaultValue: true,
    ),
    'enableMultiRelayRouting': const bool.fromEnvironment(
      'MKNOON_ENABLE_MULTI_RELAY_ROUTING',
      defaultValue: true,
    ),
    'enableReservationAwareHealth': const bool.fromEnvironment(
      'MKNOON_ENABLE_RESERVATION_AWARE_HEALTH',
      defaultValue: true,
    ),
    'enableInPlaceRelayRecovery': const bool.fromEnvironment(
      'MKNOON_ENABLE_IN_PLACE_RELAY_RECOVERY',
      defaultValue: true,
    ),
    'enableResumeGroupRecovery': const bool.fromEnvironment(
      'MKNOON_ENABLE_RESUME_GROUP_RECOVERY',
      defaultValue: true,
    ),
    'enableDeferredDirectAck': const bool.fromEnvironment(
      'MKNOON_ENABLE_DEFERRED_DIRECT_ACK',
      defaultValue: true,
    ),
    // FDC-11: gates the Go-side bonsoir-fed libp2p LAN-direct dial
    // (HandleLANPeerFound: peerstore-seed + host.Connect + relay->direct upgrade).
    // CV-09: defaults ON now that the two-phone same-WiFi D1 gate (CV-08) closed
    // (commit 121f0551 — real Pixel 6 <-> iPhone 11 reached
    // MSG_RECEIVED_TRANSPORT:"direct" both directions). This Dart default is
    // LOAD-BEARING: the full flag map is always sent to node:start and Go applies
    // it wholesale (config.go EffectiveFlags returns the map in its entirety when
    // non-nil), so THIS value — not the Go feature_flags.go fallback — is the
    // production default. The dart-define stays an explicit override knob
    // (=false forces-off for A/B / rollback).
    'enableLibp2pLANDial': const bool.fromEnvironment(
      'MKNOON_ENABLE_LIBP2P_LAN_DIAL',
      defaultValue: true,
    ),
    // FDC-12: gates the Go-side opportunistic DCUtR relay->direct upgrade
    // (ForceReachabilityPublic + active hole punch). Defaults OFF until the
    // DCUtR device campaign is GREEN; flip on for the device-proof via
    // --dart-define=MKNOON_ENABLE_DCUTR_UPGRADE=true.
    'enableDcutrUpgrade': const bool.fromEnvironment(
      'MKNOON_ENABLE_DCUTR_UPGRADE',
      defaultValue: false,
    ),
    // FDC-15: gates the Go-side peer-direct LAN media byte stream
    // (MediaLANProtocol handler registration). Defaults OFF until the two-phone
    // media device gate (D1) is GREEN; flip on for the device-proof via
    // --dart-define=MKNOON_ENABLE_LIBP2P_LAN_MEDIA=true. The Dart send leg reads
    // the same flag back from currentState.featureFlags, so one value gates both
    // halves end-to-end.
    'enableLibp2pLANMedia': const bool.fromEnvironment(
      'MKNOON_ENABLE_LIBP2P_LAN_MEDIA',
      defaultValue: false,
    ),
  };
}

/// Calls the bridge to start the P2P node.
///
/// Parameters:
///   - [bridge]: The Bridge instance to use for communication
///   - [privateKeyHex]: The Ed25519 private key in HEX format
///   - [relayAddresses]: Optional list of relay server multiaddrs
///   - [autoRegister]: Whether to auto-register on rendezvous (default true)
///   - [namespace]: Optional namespace for rendezvous registration
///   - [keyRotationGracePeriod]: Optional native key-rotation grace override
///
/// Returns a map with node state on success:
/// `{ "ok": true, "peerId": "...", "isStarted": true, ... }`
Future<Map<String, dynamic>> callP2PNodeStart(
  Bridge bridge, {
  required String privateKeyHex,
  List<String>? relayAddresses,
  bool autoRegister = true,
  String? namespace,
  Map<String, bool>? featureFlags,
  Duration? keyRotationGracePeriod,
  // FDC-S1 (observation-only): Dart process-start wall-clock epoch, threaded so
  // Go can compute sinceProcessStartMs on its cold-start timing emits. Optional;
  // omitted by callers that don't measure cold start (Go treats absent as
  // "not provided" and reports -1 — never feeds timeout logic).
  int? processStartEpochMs,
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
      'relayAddresses': relayAddresses ?? defaultRelayAddresses(),
      'autoRegister': autoRegister,
      'featureFlags': featureFlags ?? defaultResilienceFeatureFlags(),
      'namespace': ?namespace,
      'keyRotationGracePeriodMs': ?keyRotationGracePeriod?.inMilliseconds,
      'processStartEpochMs': ?processStartEpochMs,
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
  emitFlowEvent(layer: 'FL', event: 'P2P_RELAY_RECONNECT_REQUEST', details: {});

  final request = {'cmd': 'relay:reconnect', 'payload': <String, dynamic>{}};

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
    'payload': {'peerId': peerId},
  };

  final responseJson = await bridge
      .send(jsonEncode(request))
      .timeout(const Duration(seconds: 5));
  final response = jsonDecode(responseJson) as Map<String, dynamic>;

  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_RELAY_PROBE_RESPONSE',
    details: {'ok': response['ok'], 'errorCode': response['errorCode']},
  );

  return response;
}

/// Calls the bridge to look up a peer's coarse relay presence via the additive
/// `presence_get` action (FDC-08) — WITHOUT dialing a circuit (unlike
/// [callP2PRelayProbe]). It normalizes the reply to a coarse presence string and
/// surfaces `ageMs`, degrading anything that is not a clean answer (an old
/// relay's "Unknown action", an `ok:false` envelope, an unrecognized value) to
/// `'unknown'` — NEVER `'unreachable'` — so a stale/old/garbled hint can never
/// throw away a send (NET-REL-07).
///
/// Returns a map: `presence` (reachable|unreachable|unknown), `ageMs`
/// (nullable int), `ok` (nullable bool).
Future<Map<String, dynamic>> callP2PRelayPresence(
  Bridge bridge, {
  required String peerId,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_RELAY_PRESENCE_REQUEST',
    details: {'peerId': peerId},
  );

  final request = {
    'cmd': 'relay:presence_get',
    'payload': {'peerId': peerId},
  };

  final responseJson = await bridge
      .send(jsonEncode(request))
      .timeout(const Duration(seconds: 5));
  final response = jsonDecode(responseJson) as Map<String, dynamic>;

  // An old relay (or a bridge that passes the raw relay reply through) returns
  // {status:"ERROR", error:"Unknown action: presence_get"} — degrade to
  // 'unknown' (NET-REL-07), never 'unreachable', and flag it so field
  // monitoring can see un-upgraded relays.
  final errorText = (response['error'] ?? response['errorMessage'] ?? '')
      .toString();
  final isUnknownAction =
      response['status'] == 'ERROR' &&
      errorText.toLowerCase().contains('unknown action');
  if (isUnknownAction) {
    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_RELAY_PRESENCE_UNKNOWN_ACTION',
      details: {'peerId': peerId},
    );
  }

  String presence;
  if (isUnknownAction ||
      response['ok'] == false ||
      response['status'] == 'ERROR') {
    presence = 'unknown';
  } else {
    final raw = (response['presence'] ?? 'unknown').toString();
    presence = (raw == 'reachable' || raw == 'unreachable' || raw == 'unknown')
        ? raw
        : 'unknown';
  }
  final ageMs = response['ageMs'];

  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_RELAY_PRESENCE_RESPONSE',
    details: {'presence': presence, 'ageMs': ageMs, 'ok': response['ok']},
  );

  return {'presence': presence, 'ageMs': ageMs, 'ok': response['ok']};
}

/// Calls the bridge to SELF-PUBLISH the local peer's coarse foreground/background
/// presence via the additive `presence_set` action (FDC-09) — the WRITE twin of
/// [callP2PRelayPresence]. The relay derives the subject from the authenticated
/// stream identity (anti-spoof), so only `state`/`ttlMs` are sent.
///
/// Returns a map: `ok` (bool — relay accepted) and `unsupported` (bool — an old
/// relay answered "Unknown action: presence_set"). An old relay / `ok:false` /
/// exception NEVER throws away delivery: presence is a best-effort HINT, so the
/// caller degrades to "skip" (NET-REL-07), never retries/spams.
Future<Map<String, dynamic>> callP2PRelayPresenceSet(
  Bridge bridge, {
  required String state,
  required int ttlMs,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_RELAY_PRESENCE_SET_REQUEST',
    details: {'state': state, 'ttlMs': ttlMs},
  );

  final request = {
    'cmd': 'relay:presence_set',
    'payload': {'state': state, 'ttlMs': ttlMs},
  };

  final responseJson = await bridge
      .send(jsonEncode(request))
      .timeout(const Duration(seconds: 5));
  final response = jsonDecode(responseJson) as Map<String, dynamic>;

  // An old relay returns {status:"ERROR", error:"Unknown action: presence_set"}
  // (or the bridge surfaces it as {ok:false, error:"Unknown action: ..."}).
  // Degrade to "unsupported -> skip" (NET-REL-07), never retry/spam.
  final errorText = (response['error'] ?? response['errorMessage'] ?? '')
      .toString();
  final isUnknownAction = errorText.toLowerCase().contains('unknown action');
  if (isUnknownAction) {
    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_RELAY_PRESENCE_SET_UNKNOWN_ACTION',
      details: {'state': state},
    );
  }

  final ok = response['ok'] == true && !isUnknownAction;

  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_RELAY_PRESENCE_SET_RESPONSE',
    details: {'ok': ok, 'unsupported': isUnknownAction, 'state': state},
  );

  return {'ok': ok, 'unsupported': isUnknownAction};
}

/// 183: actively PINGS a directly-connected 1:1 [peerId] via the additive
/// `peer:ping` command (libp2p ping), so the active-chat keepalive can keep the
/// warm connection alive and detect a drop in seconds.
///
/// Returns a map: `ok` (bool — the peer answered within [timeoutMs]) and `rttMs`
/// (nullable int — round-trip time on success). The probe is best-effort and
/// NEVER load-bearing: an old bridge that does not know `peer:ping` (an
/// `UNKNOWN_COMMAND` / "Unknown action" envelope), an unreachable peer, or any
/// failure all degrade to `{ok:false, rttMs:null}` — never a throw — so the
/// keepalive treats it as a miss rather than crashing the loop.
Future<Map<String, dynamic>> callP2PPeerPing(
  Bridge bridge, {
  required String peerId,
  required int timeoutMs,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_PEER_PING_REQUEST',
    details: {'peerId': peerId, 'timeoutMs': timeoutMs},
  );

  final request = {
    'cmd': 'peer:ping',
    'payload': {'peerId': peerId, 'timeoutMs': timeoutMs},
  };

  final responseJson = await bridge
      .send(jsonEncode(request))
      .timeout(const Duration(seconds: 5));
  final response = jsonDecode(responseJson) as Map<String, dynamic>;

  final ok = response['ok'] == true;
  final rttMs = ok ? response['rttMs'] : null;

  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_PEER_PING_RESPONSE',
    details: {'peerId': peerId, 'ok': ok, 'rttMs': rttMs},
  );

  return {'ok': ok, 'rttMs': rttMs};
}

/// Calls the bridge to register the recipient's opaque wake-token SET with the
/// relay via the additive `register_wake_tokens` action (FDC-09 §12). Returns a
/// map: `ok` (bool — relay accepted) and `unsupported` (bool — an old relay
/// answered "Unknown action"). An old relay / failure NEVER throws away the plain
/// push — the caller degrades gracefully (NET-REL-07).
Future<Map<String, dynamic>> callP2PRegisterWakeTokens(
  Bridge bridge, {
  required List<String> tokens,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_REGISTER_WAKE_TOKENS_REQUEST',
    details: {'count': tokens.length},
  );

  final request = {
    'cmd': 'inbox:register_wake_tokens',
    'payload': {'tokens': tokens},
  };

  final responseJson = await bridge
      .send(jsonEncode(request))
      .timeout(const Duration(seconds: 5));
  final response = jsonDecode(responseJson) as Map<String, dynamic>;

  final errorText = (response['error'] ?? response['errorMessage'] ?? '')
      .toString();
  final isUnknownAction = errorText.toLowerCase().contains('unknown action');
  final ok = response['ok'] == true && !isUnknownAction;

  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_REGISTER_WAKE_TOKENS_RESPONSE',
    details: {'ok': ok, 'unsupported': isUnknownAction},
  );

  return {'ok': ok, 'unsupported': isUnknownAction};
}

/// Calls the bridge to stop the P2P node.
///
/// Returns: `{ "ok": true, "stopped": true }` on success.
Future<Map<String, dynamic>> callP2PNodeStop(Bridge bridge) async {
  emitFlowEvent(layer: 'FL', event: 'P2P_NODE_STOP_REQUEST', details: {});

  final request = {'cmd': 'node:stop', 'payload': <String, dynamic>{}};

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
  emitFlowEvent(layer: 'FL', event: 'P2P_NODE_STATUS_REQUEST', details: {});

  final request = {'cmd': 'node:status', 'payload': <String, dynamic>{}};

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
///   - [namespace]: Optional namespace (defaults to `mknoon:chat:<peerId>`)
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
    'payload': {'namespace': ?namespace, 'serverAddresses': ?serverAddresses},
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

/// Calls the bridge to unregister from a rendezvous namespace.
///
/// Parameters:
///   - [bridge]: The Bridge instance
///   - [namespace]: Optional namespace (defaults to `mknoon:chat:<peerId>`)
///   - [serverAddresses]: Optional list of rendezvous server addresses
///
/// Returns: `{ "ok": true, "unregistered": true }`
Future<Map<String, dynamic>> callP2PRendezvousUnregister(
  Bridge bridge, {
  String? namespace,
  List<String>? serverAddresses,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_RENDEZVOUS_UNREGISTER_REQUEST',
    details: {'namespace': namespace},
  );

  final request = {
    'cmd': 'rendezvous:unregister',
    'payload': {'namespace': ?namespace, 'serverAddresses': ?serverAddresses},
  };

  final responseJson = await bridge.send(jsonEncode(request));
  final response = jsonDecode(responseJson) as Map<String, dynamic>;

  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_RENDEZVOUS_UNREGISTER_RESPONSE',
    details: {'ok': response['ok']},
  );

  return response;
}

/// Calls the bridge to discover peers on a rendezvous namespace.
///
/// Parameters:
///   - [bridge]: The Bridge instance
///   - [peerId]: Optional specific peer ID to discover
///   - [namespace]: Optional namespace (defaults to `mknoon:chat:<peerId>` if peerId provided)
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
      'peerId': ?peerId,
      'namespace': ?namespace,
      'serverAddresses': ?serverAddresses,
      'timeoutMs': ?timeoutMs,
    },
  };

  final watchdog = timeoutMs == null
      ? null
      : Duration(milliseconds: timeoutMs) + p2pBridgeWatchdogMargin;

  final Map<String, dynamic> response;
  try {
    final responseJson = watchdog == null
        ? await bridge.send(jsonEncode(request))
        : await bridge.send(jsonEncode(request)).timeout(watchdog);
    response = jsonDecode(responseJson) as Map<String, dynamic>;
  } on TimeoutException {
    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_RENDEZVOUS_DISCOVER_RESPONSE',
      details: {'ok': false, 'peerCount': 0, 'errorCode': 'BRIDGE_TIMEOUT'},
    );
    return {
      'ok': false,
      'peers': <dynamic>[],
      'errorCode': 'BRIDGE_TIMEOUT',
      'errorMessage':
          'Bridge rendezvous:discover timed out after '
          '${watchdog!.inMilliseconds}ms',
    };
  }

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
///   - [preferQuic]: FDC-04 (DESIGN-5) QUIC-first re-warm intent. INERT on the
///     wire — Go's `peer:dial` handler unmarshals only `{PeerId, Addresses,
///     TimeoutMs}` and silently drops this field. FDC-11 resolves the LAN path
///     by dialing the QUIC multiaddr directly (preferQuic is moot there); the
///     generic QUIC-first ordering on a non-LAN re-warm is deferred to FDC-12.
///     Threaded so the Dart intent is host-observable; sent unconditionally so a
///     future Go change (FDC-12) can read it without a payload-shape change.
///
/// Returns: `{ "ok": true, "connected": true, "peerId": "..." }`
Future<Map<String, dynamic>> callP2PPeerDial(
  Bridge bridge, {
  required String peerId,
  List<String>? addresses,
  int? timeoutMs,
  bool preferQuic = false,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_PEER_DIAL_REQUEST',
    details: {'peerId': peerId, if (preferQuic) 'preferQuic': true},
  );

  final request = {
    'cmd': 'peer:dial',
    'payload': {
      'peerId': peerId,
      'addresses': ?addresses,
      'timeoutMs': ?timeoutMs,
      'preferQuic': preferQuic,
    },
  };

  final watchdog = timeoutMs == null
      ? null
      : Duration(milliseconds: timeoutMs) + p2pBridgeWatchdogMargin;

  final Map<String, dynamic> response;
  try {
    final responseJson = watchdog == null
        ? await bridge.send(jsonEncode(request))
        : await bridge.send(jsonEncode(request)).timeout(watchdog);
    response = jsonDecode(responseJson) as Map<String, dynamic>;
  } on TimeoutException {
    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_PEER_DIAL_RESPONSE',
      details: {'ok': false, 'connected': false, 'errorCode': 'BRIDGE_TIMEOUT'},
    );
    return {
      'ok': false,
      'connected': false,
      'errorCode': 'BRIDGE_TIMEOUT',
      'errorMessage':
          'Bridge peer:dial timed out after ${watchdog!.inMilliseconds}ms',
    };
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_PEER_DIAL_RESPONSE',
    details: {'ok': response['ok'], 'connected': response['connected']},
  );

  return response;
}

/// FDC-11: forwards a bonsoir-discovered same-WiFi peer (carrying the remote's
/// libp2p QUIC/TCP LAN multiaddrs) to the Go host's `lan:peer_found` handler,
/// which seeds the peerstore and issues a libp2p LAN-direct dial gated by
/// EnableLibp2pLANDial.
///
/// Parameters:
///   - [bridge]: The Bridge instance
///   - [peerId]: The discovered peer's libp2p peer ID
///   - [addresses]: The remote's libp2p LAN multiaddrs (QUIC preferred, TCP
///     fallback) — built from the TXT `quicPort`/`tcpPort`, NEVER the wsPort.
///
/// Returns: `{ "ok": true }`
Future<Map<String, dynamic>> callP2PLanPeerFound(
  Bridge bridge, {
  required String peerId,
  required List<String> addresses,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_LAN_PEER_FOUND_REQUEST',
    details: {
      'peerId': peerId,
      'addrCount': addresses.length,
      // FDC-S6 instrument point 2 (net-new private-IP discriminator): the raw
      // multiaddrs are redacted out of the log by flow_event_emitter, so compute
      // the private-IP gate here and carry only the non-sensitive boolean + a
      // short join prefix. A bonsoir-fed peer advertising an RFC1918/link-local
      // addr is the soak's evidence that a later `"direct"` win to this peer was
      // a real same-WiFi LAN dial, not a WAN/DCUtR `"direct"` false positive.
      'peer': peerId.length > 10 ? peerId.substring(0, 10) : peerId,
      'lanPrivateIp': multiaddrsContainPrivateIp(addresses),
    },
  );

  final request = {
    'cmd': 'lan:peer_found',
    'payload': {'peerId': peerId, 'addresses': addresses},
  };

  final responseJson = await bridge.send(jsonEncode(request));
  final response = jsonDecode(responseJson) as Map<String, dynamic>;

  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_LAN_PEER_FOUND_RESPONSE',
    details: {'ok': response['ok']},
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
    'payload': {'peerId': peerId},
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
  int? timeoutMs,
  // FDC-09 §12 / CV-14: the recipient-issued opaque wake-token to present so the
  // relay's access-token gate authorizes waking [toPeerId]. Absent/empty ⇒ the
  // key is omitted entirely so the store frame stays byte-identical to the
  // pre-FDC-09 frame (NET-REL-07); the Go bridge mirrors this with `omitempty`.
  String? wakeToken,
  String? custodyContract,
  String? custodyKind,
  int? custodyExpiresAtOrBeforeMs,
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
      'timeoutMs': ?timeoutMs,
      if (wakeToken != null && wakeToken.isNotEmpty) 'wakeToken': wakeToken,
      'custodyContract': ?custodyContract,
      'custodyKind': ?custodyKind,
      'custodyExpiresAtOrBeforeMs': ?custodyExpiresAtOrBeforeMs,
    },
  };

  final responseJson = await bridge
      .send(jsonEncode(request))
      .timeout(Duration(milliseconds: timeoutMs ?? 15000));
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
const directReactionPushCapability = 'direct_reaction_v1';
const groupReactionPushCapability = 'group_reaction_v1';

Future<Map<String, dynamic>> callP2PInboxRegisterToken(
  Bridge bridge, {
  required String token,
  required String platform,
  List<String> capabilities = const [
    directReactionPushCapability,
    groupReactionPushCapability,
  ],
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
      if (capabilities.isNotEmpty) 'capabilities': capabilities,
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

/// Calls the bridge to unregister this peer's push token from the relay inbox.
///
/// Parameters:
///   - [bridge]: The Bridge instance
///   - [serverAddresses]: Optional list of relay server addresses
///
/// Returns: `{ "ok": true, "unregistered": true }`
Future<Map<String, dynamic>> callP2PInboxUnregisterToken(
  Bridge bridge, {
  List<String>? serverAddresses,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_INBOX_UNREGISTER_TOKEN_REQUEST',
    details: {},
  );

  final request = {
    'cmd': 'inbox:unregister_token',
    'payload': {'serverAddresses': ?serverAddresses},
  };

  final responseJson = await bridge.send(jsonEncode(request));
  final response = jsonDecode(responseJson) as Map<String, dynamic>;

  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_INBOX_UNREGISTER_TOKEN_RESPONSE',
    details: {'ok': response['ok']},
  );

  return response;
}

/// Calls the bridge to retrieve messages from the offline inbox.
///
/// Parameters:
///   - [bridge]: The Bridge instance
///   - [timeoutMs]: Optional retrieval timeout in milliseconds
///
/// Returns: `{ "ok": true, "messages": [...], "hasMore": true/false }`
Future<Map<String, dynamic>> callP2PInboxRetrieve(
  Bridge bridge, {
  int? timeoutMs,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_INBOX_RETRIEVE_REQUEST',
    details: {'timeoutMs': ?timeoutMs},
  );

  final request = {
    'cmd': 'inbox:retrieve',
    'payload': <String, dynamic>{'timeoutMs': ?timeoutMs},
  };

  final responseJson = await bridge.send(jsonEncode(request));
  final response = jsonDecode(responseJson) as Map<String, dynamic>;

  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_INBOX_RETRIEVE_RESPONSE',
    details: {'ok': response['ok'], 'hasMore': response['hasMore']},
  );

  return response;
}

/// Calls the bridge to retrieve messages from the offline inbox without
/// deleting them from the relay.
///
/// Parameters:
///   - [bridge]: The Bridge instance
///   - [timeoutMs]: Optional retrieval timeout in milliseconds
///
/// Returns: `{ "ok": true, "messages": [...], "hasMore": true/false }`
Future<Map<String, dynamic>> callP2PInboxRetrievePending(
  Bridge bridge, {
  int? timeoutMs,
  String? custodyContract,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_INBOX_RETRIEVE_PENDING_REQUEST',
    details: {'timeoutMs': ?timeoutMs},
  );

  final request = {
    'cmd': 'inbox:retrieve_pending',
    'payload': <String, dynamic>{
      'timeoutMs': ?timeoutMs,
      'custodyContract': ?custodyContract,
    },
  };

  final responseJson = await bridge.send(jsonEncode(request));
  final response = jsonDecode(responseJson) as Map<String, dynamic>;

  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_INBOX_RETRIEVE_PENDING_RESPONSE',
    details: {'ok': response['ok'], 'hasMore': response['hasMore']},
  );

  return response;
}

/// Calls the bridge to acknowledge relay inbox entries after the client has
/// durably staged them locally.
///
/// Parameters:
///   - [bridge]: The Bridge instance
///   - [entryIds]: Stable relay inbox entry IDs to delete
///   - [timeoutMs]: Optional ack timeout in milliseconds
///
/// Returns: `{ "ok": true, "acked": N }`
Future<Map<String, dynamic>> callP2PInboxAck(
  Bridge bridge, {
  required List<String> entryIds,
  int? timeoutMs,
  String? custodyContract,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_INBOX_ACK_REQUEST',
    details: {'entryCount': entryIds.length, 'timeoutMs': ?timeoutMs},
  );

  final request = {
    'cmd': 'inbox:ack',
    'payload': <String, dynamic>{
      'entryIds': entryIds,
      'timeoutMs': ?timeoutMs,
      'custodyContract': ?custodyContract,
    },
  };

  final responseJson = await bridge.send(jsonEncode(request));
  final response = jsonDecode(responseJson) as Map<String, dynamic>;

  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_INBOX_ACK_RESPONSE',
    details: {'ok': response['ok'], 'acked': response['acked']},
  );

  return response;
}

// --- Media ---

/// Default Dart-side stall budget for media transfers. Generous on purpose:
/// the Go node's 10s idle-timeout reader is the real failure authority and
/// the native layer emits progress events at a 256KiB/250ms cadence while a
/// transfer is moving, so this only fires when the native call truly stalls
/// without ever reporting failure.
const mediaTransferDefaultStallTimeout = Duration(seconds: 60);

/// Floor used to scale the absolute transfer ceiling to the payload size:
/// `size / 64KiB-per-second`, never below 5 minutes. A last-resort backstop —
/// a slow-but-moving transfer is kept alive by progress events instead.
const mediaTransferBytesPerSecondFloor = 64 * 1024;

Duration mediaTransferMaxTimeout(int? payloadSizeBytes) {
  const minimum = Duration(minutes: 5);
  if (payloadSizeBytes == null || payloadSizeBytes <= 0) {
    return minimum;
  }
  final scaledSeconds = payloadSizeBytes ~/ mediaTransferBytesPerSecondFloor;
  final scaled = Duration(seconds: scaledSeconds);
  return scaled > minimum ? scaled : minimum;
}

/// Sends a media transfer command guarded by a progress-aware watchdog
/// instead of a fixed wall clock: the stall timer re-arms on every matching
/// progress event, and an absolute ceiling remains as a last resort.
Future<Map<String, dynamic>> _sendMediaTransferWithWatchdog({
  required Bridge bridge,
  required Map<String, dynamic> request,
  required Stream<Map<String, dynamic>> progressStream,
  required String id,
  required Duration stallTimeout,
  required Duration maxTimeout,
  required String watchdogLabel,
}) async {
  final completer = Completer<String>();
  Timer? stallTimer;
  Timer? maxTimer;

  void failWithTimeout(String reason, Duration budget) {
    if (completer.isCompleted) {
      return;
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'MEDIA_TRANSFER_WATCHDOG_TIMEOUT',
      details: {
        'id': id,
        'operation': watchdogLabel,
        'reason': reason,
        'budgetMs': budget.inMilliseconds,
      },
    );
    completer.completeError(
      TimeoutException('$watchdogLabel $reason after ${budget.inSeconds}s'),
    );
  }

  void armStallTimer() {
    stallTimer?.cancel();
    stallTimer = Timer(
      stallTimeout,
      () => failWithTimeout('stalled_no_progress', stallTimeout),
    );
  }

  final progressSub = progressStream
      .where((event) => event['id'] == id)
      .listen((_) => armStallTimer());
  armStallTimer();
  maxTimer = Timer(
    maxTimeout,
    () => failWithTimeout('absolute_ceiling_exceeded', maxTimeout),
  );

  bridge
      .send(jsonEncode(request))
      .then(
        (value) {
          if (!completer.isCompleted) {
            completer.complete(value);
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
        },
      );

  try {
    final responseJson = await completer.future;
    return jsonDecode(responseJson) as Map<String, dynamic>;
  } finally {
    stallTimer?.cancel();
    maxTimer.cancel();
    await progressSub.cancel();
  }
}

/// Calls the bridge to upload a media blob to the relay.
///
/// Parameters:
///   - [bridge]: The Bridge instance
///   - [id]: Unique blob ID (UUID)
///   - [toPeerId]: The recipient peer ID
///   - [mime]: MIME type of the file
///   - [filePath]: Absolute path to the local file
///   - [stallTimeout]/[maxTimeout]: watchdog budgets (test seam); defaults
///     are progress-aware with a payload-scaled absolute ceiling.
///
/// Returns: `{ "ok": true, "id": "..." }`
Future<Map<String, dynamic>> callP2PMediaUpload(
  Bridge bridge, {
  required String id,
  required String toPeerId,
  required String mime,
  required String filePath,
  List<String>? allowedPeers,
  String? custodyContract,
  String? custodyKind,
  String? contentHash,
  int? payloadSizeBytes,
  Duration? stallTimeout,
  Duration? maxTimeout,
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
      if (allowedPeers != null && allowedPeers.isNotEmpty)
        'allowedPeers': allowedPeers,
      'custodyContract': ?custodyContract,
      'custodyKind': ?custodyKind,
      'contentHash': ?contentHash,
    },
  };

  final custodyRequested =
      custodyContract != null || custodyKind != null || contentHash != null;
  // Strict custody must return the native phase-aware typed result. An outer
  // Dart timeout could otherwise fire after READY while the native commit (or
  // its same-relay recovery probe) is still running.
  final response = custodyRequested
      ? jsonDecode(await bridge.send(jsonEncode(request)))
            as Map<String, dynamic>
      : await _sendMediaTransferWithWatchdog(
          bridge: bridge,
          request: request,
          progressStream: mediaUploadProgressStream,
          id: id,
          stallTimeout: stallTimeout ?? mediaTransferDefaultStallTimeout,
          maxTimeout: maxTimeout ?? mediaTransferMaxTimeout(payloadSizeBytes),
          watchdogLabel: 'media:upload',
        );

  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_MEDIA_UPLOAD_RESPONSE',
    details: {'ok': response['ok'], 'id': response['id']},
  );

  return response;
}

/// FDC-15: streams a 1:1 media ciphertext blob to [toPeerId] over the
/// peer-authenticated libp2p LAN-direct conn (`media:lan_send` → Go
/// `MediaLANSend` → `Node.SendLANMedia`). The Go node refuses unless a
/// non-circuit conn exists, computes the SHA-256 of the ciphertext file, and the
/// receiver verifies it. Best-effort acceleration only — the relay-CDN upload
/// stays unconditional at the caller.
///
/// There is no LAN media progress stream yet (Go `MediaLANSend` emits none), so
/// this rides a stall-only watchdog (it reuses the media-upload progress stream,
/// whose events never match a LAN id, so the stall timer is never re-armed). The
/// native dispatch + EventChannel are device-deferred (FDC-11/FDC-15 D1).
///
/// Returns: `{ "ok": true, "acked": bool, "sha256Verified": bool, "transport": "direct" }`.
Future<Map<String, dynamic>> callP2PLanMediaSend(
  Bridge bridge, {
  required String id,
  required String toPeerId,
  required String fromPeerId,
  required String mime,
  required String filePath,
  bool enc = false,
  String? encScheme,
  int? durationMs,
  int? payloadSizeBytes,
  Duration? stallTimeout,
  Duration? maxTimeout,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_LAN_MEDIA_SEND_REQUEST',
    details: {'id': id, 'toPeerId': toPeerId, 'mime': mime},
  );

  final request = {
    'cmd': 'media:lan_send',
    'payload': {
      'id': id,
      'to': toPeerId,
      'from': fromPeerId,
      'mime': mime,
      'filePath': filePath,
      'enc': enc,
      'encScheme': ?encScheme,
      'durationMs': ?durationMs,
    },
  };

  final response = await _sendMediaTransferWithWatchdog(
    bridge: bridge,
    request: request,
    progressStream: mediaUploadProgressStream,
    id: id,
    stallTimeout: stallTimeout ?? mediaTransferDefaultStallTimeout,
    maxTimeout: maxTimeout ?? mediaTransferMaxTimeout(payloadSizeBytes),
    watchdogLabel: 'media:lan_send',
  );

  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_LAN_MEDIA_SEND_RESPONSE',
    details: {'ok': response['ok'], 'id': id},
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
  String? custodyContract,
  String? custodyKind,
  String? contentHash,
  int? size,
  String? mime,
  int? expiresAtMs,
  int? payloadSizeBytes,
  Duration? stallTimeout,
  Duration? maxTimeout,
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
      'custodyContract': ?custodyContract,
      'custodyKind': ?custodyKind,
      'contentHash': ?contentHash,
      'size': ?size,
      'mime': ?mime,
      'expiresAtMs': ?expiresAtMs,
    },
  };

  final custodyRequested =
      custodyContract != null ||
      custodyKind != null ||
      contentHash != null ||
      size != null ||
      mime != null ||
      expiresAtMs != null;
  final response = custodyRequested
      ? jsonDecode(await bridge.send(jsonEncode(request)))
            as Map<String, dynamic>
      : await _sendMediaTransferWithWatchdog(
          bridge: bridge,
          request: request,
          progressStream: mediaDownloadProgressStream,
          id: id,
          stallTimeout: stallTimeout ?? mediaTransferDefaultStallTimeout,
          maxTimeout: maxTimeout ?? mediaTransferMaxTimeout(payloadSizeBytes),
          watchdogLabel: 'media:download',
        );
  final responseDetails = <String, dynamic>{
    'ok': response['ok'],
    'id': response['id'],
  };
  for (final key in const [
    'sourceRole',
    'sourcePeerId',
    'sourcePeerShort',
    'streamTransport',
    'servedByPhone',
    'routedViaRelayStore',
  ]) {
    if (response.containsKey(key)) {
      responseDetails[key] = response[key];
    }
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_MEDIA_DOWNLOAD_RESPONSE',
    details: responseDetails,
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
  String? custodyContract,
  String? custodyKind,
  String? contentHash,
  int? size,
  String? mime,
  int? expiresAtMs,
  String? custodyRelayPeerId,
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
      'custodyContract': ?custodyContract,
      'custodyKind': ?custodyKind,
      'contentHash': ?contentHash,
      'size': ?size,
      'mime': ?mime,
      'expiresAtMs': ?expiresAtMs,
      'custodyRelayPeerId': ?custodyRelayPeerId,
    },
  };

  final custodyRequested =
      custodyContract != null ||
      custodyKind != null ||
      contentHash != null ||
      size != null ||
      mime != null ||
      expiresAtMs != null ||
      custodyRelayPeerId != null;
  // Native pins strict ACK to the proof source and owns its sibling retries;
  // preserve that typed result instead of pre-empting it with a Dart timeout.
  final responseJson = custodyRequested
      ? await bridge.send(jsonEncode(request))
      : await bridge
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
  emitFlowEvent(layer: 'FL', event: 'P2P_MEDIA_LIST_REQUEST', details: {});

  final request = {'cmd': 'media:list', 'payload': <String, dynamic>{}};

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
    'payload': {'mime': mime, 'filePath': filePath},
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
    'payload': {'ownerPeerId': ownerPeerId, 'outputPath': outputPath},
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
/// Returns: `{ "ok": true, "sent": true, "reply": "...", "transport": "direct|relay" }`
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
    'payload': {'peerId': peerId, 'message': message, 'timeoutMs': ?timeoutMs},
  };

  // F5: Go self-bounds the send via SetDeadline, but a MethodChannel/gomobile
  // boundary stall or iOS suspension can freeze that deadline timer and leave
  // this await pending forever, locking the composer (_isSending stuck true).
  // Cap the await strictly LOOSER than the Go self-bound so it only fires on a
  // true boundary hang, and surface it as a returned `BRIDGE_TIMEOUT` (sent:
  // false) that degrades to the durable inbox fallback — NOT failed-and-lost.
  // The wrap is null-safe: callers passing no timeoutMs (sendMessage) stay
  // unbounded, exactly as before.
  final timeout = timeoutMs == null
      ? null
      : Duration(milliseconds: timeoutMs) + p2pBridgeWatchdogMargin;

  final Map<String, dynamic> response;
  try {
    final responseJson = timeout != null
        ? await bridge.send(jsonEncode(request)).timeout(timeout)
        : await bridge.send(jsonEncode(request));
    response = jsonDecode(responseJson) as Map<String, dynamic>;
  } on TimeoutException {
    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_MESSAGE_SEND_RESPONSE',
      details: {'ok': false, 'sent': false, 'errorCode': 'BRIDGE_TIMEOUT'},
    );
    return {
      'ok': false,
      'sent': false,
      'errorCode': 'BRIDGE_TIMEOUT',
      'errorMessage':
          'Bridge message:send timed out after ${timeout?.inMilliseconds ?? 0}ms',
    };
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_MESSAGE_SEND_RESPONSE',
    details: {
      'ok': response['ok'],
      'sent': response['sent'],
      'acked': response['acked'],
      'hasReply': response['reply'] != null,
      'transport': response['transport'],
      'errorCode': response['errorCode'],
      'errorMessage': response['errorMessage'],
    },
  );

  return response;
}

/// Confirms the receiver-side terminal handling result for a deferred direct
/// chat ACK nonce.
Future<Map<String, dynamic>> callP2PConfirmDirectMessage(
  Bridge bridge, {
  required String nonce,
  required bool ok,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_DIRECT_CONFIRM_REQUEST',
    details: {'nonce': nonce, 'ok': ok},
  );

  final request = {
    'cmd': 'message:confirm',
    'payload': {'nonce': nonce, 'ok': ok},
  };

  final responseJson = await bridge.send(jsonEncode(request));
  final response = jsonDecode(responseJson) as Map<String, dynamic>;

  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_DIRECT_CONFIRM_RESPONSE',
    details: {'nonce': nonce, 'ok': response['ok'], 'confirmed': ok},
  );

  return response;
}
