import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/local_discovery/bonsoir_discovery_service.dart';
import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';

/// U-P2-ttl (real eviction) — NET-REL-01 P2 read-time staleness eviction.
///
/// The plain-host [LocalPeer.isStale] predicate is covered by
/// local_peer_ttl_test.dart. This suite instead drives the REAL read-time
/// eviction inside [BonsoirDiscoveryService.getLocalPeer]: a stale entry must
/// be removed from the live map and `getLocalPeer` must return null (so the
/// send race skips the local leg), while a fresh entry must be returned and
/// retained. A back-dated `discoveredAt` (older than [LocalPeer.ttl]) makes the
/// entry reliably stale at call time without touching production wall-clock use.
void main() {
  LocalPeer peerDiscoveredAt(String peerId, DateTime at) => LocalPeer(
        peerId: peerId,
        host: '192.168.1.42',
        port: 51234,
        discoveredAt: at,
      );

  group('BonsoirDiscoveryService.getLocalPeer read-time eviction', () {
    test('stale entry is evicted from the live map and returns null', () {
      final service = BonsoirDiscoveryService();
      // Back-date past the 30s TTL so isStale(now) is true at call time.
      final stale = peerDiscoveredAt(
        'peer-stale',
        DateTime.now().toUtc().subtract(const Duration(seconds: 31)),
      );
      service.debugSeedPeer(stale);

      // Precondition: the entry is present in the live snapshot before read.
      expect(service.discoveredPeers.containsKey('peer-stale'), isTrue);

      // The real read-time eviction must drop it and return null.
      expect(service.getLocalPeer('peer-stale'), isNull);

      // And it must be gone from the live map (proves eviction, not just a
      // null return from the predicate guard).
      expect(service.discoveredPeers.containsKey('peer-stale'), isFalse);
    });

    test('stale eviction is reflected on the discoveredPeers stream', () async {
      final service = BonsoirDiscoveryService();
      final stale = peerDiscoveredAt(
        'peer-stale',
        DateTime.now().toUtc().subtract(const Duration(seconds: 31)),
      );
      service.debugSeedPeer(stale);

      final emitted = <Map<String, LocalPeer>>[];
      final sub = service.discoveredPeersStream.listen(emitted.add);

      expect(service.getLocalPeer('peer-stale'), isNull);
      // Let the broadcast controller dispatch.
      await Future<void>.delayed(Duration.zero);

      // The eviction pushed an updated (now-empty) snapshot.
      expect(emitted, isNotEmpty);
      expect(emitted.last.containsKey('peer-stale'), isFalse);

      await sub.cancel();
    });

    test('fresh entry is returned and retained (negative control)', () {
      final service = BonsoirDiscoveryService();
      final fresh = peerDiscoveredAt(
        'peer-fresh',
        DateTime.now().toUtc(),
      );
      service.debugSeedPeer(fresh);

      final got = service.getLocalPeer('peer-fresh');
      expect(got, isNotNull);
      expect(got!.peerId, 'peer-fresh');

      // Still present — a fresh entry must NOT be evicted.
      expect(service.discoveredPeers.containsKey('peer-fresh'), isTrue);
    });

    test('isLocalPeer goes false for a stale entry via the same eviction', () {
      final service = BonsoirDiscoveryService();
      final stale = peerDiscoveredAt(
        'peer-stale',
        DateTime.now().toUtc().subtract(const Duration(seconds: 31)),
      );
      service.debugSeedPeer(stale);

      // isLocalPeer delegates to getLocalPeer, so it must observe the eviction.
      expect(service.isLocalPeer('peer-stale'), isFalse);
      expect(service.discoveredPeers.containsKey('peer-stale'), isFalse);
    });

    test('unknown peer returns null without touching other entries', () {
      final service = BonsoirDiscoveryService();
      final fresh = peerDiscoveredAt('peer-fresh', DateTime.now().toUtc());
      service.debugSeedPeer(fresh);

      expect(service.getLocalPeer('peer-absent'), isNull);
      // The fresh, unrelated entry is untouched.
      expect(service.discoveredPeers.containsKey('peer-fresh'), isTrue);
    });
  });
}
