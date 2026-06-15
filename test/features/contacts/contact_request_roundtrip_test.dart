/// End-to-end coverage test (audit gap: contact_request_roundtrip).
///
/// Stitches the two halves that the existing suite only proves separately:
///   * `contact_request/integration/contact_request_flow_test.dart` proves the
///     ML-KEM key arrives via accept/reciprocate.
///   * `conversation/integration/two_user_message_exchange_test.dart` proves a
///     v2-encrypted 1:1 message round-trips with a key already in place.
///
/// Neither proves the KEY FROM THE EXCHANGE is the thing that unlocks the
/// later encrypted message. This test does exactly that:
///
///   1. Alice scans Bob's QR (contact WITHOUT an ML-KEM key — QR carries none).
///   2. With no key yet, Alice's v2 send fails closed (`encryptionRequired`)
///      — the negative control proving the key is load-bearing.
///   3. Alice sends Bob a contact request (carrying Alice's ML-KEM key).
///   4. Bob receives it -> pending -> accept+reciprocate. The reciprocal
///      request carries Bob's ML-KEM key back to Alice.
///   5. Alice receives the reciprocal -> her Bob contact gains Bob's ML-KEM
///      key (HandleMessageResult.contactKeyUpdated).
///   6. Alice now sends a v2-encrypted 1:1 message using the freshly-exchanged
///      key -> Bob's ChatMessageListener decrypts it and stores the plaintext.
///
/// Crypto: real ML-KEM needs the native bridge (not host-runnable), so this
/// reuses `PassthroughCryptoBridge` — the same v2 encrypt/decrypt fake the
/// other host crypto integration tests use — seeded with the contact-request
/// crypto responses. The wire path (v2 envelope build -> network -> decrypt)
/// is fully exercised; only the AEAD primitive is faked.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/features/contact_request/application/accept_and_reciprocate_use_case.dart';
import 'package:flutter_app/features/contact_request/application/accept_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/application/send_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';

import '../../core/bridge/fake_bridge.dart';
import '../identity/domain/repositories/fake_identity_repository.dart';
import '../../shared/fakes/fake_p2p_network.dart';
import '../../shared/fakes/fake_p2p_service_integration.dart';
import '../../shared/fakes/in_memory_contact_repository.dart';
import '../../shared/fakes/in_memory_contact_request_repository.dart';
import '../../shared/fakes/in_memory_message_repository.dart';

/// Extends [PassthroughCryptoBridge] (which already passthrough-handles the v2
/// chat `message.encrypt`/`message.decrypt`) so the v2 CONTACT-REQUEST crypto
/// also round-trips with key fidelity: `contactrequest.encrypt` echoes the
/// signed-payload plaintext into `ciphertext`, and `contactrequest.decrypt`
/// echoes it back as `plaintext`. Real ML-KEM lives in the native bridge and
/// is not host-runnable; this fakes only the AEAD primitive while exercising
/// the full envelope build -> network -> decrypt wire path for BOTH the
/// contact-request exchange and the subsequent encrypted chat message.
class _RoundtripCryptoBridge extends PassthroughCryptoBridge {
  _RoundtripCryptoBridge(this.tag);

  final String tag;

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    final payload = parsed['payload'] as Map<String, dynamic>?;

    if (cmd == 'contactrequest.encrypt') {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);
      return jsonEncode({
        'ok': true,
        'ephemeralPublicKey': 'eph-$tag',
        'ciphertext': payload!['plaintext'],
        'nonce': 'cr-nonce-$tag',
      });
    }

    if (cmd == 'contactrequest.decrypt') {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);
      return jsonEncode({'ok': true, 'plaintext': payload!['ciphertext']});
    }

    return super.send(message);
  }
}

/// One participant: full contact-request + chat stack wired to a shared network.
class _RoundtripUser {
  _RoundtripUser({
    required this.peerId,
    required this.username,
    required this.mlKemPublicKey,
    required FakeP2PNetwork network,
  }) : p2p = FakeP2PService(peerId: peerId, network: network),
       bridge = _buildBridge(peerId),
       requestRepo = InMemoryContactRequestRepository(),
       contactRepo = InMemoryContactRepository(),
       messageRepo = InMemoryMessageRepository(),
       identityRepo = FakeIdentityRepository() {
    identityRepo.seed(
      IdentityModel(
        peerId: peerId,
        publicKey: 'pk-$peerId',
        privateKey: 'sk-$peerId',
        mnemonic12:
            'abandon abandon abandon abandon abandon abandon '
            'abandon abandon abandon abandon abandon about',
        mlKemPublicKey: mlKemPublicKey,
        createdAt: '2024-01-01T00:00:00Z',
        updatedAt: '2024-01-01T00:00:00Z',
        username: username,
      ),
    );

    router = IncomingMessageRouter(p2pService: p2p);
    contactRequestListener = ContactRequestListener(
      contactRequestStream: router.contactRequestStream,
      requestRepo: requestRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      getOwnPeerId: () => peerId,
      // Required so the listener can decrypt the v2 reciprocal request.
      getOwnPrivateKey: () async => 'sk-$peerId',
    );
    chatListener = ChatMessageListener(
      chatMessageStream: router.chatMessageStream,
      messageRepo: messageRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      getOwnMlKemSecretKey: () async => 'mlkem-secret-$peerId',
    );
  }

