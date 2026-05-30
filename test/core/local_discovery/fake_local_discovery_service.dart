import 'dart:async';

import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';

/// Test fake for [LocalDiscoveryService] that allows manual control of
/// discovered peers without actual mDNS.
class FakeLocalDiscoveryService implements LocalDiscoveryService {
  final _peers = <String, LocalPeer>{};
  final _peersController =
      StreamController<Map<String, LocalPeer>>.broadcast();

  String? advertisedPeerId;
  int? advertisedPort;
  bool isAdvertising = false;

  /// Simulate discovering a peer on the local network.
  void addPeer(LocalPeer peer) {
    _peers[peer.peerId] = peer;
    _peersController.add(Map.unmodifiable(_peers));
  }

  /// Simulate a peer leaving the local network.
  void removePeer(String peerId) {
    _peers.remove(peerId);
    _peersController.add(Map.unmodifiable(_peers));
  }

  @override
  Future<void> startAdvertising(String peerId, int wsPort) async {
    advertisedPeerId = peerId;
    advertisedPort = wsPort;
    isAdvertising = true;
  }

  @override
  Future<void> stopAdvertising() async {
    isAdvertising = false;
    _peers.clear();
    _peersController.add(Map.unmodifiable(_peers));
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
    // Mirror the production freshness filter so the fake exercises the same
    // stale-skip behaviour the send-path race relies on.
    if (p.isStale(DateTime.now().toUtc())) {
      _peers.remove(peerId);
      _peersController.add(Map.unmodifiable(_peers));
      return null;
    }
    return p;
  }

  /// When set, [resolvePeer] adds this peer (flipping [isLocalPeer] -> true)
  /// after [resolveDelay] to simulate discover-on-send. Cleared after use.
  LocalPeer? resolvesTo;
  Duration resolveDelay = Duration.zero;
  int resolvePeerCallCount = 0;

  @override
  Future<LocalPeer?> resolvePeer(
    String peerId, {
    required Duration timeout,
  }) async {
    resolvePeerCallCount++;
    // Fast path: already fresh in the map.
    final fresh = getLocalPeer(peerId);
    if (fresh != null) return fresh;

    final pending = resolvesTo;
    if (pending == null) return null;
    resolvesTo = null;

    final completer = Completer<LocalPeer?>();
    Timer(resolveDelay, () {
      addPeer(pending);
      if (!completer.isCompleted) completer.complete(pending);
    });
    return completer.future.timeout(timeout, onTimeout: () => null);
  }

  @override
  void dispose() {
    _peersController.close();
  }
}
