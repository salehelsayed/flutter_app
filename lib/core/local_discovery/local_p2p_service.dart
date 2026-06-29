import 'dart:async';

import 'package:flutter_app/core/local_discovery/lan_ack.dart';
import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/core/local_discovery/local_ws_server.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// Composed facade that pairs [LocalDiscoveryService] (mDNS) with
/// [LocalWsServer] (direct messaging) for local WiFi peer-to-peer.
///
/// Usage:
/// 1. Call [start] with the device's peerId after identity is available.
/// 2. Listen to [localMessageStream] for incoming local messages.
/// 3. Use [isLocalPeer] / [sendMessage] for local-first delivery.
/// 4. Call [stop] on app background / shutdown.
class LocalP2PService {
  final LocalDiscoveryService _discovery;
  final LocalWsServer _wsServer;

  String? _peerId;
  // FDC-11: the libp2p host's own LAN listen ports (from NodeState.listenAddresses),
  // advertised in the bonsoir TXT alongside wsPort so a same-WiFi peer can build
  // the libp2p LAN-direct multiaddr. Cached so restartAdvertising re-publishes them.
  int? _quicPort;
  int? _tcpPort;

  LocalP2PService({
    required LocalDiscoveryService discovery,
    required LocalWsServer wsServer,
  }) : _discovery = discovery,
       _wsServer = wsServer;

  /// Start the local WebSocket server and begin mDNS advertising/discovery.
  /// FDC-11: [quicPort]/[tcpPort] are the libp2p host's LAN listen ports; when
  /// known they are advertised additively (the wsPort advert/WS path is
  /// unchanged). Null when the libp2p ports are not yet known (cold-start before
  /// the host reports its listen addresses) — a later restartAdvertising
  /// re-publishes once they are.
  Future<void> start(String peerId, {int? quicPort, int? tcpPort}) async {
    _peerId = peerId;
    _quicPort = quicPort;
    _tcpPort = tcpPort;
    final port = await _wsServer.start();

    emitFlowEvent(
      layer: 'FL',
      event: 'LOCAL_P2P_SERVICE_START',
      details: {
        'peerId': peerId,
        'wsPort': port,
        'quicPort': ?quicPort,
        'tcpPort': ?tcpPort,
      },
    );

    await _discovery.startAdvertising(
      peerId,
      port,
      quicPort: quicPort,
      tcpPort: tcpPort,
    );
  }

  /// Stop mDNS and the WebSocket server.
  Future<void> stop() async {
    await _discovery.stopAdvertising();
    await _wsServer.stop();

    emitFlowEvent(layer: 'FL', event: 'LOCAL_P2P_SERVICE_STOP', details: {});
  }

  /// Restart mDNS advertising (e.g. after iOS returns from background).
  Future<void> restartAdvertising() async {
    final peerId = _peerId;
    final port = _wsServer.port;
    if (peerId == null || port == null) return;

    await _discovery.stopAdvertising();
    await _discovery.startAdvertising(
      peerId,
      port,
      quicPort: _quicPort,
      tcpPort: _tcpPort,
    );

    emitFlowEvent(
      layer: 'FL',
      event: 'LOCAL_P2P_SERVICE_RESTART_ADVERTISING',
      details: {
        'peerId': peerId,
        'wsPort': port,
        'quicPort': ?_quicPort,
        'tcpPort': ?_tcpPort,
      },
    );
  }

