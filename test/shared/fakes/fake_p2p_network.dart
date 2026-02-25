import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

import 'fake_p2p_service_integration.dart';

/// Routes messages between [FakeP2PService] instances.
///
/// Simulates a P2P relay: delivers to online peers or stores in offline inbox.
class FakeP2PNetwork {
  final Map<String, FakeP2PService> _nodes = {};
  final Map<String, List<Map<String, dynamic>>> _inboxes = {};

  void register(FakeP2PService node) {
    _nodes[node.peerId] = node;
  }

  void unregister(String peerId) {
    _nodes.remove(peerId);
  }

  /// Delivers a message from [fromPeerId] to [toPeerId].
  /// Returns true if the target node was found.
  bool deliver(String fromPeerId, String toPeerId, String content) {
    final target = _nodes[toPeerId];
    if (target == null) return false;

    target.injectIncomingMessage(
      ChatMessage(
        from: fromPeerId,
        to: toPeerId,
        content: content,
        timestamp: DateTime.now().toUtc().toIso8601String(),
        isIncoming: true,
      ),
    );
    return true;
  }

  /// Whether a peer is registered on this network.
  bool hasPeer(String peerId) => _nodes.containsKey(peerId);

  /// Store message for offline delivery.
  bool storeInInbox(String fromPeerId, String toPeerId, String content) {
    final inbox = _inboxes.putIfAbsent(toPeerId, () => []);
    inbox.add({
      'from': fromPeerId,
      'message': content,
      'timestamp': DateTime.now().toUtc().millisecondsSinceEpoch,
    });
    return true;
  }

  /// Retrieve and clear inbox for a peer.
  List<Map<String, dynamic>> retrieveInbox(String peerId) {
    final messages = _inboxes.remove(peerId) ?? [];
    return List<Map<String, dynamic>>.from(messages);
  }
}
