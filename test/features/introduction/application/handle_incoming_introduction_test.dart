import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/introduction/application/handle_incoming_introduction_use_case.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_payload.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_introduction_repository.dart';

void main() {
  late InMemoryIntroductionRepository introRepo;
  late InMemoryContactRepository contactRepo;

  const ownPeerId = 'peer-self';
  final now = DateTime.now().toUtc().toIso8601String();

  setUp(() {
    introRepo = InMemoryIntroductionRepository();
    contactRepo = InMemoryContactRepository();
  });

  group('IntroductionOverallStatus.alreadyConnected serialization', () {
    test('alreadyConnected serializes to already_connected', () {
      expect(
        IntroductionOverallStatus.alreadyConnected.toDbString(),
        'already_connected',
      );
    });

    test('already_connected parses to alreadyConnected', () {
      final model = IntroductionModel.fromMap({
        'id': 'test-id',
        'introducer_id': 'peer-A',
        'recipient_id': 'peer-B',
        'introduced_id': 'peer-C',
        'status': 'already_connected',
        'created_at': now,
      });
      expect(model.status, IntroductionOverallStatus.alreadyConnected);
    });
  });

  group('handleIncomingIntroduction — send action', () {
    test('creates new intro record', () async {
      final payload = IntroductionPayload(
        action: 'send',
        introductionId: 'intro-1',
        introducerId: 'peer-A',
        recipientId: 'peer-B',
        introducedId: 'peer-C',
        introducerUsername: 'Alice',
        recipientUsername: 'Bob',
        introducedUsername: 'Charlie',
        timestamp: now,
      );

      final (result, model) = await handleIncomingIntroduction(
        payload: payload,
        introRepo: introRepo,
        contactRepo: contactRepo,
        ownPeerId: ownPeerId,
      );

      expect(result, HandleIntroductionResult.success);
      expect(model, isNotNull);
      expect(model!.id, 'intro-1');
      expect(model.introducerId, 'peer-A');
      expect(model.recipientId, 'peer-B');
      expect(model.introducedId, 'peer-C');
      expect(model.recipientStatus, IntroductionStatus.pending);
      expect(model.introducedStatus, IntroductionStatus.pending);

      // Verify it was persisted
      final stored = await introRepo.getIntroduction('intro-1');
      expect(stored, isNotNull);
    });

    test('detects duplicate and returns alreadyExists', () async {
      final payload = IntroductionPayload(
        action: 'send',
        introductionId: 'intro-dup',
        introducerId: 'peer-A',
        recipientId: 'peer-B',
        introducedId: 'peer-C',
        timestamp: now,
      );

      // First send succeeds
      await handleIncomingIntroduction(
        payload: payload,
        introRepo: introRepo,
        contactRepo: contactRepo,
        ownPeerId: ownPeerId,
      );

      // Second send is a duplicate
      final (result, model) = await handleIncomingIntroduction(
        payload: payload,
        introRepo: introRepo,
        contactRepo: contactRepo,
        ownPeerId: ownPeerId,
      );

      expect(result, HandleIntroductionResult.alreadyExists);
      expect(model, isNotNull);
      expect(model!.id, 'intro-dup');
    });

    test(
      'duplicate send for the same introductionId does not reopen a passed intro',
      () async {
        await introRepo.saveIntroduction(
          IntroductionModel(
            id: 'intro-passed',
            introducerId: 'peer-A',
            recipientId: 'peer-B',
            introducedId: 'peer-C',
            recipientStatus: IntroductionStatus.passed,
            introducedStatus: IntroductionStatus.pending,
            status: IntroductionOverallStatus.passed,
            createdAt: '2026-03-01T11:00:00.000Z',
          ),
        );

        final (result, model) = await handleIncomingIntroduction(
          payload: IntroductionPayload(
            action: 'send',
            introductionId: 'intro-passed',
            introducerId: 'peer-A',
            recipientId: 'peer-B',
            introducedId: 'peer-C',
            timestamp: '2026-03-01T11:00:00.000Z',
          ),
          introRepo: introRepo,
          contactRepo: contactRepo,
          ownPeerId: ownPeerId,
        );

        expect(result, HandleIntroductionResult.alreadyExists);
        expect(model, isNotNull);
        expect(model!.id, 'intro-passed');
        expect(model.status, IntroductionOverallStatus.passed);
        expect(model.recipientStatus, IntroductionStatus.passed);
        expect(model.introducedStatus, IntroductionStatus.pending);
      },
    );

    test(
      'newer send for the same pair replaces the older local row and resets state',
      () async {
        await introRepo.saveIntroduction(
          IntroductionModel(
            id: 'intro-old',
            introducerId: 'peer-A',
            recipientId: 'peer-C',
            introducedId: 'peer-B',
            recipientStatus: IntroductionStatus.accepted,
            introducedStatus: IntroductionStatus.passed,
            status: IntroductionOverallStatus.passed,
            createdAt: '2026-03-01T09:00:00.000Z',
          ),
        );

        final (result, model) = await handleIncomingIntroduction(
          payload: IntroductionPayload(
            action: 'send',
            introductionId: 'intro-new',
            introducerId: 'peer-A',
            recipientId: 'peer-B',
            introducedId: 'peer-C',
            timestamp: '2026-03-01T10:00:00.000Z',
          ),
          introRepo: introRepo,
          contactRepo: contactRepo,
          ownPeerId: ownPeerId,
        );

        expect(result, HandleIntroductionResult.success);
        expect(model, isNotNull);
        expect(model!.id, 'intro-new');
        expect(model.recipientStatus, IntroductionStatus.pending);
        expect(model.introducedStatus, IntroductionStatus.pending);
        expect(model.status, IntroductionOverallStatus.pending);
        expect(await introRepo.getIntroduction('intro-old'), isNull);
      },
    );

    test(
      'older send for the same pair is ignored when a newer row exists',
      () async {
        await introRepo.saveIntroduction(
          IntroductionModel(
            id: 'intro-current',
            introducerId: 'peer-A',
            recipientId: 'peer-B',
            introducedId: 'peer-C',
            createdAt: '2026-03-01T11:00:00.000Z',
          ),
        );

        final (result, model) = await handleIncomingIntroduction(
          payload: IntroductionPayload(
            action: 'send',
            introductionId: 'intro-stale',
            introducerId: 'peer-A',
            recipientId: 'peer-B',
            introducedId: 'peer-C',
            timestamp: '2026-03-01T10:00:00.000Z',
          ),
          introRepo: introRepo,
          contactRepo: contactRepo,
          ownPeerId: ownPeerId,
        );

        expect(result, HandleIntroductionResult.alreadyExists);
        expect(model, isNotNull);
        expect(model!.id, 'intro-current');
        expect(await introRepo.getIntroduction('intro-stale'), isNull);
      },
    );

    test(
      'older same-pair send does not replace a passed intro with a new pending row',
      () async {
        await introRepo.saveIntroduction(
          IntroductionModel(
            id: 'intro-terminal',
            introducerId: 'peer-A',
            recipientId: 'peer-B',
            introducedId: 'peer-C',
            recipientStatus: IntroductionStatus.passed,
            introducedStatus: IntroductionStatus.pending,
            status: IntroductionOverallStatus.passed,
            createdAt: '2026-03-01T11:00:00.000Z',
          ),
        );

        final (result, model) = await handleIncomingIntroduction(
          payload: IntroductionPayload(
            action: 'send',
            introductionId: 'intro-stale-terminal',
            introducerId: 'peer-A',
            recipientId: 'peer-B',
            introducedId: 'peer-C',
            timestamp: '2026-03-01T10:00:00.000Z',
          ),
          introRepo: introRepo,
          contactRepo: contactRepo,
          ownPeerId: ownPeerId,
        );

        expect(result, HandleIntroductionResult.alreadyExists);
        expect(model, isNotNull);
        expect(model!.id, 'intro-terminal');
        expect(model.status, IntroductionOverallStatus.passed);
        expect(model.recipientStatus, IntroductionStatus.passed);
        expect(model.introducedStatus, IntroductionStatus.pending);
        expect(await introRepo.getIntroduction('intro-stale-terminal'), isNull);

        final stored = await introRepo.getIntroduction('intro-terminal');
        expect(stored, isNotNull);
        expect(stored!.status, IntroductionOverallStatus.passed);
        expect(stored.recipientStatus, IntroductionStatus.passed);
        expect(stored.introducedStatus, IntroductionStatus.pending);
      },
    );

    test(
      'older same-pair send does not replace an expired intro with a new pending row',
      () async {
        await introRepo.saveIntroduction(
          IntroductionModel(
            id: 'intro-expired-current',
            introducerId: 'peer-A',
            recipientId: 'peer-B',
            introducedId: 'peer-C',
            recipientStatus: IntroductionStatus.pending,
            introducedStatus: IntroductionStatus.pending,
            status: IntroductionOverallStatus.expired,
            createdAt: '2026-03-01T11:00:00.000Z',
          ),
        );

        final (result, model) = await handleIncomingIntroduction(
          payload: IntroductionPayload(
            action: 'send',
            introductionId: 'intro-expired-stale',
            introducerId: 'peer-A',
            recipientId: 'peer-B',
            introducedId: 'peer-C',
            timestamp: '2026-03-01T10:00:00.000Z',
          ),
          introRepo: introRepo,
          contactRepo: contactRepo,
          ownPeerId: ownPeerId,
        );

        expect(result, HandleIntroductionResult.alreadyExists);
        expect(model, isNotNull);
        expect(model!.id, 'intro-expired-current');
        expect(model.status, IntroductionOverallStatus.expired);
        expect(await introRepo.getIntroduction('intro-expired-stale'), isNull);

        final stored = await introRepo.getIntroduction('intro-expired-current');
        expect(stored, isNotNull);
        expect(stored!.status, IntroductionOverallStatus.expired);
      },
    );

    test(
      'older same-pair send does not replace an alreadyConnected intro with a new pending row',
      () async {
        await introRepo.saveIntroduction(
          IntroductionModel(
            id: 'intro-already-connected-current',
            introducerId: 'peer-A',
            recipientId: 'peer-B',
            introducedId: 'peer-C',
            recipientStatus: IntroductionStatus.pending,
            introducedStatus: IntroductionStatus.pending,
            status: IntroductionOverallStatus.alreadyConnected,
            createdAt: '2026-03-01T11:00:00.000Z',
          ),
        );

        final (result, model) = await handleIncomingIntroduction(
          payload: IntroductionPayload(
            action: 'send',
            introductionId: 'intro-already-connected-stale',
            introducerId: 'peer-A',
            recipientId: 'peer-B',
            introducedId: 'peer-C',
            timestamp: '2026-03-01T10:00:00.000Z',
          ),
          introRepo: introRepo,
          contactRepo: contactRepo,
          ownPeerId: ownPeerId,
        );

        expect(result, HandleIntroductionResult.alreadyExists);
        expect(model, isNotNull);
        expect(model!.id, 'intro-already-connected-current');
        expect(model.status, IntroductionOverallStatus.alreadyConnected);
        expect(
          await introRepo.getIntroduction('intro-already-connected-stale'),
          isNull,
        );

        final stored = await introRepo.getIntroduction(
          'intro-already-connected-current',
        );
        expect(stored, isNotNull);
        expect(stored!.status, IntroductionOverallStatus.alreadyConnected);
      },
    );
  });

  group('handleIncomingIntroduction — already connected detection', () {
    test(
      'incoming intro for existing contact gets alreadyConnected status',
      () async {
        // B already has C as a contact
        contactRepo.addTestContact(
          ContactModel(
            peerId: 'peer-C',
            publicKey: 'pk-C',
            rendezvous: '/rv',
            username: 'Charlie',
            signature: 'sig-C',
            scannedAt: now,
          ),
        );

        final payload = IntroductionPayload(
          action: 'send',
          introductionId: 'intro-ac',
          introducerId: 'peer-A',
          recipientId: 'peer-self',
          introducedId: 'peer-C',
          introducerUsername: 'Alice',
          recipientUsername: 'Me',
          introducedUsername: 'Charlie',
          timestamp: now,
        );

        final (result, model) = await handleIncomingIntroduction(
          payload: payload,
          introRepo: introRepo,
          contactRepo: contactRepo,
          ownPeerId: ownPeerId,
        );

        expect(result, HandleIntroductionResult.success);
        expect(model!.status, IntroductionOverallStatus.alreadyConnected);
      },
    );

    test('incoming intro for non-contact stays pending', () async {
      // No contact for peer-C
      final payload = IntroductionPayload(
        action: 'send',
        introductionId: 'intro-nc',
        introducerId: 'peer-A',
        recipientId: 'peer-self',
        introducedId: 'peer-C',
        introducerUsername: 'Alice',
        recipientUsername: 'Me',
        introducedUsername: 'Charlie',
        timestamp: now,
      );

      final (result, model) = await handleIncomingIntroduction(
        payload: payload,
        introRepo: introRepo,
        contactRepo: contactRepo,
        ownPeerId: ownPeerId,
      );

      expect(result, HandleIntroductionResult.success);
      expect(model!.status, IntroductionOverallStatus.pending);
    });

    test(
      'alreadyConnected intro appears in getPendingIntroductionsForUser',
      () async {
        await introRepo.saveIntroduction(
          IntroductionModel(
            id: 'intro-ac-list',
            introducerId: 'peer-A',
            recipientId: 'peer-self',
            introducedId: 'peer-C',
            status: IntroductionOverallStatus.alreadyConnected,
            createdAt: now,
          ),
        );

        final results = await introRepo.getPendingIntroductionsForUser(
          'peer-self',
        );
        expect(results, hasLength(1));
        expect(
          results.first.status,
          IntroductionOverallStatus.alreadyConnected,
        );
      },
    );

    test(
      'alreadyConnected intro does NOT inflate pending badge count',
      () async {
        await introRepo.saveIntroduction(
          IntroductionModel(
            id: 'intro-ac-count',
            introducerId: 'peer-A',
            recipientId: 'peer-self',
            introducedId: 'peer-C',
            status: IntroductionOverallStatus.alreadyConnected,
            createdAt: now,
          ),
        );

        final count = await introRepo.countPendingIntroductions('peer-self');
        expect(count, 0);
      },
    );
  });

  group('handleIncomingIntroduction — accept/pass actions', () {
    /// Seeds an intro and returns a response payload.
    Future<void> seedIntro(String introId) async {
      await introRepo.saveIntroduction(
        IntroductionModel(
          id: introId,
          introducerId: 'peer-A',
          recipientId: 'peer-B',
          introducedId: 'peer-C',
          createdAt: now,
        ),
      );
    }

    test(
      'accept updates recipient status when responder is recipient',
      () async {
        await seedIntro('intro-accept-r');

        final payload = IntroductionPayload(
          action: 'accept',
          introductionId: 'intro-accept-r',
          responderId: 'peer-B', // recipient
          timestamp: now,
        );

        final (result, model) = await handleIncomingIntroduction(
          payload: payload,
          introRepo: introRepo,
          contactRepo: contactRepo,
          ownPeerId: ownPeerId,
        );

        expect(result, HandleIntroductionResult.success);
        expect(model!.recipientStatus, IntroductionStatus.accepted);
        expect(model.introducedStatus, IntroductionStatus.pending);
      },
    );

    test(
      'accept updates introduced status when responder is introduced',
      () async {
        await seedIntro('intro-accept-i');

        final payload = IntroductionPayload(
          action: 'accept',
          introductionId: 'intro-accept-i',
          responderId: 'peer-C', // introduced
          timestamp: now,
        );

        final (result, model) = await handleIncomingIntroduction(
          payload: payload,
          introRepo: introRepo,
          contactRepo: contactRepo,
          ownPeerId: ownPeerId,
        );

        expect(result, HandleIntroductionResult.success);
        expect(model!.recipientStatus, IntroductionStatus.pending);
        expect(model.introducedStatus, IntroductionStatus.accepted);
      },
    );

    test('both accept derives mutualAccepted overall status', () async {
      await seedIntro('intro-mutual');

      // Recipient accepts
      await handleIncomingIntroduction(
        payload: IntroductionPayload(
          action: 'accept',
          introductionId: 'intro-mutual',
          responderId: 'peer-B',
          timestamp: now,
        ),
        introRepo: introRepo,
        contactRepo: contactRepo,
        ownPeerId: ownPeerId,
      );

      // Introduced accepts
      final (result, model) = await handleIncomingIntroduction(
        payload: IntroductionPayload(
          action: 'accept',
          introductionId: 'intro-mutual',
          responderId: 'peer-C',
          timestamp: now,
        ),
        introRepo: introRepo,
        contactRepo: contactRepo,
        ownPeerId: ownPeerId,
      );

      expect(result, HandleIntroductionResult.success);
      expect(model!.recipientStatus, IntroductionStatus.accepted);
      expect(model.introducedStatus, IntroductionStatus.accepted);
      expect(model.status, IntroductionOverallStatus.mutualAccepted);
    });

    test('pass action derives passed overall status', () async {
      await seedIntro('intro-pass');

      final (result, model) = await handleIncomingIntroduction(
        payload: IntroductionPayload(
          action: 'pass',
          introductionId: 'intro-pass',
          responderId: 'peer-B',
          timestamp: now,
        ),
        introRepo: introRepo,
        contactRepo: contactRepo,
        ownPeerId: ownPeerId,
      );

      expect(result, HandleIntroductionResult.success);
      expect(model!.recipientStatus, IntroductionStatus.passed);
      expect(model.status, IntroductionOverallStatus.passed);
    });

    test(
      'accept before send is deferred and replayed when send arrives',
      () async {
        final deferredPayload = IntroductionPayload(
          action: 'accept',
          introductionId: 'intro-deferred-accept',
          responderId: 'peer-C',
          responderUsername: 'Charlie',
          timestamp: now,
        );

        final (
          deferredResult,
          deferredModel,
        ) = await handleIncomingIntroduction(
          payload: deferredPayload,
          introRepo: introRepo,
          contactRepo: contactRepo,
          ownPeerId: ownPeerId,
        );

        expect(deferredResult, HandleIntroductionResult.deferred);
        expect(deferredModel, isNull);
        expect(
          await introRepo.loadPendingResponses('intro-deferred-accept'),
          hasLength(1),
        );

        final (sendResult, sendModel) = await handleIncomingIntroduction(
          payload: IntroductionPayload(
            action: 'send',
            introductionId: 'intro-deferred-accept',
            introducerId: 'peer-A',
            recipientId: 'peer-B',
            introducedId: 'peer-C',
            timestamp: now,
          ),
          introRepo: introRepo,
          contactRepo: contactRepo,
          ownPeerId: ownPeerId,
        );

        expect(sendResult, HandleIntroductionResult.success);
        expect(sendModel, isNotNull);
        expect(sendModel!.introducedStatus, IntroductionStatus.accepted);
        expect(sendModel.recipientStatus, IntroductionStatus.pending);
        expect(sendModel.status, IntroductionOverallStatus.pending);
        expect(
          await introRepo.loadPendingResponses('intro-deferred-accept'),
          isEmpty,
        );
      },
    );

    test(
      'pass before send is deferred and replayed when send arrives',
      () async {
        final deferredPayload = IntroductionPayload(
          action: 'pass',
          introductionId: 'intro-deferred-pass',
          responderId: 'peer-B',
          responderUsername: 'Bob',
          timestamp: now,
        );

        final (
          deferredResult,
          deferredModel,
        ) = await handleIncomingIntroduction(
          payload: deferredPayload,
          introRepo: introRepo,
          contactRepo: contactRepo,
          ownPeerId: ownPeerId,
        );

        expect(deferredResult, HandleIntroductionResult.deferred);
        expect(deferredModel, isNull);
        expect(
          await introRepo.loadPendingResponses('intro-deferred-pass'),
          hasLength(1),
        );

        final (sendResult, sendModel) = await handleIncomingIntroduction(
          payload: IntroductionPayload(
            action: 'send',
            introductionId: 'intro-deferred-pass',
            introducerId: 'peer-A',
            recipientId: 'peer-B',
            introducedId: 'peer-C',
            timestamp: now,
          ),
          introRepo: introRepo,
          contactRepo: contactRepo,
          ownPeerId: ownPeerId,
        );

        expect(sendResult, HandleIntroductionResult.success);
        expect(sendModel, isNotNull);
        expect(sendModel!.recipientStatus, IntroductionStatus.passed);
        expect(sendModel.status, IntroductionOverallStatus.passed);
        expect(
          await introRepo.loadPendingResponses('intro-deferred-pass'),
          isEmpty,
        );
      },
    );
  });
}
