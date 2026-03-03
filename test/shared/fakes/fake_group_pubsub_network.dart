import 'dart:async';
import 'dart:math';

/// Routes group messages between peers via topic-based fan-out.
///
/// Simulates GossipSub pubsub: when a peer publishes to a group topic,
/// all other subscribers receive the message. The sender never receives
/// their own message.
class FakeGroupPubSubNetwork {
  final Map<String, Set<String>> _subscriptions = {};
  final Map<String, StreamController<Map<String, dynamic>>> _peerControllers =
      {};

  final _random = Random();

  // -- Fault-injection hooks --

  /// When true, [publish] silently drops all messages.
  bool deliveryFails = false;

  /// Delay before each delivery (for race tests).
  Duration? deliveryDelay;

  /// Probability of dropping delivery to each individual subscriber (0.0-1.0).
  double dropRate = 0.0;

  /// When true, deliver each message twice to each subscriber.
  bool duplicateOnDeliver = false;

  /// Number of [publish] calls made.
  int publishCallCount = 0;

  int _totalDeliveries = 0;

  /// Total deliveries across all subscribers.
  int get totalDeliveries => _totalDeliveries;

  /// Total publishes (alias for [publishCallCount]).
  int get publishCount => publishCallCount;

  /// Creates and returns the broadcast stream controller for a peer.
  ///
  /// Called once per test user during setup.
  StreamController<Map<String, dynamic>> registerPeer(String peerId) {
    final controller = StreamController<Map<String, dynamic>>.broadcast();
    _peerControllers[peerId] = controller;
    return controller;
  }

  /// Removes a peer from all subscriptions and closes their controller.
  void unregisterPeer(String peerId) {
    // Remove from all group subscriptions.
    for (final subscribers in _subscriptions.values) {
      subscribers.remove(peerId);
    }

    final controller = _peerControllers.remove(peerId);
    if (controller != null && !controller.isClosed) {
      controller.close();
    }
  }

  /// Adds a peer to the subscription set for a group.
  void subscribe(String groupId, String peerId) {
    _subscriptions.putIfAbsent(groupId, () => <String>{}).add(peerId);
  }

  /// Removes a peer from the subscription set for a group.
  void unsubscribe(String groupId, String peerId) {
    _subscriptions[groupId]?.remove(peerId);
  }

  /// Fans out the envelope to all subscribers of [groupId] except the sender.
  ///
  /// The envelope is the raw map with keys: `groupId`, `senderId`,
  /// `senderUsername`, `keyEpoch`, `text`, `timestamp`.
  Future<void> publish(
    String groupId,
    String senderPeerId,
    Map<String, dynamic> envelope,
  ) async {
    publishCallCount++;

    if (deliveryFails) return;

    final subscribers = _subscriptions[groupId];
    if (subscribers == null || subscribers.isEmpty) return;

    for (final peerId in subscribers) {
      // Sender does not receive their own message (GossipSub semantics).
      if (peerId == senderPeerId) continue;

      final controller = _peerControllers[peerId];
      if (controller == null || controller.isClosed) continue;

      // Per-subscriber random drop.
      if (dropRate > 0.0 && _random.nextDouble() < dropRate) continue;

      if (deliveryDelay != null) {
        await Future.delayed(deliveryDelay!);
      }

      controller.add(envelope);
      _totalDeliveries++;

      // Duplicate injection if enabled.
      if (duplicateOnDeliver) {
        controller.add(Map<String, dynamic>.from(envelope));
        _totalDeliveries++;
      }
    }
  }

  /// Whether a peer is subscribed to a group.
  bool isSubscribed(String groupId, String peerId) {
    return _subscriptions[groupId]?.contains(peerId) ?? false;
  }

  /// Returns the current subscriber list for a group.
  List<String> getSubscribers(String groupId) {
    return _subscriptions[groupId]?.toList() ?? [];
  }

  /// Resets all counters and fault-injection flags to defaults.
  void resetCounters() {
    publishCallCount = 0;
    _totalDeliveries = 0;
    deliveryFails = false;
    deliveryDelay = null;
    dropRate = 0.0;
    duplicateOnDeliver = false;
  }
}
