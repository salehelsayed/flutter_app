import 'dart:async';
import 'dart:math';

enum FakeGroupRouteMode { direct, relayOnly, circuitRouted }

typedef FakeGroupNetworkDelay = Future<void> Function(Duration delay);

/// Routes group messages between peers via topic-based fan-out.
///
/// Simulates GossipSub pubsub: when a peer publishes to a group topic,
/// all other subscribers receive the message. Legacy tests still use one
/// device per peer id, while same-user multi-device tests can register more
/// than one device for the same peer id.
class FakeGroupPubSubNetwork {
  FakeGroupPubSubNetwork({int randomSeed = 0, FakeGroupNetworkDelay? delay})
    : _randomSeed = randomSeed,
      _random = Random(randomSeed),
      _delay = delay ?? ((duration) => Future<void>.delayed(duration));

  final Map<String, Set<String>> _subscriptions = {};
  final Map<String, String> _devicePeerIds = {};
  final Map<String, Set<String>> _peerDeviceIds = {};
  final Map<String, StreamController<Map<String, dynamic>>> _deviceControllers =
      {};
  final Map<String, StreamController<Map<String, dynamic>>>
  _deviceReactionControllers = {};
  final Map<String, StreamController<Map<String, dynamic>>>
  _deviceDiagnosticControllers = {};
  final Set<String> _heldDeliveryDeviceIds = {};
  final Map<String, List<Map<String, dynamic>>> _heldMessageDeliveries = {};
  final Map<String, FakeGroupRouteMode> _deviceRouteModes = {};
  final List<Map<String, dynamic>> _deliveryRecords = [];

  final int _randomSeed;
  Random _random;
  final FakeGroupNetworkDelay _delay;

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
  int reactionPublishCallCount = 0;

  int _totalDeliveries = 0;
  int _totalReactionDeliveries = 0;

  /// Total deliveries across all subscribers.
  int get totalDeliveries => _totalDeliveries;
  int get totalReactionDeliveries => _totalReactionDeliveries;

  List<Map<String, dynamic>> get deliveryRecords => List.unmodifiable(
    _deliveryRecords.map((record) => Map<String, dynamic>.unmodifiable(record)),
  );

  void setRouteMode(String peerOrDeviceId, FakeGroupRouteMode mode) {
    final deviceIds = _resolveKnownDeliveryIds(peerOrDeviceId);
    for (final deviceId in deviceIds) {
      _deviceRouteModes[deviceId] = mode;
    }
  }

  FakeGroupRouteMode routeModeFor(String peerOrDeviceId) {
    final deviceIds = _resolveKnownDeliveryIds(peerOrDeviceId);
    for (final deviceId in deviceIds) {
      final mode = _deviceRouteModes[deviceId];
      if (mode != null) return mode;
    }
    return FakeGroupRouteMode.direct;
  }

  /// Total publishes (alias for [publishCallCount]).
  int get publishCount => publishCallCount;

  Set<String> registeredDeviceIdsFor(String peerId) {
    final deviceIds = _peerDeviceIds[peerId];
    if (deviceIds == null || deviceIds.isEmpty) {
      return const <String>{};
    }
    return Set<String>.unmodifiable(deviceIds);
  }

  /// Creates and returns the broadcast stream controller for a peer.
  ///
  /// Called once per test user during setup.
  StreamController<Map<String, dynamic>> registerPeer(
    String peerId, {
    String? deviceId,
  }) {
    final resolvedDeviceId = deviceId ?? peerId;
    final controller = StreamController<Map<String, dynamic>>.broadcast();
    _devicePeerIds[resolvedDeviceId] = peerId;
    _peerDeviceIds.putIfAbsent(peerId, () => <String>{}).add(resolvedDeviceId);
    _deviceControllers[resolvedDeviceId] = controller;
    return controller;
  }

  /// Creates and returns the broadcast reaction stream controller for a peer.
  StreamController<Map<String, dynamic>> registerReactionPeer(
    String peerId, {
    String? deviceId,
  }) {
    final resolvedDeviceId = deviceId ?? peerId;
    final controller = StreamController<Map<String, dynamic>>.broadcast();
    _devicePeerIds[resolvedDeviceId] = peerId;
    _peerDeviceIds.putIfAbsent(peerId, () => <String>{}).add(resolvedDeviceId);
    _deviceReactionControllers[resolvedDeviceId] = controller;
    return controller;
  }

