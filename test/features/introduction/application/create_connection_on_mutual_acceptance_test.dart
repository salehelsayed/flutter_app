import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/introduction/application/handle_mutual_acceptance_use_case.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/in_memory_contact_repository.dart';

void main() {
  late InMemoryContactRepository contactRepo;
  late IntroductionModel mutualIntro;

  setUp(() {
    contactRepo = InMemoryContactRepository();
    mutualIntro = IntroductionModel(
      id: 'intro-1',
      introducerId: 'peer-A',
      recipientId: 'peer-B',
      introducedId: 'peer-C',
      recipientStatus: IntroductionStatus.accepted,
      introducedStatus: IntroductionStatus.accepted,
      status: IntroductionOverallStatus.mutualAccepted,
      createdAt: DateTime.now().toUtc().toIso8601String(),
      introducerUsername: 'Noor',
      recipientUsername: 'Lina',
      introducedUsername: 'Sarah',
      introducedPublicKey: 'pk-peer-C',
      introducedMlKemPublicKey: 'mlkem-pk-peer-C',
    );
  });

  group('handleMutualAcceptance', () {
    test('mutual_accepted triggers contactRepo.addContact() for other party',
        () async {
      final result = await handleMutualAcceptance(
        introduction: mutualIntro,
        contactRepo: contactRepo,
        ownPeerId: 'peer-B',
      );

      expect(result, isNotNull);
      expect(await contactRepo.contactExists('peer-C'), isTrue);
    });

    test('new contact has correct peerId and username from introduction',
        () async {
      final result = await handleMutualAcceptance(
        introduction: mutualIntro,
        contactRepo: contactRepo,
        ownPeerId: 'peer-B',
      );

      expect(result!.peerId, 'peer-C');
      expect(result.username, 'Sarah');
    });

    test('new contact has introducedBy set to introducer username', () async {
      final result = await handleMutualAcceptance(
        introduction: mutualIntro,
        contactRepo: contactRepo,
        ownPeerId: 'peer-B',
      );

      expect(result!.introducedBy, 'Noor');
    });

    test('contact NOT created if already exists (idempotency)', () async {
      contactRepo.addTestContact(ContactModel(
        peerId: 'peer-C',
        publicKey: 'existing-pk',
        rendezvous: '/existing',
        username: 'ExistingSarah',
        signature: 'sig',
        scannedAt: DateTime.now().toUtc().toIso8601String(),
      ));

      final result = await handleMutualAcceptance(
        introduction: mutualIntro,
        contactRepo: contactRepo,
        ownPeerId: 'peer-B',
      );

      expect(result, isNull);
      // Existing contact unchanged
      final contact = await contactRepo.getContact('peer-C');
      expect(contact!.username, 'ExistingSarah');
    });

    test('contact NOT created if status != mutual_accepted', () async {
      final pendingIntro = mutualIntro.copyWith(
        status: IntroductionOverallStatus.pending,
      );

      final result = await handleMutualAcceptance(
        introduction: pendingIntro,
        contactRepo: contactRepo,
        ownPeerId: 'peer-B',
      );

      expect(result, isNull);
      expect(await contactRepo.contactExists('peer-C'), isFalse);
    });

    test('recipient gets contact for introduced party', () async {
      final result = await handleMutualAcceptance(
        introduction: mutualIntro,
        contactRepo: contactRepo,
        ownPeerId: 'peer-B', // recipient
      );

      expect(result!.peerId, 'peer-C'); // introduced party
    });

    test('introduced party gets contact for recipient', () async {
      final result = await handleMutualAcceptance(
        introduction: mutualIntro,
        contactRepo: contactRepo,
        ownPeerId: 'peer-C', // introduced party
      );

      expect(result!.peerId, 'peer-B'); // recipient
      expect(result.username, 'Lina');
    });

    test('new contact has mlKemPublicKey from introduction', () async {
      final result = await handleMutualAcceptance(
        introduction: mutualIntro,
        contactRepo: contactRepo,
        ownPeerId: 'peer-B',
      );

      expect(result!.mlKemPublicKey, 'mlkem-pk-peer-C');
    });
  });

  group('ConnectionFeedItem.fromContact', () {
    test('populates introducedBy from contact field', () {
      final contact = ContactModel(
        peerId: 'peer-C',
        publicKey: 'pk',
        rendezvous: '',
        username: 'Sarah',
        signature: 'sig',
        scannedAt: DateTime.now().toUtc().toIso8601String(),
        introducedBy: 'Noor',
      );

      final feedItem = ConnectionFeedItem.fromContact(contact);
      expect(feedItem.introducedBy, 'Noor');
    });
  });
}
