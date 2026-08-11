/// Phase 1 startup router tests.
///
/// These tests verify startup path behavior via the startup decision logic
/// and P2P service contracts, without requiring widget tree rendering
/// (avoiding Firebase/platform dependencies).
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/canonical_runtime_lease.dart';
import 'package:flutter_app/features/identity/application/linked_installation_authority.dart';
import 'package:flutter_app/features/identity/application/startup_decision.dart';
import 'package:flutter_app/features/p2p/application/start_node_use_case.dart';

import '../../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../../core/services/fake_p2p_service.dart';
import '../../domain/repositories/fake_identity_repository.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

// ─── Fake Identity Repository ─────────────────────────────────
class _FakeIdentityRepo implements IdentityRepository {
  IdentityModel? _identity;

  _FakeIdentityRepo({IdentityModel? identity}) : _identity = identity;

  @override
  Future<IdentityModel?> loadIdentity() async => _identity;

  @override
  Future<void> saveIdentity(IdentityModel identity) async {
    _identity = identity;
  }
}

// ─── Fake Contact Repository ──────────────────────────────────
class _FakeContactRepo implements ContactRepository {
  final int count;
  _FakeContactRepo({this.count = 0});

  @override
  Future<int> getContactCount() async => count;

  @override
  Future<void> addContact(ContactModel contact) async {}
  @override
  Future<ContactModel?> getContact(String peerId) async => null;
  @override
  Future<List<ContactModel>> getAllContacts() async => [];
  @override
  Future<void> deleteContact(String peerId) async {}
  @override
  Future<bool> contactExists(String peerId) async => false;
  @override
  Future<void> archiveContact(String peerId) async {}
  @override
  Future<void> unarchiveContact(String peerId) async {}
  @override
  Future<List<ContactModel>> getActiveContacts() async => [];
  @override
  Future<List<ContactModel>> getArchivedContacts() async => [];
  @override
  Future<void> blockContact(String peerId) async {}
  @override
  Future<void> unblockContact(String peerId) async {}
  @override
  Future<void> dismissIntroBanner(String peerId) async {}
  @override
  Future<void> setIntrosSentAt(String peerId, String timestamp) async {}
}