  /// Creates and returns the broadcast diagnostic stream controller for a peer.
  StreamController<Map<String, dynamic>> registerDiagnosticPeer(
    String peerId, {
    String? deviceId,
  }) {
    final resolvedDeviceId = deviceId ?? peerId;
    final controller = StreamController<Map<String, dynamic>>.broadcast();
    _devicePeerIds[resolvedDeviceId] = peerId;
    _peerDeviceIds.putIfAbsent(peerId, () => <String>{}).add(resolvedDeviceId);
    _deviceDiagnosticControllers[resolvedDeviceId] = controller;
    return controller;
  }

  int emitPayloadParseFailureDiagnostic({
    required String receiverPeerOrDeviceId,
    required String groupId,
    required String senderPeerId,
    String envelopeType = 'group_message',
    String error = 'fake network payload parse failure',
  }) {
    var emitted = 0;
    for (final deviceId in _resolveKnownDeviceIds(receiverPeerOrDeviceId)) {
      final controller = _deviceDiagnosticControllers[deviceId];
      if (controller == null || controller.isClosed) continue;
      controller.add({
        'event': 'group:payload_parse_failed',
        'groupId': groupId,
        'senderId': senderPeerId,
        'envelopeType': envelopeType,
        'error': error,
      });
      emitted++;
    }
    return emitted;
  }

  int emitValidationRejectedDiagnostic({
    required String receiverPeerOrDeviceId,
    required String reason,
    required String groupHash,
    required String senderHash,
    required int keyEpoch,
    String envelopeType = 'group_message',
    String? transportPeerHash,
    String? localPeerHash,
  }) {
    var emitted = 0;
    for (final deviceId in _resolveKnownDeviceIds(receiverPeerOrDeviceId)) {
      final controller = _deviceDiagnosticControllers[deviceId];
      if (controller == null || controller.isClosed) continue;
      controller.add({
        'event': 'group:validation_rejected',
        'reason': reason,
        'groupHash': groupHash,
        'senderHash': senderHash,
        'transportPeerHash': ?transportPeerHash,
        'localPeerHash': ?localPeerHash,
        'envelopeType': envelopeType,
        'keyEpoch': keyEpoch,
      });
      emitted++;
    }
    return emitted;
  }

  /// Removes one registered device or every device for a peer id.
  void unregisterPeer(String peerOrDeviceId) {
    final deviceIds = _resolveDeviceIds(peerOrDeviceId);

    // Remove from all group subscriptions.
    for (final subscribers in _subscriptions.values) {
      subscribers.removeAll(deviceIds);
    }

    for (final deviceId in deviceIds) {
      final peerId = _devicePeerIds.remove(deviceId);
      if (peerId != null) {
        final peerDevices = _peerDeviceIds[peerId];
        peerDevices?.remove(deviceId);
        if (peerDevices != null && peerDevices.isEmpty) {
          _peerDeviceIds.remove(peerId);
        }
      }

      final controller = _deviceControllers.remove(deviceId);
      if (controller != null && !controller.isClosed) {
        controller.close();
      }

      final reactionController = _deviceReactionControllers.remove(deviceId);
      if (reactionController != null && !reactionController.isClosed) {
        reactionController.close();
      }

      final diagnosticController = _deviceDiagnosticControllers.remove(
        deviceId,
      );
      if (diagnosticController != null && !diagnosticController.isClosed) {
        diagnosticController.close();
      }

      _heldDeliveryDeviceIds.remove(deviceId);
      _heldMessageDeliveries.remove(deviceId);
    }
  }

  /// Holds future message deliveries for one device or all devices of a peer.
  void holdDeliveriesFor(String peerOrDeviceId) {
    for (final deviceId in _resolveKnownDeliveryIds(peerOrDeviceId)) {
      _heldDeliveryDeviceIds.add(deviceId);
    }
  }

