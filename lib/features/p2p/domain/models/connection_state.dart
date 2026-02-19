/// Connection state representing a peer connection.
class ConnectionState {
  final String peerId;
  final List<String> multiaddrs;
  final String direction; // 'inbound' or 'outbound'
  final String status; // 'connected' or 'disconnected'
  final String? connectedAt;

  const ConnectionState({
    required this.peerId,
    required this.multiaddrs,
    required this.direction,
    required this.status,
    this.connectedAt,
  });

  factory ConnectionState.fromJson(Map<String, dynamic> json) {
    // Handle connectedAt that may come as int (Unix ms) or String (ISO8601)
    String? connectedAt;
    final ca = json['connectedAt'];
    if (ca is int) {
      connectedAt = DateTime.fromMillisecondsSinceEpoch(ca).toUtc().toIso8601String();
    } else if (ca is String) {
      connectedAt = ca;
    }

    return ConnectionState(
      peerId: json['peerId'] as String,
      multiaddrs: (json['multiaddrs'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      direction: json['direction']?.toString() ?? 'outbound',
      status: json['status']?.toString() ?? 'connected',
      connectedAt: connectedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'peerId': peerId,
      'multiaddrs': multiaddrs,
      'direction': direction,
      'status': status,
      if (connectedAt != null) 'connectedAt': connectedAt,
    };
  }

  ConnectionState copyWith({
    String? peerId,
    List<String>? multiaddrs,
    String? direction,
    String? status,
    String? connectedAt,
  }) {
    return ConnectionState(
      peerId: peerId ?? this.peerId,
      multiaddrs: multiaddrs ?? this.multiaddrs,
      direction: direction ?? this.direction,
      status: status ?? this.status,
      connectedAt: connectedAt ?? this.connectedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ConnectionState &&
        other.peerId == peerId &&
        other.direction == direction &&
        other.status == status;
  }

  @override
  int get hashCode => Object.hash(peerId, direction, status);

  @override
  String toString() {
    return 'ConnectionState(peerId: $peerId, direction: $direction, status: $status)';
  }
}
