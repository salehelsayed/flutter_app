import 'dart:async';

import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// No-op local discovery used by harnesses that do not exercise mDNS.
class DisabledLocalDiscoveryService implements LocalDiscoveryService {
  final _peersController = StreamController<Map<String, LocalPeer>>.broadcast();

  @override
  Future<void> startAdvertising(String peerId, int wsPort) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'LOCAL_MDNS_DISABLED',
      details: {'peerId': peerId, 'port': wsPort},
    );
  }

  @override
  Future<void> stopAdvertising() async {
    _peersController.add(const <String, LocalPeer>{});
  }

  @override
  Stream<Map<String, LocalPeer>> get discoveredPeersStream =>
      _peersController.stream;

  @override
  Map<String, LocalPeer> get discoveredPeers => const <String, LocalPeer>{};

  @override
  bool isLocalPeer(String peerId) => false;

  @override
  LocalPeer? getLocalPeer(String peerId) => null;

  @override
  void dispose() {
    _peersController.close();
  }
}
