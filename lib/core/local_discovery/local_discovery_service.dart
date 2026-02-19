/// Model representing a peer discovered on the local network via mDNS.
class LocalPeer {
  final String peerId;
  final String host;
  final int port;
  final DateTime discoveredAt;

  const LocalPeer({
    required this.peerId,
    required this.host,
    required this.port,
    required this.discoveredAt,
  });

  @override
  String toString() =>
      'LocalPeer(peerId: $peerId, host: $host, port: $port)';
}

/// A message received over a local WebSocket connection.
class LocalChatMessage {
  final String from;
  final String to;
  final String content;
  final DateTime timestamp;
  final bool isIncoming;

  const LocalChatMessage({
    required this.from,
    required this.to,
    required this.content,
    required this.timestamp,
    required this.isIncoming,
  });
}

/// Abstract interface for local network peer discovery.
///
/// Implementations use mDNS (Bonjour/NSD) to advertise this device's
/// WebSocket server and discover peers on the same WiFi network.
abstract class LocalDiscoveryService {
  /// Start advertising this device on the local network.
  ///
  /// [peerId] is the libp2p peer ID to advertise in the TXT record.
  /// [wsPort] is the local WebSocket server port to advertise.
  Future<void> startAdvertising(String peerId, int wsPort);

  /// Stop advertising and discovery.
  Future<void> stopAdvertising();

  /// Stream that emits the current map of discovered peers whenever it changes.
  Stream<Map<String, LocalPeer>> get discoveredPeersStream;

  /// Current snapshot of discovered peers, keyed by peerId.
  Map<String, LocalPeer> get discoveredPeers;

  /// Returns true if the given peerId is currently visible on the local network.
  bool isLocalPeer(String peerId);

  /// Returns the [LocalPeer] for the given peerId, or null if not found.
  LocalPeer? getLocalPeer(String peerId);

  /// Release all resources.
  void dispose();
}
