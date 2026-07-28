part of '../p2p_service_impl.dart';

/// A learned per-peer live transport plus its observation time.
class _LearnedTransport {
  final String transport;
  final DateTime at;

  const _LearnedTransport(this.transport, this.at);
}

/// A short-lived relay-presence answer plus its observation time.
class _PresenceCacheEntry {
  final RelayPresence presence;
  final DateTime at;

  const _PresenceCacheEntry(this.presence, this.at);
}

/// Per-peer eager-warm debounce and escalating-backoff state.
class _WarmAttempt {
  bool inFlight = false;
  DateTime? nextEligibleAt;
  int failureCount = 0;
}

/// Sanitized transport telemetry parsed before entering the coordinator.
class _PeerTransportDiagnostic {
  final String eventName;
  final Object? step;
  final Object? remotePeerShort;

  const _PeerTransportDiagnostic({
    required this.eventName,
    this.step,
    this.remotePeerShort,
  });
}

/// Narrow immutable primitives needed by the peer/LAN decision owner.
class _P2PPeerTransportPort {
  final NodeState Function() readNodeState;
  final Future<bool> Function(String operation, {String? peerId})
  allowsAccountNetworkSideEffects;
  final Future<bool> Function(
    String peerId, {
    List<String>? addresses,
    int? timeoutMs,
    required bool preferQuic,
  })
  dialPeer;
  final Future<void> Function() drainOfflineInbox;
  final Future<Map<String, dynamic>> Function({required String peerId})
  probeRelay;
  final Future<Map<String, dynamic>> Function({required String peerId})
  lookupRelayPresence;
  final Future<Map<String, dynamic>> Function({
    required String state,
    required int ttlMs,
  })
  setRelayPresence;
  final Future<Map<String, dynamic>> Function({
    required String peerId,
    required int timeoutMs,
  })
  pingPeer;
  final Future<Map<String, dynamic>> Function({
    required String peerId,
    required List<String> addresses,
  })
  forwardLanPeer;
  final Future<Map<String, dynamic>> Function({
    required String id,
    required String toPeerId,
    required String fromPeerId,
    required String mime,
    required String filePath,
    required bool enc,
    String? encScheme,
    int? durationMs,
  })
  sendLanMedia;
  final void Function({
    required String layer,
    required String event,
    required Map<String, dynamic> details,
  })
  emitEvent;

  const _P2PPeerTransportPort({
    required this.readNodeState,
    required this.allowsAccountNetworkSideEffects,
    required this.dialPeer,
    required this.drainOfflineInbox,
    required this.probeRelay,
    required this.lookupRelayPresence,
    required this.setRelayPresence,
    required this.pingPeer,
    required this.forwardLanPeer,
    required this.sendLanMedia,
    required this.emitEvent,
  });
}

/// Owns peer/LAN policy and session-scoped caches behind typed primitives.
class _P2PPeerTransportCoordinator {
  static const Duration _presenceCacheTtl = Duration(seconds: 12);
  static const Duration _warmLanTimeout = Duration(milliseconds: 1500);
  static const Duration _warmDialTimeout = Duration(seconds: 4);
  static const Duration _warmCooldownFloor = Duration(seconds: 5);
  static const Duration _warmCooldownCeil = Duration(minutes: 5);

  final _P2PPeerTransportPort _port;
  final LocalP2PService? _localP2P;
  final TransportMetrics? _transportMetrics;
  final String? Function()? _activePeerId;

  final Set<String> _peersUpgradedToDirect = <String>{};
  final Map<String, _LearnedTransport> _learnedTransport =
      <String, _LearnedTransport>{};
  final Map<String, _PresenceCacheEntry> _presenceCache =
      <String, _PresenceCacheEntry>{};
  final Map<String, _WarmAttempt> _warmAttempts = <String, _WarmAttempt>{};
  final Set<String> _lanDialForwardedPeerIds = <String>{};
  final Set<String> _lanEmptyReResolvedPeerIds = <String>{};
  final Set<String> _suspectedDroppedPeers = <String>{};

