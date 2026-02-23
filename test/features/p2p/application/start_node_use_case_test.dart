import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/p2p/application/start_node_use_case.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';

import '../../../features/identity/domain/repositories/fake_identity_repository.dart';
import '../../../core/services/fake_p2p_service.dart';

/// A [FakeP2PService] that throws on startNode for error-path testing.
class _ThrowingP2PService extends FakeP2PService {
  @override
  Future<bool> startNode(String privateKeyBase64, String peerId) async {
    startNodeCallCount++;
    lastStartNodePrivateKey = privateKeyBase64;
    lastStartNodePeerId = peerId;
    throw Exception('Simulated bridge crash');
  }
}

final _testIdentity = IdentityModel(
  peerId: 'peer-start-node-001',
  publicKey: 'pub-key-base64',
  privateKey: 'priv-key-base64',
  mnemonic12: 'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
  mlKemPublicKey: 'mlkem-pub',
  mlKemSecretKey: 'mlkem-sec',
  username: 'TestUser',
  createdAt: '2026-01-01T00:00:00.000Z',
  updatedAt: '2026-01-01T00:00:00.000Z',
);

void main() {
  late FakeIdentityRepository identityRepo;
  late FakeP2PService p2pService;

  setUp(() {
    identityRepo = FakeIdentityRepository();
    p2pService = FakeP2PService();
  });

  group('startP2PNode', () {
    test('returns noIdentity when identity is null', () async {
      // identityRepo has no identity seeded (null by default)
      final result = await startP2PNode(
        identityRepo: identityRepo,
        p2pService: p2pService,
      );

      expect(result, StartNodeResult.noIdentity);
      expect(p2pService.startNodeCallCount, 0);
    });

    test('returns success when startNode returns true', () async {
      identityRepo.seed(_testIdentity);
      p2pService.startNodeResult = true;

      final result = await startP2PNode(
        identityRepo: identityRepo,
        p2pService: p2pService,
      );

      expect(result, StartNodeResult.success);
    });

    test('passes privateKey to service', () async {
      identityRepo.seed(_testIdentity);

      await startP2PNode(
        identityRepo: identityRepo,
        p2pService: p2pService,
      );

      expect(p2pService.lastStartNodePrivateKey, _testIdentity.privateKey);
    });

    test('passes peerId to service', () async {
      identityRepo.seed(_testIdentity);

      await startP2PNode(
        identityRepo: identityRepo,
        p2pService: p2pService,
      );

      expect(p2pService.lastStartNodePeerId, _testIdentity.peerId);
    });

    test('returns bridgeError when startNode returns false', () async {
      identityRepo.seed(_testIdentity);
      p2pService.startNodeResult = false;

      final result = await startP2PNode(
        identityRepo: identityRepo,
        p2pService: p2pService,
      );

      expect(result, StartNodeResult.bridgeError);
    });

    test('returns bridgeError when startNode throws', () async {
      identityRepo.seed(_testIdentity);
      final throwingService = _ThrowingP2PService();

      final result = await startP2PNode(
        identityRepo: identityRepo,
        p2pService: throwingService,
      );

      expect(result, StartNodeResult.bridgeError);
      expect(throwingService.startNodeCallCount, 1);
    });
  });
}
