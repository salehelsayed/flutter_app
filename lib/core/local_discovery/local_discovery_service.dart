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

/// Event emitted when a media file has been received via local WiFi transfer.
class LocalMediaReady {
  final String id;
  final String from;
  final String to;
  final String mime;
  final int size;
  final String localPath;
  final String sha256;
  final int? durationMs;
  final List<double>? waveform;
  final String? filename;

  const LocalMediaReady({
    required this.id,
    required this.from,
    required this.to,
    required this.mime,
    required this.size,
    required this.localPath,
    required this.sha256,
    this.durationMs,
    this.waveform,
    this.filename,
  });
}

/// Offer from a sender to transfer a media file locally.
class MediaOffer {
  final String id;
  final String from;
  final String to;
  final String mime;
  final int size;
  final String sha256;
  final String token;
  final String nonce;
  final int? durationMs;
  final List<double>? waveform;
  final String? filename;

  const MediaOffer({
    required this.id,
    required this.from,
    required this.to,
    required this.mime,
    required this.size,
    required this.sha256,
    required this.token,
    required this.nonce,
    this.durationMs,
    this.waveform,
    this.filename,
  });

  factory MediaOffer.fromJson(Map<String, dynamic> json) => MediaOffer(
        id: json['id'] as String,
        from: json['from'] as String,
        to: json['to'] as String,
        mime: json['mime'] as String,
        size: json['size'] as int,
        sha256: json['sha256'] as String,
        token: json['token'] as String,
        nonce: json['nonce'] as String,
        durationMs: json['durationMs'] as int?,
        waveform: (json['waveform'] as List<dynamic>?)
            ?.map((e) => (e as num).toDouble())
            .toList(),
        filename: json['filename'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'type': 'media_offer',
        'id': id,
        'from': from,
        'to': to,
        'mime': mime,
        'size': size,
        'sha256': sha256,
        'token': token,
        'nonce': nonce,
        if (durationMs != null) 'durationMs': durationMs,
        if (waveform != null) 'waveform': waveform,
        if (filename != null) 'filename': filename,
      };
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