  /// FDC-11 (174): re-advertise the bonsoir TXT with freshly-resolved libp2p
  /// QUIC/TCP LAN ports. The FDC-07 cold-start early seam derives the ports
  /// from the node's listen addresses before the host has surfaced its resolved
  /// LAN addrs, so [start] advertises null; once the host reports them (via the
  /// addresses:updated push), the P2P service calls this to self-heal the
  /// advert. No-op when the ports are unchanged so repeated pushes do not churn
  /// advertising. The cache is updated so a later [restartAdvertising]
  /// re-publishes the fresh ports rather than the stale cold-start null. The
  /// wsPort advert/WS messaging path is untouched.
  Future<void> updateLibp2pPorts({int? quicPort, int? tcpPort}) async {
    if (quicPort == _quicPort && tcpPort == _tcpPort) return;
    _quicPort = quicPort;
    _tcpPort = tcpPort;

    final peerId = _peerId;
    final port = _wsServer.port;
    if (peerId == null || port == null) return;

    await _discovery.stopAdvertising();
    await _discovery.startAdvertising(
      peerId,
      port,
      quicPort: _quicPort,
      tcpPort: _tcpPort,
    );

    emitFlowEvent(
      layer: 'FL',
      event: 'FDC_LAN_ADVERT_PORTS',
      details: {
        'quicPort': quicPort ?? -1,
        'tcpPort': tcpPort ?? -1,
        'source': 'update',
      },
    );
  }

  /// Stream of messages received from local peers.
  Stream<LocalChatMessage> get localMessageStream => _wsServer.messageStream;

  /// Configure the receiver-side commit handler for durable inbound LAN chat.
  void configureInboundChatCommitHandler(LanInboundChatCommitHandler handler) {
    _wsServer.configureInboundChatCommitHandler(handler);
  }

  /// Stream of discovered peer map changes.
  Stream<Map<String, LocalPeer>> get discoveredPeersStream =>
      _discovery.discoveredPeersStream;

  /// Current snapshot of discovered peers.
  Map<String, LocalPeer> get discoveredPeers => _discovery.discoveredPeers;

  /// Returns true if the given peerId is visible on the local network.
  bool isLocalPeer(String peerId) => _discovery.isLocalPeer(peerId);

  /// Bounded on-demand discovery at send time. Returns true if the peer
  /// became visible on the LAN within [timeout]. Lets a not-yet-discovered
  /// same-WiFi peer join the send race during the cold-open window.
  Future<bool> discoverLocalPeer(
    String peerId, {
    required Duration timeout,
  }) async => (await _discovery.resolvePeer(peerId, timeout: timeout)) != null;

  /// Stream of media files received via local WiFi transfer.
  Stream<LocalMediaReady>? get mediaReadyStream => _wsServer.mediaReadyStream;

  /// Send a message to a local peer. Returns true if the peer acknowledged.
  ///
  /// Returns false if the peer is not on the local network or the send fails.
  Future<bool> sendMessage(
    String peerId,
    String content,
    String fromPeerId, {
    int? timeoutMs,
  }) async {
    return await sendMessageDetailed(
          peerId,
          content,
          fromPeerId,
          timeoutMs: timeoutMs,
        ) ==
        LanSendAck.committed;
  }

  /// Send a message to a local peer and return the detailed LAN ack result.
  ///
  /// Returns [LanSendAck.failed] if the peer is not on the local network or the
  /// send fails before a peer ack is classified.
  Future<LanSendAck> sendMessageDetailed(
    String peerId,
    String content,
    String fromPeerId, {
    int? timeoutMs,
  }) async {
    final peer = _discovery.getLocalPeer(peerId);
    if (peer == null) return LanSendAck.failed;

    return _wsServer.sendMessageWithAck(
      peer.host,
      peer.port,
      content,
      fromPeerId,
      peerId,
      timeoutMs: timeoutMs,
    );
  }

  /// Send a media file to a local peer. Returns true if uploaded + verified.
  ///
  /// Returns false if the peer is not on the local network or the transfer fails.
  Future<bool> sendMedia({
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
    final peer = _discovery.getLocalPeer(peerId);
    if (peer == null) return false;

    return _wsServer.sendMedia(
      host: peer.host,
      port: peer.port,
      toPeerId: peerId,
      filePath: filePath,
      mediaId: mediaId,
      mime: mime,
      fromPeerId: fromPeerId,
      durationMs: durationMs,
      waveform: waveform,
      filename: filename,
      enc: enc,
      encScheme: encScheme,
    );
  }

  void dispose() {
    _discovery.dispose();
    _wsServer.dispose();
  }
}
