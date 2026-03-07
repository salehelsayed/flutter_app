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
      expect(IntroductionOverallStatus.alreadyConnected.toDbString(),
          'already_connected');
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
  });

  group('handleIncomingIntroduction — already connected detection', () {
    test('incoming intro for existing contact gets alreadyConnected status',
        () async {
      // B already has C as a contact
      contactRepo.addTestContact(ContactModel(
        peerId: 'peer-C',
        publicKey: 'pk-C',
        rendezvous: '/rv',
        username: 'Charlie',
        signature: 'sig-C',
        scannedAt: now,
      ));

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
    });

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

    test('alreadyConnected intro appears in getPendingIntroductionsForUser',
        () async {
      await introRepo.saveIntroduction(IntroductionModel(
        id: 'intro-ac-list',
        introducerId: 'peer-A',
        recipientId: 'peer-self',
        introducedId: 'peer-C',
        status: IntroductionOverallStatus.alreadyConnected,
        createdAt: now,
      ));

      final results =
          await introRepo.getPendingIntroductionsForUser('peer-self');
      expect(results, hasLength(1));
      expect(results.first.status,
          IntroductionOverallStatus.alreadyConnected);
    });

    test('alreadyConnected intro does NOT inflate pending badge count',
        () async {
      await introRepo.saveIntroduction(IntroductionModel(
        id: 'intro-ac-count',
        introducerId: 'peer-A',
        recipientId: 'peer-self',
        introducedId: 'peer-C',
        status: IntroductionOverallStatus.alreadyConnected,
        createdAt: now,
      ));

      final count =
          await introRepo.countPendingIntroductions('peer-self');
      expect(count, 0);
    });
  });

  group('handleIncomingIntroduction — accept/pass actions', () {
    /// Seeds an intro and returns a response payload.
    Future<void> seedIntro(String introId) async {
      await introRepo.saveIntroduction(IntroductionModel(
        id: introId,
        introducerId: 'peer-A',
        recipientId: 'peer-B',
        introducedId: 'peer-C',
        createdAt: now,
      ));
    }

    test('accept updates recipient status when responder is recipient',
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
    });

    test('accept updates introduced status when responder is introduced',
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
    });

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
  });
}
