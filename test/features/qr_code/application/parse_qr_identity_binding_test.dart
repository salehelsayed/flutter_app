import 'dart:collection';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/qr_code/application/parse_qr_payload_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/ed25519_contact_request_crypto.dart';

// Task 12b: a scanned QR is accepted only when its peer ID is the libp2p ID of
// its own Ed25519 account key. Signatures here are real Ed25519 and the peer
// IDs come from the production derivation, so no case relies on a fake
// always-valid verifier.

final _bus = Ed25519ContactRequestCryptoBus();
final _k1 = TestEd25519Identity.fromSeedByte(0x31);
final _k2 = TestEd25519Identity.fromSeedByte(0x32);
final _own = TestEd25519Identity.fromSeedByte(0x33);

const _rendezvous = '/dns4/relay.example/tcp/4001/wss/p2p/relay';

String _signedQr({
  required TestEd25519Identity signer,
  String? claimedPeerId,
  String? claimedPublicKey,
  String? mlKem,
  String? username = 'Alice',
  String? ts,
  bool reorder = false,
}) {
  final unsigned = SplayTreeMap<String, dynamic>.from({
    'mlkem': ?mlKem,
    'ns': claimedPeerId ?? signer.peerId,
    'pk': claimedPublicKey ?? signer.publicKey,
    'rv': _rendezvous,
    'ts': ts ?? DateTime.now().toUtc().toIso8601String(),
    'un': ?username,
  });
  final signature = signer.signBase64(jsonEncode(unsigned));
  final fields = <String, dynamic>{...unsigned, 'sig': signature};
  if (!reorder) return jsonEncode(fields);
  final reversed = Map<String, dynamic>.fromEntries(
    fields.entries.toList().reversed,
  );
  return jsonEncode(reversed);
}

/// CIDv1 (libp2p-key codec 0x72, multibase base32 lower) of a base58 peer ID,
/// written independently of production code.
String _cidV1For(String base58PeerId) {
  const alphabet = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
  var value = BigInt.zero;
  for (final rune in base58PeerId.runes) {
    value =
        value * BigInt.from(58) +
        BigInt.from(alphabet.indexOf(String.fromCharCode(rune)));
  }
  final bytes = <int>[];
  while (value > BigInt.zero) {
    bytes.insert(0, (value & BigInt.from(0xff)).toInt());
    value = value >> 8;
  }
  for (final rune in base58PeerId.runes) {
    if (String.fromCharCode(rune) != '1') break;
    bytes.insert(0, 0);
  }
  final cid = <int>[0x01, 0x72, ...bytes];
  const b32 = 'abcdefghijklmnopqrstuvwxyz234567';
  final out = StringBuffer('b');
  var buffer = 0;
  var bits = 0;
  for (final byte in cid) {
    buffer = (buffer << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      out.write(b32[(buffer >> (bits - 5)) & 31]);
      bits -= 5;
    }
  }
  if (bits > 0) out.write(b32[(buffer << (5 - bits)) & 31]);
  return out.toString();
}

Future<(ParseQRResult, String?)> _parse(String qr) async {
  final (result, contact) = await parseQRPayload(
    qrString: qr,
    bridge: Ed25519ContactRequestBridge(_bus),
    ownPeerId: _own.peerId,
  );
  return (result, contact?.peerId);
}

