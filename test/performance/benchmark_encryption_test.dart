import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../core/bridge/fake_bridge.dart';
import 'benchmark_harness.dart';
import 'timing_test_bridge.dart';

void main() {
  late BenchmarkHarness harness;

  setUp(() {
    harness = BenchmarkHarness();
  });

  tearDown(() {
    harness.dispose();
  });

  group('Benchmark: Encryption Overhead', () {
    test('G1: ML-KEM keygen bridge call succeeds', () async {
      final bridge = FakeBridge(
        initialResponses: {
          'mlkem.keygen': {
            'ok': true,
            'publicKey': 'test-public-key',
            'secretKey': 'test-secret-key',
          },
        },
      );

      final response = await bridge.send(
        jsonEncode({'cmd': 'mlkem.keygen', 'payload': {}}),
      );
      final parsed = jsonDecode(response) as Map<String, dynamic>;

      expect(parsed['ok'], isTrue);
      expect(parsed['publicKey'], isA<String>());
      expect(parsed['secretKey'], isA<String>());
    });

    test('G2: Encrypt bridge call returns expected fields', () async {
      final bridge = PassthroughCryptoBridge();

      final response = await bridge.send(
        jsonEncode({
          'cmd': 'message.encrypt',
          'payload': {
            'plaintext': 'Hello, encrypted world!',
            'publicKey': 'test-mlkem-public-key',
          },
        }),
      );
      final parsed = jsonDecode(response) as Map<String, dynamic>;

      expect(parsed['ok'], isTrue);
      expect(parsed['ciphertext'], isA<String>());
      expect(parsed['kem'], isA<String>());
      expect(parsed['nonce'], isA<String>());
    });

    test('G3: Decrypt bridge call returns plaintext', () async {
      final bridge = PassthroughCryptoBridge();

      final response = await bridge.send(
        jsonEncode({
          'cmd': 'message.decrypt',
          'payload': {
            'ciphertext': 'Hello, encrypted world!',
            'kem': 'fake-kem',
            'nonce': 'fake-nonce',
            'secretKey': 'test-mlkem-secret-key',
          },
        }),
      );
      final parsed = jsonDecode(response) as Map<String, dynamic>;

      expect(parsed['ok'], isTrue);
      expect(parsed['plaintext'], 'Hello, encrypted world!');
    });

    test('G4: TimingTestBridge injects encryptMs into response', () async {
      final bridge = TimingTestBridge(
        responseTimingFields: {
          'message.encrypt': {'encryptMs': 3},
        },
      );

      final response = await bridge.send(
        jsonEncode({
          'cmd': 'message.encrypt',
          'payload': {
            'plaintext': 'test payload',
            'publicKey': 'test-key',
          },
        }),
      );
      final parsed = jsonDecode(response) as Map<String, dynamic>;

      expect(parsed['ok'], isTrue);
      expect(parsed['encryptMs'], 3);
    });

    test('G5: Group encrypt/decrypt via FakeBridge (passthrough)', () async {
      final bridge = FakeBridge();

      // Group encrypt
      final encResponse = await bridge.send(
        jsonEncode({
          'cmd': 'group.encrypt',
          'payload': {'plaintext': 'group message text'},
        }),
      );
      final enc = jsonDecode(encResponse) as Map<String, dynamic>;
      expect(enc['ok'], isTrue);
      expect(enc['ciphertext'], 'group message text'); // passthrough

      // Group decrypt
      final decResponse = await bridge.send(
        jsonEncode({
          'cmd': 'group.decrypt',
          'payload': {'ciphertext': 'group message text'},
        }),
      );
      final dec = jsonDecode(decResponse) as Map<String, dynamic>;
      expect(dec['ok'], isTrue);
      expect(dec['plaintext'], 'group message text'); // passthrough
    });
  });
}
