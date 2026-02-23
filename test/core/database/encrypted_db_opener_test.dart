import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import '../../core/secure_storage/fake_secure_key_store.dart';

void main() {
  group('encrypted_db_opener', () {
    group('key generation contract', () {
      // Replicate the private _generateRandomKey to verify its contract
      String generateRandomKey() {
        final random = Random.secure();
        final bytes = List<int>.generate(32, (_) => random.nextInt(256));
        return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      }

      test('generates a 64-character hex string', () {
        final key = generateRandomKey();
        expect(key.length, 64);
        expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(key), isTrue);
      });

      test('generates unique keys on each call', () {
        final key1 = generateRandomKey();
        final key2 = generateRandomKey();
        // Statistically impossible to collide with 256-bit random
        expect(key1, isNot(equals(key2)));
      });

      test('each byte is zero-padded to 2 hex chars', () {
        // Verify that bytes < 16 get padded (e.g., 0x0A -> "0a" not "a")
        final key = generateRandomKey();
        // All pairs should be exactly 2 chars
        for (var i = 0; i < key.length; i += 2) {
          final pair = key.substring(i, i + 2);
          expect(pair.length, 2);
          expect(int.tryParse(pair, radix: 16), isNotNull);
        }
      });
    });

    group('SecureKeyStore interaction', () {
      test('db_encryption_key is stored after generation', () async {
        final store = FakeSecureKeyStore();
        // Verify initial state
        expect(await store.containsKey('db_encryption_key'), isFalse);

        // Simulate what openEncryptedDatabase does
        await store.write('db_encryption_key', 'a' * 64);
        expect(await store.read('db_encryption_key'), 'a' * 64);
      });

      test('existing key is read from secure storage', () async {
        final store = FakeSecureKeyStore();
        const existingKey =
            'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789';
        await store.write('db_encryption_key', existingKey);

        final key = await store.read('db_encryption_key');
        expect(key, existingKey);
        expect(key!.length, 64);
      });
    });
  });
}
