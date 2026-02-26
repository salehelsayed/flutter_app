import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// MockBridge that returns ok + valid for payload.verify by default.
class _MockBridge extends Bridge {
  Map<String, dynamic> nextResponse = {'ok': true, 'valid': true};
  bool shouldThrow = false;

  @override
  bool get isInitialized => true;
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> checkHealth() async => true;
  @override
  Future<void> reinitialize() async {}
  @override
  void dispose() {}

  @override
  Future<String> send(String message) async {
    if (shouldThrow) throw Exception('bridge error');
    return jsonEncode(nextResponse);
  }
}

class _FakeContactRequestRepository implements ContactRequestRepository {
  ContactRequestModel? existingRequest;
  ContactRequestModel? lastAdded;

  @override
  Future<ContactRequestModel?> getRequest(String peerId) async =>
      (existingRequest?.peerId == peerId) ? existingRequest : null;

  @override
  Future<void> addRequest(ContactRequestModel request) async {
    lastAdded = request;
  }

  @override
  Future<bool> requestExists(String peerId) async =>
      existingRequest?.peerId == peerId;

  // Not needed
  @override
  Future<void> deleteRequest(String peerId) async {}
  @override
  Future<List<ContactRequestModel>> getPendingRequests() async => [];
  @override
  Future<void> updateStatus(
      String peerId, ContactRequestStatus status) async {}
}

class _FakeContactRepository implements ContactRepository {
  final Map<String, ContactModel> _contacts = {};

  /// Seed a contact for testing.
  void addTestContact(ContactModel contact) {
    _contacts[contact.peerId] = contact;
  }

  @override
  Future<bool> contactExists(String peerId) async =>
      _contacts.containsKey(peerId);

  @override
  Future<void> addContact(ContactModel contact) async {
    _contacts[contact.peerId] = contact;
  }

  @override
  Future<ContactModel?> getContact(String peerId) async => _contacts[peerId];

  @override
  Future<void> archiveContact(String peerId) async {}
  @override
  Future<void> blockContact(String peerId) async {}
  @override
  Future<void> deleteContact(String peerId) async {}
  @override
  Future<List<ContactModel>> getActiveContacts() async => [];
  @override
  Future<List<ContactModel>> getAllContacts() async => [];
  @override
  Future<List<ContactModel>> getArchivedContacts() async => [];
  @override
  Future<int> getContactCount() async => 0;
  @override
  Future<void> unarchiveContact(String peerId) async {}
  @override
  Future<void> unblockContact(String peerId) async {}
}

// ---------------------------------------------------------------------------
// Helper to build a valid contact request ChatMessage
// ---------------------------------------------------------------------------
const _testPeerId = '12D3KooWSenderPeerId1234567890';
const _testPublicKey = 'dGVzdFB1YmxpY0tleUJhc2U2NA==';
const _testOwnPeerId = '12D3KooWOwnPeerId12345678901';

ChatMessage _makeContactRequestMessage({
  String peerId = _testPeerId,
  String publicKey = _testPublicKey,
  String? from,
  String? mlkem,
}) {
  final payload = SplayTreeMap<String, dynamic>.from({
    if (mlkem != null) 'mlkem': mlkem,
    'ns': peerId,
    'pk': publicKey,
    'rv': '/dns4/rendezvous.example.com/tcp/4001/p2p/$peerId',
    'ts': '2024-06-15T12:00:00Z',
    'un': 'TestUser',
  });
  final sig = 'fakeSigBase64ForTesting';

  final envelope = jsonEncode({
    'type': 'contact_request',
    'payload': {
      ...payload,
      'sig': sig,
    },
  });

  return ChatMessage(
    from: from ?? peerId,
    to: _testOwnPeerId,
    content: envelope,
    timestamp: DateTime.now().toUtc().toIso8601String(),
    isIncoming: true,
  );
}

ChatMessage _makeRegularMessage({String content = 'Hello, world!'}) {
  return ChatMessage(
    from: '12D3KooWSomePeerId_regular12',
    to: _testOwnPeerId,
    content: content,
    timestamp: DateTime.now().toUtc().toIso8601String(),
    isIncoming: true,
  );
}

