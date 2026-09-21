import 'dart:convert';
import 'dart:io';

/// Validated once, before any process launch, then sent explicitly to both
/// testpeer's JSON start parameters and Flutter's compile-time bridge input.
class BenchmarkBoundary {
  BenchmarkBoundary(String deviceId, {bool hostFiles = false}) {
    final env = Platform.environment;
    final protected = env['SIMS_PROTECTED_DEVICE_ASSIGNMENTS_JSON'];
    final isolated = protected != null || env['MKNOON_LEGACY_ISOLATED'] == '1';
    if (isolated) {
      final pins = protected == null ? null : jsonDecode(protected);
      if (pins is! Map || !pins.containsValue(deviceId)) {
        throw StateError('Benchmark requires an explicitly protected target');
      }
      // GP/H use absolute host files, not the Android routing-stage channel.
      // Only the existing iOS simulator topology is supported by this route.
      if (hostFiles &&
          !pins.entries.any(
            (e) =>
                RegExp(r'^ios-simulator-[a-d]$').hasMatch(e.key.toString()) &&
                e.value == deviceId,
          )) {
        throw StateError(
          'GP/H host-file protocol requires a leased iOS simulator',
        );
      }
    }
    final csv = env['MKNOON_RELAY_ADDRESSES'];
    if (csv == null && !isolated) return; // Legacy direct mode only.
    final addresses = csv?.split(',').map((s) => s.trim()).toList();
    if (addresses == null ||
        addresses.isEmpty ||
        addresses.any((s) => !_validRelay(s))) {
      throw StateError('Explicit valid MKNOON_RELAY_ADDRESSES required');
    }
    relays = addresses;
  }

  List<String>? relays;
  Map<String, dynamic> get startParams => {
    if (relays != null) 'relayAddresses': relays,
  };
  List<String> get flutterArgs => [
    if (relays != null)
      '--dart-define=MKNOON_RELAY_ADDRESSES=${relays!.join(',')}',
  ];

  // Deliberately bounded to the shipped relay transports (TCP, WS/WSS, QUIC)
  // and libp2p Ed25519 / SHA-256 peer IDs. No DNS lookup or process is needed.
  static bool _validRelay(String value) {
    final match = RegExp(
      r'^/(dns|dns4|dns6|ip4|ip6)/([^/\s]+)/'
      r'(tcp|udp)/([0-9]{1,5})(/ws|/wss|/quic-v1)?/p2p/([1-9A-HJ-NP-Za-km-z]+)$',
    ).firstMatch(value);
    if (match == null) return false;
    final port = int.parse(match[4]!);
    if (port < 1 ||
        port > 65535 ||
        (match[3] == 'udp') != (match[5] == '/quic-v1'))
      return false;
    final host = match[2]!;
    if (match[1]!.startsWith('dns')) {
      if (host.length > 253 ||
          host
              .split('.')
              .any(
                (label) => !RegExp(
                  r'^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$',
                ).hasMatch(label),
              ))
        return false;
    } else {
      final address = InternetAddress.tryParse(host);
      if (address == null ||
          address.type !=
              (match[1] == 'ip4'
                  ? InternetAddressType.IPv4
                  : InternetAddressType.IPv6))
        return false;
    }
    final id = match[6]!;
    if (id.length != 46 && id.length != 52) return false;
    const alphabet =
        '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
    var number = BigInt.zero;
    for (final c in id.split('')) {
      number = number * BigInt.from(58) + BigInt.from(alphabet.indexOf(c));
    }
    final bytes = <int>[];
    while (number > BigInt.zero) {
      bytes.insert(0, (number & BigInt.from(255)).toInt());
      number >>= 8;
    }
    for (var i = 0; i < id.length && id[i] == '1'; i++) {
      bytes.insert(0, 0);
    }
    return (bytes.length == 34 && bytes[0] == 18 && bytes[1] == 32) ||
        (bytes.length == 38 && bytes.take(6).join(',') == '0,36,8,1,18,32');
  }
}
