import 'dart:async';

import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';

import 'fake_p2p_network.dart';

/// Per-user P2P service backed by [FakeP2PNetwork].
///
/// Supports online/offline toggling and offline inbox drain.
class FakeP2PService implements P2PService {
  final String peerId;
  final FakeP2PNetwork network;
  final _messageController = StreamController<ChatMessage>.broadcast();

  /// First N [sendMessageWithReply] calls return `sent: false`.
  int sendFailCount = 0;
  int _sendAttempts = 0;

  /// Peers currently visible on local WiFi (for WiFi send tests).
  final Set<String> localPeers = {};

  /// Whether [sendLocalMessage] succeeds when the peer is local.
  bool localSendResult = true;

  /// How many times [sendLocalMessage] has been called.
  int localSendCallCount = 0;

  /// Current transport mode for test assertions.
  /// Can be 'wifi', 'relay', or 'inbox'. Defaults to 'relay'.
  String transportMode = 'relay';

  /// Peers that we consider "connected" for [isConnectedToPeer].
  final Set<String> connectedPeers = {};

  /// Whether this node is registered (online) on the network.
  bool get isOnline => network.hasPeer(peerId);

  /// Simulate a transport switch. Updates [transportMode] and adjusts
  /// [localPeers] accordingly.
  void simulateTransportSwitch(String newTransport) {
    transportMode = newTransport;
    // When switching away from wifi, clear local peers to reflect reality
    if (newTransport != 'wifi') {
      localPeers.clear();
    }
  }

  FakeP2PService({required this.peerId, required this.network}) {
    network.register(this);
  }

  void setOnline(bool online) {
    if (online) {
      network.register(this);
    } else {
      network.unregister(peerId);
    }
  }

  void injectIncomingMessage(ChatMessage message) {
    _messageController.add(message);
  }

  @override
  Future<void> drainOfflineInbox() async {
    await drainOfflineInboxCount();
  }

  Future<int> drainOfflineInboxCount() async {
    final messages = await retrieveInbox();
    for (final message in messages) {
      final ts = message['timestamp'];
      final timestamp = ts is int
          ? DateTime.fromMillisecondsSinceEpoch(ts, isUtc: true)
              .toIso8601String()
          : DateTime.now().toUtc().toIso8601String();
      injectIncomingMessage(
        ChatMessage(
          from: message['from'] as String,
          to: peerId,
          content: message['message'] as String,
          timestamp: timestamp,
          isIncoming: true,
        ),
      );
    }
    return messages.length;
  }

  @override
  NodeState get currentState => NodeState(isStarted: true, peerId: peerId);

  @override
  Stream<NodeState> get stateStream => const Stream.empty();

  @override
  Stream<ChatMessage> get messageStream => _messageController.stream;

  @override
  Future<bool> sendMessage(String targetPeerId, String message) async {
    return network.deliver(peerId, targetPeerId, message);
  }

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String targetPeerId,
    String message,
  ) async {
    _sendAttempts++;
    if (_sendAttempts <= sendFailCount) {
      return const SendMessageResult(sent: false);
    }
    final delivered = await network.deliver(peerId, targetPeerId, message);
    return SendMessageResult(
      sent: delivered,
      reply: delivered ? 'received: $message' : null,
    );
  }

  @override
  Future<bool> startNode(String privateKeyBase64, String peerId) async => true;

  @override
  Future<bool> stopNode() async => true;

  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId) async {
    if (network.hasPeer(peerId)) {
      return DiscoveredPeer(
        id: peerId,
        addresses: ['/ip4/127.0.0.1/tcp/4001/p2p/$peerId'],
      );
    }
    return null;
  }

  @override
  Future<bool> dialPeer(String peerId, {List<String>? addresses}) async =>
      network.hasPeer(peerId);

  @override
  Future<bool> storeInInbox(String toPeerId, String message) async {
    return network.storeInInbox(peerId, toPeerId, message);
  }

  @override
  Future<List<Map<String, dynamic>>> retrieveInbox() async {
    return network.retrieveInbox(peerId);
  }

  @override
  Future<bool> registerPushToken(String token, String platform) async => true;

  @override
  Future<void> performImmediateHealthCheck() async {}

  @override
  bool isConnectedToPeer(String peerId) => connectedPeers.contains(peerId);

  @override
  bool isLocalPeer(String peerId) => localPeers.contains(peerId);

  @override
  Future<bool> sendLocalMessage(
      String peerId, String message, String fromPeerId) async {
    localSendCallCount++;
    if (!localSendResult) return false;
    return network.deliver(fromPeerId, peerId, message);
  }

  @override
  Future<bool> startNodeCore(String privateKeyBase64, String peerId) async =>
      false;

  @override
  Future<void> warmBackground() async {}

  @override
  void dispose() {
    _messageController.close();
  }
}
