import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/local_discovery/lan_address_classifier.dart';

/// FDC-S6: the private-IP discriminator is the soak's guard against counting a
/// WAN/DCUtR `"direct"` as a libp2p-LAN win. Exact true/false per address (never
/// `> 0`) because the false-result risk is MISLABELING a WAN dial as LAN.
void main() {
  group('multiaddrIsPrivateIp — IPv4', () {
    test('RFC1918 10/8 is private', () {
      expect(
        multiaddrIsPrivateIp('/ip4/10.1.2.3/udp/4001/quic-v1/p2p/12D3KooAbc'),
        isTrue,
      );
    });

    test('RFC1918 172.16/12 boundaries (16..31 private, 15/32 public)', () {
      expect(multiaddrIsPrivateIp('/ip4/172.16.0.1/tcp/4001'), isTrue);
      expect(multiaddrIsPrivateIp('/ip4/172.31.255.254/tcp/4001'), isTrue);
      expect(multiaddrIsPrivateIp('/ip4/172.15.0.1/tcp/4001'), isFalse);
      expect(multiaddrIsPrivateIp('/ip4/172.32.0.1/tcp/4001'), isFalse);
    });

    test('RFC1918 192.168/16 is private; 192.169 is public', () {
      expect(multiaddrIsPrivateIp('/ip4/192.168.0.5/udp/4001/quic-v1'), isTrue);
      expect(multiaddrIsPrivateIp('/ip4/192.169.0.5/udp/4001/quic-v1'), isFalse);
    });

    test('169.254/16 link-local and 127/8 loopback are non-routable (private)', () {
      expect(multiaddrIsPrivateIp('/ip4/169.254.10.10/tcp/4001'), isTrue);
      expect(multiaddrIsPrivateIp('/ip4/127.0.0.1/tcp/4001'), isTrue);
    });

    test('public/WAN IPv4 is NOT private (the false-positive the gate excludes)', () {
      expect(multiaddrIsPrivateIp('/ip4/8.8.8.8/udp/4001/quic-v1'), isFalse);
      expect(multiaddrIsPrivateIp('/ip4/203.0.113.7/tcp/4001'), isFalse);
    });

    test('malformed IPv4 octets are not private', () {
      expect(multiaddrIsPrivateIp('/ip4/10.1.2/tcp/4001'), isFalse);
      expect(multiaddrIsPrivateIp('/ip4/10.1.2.999/tcp/4001'), isFalse);
      expect(multiaddrIsPrivateIp('/ip4/10.x.2.3/tcp/4001'), isFalse);
    });
  });

  group('multiaddrIsPrivateIp — IPv6', () {
    test('fc00::/7 ULA (fc/fd) and ::1 loopback are private', () {
      expect(multiaddrIsPrivateIp('/ip6/fd12:3456::1/udp/4001/quic-v1'), isTrue);
      expect(multiaddrIsPrivateIp('/ip6/fc00::abcd/tcp/4001'), isTrue);
      expect(multiaddrIsPrivateIp('/ip6/::1/tcp/4001'), isTrue);
    });

    test('fe80::/10 link-local is private', () {
      expect(multiaddrIsPrivateIp('/ip6/fe80::1/tcp/4001'), isTrue);
    });

    test('global-unicast IPv6 (2000::/3) is NOT private', () {
      expect(
        multiaddrIsPrivateIp('/ip6/2606:4700:4700::1111/udp/4001/quic-v1'),
        isFalse,
      );
    });

    test('IPv4-mapped IPv6 is classified by its embedded IPv4', () {
      expect(multiaddrIsPrivateIp('/ip6/::ffff:192.168.1.1/tcp/4001'), isTrue);
      expect(multiaddrIsPrivateIp('/ip6/::ffff:10.0.0.5/udp/4001/quic-v1'), isTrue);
      expect(multiaddrIsPrivateIp('/ip6/::ffff:8.8.8.8/tcp/4001'), isFalse);
    });
  });

  group('multiaddrIsPrivateIp — non-IP host components', () {
    test('dns/circuit multiaddrs with no literal IP are not private', () {
      expect(multiaddrIsPrivateIp('/dns4/example.com/tcp/4001'), isFalse);
      expect(
        multiaddrIsPrivateIp('/p2p/12D3KooRelay/p2p-circuit/p2p/12D3KooDst'),
        isFalse,
      );
      expect(multiaddrIsPrivateIp(''), isFalse);
    });
  });

  group('multiaddrsContainPrivateIp — per-peer aggregate', () {
    test('true when ANY advertised addr is private (LAN evidence)', () {
      expect(
        multiaddrsContainPrivateIp([
          '/ip4/203.0.113.7/tcp/4001', // WAN
          '/ip4/192.168.1.5/udp/4001/quic-v1', // LAN
        ]),
        isTrue,
      );
    });

    test('false when every addr is public/non-IP (no LAN evidence)', () {
      expect(
        multiaddrsContainPrivateIp([
          '/ip4/8.8.8.8/udp/4001/quic-v1',
          '/dns4/example.com/tcp/4001',
        ]),
        isFalse,
      );
    });

    test('false on empty list', () {
      expect(multiaddrsContainPrivateIp(const []), isFalse);
    });
  });
}
