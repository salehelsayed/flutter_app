import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/introduction/application/send_introduction_use_case.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_introduction_repository.dart';

void main() {
  late FakeP2PNetwork network;
  late FakeP2PService p2pServiceA;
  late PassthroughCryptoBridge bridge;
  late InMemoryContactRepository contactRepo;
  late InMemoryIntroductionRepository introRepo;

  late ContactModel contactB;
  late ContactModel contactC;
  late ContactModel contactD;

  setUp(() {
    network = FakeP2PNetwork();
    p2pServiceA = FakeP2PService(peerId: 'peer-A', network: network);
    // Register receivers on the network so delivery succeeds
    FakeP2PService(peerId: 'peer-B', network: network);
    FakeP2PService(peerId: 'peer-C', network: network);
    FakeP2PService(peerId: 'peer-D', network: network);
    bridge = PassthroughCryptoBridge();
    contactRepo = InMemoryContactRepository();
    introRepo = InMemoryIntroductionRepository();

    contactB = ContactModel(
      peerId: 'peer-B',
      publicKey: 'pk-peer-B',
      rendezvous: '/dns4/relay/tcp/443/p2p/relay',
      username: 'Bob',
      signature: 'sig-peer-B',
      scannedAt: DateTime.now().toUtc().toIso8601String(),
      mlKemPublicKey: 'test-mlkem-pk-peer-B',
    );

    contactC = ContactModel(
      peerId: 'peer-C',
      publicKey: 'pk-peer-C',
      rendezvous: '/dns4/relay/tcp/443/p2p/relay',
      username: 'Charlie',
      signature: 'sig-peer-C',
      scannedAt: DateTime.now().toUtc().toIso8601String(),
      mlKemPublicKey: 'test-mlkem-pk-peer-C',
    );

    contactD = ContactModel(
      peerId: 'peer-D',
      publicKey: 'pk-peer-D',
      rendezvous: '/dns4/relay/tcp/443/p2p/relay',
      username: 'Diana',
      signature: 'sig-peer-D',
      scannedAt: DateTime.now().toUtc().toIso8601String(),
      mlKemPublicKey: 'test-mlkem-pk-peer-D',
    );

    contactRepo.addTestContact(contactB);
    contactRepo.addTestContact(contactC);
    contactRepo.addTestContact(contactD);
  });

  Future<List<IntroductionModel>> _sendTwoFriends() {
    return sendIntroductions(
      contactRepo: contactRepo,
      introRepo: introRepo,
      p2pService: p2pServiceA,
      bridge: bridge,
      introducerPeerId: 'peer-A',
      introducerUsername: 'Alice',
      recipientPeerId: 'peer-B',
      recipientUsername: 'Bob',
      recipientMlKemPublicKey: contactB.mlKemPublicKey,
      friendsToIntroduce: [contactC, contactD],
    );
  }

  test('creates N introduction records for N selected friends', () async {
    final results = await _sendTwoFriends();
    expect(results.length, 2);
  });

  test('each record has correct introducerId', () async {
    final results = await _sendTwoFriends();
    for (final model in results) {
      expect(model.introducerId, 'peer-A');
    }
  });

  test('each record has correct recipientId and introducedId', () async {
    final results = await _sendTwoFriends();
    expect(results[0].recipientId, 'peer-B');
    expect(results[0].introducedId, 'peer-C');
    expect(results[1].recipientId, 'peer-B');
    expect(results[1].introducedId, 'peer-D');
  });

  test('each record initializes with pending statuses', () async {
    final results = await _sendTwoFriends();
    for (final model in results) {
      expect(model.recipientStatus, IntroductionStatus.pending);
      expect(model.introducedStatus, IntroductionStatus.pending);
      expect(model.status, IntroductionOverallStatus.pending);
    }
  });

  test('introsSentAt is set on the recipient contact', () async {
    await _sendTwoFriends();
    final updatedContact = await contactRepo.getContact('peer-B');
    expect(updatedContact, isNotNull);
    expect(updatedContact!.introsSentAt, isNotNull);
  });

  test('payload sent to recipient via P2P', () async {
    await _sendTwoFriends();
    // 2 friends x 2 messages each (one to recipient, one to friend) = 4 deliveries
    // At minimum, 2 messages go to the recipient (one per friend)
    expect(network.deliverCallCount, greaterThanOrEqualTo(2));
  });

  test('payload sent to introduced friend via P2P', () async {
    await _sendTwoFriends();
    // 2 friends: each gets 1 message to recipient + 1 message to friend = 4 total
    expect(network.deliverCallCount, 4);
  });

  test('v2 encryption used when target has ML-KEM key', () async {
    await _sendTwoFriends();
    // All 4 targets (recipient x2, friend-C, friend-D) have ML-KEM keys
    final encryptCalls =
        bridge.commandLog.where((cmd) => cmd == 'message.encrypt').length;
    expect(encryptCalls, 4);
  });

  test('v1 plaintext used when target lacks ML-KEM key', () async {
    // Create a friend without ML-KEM key
    final contactNoMlKem = ContactModel(
      peerId: 'peer-E',
      publicKey: 'pk-peer-E',
      rendezvous: '/dns4/relay/tcp/443/p2p/relay',
      username: 'Eve',
      signature: 'sig-peer-E',
      scannedAt: DateTime.now().toUtc().toIso8601String(),
      mlKemPublicKey: null,
    );
    contactRepo.addTestContact(contactNoMlKem);
    // Register receiver on network so delivery succeeds
    FakeP2PService(peerId: 'peer-E', network: network);

    bridge.commandLog.clear();

    await sendIntroductions(
      contactRepo: contactRepo,
      introRepo: introRepo,
      p2pService: p2pServiceA,
      bridge: bridge,
      introducerPeerId: 'peer-A',
      introducerUsername: 'Alice',
      recipientPeerId: 'peer-B',
      recipientUsername: 'Bob',
      recipientMlKemPublicKey: null, // No ML-KEM for recipient either
      friendsToIntroduce: [contactNoMlKem],
    );

    // Neither recipient nor introduced friend has ML-KEM key → no encrypt calls
    final encryptCalls =
        bridge.commandLog.where((cmd) => cmd == 'message.encrypt').length;
    expect(encryptCalls, 0);
  });

  test('returns list of created IntroductionModels', () async {
    final results = await _sendTwoFriends();
    expect(results, isList);
    expect(results.length, 2);
    // Each result should have a non-empty ID
    for (final model in results) {
      expect(model.id, isNotEmpty);
    }
  });

  test('records are persisted in introRepo', () async {
    final results = await _sendTwoFriends();
    for (final model in results) {
      final persisted = await introRepo.getIntroduction(model.id);
      expect(persisted, isNotNull);
      expect(persisted!.id, model.id);
      expect(persisted.introducerId, 'peer-A');
      expect(persisted.recipientId, 'peer-B');
    }
  });
}
