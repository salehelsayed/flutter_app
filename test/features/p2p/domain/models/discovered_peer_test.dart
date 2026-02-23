import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';

void main() {
  group('DiscoveredPeer', () {
    const basePeer = DiscoveredPeer(
      id: 'QmPeer123',
      addresses: ['/ip4/192.168.1.1/tcp/4001'],
    );

    group('fromJson', () {
      test('parses using peerId key', () {
        final peer = DiscoveredPeer.fromJson({
          'peerId': 'QmPeer123',
          'addresses': ['/ip4/192.168.1.1/tcp/4001'],
        });
        expect(peer.id, 'QmPeer123');
        expect(peer.addresses, ['/ip4/192.168.1.1/tcp/4001']);
      });

      test('parses using id key', () {
        final peer = DiscoveredPeer.fromJson({
          'id': 'QmPeer456',
          'addresses': ['/ip4/10.0.0.1/tcp/4001'],
        });
        expect(peer.id, 'QmPeer456');
        expect(peer.addresses, ['/ip4/10.0.0.1/tcp/4001']);
      });

      test('prefers peerId over id when both present', () {
        final peer = DiscoveredPeer.fromJson({
          'peerId': 'QmFromPeerId',
          'id': 'QmFromId',
          'addresses': [],
        });
        // peerId ?? id — peerId is non-null so it wins
        expect(peer.id, 'QmFromPeerId');
      });

      test('defaults addresses to empty list when missing', () {
        final peer = DiscoveredPeer.fromJson({
          'id': 'QmPeer789',
        });
        expect(peer.addresses, isEmpty);
      });
    });

    group('toJson', () {
      test('round-trips through toJson and fromJson', () {
        final json = basePeer.toJson();
        final restored = DiscoveredPeer.fromJson(json);
        expect(restored.id, basePeer.id);
        expect(restored.addresses, basePeer.addresses);
      });

      test('uses id key in output', () {
        final json = basePeer.toJson();
        expect(json.containsKey('id'), isTrue);
        expect(json.containsKey('peerId'), isFalse);
        expect(json['id'], 'QmPeer123');
      });
    });

    group('equality', () {
      test('equal by id only, different addresses still equal', () {
        const a = DiscoveredPeer(
          id: 'QmSame',
          addresses: ['/ip4/1.1.1.1/tcp/4001'],
        );
        const b = DiscoveredPeer(
          id: 'QmSame',
          addresses: ['/ip4/2.2.2.2/tcp/9999', '/ip4/3.3.3.3/tcp/5555'],
        );
        expect(a, equals(b));
      });

      test('not equal when id differs', () {
        const a = DiscoveredPeer(id: 'QmAlpha', addresses: []);
        const b = DiscoveredPeer(id: 'QmBeta', addresses: []);
        expect(a, isNot(equals(b)));
      });

      test('hashCode consistent with equality', () {
        const a = DiscoveredPeer(id: 'QmSame', addresses: []);
        const b = DiscoveredPeer(
          id: 'QmSame',
          addresses: ['/ip4/1.1.1.1/tcp/4001'],
        );
        expect(a.hashCode, equals(b.hashCode));
      });
    });

    group('toString', () {
      test('contains id and address count', () {
        final str = basePeer.toString();
        expect(str, contains('QmPeer123'));
        expect(str, contains('1')); // address count
      });
    });
  });
}
