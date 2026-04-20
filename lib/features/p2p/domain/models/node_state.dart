import 'connection_state.dart';

enum BadgeReadinessState { offline, connecting, online, onlineDotted }

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
    if (healthyRelayCount != null)
      result['healthyRelayCount'] = healthyRelayCount;
    if (watchdogRestartCount != null)
      result['watchdogRestartCount'] = watchdogRestartCount;
    if (needsGroupRecovery != null)
      result['needsGroupRecovery'] = needsGroupRecovery;
    if (featureFlags != null) result['featureFlags'] = featureFlags;
    result['sendCapabilityReady'] = sendCapabilityReady;
    result['inboxCapabilityReady'] = inboxCapabilityReady;

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
    return relayReady
        ? BadgeReadinessState.onlineDotted
        : BadgeReadinessState.online;
  }

  @override
  String toString() {
    return 'NodeState(peerId: $peerId, isStarted: $isStarted, '
        'connections: ${connections.length}, sendReady: $sendCapabilityReady, '
        'inboxReady: $inboxCapabilityReady'
        '${relayState != null ? ', relayState: $relayState' : ''})';
  }
}
