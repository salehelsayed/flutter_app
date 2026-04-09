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

  final _peers = <String, LocalPeer>{};
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
  }

  void _handleDiscoveryEvent(BonsoirDiscoveryEvent event) {
    switch (event.type) {
      case BonsoirDiscoveryEventType.discoveryServiceFound:
        final discovery = _discovery;
        final service = event.service;
        if (discovery == null || service == null) return;
        // Bonsoir requires explicit resolution after a service is found.
        unawaited(service.resolve(discovery.serviceResolver));
        break;
      case BonsoirDiscoveryEventType.discoveryServiceResolved:
        final service = event.service as ResolvedBonsoirService;
        final peerId = service.attributes['peerId'];
        if (peerId == null || peerId == _ownPeerId) return;

        final host = service.host;
        if (host == null) return;

        _peers[peerId] = LocalPeer(
          peerId: peerId,
          host: host,
          port: service.port,
          discoveredAt: DateTime.now().toUtc(),
        );
        _peersController.add(Map.unmodifiable(_peers));

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
    await _broadcast?.stop();
    _broadcast = null;

    await _discoverySub?.cancel();
    _discoverySub = null;
    await _discovery?.stop();
    _discovery = null;

    _peers.clear();
    _peersController.add(Map.unmodifiable(_peers));

    emitFlowEvent(layer: 'FL', event: 'LOCAL_MDNS_ADVERTISE_STOP', details: {});
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
    stopAdvertising();
    _peersController.close();
  }
}