void main() {
  setUpAll(() {
    _bus
      ..register(_k1)
      ..register(_k2)
      ..register(_own);
  });

  group('QR peer-ID/Ed25519 binding', () {
    test('K2 self-signs a QR that claims K1 peer ID: rejected before any '
        'contact is built', () async {
      final (result, peerId) = await _parse(
        _signedQr(signer: _k2, claimedPeerId: _k1.peerId),
      );

      expect(result, ParseQRResult.invalidSignature);
      expect(peerId, isNull);
    });

    test('valid K1/K1-ID and K2/K2-ID compact QRs pass', () async {
      expect(await _parse(_signedQr(signer: _k1)), (
        ParseQRResult.success,
        _k1.peerId,
      ));
      expect(await _parse(_signedQr(signer: _k2)), (
        ParseQRResult.success,
        _k2.peerId,
      ));
    });

    test('compact QR without ML-KEM and older full QR with ML-KEM both '
        'pass with real signatures', () async {
      final (compact, compactContact) = await parseQRPayload(
        qrString: _signedQr(signer: _k1),
        bridge: Ed25519ContactRequestBridge(_bus),
        ownPeerId: _own.peerId,
      );
      expect(compact, ParseQRResult.success);
      expect(compactContact!.mlKemPublicKey, isNull);

      final (full, fullContact) = await parseQRPayload(
        qrString: _signedQr(signer: _k1, mlKem: 'mlkem-public-key-k1'),
        bridge: Ed25519ContactRequestBridge(_bus),
        ownPeerId: _own.peerId,
      );
      expect(full, ParseQRResult.success);
      expect(fullContact!.mlKemPublicKey, 'mlkem-public-key-k1');
    });

    test('optional username absent and reordered JSON still pass', () async {
      expect(await _parse(_signedQr(signer: _k1, username: null)), (
        ParseQRResult.success,
        _k1.peerId,
      ));
      expect(await _parse(_signedQr(signer: _k1, reorder: true)), (
        ParseQRResult.success,
        _k1.peerId,
      ));
    });

    test('a device key cannot impersonate the account key', () async {
      // The "device" key signs honestly but carries the account peer ID.
      final device = TestEd25519Identity.fromSeedByte(0x34);
      _bus.register(device);
      final (result, _) = await _parse(
        _signedQr(signer: device, claimedPeerId: _k1.peerId),
      );
      expect(result, ParseQRResult.invalidSignature);
    });

    test('malformed or wrong-size public key fails closed', () async {
      for (final badKey in <String>[
        'not base64 !!',
        base64Encode(List<int>.filled(31, 7)),
        base64Encode(List<int>.filled(33, 7)),
      ]) {
        final qr = jsonEncode(<String, dynamic>{
          'ns': _k1.peerId,
          'pk': badKey,
          'rv': _rendezvous,
          'ts': DateTime.now().toUtc().toIso8601String(),
          'sig': 'c2ln',
        });
        expect((await _parse(qr)).$1, ParseQRResult.invalidSignature);
      }
    });

    test(
      'non-string identity fields fail closed instead of throwing',
      () async {
        final qr = jsonEncode(<String, dynamic>{
          'ns': 12345,
          'pk': _k1.publicKey,
          'rv': _rendezvous,
          'ts': DateTime.now().toUtc().toIso8601String(),
          'sig': 'c2ln',
        });
        expect((await _parse(qr)).$1, ParseQRResult.invalidSignature);
      },
    );

    test('a supported CIDv1 encoding of the same peer ID passes and is '
        'stored as the canonical ID', () async {
      final cid = _cidV1For(_k1.peerId);
      expect(cid, startsWith('b'));
      expect(await _parse(_signedQr(signer: _k1, claimedPeerId: cid)), (
        ParseQRResult.success,
        _k1.peerId,
      ));
    });

    test('a QR claiming our own peer ID with a foreign key is not a '
        'valid self-scan', () async {
      final (result, _) = await _parse(
        _signedQr(signer: _k2, claimedPeerId: _own.peerId),
      );
      expect(result, ParseQRResult.invalidSignature);
    });

    test('our own genuine QR is still a self-scan', () async {
      expect(
        (await _parse(_signedQr(signer: _own))).$1,
        ParseQRResult.selfScan,
      );
    });

    test('expiry control is unchanged by the binding check', () async {
      final old = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 25))
          .toIso8601String();
      expect(
        (await _parse(_signedQr(signer: _k1, ts: old))).$1,
        ParseQRResult.expired,
      );
    });
  });

  test('binding failure diagnostics carry no key or peer bytes', () async {
    final events = <Map<String, dynamic>>[];
    debugSetFlowEventSink(events.add);
    addTearDown(() => debugSetFlowEventSink(null));

    await _parse(_signedQr(signer: _k2, claimedPeerId: _k1.peerId));

    final binding = events
        .where((e) => e['event'] == 'QR_PARSE_IDENTITY_BINDING_MISMATCH')
        .toList();
    expect(binding, hasLength(1));
    expect(binding.single['details'], isEmpty);
    final rendered = jsonEncode(events.map((e) => e['details']).toList());
    expect(rendered, isNot(contains(_k1.peerId.substring(0, 10))));
    expect(rendered, isNot(contains(_k2.publicKey.substring(0, 10))));
  });

  test('bridge is never asked to verify when the binding fails', () async {
    final bridge = Ed25519ContactRequestBridge(_bus);
    await parseQRPayload(
      qrString: _signedQr(signer: _k2, claimedPeerId: _k1.peerId),
      bridge: bridge,
      ownPeerId: _own.peerId,
    );
    expect(bridge.verifyCalls, 0);
    expect(bridge, isA<Bridge>());
  });
}
