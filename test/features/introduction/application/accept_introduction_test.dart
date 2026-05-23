import 'dart:convert';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/introduction/application/accept_introduction_use_case.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_outbox_delivery.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_introduction_repository.dart';

void main() {
  late FakeP2PNetwork network;
  late FakeP2PService p2pServiceB;
  late FakeP2PService p2pServiceC;
  late PassthroughCryptoBridge bridge;
  late InMemoryContactRepository contactRepo;
  late InMemoryIntroductionRepository introRepo;

  final now = DateTime.now().toUtc().toIso8601String();

  setUp(() {
    network = FakeP2PNetwork();
    // Register all peers so messages can be delivered
    FakeP2PService(peerId: 'peer-A', network: network); // introducer
    p2pServiceB = FakeP2PService(peerId: 'peer-B', network: network);
    p2pServiceC = FakeP2PService(peerId: 'peer-C', network: network);
    bridge = PassthroughCryptoBridge();
    contactRepo = InMemoryContactRepository();
    introRepo = InMemoryIntroductionRepository();

    // Add contacts so accept can look up ML-KEM keys for encryption
    contactRepo.addTestContact(
      ContactModel(
        peerId: 'peer-A',
        publicKey: 'pk-peer-A',
        rendezvous: '/dns4/relay/tcp/443/p2p/relay',
        username: 'Alice',
        signature: 'sig-peer-A',
        scannedAt: now,
        mlKemPublicKey: 'test-mlkem-pk-peer-A',
      ),
    );
    contactRepo.addTestContact(
      ContactModel(
        peerId: 'peer-B',
        publicKey: 'pk-peer-B',
        rendezvous: '/dns4/relay/tcp/443/p2p/relay',
        username: 'Bob',
        signature: 'sig-peer-B',
        scannedAt: now,
        mlKemPublicKey: 'test-mlkem-pk-peer-B',
      ),
    );
    contactRepo.addTestContact(
      ContactModel(
        peerId: 'peer-C',
        publicKey: 'pk-peer-C',
        rendezvous: '/dns4/relay/tcp/443/p2p/relay',
        username: 'Charlie',
        signature: 'sig-peer-C',
        scannedAt: now,
        mlKemPublicKey: 'test-mlkem-pk-peer-C',
      ),
    );

    // Pre-seed a pending introduction
    introRepo.saveIntroduction(
      IntroductionModel(
        id: 'intro-1',
        introducerId: 'peer-A',
        recipientId: 'peer-B',
        introducedId: 'peer-C',
        introducerUsername: 'Alice',
        recipientUsername: 'Bob',
        introducedUsername: 'Charlie',
        createdAt: now,
      ),
    );
  });

  test(
    'accept sets recipientStatus to accepted when user is recipient',
    () async {
      final result = await acceptIntroduction(
        introRepo: introRepo,
        contactRepo: contactRepo,
        p2pService: p2pServiceB,
        bridge: bridge,
        introductionId: 'intro-1',
        ownPeerId: 'peer-B',
        ownUsername: 'Bob',
      );

      expect(result, isNotNull);
      expect(result!.recipientStatus, IntroductionStatus.accepted);
      // Introduced status should still be pending
      expect(result.introducedStatus, IntroductionStatus.pending);
    },
  );

  test(
    'accept sets introducedStatus to accepted when user is introduced',
    () async {
      final result = await acceptIntroduction(
        introRepo: introRepo,
        contactRepo: contactRepo,
        p2pService: p2pServiceC,
        bridge: bridge,
        introductionId: 'intro-1',
        ownPeerId: 'peer-C',
        ownUsername: 'Charlie',
      );

      expect(result, isNotNull);
      expect(result!.introducedStatus, IntroductionStatus.accepted);
      // Recipient status should still be pending
      expect(result.recipientStatus, IntroductionStatus.pending);
    },
  );

  test(
    'single-side accept does NOT change overall to mutualAccepted',
    () async {
      final result = await acceptIntroduction(
        introRepo: introRepo,
        contactRepo: contactRepo,
        p2pService: p2pServiceB,
        bridge: bridge,
        introductionId: 'intro-1',
        ownPeerId: 'peer-B',
        ownUsername: 'Bob',
      );

      expect(result, isNotNull);
      expect(result!.status, isNot(IntroductionOverallStatus.mutualAccepted));
      expect(result.status, IntroductionOverallStatus.pending);
    },
  );

  test('both sides accepting sets status to mutualAccepted', () async {
    // B accepts first
    await acceptIntroduction(
      introRepo: introRepo,
      contactRepo: contactRepo,
      p2pService: p2pServiceB,
      bridge: bridge,
      introductionId: 'intro-1',
      ownPeerId: 'peer-B',
      ownUsername: 'Bob',
    );

    // C accepts second
    final result = await acceptIntroduction(
      introRepo: introRepo,
      contactRepo: contactRepo,
      p2pService: p2pServiceC,
      bridge: bridge,
      introductionId: 'intro-1',
      ownPeerId: 'peer-C',
      ownUsername: 'Charlie',
    );

    expect(result, isNotNull);
    expect(result!.recipientStatus, IntroductionStatus.accepted);
    expect(result.introducedStatus, IntroductionStatus.accepted);
    expect(result.status, IntroductionOverallStatus.mutualAccepted);
  });

  test(
    'accepting a passed intro does not revive terminal state or send fan-out',
    () async {
      introRepo.clear();
      await introRepo.saveIntroduction(
        IntroductionModel(
          id: 'intro-terminal-passed',
          introducerId: 'peer-A',
          recipientId: 'peer-B',
          introducedId: 'peer-C',
          recipientStatus: IntroductionStatus.passed,
          introducedStatus: IntroductionStatus.accepted,
          status: IntroductionOverallStatus.passed,
          createdAt: now,
        ),
      );
      network.resetCounters();

      final result = await acceptIntroduction(
        introRepo: introRepo,
        contactRepo: contactRepo,
        p2pService: p2pServiceB,
        bridge: bridge,
        introductionId: 'intro-terminal-passed',
        ownPeerId: 'peer-B',
        ownUsername: 'Bob',
      );

      expect(result, isNotNull);
      expect(result!.recipientStatus, IntroductionStatus.passed);
      expect(result.introducedStatus, IntroductionStatus.accepted);
      expect(result.status, IntroductionOverallStatus.passed);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
    },
  );

  test('accept returns null for non-existent introduction', () async {
    final result = await acceptIntroduction(
      introRepo: introRepo,
      contactRepo: contactRepo,
      p2pService: p2pServiceB,
      bridge: bridge,
      introductionId: 'non-existent-id',
      ownPeerId: 'peer-B',
      ownUsername: 'Bob',
    );

    expect(result, isNull);
  });

  test(
    'non-party caller cannot accept and does not mutate intro state',
    () async {
      network.resetCounters();

      final result = await acceptIntroduction(
        introRepo: introRepo,
        contactRepo: contactRepo,
        p2pService: p2pServiceB,
        bridge: bridge,
        introductionId: 'intro-1',
        ownPeerId: 'peer-X',
        ownUsername: 'Mallory',
      );

      final intro = await introRepo.getIntroduction('intro-1');
      expect(result, isNull);
      expect(intro, isNotNull);
      expect(intro!.recipientStatus, IntroductionStatus.pending);
      expect(intro.introducedStatus, IntroductionStatus.pending);
      expect(intro.status, IntroductionOverallStatus.pending);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
    },
  );

  test('accept sends notification to introducer', () async {
    network.resetCounters();

    await acceptIntroduction(
      introRepo: introRepo,
      contactRepo: contactRepo,
      p2pService: p2pServiceB,
      bridge: bridge,
      introductionId: 'intro-1',
      ownPeerId: 'peer-B',
      ownUsername: 'Bob',
    );

    // Should send to introducer (peer-A) and other party (peer-C) = 2 deliveries
    expect(network.deliverCallCount, greaterThanOrEqualTo(1));
  });

  test('accept sends notification to other party', () async {
    network.resetCounters();

    await acceptIntroduction(
      introRepo: introRepo,
      contactRepo: contactRepo,
      p2pService: p2pServiceB,
      bridge: bridge,
      introductionId: 'intro-1',
      ownPeerId: 'peer-B',
      ownUsername: 'Bob',
    );

    // Should send to both introducer (peer-A) and other party (peer-C)
    expect(network.deliverCallCount, 2);
  });

  test(
    'persists local accept and both fan-out rows before a delivery-stage crash',
    () async {
      final crashingRepo = _CrashAfterNthOutboxSaveIntroductionRepository(
        crashOnSaveNumber: 1,
      );
      introRepo = crashingRepo;
      await introRepo.saveIntroduction(
        IntroductionModel(
          id: 'intro-1',
          introducerId: 'peer-A',
          recipientId: 'peer-B',
          introducedId: 'peer-C',
          introducerUsername: 'Alice',
          recipientUsername: 'Bob',
          introducedUsername: 'Charlie',
          createdAt: now,
        ),
      );

      await expectLater(
        acceptIntroduction(
          introRepo: introRepo,
          contactRepo: contactRepo,
          p2pService: p2pServiceB,
          bridge: bridge,
          introductionId: 'intro-1',
          ownPeerId: 'peer-B',
          ownUsername: 'Bob',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'simulated crash after accept fan-out staging',
          ),
        ),
      );

      final intro = await crashingRepo.getIntroduction('intro-1');
      expect(intro, isNotNull);
      expect(intro!.recipientStatus, IntroductionStatus.accepted);
      expect(intro.introducedStatus, IntroductionStatus.pending);
      expect(intro.status, IntroductionOverallStatus.pending);

      final deliveries = await crashingRepo.loadOutboxDeliveriesForIntroduction(
        'intro-1',
      );
      expect(
        deliveries.map((delivery) => delivery.action),
        everyElement('accept'),
      );
      expect(deliveries.map((delivery) => delivery.targetPeerId).toSet(), {
        'peer-A',
        'peer-C',
      });
      expect(
        deliveries.map((delivery) => delivery.deliveryStatus),
        everyElement(IntroductionOutboxDeliveryStatus.sending),
      );
      expect(network.deliverCallCount, 1);
    },
  );

  group('v2 encryption to stranger', () {
    test('v2 encryption used for stranger when intro has ML-KEM key', () async {
      // Remove peer-C from contacts so it's a "stranger"
      await contactRepo.deleteContact('peer-C');

      // Seed intro with ML-KEM keys
      introRepo.clear();
      await introRepo.saveIntroduction(
        IntroductionModel(
          id: 'intro-1',
          introducerId: 'peer-A',
          recipientId: 'peer-B',
          introducedId: 'peer-C',
          introducerUsername: 'Alice',
          recipientUsername: 'Bob',
          introducedUsername: 'Charlie',
          introducedMlKemPublicKey: 'mlkem-pk-charlie',
          recipientMlKemPublicKey: 'mlkem-pk-bob',
          createdAt: now,
        ),
      );

      bridge.commandLog.clear();

      // B (recipient) accepts → sends to A (contact) and C (stranger)
      await acceptIntroduction(
        introRepo: introRepo,
        contactRepo: contactRepo,
        p2pService: p2pServiceB,
        bridge: bridge,
        introductionId: 'intro-1',
        ownPeerId: 'peer-B',
        ownUsername: 'Bob',
      );

      // Should have called message.encrypt for both sends
      final encryptCalls = bridge.commandLog
          .where((c) => c == 'message.encrypt')
          .length;
      expect(
        encryptCalls,
        2,
        reason: 'encrypt called for introducer + stranger',
      );

      expect(network.deliverCallCount, 2);
    });

    test('v2 encryption used for stranger from introduced side', () async {
      // Remove peer-B from contacts so it's a "stranger" for C
      final contactRepoC = InMemoryContactRepository();
      final introRepoC = InMemoryIntroductionRepository();

      // C only knows A (the introducer)
      contactRepoC.addTestContact(
        ContactModel(
          peerId: 'peer-A',
          publicKey: 'pk-peer-A',
          rendezvous: '/dns4/relay/tcp/443/p2p/relay',
          username: 'Alice',
          signature: 'sig-peer-A',
          scannedAt: now,
          mlKemPublicKey: 'test-mlkem-pk-peer-A',
        ),
      );

      // Seed intro with ML-KEM keys
      await introRepoC.saveIntroduction(
        IntroductionModel(
          id: 'intro-1',
          introducerId: 'peer-A',
          recipientId: 'peer-B',
          introducedId: 'peer-C',
          introducerUsername: 'Alice',
          recipientUsername: 'Bob',
          introducedUsername: 'Charlie',
          introducedMlKemPublicKey: 'mlkem-pk-charlie',
          recipientMlKemPublicKey: 'mlkem-pk-bob',
          createdAt: now,
        ),
      );

      final bridgeC = PassthroughCryptoBridge();

      // C (introduced) accepts → sends to A (contact) and B (stranger)
      await acceptIntroduction(
        introRepo: introRepoC,
        contactRepo: contactRepoC,
        p2pService: p2pServiceC,
        bridge: bridgeC,
        introductionId: 'intro-1',
        ownPeerId: 'peer-C',
        ownUsername: 'Charlie',
      );

      // Should encrypt for both: A (from contact lookup) and B (from intro record)
      final encryptCalls = bridgeC.commandLog
          .where((c) => c == 'message.encrypt')
          .length;
      expect(encryptCalls, 2);
    });

    test(
      'v1 fallback when intro record has null ML-KEM key for stranger',
      () async {
        // Remove peer-C from contacts
        await contactRepo.deleteContact('peer-C');

        // Seed intro WITHOUT ML-KEM keys
        introRepo.clear();
        await introRepo.saveIntroduction(
          IntroductionModel(
            id: 'intro-1',
            introducerId: 'peer-A',
            recipientId: 'peer-B',
            introducedId: 'peer-C',
            introducerUsername: 'Alice',
            recipientUsername: 'Bob',
            introducedUsername: 'Charlie',
            // No ML-KEM keys
            createdAt: now,
          ),
        );

        bridge.commandLog.clear();

        await acceptIntroduction(
          introRepo: introRepo,
          contactRepo: contactRepo,
          p2pService: p2pServiceB,
          bridge: bridge,
          introductionId: 'intro-1',
          ownPeerId: 'peer-B',
          ownUsername: 'Bob',
        );

        // Only 1 encrypt call (for the introducer who IS a contact with ML-KEM key)
        // The stranger send should be v1 (no encrypt call)
        final encryptCalls = bridge.commandLog
            .where((c) => c == 'message.encrypt')
            .length;
        expect(
          encryptCalls,
          1,
          reason: 'only introducer encrypted, stranger gets v1',
        );
      },
    );

    test('v1 fallback when encryption fails for stranger', () async {
      // Remove peer-C from contacts
      await contactRepo.deleteContact('peer-C');

      // Seed intro with ML-KEM keys
      introRepo.clear();
      await introRepo.saveIntroduction(
        IntroductionModel(
          id: 'intro-1',
          introducerId: 'peer-A',
          recipientId: 'peer-B',
          introducedId: 'peer-C',
          introducerUsername: 'Alice',
          recipientUsername: 'Bob',
          introducedUsername: 'Charlie',
          introducedMlKemPublicKey: 'mlkem-pk-charlie',
          recipientMlKemPublicKey: 'mlkem-pk-bob',
          createdAt: now,
        ),
      );

      // Use a bridge that fails encryption
      final failBridge = FakeBridge(
        initialResponses: {
          'message.encrypt': {'ok': false},
        },
      );

      await acceptIntroduction(
        introRepo: introRepo,
        contactRepo: contactRepo,
        p2pService: p2pServiceB,
        bridge: failBridge,
        introductionId: 'intro-1',
        ownPeerId: 'peer-B',
        ownUsername: 'Bob',
      );

      // Both sends should still succeed (v1 fallback)
      expect(network.deliverCallCount, greaterThanOrEqualTo(2));
    });

    test(
      'contact ML-KEM key is used for stranger when intro record omits it',
      () async {
        introRepo.clear();
        await introRepo.saveIntroduction(
          IntroductionModel(
            id: 'intro-1',
            introducerId: 'peer-A',
            recipientId: 'peer-B',
            introducedId: 'peer-C',
            introducerUsername: 'Alice',
            recipientUsername: 'Bob',
            introducedUsername: 'Charlie',
            recipientMlKemPublicKey: 'mlkem-pk-bob',
            createdAt: now,
          ),
        );

        bridge.sentMessages.clear();
        bridge.commandLog.clear();

        await acceptIntroduction(
          introRepo: introRepo,
          contactRepo: contactRepo,
          p2pService: p2pServiceB,
          bridge: bridge,
          introductionId: 'intro-1',
          ownPeerId: 'peer-B',
          ownUsername: 'Bob',
        );

        final encryptRecipientKeys = bridge.sentMessages
            .map((message) => jsonDecode(message) as Map<String, dynamic>)
            .where((request) => request['cmd'] == 'message.encrypt')
            .map(
              (request) =>
                  (request['payload']
                          as Map<String, dynamic>)['recipientPublicKey']
                      as String,
            )
            .toList();

        expect(encryptRecipientKeys, hasLength(2));
        expect(encryptRecipientKeys, contains('test-mlkem-pk-peer-A'));
        expect(encryptRecipientKeys, contains('test-mlkem-pk-peer-C'));
      },
    );

    test(
      'rejects intro/contact stranger ML-KEM mismatches before mutation',
      () async {
        introRepo.clear();
        await introRepo.saveIntroduction(
          IntroductionModel(
            id: 'intro-1',
            introducerId: 'peer-A',
            recipientId: 'peer-B',
            introducedId: 'peer-C',
            introducerUsername: 'Alice',
            recipientUsername: 'Bob',
            introducedUsername: 'Charlie',
            introducedMlKemPublicKey: 'mlkem-pk-charlie-stale',
            recipientMlKemPublicKey: 'mlkem-pk-bob',
            createdAt: now,
          ),
        );

        bridge.commandLog.clear();

        final result = await acceptIntroduction(
          introRepo: introRepo,
          contactRepo: contactRepo,
          p2pService: p2pServiceB,
          bridge: bridge,
          introductionId: 'intro-1',
          ownPeerId: 'peer-B',
          ownUsername: 'Bob',
        );

        expect(result, isNull);

        final intro = await introRepo.getIntroduction('intro-1');
        expect(intro, isNotNull);
        expect(intro!.recipientStatus, IntroductionStatus.pending);
        expect(intro.introducedStatus, IntroductionStatus.pending);
        expect(intro.status, IntroductionOverallStatus.pending);
        expect(network.deliverCallCount, 0);
        expect(bridge.commandLog, isEmpty);
      },
    );
  });
}

class _CrashAfterNthOutboxSaveIntroductionRepository
    extends InMemoryIntroductionRepository {
  _CrashAfterNthOutboxSaveIntroductionRepository({
    required this.crashOnSaveNumber,
  });

  final int crashOnSaveNumber;
  int _saveOutboxDeliveryCalls = 0;

  @override
  Future<void> saveOutboxDelivery(IntroductionOutboxDelivery delivery) async {
    _saveOutboxDeliveryCalls++;
    if (_saveOutboxDeliveryCalls == crashOnSaveNumber) {
      throw StateError('simulated crash after accept fan-out staging');
    }
    await super.saveOutboxDelivery(delivery);
  }
}
