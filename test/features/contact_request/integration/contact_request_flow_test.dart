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
import 'package:flutter_app/features/contact_request/application/send_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../features/identity/domain/repositories/fake_identity_repository.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_contact_request_repository.dart';
import '../../../shared/fakes/in_memory_message_repository.dart';

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

  final payload = {...unsignedPayload, 'sig': 'fake-sig-$peerId'};

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
    bridge = FakeBridge(
      initialResponses: {
        'payload.verify': {'ok': true, 'valid': true},
        'payload.sign': {'ok': true, 'signature': 'fakeSig'},
        'contactrequest.encrypt': {
          'ok': true,
          'ephemeralPublicKey': 'ephPub',
          'ciphertext': 'ct',
          'nonce': 'nonce',
        },
      },
    );
    requestRepo = InMemoryContactRequestRepository();
    contactRepo = InMemoryContactRepository();
    identityRepo = FakeIdentityRepository()
      ..seed(
        IdentityModel(
          peerId: ownPeerId,
          publicKey: 'ownPubKey',
          privateKey: 'ownPrivKey',
          mnemonic12:
              'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
          mlKemPublicKey: 'ownMlKemPub',
          createdAt: '2024-01-01T00:00:00Z',
          updatedAt: '2024-01-01T00:00:00Z',
        ),
      );
    network = FakeP2PNetwork();
    p2pService = FakeP2PService(peerId: ownPeerId, network: network);
  });

  group('Contact request flow', () {
    test(
      '2a. Full accept: incoming -> pending -> accept -> contact appears',
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

        // Wait for fire-and-forget reciprocal send to complete
        await Future.delayed(const Duration(milliseconds: 200));

        // Verify reciprocal send used v2 encryption path
        expect(bridge.commandLog, contains('contactrequest.encrypt'));

        // Verify contact created
        final contact = await contactRepo.getContact(bobPeerId);
        expect(contact, isNotNull);
        expect(contact!.peerId, bobPeerId);
        expect(contact.username, 'Bob');

        // Verify request status updated
        final updatedRequest = await requestRepo.getRequest(bobPeerId);
        expect(updatedRequest!.status, ContactRequestStatus.accepted);
      },
    );

    test(
      '2b. Full decline: incoming -> pending -> decline -> no contact',
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
      },
    );

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
        buildContactRequestMessage(fromPeerId: bobPeerId, username: 'Bob'),
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

    test(
      '2i. Reciprocal contact_request updates ML-KEM key on existing contact',
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
      },
    );

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

    test(
      '2k. declined request can be replayed later and accepted on rescan',
      () async {
        final firstMessage = buildContactRequestMessage(
          fromPeerId: bobPeerId,
          username: 'Bob',
        );

        final (firstResult, firstRequest, _) = await handleIncomingMessage(
          message: firstMessage,
          bridge: bridge,
          requestRepo: requestRepo,
          contactRepo: contactRepo,
          ownPeerId: ownPeerId,
        );

        expect(firstResult, HandleMessageResult.contactRequest);
        expect(firstRequest, isNotNull);
        expect(firstRequest!.status, ContactRequestStatus.pending);

        final declineResult = await declineContactRequest(
          requestRepo: requestRepo,
          peerId: bobPeerId,
        );
        expect(declineResult, DeclineContactRequestResult.success);
        expect(
          (await requestRepo.getRequest(bobPeerId))?.status,
          ContactRequestStatus.declined,
        );

        final secondMessage = buildContactRequestMessage(
          fromPeerId: bobPeerId,
          username: 'Bob',
          mlKem: 'bobMlKemPublicKey',
        );

        final (secondResult, secondRequest, _) = await handleIncomingMessage(
          message: secondMessage,
          bridge: bridge,
          requestRepo: requestRepo,
          contactRepo: contactRepo,
          ownPeerId: ownPeerId,
        );

        expect(secondResult, HandleMessageResult.contactRequest);
        expect(secondRequest, isNotNull);
        expect(secondRequest!.status, ContactRequestStatus.pending);
        expect(
          requestRepo.count,
          1,
          reason: 'rescan should replace the record',
        );

        final acceptResult = await acceptAndReciprocateContactRequest(
          requestRepo: requestRepo,
          contactRepo: contactRepo,
          peerId: bobPeerId,
          p2pService: p2pService,
          identityRepo: identityRepo,
          bridge: bridge,
        );

        expect(acceptResult, AcceptContactRequestResult.success);
        await Future<void>.delayed(const Duration(milliseconds: 200));

        final acceptedContact = await contactRepo.getContact(bobPeerId);
        expect(acceptedContact, isNotNull);
        expect(acceptedContact!.username, 'Bob');
        expect(acceptedContact.mlKemPublicKey, 'bobMlKemPublicKey');
        expect(
          (await requestRepo.getRequest(bobPeerId))?.status,
          ContactRequestStatus.accepted,
        );
        expect(
          bridge.commandLog,
          contains('contactrequest.encrypt'),
          reason: 'accept should still trigger the reciprocal bootstrap send',
        );
      },
    );

    test(
      '2l. mutual scan race leaves both sides with one accepted contact',
      () async {
        const alicePeerId = ownPeerId;
        const carolPeerId = '12D3KooWCarolPeerIdxx00000000002';

        final sharedNetwork = FakeP2PNetwork();
        final aliceBridge = FakeBridge(
          initialResponses: {
            'payload.verify': {'ok': true, 'valid': true},
            'payload.sign': {'ok': true, 'signature': 'alice-sig'},
            'contactrequest.encrypt': {
              'ok': true,
              'ephemeralPublicKey': 'alice-eph',
              'ciphertext': 'alice-ct',
              'nonce': 'alice-nonce',
            },
          },
        );
        final carolBridge = FakeBridge(
          initialResponses: {
            'payload.verify': {'ok': true, 'valid': true},
            'payload.sign': {'ok': true, 'signature': 'carol-sig'},
            'contactrequest.encrypt': {
              'ok': true,
              'ephemeralPublicKey': 'carol-eph',
              'ciphertext': 'carol-ct',
              'nonce': 'carol-nonce',
            },
          },
        );
        final aliceRequestRepo = InMemoryContactRequestRepository();
        final aliceContactRepo = InMemoryContactRepository();
        final aliceIdentityRepo = FakeIdentityRepository()
          ..seed(
            IdentityModel(
              peerId: alicePeerId,
              publicKey: 'pk-$alicePeerId',
              privateKey: 'sk-$alicePeerId',
              mnemonic12:
                  'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
              mlKemPublicKey: 'mlkem-$alicePeerId',
              createdAt: '2024-01-01T00:00:00Z',
              updatedAt: '2024-01-01T00:00:00Z',
            ),
          );
        final aliceP2p = FakeP2PService(
          peerId: alicePeerId,
          network: sharedNetwork,
        );

        final carolRequestRepo = InMemoryContactRequestRepository();
        final carolContactRepo = InMemoryContactRepository();
        final carolIdentityRepo = FakeIdentityRepository()
          ..seed(
            IdentityModel(
              peerId: carolPeerId,
              publicKey: 'pk-$carolPeerId',
              privateKey: 'sk-$carolPeerId',
              mnemonic12:
                  'legal winner thank year wave sausage worth useful legal winner thank yellow',
              mlKemPublicKey: 'mlkem-$carolPeerId',
              createdAt: '2024-01-01T00:00:00Z',
              updatedAt: '2024-01-01T00:00:00Z',
            ),
          );
        final carolP2p = FakeP2PService(
          peerId: carolPeerId,
          network: sharedNetwork,
        );

        final incomingResults = await Future.wait([
          handleIncomingMessage(
            message: buildContactRequestMessage(
              fromPeerId: carolPeerId,
              username: 'Carol',
              mlKem: 'mlkem-$carolPeerId',
            ),
            bridge: aliceBridge,
            requestRepo: aliceRequestRepo,
            contactRepo: aliceContactRepo,
            ownPeerId: alicePeerId,
          ),
          handleIncomingMessage(
            message: buildContactRequestMessage(
              fromPeerId: alicePeerId,
              username: 'Alice',
              mlKem: 'mlkem-$alicePeerId',
            ),
            bridge: carolBridge,
            requestRepo: carolRequestRepo,
            contactRepo: carolContactRepo,
            ownPeerId: carolPeerId,
          ),
        ]);

        expect(
          incomingResults.map((result) => result.$1),
          everyElement(HandleMessageResult.contactRequest),
        );
        expect(aliceRequestRepo.count, 1);
        expect(carolRequestRepo.count, 1);

        final acceptResults = await Future.wait([
          acceptAndReciprocateContactRequest(
            requestRepo: aliceRequestRepo,
            contactRepo: aliceContactRepo,
            peerId: carolPeerId,
            p2pService: aliceP2p,
            identityRepo: aliceIdentityRepo,
            bridge: aliceBridge,
          ),
          acceptAndReciprocateContactRequest(
            requestRepo: carolRequestRepo,
            contactRepo: carolContactRepo,
            peerId: alicePeerId,
            p2pService: carolP2p,
            identityRepo: carolIdentityRepo,
            bridge: carolBridge,
          ),
        ]);

        expect(acceptResults, everyElement(AcceptContactRequestResult.success));
        await Future<void>.delayed(const Duration(milliseconds: 200));

        final aliceContact = await aliceContactRepo.getContact(carolPeerId);
        final carolContact = await carolContactRepo.getContact(alicePeerId);
        expect(aliceContact, isNotNull);
        expect(carolContact, isNotNull);
        expect(aliceContact!.mlKemPublicKey, 'mlkem-$carolPeerId');
        expect(carolContact!.mlKemPublicKey, 'mlkem-$alicePeerId');
        expect(
          (await aliceRequestRepo.getRequest(carolPeerId))?.status,
          ContactRequestStatus.accepted,
        );
        expect(
          (await carolRequestRepo.getRequest(alicePeerId))?.status,
          ContactRequestStatus.accepted,
        );
        expect(aliceBridge.commandLog, contains('contactrequest.encrypt'));
        expect(carolBridge.commandLog, contains('contactrequest.encrypt'));

        aliceP2p.dispose();
        carolP2p.dispose();
      },
    );

    test(
      '2m. offline bootstrap send replays from inbox into one pending request',
      () async {
        const carolPeerId = '12D3KooWCarolPeerIdxx00000000002';

        final aliceNetwork = FakeP2PNetwork();
        final aliceP2p = FakeP2PService(
          peerId: ownPeerId,
          network: aliceNetwork,
        );
        final carolP2p = FakeP2PService(
          peerId: carolPeerId,
          network: aliceNetwork,
        );
        carolP2p.setOnline(false);

        final carolRequestRepo = InMemoryContactRequestRepository();
        final carolContactRepo = InMemoryContactRepository();
        final carolIdentityRepo = FakeIdentityRepository()
          ..seed(
            IdentityModel(
              peerId: carolPeerId,
              publicKey: 'pk-$carolPeerId',
              privateKey: 'sk-$carolPeerId',
              mnemonic12:
                  'legal winner thank year wave sausage worth useful legal winner thank yellow',
              mlKemPublicKey: 'mlkem-$carolPeerId',
              createdAt: '2024-01-01T00:00:00Z',
              updatedAt: '2024-01-01T00:00:00Z',
            ),
          );
        final carolBridge = FakeBridge(
          initialResponses: {
            'payload.verify': {'ok': true, 'valid': true},
            'payload.sign': {'ok': true, 'signature': 'carol-sig'},
            'contactrequest.encrypt': {
              'ok': true,
              'ephemeralPublicKey': 'carol-eph',
              'ciphertext': 'carol-ct',
              'nonce': 'carol-nonce',
            },
          },
        );
        final carolRouter = IncomingMessageRouter(p2pService: carolP2p);
        final carolListener = ContactRequestListener(
          contactRequestStream: carolRouter.contactRequestStream,
          requestRepo: carolRequestRepo,
          contactRepo: carolContactRepo,
          bridge: carolBridge,
          getOwnPeerId: () => carolPeerId,
        );

        carolRouter.start();
        carolListener.start();
        final replayedRequestFuture = carolListener.requestStream.first;

        final sendResult = await sendContactRequest(
          p2pService: aliceP2p,
          identityRepo: identityRepo,
          bridge: bridge,
          targetPeerId: carolPeerId,
        );

        expect(sendResult, SendContactRequestResult.success);
        expect(
          aliceNetwork.inboxCount(carolPeerId),
          1,
          reason: 'offline scan should park the request in the inbox first',
        );

        carolP2p.setOnline(true);
        final drained = await carolP2p.drainOfflineInboxCount();
        expect(drained, 1);

        final replayedRequest = await replayedRequestFuture.timeout(
          const Duration(seconds: 2),
          onTimeout: () => throw StateError(
            'Offline inbox replay never surfaced the contact request',
          ),
        );

        expect(replayedRequest.peerId, ownPeerId);
        expect(replayedRequest.status, ContactRequestStatus.pending);
        expect(
          (await carolRequestRepo.getRequest(ownPeerId))?.status,
          ContactRequestStatus.pending,
        );

        final acceptResult = await acceptAndReciprocateContactRequest(
          requestRepo: carolRequestRepo,
          contactRepo: carolContactRepo,
          peerId: ownPeerId,
          p2pService: carolP2p,
          identityRepo: carolIdentityRepo,
          bridge: carolBridge,
        );

        expect(acceptResult, AcceptContactRequestResult.success);
        await Future<void>.delayed(const Duration(milliseconds: 200));

        final acceptedContact = await carolContactRepo.getContact(ownPeerId);
        final ownIdentity = await identityRepo.loadIdentity();
        expect(acceptedContact, isNotNull);
        expect(acceptedContact!.username, ownIdentity!.username);
        expect(
          (await carolRequestRepo.getRequest(ownPeerId))?.status,
          ContactRequestStatus.accepted,
        );

        carolListener.dispose();
        carolRouter.dispose();
        aliceP2p.dispose();
        carolP2p.dispose();
      },
    );

    test(
      '2n. accepting a pending request while a chat waits offline replays exactly one delivered message',
      () async {
        const carolPeerId = '12D3KooWCarolPeerIdxx00000000002';

        final sharedNetwork = FakeP2PNetwork();
        final aliceP2p = FakeP2PService(
          peerId: ownPeerId,
          network: sharedNetwork,
        );
        final carolP2p = FakeP2PService(
          peerId: carolPeerId,
          network: sharedNetwork,
        );
        final aliceMessageRepo = InMemoryMessageRepository();
        final carolMessageRepo = InMemoryMessageRepository();
        final carolRequestRepo = InMemoryContactRequestRepository();
        final carolContactRepo = InMemoryContactRepository();
        final carolIdentityRepo = FakeIdentityRepository()
          ..seed(
            IdentityModel(
              peerId: carolPeerId,
              publicKey: 'pk-$carolPeerId',
              privateKey: 'sk-$carolPeerId',
              mnemonic12:
                  'legal winner thank year wave sausage worth useful legal winner thank yellow',
              mlKemPublicKey: 'mlkem-$carolPeerId',
              createdAt: '2024-01-01T00:00:00Z',
              updatedAt: '2024-01-01T00:00:00Z',
            ),
          );
        final carolBridge = FakeBridge(
          initialResponses: {
            'payload.verify': {'ok': true, 'valid': true},
            'payload.sign': {'ok': true, 'signature': 'carol-sig'},
            'contactrequest.encrypt': {
              'ok': true,
              'ephemeralPublicKey': 'carol-eph',
              'ciphertext': 'carol-ct',
              'nonce': 'carol-nonce',
            },
          },
        );
        final carolRouter = IncomingMessageRouter(p2pService: carolP2p);
        final carolListener = ContactRequestListener(
          contactRequestStream: carolRouter.contactRequestStream,
          requestRepo: carolRequestRepo,
          contactRepo: carolContactRepo,
          bridge: carolBridge,
          getOwnPeerId: () => carolPeerId,
        );
        final carolChatListener = ChatMessageListener(
          chatMessageStream: carolRouter.chatMessageStream,
          messageRepo: carolMessageRepo,
          contactRepo: carolContactRepo,
        );

        carolP2p.setOnline(false);
        carolRouter.start();
        carolListener.start();
        carolChatListener.start();
        final replayedRequestFuture = carolListener.requestStream.first;

        final sendRequestResult = await sendContactRequest(
          p2pService: aliceP2p,
          identityRepo: identityRepo,
          bridge: bridge,
          targetPeerId: carolPeerId,
        );

        expect(sendRequestResult, SendContactRequestResult.success);
        expect(sharedNetwork.inboxCount(carolPeerId), 1);

        carolP2p.setOnline(true);
        expect(await carolP2p.drainOfflineInboxCount(), 1);

        final replayedRequest = await replayedRequestFuture.timeout(
          const Duration(seconds: 2),
          onTimeout: () => throw StateError(
            'Pending request never surfaced before the queued chat step',
          ),
        );
        expect(replayedRequest.peerId, ownPeerId);
        expect(
          (await carolRequestRepo.getRequest(ownPeerId))?.status,
          ContactRequestStatus.pending,
        );

        carolP2p.setOnline(false);
        final ownIdentity = await identityRepo.loadIdentity();
        final (sendResult, _) = await sendChatMessage(
          p2pService: aliceP2p,
          messageRepo: aliceMessageRepo,
          targetPeerId: carolPeerId,
          text: 'Queued after pending request',
          senderPeerId: ownPeerId,
          senderUsername: ownIdentity!.username,
        );

        expect(sendResult, SendChatMessageResult.success);
        expect(
          sharedNetwork.inboxCount(carolPeerId),
          1,
          reason: 'chat should remain queued while Carol is offline',
        );

        final acceptResult = await acceptAndReciprocateContactRequest(
          requestRepo: carolRequestRepo,
          contactRepo: carolContactRepo,
          peerId: ownPeerId,
          p2pService: carolP2p,
          identityRepo: carolIdentityRepo,
          bridge: carolBridge,
        );

        expect(acceptResult, AcceptContactRequestResult.success);
        expect(
          (await carolRequestRepo.getRequest(ownPeerId))?.status,
          ContactRequestStatus.accepted,
        );
        expect(await carolContactRepo.getContact(ownPeerId), isNotNull);

        carolP2p.setOnline(true);
        final replayedMessageFuture =
            carolChatListener.incomingMessageStream.first;
        expect(await carolP2p.drainOfflineInboxCount(), 1);

        final replayedMessage = await replayedMessageFuture.timeout(
          const Duration(seconds: 2),
          onTimeout: () => throw StateError(
            'Queued chat never replayed after accepting the request',
          ),
        );
        expect(replayedMessage.text, 'Queued after pending request');
        expect(replayedMessage.contactPeerId, ownPeerId);

        final storedMessages = await carolMessageRepo.getMessagesForContact(
          ownPeerId,
        );
        expect(storedMessages.map((message) => message.text).toList(), <String>[
          'Queued after pending request',
        ]);

        carolChatListener.dispose();
        carolListener.dispose();
        carolRouter.dispose();
        aliceP2p.dispose();
        carolP2p.dispose();
      },
    );

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
      await requestRepo.updateStatus(bobPeerId, ContactRequestStatus.declined);

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