  final String peerId;
  final String username;
  final String mlKemPublicKey;
  final FakeP2PService p2p;
  final _RoundtripCryptoBridge bridge;
  final InMemoryContactRequestRepository requestRepo;
  final InMemoryContactRepository contactRepo;
  final InMemoryMessageRepository messageRepo;
  final FakeIdentityRepository identityRepo;
  late final IncomingMessageRouter router;
  late final ContactRequestListener contactRequestListener;
  late final ChatMessageListener chatListener;

  /// The roundtrip bridge passthrough-handles the v2 contact-request AND chat
  /// crypto. It still needs static `payload.sign`/`payload.verify` responses
  /// (FakeBridge defaults already cover those, but seed explicitly for clarity).
  static _RoundtripCryptoBridge _buildBridge(String peerId) {
    final b = _RoundtripCryptoBridge(peerId);
    b.responses.addAll({
      'payload.verify': {'ok': true, 'valid': true},
      'payload.sign': {'ok': true, 'signature': 'sig-$peerId'},
    });
    return b;
  }

  void start() {
    router.start();
    contactRequestListener.start();
    chatListener.start();
  }

  /// Simulates a QR scan: stores the peer as a contact but WITHOUT an ML-KEM
  /// key (a scanned QR carries no `mlkem` field — see flow test case 2i).
  void scanContactWithoutMlKem(_RoundtripUser other) {
    contactRepo.addTestContact(
      ContactModel(
        peerId: other.peerId,
        publicKey: 'pk-${other.peerId}',
        rendezvous: '/dns4/relay/tcp/443/p2p/relay',
        username: other.username,
        signature: 'sig-${other.peerId}',
        scannedAt: '2026-01-01T00:00:00Z',
        mlKemPublicKey: null,
      ),
    );
  }

  void dispose() {
    chatListener.dispose();
    contactRequestListener.dispose();
    router.dispose();
    p2p.dispose();
  }
}

