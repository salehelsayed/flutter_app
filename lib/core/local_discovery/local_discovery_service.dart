/// Model representing a peer discovered on the local network via mDNS.
class LocalPeer {
  final String peerId;
  final String host;
  final int port;
  final DateTime discoveredAt;

  /// FDC-11: the remote's libp2p LAN multiaddrs (QUIC, optionally TCP), built
  /// from the bonsoir TXT `quicPort`/`tcpPort` attributes at resolve time, e.g.
  /// `/ip4/<host>/udp/<quicPort>/quic-v1`. Fed to the Go LAN-direct dial
  /// (`lan:peer_found`). Empty when the peer advertised no libp2p ports (an
  /// older client, or the WS-only path) — distinct from [port], which is the
  /// WebSocket port for the bespoke LAN byte path.
  final List<String> libp2pAddresses;

  const LocalPeer({
    required this.peerId,
    required this.host,
    required this.port,
    required this.discoveredAt,
    this.libp2pAddresses = const [],
  });

  /// Time after which a discovered entry is considered stale and skipped.
  ///
  /// 30s comfortably spans a typical mDNS announce cadence on home/office
  /// WiFi while expiring a peer that walked away within ~1 conversation turn.
  static const Duration ttl = Duration(seconds: 30);

  /// True when this entry is older than [ttl] relative to [nowUtc].
  ///
  /// Compare against `DateTime.now().toUtc()` to match the UTC write in
  /// [BonsoirDiscoveryService].
  bool isStale(DateTime nowUtc) => nowUtc.difference(discoveredAt) > ttl;

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

  /// True when the transferred bytes are an encrypted blob artifact
  /// (112: ciphertext on the LAN transport). The bytes must be staged for
  /// deferred decrypt, never promoted to canonical media.
  final bool enc;

  /// Blob encryption scheme advertised by the sender for enc transfers.
  final String? encScheme;

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
    this.enc = false,
    this.encScheme,
  });

  /// FDC-15: reconstructs a [LocalMediaReady] from a Go `media:lan_received`
  /// event payload (the receiver staged the ciphertext to a temp file and emits
  /// its path as [localPath]). The [enc]/[encScheme] fields MUST round-trip so
  /// the bytes are staged for decrypt-adopt and never rendered as raw plaintext.
  factory LocalMediaReady.fromJson(Map<String, dynamic> json) {
    return LocalMediaReady(
      id: json['id'] as String,
      from: json['from'] as String,
      to: json['to'] as String? ?? '',
      mime: json['mime'] as String? ?? 'application/octet-stream',
      size: (json['size'] as num?)?.toInt() ?? 0,
      localPath: json['localPath'] as String,
      sha256: json['sha256'] as String? ?? '',
      durationMs: (json['durationMs'] as num?)?.toInt(),
      waveform: (json['waveform'] as List<dynamic>?)
          ?.map((e) => (e as num).toDouble())
          .toList(),
      filename: json['filename'] as String?,
      enc: json['enc'] as bool? ?? false,
      encScheme: json['encScheme'] as String?,
    );
  }
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

  /// True when the offered bytes are an encrypted blob artifact (112): the
  /// mime is opaque by design, [sha256] covers the CIPHERTEXT, and the
  /// receiver must stage — never promote — the payload.
  final bool enc;

  /// Blob encryption scheme for enc offers.
  final String? encScheme;

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
    this.enc = false,
    this.encScheme,
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
        enc: json['enc'] as bool? ?? false,
        encScheme: json['encScheme'] as String?,
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
        if (enc) 'enc': enc,
        if (encScheme != null) 'encScheme': encScheme,
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
  /// FDC-11: [quicPort]/[tcpPort] are the libp2p host's own LAN listen ports
  /// (from `host.Addrs()`); advertised additively in the TXT so a same-WiFi peer
  /// can build the QUIC/TCP multiaddr for the libp2p LAN-direct dial. Null when
  /// the libp2p listen ports are unknown (the WS-only path is unaffected).
  Future<void> startAdvertising(
    String peerId,
    int wsPort, {
    int? quicPort,
    int? tcpPort,
  });

  /// Stop advertising and discovery.
  Future<void> stopAdvertising();

  /// 179: true while the iOS Local-Network watchdog gate is latched — the next
  /// native broadcast (re)start would be SKIPPED (see the suspected-denied gate
  /// in BonsoirDiscoveryService). Lets the libp2p-advert port self-heal avoid
  /// tearing down a working advert it cannot immediately re-register. Always
  /// false on platforms/implementations that never gate the broadcast.
  bool get isAdvertiseBroadcastGated;

  /// Stream that emits the current map of discovered peers whenever it changes.
  Stream<Map<String, LocalPeer>> get discoveredPeersStream;

  /// Current snapshot of discovered peers, keyed by peerId.
  Map<String, LocalPeer> get discoveredPeers;

  /// Returns true if the given peerId is currently visible on the local network.
  bool isLocalPeer(String peerId);

  /// Returns the [LocalPeer] for the given peerId, or null if not found.
  LocalPeer? getLocalPeer(String peerId);

  /// On-demand bounded resolve at send time.
  ///
  /// Returns the peer once it resolves on the LAN within [timeout], or null if
  /// it does not. Implementations must complete within [timeout] so the caller
  /// (the send race) stays inside its local budget. This lets a not-yet-
  /// discovered same-WiFi peer join the race during the cold-open window.
  Future<LocalPeer?> resolvePeer(String peerId, {required Duration timeout});

  /// Release all resources.
  void dispose();
}
