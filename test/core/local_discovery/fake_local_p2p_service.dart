import 'dart:async';

import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/core/local_discovery/local_p2p_service.dart';

/// Test fake for [LocalP2PService] that allows manual control over local
/// peer availability and message delivery.
class FakeLocalP2PService implements LocalP2PService {
  final _localPeers = <String, LocalPeer>{};
  final _messageController = StreamController<LocalChatMessage>.broadcast();
  final _peersController =
      StreamController<Map<String, LocalPeer>>.broadcast();

  bool sendWillSucceed = true;
  bool started = false;
  String? startedPeerId;

  final sentMessages = <_SentMessage>[];

  /// Register a peer as locally available.
  void addLocalPeer(String peerId, {String host = '192.168.1.100', int port = 9999}) {
    _localPeers[peerId] = LocalPeer(
      peerId: peerId,
      host: host,
      port: port,
      discoveredAt: DateTime.now().toUtc(),
    );
    _peersController.add(Map.unmodifiable(_localPeers));
  }

  /// Simulate receiving a message from a local peer.
  void emitLocalMessage(LocalChatMessage msg) {
    _messageController.add(msg);
  }

  @override
  Future<void> start(String peerId) async {
    started = true;
    startedPeerId = peerId;
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
  Stream<Map<String, LocalPeer>> get discoveredPeersStream =>
      _peersController.stream;

  @override
  Map<String, LocalPeer> get discoveredPeers =>
      Map.unmodifiable(_localPeers);

  @override
  bool isLocalPeer(String peerId) => _localPeers.containsKey(peerId);

  @override
  Future<bool> sendMessage(
    String peerId,
    String content,
    String fromPeerId,
  ) async {
    sentMessages.add(_SentMessage(
      peerId: peerId,
      content: content,
      fromPeerId: fromPeerId,
    ));
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
