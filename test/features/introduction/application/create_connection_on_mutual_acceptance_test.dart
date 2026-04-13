import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/introduction/application/handle_mutual_acceptance_use_case.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_message_repository.dart';

void main() {
  late InMemoryContactRepository contactRepo;
  late InMemoryMessageRepository messageRepo;
  late IntroductionModel mutualIntro;

  setUp(() {
    contactRepo = InMemoryContactRepository();
    messageRepo = InMemoryMessageRepository();
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
    test(
      'mutual_accepted triggers contactRepo.addContact() for other party',
      () async {
        final result = await handleMutualAcceptance(
          introduction: mutualIntro,
          contactRepo: contactRepo,
          ownPeerId: 'peer-B',
        );

        expect(result, isNotNull);
        expect(await contactRepo.contactExists('peer-C'), isTrue);
      },
    );

    test(
      'new contact has correct peerId and username from introduction',
      () async {
        final result = await handleMutualAcceptance(
          introduction: mutualIntro,
          contactRepo: contactRepo,
          ownPeerId: 'peer-B',
        );

        expect(result!.peerId, 'peer-C');
        expect(result.username, 'Sarah');
      },
    );

    test('new contact has introducedBy set to introducer username', () async {
      final result = await handleMutualAcceptance(
        introduction: mutualIntro,
        contactRepo: contactRepo,
        ownPeerId: 'peer-B',
      );

      expect(result!.introducedBy, 'Noor');
    });

    test('contact NOT created if already exists (idempotency)', () async {
      contactRepo.addTestContact(
        ContactModel(
          peerId: 'peer-C',
          publicKey: 'existing-pk',
          rendezvous: '/existing',
          username: 'ExistingSarah',
          signature: 'sig',
          scannedAt: DateTime.now().toUtc().toIso8601String(),
        ),
      );

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

    test(
      'stores a meaningful system message in the new conversation',
      () async {
        await handleMutualAcceptance(
          introduction: mutualIntro,
          contactRepo: contactRepo,
          ownPeerId: 'peer-B',
          messageRepo: messageRepo,
        );

        final messages = await messageRepo.getMessagesForContact('peer-C');
        expect(messages, hasLength(1));
        expect(
          messages.single.text,
          'You and Sarah are now connected — introduced by Noor',
        );
      },
    );

    test(
      'avatar retry failure does not roll back the created contact or system message',
      () async {
        final bridge = PassthroughCryptoBridge();
        var downloadCalls = 0;

        final result = await handleMutualAcceptance(
          introduction: mutualIntro,
          contactRepo: contactRepo,
          ownPeerId: 'peer-B',
          messageRepo: messageRepo,
          bridge: bridge,
          downloadProfilePictureFn:
              ({
                required bridge,
                required contactRepo,
                required ownerPeerId,
                required avatarVersion,
              }) async {
                downloadCalls++;
                if (downloadCalls == 1) {
                  return null;
                }
                throw StateError('avatar retry failed');
              },
        );

        expect(result, isNotNull);
        expect(await contactRepo.contactExists('peer-C'), isTrue);

        await Future<void>.delayed(
          const Duration(seconds: 5, milliseconds: 50),
        );

        expect(downloadCalls, 2);
        expect(await contactRepo.contactExists('peer-C'), isTrue);

        final messages = await messageRepo.getMessagesForContact('peer-C');
        expect(messages, hasLength(1));
        expect(
          messages.single.text,
          'You and Sarah are now connected — introduced by Noor',
        );
      },
    );

    test(
      'existing mutual-acceptance contact without avatar retries settlement without duplicating system message',
      () async {
        await handleMutualAcceptance(
          introduction: mutualIntro,
          contactRepo: contactRepo,
          ownPeerId: 'peer-B',
          messageRepo: messageRepo,
        );

        final bridge = PassthroughCryptoBridge();
        var downloadCalls = 0;

        final result = await handleMutualAcceptance(
          introduction: mutualIntro,
          contactRepo: contactRepo,
          ownPeerId: 'peer-B',
          messageRepo: messageRepo,
          bridge: bridge,
          downloadProfilePictureFn:
              ({
                required bridge,
                required contactRepo,
                required ownerPeerId,
                required avatarVersion,
              }) async {
                downloadCalls++;
                final existing = await contactRepo.getContact(ownerPeerId);
                final updated = existing!.copyWith(
                  avatarPath: 'media/avatars/$ownerPeerId.jpg',
                  avatarVersion: avatarVersion,
                );
                await contactRepo.addContact(updated);
                return updated;
              },
        );

        expect(result, isNull);

        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(downloadCalls, 1);
        final contact = await contactRepo.getContact('peer-C');
        expect(contact, isNotNull);
        expect(contact!.avatarPath, 'media/avatars/peer-C.jpg');
        expect(contact.avatarVersion, 'initial');

        final messages = await messageRepo.getMessagesForContact('peer-C');
        expect(messages, hasLength(1));
        expect(
          messages.single.text,
          'You and Sarah are now connected — introduced by Noor',
        );
      },
    );
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
