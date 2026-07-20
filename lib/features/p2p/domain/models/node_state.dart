import 'connection_state.dart';

enum BadgeReadinessState { offline, connecting, online, onlineDotted, onlineDirect }

/// Node state representing the P2P node status.
class NodeState {
  final String? peerId;
  final bool isStarted;
  final List<String> listenAddresses;
  final List<String> circuitAddresses;
  final List<ConnectionState> connections;
  final List<String> registeredNamespaces;

  /// Phase 4: Relay session state fields (additive — null when absent).
  final String? relayState;
  final int? healthyRelayCount;
  final int? watchdogRestartCount;
  final bool? needsGroupRecovery;
  final Map<String, bool>? featureFlags;
  final bool sendCapabilityReady;
  final bool inboxCapabilityReady;

  /// FDC-14: self "directly reachable" axis — true when the node holds a live
  /// non-relay (LAN/direct) path. Defaults false; the live bridge does not yet
  /// emit it, so existing states keep their current badge (no silent promotion).
  /// directReady producer = FDC-14b follow-on (derives from FDC-02 ranked-race
  /// live LAN/direct + FDC-11 libp2p LAN-direct dial); default false until then.
  final bool directReady;

  const NodeState({
    this.peerId,
    required this.isStarted,
    this.listenAddresses = const [],
    this.circuitAddresses = const [],
    this.connections = const [],
    this.registeredNamespaces = const [],
    this.relayState,
    this.healthyRelayCount,
    this.watchdogRestartCount,
    this.needsGroupRecovery,
    this.featureFlags,
    this.sendCapabilityReady = false,
    this.inboxCapabilityReady = false,
    this.directReady = false,
  });

  /// Stopped node state constant.
  static const stopped = NodeState(isStarted: false);

  factory NodeState.fromJson(Map<String, dynamic> json) {
    return NodeState(
      peerId: json['peerId'] as String?,
      isStarted: json['isStarted'] as bool? ?? false,
      listenAddresses:
          (json['listenAddresses'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      circuitAddresses:
          (json['circuitAddresses'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      connections:
          (json['connections'] as List<dynamic>?)
              ?.map((e) => ConnectionState.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      registeredNamespaces:
          (json['registeredNamespaces'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      // Phase 4: Parse relay session fields when present.
      relayState: json['relayState'] as String?,
      healthyRelayCount: (json['healthyRelayCount'] as num?)?.toInt(),
      watchdogRestartCount: (json['watchdogRestartCount'] as num?)?.toInt(),
      needsGroupRecovery: json['needsGroupRecovery'] as bool?,
      featureFlags: (json['featureFlags'] as Map<String, dynamic>?)?.map(
        (key, value) => MapEntry(key, value == true),
      ),
      sendCapabilityReady: json['sendCapabilityReady'] == true,
      inboxCapabilityReady: json['inboxCapabilityReady'] == true,
      directReady: json['directReady'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    final result = <String, dynamic>{
      'peerId': peerId,
      'isStarted': isStarted,
      'listenAddresses': listenAddresses,
      'circuitAddresses': circuitAddresses,
      'connections': connections.map((c) => c.toJson()).toList(),
      'registeredNamespaces': registeredNamespaces,
    };

    // Phase 4: Include relay session fields when present.
    if (relayState != null) result['relayState'] = relayState;
    if (healthyRelayCount != null) {
      result['healthyRelayCount'] = healthyRelayCount;
    }
    if (watchdogRestartCount != null) {
      result['watchdogRestartCount'] = watchdogRestartCount;
    }
    if (needsGroupRecovery != null) {
      result['needsGroupRecovery'] = needsGroupRecovery;
    }
    if (featureFlags != null) result['featureFlags'] = featureFlags;
    result['sendCapabilityReady'] = sendCapabilityReady;
    result['inboxCapabilityReady'] = inboxCapabilityReady;
    // Always emit (Pattern B, like send/inbox capability) — directReady is a
    // non-nullable bool, not an omit-when-null nullable field.
    result['directReady'] = directReady;

    return result;
  }

  NodeState copyWith({
    String? peerId,
    bool? isStarted,
    List<String>? listenAddresses,
    List<String>? circuitAddresses,
    List<ConnectionState>? connections,
    List<String>? registeredNamespaces,
    String? relayState,
    int? healthyRelayCount,
    int? watchdogRestartCount,
    bool? needsGroupRecovery,
    Map<String, bool>? featureFlags,
    bool? sendCapabilityReady,
    bool? inboxCapabilityReady,
    bool? directReady,
  }) {
    return NodeState(
      peerId: peerId ?? this.peerId,
      isStarted: isStarted ?? this.isStarted,
      listenAddresses: listenAddresses ?? this.listenAddresses,
      circuitAddresses: circuitAddresses ?? this.circuitAddresses,
      connections: connections ?? this.connections,
      registeredNamespaces: registeredNamespaces ?? this.registeredNamespaces,
      relayState: relayState ?? this.relayState,
      healthyRelayCount: healthyRelayCount ?? this.healthyRelayCount,
      watchdogRestartCount: watchdogRestartCount ?? this.watchdogRestartCount,
      needsGroupRecovery: needsGroupRecovery ?? this.needsGroupRecovery,
      featureFlags: featureFlags ?? this.featureFlags,
      sendCapabilityReady: sendCapabilityReady ?? this.sendCapabilityReady,
      inboxCapabilityReady: inboxCapabilityReady ?? this.inboxCapabilityReady,
      directReady: directReady ?? this.directReady,
    );
  }

  bool get relayReady {
    if (!isStarted) return false;
    if (relayState != null) {
      return relayState == 'online';
    }
    return circuitAddresses.isNotEmpty;
  }

  bool get usabilityReady =>
      isStarted && sendCapabilityReady && inboxCapabilityReady;

  BadgeReadinessState get badgeReadinessState {
    if (!isStarted) return BadgeReadinessState.offline;
    if (!usabilityReady) return BadgeReadinessState.connecting;
    // FDC-14: a live direct/LAN path is "more connected" than relay-reserved
    // and is decoupled from it (holds even when relay is not ready). Ranked
    // above onlineDotted; never bypasses the usabilityReady gate above.
    if (directReady) return BadgeReadinessState.onlineDirect;
    return relayReady
        ? BadgeReadinessState.onlineDotted
        : BadgeReadinessState.online;
  }

  @override
  String toString() {
    return 'NodeState(peerId: $peerId, isStarted: $isStarted, '
        'connections: ${connections.length}, sendReady: $sendCapabilityReady, '
        'inboxReady: $inboxCapabilityReady'
        '${relayState != null ? ', relayState: $relayState' : ''}'
        '${directReady ? ', directReady: true' : ''})';
  }
}
