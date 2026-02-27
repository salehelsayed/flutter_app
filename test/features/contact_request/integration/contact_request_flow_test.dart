/// Integration test: Contact request accept/decline flow.
///
/// Verifies end-to-end: incoming message -> parse -> verify sig -> store ->
/// accept/decline -> contact created or request declined.

import 'dart:collection';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/features/contact_request/application/accept_and_reciprocate_use_case.dart';
import 'package:flutter_app/features/contact_request/application/accept_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/application/decline_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/application/handle_incoming_message_use_case.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../features/identity/domain/repositories/fake_identity_repository.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_contact_request_repository.dart';

/// Constructs a valid contact_request envelope JSON string.
String buildContactRequestEnvelope({
  required String peerId,
  String? publicKey,
  String? username,
  String? mlKem,
}) {
  final pk = publicKey ?? 'pk-$peerId';
  final un = username ?? 'User-$peerId';

  // Build unsigned payload (sorted keys for deterministic signature)
  final unsignedPayload = SplayTreeMap<String, dynamic>.from({
    if (mlKem != null) 'mlkem': mlKem,
    'ns': peerId,
    'pk': pk,
    'rv': '/dns4/relay/tcp/443/p2p/relay',
    'ts': DateTime.now().toUtc().toIso8601String(),
    'un': un,
  });

  final payload = {
    ...unsignedPayload,
    'sig': 'fake-sig-$peerId',
  };

  return jsonEncode({
    'type': 'contact_request',
    'version': '1',
    'payload': payload,
  });
}

ChatMessage buildContactRequestMessage({
  required String fromPeerId,
  String? username,
  String? mlKem,
}) {
  return ChatMessage(
    from: fromPeerId,
    to: 'own-peer',
    content: buildContactRequestEnvelope(
      peerId: fromPeerId,
      username: username,
      mlKem: mlKem,
    ),
    timestamp: DateTime.now().toUtc().toIso8601String(),
    isIncoming: true,
  );
}

