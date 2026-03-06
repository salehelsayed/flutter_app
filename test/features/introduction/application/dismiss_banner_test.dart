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
  group('dismiss banner behavior', () {
    late InMemoryContactRepository contactRepo;

    setUp(() {
      contactRepo = InMemoryContactRepository();
    });

    test('dismissIntroBanner sets introsBannerDismissed to true', () async {
      final contact = _makeContact(peerId: 'peer-1', username: 'Alice');
      contactRepo.addTestContact(contact);

      await contactRepo.dismissIntroBanner('peer-1');

      final updated = await contactRepo.getContact('peer-1');
      expect(updated!.introsBannerDismissed, isTrue);
    });

    test('banner does not show after dismissal', () async {
      final target = _makeContact(peerId: 'peer-1', username: 'Alice');
      contactRepo.addTestContact(target);
      contactRepo.addTestContact(
          _makeContact(peerId: 'peer-2', username: 'Bob'));

      await contactRepo.dismissIntroBanner('peer-1');

      final dismissed = await contactRepo.getContact('peer-1');
      final result = await shouldShowIntroBanner(
        contactRepo: contactRepo,
        contact: dismissed!,
        messageCount: 0,
      );

      expect(result, isFalse);
    });

    test('setIntrosSentAt records timestamp', () async {
      final contact = _makeContact(peerId: 'peer-1', username: 'Alice');
      contactRepo.addTestContact(contact);

      final timestamp = DateTime.now().toUtc().toIso8601String();
      await contactRepo.setIntrosSentAt('peer-1', timestamp);

      final updated = await contactRepo.getContact('peer-1');
      expect(updated!.introsSentAt, equals(timestamp));
    });

    test('introsSentAt causes banner to hide', () async {
      final target = _makeContact(peerId: 'peer-1', username: 'Alice');
      contactRepo.addTestContact(target);
      contactRepo.addTestContact(
          _makeContact(peerId: 'peer-2', username: 'Bob'));

      final timestamp = DateTime.now().toUtc().toIso8601String();
      await contactRepo.setIntrosSentAt('peer-1', timestamp);

      final updated = await contactRepo.getContact('peer-1');
      final result = await shouldShowIntroBanner(
        contactRepo: contactRepo,
        contact: updated!,
        messageCount: 0,
      );

      expect(result, isFalse);
    });

    test('introsBannerDismissed defaults to false on new contact', () async {
      final contact = _makeContact(peerId: 'peer-1', username: 'Alice');
      contactRepo.addTestContact(contact);

      final stored = await contactRepo.getContact('peer-1');
      expect(stored!.introsBannerDismissed, isFalse);
    });

    test('introsSentAt defaults to null on new contact', () async {
      final contact = _makeContact(peerId: 'peer-1', username: 'Alice');
      contactRepo.addTestContact(contact);

      final stored = await contactRepo.getContact('peer-1');
      expect(stored!.introsSentAt, isNull);
    });

    test('dismissIntroBanner is idempotent', () async {
      final contact = _makeContact(peerId: 'peer-1', username: 'Alice');
      contactRepo.addTestContact(contact);

      await contactRepo.dismissIntroBanner('peer-1');
      await contactRepo.dismissIntroBanner('peer-1');

      final updated = await contactRepo.getContact('peer-1');
      expect(updated!.introsBannerDismissed, isTrue);
    });

    test('setIntrosSentAt can be updated', () async {
      final contact = _makeContact(peerId: 'peer-1', username: 'Alice');
      contactRepo.addTestContact(contact);

      final first = '2026-03-01T00:00:00.000Z';
      final second = '2026-03-05T12:00:00.000Z';

      await contactRepo.setIntrosSentAt('peer-1', first);
      await contactRepo.setIntrosSentAt('peer-1', second);

      final updated = await contactRepo.getContact('peer-1');
      expect(updated!.introsSentAt, equals(second));
    });
  });
}
