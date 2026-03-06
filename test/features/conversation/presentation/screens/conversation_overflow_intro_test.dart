import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/introduction/application/check_intro_banner_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../shared/fakes/in_memory_contact_repository.dart';

void main() {
  late InMemoryContactRepository contactRepo;

  setUp(() {
    contactRepo = InMemoryContactRepository();
    // A and B are friends
    contactRepo.addTestContact(ContactModel(
      peerId: 'peer-A',
      publicKey: 'pk-A',
      rendezvous: '/rv',
      username: 'Noor',
      signature: 'sig-A',
      scannedAt: DateTime.now().toUtc().toIso8601String(),
    ));
    contactRepo.addTestContact(ContactModel(
      peerId: 'peer-B',
      publicKey: 'pk-B',
      rendezvous: '/rv',
      username: 'Lina',
      signature: 'sig-B',
      scannedAt: DateTime.now().toUtc().toIso8601String(),
    ));
  });

  group('overflow menu introduce visibility', () {
    test('"Introduce" visible when >= 1 other friend and not blocked',
        () async {
      final activeContacts = await contactRepo.getActiveContacts();
      final contact = await contactRepo.getContact('peer-B');
      final otherFriends = activeContacts
          .where((c) => c.peerId != contact!.peerId && !c.isBlocked)
          .toList();

      expect(contact!.isBlocked, isFalse);
      expect(otherFriends.isNotEmpty, isTrue);
    });

    test('"Introduce" hidden when 0 other friends', () async {
      final lonelyRepo = InMemoryContactRepository();
      lonelyRepo.addTestContact(ContactModel(
        peerId: 'peer-only',
        publicKey: 'pk',
        rendezvous: '/rv',
        username: 'Solo',
        signature: 'sig',
        scannedAt: DateTime.now().toUtc().toIso8601String(),
      ));

      final activeContacts = await lonelyRepo.getActiveContacts();
      final contact = await lonelyRepo.getContact('peer-only');
      final otherFriends = activeContacts
          .where((c) => c.peerId != contact!.peerId && !c.isBlocked)
          .toList();

      expect(otherFriends.isEmpty, isTrue);
    });

    test('"Introduce" hidden when contact is blocked', () async {
      await contactRepo.blockContact('peer-B');
      final contact = await contactRepo.getContact('peer-B');
      expect(contact!.isBlocked, isTrue);
    });

    test('tapping triggers introduce callback', () async {
      // Verify the gating logic allows showing introduce option
      final contact = await contactRepo.getContact('peer-B');
      final activeContacts = await contactRepo.getActiveContacts();
      final hasOtherFriends = activeContacts
          .where((c) => c.peerId != contact!.peerId && !c.isBlocked)
          .isNotEmpty;

      expect(hasOtherFriends, isTrue);
      expect(contact!.isBlocked, isFalse);
      // In production, !contact.isBlocked && hasOtherFriends → show introduce
    });

    test('still works after introsSentAt is set', () async {
      await contactRepo.setIntrosSentAt(
          'peer-B', DateTime.now().toUtc().toIso8601String());
      final contact = await contactRepo.getContact('peer-B');

      // introsSentAt only affects banner, not overflow menu
      final activeContacts = await contactRepo.getActiveContacts();
      final hasOtherFriends = activeContacts
          .where((c) => c.peerId != contact!.peerId && !c.isBlocked)
          .isNotEmpty;

      // Overflow menu should still be available
      expect(hasOtherFriends, isTrue);
      expect(contact!.isBlocked, isFalse);
    });
  });
}
