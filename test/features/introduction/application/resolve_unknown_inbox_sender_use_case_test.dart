import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/introduction/application/resolve_unknown_inbox_sender_use_case.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';

import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_introduction_repository.dart';

void main() {
  late InMemoryIntroductionRepository introRepo;
  late InMemoryContactRepository contactRepo;
  late String createdAt;

  setUp(() {
    introRepo = InMemoryIntroductionRepository();
    contactRepo = InMemoryContactRepository();
    createdAt = DateTime.utc(2026, 4, 3, 12).toIso8601String();
  });

  IntroductionModel makeIntro({
    required String id,
    required String ownPeerId,
    required String otherPeerId,
    required bool ownIsRecipient,
    IntroductionStatus recipientStatus = IntroductionStatus.pending,
    IntroductionStatus introducedStatus = IntroductionStatus.pending,
    IntroductionOverallStatus status = IntroductionOverallStatus.pending,
  }) {
    return IntroductionModel(
      id: id,
      introducerId: 'peer-introducer',
      recipientId: ownIsRecipient ? ownPeerId : otherPeerId,
      introducedId: ownIsRecipient ? otherPeerId : ownPeerId,
      recipientStatus: recipientStatus,
      introducedStatus: introducedStatus,
      status: status,
      createdAt: createdAt,
      introducerUsername: 'Introducer',
      recipientUsername: ownIsRecipient ? 'You' : 'Other',
      introducedUsername: ownIsRecipient ? 'Other' : 'You',
      recipientPublicKey: ownIsRecipient ? 'pk-you' : 'pk-other',
      recipientMlKemPublicKey: ownIsRecipient ? 'mlkem-you' : 'mlkem-other',
      introducedPublicKey: ownIsRecipient ? 'pk-other' : 'pk-you',
      introducedMlKemPublicKey: ownIsRecipient ? 'mlkem-other' : 'mlkem-you',
    );
  }

  group('resolveUnknownInboxSender', () {
    test('rejects senders with no matching introduction', () async {
      final resolution = await resolveUnknownInboxSender(
        introRepo: introRepo,
        contactRepo: contactRepo,
        ownPeerId: 'peer-you',
        senderPeerId: 'peer-stranger',
      );

      expect(resolution, UnknownInboxSenderResolution.rejected);
    });

    test(
      'rejects pending introductions when own side has not accepted',
      () async {
        await introRepo.saveIntroduction(
          makeIntro(
            id: 'intro-pending-no-accept',
            ownPeerId: 'peer-you',
            otherPeerId: 'peer-other',
            ownIsRecipient: true,
          ),
        );

        final resolution = await resolveUnknownInboxSender(
          introRepo: introRepo,
          contactRepo: contactRepo,
          ownPeerId: 'peer-you',
          senderPeerId: 'peer-other',
        );

        expect(resolution, UnknownInboxSenderResolution.rejected);
      },
    );

    test(
      'keeps the message retryable once own side accepted the intro',
      () async {
        await introRepo.saveIntroduction(
          makeIntro(
            id: 'intro-own-accepted',
            ownPeerId: 'peer-you',
            otherPeerId: 'peer-other',
            ownIsRecipient: true,
            recipientStatus: IntroductionStatus.accepted,
          ),
        );

        final resolution = await resolveUnknownInboxSender(
          introRepo: introRepo,
          contactRepo: contactRepo,
          ownPeerId: 'peer-you',
          senderPeerId: 'peer-other',
        );

        expect(resolution, UnknownInboxSenderResolution.retryable);
      },
    );

    test(
      'recreates a mutually accepted contact and marks the message recoverable',
      () async {
        await introRepo.saveIntroduction(
          makeIntro(
            id: 'intro-mutual',
            ownPeerId: 'peer-you',
            otherPeerId: 'peer-other',
            ownIsRecipient: true,
            recipientStatus: IntroductionStatus.accepted,
            introducedStatus: IntroductionStatus.accepted,
            status: IntroductionOverallStatus.mutualAccepted,
          ),
        );

        final resolution = await resolveUnknownInboxSender(
          introRepo: introRepo,
          contactRepo: contactRepo,
          ownPeerId: 'peer-you',
          senderPeerId: 'peer-other',
        );

        expect(resolution, UnknownInboxSenderResolution.contactRecovered);
        final recovered = await contactRepo.getContact('peer-other');
        expect(recovered, isNotNull);
        expect(recovered!.peerId, 'peer-other');
        expect(recovered.username, 'Other');
        expect(recovered.introducedBy, 'Introducer');
        expect(recovered.mlKemPublicKey, 'mlkem-other');
      },
    );

    test('does not retry passed or expired introductions', () async {
      await introRepo.saveIntroduction(
        makeIntro(
          id: 'intro-passed',
          ownPeerId: 'peer-you',
          otherPeerId: 'peer-other',
          ownIsRecipient: false,
          introducedStatus: IntroductionStatus.accepted,
          status: IntroductionOverallStatus.passed,
        ),
      );
      await introRepo.saveIntroduction(
        makeIntro(
          id: 'intro-expired',
          ownPeerId: 'peer-you',
          otherPeerId: 'peer-other',
          ownIsRecipient: true,
          recipientStatus: IntroductionStatus.accepted,
          status: IntroductionOverallStatus.expired,
        ),
      );

      final resolution = await resolveUnknownInboxSender(
        introRepo: introRepo,
        contactRepo: contactRepo,
        ownPeerId: 'peer-you',
        senderPeerId: 'peer-other',
      );

      expect(resolution, UnknownInboxSenderResolution.rejected);
    });

    test(
      'treats already-connected intros without a local row as retryable',
      () async {
        await introRepo.saveIntroduction(
          makeIntro(
            id: 'intro-already-connected',
            ownPeerId: 'peer-you',
            otherPeerId: 'peer-other',
            ownIsRecipient: true,
            recipientStatus: IntroductionStatus.accepted,
            introducedStatus: IntroductionStatus.accepted,
            status: IntroductionOverallStatus.alreadyConnected,
          ),
        );

        final resolution = await resolveUnknownInboxSender(
          introRepo: introRepo,
          contactRepo: contactRepo,
          ownPeerId: 'peer-you',
          senderPeerId: 'peer-other',
        );

        expect(resolution, UnknownInboxSenderResolution.retryable);
      },
    );

    test(
      'reports already-connected intros as recovered when the contact exists',
      () async {
        contactRepo.addTestContact(
          ContactModel(
            peerId: 'peer-other',
            publicKey: 'pk-other',
            rendezvous: '',
            username: 'Other',
            signature: 'sig-other',
            scannedAt: createdAt,
            mlKemPublicKey: 'mlkem-other',
          ),
        );
        await introRepo.saveIntroduction(
          makeIntro(
            id: 'intro-already-connected-existing-contact',
            ownPeerId: 'peer-you',
            otherPeerId: 'peer-other',
            ownIsRecipient: true,
            recipientStatus: IntroductionStatus.accepted,
            introducedStatus: IntroductionStatus.accepted,
            status: IntroductionOverallStatus.alreadyConnected,
          ),
        );

        final resolution = await resolveUnknownInboxSender(
          introRepo: introRepo,
          contactRepo: contactRepo,
          ownPeerId: 'peer-you',
          senderPeerId: 'peer-other',
        );

        expect(resolution, UnknownInboxSenderResolution.contactRecovered);
      },
    );
  });
}