  DateTime? _lastNetworkRewarmAt;
  bool _localDiscoveryActive = false;
  int? _resolvedAdvertQuicPort;
  int? _resolvedAdvertTcpPort;
  bool _localNetworkProven = false;
  bool _disposed = false;
  Timer? _lanPermProbeTimer;

  _P2PPeerTransportCoordinator({
    required _P2PPeerTransportPort port,
    LocalP2PService? localP2P,
    TransportMetrics? transportMetrics,
    String? Function()? activePeerId,
  }) : _port = port,
       _localP2P = localP2P,
       _transportMetrics = transportMetrics,
       _activePeerId = activePeerId {
    _recordLanAvailability(
      discoveryActive: false,
      discoveredPeerCount: _localP2P?.discoveredPeers.length ?? 0,
    );
  }

  void _emit(String event, Map<String, dynamic> details) {
    if (_disposed) return;
    _port.emitEvent(layer: 'FL', event: event, details: details);
  }

  void recordTransport(String transport) {
    if (_disposed) return;
    _transportMetrics?.recordTransport(transport);
  }

  Future<void> startEarlyLocalDiscovery() async {
    if (_disposed || _localDiscoveryActive) return;
    final allowed = await _port.allowsAccountNetworkSideEffects(
      'p2p_lan_discovery',
    );
    if (_disposed || !allowed) {
      return;
    }
    final localPeerId = _port.readNodeState().peerId;
    if (_localP2P == null || localPeerId == null) return;
    _emit('P2P_SERVICE_EARLY_LOCAL_DISCOVERY_START', <String, dynamic>{});
    await _startLocalDiscovery(localPeerId);
  }

  Future<void> _startLocalDiscovery(String localPeerId) async {
    if (_disposed || _localDiscoveryActive) return;
    final localP2P = _localP2P;
    if (localP2P == null) return;

    try {
      final listenAddresses = _port.readNodeState().listenAddresses;
      await localP2P.start(
        localPeerId,
        quicPort: _libp2pListenPort(listenAddresses, quic: true),
        tcpPort: _libp2pListenPort(listenAddresses, quic: false),
      );
      if (_disposed) {
        try {
          await localP2P.stop();
        } catch (_) {
          // Best-effort compensation for a start that completed after dispose.
        }
        return;
      }
      _setLocalDiscoveryActive();
    } catch (_) {
      if (_disposed) return;
      _setLocalDiscoveryInactive();
      rethrow;
    }
  }

  static int? _libp2pListenPort(
    List<String> listenAddresses, {
    required bool quic,
  }) {
    for (final address in listenAddresses) {
      if (quic) {
        final match = RegExp(r'/udp/(\d+)/quic-v1').firstMatch(address);
        if (match != null) return int.tryParse(match.group(1)!);
      } else {
        if (address.contains('/ws') || address.contains('quic')) continue;
        final match = RegExp(r'/tcp/(\d+)').firstMatch(address);
        if (match != null) return int.tryParse(match.group(1)!);
      }
    }
    return null;
  }

  void _setLocalDiscoveryActive() {
    if (_disposed) return;
    _localDiscoveryActive = true;
    _recordLanAvailability(
      discoveryActive: true,
      discoveredPeerCount: _localP2P?.discoveredPeers.length ?? 0,
    );
    _startLanPermProbe();
  }

  Future<void> stopLocalService() async {
    await _localP2P?.stop();
  }

  Future<void> restartLocalAdvertising() async {
    if (_disposed) return;
    await _localP2P?.restartAdvertising();
  }

  void setLocalDiscoveryActive() {
    if (_disposed) return;
    _setLocalDiscoveryActive();
  }

  void setLocalDiscoveryInactive() {
    _setLocalDiscoveryInactive();
  }

  void _setLocalDiscoveryInactive() {
    _localDiscoveryActive = false;
    _lanPermProbeTimer?.cancel();
    _lanPermProbeTimer = null;
    _recordLanAvailability(discoveryActive: false, discoveredPeerCount: 0);
  }

