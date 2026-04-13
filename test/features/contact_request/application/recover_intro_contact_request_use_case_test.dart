import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contact_request/application/recover_intro_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart'
    show ContactRequestStatus;
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';

import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_contact_request_repository.dart';
import '../../../shared/fakes/in_memory_introduction_repository.dart';
import '../../../shared/fakes/in_memory_message_repository.dart';

void main() {
  late InMemoryIntroductionRepository introRepo;
  late InMemoryContactRepository contactRepo;
  late InMemoryContactRequestRepository requestRepo;
  late InMemoryMessageRepository messageRepo;

  const ownPeerId = 'peer-b';
  const otherPeerId = 'peer-c';
  const createdAt = '2026-04-03T12:00:00.000Z';

  setUp(() {
    introRepo = InMemoryIntroductionRepository();
    contactRepo = InMemoryContactRepository();
    requestRepo = InMemoryContactRequestRepository();
    messageRepo = InMemoryMessageRepository();
  });

  IntroductionModel makeIntro({
    required String id,
    String introducerId = 'peer-a',
    String introducerUsername = 'Noor',
    IntroductionStatus recipientStatus = IntroductionStatus.accepted,
    IntroductionStatus introducedStatus = IntroductionStatus.pending,
    IntroductionOverallStatus status = IntroductionOverallStatus.pending,
    String? recipientMlKemPublicKey = 'mlkem-peer-b',
    String? introducedMlKemPublicKey = 'mlkem-peer-c',
  }) {
    return IntroductionModel(
      id: id,
      introducerId: introducerId,
      recipientId: ownPeerId,
      introducedId: otherPeerId,
      recipientStatus: recipientStatus,
      introducedStatus: introducedStatus,
      status: status,
      createdAt: createdAt,
      introducerUsername: introducerUsername,
      recipientUsername: 'Basma',
      introducedUsername: 'Dora',
      recipientPublicKey: 'pk-peer-b',
      recipientMlKemPublicKey: recipientMlKemPublicKey,
      introducedPublicKey: 'pk-peer-c',
      introducedMlKemPublicKey: introducedMlKemPublicKey,
    );
  }

  VerifiedContactRequestEnvelope makeRequest({String? mlKemPublicKey}) {
    return VerifiedContactRequestEnvelope(
      peerId: otherPeerId,
      publicKey: 'pk-peer-c',
      rendezvous: '/dns4/relay/tcp/443',
      username: 'Dora',
      signature: 'sig-peer-c',
      mlKemPublicKey: mlKemPublicKey,
    );
  }

  Future<void> seedPendingRequest() {
    return requestRepo.addRequest(
      const ContactRequestModel(
        peerId: otherPeerId,
        publicKey: 'pk-peer-c',
        rendezvous: '/dns4/relay/tcp/443',
        username: 'Dora',
        signature: 'sig-peer-c',
        receivedAt: createdAt,
        status: ContactRequestStatus.pending,
      ),
    );
  }

  group('recoverIntroContactRequest', () {
    test(
      'recovers a missing contact through the intro path and converges the intro',
      () async {
        await introRepo.saveIntroduction(makeIntro(id: 'intro-recover'));

        final result = await recoverIntroContactRequest(
          introRepo: introRepo,
          requestRepo: requestRepo,
          contactRepo: contactRepo,
          ownPeerId: ownPeerId,
          request: makeRequest(),
          messageRepo: messageRepo,
        );

        expect(result.action, IntroContactRequestRecoveryAction.recovered);
        expect(result.contact, isNotNull);
        expect(result.contact!.peerId, otherPeerId);
        expect(result.contact!.introducedBy, 'Noor');
        expect(result.contact!.introducedByPeerId, 'peer-a');
        expect(result.contact!.mlKemPublicKey, 'mlkem-peer-c');

        final updatedIntro = await introRepo.getIntroduction('intro-recover');
        expect(updatedIntro, isNotNull);
        expect(updatedIntro!.recipientStatus, IntroductionStatus.accepted);
        expect(updatedIntro.introducedStatus, IntroductionStatus.accepted);
        expect(updatedIntro.status, IntroductionOverallStatus.mutualAccepted);
        expect(
          await introRepo.getPendingIntroductionsForUser(ownPeerId),
          isEmpty,
        );

        final messages = await messageRepo.getMessagesForContact(otherPeerId);
        expect(messages, hasLength(1));
      },
    );

    test(
      'fills a missing ML-KEM key once on an existing contact and preserves intro provenance',
      () async {
        await introRepo.saveIntroduction(
          makeIntro(
            id: 'intro-existing-contact',
            introducedMlKemPublicKey: null,
          ),
        );
        contactRepo.addTestContact(
          const ContactModel(
            peerId: otherPeerId,
            publicKey: 'pk-peer-c',
            rendezvous: '/dns4/relay/tcp/443',
            username: 'Dora',
            signature: 'sig-peer-c',
            scannedAt: createdAt,
          ),
        );

        final result = await recoverIntroContactRequest(
          introRepo: introRepo,
          requestRepo: requestRepo,
          contactRepo: contactRepo,
          ownPeerId: ownPeerId,
          request: makeRequest(mlKemPublicKey: 'incoming-mlkem-peer-c'),
          messageRepo: messageRepo,
        );

        expect(result.action, IntroContactRequestRecoveryAction.recovered);
        expect(result.contactKeyUpdated, isTrue);
        expect(result.contact, isNotNull);
        expect(result.contact!.mlKemPublicKey, 'incoming-mlkem-peer-c');
        expect(result.contact!.introducedBy, 'Noor');
        expect(result.contact!.introducedByPeerId, 'peer-a');

        final updatedIntro = await introRepo.getIntroduction(
          'intro-existing-contact',
        );
        expect(updatedIntro!.status, IntroductionOverallStatus.mutualAccepted);
      },
    );

    test(
      'does not overwrite an existing ML-KEM key and does not create a duplicate contact',
      () async {
        await introRepo.saveIntroduction(
          makeIntro(id: 'intro-existing-key', introducedMlKemPublicKey: null),
        );
        contactRepo.addTestContact(
          const ContactModel(
            peerId: otherPeerId,
            publicKey: 'pk-peer-c',
            rendezvous: '/dns4/relay/tcp/443',
            username: 'Dora',
            signature: 'sig-peer-c',
            scannedAt: createdAt,
            mlKemPublicKey: 'existing-mlkem-peer-c',
          ),
        );

        final result = await recoverIntroContactRequest(
          introRepo: introRepo,
          requestRepo: requestRepo,
          contactRepo: contactRepo,
          ownPeerId: ownPeerId,
          request: makeRequest(mlKemPublicKey: 'different-mlkem-peer-c'),
          messageRepo: messageRepo,
        );

        expect(result.action, IntroContactRequestRecoveryAction.recovered);
        expect(result.contactKeyUpdated, isFalse);
        expect(result.contact, isNotNull);
        expect(result.contact!.mlKemPublicKey, 'existing-mlkem-peer-c');
        expect(await contactRepo.getContactCount(), 1);

        final updatedIntro = await introRepo.getIntroduction(
          'intro-existing-key',
        );
        expect(updatedIntro!.status, IntroductionOverallStatus.mutualAccepted);
      },
    );

    test(
      'cleans up a stale pending request row before returning recovery',
      () async {
        await introRepo.saveIntroduction(makeIntro(id: 'intro-cleans-request'));
        await seedPendingRequest();

        final result = await recoverIntroContactRequest(
          introRepo: introRepo,
          requestRepo: requestRepo,
          contactRepo: contactRepo,
          ownPeerId: ownPeerId,
          request: makeRequest(),
          messageRepo: messageRepo,
        );

        expect(result.action, IntroContactRequestRecoveryAction.recovered);
        expect(await requestRepo.getRequest(otherPeerId), isNull);
      },
    );

    test(
      'refuses silent recovery when multiple unresolved intros exist for the pair',
      () async {
        await introRepo.saveIntroduction(
          makeIntro(id: 'intro-ambiguous-1', introducerId: 'peer-a'),
        );
        await introRepo.saveIntroduction(
          makeIntro(id: 'intro-ambiguous-2', introducerId: 'peer-z'),
        );
        await seedPendingRequest();

        final result = await recoverIntroContactRequest(
          introRepo: introRepo,
          requestRepo: requestRepo,
          contactRepo: contactRepo,
          ownPeerId: ownPeerId,
          request: makeRequest(),
          messageRepo: messageRepo,
        );

        expect(
          result.action,
          IntroContactRequestRecoveryAction.continueAsContactRequest,
        );
        expect(result.introduction, isNull);
        expect(result.contact, isNull);
        expect(await requestRepo.getRequest(otherPeerId), isNull);
        expect(await contactRepo.getContact(otherPeerId), isNull);
      },
    );

    test(
      'does not recover when the local side has not accepted the intro yet',
      () async {
        await introRepo.saveIntroduction(
          makeIntro(
            id: 'intro-no-local-accept',
            recipientStatus: IntroductionStatus.pending,
          ),
        );
        await seedPendingRequest();

        final result = await recoverIntroContactRequest(
          introRepo: introRepo,
          requestRepo: requestRepo,
          contactRepo: contactRepo,
          ownPeerId: ownPeerId,
          request: makeRequest(),
          messageRepo: messageRepo,
        );

        expect(result.action, IntroContactRequestRecoveryAction.noMatch);
        expect(await requestRepo.getRequest(otherPeerId), isNotNull);
        expect(await contactRepo.getContact(otherPeerId), isNull);
      },
    );
  });
}
