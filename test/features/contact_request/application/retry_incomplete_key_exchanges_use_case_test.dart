import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contact_request/application/mlkem_reannounce_marker.dart';
import 'package:flutter_app/features/contact_request/application/retry_incomplete_key_exchanges_use_case.dart';
import 'package:flutter_app/features/contact_request/application/send_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/application/wake_token_pending_marker.dart';
import 'package:flutter_app/features/push/application/wake_token_reissue_coalescer.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../../../features/identity/domain/repositories/fake_identity_repository.dart';

IdentityModel _makeIdentity({String? mlKemPublicKey = 'own-mlkem-pk'}) {
  return IdentityModel(
    peerId: 'my-peer-id-1234567890',
    publicKey: 'my-public-key',
    privateKey: 'my-private-key',
    mnemonic12:
        'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
    mlKemPublicKey: mlKemPublicKey,
    mlKemSecretKey: mlKemPublicKey != null ? 'own-mlkem-sk' : null,
    createdAt: '2024-01-01T00:00:00Z',
    updatedAt: '2024-01-01T00:00:00Z',
  );
}

ContactModel _makeContact(
  String peerId, {
  String? mlKemPublicKey,
  bool isBlocked = false,
  bool isArchived = false,
}) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/p2p-circuit/rendezvous',
    username: 'user-$peerId',
    signature: 'sig-$peerId',
    scannedAt: '2024-01-01T00:00:00Z',
    mlKemPublicKey: mlKemPublicKey,
    isBlocked: isBlocked,
    blockedAt: isBlocked ? '2024-01-01T00:00:00Z' : null,
    isArchived: isArchived,
    archivedAt: isArchived ? '2024-01-01T00:00:00Z' : null,
  );
}

