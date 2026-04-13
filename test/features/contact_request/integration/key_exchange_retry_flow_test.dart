import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contact_request/application/retry_incomplete_key_exchanges_use_case.dart';
import 'package:flutter_app/features/contact_request/application/send_contact_request_use_case.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import 'dart:convert';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../../../features/identity/domain/repositories/fake_identity_repository.dart';

IdentityModel _makeIdentity({String? mlKemPublicKey = 'own-mlkem-pk'}) {
  return IdentityModel(
    peerId: 'alice-peer-id-1234567890',
    publicKey: 'alice-public-key',
    privateKey: 'alice-private-key',
    mnemonic12:
        'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
    mlKemPublicKey: mlKemPublicKey,
    mlKemSecretKey: mlKemPublicKey != null ? 'alice-mlkem-sk' : null,
    createdAt: '2024-01-01T00:00:00Z',
    updatedAt: '2024-01-01T00:00:00Z',
  );
}

ContactModel _makeContact(
  String peerId, {
  String? mlKemPublicKey,
  bool isBlocked = false,
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
        peerId: 'alice-peer-id-1234567890',
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

  group('Key exchange retry flow', () {
    test('full offline→online retry sends to contact with null key', () async {
      // Alice has Bob as contact with null ML-KEM key
      contactRepo.seed([_makeContact('bob-peer-id-1234567890')]);

      // Simulate coming back online — call retry directly
      final sent = await retryIncompleteKeyExchanges(
        contactRepo: contactRepo,
        identityRepo: identityRepo,
        p2pService: p2pService,
        bridge: bridge,
      );

      expect(sent, 1);
      // sendContactRequest signs the payload + encrypts → stores in inbox
      expect(bridge.sendCallCount, 2); // payload.sign + contactrequest.encrypt
      expect(p2pService.storeInInboxCallCount, 1);
    });

    test('no retry when all keys present', () async {
      contactRepo.seed([
        _makeContact('bob-peer-id-1234567890', mlKemPublicKey: 'bob-key'),
        _makeContact('carol-peer-id-1234567890', mlKemPublicKey: 'carol-key'),
      ]);

      final sent = await retryIncompleteKeyExchanges(
        contactRepo: contactRepo,
        identityRepo: identityRepo,
        p2pService: p2pService,
        bridge: bridge,
      );

      expect(sent, 0);
      expect(bridge.sendCallCount, 0);
      expect(p2pService.storeInInboxCallCount, 0);
    });

    test('blocked contact skipped, active contact retried', () async {
      contactRepo.seed([
        _makeContact('bob-peer-id-1234567890', isBlocked: true),
        _makeContact('carol-peer-id-1234567890'),
      ]);

      final sent = await retryIncompleteKeyExchanges(
        contactRepo: contactRepo,
        identityRepo: identityRepo,
        p2pService: p2pService,
        bridge: bridge,
      );

      // Only Carol should get the retry
      expect(sent, 1);
      // payload.sign + contactrequest.encrypt
      expect(bridge.sendCallCount, 2);
    });

    test('multiple contacts all get retry sequentially', () async {
      contactRepo.seed([
        _makeContact('bob-peer-id-1234567890'),
        _makeContact('carol-peer-id-1234567890'),
        _makeContact('dave-peer-id-1234567890'),
      ]);

      final sent = await retryIncompleteKeyExchanges(
        contactRepo: contactRepo,
        identityRepo: identityRepo,
        p2pService: p2pService,
        bridge: bridge,
      );

      expect(sent, 3);
      // Each contact gets two bridge calls (payload.sign + contactrequest.encrypt)
      expect(bridge.sendCallCount, 6);
      // Each contact stores in inbox (discoverPeer returns null)
      expect(p2pService.storeInInboxCallCount, 3);
    });

    test(
      'command sequence: payload.sign → contactrequest.encrypt per contact',
      () async {
        contactRepo.seed([
          _makeContact('bob-peer-id-1234567890'),
          _makeContact('carol-peer-id-1234567890'),
        ]);

        await retryIncompleteKeyExchanges(
          contactRepo: contactRepo,
          identityRepo: identityRepo,
          p2pService: p2pService,
          bridge: bridge,
        );

        // 2 contacts × 2 commands each = 4 commands
        expect(bridge.commandLog.length, equals(4));
        // First contact: sign then encrypt
        expect(bridge.commandLog[0], equals('payload.sign'));
        expect(bridge.commandLog[1], equals('contactrequest.encrypt'));
        // Second contact: sign then encrypt
        expect(bridge.commandLog[2], equals('payload.sign'));
        expect(bridge.commandLog[3], equals('contactrequest.encrypt'));
      },
    );

    test('stored inbox message is v2 encrypted envelope', () async {
      contactRepo.seed([_makeContact('bob-peer-id-1234567890')]);

      await retryIncompleteKeyExchanges(
        contactRepo: contactRepo,
        identityRepo: identityRepo,
        p2pService: p2pService,
        bridge: bridge,
      );

      expect(p2pService.lastStoreInInboxMessage, isNotNull);
      final envelope =
          jsonDecode(p2pService.lastStoreInInboxMessage!)
              as Map<String, dynamic>;
      expect(envelope['type'], equals('contact_request'));
      expect(envelope['version'], equals('2'));
      expect(
        envelope['intent'],
        equals(ContactRequestSendIntent.keyExchangeRetry.wireValue),
      );
      expect(envelope['msgId'], isA<String>());
      expect(envelope['ts'], isA<String>());
      expect(envelope['encrypted'], isA<Map>());
      expect(envelope['encrypted']['ephemeralPublicKey'], isA<String>());
      expect(envelope['encrypted']['ciphertext'], isA<String>());
      expect(envelope['encrypted']['nonce'], isA<String>());
      // No plaintext payload at top level
      expect(envelope.containsKey('payload'), isFalse);
    });
  });
}