void main() {
  const alicePeerId = '12D3KooWAliceRoundtrip0000000001';
  const bobPeerId = '12D3KooWBobRoundtripxx0000000002';

  late FakeP2PNetwork network;
  late _RoundtripUser alice;
  late _RoundtripUser bob;

  setUp(() {
    network = FakeP2PNetwork();
    alice = _RoundtripUser(
      peerId: alicePeerId,
      username: 'Alice',
      mlKemPublicKey: 'mlkem-pub-$alicePeerId',
      network: network,
    );
    bob = _RoundtripUser(
      peerId: bobPeerId,
      username: 'Bob',
      mlKemPublicKey: 'mlkem-pub-$bobPeerId',
      network: network,
    );
    alice.start();
    bob.start();
  });

  tearDown(() {
    alice.dispose();
    bob.dispose();
  });

  test(
    'contact-request roundtrip exchanges ML-KEM key, then a v2 message decrypts',
    () async {
      // --- Step 1: Alice scans Bob's QR -> contact WITHOUT an ML-KEM key. ---
      alice.scanContactWithoutMlKem(bob);
      final bobContactBefore = await alice.contactRepo.getContact(bobPeerId);
      expect(
        bobContactBefore!.mlKemPublicKey,
        isNull,
        reason: 'scanned QR carries no ML-KEM key',
      );

      // --- Step 2 (negative control): without the key, a v2 send fails
      // closed. This proves the exchanged key is load-bearing for the
      // encrypted-message path that step 6 will exercise. ---
      final (preExchangeResult, preExchangeMessage) = await sendChatMessage(
        p2pService: alice.p2p,
        messageRepo: alice.messageRepo,
        targetPeerId: bobPeerId,
        text: 'Should not be sendable yet',
        senderPeerId: alicePeerId,
        senderUsername: alice.username,
        bridge: alice.bridge,
        recipientMlKemPublicKey: bobContactBefore.mlKemPublicKey,
      );
      expect(preExchangeResult, SendChatMessageResult.encryptionRequired);
      expect(preExchangeMessage, isNull);

      // --- Step 3: Alice sends Bob a contact request (carries Alice's key). ---
      final bobPendingFuture = bob.contactRequestListener.requestStream.first;
      final sendResult = await sendContactRequest(
        p2pService: alice.p2p,
        identityRepo: alice.identityRepo,
        bridge: alice.bridge,
        targetPeerId: bobPeerId,
      );
      expect(sendResult, SendContactRequestResult.success);

      // --- Step 4: Bob receives it -> pending -> accept + reciprocate. ---
      final ContactRequestModel bobPending = await bobPendingFuture.timeout(
        const Duration(seconds: 2),
        onTimeout: () =>
            throw StateError('Bob never received the contact request'),
      );
      expect(bobPending.peerId, alicePeerId);
      expect(bobPending.status, ContactRequestStatus.pending);

      // Alice should learn Bob's ML-KEM key from his reciprocal request.
      final aliceKeyUpdatedFuture =
          alice.contactRequestListener.contactKeyUpdatedStream.first;

      final acceptResult = await acceptAndReciprocateContactRequest(
        requestRepo: bob.requestRepo,
        contactRepo: bob.contactRepo,
        peerId: alicePeerId,
        p2pService: bob.p2p,
        identityRepo: bob.identityRepo,
        bridge: bob.bridge,
      );
      expect(acceptResult, AcceptContactRequestResult.success);

      // Bob now has Alice as a contact carrying Alice's ML-KEM key.
      final aliceContactOnBob = await bob.contactRepo.getContact(alicePeerId);
      expect(aliceContactOnBob, isNotNull);
      expect(aliceContactOnBob!.mlKemPublicKey, alice.mlKemPublicKey);

      // --- Step 5: Alice receives the reciprocal -> her Bob contact gains
      // Bob's ML-KEM key (contactKeyUpdated path). ---
      final ContactModel aliceUpdatedBobContact = await aliceKeyUpdatedFuture
          .timeout(
            const Duration(seconds: 2),
            onTimeout: () => throw StateError(
              'Alice never received Bob reciprocal ML-KEM key',
            ),
          );
      expect(aliceUpdatedBobContact.peerId, bobPeerId);
      expect(aliceUpdatedBobContact.mlKemPublicKey, bob.mlKemPublicKey);

      final bobContactAfter = await alice.contactRepo.getContact(bobPeerId);
      expect(
        bobContactAfter!.mlKemPublicKey,
        bob.mlKemPublicKey,
        reason: 'exchange must persist Bob ML-KEM key on Alice contact',
      );

      // --- Step 6: Alice sends a v2-encrypted 1:1 message using the
      // freshly-exchanged key -> Bob decrypts it. ---
      final bobIncomingFuture = bob.chatListener.incomingMessageStream.first;

      final (chatResult, sentMessage) = await sendChatMessage(
        p2pService: alice.p2p,
        messageRepo: alice.messageRepo,
        targetPeerId: bobPeerId,
        text: 'Encrypted hello after the key exchange',
        senderPeerId: alicePeerId,
        senderUsername: alice.username,
        bridge: alice.bridge,
        recipientMlKemPublicKey: bobContactAfter.mlKemPublicKey,
      );

      expect(
        chatResult,
        SendChatMessageResult.success,
        reason: 'with the exchanged key in place the v2 send must succeed',
      );
      expect(sentMessage, isNotNull);
      expect(sentMessage!.text, 'Encrypted hello after the key exchange');
      expect(sentMessage.isIncoming, isFalse);

      // Alice's outbound wire envelope must be the v2 encrypted form.
      expect(
        alice.bridge.commandLog,
        contains('message.encrypt'),
        reason: 'send must take the v2 encrypted envelope path',
      );

      // Bob's listener decrypts the envelope and surfaces the plaintext.
      final ConversationMessage bobReceived = await bobIncomingFuture.timeout(
        const Duration(seconds: 2),
        onTimeout: () =>
            throw StateError('Bob never decrypted the encrypted message'),
      );
      expect(bobReceived.text, 'Encrypted hello after the key exchange');
      expect(bobReceived.isIncoming, isTrue);
      expect(bobReceived.senderPeerId, alicePeerId);
      expect(bobReceived.contactPeerId, alicePeerId);

      // Bob must have actually run the v2 decrypt primitive.
      expect(
        bob.bridge.commandLog,
        contains('message.decrypt'),
        reason: 'receiver must decrypt the v2 envelope',
      );

      // Persisted plaintext on Bob's side.
      final bobStored = await bob.messageRepo.getMessagesForContact(
        alicePeerId,
      );
      expect(
        bobStored.map((m) => m.text).toList(),
        const <String>['Encrypted hello after the key exchange'],
      );
    },
  );
}
