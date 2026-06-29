/// FDC-S6: privacy-safe private-IP discriminator for libp2p multiaddrs.
///
/// The libp2p-LAN soak win-rate must isolate a genuine LAN-direct win from a
/// WAN/public-IP direct dial or a DCUtR-upgraded relay->direct conn (all of
/// which Go's `classifyStreamTransport` labels identically as `"direct"`, with
/// no private-IP check). The raw multiaddr cannot ride a flow-event to the log —
/// `flow_event_emitter` redacts every multiaddr-shaped value to
/// `[redacted:multiaddr]` — so the private-IP gate must be computed BEFORE emit
/// and carried as a NON-SENSITIVE boolean. This is that pure computation.
///
/// "Private" here means non-routable / not-a-WAN address: RFC1918 IPv4
/// (10/8, 172.16/12, 192.168/16), IPv4 link-local (169.254/16), loopback, and
/// IPv6 ULA (fc00::/7) / link-local (fe80::/10) / loopback (::1). A bonsoir-fed
/// LAN peer advertises exactly these; a WAN-direct peer would not — so a
/// `true` result is the soak's evidence that a `"direct"` win was a real
/// same-WiFi LAN dial, not a WAN/DCUtR false positive.
library;

/// True if [multiaddr] (e.g. `/ip4/192.168.1.5/udp/4001/quic-v1/p2p/12D3Koo...`)
/// embeds a private / non-routable host. Two host shapes count as LAN evidence:
///   1. a literal private IPv4/IPv6 host on an `/ip4`/`/ip6` segment, and
///   2. an mDNS `.local` hostname on a `/dns4`/`/dns6`/`/dnsaddr` segment —
///      Fix C (plan 175) builds `/dns4/<host>.local` for an iOS-resolved bonsoir
///      peer (iOS resolves a same-WiFi peer to its `.local` mDNS hostname, not a
///      numeric IP). A `.local` name is link-local by definition (RFC 6762): it
///      resolves only on the local link via multicast DNS, so it can never be a
///      WAN address and IS valid LAN evidence.
/// A non-`.local` dns host (e.g. `/dns4/example.com`, a relay `/dnsaddr/...`) and
/// `/p2p-circuit/` / empty still return false — only a private IP or a `.local`
/// hostname counts.
bool multiaddrIsPrivateIp(String multiaddr) {
  final segments = multiaddr.split('/');
  for (var i = 0; i + 1 < segments.length; i++) {
    final proto = segments[i];
    if (proto == 'ip4') {
      if (_isPrivateIpv4(segments[i + 1])) return true;
    } else if (proto == 'ip6') {
      if (_isPrivateIpv6(segments[i + 1])) return true;
    } else if (proto == 'dns4' || proto == 'dns6' || proto == 'dnsaddr') {
      if (_isMdnsLocalHost(segments[i + 1])) return true;
    }
  }
  return false;
}

/// True if ANY multiaddr in [multiaddrs] embeds a private / non-routable host —
/// the per-peer discriminator the LAN soak gates a `"direct"` win on.
bool multiaddrsContainPrivateIp(Iterable<String> multiaddrs) =>
    multiaddrs.any(multiaddrIsPrivateIp);

/// True if [host] is an mDNS `.local` name (RFC 6762 link-local). Case-
/// insensitive; one trailing dot is tolerated defensively (Fix C strips the
/// FQDN trailing dot at the multiaddr build, but the host is otherwise
/// device-name-cased, so normalize both here). A bare `local` and any
/// `<label>.local` qualify; an empty-label `.local`/`..local` does NOT (RFC
/// 6762 requires a hostname label), and every other dns host (a potential WAN
/// domain) does not either.
bool _isMdnsLocalHost(String host) {
  const suffix = '.local';
  var h = host.toLowerCase();
  if (h.endsWith('.')) h = h.substring(0, h.length - 1);
  if (h == 'local') return true;
  if (!h.endsWith(suffix)) return false;
  // Require a non-empty hostname label before `.local` — a bare `.local`
  // (or `..local`) is not a valid mDNS name.
  final label = h.substring(0, h.length - suffix.length);
  return label.isNotEmpty && !label.endsWith('.');
}

bool _isPrivateIpv4(String addr) {
  final octets = addr.split('.');
  if (octets.length != 4) return false;
  final parts = <int>[];
  for (final o in octets) {
    final v = int.tryParse(o);
    if (v == null || v < 0 || v > 255) return false;
    parts.add(v);
  }
  final a = parts[0];
  final b = parts[1];
  // 10.0.0.0/8
  if (a == 10) return true;
  // 172.16.0.0/12
  if (a == 172 && b >= 16 && b <= 31) return true;
  // 192.168.0.0/16
  if (a == 192 && b == 168) return true;
  // 169.254.0.0/16 link-local
  if (a == 169 && b == 254) return true;
  // 127.0.0.0/8 loopback (non-routable; never a WAN false positive)
  if (a == 127) return true;
  return false;
}

bool _isPrivateIpv6(String addr) {
  final lower = addr.toLowerCase();
  // ::1 loopback
  if (lower == '::1') return true;
  // IPv4-mapped (::ffff:a.b.c.d) — classify by the embedded IPv4 (a private
  // mapped addr must not be missed). libp2p/bonsoir don't normally advertise
  // these, but the guard is cheap and prevents a false-negative LAN miss.
  if (lower.startsWith('::ffff:') && lower.contains('.')) {
    return _isPrivateIpv4(lower.substring(lower.lastIndexOf(':') + 1));
  }
  // fc00::/7 unique-local (fc.. / fd..)
  if (lower.startsWith('fc') || lower.startsWith('fd')) return true;
  // fe80::/10 link-local (fe8.. / fe9.. / fea.. / feb..)
  if (lower.startsWith('fe8') ||
      lower.startsWith('fe9') ||
      lower.startsWith('fea') ||
      lower.startsWith('feb')) {
    return true;
  }
  return false;
}
