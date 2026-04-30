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
  });
}
