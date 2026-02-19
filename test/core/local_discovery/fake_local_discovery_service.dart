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
  bool isLocalPeer(String peerId) => _peers.containsKey(peerId);

  @override
  LocalPeer? getLocalPeer(String peerId) => _peers[peerId];

  @override
  void dispose() {
    _peersController.close();
  }
}
