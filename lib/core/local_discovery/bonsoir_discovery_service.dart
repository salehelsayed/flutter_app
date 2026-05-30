import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// mDNS-based implementation of [LocalDiscoveryService] using the bonsoir package.
///
/// Advertises this device as `_mknoon._tcp` on the local network with the
/// peer ID in a TXT record, and discovers other mknoon peers.
class BonsoirDiscoveryService implements LocalDiscoveryService {
  static const String _serviceType = '_mknoon._tcp';
  static const String _serviceName = 'mknoon';

  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _discoverySub;
  Timer? _refreshTimer;

  final _peers = <String, LocalPeer>{};
  // Retain the found BonsoirService handles so we can re-resolve a peer's
  // host:port without waiting for a fresh mDNS `found` event.
  final _resolvable = <String, BonsoirService>{};
  // Pending discover-on-send resolves keyed by peerId, completed from the
  // discoveryServiceResolved path when the awaited peer first appears.
  final _pendingResolves = <String, Completer<LocalPeer?>>{};
  final _peersController = StreamController<Map<String, LocalPeer>>.broadcast();

  String? _ownPeerId;

  @override
  Future<void> startAdvertising(String peerId, int wsPort) async {
    _ownPeerId = peerId;

    // Advertise our service.
    final service = BonsoirService(
      name: _serviceName,
      type: _serviceType,
      port: wsPort,
      attributes: {'peerId': peerId},
    );

    // Bonsoir's native iOS log formatting can crash while stringifying
    // resolved service payloads, so keep plugin-side logging disabled here.
    _broadcast = BonsoirBroadcast(service: service, printLogs: false);
    await _broadcast!.ready;
    await _broadcast!.start();

    emitFlowEvent(
      layer: 'FL',
      event: 'LOCAL_MDNS_ADVERTISE_START',
      details: {'peerId': peerId, 'port': wsPort},
    );

    // Start discovery of other peers.
    _discovery = BonsoirDiscovery(type: _serviceType, printLogs: false);
    await _discovery!.ready;
    _discoverySub?.cancel();
    _discoverySub = _discovery!.eventStream!.listen(_handleDiscoveryEvent);
    await _discovery!.start();

    emitFlowEvent(
      layer: 'FL',
      event: 'LOCAL_MDNS_DISCOVERY_START',
      details: {},
    );

    // Periodically re-resolve entries that are getting old (older than 15s)
    // so their host:port stays fresh before the 30s TTL expires them. The
    // re-resolve completes through the existing discoveryServiceResolved path,
    // which overwrites discoveredAt — refreshing freshness for free. Reuses the
    // existing BonsoirService + serviceResolver, so no new bonsoir object is
    // constructed (the printLogs:false crash mitigation is unaffected).
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      final now = DateTime.now().toUtc();
      final disc = _discovery;
      if (disc == null) return;
      for (final e in _peers.entries.toList()) {
        if (now.difference(e.value.discoveredAt) > const Duration(seconds: 15)) {
          final svc = _resolvable[e.key];
          if (svc != null) unawaited(svc.resolve(disc.serviceResolver));
        }
      }
    });
  }

  void _handleDiscoveryEvent(BonsoirDiscoveryEvent event) {
    switch (event.type) {
      case BonsoirDiscoveryEventType.discoveryServiceFound:
        final discovery = _discovery;
        final service = event.service;
        if (discovery == null || service == null) return;
        // Retain the handle so periodic re-resolution can refresh host:port.
        final foundPeerId = service.attributes['peerId'];
        if (foundPeerId != null) _resolvable[foundPeerId] = service;
        // Bonsoir requires explicit resolution after a service is found.
        unawaited(service.resolve(discovery.serviceResolver));
        break;
      case BonsoirDiscoveryEventType.discoveryServiceResolved:
        final service = event.service as ResolvedBonsoirService;
        final peerId = service.attributes['peerId'];
        if (peerId == null || peerId == _ownPeerId) return;

        final host = service.host;
        if (host == null) return;

        final peer = LocalPeer(
          peerId: peerId,
          host: host,
          port: service.port,
          discoveredAt: DateTime.now().toUtc(),
        );
        _peers[peerId] = peer;
        _peersController.add(Map.unmodifiable(_peers));

        // Wake any discover-on-send resolve waiting for this peer.
        final pending = _pendingResolves.remove(peerId);
        if (pending != null && !pending.isCompleted) pending.complete(peer);

        emitFlowEvent(
          layer: 'FL',
          event: 'LOCAL_MDNS_PEER_FOUND',
          details: {'peerId': peerId, 'host': host, 'port': service.port},
        );
        break;
      case BonsoirDiscoveryEventType.discoveryServiceLost:
        final service = event.service;
        final peerId = service?.attributes['peerId'];
        if (peerId == null) return;

        _peers.remove(peerId);
        _resolvable.remove(peerId);
        _peersController.add(Map.unmodifiable(_peers));

        emitFlowEvent(
          layer: 'FL',
          event: 'LOCAL_MDNS_PEER_LOST',
          details: {'peerId': peerId},
        );
        break;
      default:
        break;
    }
  }

  @override
  Future<void> stopAdvertising() async {
    _refreshTimer?.cancel();
    _refreshTimer = null;

    await _broadcast?.stop();
    _broadcast = null;

    await _discoverySub?.cancel();
    _discoverySub = null;
    await _discovery?.stop();
    _discovery = null;

    _peers.clear();
    _resolvable.clear();
    // Resolve any in-flight discover-on-send waiters to null so they don't
    // hang past shutdown (their own .timeout would otherwise carry them).
    for (final c in _pendingResolves.values) {
      if (!c.isCompleted) c.complete(null);
    }
    _pendingResolves.clear();
    _peersController.add(Map.unmodifiable(_peers));

    emitFlowEvent(layer: 'FL', event: 'LOCAL_MDNS_ADVERTISE_STOP', details: {});
  }

  @override
  Stream<Map<String, LocalPeer>> get discoveredPeersStream =>
      _peersController.stream;

  @override
  Map<String, LocalPeer> get discoveredPeers => Map.unmodifiable(_peers);

  @override
  bool isLocalPeer(String peerId) => getLocalPeer(peerId) != null;

  @override
  LocalPeer? getLocalPeer(String peerId) {
    final p = _peers[peerId];
    if (p == null) return null;
    // Freshness filter at read: a stale host:port would otherwise burn the
    // full local send budget on a peer that has left the WiFi. Drop it so the
    // send path skips local and the parallel direct leg carries the message.
    if (p.isStale(DateTime.now().toUtc())) {
      _peers.remove(peerId);
      _resolvable.remove(peerId);
      _peersController.add(Map.unmodifiable(_peers));

      emitFlowEvent(
        layer: 'FL',
        event: 'LOCAL_MDNS_PEER_STALE',
        details: {'peerId': peerId},
      );
      return null;
    }
    return p;
  }

  @override
  Future<LocalPeer?> resolvePeer(
    String peerId, {
    required Duration timeout,
  }) async {
    // Fast path: already fresh in the map — no need to wait for mDNS.
    final fresh = getLocalPeer(peerId);
    if (fresh != null) return fresh;

    emitFlowEvent(
      layer: 'FL',
      event: 'LOCAL_MDNS_RESOLVE_ON_SEND',
      details: {'peerId': peerId, 'timeoutMs': timeout.inMilliseconds},
    );

    // Register a completer the resolved path will wake when the peer appears.
    // If an mDNS `found` for this peer was already seen, re-resolve its handle
    // to nudge discovery; otherwise we simply wait for a fresh announce.
    final completer = _pendingResolves[peerId] ??= Completer<LocalPeer?>();
    final svc = _resolvable[peerId];
    final disc = _discovery;
    if (svc != null && disc != null) {
      unawaited(svc.resolve(disc.serviceResolver));
    }

    try {
      return await completer.future.timeout(
        timeout,
        onTimeout: () => null,
      );
    } finally {
      // Clean up so we never leak completers across send attempts.
      _pendingResolves.remove(peerId);
    }
  }

  @override
  void dispose() {
    stopAdvertising();
    _peersController.close();
  }
}
