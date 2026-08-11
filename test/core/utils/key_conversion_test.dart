import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/utils/key_conversion.dart';

void main() {
  group('key_conversion', () {
    // Known test vector: bytes [0xde, 0xad, 0xbe, 0xef]
    // base64 of those bytes: "3q2+7w=="
    // hex of those bytes: "deadbeef"

    group('base64ToHex', () {
      test('converts known base64 to hex', () {
        expect(base64ToHex('3q2+7w=='), 'deadbeef');
      });

      test('converts empty base64 to empty hex', () {
        // base64 of empty bytes is ""
        expect(base64ToHex(''), '');
      });
    });

    group('hexToBase64', () {
      test('converts known hex to base64', () {
        expect(hexToBase64('deadbeef'), '3q2+7w==');
      });

      test('converts empty hex to empty base64', () {
        expect(hexToBase64(''), '');
      });
    });

    group('base64ToHex / hexToBase64 round-trip', () {
      test('round-trips from base64', () {
        const original = '3q2+7w==';
        expect(hexToBase64(base64ToHex(original)), original);
      });

      test('round-trips from hex', () {
        const original = 'deadbeef';
        expect(base64ToHex(hexToBase64(original)), original);
      });
    });

    group('bytesToHex', () {
      test('pads single-digit hex values', () {
        final bytes = Uint8List.fromList([0, 1, 15]);
        expect(bytesToHex(bytes), '00010f');
      });

      test('empty bytes returns empty string', () {
        expect(bytesToHex(Uint8List(0)), '');
      });

      test('converts all-ff bytes', () {
        final bytes = Uint8List.fromList([255, 255]);
        expect(bytesToHex(bytes), 'ffff');
      });
    });

    group('hexToBytes', () {
      test('converts known hex string', () {
        final bytes = hexToBytes('deadbeef');
        expect(bytes, Uint8List.fromList([0xde, 0xad, 0xbe, 0xef]));
      });

      test('handles uppercase hex input', () {
        final bytes = hexToBytes('DEADBEEF');
        expect(bytes, Uint8List.fromList([0xde, 0xad, 0xbe, 0xef]));
      });

      test('throws on odd-length hex string', () {
        expect(() => hexToBytes('abc'), throwsA(isA<ArgumentError>()));
      });

      test('empty string returns empty Uint8List', () {
        final bytes = hexToBytes('');
        expect(bytes, Uint8List(0));
        expect(bytes.length, 0);
      });
    });

    group('bytesToHex / hexToBytes round-trip', () {
      test('round-trips with varied data', () {
        final original = Uint8List.fromList([0, 1, 127, 128, 255, 16, 32, 64]);
        final hex = bytesToHex(original);
        final restored = hexToBytes(hex);
        expect(restored, original);
      });
    });

    group('TC-360-01a Ed25519 public key -> libp2p peer ID', () {
      // Fixed vectors produced by the INCUMBENT Go implementation
      // (`go-mknoon/identity`, `peer.IDFromPublicKey`) from BIP39 test
      // mnemonics. The pure-Dart helper must reproduce them exactly: it runs
      // OFFLINE, before `node:start` and before a scanned QR is trusted, so
      // any drift from Go would silently bind device rows to peers nobody
      // controls.
      const goVectors = <String, String>{
        // "abandon abandon ... about"
        'xXheGGW3CJOK/4Fh1XMAZJZmOxqhCDTjltxWaGmixmo=':
            '12D3KooWP7CwQswqLKZbwvYd9wrEynnL9F2aKVP1X9huNASBTuqj',
        // "legal winner thank year wave sausage worth useful legal winner
        //  thank yellow"
        'xvKsVZiXDHljNxTT61w017/D6S2ljHNUs3mW2aSvOrI=':
            '12D3KooWPCyWnZCXR3VGdrQjLr5d8TBaAHD956XZvo6xoCXYB5AR',
        // "letter advice cage absurd amount doctor acoustic avoid letter
        //  advice cage above"
        '8MoQw54eBrJfQtZUoNSQt5eZ9LeEseHxRKYv2zhyy58=':
            '12D3KooWS2Jiwq8amLufp2meksG2jhWkZzhvAmetUsPdWv5xk7ZY',
        // "zoo zoo ... wrong"
        'zkx33kYfgvN4I4Z5ka7AXMY8Ywmm/Om42Kv1lIHz7Gw=':
            '12D3KooWPhfnPm23Hq3jyFu9MUTZCALUDCaXYwzbgkCjXvs2DhwZ',
      };

      test('TC-360-01a linked-secondary transport identity is distinct stable '
          'and fail-closed', () {
        goVectors.forEach((publicKey, expectedPeerId) {
          expect(
            ed25519PublicKeyToPeerId(publicKey),
            expectedPeerId,
            reason: publicKey,
          );
          expect(
            ed25519PublicKeyMatchesPeerId(
              base64PublicKey: publicKey,
              claimedPeerId: expectedPeerId,
            ),
            isTrue,
          );
        });

        // Distinct keys derive distinct peers: this is what makes a linked
        // secondary a different relay mailbox owner than its account.
        final derived = goVectors.keys.map(ed25519PublicKeyToPeerId).toSet();
        expect(derived, hasLength(goVectors.length));

        // Cross-matching a real key against another real peer is refused.
        final entries = goVectors.entries.toList();
        expect(
          ed25519PublicKeyMatchesPeerId(
            base64PublicKey: entries[0].key,
            claimedPeerId: entries[1].value,
          ),
          isFalse,
        );

        // Malformed input FAILS CLOSED rather than returning a peer.
        for (final malformed in const <String>[
          '',
          '   ',
          'not-base64!!',
          'c2hvcnQ=', // valid base64, wrong length
        ]) {
          expect(
            () => ed25519PublicKeyToPeerId(malformed),
            throwsA(isA<PeerIdDerivationException>()),
            reason: malformed,
          );
          expect(
            ed25519PublicKeyMatchesPeerId(
              base64PublicKey: malformed,
              claimedPeerId: entries[0].value,
            ),
            isFalse,
            reason: 'match must never throw; it refuses',
          );
        }

        // A blank claimed peer never matches.
        expect(
          ed25519PublicKeyMatchesPeerId(
            base64PublicKey: entries[0].key,
            claimedPeerId: '  ',
          ),
          isFalse,
        );

        // Byte-level derivation agrees with the base64 entry point.
        expect(
          ed25519PublicKeyBytesToPeerId(base64Decode(entries[0].key)),
          entries[0].value,
        );
        expect(
          () => ed25519PublicKeyBytesToPeerId(Uint8List(31)),
          throwsA(isA<PeerIdDerivationException>()),
        );
      });
    });
  });
}
