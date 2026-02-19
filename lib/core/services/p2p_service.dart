import 'dart:async';

import 'package:flutter_app/core/services/chat_message.dart';

/// Abstract P2P messaging service.
///
/// Implementations receive messages from the Go libp2p node
/// and optionally from local WiFi peers, merging them into a
/// single [messageStream].
abstract class P2PService {
  /// Stream of all incoming/outgoing messages (Go + local merged).
  Stream<ChatMessage> get messageStream;

  /// Start the P2P node with the given private key.
  Future<void> startNode({
    required String privateKeyHex,
    String? namespace,
    bool autoRegister = true,
  });

  /// Stop the P2P node.
  Future<void> stopNode();

  /// Get current node status as a map.
  Future<Map<String, dynamic>> nodeStatus();

  /// Send a message via the Go libp2p node.
  /// Returns the reply string (may be empty).
  Future<String> sendMessage(String peerId, String message);

  /// Dial a peer with optional addresses.
  Future<void> dialPeer(String peerId, {List<String>? addresses});

  /// Disconnect from a peer.
  Future<void> disconnectPeer(String peerId);

  /// Discover peers on a rendezvous namespace.
  Future<List<Map<String, dynamic>>> discoverPeers({String? namespace});

  /// Register on rendezvous.
  Future<void> rendezvousRegister({String? namespace});

  /// Store a message in the offline inbox.
  Future<void> inboxStore(String toPeerId, String message);

  /// Retrieve pending inbox messages.
  Future<List<Map<String, dynamic>>> inboxRetrieve();

  /// Register push token.
  Future<void> inboxRegisterToken(String token, String platform);

  /// Release resources.
  void dispose();
}
