import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';

/// U-P2-ttl — TTL / freshness predicate on the discovered-peers map.
///
/// Plain host test: constructs [LocalPeer] entries with synthetic
/// `discoveredAt` timestamps and asserts the [LocalPeer.isStale] boundary.
void main() {
  LocalPeer peerDiscoveredAt(DateTime at) => LocalPeer(
        peerId: 'peer-1',
        host: '192.168.1.42',
        port: 51234,
        discoveredAt: at,
      );

  group('LocalPeer.isStale (TTL predicate)', () {
    test('ttl constant is 30 seconds', () {
      expect(LocalPeer.ttl, const Duration(seconds: 30));
    });

    test('entry older than ttl (now - 31s) is stale', () {
      final now = DateTime.utc(2026, 1, 1, 12, 0, 0);
      final peer = peerDiscoveredAt(now.subtract(const Duration(seconds: 31)));
      expect(peer.isStale(now), isTrue);
    });

    test('entry younger than ttl (now - 29s) is NOT stale', () {
      final now = DateTime.utc(2026, 1, 1, 12, 0, 0);
      final peer = peerDiscoveredAt(now.subtract(const Duration(seconds: 29)));
      expect(peer.isStale(now), isFalse);
    });

    test('entry exactly at ttl (now - 30s) is NOT stale (strict >)', () {
      final now = DateTime.utc(2026, 1, 1, 12, 0, 0);
      final peer = peerDiscoveredAt(now.subtract(const Duration(seconds: 30)));
      // isStale uses strict greater-than, so exactly-ttl is still fresh.
      expect(peer.isStale(now), isFalse);
    });

    test('just over ttl (now - 30s - 1ms) is stale', () {
      final now = DateTime.utc(2026, 1, 1, 12, 0, 0);
      final peer = peerDiscoveredAt(
        now.subtract(const Duration(seconds: 30, milliseconds: 1)),
      );
      expect(peer.isStale(now), isTrue);
    });

    test('freshly discovered entry is not stale', () {
      final now = DateTime.utc(2026, 1, 1, 12, 0, 0);
      final peer = peerDiscoveredAt(now);
      expect(peer.isStale(now), isFalse);
    });
  });
}
