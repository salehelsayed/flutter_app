import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/p2p/application/start_node_use_case.dart';
import 'package:flutter_app/features/identity/application/linked_installation_authority.dart';
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
  mnemonic12:
      'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
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

      await startP2PNode(identityRepo: identityRepo, p2pService: p2pService);

      expect(p2pService.lastStartNodePrivateKey, _testIdentity.privateKey);
    });

    test('passes peerId to service', () async {
      identityRepo.seed(_testIdentity);

      await startP2PNode(identityRepo: identityRepo, p2pService: p2pService);

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

    test('returns accountMigrationBlocked without starting service', () async {
      identityRepo.seed(_testIdentity);

      final result = await startP2PNode(
        identityRepo: identityRepo,
        p2pService: p2pService,
        accountMigrationNetworkGate: ({peerId, required operation}) async {
          expect(peerId, _testIdentity.peerId);
          expect(operation, 'p2p_start');
          return false;
        },
      );

      expect(result, StartNodeResult.accountMigrationBlocked);
      expect(p2pService.startNodeCallCount, 0);
    });

    test('TC-360-01a linked-secondary transport identity is distinct stable '
        'and fail-closed', () async {
      // Real Go-derived account/transport pairs, so the offline key->peer
      // barrier below is a genuine derivation and not a string compare.
      const accountPublicKey = 'xXheGGW3CJOK/4Fh1XMAZJZmOxqhCDTjltxWaGmixmo=';
      const accountPeerId =
          '12D3KooWP7CwQswqLKZbwvYd9wrEynnL9F2aKVP1X9huNASBTuqj';
      const transportPublicKey = 'xvKsVZiXDHljNxTT61w017/D6S2ljHNUs3mW2aSvOrI=';
      const transportPeerId =
          '12D3KooWPCyWnZCXR3VGdrQjLr5d8TBaAHD956XZvo6xoCXYB5AR';

      final linkedIdentity = IdentityModel(
        peerId: accountPeerId,
        publicKey: accountPublicKey,
        privateKey: 'account-private-key',
        mnemonic12: _testIdentity.mnemonic12,
        mlKemPublicKey: 'mlkem-pub',
        mlKemSecretKey: 'mlkem-sec',
        username: 'Linked',
        createdAt: '2026-01-01T00:00:00.000Z',
        updatedAt: '2026-01-01T00:00:00.000Z',
      );

      LinkedTransportCredential credential({
        String peerId = transportPeerId,
        String publicKey = transportPublicKey,
        String accountPeer = accountPeerId,
      }) {
        return LinkedTransportCredential(
          state: LinkedTransportCredentialState.active,
          accountPeerId: accountPeer,
          accountPublicKey: accountPublicKey,
          deviceId: 'installation-1',
          transportPeerId: peerId,
          transportPublicKey: publicKey,
          transportPrivateKey: 'transport-private-key',
          createdAt: '2026-01-01T00:00:00.000Z',
          activatedAt: '2026-01-01T00:00:00.000Z',
        );
      }

      LinkedInstallationAuthoritySnapshot snapshot(
        LinkedInstallationDisposition disposition, {
        LinkedTransportCredential? withCredential,
        String? reason,
      }) {
        return LinkedInstallationAuthoritySnapshot(
          disposition: disposition,
          credential: withCredential,
          failClosedReason: reason,
        );
      }

      // ── Ordinary primary is byte-for-byte the incumbent path. ──
      identityRepo.seed(_testIdentity);
      p2pService.startNodeResult = true;
      var gatePeerIds = <String?>[];
      var result = await startP2PNode(
        identityRepo: identityRepo,
        p2pService: p2pService,
        accountMigrationNetworkGate: ({peerId, required operation}) async {
          gatePeerIds.add(peerId);
          return true;
        },
        linkedAuthority: snapshot(LinkedInstallationDisposition.primary),
      );
      expect(result, StartNodeResult.success);
      expect(p2pService.lastStartNodePrivateKey, _testIdentity.privateKey);
      expect(p2pService.lastStartNodePeerId, _testIdentity.peerId);
      expect(gatePeerIds, <String?>[_testIdentity.peerId]);

      // ── Active linked: the gate sees the LOGICAL ACCOUNT, the bridge sees
      // the TRANSPORT. Conflating them would evaluate account-level
      // migration authority against a per-device identity. ──
      identityRepo.seed(linkedIdentity);
      p2pService.startNodeCallCount = 0;
      gatePeerIds = <String?>[];
      result = await startP2PNode(
        identityRepo: identityRepo,
        p2pService: p2pService,
        accountMigrationNetworkGate: ({peerId, required operation}) async {
          gatePeerIds.add(peerId);
          return true;
        },
        linkedAuthority: snapshot(
          LinkedInstallationDisposition.active,
          withCredential: credential(),
        ),
      );
      expect(result, StartNodeResult.success);
      expect(gatePeerIds, <String?>[accountPeerId]);
      expect(p2pService.lastStartNodePeerId, transportPeerId);
      expect(p2pService.lastStartNodePrivateKey, 'transport-private-key');
      expect(
        p2pService.lastStartNodePeerId,
        isNot(accountPeerId),
        reason:
            'a linked secondary exists precisely so it stops sharing the '
            'account mailbox',
      );

      // ── Every partial/fail-closed disposition refuses BEFORE the node
      // starts, and never falls back to the account transport.
      //
      // `preparing` deliberately carries its credential, exactly as
      // `LinkedInstallationAuthority.load()` returns it. A snapshot with a
      // null credential would be refused by the account-match guard further
      // down and would NOT discriminate the disposition check under test. ──
      for (final refusing
          in <(LinkedInstallationDisposition, LinkedTransportCredential?)>[
            (LinkedInstallationDisposition.awaitingCredential, null),
            (LinkedInstallationDisposition.preparing, credential()),
            (LinkedInstallationDisposition.failClosed, null),
          ]) {
        final (disposition, refusingCredential) = refusing;
        p2pService.startNodeCallCount = 0;
        var gateCalls = 0;
        final refused = await startP2PNode(
          identityRepo: identityRepo,
          p2pService: p2pService,
          accountMigrationNetworkGate: ({peerId, required operation}) async {
            gateCalls += 1;
            return true;
          },
          linkedAuthority: snapshot(
            disposition,
            withCredential: refusingCredential,
            reason: 'test',
          ),
        );
        expect(
          refused,
          StartNodeResult.linkedAuthorityRefused,
          reason: disposition.name,
        );
        expect(p2pService.startNodeCallCount, 0, reason: disposition.name);
        expect(
          gateCalls,
          0,
          reason: 'a fail-closed installation performs no account work',
        );
      }

      // ── Cross-account credential refuses. ──
      p2pService.startNodeCallCount = 0;
      expect(
        await startP2PNode(
          identityRepo: identityRepo,
          p2pService: p2pService,
          linkedAuthority: snapshot(
            LinkedInstallationDisposition.active,
            withCredential: credential(accountPeer: 'someone-elses-account'),
          ),
        ),
        StartNodeResult.linkedAuthorityRefused,
      );
      expect(p2pService.startNodeCallCount, 0);

      // ── The offline key->peer barrier is mandatory for BOTH halves. ──
      p2pService.startNodeCallCount = 0;
      expect(
        await startP2PNode(
          identityRepo: identityRepo,
          p2pService: p2pService,
          linkedAuthority: snapshot(
            LinkedInstallationDisposition.active,
            // A transport peer that the carried transport key does not
            // derive: exactly what a tampered or corrupted credential looks
            // like.
            withCredential: credential(
              peerId: '12D3KooWS2Jiwq8amLufp2meksG2jhWkZzhvAmetUsPdWv5xk7ZY',
            ),
          ),
        ),
        StartNodeResult.linkedAuthorityRefused,
      );
      expect(p2pService.startNodeCallCount, 0);

      // An account key that no longer derives its own account peer also
      // refuses — that installation cannot be trusted to name the right
      // logical owner in a QR a contact will bind to.
      identityRepo.seed(
        IdentityModel(
          peerId: accountPeerId,
          publicKey: transportPublicKey,
          privateKey: 'account-private-key',
          mnemonic12: _testIdentity.mnemonic12,
          mlKemPublicKey: 'mlkem-pub',
          mlKemSecretKey: 'mlkem-sec',
          username: 'Linked',
          createdAt: '2026-01-01T00:00:00.000Z',
          updatedAt: '2026-01-01T00:00:00.000Z',
        ),
      );
      p2pService.startNodeCallCount = 0;
      expect(
        await startP2PNode(
          identityRepo: identityRepo,
          p2pService: p2pService,
          linkedAuthority: snapshot(
            LinkedInstallationDisposition.active,
            withCredential: credential(),
          ),
        ),
        StartNodeResult.linkedAuthorityRefused,
      );
      expect(p2pService.startNodeCallCount, 0);
    });
  });
}
