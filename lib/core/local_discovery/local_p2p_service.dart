import 'dart:async';

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

  LocalP2PService({
    required LocalDiscoveryService discovery,
    required LocalWsServer wsServer,
  }) : _discovery = discovery,
       _wsServer = wsServer;

  /// Start the local WebSocket server and begin mDNS advertising/discovery.
  Future<void> start(String peerId) async {
    _peerId = peerId;
    final port = await _wsServer.start();

    emitFlowEvent(
      layer: 'FL',
      event: 'LOCAL_P2P_SERVICE_START',
      details: {'peerId': peerId, 'wsPort': port},
    );

    await _discovery.startAdvertising(peerId, port);
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
    await _discovery.startAdvertising(peerId, port);

    emitFlowEvent(
      layer: 'FL',
      event: 'LOCAL_P2P_SERVICE_RESTART_ADVERTISING',
      details: {'peerId': peerId, 'wsPort': port},
    );
  }

  /// Stream of messages received from local peers.
  Stream<LocalChatMessage> get localMessageStream => _wsServer.messageStream;

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
  }) async =>
      (await _discovery.resolvePeer(peerId, timeout: timeout)) != null;

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
    final peer = _discovery.getLocalPeer(peerId);
    if (peer == null) return false;

    return _wsServer.sendMessage(
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
    );
  }

  void dispose() {
    _discovery.dispose();
    _wsServer.dispose();
  }
}
