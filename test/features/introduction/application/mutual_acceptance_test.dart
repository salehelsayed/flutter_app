import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/introduction/application/accept_introduction_use_case.dart';
import 'package:flutter_app/features/introduction/application/handle_incoming_introduction_use_case.dart';
import 'package:flutter_app/features/introduction/application/pass_introduction_use_case.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_payload.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_introduction_repository.dart';

void main() {
  late InMemoryIntroductionRepository introRepo;
  late InMemoryContactRepository contactRepo;
  late FakeP2PNetwork network;
  late FakeP2PService p2pService;
  late PassthroughCryptoBridge bridge;
  final now = DateTime.now().toUtc().toIso8601String();

  ContactModel _makeContact(String peerId, String username) {
    return ContactModel(
      peerId: peerId,
      publicKey: 'pk-$peerId',
      rendezvous: '/dns4/relay/tcp/443/p2p/relay',
      username: username,
      signature: 'sig-$peerId',
      scannedAt: now,
      mlKemPublicKey: 'test-mlkem-pk-$peerId',
    );
  }

  void seedIntro(
    String id, {
    IntroductionStatus recipientStatus = IntroductionStatus.pending,
    IntroductionStatus introducedStatus = IntroductionStatus.pending,
    IntroductionOverallStatus overallStatus = IntroductionOverallStatus.pending,
  }) {
    introRepo.saveIntroduction(
      IntroductionModel(
        id: id,
        introducerId: 'peer-A',
        recipientId: 'peer-B',
        introducedId: 'peer-C',
        introducerUsername: 'Alice',
        recipientUsername: 'Bob',
        introducedUsername: 'Charlie',
        createdAt: now,
        recipientStatus: recipientStatus,
        introducedStatus: introducedStatus,
        status: overallStatus,
      ),
    );
  }

  setUp(() {
    introRepo = InMemoryIntroductionRepository();
    contactRepo = InMemoryContactRepository();
    network = FakeP2PNetwork();
    p2pService = FakeP2PService(peerId: 'peer-B', network: network);
    bridge = PassthroughCryptoBridge();

    // Add contacts for introducer and other party
    contactRepo.addTestContact(_makeContact('peer-A', 'Alice'));
    contactRepo.addTestContact(_makeContact('peer-C', 'Charlie'));
  });

  group('mutual acceptance', () {
    test('mutual_accepted triggers after both accept', () async {
      seedIntro('i1');

      // B accepts (as recipient)
      await acceptIntroduction(
        introRepo: introRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        bridge: bridge,
        introductionId: 'i1',
        ownPeerId: 'peer-B',
        ownUsername: 'Bob',
      );

      // Simulate C accepting via handleIncoming
      final (result, model) = await handleIncomingIntroduction(
        payload: IntroductionPayload(
          action: 'accept',
          introductionId: 'i1',
          responderId: 'peer-C',
          responderUsername: 'Charlie',
          timestamp: now,
        ),
        introRepo: introRepo,
        contactRepo: contactRepo,
        ownPeerId: 'peer-B',
      );

      expect(result, HandleIntroductionResult.success);
      expect(model!.status, IntroductionOverallStatus.mutualAccepted);
    });

    test('single-side accept does NOT trigger mutualAccepted', () async {
      seedIntro('i1');

      final model = await acceptIntroduction(
        introRepo: introRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        bridge: bridge,
        introductionId: 'i1',
        ownPeerId: 'peer-B',
        ownUsername: 'Bob',
      );

      expect(model!.status, IntroductionOverallStatus.pending);
      expect(model.recipientStatus, IntroductionStatus.accepted);
      expect(model.introducedStatus, IntroductionStatus.pending);
    });

    test('pass after other accepted results in passed overall', () async {
      seedIntro('i1');

      // B accepts
      await acceptIntroduction(
        introRepo: introRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        bridge: bridge,
        introductionId: 'i1',
        ownPeerId: 'peer-B',
        ownUsername: 'Bob',
      );

      // C passes via handleIncoming
      final (result, model) = await handleIncomingIntroduction(
        payload: IntroductionPayload(
          action: 'pass',
          introductionId: 'i1',
          responderId: 'peer-C',
          responderUsername: 'Charlie',
          timestamp: now,
        ),
        introRepo: introRepo,
        contactRepo: contactRepo,
        ownPeerId: 'peer-B',
      );

      expect(result, HandleIntroductionResult.success);
      expect(model!.status, IntroductionOverallStatus.passed);
    });

    test('order independence: C accepts first then B', () async {
      seedIntro('i1');

      // C accepts first (via handleIncoming)
      await handleIncomingIntroduction(
        payload: IntroductionPayload(
          action: 'accept',
          introductionId: 'i1',
          responderId: 'peer-C',
          responderUsername: 'Charlie',
          timestamp: now,
        ),
        introRepo: introRepo,
        contactRepo: contactRepo,
        ownPeerId: 'peer-B',
      );

      // B accepts second
      final model = await acceptIntroduction(
        introRepo: introRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        bridge: bridge,
        introductionId: 'i1',
        ownPeerId: 'peer-B',
        ownUsername: 'Bob',
      );

      expect(model!.status, IntroductionOverallStatus.mutualAccepted);
    });

    test(
      'concurrent acceptance: only one status update (idempotency)',
      () async {
        seedIntro('i1');

        // Both accept nearly simultaneously
        final resultB = await acceptIntroduction(
          introRepo: introRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
          introductionId: 'i1',
          ownPeerId: 'peer-B',
          ownUsername: 'Bob',
        );

        // Simulate C's accept arriving
        final (_, modelC) = await handleIncomingIntroduction(
          payload: IntroductionPayload(
            action: 'accept',
            introductionId: 'i1',
            responderId: 'peer-C',
            responderUsername: 'Charlie',
            timestamp: now,
          ),
          introRepo: introRepo,
          contactRepo: contactRepo,
          ownPeerId: 'peer-B',
        );

        // Final state is mutualAccepted
        expect(modelC!.status, IntroductionOverallStatus.mutualAccepted);
        expect(modelC.recipientStatus, IntroductionStatus.accepted);
        expect(modelC.introducedStatus, IntroductionStatus.accepted);

        // B's intermediate state was pending (only one side)
        expect(resultB!.recipientStatus, IntroductionStatus.accepted);
      },
    );

    test('accept sends notification to introducer', () async {
      seedIntro('i1');
      network.resetCounters();

      await acceptIntroduction(
        introRepo: introRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        bridge: bridge,
        introductionId: 'i1',
        ownPeerId: 'peer-B',
        ownUsername: 'Bob',
      );

      // With no online recipients, both notifications should fall back to inbox.
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 2);
    });

    test('accept sends notification to other party', () async {
      seedIntro('i1');

      // Create a second p2p service for peer-C to verify delivery
      final p2pC = FakeP2PService(peerId: 'peer-C', network: network);
      final contactRepoC = InMemoryContactRepository();
      contactRepoC.addTestContact(_makeContact('peer-A', 'Alice'));
      contactRepoC.addTestContact(_makeContact('peer-B', 'Bob'));

      network.resetCounters();

      await acceptIntroduction(
        introRepo: introRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        bridge: bridge,
        introductionId: 'i1',
        ownPeerId: 'peer-B',
        ownUsername: 'Bob',
      );

      // Introducer is offline so their notification lands in inbox, while the
      // other party is online and receives the live update.
      expect(network.deliverCallCount, 1);
      expect(network.storeInInboxCallCount, 1);

      p2pC.dispose();
    });

    test('deriveStatus with both accepted returns mutualAccepted', () {
      final status = IntroductionModel.deriveStatus(
        recipientStatus: IntroductionStatus.accepted,
        introducedStatus: IntroductionStatus.accepted,
        createdAt: now,
      );

      expect(status, IntroductionOverallStatus.mutualAccepted);
    });

    test('deriveStatus with one accepted one pending returns pending', () {
      final status = IntroductionModel.deriveStatus(
        recipientStatus: IntroductionStatus.accepted,
        introducedStatus: IntroductionStatus.pending,
        createdAt: now,
      );

      expect(status, IntroductionOverallStatus.pending);
    });

    test('deriveStatus with one passed returns passed regardless of other', () {
      final status1 = IntroductionModel.deriveStatus(
        recipientStatus: IntroductionStatus.accepted,
        introducedStatus: IntroductionStatus.passed,
        createdAt: now,
      );
      final status2 = IntroductionModel.deriveStatus(
        recipientStatus: IntroductionStatus.passed,
        introducedStatus: IntroductionStatus.pending,
        createdAt: now,
      );

      expect(status1, IntroductionOverallStatus.passed);
      expect(status2, IntroductionOverallStatus.passed);
    });

    test(
      'multiple intros: only matching pair reaches mutualAccepted',
      () async {
        // B↔C intro
        seedIntro('i1');
        // B↔D intro
        await introRepo.saveIntroduction(
          IntroductionModel(
            id: 'i2',
            introducerId: 'peer-A',
            recipientId: 'peer-B',
            introducedId: 'peer-D',
            introducerUsername: 'Alice',
            recipientUsername: 'Bob',
            introducedUsername: 'Dana',
            createdAt: now,
          ),
        );
        contactRepo.addTestContact(_makeContact('peer-D', 'Dana'));

        // B accepts both
        await acceptIntroduction(
          introRepo: introRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
          introductionId: 'i1',
          ownPeerId: 'peer-B',
          ownUsername: 'Bob',
        );
        await acceptIntroduction(
          introRepo: introRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
          introductionId: 'i2',
          ownPeerId: 'peer-B',
          ownUsername: 'Bob',
        );

        // Only C accepts back (via handleIncoming)
        await handleIncomingIntroduction(
          payload: IntroductionPayload(
            action: 'accept',
            introductionId: 'i1',
            responderId: 'peer-C',
            responderUsername: 'Charlie',
            timestamp: now,
          ),
          introRepo: introRepo,
          contactRepo: contactRepo,
          ownPeerId: 'peer-B',
        );

        // i1 should be mutualAccepted, i2 should still be pending
        final intro1 = await introRepo.getIntroduction('i1');
        final intro2 = await introRepo.getIntroduction('i2');
        expect(intro1!.status, IntroductionOverallStatus.mutualAccepted);
        expect(intro2!.status, IntroductionOverallStatus.pending);
      },
    );

    test('handleIncoming defers response for non-existent intro', () async {
      final (result, model) = await handleIncomingIntroduction(
        payload: IntroductionPayload(
          action: 'accept',
          introductionId: 'non-existent',
          responderId: 'peer-C',
          timestamp: now,
        ),
        introRepo: introRepo,
        contactRepo: contactRepo,
        ownPeerId: 'peer-B',
      );

      expect(result, HandleIntroductionResult.deferred);
      expect(model, isNull);
      expect(
        await introRepo.loadPendingResponses('non-existent'),
        hasLength(1),
      );
    });

    test('pass use case sets overall status to passed', () async {
      seedIntro('i1');

      final model = await passIntroduction(
        introRepo: introRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        bridge: bridge,
        introductionId: 'i1',
        ownPeerId: 'peer-B',
        ownUsername: 'Bob',
      );

      expect(model!.status, IntroductionOverallStatus.passed);
      expect(model.recipientStatus, IntroductionStatus.passed);
    });

    test('pass sends notifications to both parties', () async {
      seedIntro('i1');
      network.resetCounters();

      await passIntroduction(
        introRepo: introRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        bridge: bridge,
        introductionId: 'i1',
        ownPeerId: 'peer-B',
        ownUsername: 'Bob',
      );

      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 2);
    });

    test('accept after pass still results in passed', () async {
      seedIntro('i1');

      // B passes
      await passIntroduction(
        introRepo: introRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        bridge: bridge,
        introductionId: 'i1',
        ownPeerId: 'peer-B',
        ownUsername: 'Bob',
      );

      // C accepts via handleIncoming
      final (_, model) = await handleIncomingIntroduction(
        payload: IntroductionPayload(
          action: 'accept',
          introductionId: 'i1',
          responderId: 'peer-C',
          responderUsername: 'Charlie',
          timestamp: now,
        ),
        introRepo: introRepo,
        contactRepo: contactRepo,
        ownPeerId: 'peer-B',
      );

      // Still passed because B already passed
      expect(model!.status, IntroductionOverallStatus.passed);
    });

    test('expired intro derives expired status', () {
      final thirtyOneDaysAgo = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 31))
          .toIso8601String();

      final status = IntroductionModel.deriveStatus(
        recipientStatus: IntroductionStatus.pending,
        introducedStatus: IntroductionStatus.pending,
        createdAt: thirtyOneDaysAgo,
      );

      expect(status, IntroductionOverallStatus.expired);
    });

    test('accept returns null for non-existent introduction', () async {
      final result = await acceptIntroduction(
        introRepo: introRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        bridge: bridge,
        introductionId: 'fake-id',
        ownPeerId: 'peer-B',
        ownUsername: 'Bob',
      );

      expect(result, isNull);
    });
  });
}
