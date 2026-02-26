import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

import 'fake_p2p_service_integration.dart';

/// Routes messages between [FakeP2PService] instances.
///
/// Simulates a P2P relay: delivers to online peers or stores in offline inbox.
class FakeP2PNetwork {
  final Map<String, FakeP2PService> _nodes = {};
  final Map<String, List<Map<String, dynamic>>> _inboxes = {};

  /// When true, [storeInInbox] always returns false (simulates inbox outage).
  bool inboxDisabled = false;

  /// When set, [deliver] awaits this delay before delivery (for race tests).
  Duration? deliveryDelay;

  // -- Fault-injection hooks --

  /// When true, [deliver] always returns false (simulates delivery failure).
  bool deliveryFails = false;

  /// Delay before returning from [deliver] (simulates slow ACK).
  Duration? ackDelay;

  /// When true, [deliver] sends the message twice (simulates network duplicate).
  bool duplicateOnDeliver = false;

  /// Number of [deliver] calls made.
  int deliverCallCount = 0;

  /// Number of [storeInInbox] calls made.
  int storeInInboxCallCount = 0;

  void register(FakeP2PService node) {
    _nodes[node.peerId] = node;
  }

  void unregister(String peerId) {
    _nodes.remove(peerId);
  }

  /// Delivers a message from [fromPeerId] to [toPeerId].
  /// Returns true if the target node was found and online.
  Future<bool> deliver(String fromPeerId, String toPeerId, String content) async {
    deliverCallCount++;

    if (deliveryDelay != null) {
      await Future.delayed(deliveryDelay!);
    }

    if (ackDelay != null) {
      await Future.delayed(ackDelay!);
    }

    if (deliveryFails) return false;

    final target = _nodes[toPeerId];
    if (target == null) return false;

    final message = ChatMessage(
      from: fromPeerId,
      to: toPeerId,
      content: content,
      timestamp: DateTime.now().toUtc().toIso8601String(),
      isIncoming: true,
    );

    target.injectIncomingMessage(message);

    // Duplicate injection if enabled.
    if (duplicateOnDeliver) {
      target.injectIncomingMessage(
        ChatMessage(
          from: fromPeerId,
          to: toPeerId,
          content: content,
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
        ),
      );
    }

    return true;
  }

  /// Whether a peer is registered on this network.
  bool hasPeer(String peerId) => _nodes.containsKey(peerId);

  /// Store message for offline delivery.
  bool storeInInbox(String fromPeerId, String toPeerId, String content) {
    storeInInboxCallCount++;
    if (inboxDisabled) return false;

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

  /// Number of messages currently in a peer's inbox (without clearing).
  int inboxCount(String peerId) => _inboxes[peerId]?.length ?? 0;

  /// Resets all counters and fault-injection flags to defaults.
  void resetCounters() {
    deliverCallCount = 0;
    storeInInboxCallCount = 0;
    deliveryFails = false;
    ackDelay = null;
    duplicateOnDeliver = false;
    deliveryDelay = null;
    inboxDisabled = false;
  }
}
