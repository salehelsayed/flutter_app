import 'package:flutter_app/features/introduction/application/check_intro_banner_use_case.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/in_memory_contact_repository.dart';

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
  group('shouldShowIntroBanner extended', () {
    late InMemoryContactRepository contactRepo;

    setUp(() {
      contactRepo = InMemoryContactRepository();
    });

    test('returns true with messageCount 0 and multiple friends', () async {
      final target = _makeContact(peerId: 'peer-1', username: 'Alice');
      contactRepo.addTestContact(target);
      contactRepo.addTestContact(
          _makeContact(peerId: 'peer-2', username: 'Bob'));
      contactRepo.addTestContact(
          _makeContact(peerId: 'peer-3', username: 'Charlie'));
      contactRepo.addTestContact(
          _makeContact(peerId: 'peer-4', username: 'Dana'));

      final result = await shouldShowIntroBanner(
        contactRepo: contactRepo,
        contact: target,
        messageCount: 0,
      );

      expect(result, isTrue);
    });

    test('returns false at exactly messageCount 3', () async {
      final target = _makeContact(peerId: 'peer-1', username: 'Alice');
      contactRepo.addTestContact(target);
      contactRepo.addTestContact(
          _makeContact(peerId: 'peer-2', username: 'Bob'));

      final result = await shouldShowIntroBanner(
        contactRepo: contactRepo,
        contact: target,
        messageCount: 3,
      );

      expect(result, isFalse);
    });

    test('returns true at messageCount 2', () async {
      final target = _makeContact(peerId: 'peer-1', username: 'Alice');
      contactRepo.addTestContact(target);
      contactRepo.addTestContact(
          _makeContact(peerId: 'peer-2', username: 'Bob'));

      final result = await shouldShowIntroBanner(
        contactRepo: contactRepo,
        contact: target,
        messageCount: 2,
      );

      expect(result, isTrue);
    });

    test('returns false when only other contact is blocked', () async {
      final target = _makeContact(peerId: 'peer-1', username: 'Alice');
      contactRepo.addTestContact(target);
      contactRepo.addTestContact(
          _makeContact(peerId: 'peer-2', username: 'Bob', isBlocked: true));

      final result = await shouldShowIntroBanner(
        contactRepo: contactRepo,
        contact: target,
        messageCount: 0,
      );

      expect(result, isFalse);
    });

    test('returns false when only other contact is archived', () async {
      final target = _makeContact(peerId: 'peer-1', username: 'Alice');
      contactRepo.addTestContact(target);
      contactRepo.addTestContact(
          _makeContact(peerId: 'peer-2', username: 'Bob', isArchived: true));

      final result = await shouldShowIntroBanner(
        contactRepo: contactRepo,
        contact: target,
        messageCount: 0,
      );

      expect(result, isFalse);
    });
  });
}
