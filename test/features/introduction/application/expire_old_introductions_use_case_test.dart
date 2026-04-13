import 'package:flutter_app/features/introduction/application/expire_old_introductions_use_case.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_introduction_repository.dart';
import '../../../shared/fakes/in_memory_message_repository.dart';

void main() {
  late InMemoryIntroductionRepository introRepo;
  late InMemoryContactRepository contactRepo;
  late InMemoryMessageRepository messageRepo;

  setUp(() {
    introRepo = InMemoryIntroductionRepository();
    contactRepo = InMemoryContactRepository();
    messageRepo = InMemoryMessageRepository();
  });

  group('expireOldIntroductions', () {
    test(
      'repairs stale pending mutual acceptance rows and recreates contact',
      () async {
        await introRepo.saveIntroduction(
          IntroductionModel(
            id: 'intro-stale-mutual',
            introducerId: 'peer-A',
            recipientId: 'peer-B',
            introducedId: 'peer-C',
            introducerUsername: 'Noor',
            recipientUsername: 'Lina',
            introducedUsername: 'Sarah',
            recipientPublicKey: 'pk-peer-B',
            recipientMlKemPublicKey: 'mlkem-pk-peer-B',
            introducedPublicKey: 'pk-peer-C',
            introducedMlKemPublicKey: 'mlkem-pk-peer-C',
            recipientStatus: IntroductionStatus.accepted,
            introducedStatus: IntroductionStatus.accepted,
            status: IntroductionOverallStatus.pending,
            createdAt: '2026-03-25T12:00:00.000Z',
          ),
        );

        final repaired = await expireOldIntroductions(
          introRepo: introRepo,
          peerId: 'peer-B',
          contactRepo: contactRepo,
          messageRepo: messageRepo,
        );

        expect(repaired, 1);

        final updated = await introRepo.getIntroduction('intro-stale-mutual');
        expect(updated, isNotNull);
        expect(updated!.status, IntroductionOverallStatus.mutualAccepted);
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
      'repairs stale pending passed rows without creating a contact',
      () async {
        await introRepo.saveIntroduction(
          IntroductionModel(
            id: 'intro-stale-passed',
            introducerId: 'peer-A',
            recipientId: 'peer-B',
            introducedId: 'peer-C',
            recipientStatus: IntroductionStatus.passed,
            introducedStatus: IntroductionStatus.pending,
            status: IntroductionOverallStatus.pending,
            createdAt: '2026-03-25T12:00:00.000Z',
          ),
        );

        final repaired = await expireOldIntroductions(
          introRepo: introRepo,
          peerId: 'peer-B',
          contactRepo: contactRepo,
          messageRepo: messageRepo,
        );

        expect(repaired, 1);

        final updated = await introRepo.getIntroduction('intro-stale-passed');
        expect(updated, isNotNull);
        expect(updated!.status, IntroductionOverallStatus.passed);
        expect(await contactRepo.contactExists('peer-C'), isFalse);
        expect(await messageRepo.getMessagesForContact('peer-C'), isEmpty);
      },
    );

    test(
      'repairs stale pending expired rows without creating a contact',
      () async {
        final thirtyOneDaysAgo = DateTime.now()
            .toUtc()
            .subtract(const Duration(days: 31))
            .toIso8601String();

        await introRepo.saveIntroduction(
          IntroductionModel(
            id: 'intro-stale-expired',
            introducerId: 'peer-A',
            recipientId: 'peer-B',
            introducedId: 'peer-C',
            recipientStatus: IntroductionStatus.pending,
            introducedStatus: IntroductionStatus.pending,
            status: IntroductionOverallStatus.pending,
            createdAt: thirtyOneDaysAgo,
          ),
        );

        final repaired = await expireOldIntroductions(
          introRepo: introRepo,
          peerId: 'peer-B',
          contactRepo: contactRepo,
          messageRepo: messageRepo,
        );

        expect(repaired, 1);

        final updated = await introRepo.getIntroduction('intro-stale-expired');
        expect(updated, isNotNull);
        expect(updated!.status, IntroductionOverallStatus.expired);
        expect(await contactRepo.contactExists('peer-C'), isFalse);
        expect(await messageRepo.getMessagesForContact('peer-C'), isEmpty);
      },
    );

    test(
      'leaves alreadyConnected rows untouched during startup repair',
      () async {
        await introRepo.saveIntroduction(
          IntroductionModel(
            id: 'intro-already-connected',
            introducerId: 'peer-A',
            recipientId: 'peer-B',
            introducedId: 'peer-C',
            status: IntroductionOverallStatus.alreadyConnected,
            createdAt: '2026-01-01T12:00:00.000Z',
          ),
        );

        final repaired = await expireOldIntroductions(
          introRepo: introRepo,
          peerId: 'peer-B',
          contactRepo: contactRepo,
        );

        expect(repaired, 0);

        final updated = await introRepo.getIntroduction(
          'intro-already-connected',
        );
        expect(updated, isNotNull);
        expect(updated!.status, IntroductionOverallStatus.alreadyConnected);
      },
    );

    test(
      'later recovery settles avatar for an already-mutual-accepted contact without duplicating side effects',
      () async {
        await introRepo.saveIntroduction(
          IntroductionModel(
            id: 'intro-mutual-avatar-retry',
            introducerId: 'peer-A',
            recipientId: 'peer-B',
            introducedId: 'peer-C',
            introducerUsername: 'Noor',
            recipientUsername: 'Lina',
            introducedUsername: 'Sarah',
            recipientPublicKey: 'pk-peer-B',
            recipientMlKemPublicKey: 'mlkem-pk-peer-B',
            introducedPublicKey: 'pk-peer-C',
            introducedMlKemPublicKey: 'mlkem-pk-peer-C',
            recipientStatus: IntroductionStatus.accepted,
            introducedStatus: IntroductionStatus.accepted,
            status: IntroductionOverallStatus.mutualAccepted,
            createdAt: '2026-03-25T12:00:00.000Z',
          ),
        );

        contactRepo.addTestContact(
          ContactModel(
            peerId: 'peer-C',
            publicKey: 'pk-peer-C',
            rendezvous: '',
            username: 'Sarah',
            signature: 'sig-peer-C',
            scannedAt: '2026-03-25T12:00:00.000Z',
            introducedBy: 'Noor',
            introducedByPeerId: 'peer-A',
          ),
        );
        final bridge = PassthroughCryptoBridge();
        var downloadCalls = 0;

        final repaired = await expireOldIntroductions(
          introRepo: introRepo,
          peerId: 'peer-B',
          contactRepo: contactRepo,
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

        expect(repaired, 0);

        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(downloadCalls, 1);
        expect(await contactRepo.getContactCount(), 1);

        final contact = await contactRepo.getContact('peer-C');
        expect(contact, isNotNull);
        expect(contact!.avatarPath, 'media/avatars/peer-C.jpg');
        expect(contact.avatarVersion, 'initial');
        expect(await messageRepo.getMessagesForContact('peer-C'), isEmpty);
      },
    );
  });
}
