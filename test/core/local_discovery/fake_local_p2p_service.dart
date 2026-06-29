import 'dart:async';

import 'package:flutter_app/core/local_discovery/lan_ack.dart';
import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/core/local_discovery/local_p2p_service.dart';

/// Test fake for [LocalP2PService] that allows manual control over local
/// peer availability and message delivery.
class FakeLocalP2PService implements LocalP2PService {
  final _localPeers = <String, LocalPeer>{};
  final _messageController = StreamController<LocalChatMessage>.broadcast();
  final _peersController = StreamController<Map<String, LocalPeer>>.broadcast();

  bool sendWillSucceed = true;
  LanSendAck? sendMessageAck;
  bool started = false;
  String? startedPeerId;
  LanInboundChatCommitHandler? inboundChatCommitHandler;

  final sentMessages = <_SentMessage>[];

  /// Register a peer as locally available.
  void addLocalPeer(
    String peerId, {
    String host = '192.168.1.100',
    int port = 9999,
    List<String> libp2pAddresses = const [],
  }) {
    _localPeers[peerId] = LocalPeer(
      peerId: peerId,
      host: host,
      port: port,
      discoveredAt: DateTime.now().toUtc(),
      libp2pAddresses: libp2pAddresses,
    );
    _peersController.add(Map.unmodifiable(_localPeers));
  }

  /// Remove a previously-registered peer and emit the updated set.
  void removeLocalPeer(String peerId) {
    _localPeers.remove(peerId);
    _peersController.add(Map.unmodifiable(_localPeers));
  }

  /// Simulate receiving a message from a local peer.
  void emitLocalMessage(LocalChatMessage msg) {
    _messageController.add(msg);
  }

  int? startedQuicPort;
  int? startedTcpPort;

  // FDC-11 (174): captures the self-heal re-advertise driven by
  // _handleAddressesUpdated once the host surfaces its resolved LAN ports.
  int? updatedQuicPort;
  int? updatedTcpPort;
  int updateLibp2pPortsCallCount = 0;

  @override
  Future<void> start(String peerId, {int? quicPort, int? tcpPort}) async {
    started = true;
    startedPeerId = peerId;
    startedQuicPort = quicPort;
    startedTcpPort = tcpPort;
  }

  @override
  Future<void> updateLibp2pPorts({int? quicPort, int? tcpPort}) async {
    updateLibp2pPortsCallCount++;
    updatedQuicPort = quicPort;
    updatedTcpPort = tcpPort;
  }

  @override
  Future<void> stop() async {
    started = false;
  }

  @override
  Future<void> restartAdvertising() async {}

  @override
  Stream<LocalChatMessage> get localMessageStream => _messageController.stream;

  @override
  void configureInboundChatCommitHandler(LanInboundChatCommitHandler handler) {
    inboundChatCommitHandler = handler;
  }

  @override
  Stream<Map<String, LocalPeer>> get discoveredPeersStream =>
      _peersController.stream;

  @override
  Map<String, LocalPeer> get discoveredPeers => Map.unmodifiable(_localPeers);

  @override
  bool isLocalPeer(String peerId) => _localPeers.containsKey(peerId);

  /// When set, [discoverLocalPeer] registers this peer after [resolveDelay],
  /// simulating a bounded mDNS resolve at send time. Cleared after use.
  LocalPeer? resolvesTo;
  Duration resolveDelay = Duration.zero;
  int discoverLocalPeerCallCount = 0;

  @override
  Future<bool> discoverLocalPeer(
    String peerId, {
    required Duration timeout,
  }) async {
    discoverLocalPeerCallCount++;
    if (_localPeers.containsKey(peerId)) return true;
    final pending = resolvesTo;
    if (pending == null) return false;
    resolvesTo = null;
    final completer = Completer<bool>();
    Timer(resolveDelay, () {
      _localPeers[pending.peerId] = pending;
      _peersController.add(Map.unmodifiable(_localPeers));
      if (!completer.isCompleted) completer.complete(true);
    });
    return completer.future.timeout(timeout, onTimeout: () => false);
  }

  @override
  Future<bool> sendMessage(
    String peerId,
    String content,
    String fromPeerId, {
    int? timeoutMs,
  }) async =>
      await sendMessageDetailed(
        peerId,
        content,
        fromPeerId,
        timeoutMs: timeoutMs,
      ) ==
      LanSendAck.committed;

  @override
  Future<LanSendAck> sendMessageDetailed(
    String peerId,
    String content,
    String fromPeerId, {
    int? timeoutMs,
  }) async {
    sentMessages.add(
      _SentMessage(peerId: peerId, content: content, fromPeerId: fromPeerId),
    );
    return sendMessageAck ??
        (sendWillSucceed ? LanSendAck.committed : LanSendAck.failed);
  }

  @override
  Stream<LocalMediaReady>? get mediaReadyStream => null;

  @override
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
    return sendWillSucceed;
  }

  @override
  void dispose() {
    _messageController.close();
    _peersController.close();
  }
}

class _SentMessage {
  final String peerId;
  final String content;
  final String fromPeerId;

  _SentMessage({
    required this.peerId,
    required this.content,
    required this.fromPeerId,
  });
}
