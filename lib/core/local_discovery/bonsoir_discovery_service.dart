import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/startup_timing.dart';

typedef BonsoirBroadcastFactory =
    BonsoirBroadcast Function(BonsoirService service);
typedef BonsoirDiscoveryFactory = BonsoirDiscovery Function(String type);

/// mDNS-based implementation of [LocalDiscoveryService] using the bonsoir package.
///
/// Advertises this device as `_mknoon._tcp` on the local network with the
/// peer ID in a TXT record, and discovers other mknoon peers.
class BonsoirDiscoveryService implements LocalDiscoveryService {
  static const String _serviceType = '_mknoon._tcp';
  static const String _serviceName = 'mknoon';

  /// Factory seams so host tests can drive the discovery contract with fake
  /// bonsoir objects; production defaults construct the real plugin types.
  /// `printLogs: false` is a deliberate iOS-crash mitigation — it stays
  /// inside the defaults.
  BonsoirDiscoveryService({
    BonsoirBroadcastFactory? createBroadcast,
    BonsoirDiscoveryFactory? createDiscovery,
    // iOS Local Network watchdog mitigation (see the gate notes below). The
    // probe window mirrors p2p_service's existing suspected-denial heuristic;
    // the backoff bounds how long the native (re)start stays gated before a
    // single re-probe.
    Duration suspectedDenialProbe = const Duration(seconds: 12),
    Duration suspectedDenialBackoff = const Duration(minutes: 5),
  }) : _createBroadcast =
           createBroadcast ??
           ((service) => BonsoirBroadcast(service: service, printLogs: false)),
       _createDiscovery =
           createDiscovery ??
           ((type) => BonsoirDiscovery(type: type, printLogs: false)),
       _suspectedDenialProbe = suspectedDenialProbe,
       _suspectedDenialBackoff = suspectedDenialBackoff;

  final BonsoirBroadcastFactory _createBroadcast;
  final BonsoirDiscoveryFactory _createDiscovery;

  // iOS Local Network main-thread watchdog mitigation.
  //
  // The native bonsoir broadcast `start()` runs a SYNCHRONOUS DNS-SD socket
  // read on the iOS main thread. When the Local Network permission is denied or
  // its prompt is pending, that read blocks past the 10s scene-update watchdog
  // and iOS SIGKILLs the app (0x8BADF00D / FRONTBOARD). The crash vector is the
  // RESTART: restartAdvertising (on resume / address-update) tears down and
  // re-`start()`s the broadcast, re-blocking. So once we suspect Local Network
  // is unavailable — advertising stayed active with zero discovered peers for
  // [_suspectedDenialProbe] — we set a backoff deadline and SKIP the native
  // (re)start until it lapses (a single re-probe), and clear it the instant a
  // real peer resolves (Local Network is provably working).
  final Duration _suspectedDenialProbe;
  final Duration _suspectedDenialBackoff;
  DateTime? _suspectedDeniedUntil;
  Timer? _denialProbeTimer;

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

  // FDC-S1 (c): peers whose FIRST mDNS resolve has already been timed, so the
  // resolve-complete timing event fires once per peer (re-resolves from the
  // refresh timer are skipped). Observation-only.
  final _fdcTimedResolvePeerIds = <String>{};
  bool _fdcFirstMdnsResolveEmitted = false;

  String? _ownPeerId;

  // B1.2: peers with a resolve currently in flight, so we never issue a second
  // overlapping `service.resolve(...)` for the same peer — each extra native
  // resolve is another use-after-free window.
  // Cleared on the resolved or lost event for that peer.
  final _resolvingPeerIds = <String>{};
  // B1.3/B1.4: set once teardown begins so no new resolves are issued while or
  // after discovery is being stopped.
  bool _stopping = false;

  /// FDC-11: builds the resolved peer's libp2p LAN multiaddrs from its
  /// advertised QUIC (+TCP) TXT ports. QUIC is preferred (FDC-S2 Option A); the
  /// TCP lane is the fallback. Returns empty when no libp2p port was advertised
  /// (older client / WS-only path). Built from the libp2p port, never the
  /// wsPort.
  static List<String> _buildLibp2pAddresses(
    String host,
    Map<String, String> attributes,
  ) {
    final proto = host.contains(':') ? 'ip6' : 'ip4';
    final addrs = <String>[];
    final quicPort = int.tryParse(attributes['quicPort'] ?? '');
    if (quicPort != null && quicPort > 0) {
      addrs.add('/$proto/$host/udp/$quicPort/quic-v1');
    }
    final tcpPort = int.tryParse(attributes['tcpPort'] ?? '');
    if (tcpPort != null && tcpPort > 0) {
      addrs.add('/$proto/$host/tcp/$tcpPort');
    }
    return addrs;
  }