  /// Releases held message deliveries, optionally reversing delivery order.
  Future<void> releaseHeldDeliveriesFor(
    String peerOrDeviceId, {
    bool reverse = false,
  }) async {
    for (final deviceId in _resolveKnownDeliveryIds(peerOrDeviceId)) {
      _heldDeliveryDeviceIds.remove(deviceId);
      final held = _heldMessageDeliveries.remove(deviceId) ?? const [];
      final deliveries = reverse ? held.reversed : held;
      final controller = _deviceControllers[deviceId];
      if (controller == null || controller.isClosed) continue;

      for (final envelope in deliveries) {
        if (deliveryDelay != null) {
          await _delay(deliveryDelay!);
        }

        controller.add(Map<String, dynamic>.from(envelope));
        _totalDeliveries++;

        if (duplicateOnDeliver) {
          controller.add(Map<String, dynamic>.from(envelope));
          _totalDeliveries++;
        }
      }
    }
  }

  int heldDeliveryCountFor(String peerOrDeviceId) {
    var total = 0;
    for (final deviceId in _resolveKnownDeliveryIds(peerOrDeviceId)) {
      total += _heldMessageDeliveries[deviceId]?.length ?? 0;
    }
    return total;
  }

  /// Adds a device (or a legacy one-device peer id) to the subscription set.
  void subscribe(String groupId, String peerOrDeviceId) {
    _subscriptions.putIfAbsent(groupId, () => <String>{}).add(peerOrDeviceId);
  }

  /// Removes one device or every device for a peer id from the subscription set.
  void unsubscribe(String groupId, String peerOrDeviceId) {
    final subscribers = _subscriptions[groupId];
    if (subscribers == null) return;

    if (subscribers.remove(peerOrDeviceId)) {
      return;
    }

    subscribers.removeAll(_resolveDeviceIds(peerOrDeviceId));
  }

  /// Fans out the envelope to all subscribers of [groupId] except the sender.
  ///
  /// The envelope is the raw map with keys: `groupId`, `senderId`,
  /// `senderUsername`, `keyEpoch`, `text`, `timestamp`.
  Future<void> publish(
    String groupId,
    String senderPeerId,
    Map<String, dynamic> envelope, {
    String? senderDeviceId,
  }) async {
    publishCallCount++;

    if (deliveryFails) return;

    final subscribers = _subscriptions[groupId];
    if (subscribers == null || subscribers.isEmpty) return;

    for (final subscriberId in subscribers) {
      final subscriberPeerId = _devicePeerIds[subscriberId] ?? subscriberId;
      if (senderDeviceId != null) {
        if (subscriberId == senderDeviceId) continue;
      } else if (subscriberPeerId == senderPeerId) {
        continue;
      }

      final controller = _deviceControllers[subscriberId];
      if (controller == null || controller.isClosed) continue;

      // Per-subscriber random drop.
      if (dropRate > 0.0 && _random.nextDouble() < dropRate) continue;

      if (deliveryDelay != null) {
        await _delay(deliveryDelay!);
      }

      final deliveredEnvelope = Map<String, dynamic>.from(envelope)
        ..putIfAbsent('senderDeviceId', () => senderDeviceId ?? senderPeerId)
        ..putIfAbsent('transportPeerId', () => senderDeviceId ?? senderPeerId);
      final senderRouteMode = routeModeFor(senderDeviceId ?? senderPeerId);
      final receiverRouteMode = routeModeFor(subscriberId);
      final deliveryRouteKind = _deliveryRouteKind(
        senderRouteMode,
        receiverRouteMode,
      );
      deliveredEnvelope
        ..putIfAbsent('senderRouteMode', () => senderRouteMode.name)
        ..putIfAbsent('receiverRouteMode', () => receiverRouteMode.name)
        ..putIfAbsent('deliveryRouteKind', () => deliveryRouteKind);
      _deliveryRecords.add({
        'groupId': groupId,
        'senderPeerId': senderPeerId,
        'senderDeviceId': senderDeviceId ?? senderPeerId,
        'receiverPeerId': subscriberPeerId,
        'receiverDeviceId': subscriberId,
        'senderRouteMode': senderRouteMode.name,
        'receiverRouteMode': receiverRouteMode.name,
        'deliveryRouteKind': deliveryRouteKind,
        'messageId': envelope['messageId'],
        'payloadGroupId': envelope['groupId'],
      });
      if (_heldDeliveryDeviceIds.contains(subscriberId)) {
        _heldMessageDeliveries
            .putIfAbsent(subscriberId, () => <Map<String, dynamic>>[])
            .add(Map<String, dynamic>.from(deliveredEnvelope));
        continue;
      }

      controller.add(deliveredEnvelope);
      _totalDeliveries++;

      // Duplicate injection if enabled.
      if (duplicateOnDeliver) {
        controller.add(Map<String, dynamic>.from(deliveredEnvelope));
        _totalDeliveries++;
      }
    }
  }