void main() {
  const ownPeerId = '12D3KooWOwnPeerIdxxx00000000000';
  const bobPeerId = '12D3KooWBobPeerIdxxx00000000001';

  late FakeBridge bridge;
  late InMemoryContactRequestRepository requestRepo;
  late InMemoryContactRepository contactRepo;
  late FakeIdentityRepository identityRepo;
  late FakeP2PNetwork network;
  late FakeP2PService p2pService;

  setUp(() {
    bridge = FakeBridge(initialResponses: {
      'payload.verify': {'ok': true, 'valid': true},
      'payload.sign': {'ok': true, 'signature': 'fakeSig'},
    });
    requestRepo = InMemoryContactRequestRepository();
    contactRepo = InMemoryContactRepository();
    identityRepo = FakeIdentityRepository()
      ..seed(IdentityModel(
        peerId: ownPeerId,
        publicKey: 'ownPubKey',
        privateKey: 'ownPrivKey',
        mnemonic12: 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
        mlKemPublicKey: 'ownMlKemPub',
        createdAt: '2024-01-01T00:00:00Z',
        updatedAt: '2024-01-01T00:00:00Z',
      ));
    network = FakeP2PNetwork();
    p2pService = FakeP2PService(peerId: ownPeerId, network: network);
  });

  group('Contact request flow', () {
    test('2a. Full accept: incoming -> pending -> accept -> contact appears',
        () async {
      final message = buildContactRequestMessage(
        fromPeerId: bobPeerId,
        username: 'Bob',
      );

      final (result, request, _) = await handleIncomingMessage(
        message: message,
        bridge: bridge,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        ownPeerId: ownPeerId,
      );

      expect(result, HandleMessageResult.contactRequest);
      expect(request, isNotNull);
      expect(request!.peerId, bobPeerId);
      expect(request.username, 'Bob');
      expect(request.status, ContactRequestStatus.pending);

      // Verify stored
      final stored = await requestRepo.getRequest(bobPeerId);
      expect(stored, isNotNull);
      expect(stored!.status, ContactRequestStatus.pending);

      // Accept (with reciprocal send)
      final acceptResult = await acceptAndReciprocateContactRequest(
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        peerId: bobPeerId,
        p2pService: p2pService,
        identityRepo: identityRepo,
        bridge: bridge,
      );

      expect(acceptResult, AcceptContactRequestResult.success);

      // Verify contact created
      final contact = await contactRepo.getContact(bobPeerId);
      expect(contact, isNotNull);
      expect(contact!.peerId, bobPeerId);
      expect(contact.username, 'Bob');

      // Verify request status updated
      final updatedRequest = await requestRepo.getRequest(bobPeerId);
      expect(updatedRequest!.status, ContactRequestStatus.accepted);
    });

    test('2b. Full decline: incoming -> pending -> decline -> no contact',
        () async {
      final message = buildContactRequestMessage(
        fromPeerId: bobPeerId,
        username: 'Bob',
      );

      await handleIncomingMessage(
        message: message,
        bridge: bridge,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        ownPeerId: ownPeerId,
      );

      final declineResult = await declineContactRequest(
        requestRepo: requestRepo,
        peerId: bobPeerId,
      );

      expect(declineResult, DeclineContactRequestResult.success);

      // Request status == declined
      final request = await requestRepo.getRequest(bobPeerId);
      expect(request!.status, ContactRequestStatus.declined);

      // No contact created
      final contact = await contactRepo.getContact(bobPeerId);
      expect(contact, isNull);
    });

    test('2c. Duplicate request rejection', () async {
      final message = buildContactRequestMessage(fromPeerId: bobPeerId);

      // First request
      final (r1, _, _) = await handleIncomingMessage(
        message: message,
        bridge: bridge,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        ownPeerId: ownPeerId,
      );
      expect(r1, HandleMessageResult.contactRequest);

      // Second request from same peer
      final (r2, _, _) = await handleIncomingMessage(
        message: message,
        bridge: bridge,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        ownPeerId: ownPeerId,
      );
      expect(r2, HandleMessageResult.duplicateRequest);

      // Only one request stored
      expect(requestRepo.count, 1);
    });

    test('2d. Already-contact rejection', () async {
      // Seed Bob as existing contact
      contactRepo.addTestContact(
        ContactModel(
          peerId: bobPeerId,
          publicKey: 'pk-bob',
          rendezvous: '/rv/bob',
          username: 'Bob',
          signature: 'sig-bob',
          scannedAt: '2026-01-01T00:00:00Z',
        ),
      );

      final message = buildContactRequestMessage(fromPeerId: bobPeerId);
      final (result, _, _) = await handleIncomingMessage(
        message: message,
        bridge: bridge,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        ownPeerId: ownPeerId,
      );

      expect(result, HandleMessageResult.alreadyContact);
      expect(requestRepo.count, 0);
    });

    test('2e. Invalid signature rejection', () async {
      bridge.responses['payload.verify'] = {'ok': true, 'valid': false};

      final message = buildContactRequestMessage(fromPeerId: bobPeerId);
      final (result, _, _) = await handleIncomingMessage(
        message: message,
        bridge: bridge,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        ownPeerId: ownPeerId,
      );

      expect(result, HandleMessageResult.invalidMessage);
    });

    test('2f. Self-request rejection', () async {
      final message = buildContactRequestMessage(fromPeerId: ownPeerId);
      final (result, _, _) = await handleIncomingMessage(
        message: message,
        bridge: bridge,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        ownPeerId: ownPeerId,
      );

      expect(result, HandleMessageResult.invalidMessage);
    });

    test('2g. Stream-based flow via ContactRequestListener', () async {
      final network = FakeP2PNetwork();
      final p2pService = FakeP2PService(peerId: ownPeerId, network: network);

      final router = IncomingMessageRouter(p2pService: p2pService);
      router.start();

      final listener = ContactRequestListener(
        contactRequestStream: router.contactRequestStream,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        getOwnPeerId: () => ownPeerId,
      );
      listener.start();

      final requestFuture = listener.requestStream.first;

      // Inject a contact request via the P2P service
      p2pService.injectIncomingMessage(
        buildContactRequestMessage(
          fromPeerId: bobPeerId,
          username: 'Bob',
        ),
      );

      final receivedRequest = await requestFuture.timeout(
        const Duration(seconds: 2),
        onTimeout: () =>
            throw StateError('Listener never emitted ContactRequestModel'),
      );

      expect(receivedRequest.peerId, bobPeerId);
      expect(receivedRequest.username, 'Bob');
      expect(receivedRequest.status, ContactRequestStatus.pending);

      listener.dispose();
      router.dispose();
      p2pService.dispose();
    });

    test('2i. Reciprocal contact_request updates ML-KEM key on existing contact',
        () async {
      // Seed Bob as existing contact WITHOUT ML-KEM key (simulates
      // User-A who scanned Bob's QR — QR has no mlkem field).
      contactRepo.addTestContact(
        ContactModel(
          peerId: bobPeerId,
          publicKey: 'pk-bob',
          rendezvous: '/dns4/relay/tcp/443/p2p/relay',
          username: 'Bob',
          signature: 'sig-bob',
          scannedAt: '2026-01-01T00:00:00Z',
          mlKemPublicKey: null,
        ),
      );

      // Bob sends a reciprocal contact_request carrying his ML-KEM key.
      final message = buildContactRequestMessage(
        fromPeerId: bobPeerId,
        username: 'Bob',
        mlKem: 'bobMlKemPublicKey',
      );

      final (result, request, _) = await handleIncomingMessage(
        message: message,
        bridge: bridge,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        ownPeerId: ownPeerId,
      );

      expect(result, HandleMessageResult.contactKeyUpdated);
      expect(request, isNull);

      // Verify the contact now has Bob's ML-KEM key.
      final updatedContact = await contactRepo.getContact(bobPeerId);
      expect(updatedContact, isNotNull);
      expect(updatedContact!.mlKemPublicKey, 'bobMlKemPublicKey');

      // Other fields preserved.
      expect(updatedContact.username, 'Bob');
      expect(updatedContact.publicKey, 'pk-bob');

      // No contact request was stored (it's an existing contact).
      expect(requestRepo.count, 0);
    });

    test('2j. Stream-based key update via ContactRequestListener', () async {
      // Full chain: P2P message → router → listener → contactKeyUpdatedStream
      final network = FakeP2PNetwork();
      final p2pService = FakeP2PService(peerId: ownPeerId, network: network);

      // Seed Bob as contact without ML-KEM key
      contactRepo.addTestContact(
        ContactModel(
          peerId: bobPeerId,
          publicKey: 'pk-bob',
          rendezvous: '/dns4/relay/tcp/443/p2p/relay',
          username: 'Bob',
          signature: 'sig-bob',
          scannedAt: '2026-01-01T00:00:00Z',
          mlKemPublicKey: null,
        ),
      );

      final router = IncomingMessageRouter(p2pService: p2pService);
      router.start();

      final listener = ContactRequestListener(
        contactRequestStream: router.contactRequestStream,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        getOwnPeerId: () => ownPeerId,
      );
      listener.start();

      final updateFuture = listener.contactKeyUpdatedStream.first;

      // Inject reciprocal contact request with Bob's ML-KEM key
      p2pService.injectIncomingMessage(
        buildContactRequestMessage(
          fromPeerId: bobPeerId,
          username: 'Bob',
          mlKem: 'bobMlKemPublicKey',
        ),
      );

      final updatedContact = await updateFuture.timeout(
        const Duration(seconds: 2),
        onTimeout: () =>
            throw StateError('Listener never emitted ContactModel'),
      );

      // Stream emits the updated contact with the ML-KEM key
      expect(updatedContact.peerId, bobPeerId);
      expect(updatedContact.mlKemPublicKey, 'bobMlKemPublicKey');
      expect(updatedContact.username, 'Bob');

      // DB also updated
      final dbContact = await contactRepo.getContact(bobPeerId);
      expect(dbContact!.mlKemPublicKey, 'bobMlKemPublicKey');

      // No contact request stored
      expect(requestRepo.count, 0);

      listener.dispose();
      router.dispose();
      p2pService.dispose();
    });

    test('2h. Accept non-pending request returns notPending', () async {
      // Handle the request
      final message = buildContactRequestMessage(fromPeerId: bobPeerId);
      await handleIncomingMessage(
        message: message,
        bridge: bridge,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        ownPeerId: ownPeerId,
      );

      // Decline it first
      await requestRepo.updateStatus(
          bobPeerId, ContactRequestStatus.declined);

      // Try to accept the declined request
      final result = await acceptContactRequest(
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        peerId: bobPeerId,
      );

      expect(result, AcceptContactRequestResult.notPending);
    });
  });
}
