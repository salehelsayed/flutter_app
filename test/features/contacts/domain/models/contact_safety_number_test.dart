import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/contacts/domain/models/contact_safety_number.dart';

void main() {
  group('ContactSafetyNumber', () {
    test('builds stable grouped digits for the same key material', () {
      final first = ContactSafetyNumber.build(
        peerId: 'peer-alice',
        publicKey: 'pk-alice',
        mlKemPublicKey: 'mlkem-alice',
      );
      final second = ContactSafetyNumber.build(
        peerId: 'peer-alice',
        publicKey: 'pk-alice',
        mlKemPublicKey: 'mlkem-alice',
      );

      expect(first, second);
      expect(first, matches(RegExp(r'^\d{4} \d{4} \d{4}$')));
    });

    test('changes when identity key material changes', () {
      final saved = ContactSafetyNumber.build(
        peerId: 'peer-alice',
        publicKey: 'pk-alice',
        mlKemPublicKey: 'mlkem-alice',
      );
      final changed = ContactSafetyNumber.build(
        peerId: 'peer-alice',
        publicKey: 'pk-alice-rotated',
        mlKemPublicKey: 'mlkem-alice',
      );

      expect(changed, isNot(saved));
    });

    test('returns null when comparable public key material is missing', () {
      expect(
        ContactSafetyNumber.build(peerId: 'peer-alice', publicKey: null),
        isNull,
      );
      expect(
        ContactSafetyNumber.build(peerId: 'peer-alice', publicKey: '  '),
        isNull,
      );
      expect(ContactSafetyNumber.build(peerId: ' ', publicKey: 'pk'), isNull);
    });

    group('B4 per-device fingerprints', () {
      test('empty deviceFingerprints is byte-identical to the v1 number', () {
        final v1 = ContactSafetyNumber.build(
          peerId: 'peer-alice',
          publicKey: 'pk-alice',
          mlKemPublicKey: 'mlkem-alice',
        );
        final withEmpty = ContactSafetyNumber.build(
          peerId: 'peer-alice',
          publicKey: 'pk-alice',
          mlKemPublicKey: 'mlkem-alice',
          deviceFingerprints: const [],
        );
        expect(withEmpty, v1, reason: 'non-breaking: empty == account-level v1');
      });

      test('a non-empty device set produces a DIFFERENT (v2) number', () {
        final accountOnly = ContactSafetyNumber.build(
          peerId: 'peer-alice',
          publicKey: 'pk-alice',
          mlKemPublicKey: 'mlkem-alice',
        );
        final withDevices = ContactSafetyNumber.build(
          peerId: 'peer-alice',
          publicKey: 'pk-alice',
          mlKemPublicKey: 'mlkem-alice',
          deviceFingerprints: const ['dev-a-sign:dev-a-mlkem:'],
        );
        expect(withDevices, isNot(accountOnly));
        expect(withDevices, matches(RegExp(r'^\d{4} \d{4} \d{4}$')));
      });

      test('device fingerprints are order-independent (sorted)', () {
        final ab = ContactSafetyNumber.build(
          peerId: 'p',
          publicKey: 'pk',
          deviceFingerprints: const ['a', 'b'],
        );
        final ba = ContactSafetyNumber.build(
          peerId: 'p',
          publicKey: 'pk',
          deviceFingerprints: const ['b', 'a'],
        );
        expect(ab, ba);
      });

      test('adding a device changes the number', () {
        final one = ContactSafetyNumber.build(
          peerId: 'p',
          publicKey: 'pk',
          deviceFingerprints: const ['a'],
        );
        final two = ContactSafetyNumber.build(
          peerId: 'p',
          publicKey: 'pk',
          deviceFingerprints: const ['a', 'b'],
        );
        expect(two, isNot(one));
      });
    });
  });
}