  /// Fans out the reaction envelope to all subscribers of [groupId] except the sender.
  Future<void> publishReaction(
    String groupId,
    String senderPeerId,
    Map<String, dynamic> envelope, {
    String? senderDeviceId,
  }) async {
    reactionPublishCallCount++;

    if (deliveryFails) return;

    final subscribers = _subscriptions[groupId];
    if (subscribers == null || subscribers.isEmpty) return;

    for (final subscriberId in subscribers) {
      final subscriberPeerId = _devicePeerIds[subscriberId] ?? subscriberId;
      if (senderDeviceId != null) {
        if (subscriberId == senderDeviceId) continue;
      } else if (subscriberPeerId == senderPeerId) {
        continue;
      }

      final controller = _deviceReactionControllers[subscriberId];
      if (controller == null || controller.isClosed) continue;

      if (dropRate > 0.0 && _random.nextDouble() < dropRate) continue;

      if (deliveryDelay != null) {
        await _delay(deliveryDelay!);
      }

      controller.add(envelope);
      _totalReactionDeliveries++;

      if (duplicateOnDeliver) {
        controller.add(Map<String, dynamic>.from(envelope));
        _totalReactionDeliveries++;
      }
    }
  }

  /// Whether a peer is subscribed to a group.
  bool isSubscribed(String groupId, String peerOrDeviceId) {
    final subscribers = _subscriptions[groupId];
    if (subscribers == null) return false;
    if (subscribers.contains(peerOrDeviceId)) return true;
    return _resolveDeviceIds(
      peerOrDeviceId,
    ).any((deviceId) => subscribers.contains(deviceId));
  }

  /// Returns the current subscriber list for a group.
  List<String> getSubscribers(String groupId) {
    final subscribers = _subscriptions[groupId];
    if (subscribers == null) return [];
    return subscribers
        .map((subscriberId) => _devicePeerIds[subscriberId] ?? subscriberId)
        .toList();
  }

  /// Resets all counters and fault-injection flags to defaults.
  void resetCounters() {
    publishCallCount = 0;
    reactionPublishCallCount = 0;
    _totalDeliveries = 0;
    _totalReactionDeliveries = 0;
    deliveryFails = false;
    deliveryDelay = null;
    dropRate = 0.0;
    duplicateOnDeliver = false;
    _random = Random(_randomSeed);
    _heldDeliveryDeviceIds.clear();
    _heldMessageDeliveries.clear();
    _deliveryRecords.clear();
  }

  Iterable<String> _resolveDeviceIds(String peerOrDeviceId) sync* {
    if (_devicePeerIds.containsKey(peerOrDeviceId)) {
      yield peerOrDeviceId;
      return;
    }

    yield* _peerDeviceIds[peerOrDeviceId] ?? const <String>{};
  }

  List<String> _resolveKnownDeviceIds(String peerOrDeviceId) {
    final deviceIds = _resolveDeviceIds(peerOrDeviceId).toList();
    if (deviceIds.isNotEmpty) return deviceIds;
    return [peerOrDeviceId];
  }

  List<String> _resolveKnownDeliveryIds(String peerOrDeviceId) {
    return <String>{
      peerOrDeviceId,
      ..._resolveKnownDeviceIds(peerOrDeviceId),
    }.toList(growable: false);
  }

  String _deliveryRouteKind(
    FakeGroupRouteMode senderMode,
    FakeGroupRouteMode receiverMode,
  ) {
    if (senderMode == FakeGroupRouteMode.relayOnly ||
        receiverMode == FakeGroupRouteMode.relayOnly) {
      return 'relay_only';
    }
    if (senderMode == FakeGroupRouteMode.circuitRouted ||
        receiverMode == FakeGroupRouteMode.circuitRouted) {
      return 'circuit_routed';
    }
    return 'direct';
  }
}