  void _startLanPermProbe() {
    if (_disposed) return;
    _lanPermProbeTimer?.cancel();
    _lanPermProbeTimer = Timer(const Duration(seconds: 12), () {
      _lanPermProbeTimer = null;
      if (_disposed) return;
      final peerCount = _localP2P?.discoveredPeers.length ?? 0;
      if (_localDiscoveryActive && peerCount == 0) {
        _emit('LOCAL_MDNS_SUSPECTED_PERMISSION_DENIED', <String, dynamic>{
          'discoveryActive': true,
          'discoveredPeerCount': 0,
        });
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

  void onDiscoveredPeersChanged(Map<String, LocalPeer> peers) {
    if (_disposed) return;
    _lanDialForwardedPeerIds.removeWhere((id) => !peers.containsKey(id));
    _lanEmptyReResolvedPeerIds.removeWhere((id) => !peers.containsKey(id));

    if (peers.isNotEmpty) {
      _lanPermProbeTimer?.cancel();
      _lanPermProbeTimer = null;
      _localNetworkProven = true;
      _maybePublishLibp2pAdvertPorts(source: 'peer_resolved');
    }

    _recordLanAvailability(
      discoveryActive: _localDiscoveryActive,
      discoveredPeerCount: peers.length,
    );
    unawaited(_forwardLanPeersToLibp2pDial(peers));
  }

  Future<void> _forwardLanPeersToLibp2pDial(
    Map<String, LocalPeer> peers,
  ) async {
    for (final peer in peers.values) {
      if (_disposed) return;
      if (peer.libp2pAddresses.isEmpty) {
        if (_lanEmptyReResolvedPeerIds.add(peer.peerId)) {
          _emit('LOCAL_MDNS_PEER_SKIPPED_NO_LIBP2P_ADDR', <String, dynamic>{
            'peerId': peer.peerId,
            'host': peer.host,
          });
          unawaited(_reResolveEmptyLanPeer(peer.peerId));
        }
        continue;
      }

      _lanEmptyReResolvedPeerIds.remove(peer.peerId);
      if (_lanDialForwardedPeerIds.contains(peer.peerId)) continue;
      if (!await _port.allowsAccountNetworkSideEffects(
        'p2p_lan_dial',
        peerId: peer.peerId,
      )) {
        continue;
      }
      if (_disposed) return;

      _lanDialForwardedPeerIds.add(peer.peerId);
      try {
        await _port.forwardLanPeer(
          peerId: peer.peerId,
          addresses: peer.libp2pAddresses,
        );
      } catch (error) {
        if (_disposed) return;
        _lanDialForwardedPeerIds.remove(peer.peerId);
        _emit('P2P_SERVICE_LAN_PEER_FOUND_FORWARD_ERROR', <String, dynamic>{
          'error': error.toString(),
        });
      }
    }
  }

  Future<void> _reResolveEmptyLanPeer(String peerId) async {
    if (_disposed) return;
    final localP2P = _localP2P;
    if (localP2P == null) return;
    try {
      await localP2P.discoverLocalPeer(
        peerId,
        timeout: const Duration(seconds: 3),
      );
    } catch (_) {
      // Best effort. A later snapshot can retry after the episode resets.
    }
  }

  void onListenAddressesUpdated(List<String> listenAddresses) {
    if (_disposed) return;
    _resolvedAdvertQuicPort = _libp2pListenPort(listenAddresses, quic: true);
    _resolvedAdvertTcpPort = _libp2pListenPort(listenAddresses, quic: false);
    _maybePublishLibp2pAdvertPorts(source: 'addresses_updated');
  }

  void _maybePublishLibp2pAdvertPorts({required String source}) {
    if (_disposed) return;
    final localP2P = _localP2P;
    if (localP2P == null || !_localDiscoveryActive) return;
    final quicPort = _resolvedAdvertQuicPort;
    final tcpPort = _resolvedAdvertTcpPort;
    if (quicPort == null && tcpPort == null) return;

    if (!_localNetworkProven) {
      _emit('FDC_LAN_ADVERT_PORTS_DEFERRED', <String, dynamic>{
        'quicPort': quicPort ?? -1,
        'tcpPort': tcpPort ?? -1,
        'source': source,
      });
      return;
    }

    unawaited(localP2P.updateLibp2pPorts(quicPort: quicPort, tcpPort: tcpPort));
    _emit('FDC_LAN_ADVERT_PORTS', <String, dynamic>{
      'quicPort': quicPort ?? -1,
      'tcpPort': tcpPort ?? -1,
      'source': source,
    });
  }

  static String _shortPeer(String peerId) =>
      peerId.length > 10 ? peerId.substring(0, 10) : peerId;

  Future<void> warmPeer(String peerId, {bool preferQuic = false}) async {
    if (_disposed) return;
    final attempt = _warmAttempts.putIfAbsent(peerId, () => _WarmAttempt());
    try {
      if (!_port.readNodeState().isStarted) {
        _emit('P2P_SERVICE_WARM_PEER_SKIPPED', <String, dynamic>{
          'reason': 'not_started',
        });
        return;
      }

      final now = clock.now();
      if (attempt.inFlight ||
          (attempt.nextEligibleAt != null &&
              now.isBefore(attempt.nextEligibleAt!))) {
        _emit('P2P_SERVICE_WARM_PEER_DEBOUNCED', <String, dynamic>{
          'peerId': _shortPeer(peerId),
        });
        return;
      }
      attempt.inFlight = true;

      _emit('P2P_SERVICE_WARM_PEER_BEGIN', <String, dynamic>{
        'peerId': _shortPeer(peerId),
        if (preferQuic) 'preferQuic': true,
      });

      final allowed = await _port.allowsAccountNetworkSideEffects(
        'p2p_warm_peer',
      );
      if (_disposed) return;
      if (!allowed) {
        attempt.inFlight = false;
        return;
      }

      _emit('P2P_SERVICE_WARM_PEER_LAN_SEED', <String, dynamic>{
        'peerId': _shortPeer(peerId),
      });
      final seededLocal = await discoverLocalPeer(
        peerId,
        timeout: _warmLanTimeout,
      ).catchError((Object _) => false);
      if (_disposed) return;

      if (seededLocal || isLocalPeer(peerId)) {
        attempt.inFlight = false;
        _emit('P2P_SERVICE_WARM_PEER_DIAL_SKIPPED', <String, dynamic>{
          'peerId': _shortPeer(peerId),
          'reason': 'is_local',
        });
        return;
      }

      _emit('P2P_SERVICE_WARM_PEER_DIAL', <String, dynamic>{
        'peerId': _shortPeer(peerId),
        if (preferQuic) 'preferQuic': true,
      });
      unawaited(
        _port
            .dialPeer(
              peerId,
              timeoutMs: _warmDialTimeout.inMilliseconds,
              preferQuic: preferQuic,
            )
            .then((ok) => _onWarmDialOutcome(peerId, ok))
            .catchError((Object _) {
              _onWarmDialOutcome(peerId, false);
            }),
      );
    } catch (_) {
      if (_disposed) return;
      attempt.inFlight = false;
    }
  }

  void _onWarmDialOutcome(String peerId, bool ok) {
    if (_disposed) return;
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

  void onNetworkChanged() {
    if (_disposed) return;
    try {
      final now = clock.now();
      if (_lastNetworkRewarmAt != null &&
          now.difference(_lastNetworkRewarmAt!) < _warmCooldownFloor) {
        return;
      }
      _lastNetworkRewarmAt = now;

      _emit('P2P_SERVICE_NETWORK_CHANGE_DRAIN_BEGIN', <String, dynamic>{});
      unawaited(_port.drainOfflineInbox().catchError((Object _) {}));

      final peerId = _activePeerId?.call();
      if (peerId == null || peerId.isEmpty) return;

      _warmAttempts[peerId]?.nextEligibleAt = null;
      final learned = _learnedTransport[peerId];
      if (learned != null && learned.transport == 'local') {
        _learnedTransport.remove(peerId);
      }

      _emit('P2P_SERVICE_WARM_PEER_NETWORK_CHANGE_REWARM', <String, dynamic>{
        'peerId': _shortPeer(peerId),
      });
      unawaited(warmPeer(peerId, preferQuic: true));
    } catch (_) {
      // Stream-driven and intentionally total.
    }
  }

  void onPeerDisconnected(String peerId) {
    if (_disposed) return;
    _learnedTransport.remove(peerId);
  }

  void onRelayHealthTransition({
    required bool wasHealthy,
    required bool nowHealthy,
  }) {
    if (_disposed) return;
    if (wasHealthy != nowHealthy) {
      _learnedTransport.removeWhere(
        (_, learned) => learned.transport != 'local',
      );
    }
  }

  static String _shortId(String peerId) =>
      peerId.length <= 8 ? peerId : peerId.substring(peerId.length - 8);

  void onTransportDiagnostic(_PeerTransportDiagnostic diagnostic) {
    if (_disposed) return;
    switch (diagnostic.eventName) {
      case 'holepunch:attempt':
        final step = diagnostic.step as String?;
        if (step == 'attempt') {
          _transportMetrics?.recordHolePunchAttempt();
        }
        break;
      case 'holepunch:success':
        _transportMetrics?.recordHolePunchSuccess();
        _recordPeerUpgrade(diagnostic.remotePeerShort as String?);
        break;
      case 'holepunch:failure':
        _transportMetrics?.recordHolePunchFailure();
        break;
      case 'transport:upgraded':
        {
          _transportMetrics?.recordRelayToDirectUpgrade();
          final short = diagnostic.remotePeerShort as String?;
          _recordPeerUpgrade(short);
          final upgradedPeerId = _resolveFullPeerId(short);
          if (upgradedPeerId != null) {
            recordSuccessfulTransport(upgradedPeerId, 'direct');
          }
        }
        break;
      case 'transport:downgraded':
        {
          final short = diagnostic.remotePeerShort as String?;
          _recordPeerDowngrade(short);
          final downgradedPeerId = _resolveFullPeerId(short);
          if (downgradedPeerId != null) {
            _learnedTransport.remove(downgradedPeerId);
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

  void _recordPeerDowngrade(String? remotePeerShort) {
    if (remotePeerShort != null && remotePeerShort.isNotEmpty) {
      _peersUpgradedToDirect.remove(remotePeerShort);
    }
  }

  String? _resolveFullPeerId(String? remotePeerShort) {
    if (remotePeerShort == null || remotePeerShort.isEmpty) return null;
    String? match;
    for (final connection in _port.readNodeState().connections) {
      if (_shortId(connection.peerId) == remotePeerShort) {
        if (match != null && match != connection.peerId) {
          return null;
        }
        match = connection.peerId;
      }
    }
    return match;
  }

  String? _inferTransportForPeer(String peerId) {
    if (_peersUpgradedToDirect.contains(_shortId(peerId))) {
      return 'upgraded';
    }

    var sawDirectConnection = false;
    for (final connection in _port.readNodeState().connections) {
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

  Future<RelayProbeResult> probeRelay(String peerId) async {
    if (_disposed) return RelayProbeResult.error;
    final allowed = await _port.allowsAccountNetworkSideEffects(
      'p2p_probe_relay',
    );
    if (_disposed || !allowed) {
      return RelayProbeResult.error;
    }

    try {
      final result = await _port.probeRelay(peerId: peerId);
      if (result['ok'] == true) return RelayProbeResult.connected;
      if (result['errorCode'] == 'NO_RESERVATION') {
        return RelayProbeResult.noReservation;
      }
      return RelayProbeResult.error;
    } catch (_) {
      return RelayProbeResult.error;
    }
  }

  Future<RelayPresence> lookupRelayPresence(String peerId) async {
    if (_disposed) return RelayPresence.unknown;
    final allowed = await _port.allowsAccountNetworkSideEffects(
      'p2p_get_presence',
    );
    if (_disposed || !allowed) {
      return RelayPresence.unknown;
    }

    final cached = _presenceCache[peerId];
    if (cached != null) {
      if (clock.now().difference(cached.at) <= _presenceCacheTtl) {
        _emit('P2P_RELAY_PRESENCE_CACHE_HIT', <String, dynamic>{
          'peerId': peerId,
          'presence': cached.presence.name,
        });
        return cached.presence;
      }
      _presenceCache.remove(peerId);
    }

    try {
      final result = await _port.lookupRelayPresence(peerId: peerId);
      if (_disposed) return RelayPresence.unknown;
      final presence = _relayPresenceFromString(result['presence'] as String?);
      _presenceCache[peerId] = _PresenceCacheEntry(presence, clock.now());
      return presence;
    } catch (_) {
      return RelayPresence.unknown;
    }
  }

  RelayPresence _relayPresenceFromString(String? value) {
    switch (value) {
      case 'reachable':
        return RelayPresence.reachable;
      case 'unreachable':
        return RelayPresence.unreachable;
      default:
        return RelayPresence.unknown;
    }
  }

  Future<PresenceSetResult> setPresence(String state, int ttlMs) async {
    if (_disposed) return PresenceSetResult.blocked;
    final allowed = await _port.allowsAccountNetworkSideEffects(
      'p2p_set_presence',
    );
    if (_disposed || !allowed) {
      return PresenceSetResult.blocked;
    }

    _emit('P2P_SERVICE_SET_PRESENCE_BEGIN', <String, dynamic>{
      'state': state,
      'ttlMs': ttlMs,
    });

    try {
      final result = await _port.setRelayPresence(state: state, ttlMs: ttlMs);
      if (_disposed) return PresenceSetResult.blocked;
      if (result['unsupported'] == true) {
        return PresenceSetResult.unsupported;
      }
      final ok = result['ok'] == true;
      _emit(
        ok
            ? 'P2P_SERVICE_SET_PRESENCE_SUCCESS'
            : 'P2P_SERVICE_SET_PRESENCE_FAILED',
        <String, dynamic>{'state': state, 'ok': ok},
      );
      return ok ? PresenceSetResult.published : PresenceSetResult.failed;
    } catch (error) {
      _emit('P2P_SERVICE_SET_PRESENCE_EXCEPTION', <String, dynamic>{
        'state': state,
        'error': error.toString(),
      });
      return PresenceSetResult.failed;
    }
  }

  Future<bool> pingPeer(String peerId, {required int timeoutMs}) async {
    if (_disposed) return false;
    final allowed = await _port.allowsAccountNetworkSideEffects(
      'p2p_peer_ping',
      peerId: peerId,
    );
    if (_disposed || !allowed) {
      return false;
    }

    _emit('P2P_SERVICE_PEER_PING_BEGIN', <String, dynamic>{
      'peerId': _shortPeer(peerId),
    });

    try {
      final result = await _port.pingPeer(peerId: peerId, timeoutMs: timeoutMs);
      if (_disposed) return false;
      final ok = result['ok'] == true;
      _emit(
        ok ? 'P2P_SERVICE_PEER_PING_SUCCESS' : 'P2P_SERVICE_PEER_PING_FAILED',
        <String, dynamic>{'peerId': _shortPeer(peerId), 'ok': ok},
      );
      return ok;
    } catch (error) {
      _emit('P2P_SERVICE_PEER_PING_EXCEPTION', <String, dynamic>{
        'peerId': _shortPeer(peerId),
        'error': error.toString(),
      });
      return false;
    }
  }

  bool isPeerSuspectedDropped(String peerId) {
    return _suspectedDroppedPeers.contains(
      ActiveConversationTracker.normalizeActiveKey(peerId),
    );
  }

  void setPeerDropSuspected(String peerId, bool dropped) {
    if (_disposed) return;
    final key = ActiveConversationTracker.normalizeActiveKey(peerId);
    if (dropped) {
      _suspectedDroppedPeers.add(key);
    } else {
      _suspectedDroppedPeers.remove(key);
    }
  }

  bool isConnectedToPeer(String peerId) {
    return _port.readNodeState().connections.any(
      (connection) =>
          connection.peerId == peerId && connection.status == 'connected',
    );
  }

  bool isLocalPeer(String peerId) => _localP2P?.isLocalPeer(peerId) ?? false;

  static bool _connHasDirectAddr(ConnectionState connection) {
    return connection.multiaddrs.any(
      (multiaddr) =>
          multiaddr.isNotEmpty && !multiaddr.contains('/p2p-circuit'),
    );
  }

  bool hasNonCircuitDirectConn(String peerId) {
    if (!isConnectedToPeer(peerId)) return false;
    return _port.readNodeState().connections.any(
      (connection) =>
          connection.peerId == peerId && _connHasDirectAddr(connection),
    );
  }

  bool get _libp2pLanMediaEnabled {
    return _port.readNodeState().featureFlags?['enableLibp2pLANMedia'] ?? false;
  }

  String? lastKnownGoodTransport(String peerId) {
    if (_disposed) return null;
    final learned = _learnedTransport[peerId];
    if (learned == null) return null;

    final age = clock.now().difference(learned.at);
    final ttl = learned.transport == 'local'
        ? const Duration(seconds: 30)
        : const Duration(minutes: 10);
    if (age > ttl) {
      _learnedTransport.remove(peerId);
      return null;
    }

    if (learned.transport == 'local' && !isLocalPeer(peerId)) {
      _learnedTransport.remove(peerId);
      return null;
    }
    return learned.transport;
  }

  void recordSuccessfulTransport(String peerId, String transport) {
    if (_disposed) return;
    if (transport == 'local' || transport == 'direct' || transport == 'relay') {
      _learnedTransport[peerId] = _LearnedTransport(transport, clock.now());
    }
  }

  Future<bool> discoverLocalPeer(
    String peerId, {
    required Duration timeout,
  }) async {
    if (_disposed) return false;
    final allowed = await _port.allowsAccountNetworkSideEffects(
      'p2p_discover_local_peer',
    );
    if (_disposed || !allowed) {
      return false;
    }

    final localP2P = _localP2P;
    if (localP2P == null) return false;
    return localP2P.discoverLocalPeer(peerId, timeout: timeout);
  }

  Future<LanSendAck> sendLocalMessageDurable(
    String peerId,
    String message,
    String fromPeerId, {
    int? timeoutMs,
  }) async {
    if (_disposed) return LanSendAck.failed;
    final allowed = await _port.allowsAccountNetworkSideEffects(
      'p2p_send_local_message',
      peerId: fromPeerId,
    );
    if (_disposed || !allowed) {
      return LanSendAck.failed;
    }

    final localP2P = _localP2P;
    if (localP2P == null) return LanSendAck.failed;
    return localP2P.sendMessageDetailed(
      peerId,
      message,
      fromPeerId,
      timeoutMs: timeoutMs,
    );
  }

  Future<bool> sendLocalMessage(
    String peerId,
    String message,
    String fromPeerId, {
    int? timeoutMs,
  }) async {
    return await sendLocalMessageDurable(
          peerId,
          message,
          fromPeerId,
          timeoutMs: timeoutMs,
        ) ==
        LanSendAck.committed;
  }

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
    if (_disposed) return false;
    final allowed = await _port.allowsAccountNetworkSideEffects(
      'p2p_send_local_media',
      peerId: fromPeerId,
    );
    if (_disposed || !allowed) {
      return false;
    }

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
      _emit('LIBP2P_LAN_MEDIA_SEND_SKIPPED', <String, dynamic>{
        'id': mediaId,
        'flagEnabled': _libp2pLanMediaEnabled,
        'enc': enc,
        'hasDirectConn': hasDirectConn,
      });
    }

    final localP2P = _localP2P;
    if (localP2P == null) return false;
    return localP2P.sendMedia(
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
    if (_disposed) return;
    try {
      await _port.sendLanMedia(
        id: mediaId,
        toPeerId: peerId,
        fromPeerId: fromPeerId,
        mime: mime,
        filePath: filePath,
        enc: enc,
        encScheme: encScheme,
        durationMs: durationMs,
      );
    } catch (error) {
      _emit('LIBP2P_LAN_MEDIA_SEND_ERROR', <String, dynamic>{
        'id': mediaId,
        'error': error.toString(),
      });
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _setLocalDiscoveryInactive();
    _peersUpgradedToDirect.clear();
    _learnedTransport.clear();
    _presenceCache.clear();
    _warmAttempts.clear();
    _lanDialForwardedPeerIds.clear();
    _lanEmptyReResolvedPeerIds.clear();
    _suspectedDroppedPeers.clear();
    _lastNetworkRewarmAt = null;
    _resolvedAdvertQuicPort = null;
    _resolvedAdvertTcpPort = null;
    _localNetworkProven = false;
  }

  void disposeLocalService() {
    _localP2P?.dispose();
  }
}
