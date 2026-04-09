import 'dart:convert';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/introduction/application/pass_introduction_use_case.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_introduction_repository.dart';

void main() {
  late FakeP2PNetwork network;
  late FakeP2PService p2pServiceB;
  late PassthroughCryptoBridge bridge;
  late InMemoryContactRepository contactRepo;
  late InMemoryIntroductionRepository introRepo;

  final now = DateTime.now().toUtc().toIso8601String();

  setUp(() {
    network = FakeP2PNetwork();
    // Register all peers so messages can be delivered
    FakeP2PService(peerId: 'peer-A', network: network); // introducer
    p2pServiceB = FakeP2PService(peerId: 'peer-B', network: network);
    FakeP2PService(peerId: 'peer-C', network: network); // introduced
    bridge = PassthroughCryptoBridge();
    contactRepo = InMemoryContactRepository();
    introRepo = InMemoryIntroductionRepository();

    // Add contacts so pass can look up ML-KEM keys for encryption
    contactRepo.addTestContact(ContactModel(
      peerId: 'peer-A',
      publicKey: 'pk-peer-A',
      rendezvous: '/dns4/relay/tcp/443/p2p/relay',
      username: 'Alice',
      signature: 'sig-peer-A',
      scannedAt: now,
      mlKemPublicKey: 'test-mlkem-pk-peer-A',
    ));
    contactRepo.addTestContact(ContactModel(
      peerId: 'peer-B',
      publicKey: 'pk-peer-B',
      rendezvous: '/dns4/relay/tcp/443/p2p/relay',
      username: 'Bob',
      signature: 'sig-peer-B',
      scannedAt: now,
      mlKemPublicKey: 'test-mlkem-pk-peer-B',
    ));
    contactRepo.addTestContact(ContactModel(
      peerId: 'peer-C',
      publicKey: 'pk-peer-C',
      rendezvous: '/dns4/relay/tcp/443/p2p/relay',
      username: 'Charlie',
      signature: 'sig-peer-C',
      scannedAt: now,
      mlKemPublicKey: 'test-mlkem-pk-peer-C',
    ));

    // Pre-seed a pending introduction
    introRepo.saveIntroduction(IntroductionModel(
      id: 'intro-1',
      introducerId: 'peer-A',
      recipientId: 'peer-B',
      introducedId: 'peer-C',
      introducerUsername: 'Alice',
      recipientUsername: 'Bob',
      introducedUsername: 'Charlie',
      createdAt: now,
    ));
  });

  test("pass sets the passing user's status to passed", () async {
    final result = await passIntroduction(
      introRepo: introRepo,
      contactRepo: contactRepo,
      p2pService: p2pServiceB,
      bridge: bridge,
      introductionId: 'intro-1',
      ownPeerId: 'peer-B',
      ownUsername: 'Bob',
    );

    expect(result, isNotNull);
    expect(result!.recipientStatus, IntroductionStatus.passed);
    // The other party's status should remain pending
    expect(result.introducedStatus, IntroductionStatus.pending);
  });

  test('pass changes overall status to passed', () async {
    final result = await passIntroduction(
      introRepo: introRepo,
      contactRepo: contactRepo,
      p2pService: p2pServiceB,
      bridge: bridge,
      introductionId: 'intro-1',
      ownPeerId: 'peer-B',
      ownUsername: 'Bob',
    );

    expect(result, isNotNull);
    expect(result!.status, IntroductionOverallStatus.passed);
  });

  test('pass does NOT create a connection', () async {
    final contactCountBefore = await contactRepo.getContactCount();

    await passIntroduction(
      introRepo: introRepo,
      contactRepo: contactRepo,
      p2pService: p2pServiceB,
      bridge: bridge,
      introductionId: 'intro-1',
      ownPeerId: 'peer-B',
      ownUsername: 'Bob',
    );

    final contactCountAfter = await contactRepo.getContactCount();
    expect(contactCountAfter, contactCountBefore);
  });

  test('non-party caller cannot pass and does not mutate intro state',
      () async {
    network.resetCounters();

    final result = await passIntroduction(
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
  });

  test('pass sends notification to introducer and other party', () async {
    network.resetCounters();

    await passIntroduction(
      introRepo: introRepo,
      contactRepo: contactRepo,
      p2pService: p2pServiceB,
      bridge: bridge,
      introductionId: 'intro-1',
      ownPeerId: 'peer-B',
      ownUsername: 'Bob',
    );

    // Should send to introducer (peer-A) and other party (peer-C)
    expect(network.deliverCallCount, 2);
  });

  group('v2 encryption to stranger', () {
    test('v2 encryption used for stranger on pass', () async {
      // Remove peer-C from contacts so it's a "stranger"
      await contactRepo.deleteContact('peer-C');

      // Seed intro with ML-KEM keys
      introRepo.clear();
      await introRepo.saveIntroduction(IntroductionModel(
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
      ));

      bridge.commandLog.clear();

      await passIntroduction(
        introRepo: introRepo,
        contactRepo: contactRepo,
        p2pService: p2pServiceB,
        bridge: bridge,
        introductionId: 'intro-1',
        ownPeerId: 'peer-B',
        ownUsername: 'Bob',
      );

      // Should have called message.encrypt for both sends
      final encryptCalls =
          bridge.commandLog.where((c) => c == 'message.encrypt').length;
      expect(encryptCalls, 2, reason: 'encrypt called for introducer + stranger');
    });

    test('v1 fallback on pass when no ML-KEM key', () async {
      // Remove peer-C from contacts
      await contactRepo.deleteContact('peer-C');

      // Seed intro WITHOUT ML-KEM keys for the stranger
      introRepo.clear();
      await introRepo.saveIntroduction(IntroductionModel(
        id: 'intro-1',
        introducerId: 'peer-A',
        recipientId: 'peer-B',
        introducedId: 'peer-C',
        introducerUsername: 'Alice',
        recipientUsername: 'Bob',
        introducedUsername: 'Charlie',
        // No ML-KEM keys
        createdAt: now,
      ));

      bridge.commandLog.clear();

      await passIntroduction(
        introRepo: introRepo,
        contactRepo: contactRepo,
        p2pService: p2pServiceB,
        bridge: bridge,
        introductionId: 'intro-1',
        ownPeerId: 'peer-B',
        ownUsername: 'Bob',
      );

      // Only 1 encrypt call (for the introducer who IS a contact)
      final encryptCalls =
          bridge.commandLog.where((c) => c == 'message.encrypt').length;
      expect(encryptCalls, 1,
          reason: 'only introducer encrypted, stranger gets v1');
    });

    test(
        'contact ML-KEM key is used for stranger on pass when intro record omits it',
        () async {
      introRepo.clear();
      await introRepo.saveIntroduction(IntroductionModel(
        id: 'intro-1',
        introducerId: 'peer-A',
        recipientId: 'peer-B',
        introducedId: 'peer-C',
        introducerUsername: 'Alice',
        recipientUsername: 'Bob',
        introducedUsername: 'Charlie',
        recipientMlKemPublicKey: 'mlkem-pk-bob',
        createdAt: now,
      ));

      bridge.sentMessages.clear();
      bridge.commandLog.clear();

      await passIntroduction(
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
          .map((request) =>
              (request['payload'] as Map<String, dynamic>)['recipientPublicKey']
                  as String)
          .toList();

      expect(encryptRecipientKeys, hasLength(2));
      expect(encryptRecipientKeys, contains('test-mlkem-pk-peer-A'));
      expect(encryptRecipientKeys, contains('test-mlkem-pk-peer-C'));
    });

    test('rejects intro/contact stranger ML-KEM mismatches before mutation',
        () async {
      introRepo.clear();
      await introRepo.saveIntroduction(IntroductionModel(
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
      ));

      bridge.commandLog.clear();

      final result = await passIntroduction(
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
    });
  });
}
