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
        final original = Uint8List.fromList(
          [0, 1, 127, 128, 255, 16, 32, 64],
        );
        final hex = bytesToHex(original);
        final restored = hexToBytes(hex);
        expect(restored, original);
      });
    });
  });
}
