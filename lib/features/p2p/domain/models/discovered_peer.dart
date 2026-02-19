/// Discovered peer model from rendezvous discovery.
class DiscoveredPeer {
  final String id;
  final List<String> addresses;

  const DiscoveredPeer({
    required this.id,
    required this.addresses,
  });

  factory DiscoveredPeer.fromJson(Map<String, dynamic> json) {
    return DiscoveredPeer(
      id: (json['peerId'] ?? json['id']) as String,
      addresses: (json['addresses'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'addresses': addresses,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DiscoveredPeer && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'DiscoveredPeer(id: $id, addresses: ${addresses.length})';
  }
}