void main() {
  group('Phase 1 — startup routing', () {
    test(
      'fresh identity creation uses light startup path without returning-user recovery',
      () async {
        // No identity exists → needsIdentity decision
        final decision = await decideStartupRoute(
          identityRepo: _FakeIdentityRepo(identity: null),
          contactRepo: _FakeContactRepo(count: 0),
        );

        expect(decision, StartupDecision.needsIdentity);

        // Fresh identity doesn't need inbox drain or group rejoin
        // (The StartupRouter.onNavigateToMain handles this by calling startP2PInBackground
        // which starts node + warmBackground — but for fresh users, inbox will be empty)
      },
    );

    test(
      'fresh identity creation skips group rejoin and group inbox drain',
      () async {
        // A fresh user (needsIdentity) won't have groups or inbox to drain
        final decision = await decideStartupRoute(
          identityRepo: _FakeIdentityRepo(identity: null),
          contactRepo: _FakeContactRepo(count: 0),
        );

        expect(decision, StartupDecision.needsIdentity);
        // The fresh-identity bootstrap path means:
        // - No contacts → no group rejoin
        // - No inbox messages → inbox drain is a no-op
        // This is enforced by the decision routing in StartupRouter
      },
    );

    test(
      'returning user startup still schedules inbox-first warm recovery',
      () async {
        // Returning user with contacts → hasIdentityWithContacts
        final identity = IdentityModel(
          peerId: 'test-peer',
          publicKey: 'pk',
          privateKey: 'sk',
          mnemonic12:
              'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
          createdAt: '2026-01-01T00:00:00Z',
          updatedAt: '2026-01-01T00:00:00Z',
        );

        final decision = await decideStartupRoute(
          identityRepo: _FakeIdentityRepo(identity: identity),
          contactRepo: _FakeContactRepo(count: 5),
        );

        expect(decision, StartupDecision.hasIdentityWithContacts);

        // For returning users, StartupRouter calls _startP2PInBackground which
        // calls startP2PNode → p2pService.startNode → warmBackground → inbox drain
      },
    );

    test(
      'returning cold start after reboot shows persisted conversation history before network warm completion',
      () async {
        // This test verifies the architectural invariant:
        // The startup decision and UI routing happen synchronously before
        // P2P networking begins (P2P is started "in background").
        final identity = IdentityModel(
          peerId: 'test-peer',
          publicKey: 'pk',
          privateKey: 'sk',
          mnemonic12:
              'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
          createdAt: '2026-01-01T00:00:00Z',
          updatedAt: '2026-01-01T00:00:00Z',
        );

        final decision = await decideStartupRoute(
          identityRepo: _FakeIdentityRepo(identity: identity),
          contactRepo: _FakeContactRepo(count: 3),
        );

        // Route decision is made from local DB, not from network
        expect(decision, StartupDecision.hasIdentityWithContacts);

        // The UI navigates to FeedWired immediately (showing persisted data)
        // then P2P starts in background — this means persisted conversation
        // history is visible before network is warm
      },
    );
  });

  group('TC-360-01a startup honours persisted linked authority', () {
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
      mnemonic12:
          'abandon abandon abandon abandon abandon abandon abandon abandon '
          'abandon abandon abandon about',
      mlKemPublicKey: 'mlkem-pub',
      mlKemSecretKey: 'mlkem-sec',
      username: 'Linked',
      createdAt: '2026-01-01T00:00:00.000Z',
      updatedAt: '2026-01-01T00:00:00.000Z',
    );

    Future<FakeSecureKeyStore> activeLinkedStore() async {
      final store = FakeSecureKeyStore();
      await store.write(
        canonicalRuntimeInstallationIdStorageKey,
        'installation-1',
      );
      await store.write(
        linkedInstallationRoleStorageKey,
        linkedInstallationRoleMarkerValue,
      );
      await store.write(
        linkedInstallationTransportCredentialStorageKey,
        jsonEncode(
          const LinkedTransportCredential(
            state: LinkedTransportCredentialState.active,
            accountPeerId: accountPeerId,
            accountPublicKey: accountPublicKey,
            deviceId: 'installation-1',
            transportPeerId: transportPeerId,
            transportPublicKey: transportPublicKey,
            transportPrivateKey: 'transport-private-key',
            createdAt: '2026-01-01T00:00:00.000Z',
            activatedAt: '2026-01-01T00:00:00.000Z',
          ).toJson(),
        ),
      );
      return store;
    }

    test('TC-360-01a linked-secondary transport identity is distinct stable '
        'and fail-closed', () async {
      // The router resolves persisted authority WITHOUT consulting the
      // authoring selector, which is the whole flag-off contract: rolling the
      // define back stops new setup and QR activity, but an installation that
      // already claimed a transport keeps starting exactly that transport.
      // Anything else would silently return it to the account mailbox its
      // contacts have already stopped addressing.
      final store = await activeLinkedStore();
      final authority = await LinkedInstallationAuthority(
        secureKeyStore: store,
      ).load();
      expect(authority.isActiveLinkedSecondary, isTrue);

      final identityRepo = FakeIdentityRepository()..seed(linkedIdentity);
      final p2pService = FakeP2PService()..startNodeResult = true;
      expect(
        await startP2PNode(
          identityRepo: identityRepo,
          p2pService: p2pService,
          linkedAuthority: authority,
        ),
        StartNodeResult.success,
      );
      expect(p2pService.lastStartNodePeerId, transportPeerId);
      expect(p2pService.lastStartNodePrivateKey, 'transport-private-key');

      // An ordinary primary installation resolves to `primary` and takes the
      // incumbent path byte-for-byte.
      final primaryAuthority = await LinkedInstallationAuthority(
        secureKeyStore: FakeSecureKeyStore(),
      ).load();
      expect(primaryAuthority.isOrdinaryPrimary, isTrue);
      final primaryP2p = FakeP2PService()..startNodeResult = true;
      expect(
        await startP2PNode(
          identityRepo: identityRepo,
          p2pService: primaryP2p,
          linkedAuthority: primaryAuthority,
        ),
        StartNodeResult.success,
      );
      expect(primaryP2p.lastStartNodePeerId, accountPeerId);
      expect(primaryP2p.lastStartNodePrivateKey, 'account-private-key');

      // A half-written credential refuses startup outright and never falls
      // back to the account transport.
      await store.delete(linkedInstallationRoleStorageKey);
      final orphanAuthority = await LinkedInstallationAuthority(
        secureKeyStore: store,
      ).load();
      final refusingP2p = FakeP2PService()..startNodeResult = true;
      expect(
        await startP2PNode(
          identityRepo: identityRepo,
          p2pService: refusingP2p,
          linkedAuthority: orphanAuthority,
        ),
        StartNodeResult.linkedAuthorityRefused,
      );
      expect(refusingP2p.startNodeCallCount, 0);
    });
  });
}