  @override
  Future<void> startAdvertising(
    String peerId,
    int wsPort, {
    int? quicPort,
    int? tcpPort,
  }) async {
    _ownPeerId = peerId;
    _stopping = false;

    // iOS Local Network watchdog gate: while Local Network is suspected
    // unavailable, SKIP the native bonsoir (re)start so a blocking DNS-SD read
    // can't freeze the main thread past the 10s scene-update watchdog. This
    // returns early WITHOUT touching the broadcast/discovery objects (they were
    // already torn down by the restart's stopAdvertising), so discovery stays
    // dark until a later restart after the backoff lapses.
    final deniedUntil = _suspectedDeniedUntil;
    if (deniedUntil != null) {
      if (DateTime.now().toUtc().isBefore(deniedUntil)) {
        emitFlowEvent(
          layer: 'FL',
          event: 'LOCAL_MDNS_START_SKIPPED_SUSPECTED_DENIED',
          details: {'peerId': peerId},
        );
        return;
      }
      // Backoff lapsed → allow this start to re-probe Local Network.
      _suspectedDeniedUntil = null;
    }

    // Advertise our service. FDC-11: additively carry the libp2p QUIC (+TCP)
    // listen ports in the TXT so a same-WiFi peer can build the libp2p
    // LAN-direct multiaddr — the `wsPort` advert stays for the WS byte path.
    // (FDC-S2 hard requirement: advertise the libp2p QUIC port, NOT wsPort.)
    final service = BonsoirService(
      name: _serviceName,
      type: _serviceType,
      port: wsPort,
      attributes: {
        'peerId': peerId,
        if (quicPort != null) 'quicPort': '$quicPort',
        if (tcpPort != null) 'tcpPort': '$tcpPort',
      },
    );

    // Bonsoir's native iOS log formatting can crash while stringifying
    // resolved service payloads, so plugin-side logging stays disabled in
    // the default factory.
    _broadcast = _createBroadcast(service);
    await _broadcast!.ready;
    await _broadcast!.start();

    emitFlowEvent(
      layer: 'FL',
      event: 'LOCAL_MDNS_ADVERTISE_START',
      details: {'peerId': peerId, 'port': wsPort},
    );

    // Start discovery of other peers.
    _discovery = _createDiscovery(_serviceType);
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
        if (now.difference(e.value.discoveredAt) >
            const Duration(seconds: 15)) {
          final svc = _resolvable[e.key];
          if (svc != null) _issueResolve(e.key, svc, disc);
        }
      }
    });

    _armSuspectedDenialProbe();
  }

  /// (Re)arms the one-shot suspected-Local-Network-denial probe. If advertising
  /// is still active with ZERO discovered peers when it fires, sets a backoff
  /// deadline so the NEXT (re)start is skipped before its native DNS-SD read can
  /// block the main thread past the iOS watchdog. "Suspected" because a user
  /// genuinely alone on the LAN produces the same zero-peers signal — hence the
  /// bounded backoff + the immediate clear when a real peer resolves.
  void _armSuspectedDenialProbe() {
    _denialProbeTimer?.cancel();
    _denialProbeTimer = Timer(_suspectedDenialProbe, () {
      _denialProbeTimer = null;
      if (!_stopping && _discovery != null && _peers.isEmpty) {
        _suspectedDeniedUntil = DateTime.now().toUtc().add(
          _suspectedDenialBackoff,
        );
        emitFlowEvent(
          layer: 'FL',
          event: 'LOCAL_MDNS_SUSPECTED_DENIED_GATE_LATCHED',
          details: {'backoffMs': _suspectedDenialBackoff.inMilliseconds},
        );
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
        // B1.1: never resolve our OWN advertised service. (The own-peer skip
        // used to happen only on the resolved event, AFTER the resolve had
        // already been issued — wasted resolve + extra UAF window, doubled when
        // two iOS devices both advertise `_mknoon._tcp`.)
        if (foundPeerId == null || foundPeerId == _ownPeerId) break;
        // Bonsoir requires explicit resolution after a service is found.
        _issueResolve(foundPeerId, service, discovery);
        break;
      case BonsoirDiscoveryEventType.discoveryServiceResolved:
        final service = event.service as ResolvedBonsoirService;
        final peerId = service.attributes['peerId'];
        if (peerId == null || peerId == _ownPeerId) return;
        _resolvingPeerIds.remove(peerId); // B1.2: resolve completed.

        final host = service.host;
        if (host == null) return;

        // FDC-11: build the remote's libp2p LAN multiaddrs from its advertised
        // QUIC (+TCP) TXT ports — NEVER from service.port (= wsPort), which would
        // feed the libp2p dial the wrong port and re-trigger the FDC-S2
        // QUIC-identify "hang" as a config bug.
        final libp2pAddresses = _buildLibp2pAddresses(host, service.attributes);

        final peer = LocalPeer(
          peerId: peerId,
          host: host,
          port: service.port,
          discoveredAt: DateTime.now().toUtc(),
          libp2pAddresses: libp2pAddresses,
        );
        _peers[peerId] = peer;
        _peersController.add(Map.unmodifiable(_peers));

        // A real peer resolved → Local Network is provably working; clear any
        // suspected-denial gate so a subsequent restart is NOT skipped.
        _suspectedDeniedUntil = null;

        // Wake any discover-on-send resolve waiting for this peer.
        final pending = _pendingResolves.remove(peerId);
        if (pending != null && !pending.isCompleted) pending.complete(peer);

        emitFlowEvent(
          layer: 'FL',
          event: 'LOCAL_MDNS_PEER_FOUND',
          details: {'peerId': peerId, 'host': host, 'port': service.port},
        );

        // FDC-S1 (c): process-start → first mDNS resolve of a same-WiFi peer.
        // Once per distinct peer; the earliest across peers is the global
        // first-resolve metric (firstResolveOverall). Pair with
        // LOCAL_MDNS_DISCOVERY_START for the start→resolve delta.
        if (_fdcTimedResolvePeerIds.add(peerId)) {
          emitFlowEvent(
            layer: 'FL',
            event: 'FDC_COLDSTART_FIRST_MDNS_RESOLVE_TIMING',
            details: {
              'peerId': peerId,
              'sinceProcessStartMs':
                  StartupTiming.instance.sinceProcessStartMs() ?? -1,
              'firstResolveOverall': !_fdcFirstMdnsResolveEmitted,
            },
          );
          _fdcFirstMdnsResolveEmitted = true;
        }
        break;
      case BonsoirDiscoveryEventType.discoveryServiceLost:
        final service = event.service;
        final peerId = service?.attributes['peerId'];
        if (peerId == null) return;

        _markPeerLost(peerId);
        break;
      default:
        break;
    }
  }

  void _markPeerLost(String peerId) {
    _resolvable.remove(peerId);
    _resolvingPeerIds.remove(peerId); // B1.2: stop tracking a lost peer.

    final cachedPeer = _peers[peerId];
    if (cachedPeer != null && !cachedPeer.isStale(DateTime.now().toUtc())) {
      emitFlowEvent(
        layer: 'FL',
        event: 'LOCAL_MDNS_PEER_LOST_RETAINED',
        details: {'peerId': peerId},
      );
      return;
    }

    _peers.remove(peerId);
    _peersController.add(Map.unmodifiable(_peers));

    emitFlowEvent(
      layer: 'FL',
      event: 'LOCAL_MDNS_PEER_LOST',
      details: {'peerId': peerId},
    );
  }

  /// Issues a single-flight `resolve` for [peerId]: skips when teardown has
  /// begun (B1.4) or a resolve for the same peer is already in flight (B1.2).
  /// The in-flight flag clears on the resolved or lost event for that peer.
  void _issueResolve(
    String peerId,
    BonsoirService service,
    BonsoirDiscovery discovery,
  ) {
    if (_stopping || _discovery == null) return;
    if (!_resolvingPeerIds.add(peerId)) return;
    unawaited(service.resolve(discovery.serviceResolver));
  }

  @override
  Future<void> stopAdvertising() async {
    // B1.3: stop issuing resolves before tearing discovery down, so no new
    // native resolve dispatch source is created during or after teardown.
    _stopping = true;
    _resolvingPeerIds.clear();
    _refreshTimer?.cancel();
    _refreshTimer = null;
    // Cancel the session-scoped denial probe, but PRESERVE [_suspectedDeniedUntil]
    // — restartAdvertising calls stopAdvertising() then startAdvertising(), and
    // the gate must survive that teardown to skip the re-`start()` that blocks.
    _denialProbeTimer?.cancel();
    _denialProbeTimer = null;

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

  /// Test-only seam: seed the discovered-peers map directly so the real
  /// read-time staleness eviction in [getLocalPeer] can be exercised against a
  /// known [LocalPeer] (e.g. one with a back-dated `discoveredAt`). Production
  /// code never calls this — peers only enter via the mDNS resolved path.
  @visibleForTesting
  void debugSeedPeer(LocalPeer peer) {
    _peers[peer.peerId] = peer;
  }

  @visibleForTesting
  void debugMarkPeerLost(String peerId) {
    _markPeerLost(peerId);
  }

  /// True while the iOS Local Network watchdog gate is latched — the next
  /// native bonsoir (re)start will be skipped until the backoff lapses.
  @visibleForTesting
  bool get debugSuspectedLocalNetworkUnavailable {
    final until = _suspectedDeniedUntil;
    return until != null && DateTime.now().toUtc().isBefore(until);
  }

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

    // B1.4: never issue a resolve once teardown has begun / discovery is gone.
    if (_stopping || _discovery == null) return null;

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
      _issueResolve(peerId, svc, disc);
    }

    try {
      return await completer.future.timeout(timeout, onTimeout: () => null);
    } finally {
      // Clean up so we never leak completers across send attempts.
      _pendingResolves.remove(peerId);
      _resolvingPeerIds.remove(peerId);
    }
  }

  @override
  void dispose() {
    stopAdvertising();
    _peersController.close();
  }
}
