import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/introduction/application/accept_introduction_use_case.dart';
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

  test('accept sets recipientStatus to accepted when user is recipient',
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
  });

  test('accept sets introducedStatus to accepted when user is introduced',
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
  });

  test(
      'single-side accept does NOT change overall to mutualAccepted', () async {
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
  });

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
}