void main() {
  late FakeP2PService p2pService;
  late FakeContactRepository contactRepo;
  late FakeIdentityRepository identityRepo;
  late FakeBridge bridge;

  setUp(() {
    p2pService = FakeP2PService(
      initialState: const NodeState(
        isStarted: true,
        peerId: 'my-peer-id-1234567890',
        circuitAddresses: ['/p2p-circuit/addr1'],
      ),
    );
    // sendContactRequest discovers peer, dials, and sends
    p2pService.discoverPeerResult = null; // falls through to inbox fallback
    p2pService.storeInInboxResult = true;
    contactRepo = FakeContactRepository();
    identityRepo = FakeIdentityRepository();
    bridge = FakeBridge();
    // sendContactRequest calls callSignPayload → bridge.send with cmd 'payload.sign'
    // Must return a signature for the sign response to succeed
    bridge.responses['payload.sign'] = {'ok': true, 'signature': 'test-sig'};
    bridge.responses['contactrequest.encrypt'] = {
      'ok': true,
      'ephemeralPublicKey': 'ephPub',
      'ciphertext': 'ct',
      'nonce': 'nonce',
    };

    // Seed a default identity with ML-KEM key
    identityRepo.seed(_makeIdentity());
  });

  tearDown(() {
    p2pService.dispose();
  });

  group('retryIncompleteKeyExchanges', () {
    test('returns 0 when no identity', () async {
      identityRepo.seed(null);

      final result = await retryIncompleteKeyExchanges(
        contactRepo: contactRepo,
        identityRepo: identityRepo,
        p2pService: p2pService,
        bridge: bridge,
      );

      expect(result, 0);
      expect(bridge.sendCallCount, 0);
    });

    test('returns 0 when own ML-KEM key is null', () async {
      identityRepo.seed(_makeIdentity(mlKemPublicKey: null));

      final result = await retryIncompleteKeyExchanges(
        contactRepo: contactRepo,
        identityRepo: identityRepo,
        p2pService: p2pService,
        bridge: bridge,
      );

      expect(result, 0);
      expect(bridge.sendCallCount, 0);
    });

    test('returns 0 when node not running', () async {
      p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: false),
      );

      final result = await retryIncompleteKeyExchanges(
        contactRepo: contactRepo,
        identityRepo: identityRepo,
        p2pService: p2pService,
        bridge: bridge,
      );

      expect(result, 0);
      p2pService.dispose();
    });

    test('returns 0 when no contacts need retry', () async {
      contactRepo.seed([
        _makeContact('peer-a-1234567890', mlKemPublicKey: 'has-key'),
        _makeContact('peer-b-1234567890', mlKemPublicKey: 'has-key-too'),
      ]);

      final result = await retryIncompleteKeyExchanges(
        contactRepo: contactRepo,
        identityRepo: identityRepo,
        p2pService: p2pService,
        bridge: bridge,
      );

      expect(result, 0);
      expect(bridge.sendCallCount, 0);
    });

    // 171 TC-16 Shape A (INV-7): a QR-scanned contact has mlKemPublicKey==null
    // (the QR omits ML-KEM), so it IS the durable outbound queue — eligible for
    // re-send on resume/periodic retry. This is what makes the offline one-scan
    // case eventually consistent. Mutation-first guard lock: PASSES on HEAD;
    // the mutation "give the QR contact a non-null ML-KEM" excludes it -> 0.
    test('a QR contact (null ML-KEM) is eligible for retry re-send', () async {
      contactRepo.seed([
        _makeContact('qr-scanned-peer-12345', mlKemPublicKey: null),
      ]);

      final result = await retryIncompleteKeyExchanges(
        contactRepo: contactRepo,
        identityRepo: identityRepo,
        p2pService: p2pService,
        bridge: bridge,
      );

      expect(result, equals(1));
      expect(bridge.sendCallCount, greaterThan(0));
    });

    test('skips blocked contacts', () async {
      contactRepo.seed([
        _makeContact('blocked-peer-1234567890', isBlocked: true),
        _makeContact('active-peer-1234567890'),
      ]);

      final result = await retryIncompleteKeyExchanges(
        contactRepo: contactRepo,
        identityRepo: identityRepo,
        p2pService: p2pService,
        bridge: bridge,
      );

      // Only the active peer should have been attempted
      // sendContactRequest calls bridge.send for payload.sign
      expect(bridge.sendCallCount, greaterThan(0));
      // The inbox fallback succeeds → result should be 1
      expect(result, 1);
    });

    test('skips archived contacts', () async {
      contactRepo.seed([
        _makeContact('archived-peer-1234567890', isArchived: true),
      ]);

      final result = await retryIncompleteKeyExchanges(
        contactRepo: contactRepo,
        identityRepo: identityRepo,
        p2pService: p2pService,
        bridge: bridge,
      );

      // getActiveContacts() excludes archived, so nothing to retry
      expect(result, 0);
      expect(bridge.sendCallCount, 0);
    });

    test('sends to all eligible contacts', () async {
      contactRepo.seed([
        _makeContact('peer-a-1234567890'),
        _makeContact('peer-b-1234567890'),
        _makeContact('peer-c-1234567890'),
      ]);

      final result = await retryIncompleteKeyExchanges(
        contactRepo: contactRepo,
        identityRepo: identityRepo,
        p2pService: p2pService,
        bridge: bridge,
      );

      // Each sendContactRequest calls bridge.send twice (payload.sign + contactrequest.encrypt)
      // All 3 contacts should be attempted
      expect(bridge.sendCallCount, 6);
      expect(result, 3);
    });

    test('marks retry envelopes with key_exchange_retry intent', () async {
      contactRepo.seed([_makeContact('peer-a-1234567890')]);

      final result = await retryIncompleteKeyExchanges(
        contactRepo: contactRepo,
        identityRepo: identityRepo,
        p2pService: p2pService,
        bridge: bridge,
      );

      expect(result, 1);
      final envelope =
          jsonDecode(p2pService.lastStoreInInboxMessage!)
              as Map<String, dynamic>;
      expect(
        envelope['intent'],
        equals(ContactRequestSendIntent.keyExchangeRetry.wireValue),
      );
    });

    test('contacts with existing ML-KEM key are skipped', () async {
      contactRepo.seed([
        _makeContact('has-key-1234567890', mlKemPublicKey: 'existing-key'),
        _makeContact('no-key-a-1234567890'),
        _makeContact('no-key-b-1234567890'),
      ]);

      final result = await retryIncompleteKeyExchanges(
        contactRepo: contactRepo,
        identityRepo: identityRepo,
        p2pService: p2pService,
        bridge: bridge,
      );

      // Only 2 contacts should be attempted (the ones without keys)
      // Each calls bridge.send twice (payload.sign + contactrequest.encrypt)
      expect(bridge.sendCallCount, 4);
      expect(result, 2);
    });

    test('partial failure: counts only successes', () async {
      contactRepo.seed([
        _makeContact('peer-a-1234567890'),
        _makeContact('peer-b-1234567890'),
      ]);

      // Use a bridge that fails on 1st sign call, succeeds on 2nd
      final failingBridge = _FailOnNthBridge(failOnCall: 1);
      failingBridge.responses['payload.sign'] = {
        'ok': true,
        'signature': 'test-sig',
      };
      failingBridge.responses['contactrequest.encrypt'] = {
        'ok': true,
        'ephemeralPublicKey': 'ephPub',
        'ciphertext': 'ct',
        'nonce': 'nonce',
      };

      final result = await retryIncompleteKeyExchanges(
        contactRepo: contactRepo,
        identityRepo: identityRepo,
        p2pService: p2pService,
        bridge: failingBridge,
      );

      // First fails (bridge throw → caught as error), second succeeds
      expect(result, 1);
    });

    test(
      'sends keyExchangeRetry to contacts in re-announce marker even when '
      'their key is non-null',
      () async {
        contactRepo.seed([
          _makeContact('has-key-1234567890', mlKemPublicKey: 'their-key'),
          _makeContact('other-key-1234567890', mlKemPublicKey: 'other-key'),
        ]);
        final secureKeyStore = FakeSecureKeyStore();
        await writeMlKemReannounceMarker(secureKeyStore, [
          'has-key-1234567890',
        ]);

        final result = await retryIncompleteKeyExchanges(
          contactRepo: contactRepo,
          identityRepo: identityRepo,
          p2pService: p2pService,
          bridge: bridge,
          secureKeyStore: secureKeyStore,
        );

        // Only the marker contact is re-announced; the other keyed contact
        // keeps the long-standing skip behavior.
        expect(result, 1);
      },
    );

    test(
      'removes peer from marker only after successful send; partial failure '
      'retains remainder',
      () async {
        contactRepo.seed([
          _makeContact('marker-a-1234567890', mlKemPublicKey: 'key-a'),
          _makeContact('marker-b-1234567890', mlKemPublicKey: 'key-b'),
        ]);
        final secureKeyStore = FakeSecureKeyStore();
        await writeMlKemReannounceMarker(secureKeyStore, [
          'marker-a-1234567890',
          'marker-b-1234567890',
        ]);

        // First contact's sign call fails → its send fails; second succeeds.
        final failingBridge = _FailOnNthBridge(failOnCall: 1);
        failingBridge.responses['payload.sign'] = {
          'ok': true,
          'signature': 'test-sig',
        };
        failingBridge.responses['contactrequest.encrypt'] = {
          'ok': true,
          'ephemeralPublicKey': 'ephPub',
          'ciphertext': 'ct',
          'nonce': 'nonce',
        };

        final result = await retryIncompleteKeyExchanges(
          contactRepo: contactRepo,
          identityRepo: identityRepo,
          p2pService: p2pService,
          bridge: failingBridge,
          secureKeyStore: secureKeyStore,
        );

        expect(result, 1);
        final remaining = await readMlKemReannounceMarker(secureKeyStore);
        expect(remaining, ['marker-a-1234567890']);
      },
    );

    test('marker drained empty clears the secure-storage entry', () async {
      contactRepo.seed([
        _makeContact('only-marker-1234567890', mlKemPublicKey: 'their-key'),
      ]);
      final secureKeyStore = FakeSecureKeyStore();
      await writeMlKemReannounceMarker(secureKeyStore, [
        'only-marker-1234567890',
      ]);

      final result = await retryIncompleteKeyExchanges(
        contactRepo: contactRepo,
        identityRepo: identityRepo,
        p2pService: p2pService,
        bridge: bridge,
        secureKeyStore: secureKeyStore,
      );

      expect(result, 1);
      expect(
        await secureKeyStore.containsKey(kMlKemReannouncePendingKey),
        isFalse,
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 217 / CV-14 wake-token re-issue coalescing (A15) and backfill drain (A10).
  // ───────────────────────────────────────────────────────────────────────────
  group('217 CV-14 wake-token re-issue coalescing', () {
    test(
      'A15: N stream events within one window ⇒ re-issue registers exactly once',
      () async {
        var reissueCalls = 0;
        final coalescer = WakeTokenReissueCoalescer(
          reissue: () async => reissueCalls++,
          window: const Duration(milliseconds: 20),
        );

        // A burst of 5 contact-key/auto-add events.
        for (var i = 0; i < 5; i++) {
          coalescer.trigger();
        }
        await Future<void>.delayed(const Duration(milliseconds: 80));

        expect(reissueCalls, 1);
        coalescer.dispose();
      },
    );
  });

  group('217 CV-14 wake-token backfill drain', () {
    test(
      'A10: wake_token_pending (distinct key) contacts drained only after send '
      'success; partial failure keeps the remainder',
      () async {
        // Distinct-key guard: the wake marker must NOT reuse the mlkem key.
        expect(kWakeTokenPendingKey, 'wake_token_pending');
        expect(kWakeTokenPendingKey, isNot(kMlKemReannouncePendingKey));

        // Both already have ML-KEM keys, so ONLY the wake marker makes them
        // eligible — proving the wake drain is its OWN block (not the mlkem one).
        contactRepo.seed([
          _makeContact('wake-a-1234567890', mlKemPublicKey: 'key-a'),
          _makeContact('wake-b-1234567890', mlKemPublicKey: 'key-b'),
        ]);
        final secureKeyStore = FakeSecureKeyStore();
        await writeWakeTokenPendingMarker(secureKeyStore, [
          'wake-a-1234567890',
          'wake-b-1234567890',
        ]);

        // First contact's sign call fails → its send fails; second succeeds.
        final failingBridge = _FailOnNthBridge(failOnCall: 1);
        failingBridge.responses['payload.sign'] = {
          'ok': true,
          'signature': 'test-sig',
        };
        failingBridge.responses['contactrequest.encrypt'] = {
          'ok': true,
          'ephemeralPublicKey': 'ephPub',
          'ciphertext': 'ct',
          'nonce': 'nonce',
        };

        await retryIncompleteKeyExchanges(
          contactRepo: contactRepo,
          identityRepo: identityRepo,
          p2pService: p2pService,
          bridge: failingBridge,
          secureKeyStore: secureKeyStore,
        );

        // wake-b drained on success; wake-a retained for the next trigger.
        // The mlkem marker was never touched (distinct block).
        final remaining = await readWakeTokenPendingMarker(secureKeyStore);
        expect(remaining, ['wake-a-1234567890']);
        expect(
          await secureKeyStore.containsKey(kMlKemReannouncePendingKey),
          isFalse,
        );
      },
    );
  });
}

/// A bridge that throws on the Nth send call (1-indexed) and succeeds on others.
class _FailOnNthBridge extends FakeBridge {
  final int failOnCall;
  int _callCount = 0;

  _FailOnNthBridge({required this.failOnCall});

  @override
  Future<String> send(String message) async {
    _callCount++;
    if (_callCount == failOnCall) {
      throw Exception('Simulated bridge failure');
    }
    return super.send(message);
  }
}