void main() {
  late StreamController<ChatMessage> streamController;
  late _MockBridge bridge;
  late _FakeContactRequestRepository requestRepo;
  late _FakeContactRepository contactRepo;
  late ContactRequestListener listener;

  setUp(() {
    flowEventLoggingEnabled = false;
    streamController = StreamController<ChatMessage>.broadcast();
    bridge = _MockBridge();
    requestRepo = _FakeContactRequestRepository();
    contactRepo = _FakeContactRepository();

    listener = ContactRequestListener(
      contactRequestStream: streamController.stream,
      requestRepo: requestRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      getOwnPeerId: () => _testOwnPeerId,
    );
  });

  tearDown(() {
    listener.dispose();
    streamController.close();
  });

  // ---------------------------------------------------------------------------
  // start/stop lifecycle
  // ---------------------------------------------------------------------------
  group('start/stop lifecycle', () {
    test('start begins listening to stream', () async {
      listener.start();

      final requests = <ContactRequestModel>[];
      listener.requestStream.listen(requests.add);

      streamController.add(_makeContactRequestMessage());

      // Give async handlers time to complete
      await Future.delayed(const Duration(milliseconds: 100));

      expect(requests.length, equals(1));
    });

    test('start is idempotent (calling twice does not duplicate subscriptions)',
        () async {
      listener.start();
      listener.start(); // second call should be no-op

      final requests = <ContactRequestModel>[];
      listener.requestStream.listen(requests.add);

      streamController.add(_makeContactRequestMessage());
      await Future.delayed(const Duration(milliseconds: 100));

      // Should only get 1, not 2
      expect(requests.length, equals(1));
    });

    test('stop cancels subscription', () async {
      listener.start();

      final requests = <ContactRequestModel>[];
      listener.requestStream.listen(requests.add);

      listener.stop();

      streamController.add(_makeContactRequestMessage());
      await Future.delayed(const Duration(milliseconds: 100));

      expect(requests, isEmpty);
    });

    test('stop is safe to call before start', () {
      // Should not throw
      listener.stop();
    });

    test('dispose stops and closes requestStream', () async {
      listener.start();
      listener.dispose();

      // The request stream should be closed
      bool streamDone = false;
      listener.requestStream.listen(
        (_) {},
        onDone: () => streamDone = true,
      );
      await Future.delayed(const Duration(milliseconds: 50));
      expect(streamDone, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // message processing
  // ---------------------------------------------------------------------------
  group('message processing', () {
    test('emits ContactRequestModel on requestStream for valid contact request',
        () async {
      listener.start();

      final requests = <ContactRequestModel>[];
      listener.requestStream.listen(requests.add);

      streamController.add(_makeContactRequestMessage());
      await Future.delayed(const Duration(milliseconds: 100));

      expect(requests.length, equals(1));
      expect(requests.first.peerId, equals(_testPeerId));
      expect(requests.first.username, equals('TestUser'));
    });

    test('does not emit for regular chat messages (non-JSON)', () async {
      listener.start();

      final requests = <ContactRequestModel>[];
      listener.requestStream.listen(requests.add);

      streamController.add(_makeRegularMessage(content: 'not json at all'));
      await Future.delayed(const Duration(milliseconds: 100));

      expect(requests, isEmpty);
    });

    test('does not emit for non-contact_request type messages', () async {
      listener.start();

      final requests = <ContactRequestModel>[];
      listener.requestStream.listen(requests.add);

      final chatEnvelope = jsonEncode({
        'type': 'chat_message',
        'version': '1',
        'payload': {'text': 'Hello'},
      });
      streamController.add(_makeRegularMessage(content: chatEnvelope));
      await Future.delayed(const Duration(milliseconds: 100));

      expect(requests, isEmpty);
    });

    test('does not emit for already-existing contacts', () async {
      contactRepo.addTestContact(ContactModel(
        peerId: _testPeerId,
        publicKey: _testPublicKey,
        rendezvous: '/addr',
        username: 'TestUser',
        signature: 'sig',
        scannedAt: '2024-01-01T00:00:00Z',
        mlKemPublicKey: 'existingKey',
      ));
      listener.start();

      final requests = <ContactRequestModel>[];
      listener.requestStream.listen(requests.add);

      streamController.add(_makeContactRequestMessage());
      await Future.delayed(const Duration(milliseconds: 100));

      expect(requests, isEmpty);
    });

    test('does not emit for duplicate pending requests', () async {
      requestRepo.existingRequest = ContactRequestModel(
        peerId: _testPeerId,
        publicKey: _testPublicKey,
        rendezvous: '/addr',
        username: 'TestUser',
        signature: 'sig',
        receivedAt: '2024-01-01T00:00:00Z',
        status: ContactRequestStatus.pending,
      );
      listener.start();

      final requests = <ContactRequestModel>[];
      listener.requestStream.listen(requests.add);

      streamController.add(_makeContactRequestMessage());
      await Future.delayed(const Duration(milliseconds: 100));

      expect(requests, isEmpty);
    });

    test('does not emit when message is from own peerId', () async {
      listener.start();

      final requests = <ContactRequestModel>[];
      listener.requestStream.listen(requests.add);

      // Build a message where the claimed peerId = own peerId
      streamController.add(_makeContactRequestMessage(
        peerId: _testOwnPeerId,
        from: _testOwnPeerId,
      ));
      await Future.delayed(const Duration(milliseconds: 100));

      expect(requests, isEmpty);
    });

    test('swallows exception from handleIncomingMessage without crashing',
        () async {
      // Make bridge throw to cause exception inside handler
      bridge.shouldThrow = true;
      listener.start();

      final requests = <ContactRequestModel>[];
      listener.requestStream.listen(requests.add);

      // Should not crash
      streamController.add(_makeContactRequestMessage());
      await Future.delayed(const Duration(milliseconds: 100));

      expect(requests, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // contactKeyUpdatedStream
  // ---------------------------------------------------------------------------
  group('contactKeyUpdatedStream', () {
    test('emits updated contact when existing contact has null ML-KEM key',
        () async {
      // Seed a contact WITHOUT ML-KEM key
      contactRepo.addTestContact(ContactModel(
        peerId: _testPeerId,
        publicKey: _testPublicKey,
        rendezvous: '/addr',
        username: 'TestUser',
        signature: 'sig',
        scannedAt: '2024-01-01T00:00:00Z',
        mlKemPublicKey: null,
      ));
      listener.start();

      final updates = <ContactModel>[];
      listener.contactKeyUpdatedStream.listen(updates.add);

      final requests = <ContactRequestModel>[];
      listener.requestStream.listen(requests.add);

      // Send a contact_request with mlkem key from the existing contact
      streamController.add(
        _makeContactRequestMessage(mlkem: 'newMlKemPublicKey'),
      );
      await Future.delayed(const Duration(milliseconds: 100));

      // contactKeyUpdatedStream should emit
      expect(updates.length, equals(1));
      expect(updates.first.peerId, equals(_testPeerId));
      expect(updates.first.mlKemPublicKey, equals('newMlKemPublicKey'));

      // requestStream should NOT emit (this is not a new request)
      expect(requests, isEmpty);
    });

    test('does not emit when existing contact already has ML-KEM key',
        () async {
      // Seed a contact WITH an existing ML-KEM key
      contactRepo.addTestContact(ContactModel(
        peerId: _testPeerId,
        publicKey: _testPublicKey,
        rendezvous: '/addr',
        username: 'TestUser',
        signature: 'sig',
        scannedAt: '2024-01-01T00:00:00Z',
        mlKemPublicKey: 'existingKey',
      ));
      listener.start();

      final updates = <ContactModel>[];
      listener.contactKeyUpdatedStream.listen(updates.add);

      streamController.add(
        _makeContactRequestMessage(mlkem: 'differentKey'),
      );
      await Future.delayed(const Duration(milliseconds: 100));

      // Should NOT emit — existing key is never overwritten
      expect(updates, isEmpty);
    });

    test('does not emit when payload has no mlkem field', () async {
      // Seed a contact WITHOUT ML-KEM key
      contactRepo.addTestContact(ContactModel(
        peerId: _testPeerId,
        publicKey: _testPublicKey,
        rendezvous: '/addr',
        username: 'TestUser',
        signature: 'sig',
        scannedAt: '2024-01-01T00:00:00Z',
        mlKemPublicKey: null,
      ));
      listener.start();

      final updates = <ContactModel>[];
      listener.contactKeyUpdatedStream.listen(updates.add);

      // No mlkem in payload
      streamController.add(_makeContactRequestMessage());
      await Future.delayed(const Duration(milliseconds: 100));

      expect(updates, isEmpty);
    });

    test('emitted contact preserves all fields', () async {
      contactRepo.addTestContact(ContactModel(
        peerId: _testPeerId,
        publicKey: _testPublicKey,
        rendezvous: '/addr',
        username: 'TestUser',
        signature: 'sig',
        scannedAt: '2024-01-01T00:00:00Z',
        mlKemPublicKey: null,
      ));
      listener.start();

      final updates = <ContactModel>[];
      listener.contactKeyUpdatedStream.listen(updates.add);

      streamController.add(
        _makeContactRequestMessage(mlkem: 'newKey'),
      );
      await Future.delayed(const Duration(milliseconds: 100));

      expect(updates.length, equals(1));
      final contact = updates.first;
      // ML-KEM key updated
      expect(contact.mlKemPublicKey, equals('newKey'));
      // Other fields preserved
      expect(contact.peerId, equals(_testPeerId));
      expect(contact.publicKey, equals(_testPublicKey));
      expect(contact.username, equals('TestUser'));
    });

    test('dispose closes contactKeyUpdatedStream', () async {
      listener.start();
      listener.dispose();

      bool streamDone = false;
      listener.contactKeyUpdatedStream.listen(
        (_) {},
        onDone: () => streamDone = true,
      );
      await Future.delayed(const Duration(milliseconds: 50));
      expect(streamDone, isTrue);
    });
  });
}
