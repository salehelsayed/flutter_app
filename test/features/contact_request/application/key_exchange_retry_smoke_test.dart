import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/features/contact_request/application/key_exchange_retry_coordinator.dart';
import 'package:flutter_app/features/contact_request/application/key_exchange_retrier.dart';
import 'package:flutter_app/features/contact_request/application/retry_incomplete_key_exchanges_use_case.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../../../features/identity/domain/repositories/fake_identity_repository.dart';

IdentityModel _makeIdentity() {
  return IdentityModel(
    peerId: 'my-peer-id-1234567890',
    publicKey: 'my-public-key',
    privateKey: 'my-private-key',
    mnemonic12:
        'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
    mlKemPublicKey: 'own-mlkem-pk',
    mlKemSecretKey: 'own-mlkem-sk',
    createdAt: '2024-01-01T00:00:00Z',
    updatedAt: '2024-01-01T00:00:00Z',
  );
}

ContactModel _makeContact(String peerId, {String? mlKemPublicKey}) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/p2p-circuit/rendezvous',
    username: 'user-$peerId',
    signature: 'sig-$peerId',
    scannedAt: '2024-01-01T00:00:00Z',
    mlKemPublicKey: mlKemPublicKey,
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
    p2pService.storeInInboxResult = true;
    contactRepo = FakeContactRepository();
    identityRepo = FakeIdentityRepository();
    bridge = FakeBridge();
    bridge.responses['payload.sign'] = {'ok': true, 'signature': 'test-sig'};
    bridge.responses['contactrequest.encrypt'] = {
      'ok': true,
      'ephemeralPublicKey': 'ephPub',
      'ciphertext': 'ct',
      'nonce': 'nonce',
    };
    identityRepo.seed(_makeIdentity());
  });

  tearDown(() {
    p2pService.dispose();
  });

  group('Key exchange retry smoke tests', () {
    test(
      'simulated app resume triggers retry for contacts missing keys',
      () async {
        contactRepo.seed([
          _makeContact('peer-a-1234567890'),
          _makeContact('peer-b-1234567890'),
        ]);

        final sent = await retryIncompleteKeyExchanges(
          contactRepo: contactRepo,
          identityRepo: identityRepo,
          p2pService: p2pService,
          bridge: bridge,
        );

        expect(sent, 2);
        expect(bridge.sendCallCount, greaterThan(0));
      },
    );

    test('second resume with keys filled sends 0', () async {
      contactRepo.seed([_makeContact('peer-a-1234567890')]);

      // First resume
      final sent1 = await retryIncompleteKeyExchanges(
        contactRepo: contactRepo,
        identityRepo: identityRepo,
        p2pService: p2pService,
        bridge: bridge,
      );
      expect(sent1, 1);

      // Simulate key exchange completion (contact now has ML-KEM key)
      contactRepo.seed([
        _makeContact('peer-a-1234567890', mlKemPublicKey: 'received-key'),
      ]);

      // Second resume
      final sent2 = await retryIncompleteKeyExchanges(
        contactRepo: contactRepo,
        identityRepo: identityRepo,
        p2pService: p2pService,
        bridge: bridge,
      );
      expect(sent2, 0);
    });

    test('large contact set has jitter delay', () async {
      // Seed 10 contacts without ML-KEM keys
      final contacts = List.generate(
        10,
        (i) => _makeContact('peer-${i.toString().padLeft(2, '0')}-1234567890'),
      );
      contactRepo.seed(contacts);

      final stopwatch = Stopwatch()..start();
      final sent = await retryIncompleteKeyExchanges(
        contactRepo: contactRepo,
        identityRepo: identityRepo,
        p2pService: p2pService,
        bridge: bridge,
      );
      stopwatch.stop();

      expect(sent, 10);
      // 9 jitter gaps at minimum 100ms each = 900ms minimum
      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(900));
    });

    test('resume and reconnect share one repair burst inside cooldown', () {
      fakeAsync((fake) {
        final offlineP2PService = FakeP2PService(
          initialState: NodeState.stopped,
        );
        var runCount = 0;
        final coordinator = KeyExchangeRetryCoordinator(
          performRetry: () async {
            runCount += 1;
            return 1;
          },
          cooldown: const Duration(seconds: 10),
          now: () => DateTime.utc(2026, 4, 12, 18).add(fake.elapsed),
        );
        final retrier = KeyExchangeRetrier(
          p2pService: offlineP2PService,
          contactRepo: contactRepo,
          identityRepo: identityRepo,
          bridge: bridge,
          coordinator: coordinator,
        );
        retrier.start();

        handleAppResumed(
          bridge: bridge,
          p2pService: offlineP2PService,
          contactRepo: contactRepo,
          identityRepo: identityRepo,
          retryIncompleteKeyExchangesFn: () =>
              retrier.retryNow(trigger: 'app_resumed'),
        );
        fake.flushMicrotasks();
        expect(runCount, 1);

        offlineP2PService.emitState(
          const NodeState(
            isStarted: true,
            peerId: 'my-peer-id-1234567890',
            circuitAddresses: ['/p2p-circuit/addr1'],
          ),
        );
        fake.flushMicrotasks();
        fake.elapse(const Duration(seconds: 5));
        fake.flushMicrotasks();

        expect(runCount, 1);
        retrier.dispose();
        offlineP2PService.dispose();
      });
    });
  });
}
