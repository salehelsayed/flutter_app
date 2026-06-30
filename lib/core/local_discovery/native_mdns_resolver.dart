import 'dart:async';

import 'package:flutter/services.dart';

/// 180: a peer resolved by the native Android mDNS resolver. Mirrors the shape a
/// bonsoir `ResolvedBonsoirService` provides (host + attributes) so it feeds the
/// SAME `_buildLibp2pAddresses(host, attributes)` → `LocalPeer` commit path.
///
/// [host] is a NUMERIC IP — the native resolver resolves the SRV target's A
/// record itself (PTR→SRV→TXT→A over a MulticastSocket with `IP_MULTICAST_IF`
/// pinned to wlan0), bypassing the Android `NsdManager` completion gate that
/// intermittently fails to resolve iOS `.local`-hostname adverts (spec 180).
class NativeResolvedPeer {
  final String peerId;
  final String host;
  final int port;
  final Map<String, String> attributes;

  const NativeResolvedPeer({
    required this.peerId,
    required this.host,
    required this.port,
    required this.attributes,
  });
}

/// 180: Android-only native mDNS resolver. The platform implementation owns a
/// `MulticastSocket` (outgoing interface pinned to wlan0) + a
/// `WifiManager.MulticastLock` and does PTR→SRV→TXT→A itself, so the Pixel
/// resolves iOS `_mknoon._tcp` `.local` adverts that NsdManager (upstream
/// bonsoir_android) intermittently never completes. Injected into
/// [BonsoirDiscoveryService]; it is NULL — and never started — on iOS, which
/// keeps the iOS bonsoir_darwin path + the 175/178 watchdog gates untouched.
abstract class NativeMdnsResolver {
  /// Resolved peers, each carrying a numeric host + the advertised TXT.
  Stream<NativeResolvedPeer> get resolvedPeers;

  /// Begin the periodic native multicast browse/resolve for [serviceType]
  /// (e.g. `_mknoon._tcp.local`). Acquires the MulticastLock.
  Future<void> start(String serviceType);

  /// Stop the browse, release the MulticastLock, close the socket.
  Future<void> stop();
}

/// Production implementation: a `MethodChannel` (start/stop) + an `EventChannel`
/// (resolved-peer stream), mirroring the GoBridge MethodChannel/EventChannel
/// split. The native side is `MdnsResolver.kt`. Never exercised in host tests —
/// host tests inject a fake; the native multicast leg is proven by the device-
/// proof (TC-180-07).
class PlatformChannelMdnsResolver implements NativeMdnsResolver {
  static const MethodChannel _method = MethodChannel('mknoon/mdns_resolver');
  static const EventChannel _events =
      EventChannel('mknoon/mdns_resolver/events');

  @override
  Stream<NativeResolvedPeer> get resolvedPeers =>
      _events.receiveBroadcastStream().map((dynamic event) {
        final map = (event as Map);
        final attrs = <String, String>{};
        final rawAttrs = map['attributes'];
        if (rawAttrs is Map) {
          rawAttrs.forEach((dynamic k, dynamic v) => attrs['$k'] = '$v');
        }
        return NativeResolvedPeer(
          peerId: '${map['peerId']}',
          host: '${map['host']}',
          port: (map['port'] as num?)?.toInt() ?? 0,
          attributes: attrs,
        );
      });

  @override
  Future<void> start(String serviceType) =>
      _method.invokeMethod<void>('start', {'serviceType': serviceType});

  @override
  Future<void> stop() => _method.invokeMethod<void>('stop');
}
