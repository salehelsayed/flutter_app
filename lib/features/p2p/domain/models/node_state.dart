import 'connection_state.dart';

/// Node state representing the P2P node status.
class NodeState {
  final String? peerId;
  final bool isStarted;
  final List<String> listenAddresses;
  final List<String> circuitAddresses;
  final List<ConnectionState> connections;
  final List<String> registeredNamespaces;

  const NodeState({
    this.peerId,
    required this.isStarted,
    this.listenAddresses = const [],
    this.circuitAddresses = const [],
    this.connections = const [],
    this.registeredNamespaces = const [],
  });

  /// Stopped node state constant.
  static const stopped = NodeState(isStarted: false);

  factory NodeState.fromJson(Map<String, dynamic> json) {
    return NodeState(
      peerId: json['peerId'] as String?,
      isStarted: json['isStarted'] as bool? ?? false,
      listenAddresses: (json['listenAddresses'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      circuitAddresses: (json['circuitAddresses'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      connections: (json['connections'] as List<dynamic>?)
              ?.map((e) => ConnectionState.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      registeredNamespaces: (json['registeredNamespaces'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'peerId': peerId,
      'isStarted': isStarted,
      'listenAddresses': listenAddresses,
      'circuitAddresses': circuitAddresses,
      'connections': connections.map((c) => c.toJson()).toList(),
      'registeredNamespaces': registeredNamespaces,
    };
  }

  NodeState copyWith({
    String? peerId,
    bool? isStarted,
    List<String>? listenAddresses,
    List<String>? circuitAddresses,
    List<ConnectionState>? connections,
    List<String>? registeredNamespaces,
  }) {
    return NodeState(
      peerId: peerId ?? this.peerId,
      isStarted: isStarted ?? this.isStarted,
      listenAddresses: listenAddresses ?? this.listenAddresses,
      circuitAddresses: circuitAddresses ?? this.circuitAddresses,
      connections: connections ?? this.connections,
      registeredNamespaces: registeredNamespaces ?? this.registeredNamespaces,
    );
  }

  @override
  String toString() {
    return 'NodeState(peerId: $peerId, isStarted: $isStarted, connections: ${connections.length})';
  }
}
