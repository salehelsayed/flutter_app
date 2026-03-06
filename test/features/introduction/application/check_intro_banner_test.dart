import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/introduction/application/check_intro_banner_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/in_memory_contact_repository.dart';

/// Helper to build a [ContactModel] with sensible defaults.
ContactModel _makeContact({
  required String peerId,
  String username = 'User',
  bool isBlocked = false,
  bool isArchived = false,
  bool introsBannerDismissed = false,
  String? introsSentAt,
}) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/ip4/127.0.0.1/tcp/0',
    username: username,
    signature: 'sig-$peerId',
    scannedAt: DateTime.now().toUtc().toIso8601String(),
    isBlocked: isBlocked,
    isArchived: isArchived,
    introsBannerDismissed: introsBannerDismissed,
    introsSentAt: introsSentAt,
  );
}

void main() {
  late InMemoryContactRepository contactRepo;

  setUp(() {
    contactRepo = InMemoryContactRepository();
  });

  group('shouldShowIntroBanner', () {
    test('returns true when all conditions met', () async {
      final contact = _makeContact(peerId: 'peer-target', username: 'Bob');
      final otherFriend = _makeContact(peerId: 'peer-friend', username: 'Eve');
      contactRepo.addTestContact(contact);
      contactRepo.addTestContact(otherFriend);

      final result = await shouldShowIntroBanner(
        contactRepo: contactRepo,
        contact: contact,
        messageCount: 0,
      );

      expect(result, isTrue);
    });

    test('returns false when contact is blocked', () async {
      final contact = _makeContact(peerId: 'peer-blocked', isBlocked: true);
      final otherFriend = _makeContact(peerId: 'peer-friend');
      contactRepo.addTestContact(contact);
      contactRepo.addTestContact(otherFriend);

      final result = await shouldShowIntroBanner(
        contactRepo: contactRepo,
        contact: contact,
        messageCount: 0,
      );

      expect(result, isFalse);
    });

    test('returns false when contact is archived', () async {
      final contact = _makeContact(peerId: 'peer-archived', isArchived: true);
      final otherFriend = _makeContact(peerId: 'peer-friend');
      contactRepo.addTestContact(contact);
      contactRepo.addTestContact(otherFriend);

      final result = await shouldShowIntroBanner(
        contactRepo: contactRepo,
        contact: contact,
        messageCount: 0,
      );

      expect(result, isFalse);
    });

    test('returns false when banner already dismissed', () async {
      final contact = _makeContact(
        peerId: 'peer-dismissed',
        introsBannerDismissed: true,
      );
      final otherFriend = _makeContact(peerId: 'peer-friend');
      contactRepo.addTestContact(contact);
      contactRepo.addTestContact(otherFriend);

      final result = await shouldShowIntroBanner(
        contactRepo: contactRepo,
        contact: contact,
        messageCount: 0,
      );

      expect(result, isFalse);
    });

    test('returns false when intros already sent', () async {
      final contact = _makeContact(
        peerId: 'peer-sent',
        introsSentAt: DateTime.now().toUtc().toIso8601String(),
      );
      final otherFriend = _makeContact(peerId: 'peer-friend');
      contactRepo.addTestContact(contact);
      contactRepo.addTestContact(otherFriend);

      final result = await shouldShowIntroBanner(
        contactRepo: contactRepo,
        contact: contact,
        messageCount: 0,
      );

      expect(result, isFalse);
    });

    test('returns false when messageCount >= 3', () async {
      final contact = _makeContact(peerId: 'peer-chatty');
      final otherFriend = _makeContact(peerId: 'peer-friend');
      contactRepo.addTestContact(contact);
      contactRepo.addTestContact(otherFriend);

      final result = await shouldShowIntroBanner(
        contactRepo: contactRepo,
        contact: contact,
        messageCount: 3,
      );

      expect(result, isFalse);
    });

    test('returns false when no other active contacts exist', () async {
      final contact = _makeContact(peerId: 'peer-lonely');
      contactRepo.addTestContact(contact);
      // No other contacts added

      final result = await shouldShowIntroBanner(
        contactRepo: contactRepo,
        contact: contact,
        messageCount: 0,
      );

      expect(result, isFalse);
    });
  });
}
