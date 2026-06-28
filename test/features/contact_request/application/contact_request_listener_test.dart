import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contact_request/application/accept_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/application/contact_auto_add_rate_limiter.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/application/handle_incoming_message_use_case.dart';
import 'package:flutter_app/features/contact_request/application/recover_intro_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart';

import '../../../shared/fakes/in_memory_contact_request_repository.dart';
import '../../../shared/fakes/in_memory_introduction_repository.dart';
import '../../../shared/fakes/in_memory_message_repository.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// MockBridge that returns ok + valid for payload.verify by default,
/// and handles contactrequest.decrypt for v2 tests.
class _MockBridge extends Bridge {
  Map<String, dynamic> nextResponse = {'ok': true, 'valid': true};
  Map<String, dynamic>? decryptResponse;
  bool shouldThrow = false;

  /// 171: every decoded request sent through this bridge, in order — lets
  /// confirm-path tests assert a `message:confirm` was issued with the right
  /// nonce/ok. [onSend] is an ordering hook (e.g. record relative to an
  /// auto-accept call).
  final List<Map<String, dynamic>> sentRequests = [];
  void Function(Map<String, dynamic> request)? onSend;

  List<Map<String, dynamic>> get confirmRequests =>
      sentRequests.where((r) => r['cmd'] == 'message:confirm').toList();

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
    final req = jsonDecode(message) as Map<String, dynamic>;
    sentRequests.add(req);
    onSend?.call(req);
    if (req['cmd'] == 'contactrequest.decrypt' && decryptResponse != null) {
      return jsonEncode(decryptResponse!);
    }
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
    existingRequest = request;
    lastAdded = request;
  }

  @override
  Future<bool> requestExists(String peerId) async =>
      existingRequest?.peerId == peerId;

  // Not needed
  @override
  Future<void> deleteRequest(String peerId) async {
    if (existingRequest?.peerId == peerId) {
      existingRequest = null;
    }
  }
  @override
  Future<List<ContactRequestModel>> getPendingRequests() async => [];
  @override
  Future<void> updateStatus(String peerId, ContactRequestStatus status) async {}
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
  Future<int> getContactCount() async => _contacts.length;
  @override
  Future<void> unarchiveContact(String peerId) async {}
  @override
  Future<void> unblockContact(String peerId) async {}
  @override
  Future<void> dismissIntroBanner(String peerId) async {}
  @override
  Future<void> setIntrosSentAt(String peerId, String timestamp) async {}
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
    'payload': {...payload, 'sig': sig},
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

IntroductionModel _pendingIntroFor(String ownPeerId, String otherPeerId) {
  return IntroductionModel(
    id: 'intro-listener-recovery',
    introducerId: 'peer-introducer',
    recipientId: ownPeerId,
    introducedId: otherPeerId,
    recipientStatus: IntroductionStatus.accepted,
    introducedStatus: IntroductionStatus.pending,
    status: IntroductionOverallStatus.pending,
    createdAt: '2026-04-03T12:00:00.000Z',
    introducerUsername: 'Noor',
    recipientUsername: 'Receiver',
    introducedUsername: 'TestUser',
    introducedPublicKey: _testPublicKey,
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

    test(
      'start is idempotent (calling twice does not duplicate subscriptions)',
      () async {
        listener.start();
        listener.start(); // second call should be no-op

        final requests = <ContactRequestModel>[];
        listener.requestStream.listen(requests.add);

        streamController.add(_makeContactRequestMessage());
        await Future.delayed(const Duration(milliseconds: 100));

        // Should only get 1, not 2
        expect(requests.length, equals(1));
      },
    );

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
      listener.requestStream.listen((_) {}, onDone: () => streamDone = true);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(streamDone, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // message processing
  // ---------------------------------------------------------------------------
  group('message processing', () {
    test(
      'emits ContactRequestModel on requestStream for valid contact request',
      () async {
        listener.start();

        final requests = <ContactRequestModel>[];
        listener.requestStream.listen(requests.add);

        streamController.add(_makeContactRequestMessage());
        await Future.delayed(const Duration(milliseconds: 100));

        expect(requests.length, equals(1));
        expect(requests.first.peerId, equals(_testPeerId));
        expect(requests.first.username, equals('TestUser'));
      },
    );

    test('prefetches avatar for valid contact request', () async {
      String? capturedPeerId;
      String? capturedAvatarVersion;

      listener = ContactRequestListener(
        contactRequestStream: streamController.stream,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        getOwnPeerId: () => _testOwnPeerId,
        downloadProfilePictureFn:
            ({
              required bridge,
              required contactRepo,
              required ownerPeerId,
              required avatarVersion,
            }) async {
              capturedPeerId = ownerPeerId;
              capturedAvatarVersion = avatarVersion;
              return null;
            },
      );
      listener.start();

      final requests = <ContactRequestModel>[];
      listener.requestStream.listen(requests.add);

      streamController.add(_makeContactRequestMessage());
      await Future.delayed(const Duration(milliseconds: 100));

      expect(requests.length, equals(1));
      expect(capturedPeerId, equals(_testPeerId));
      expect(capturedAvatarVersion, equals('initial'));
    });

    test('avatar prefetch failure does not block request emission', () async {
      var prefetchCalls = 0;

      listener = ContactRequestListener(
        contactRequestStream: streamController.stream,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        getOwnPeerId: () => _testOwnPeerId,
        downloadProfilePictureFn:
            ({
              required bridge,
              required contactRepo,
              required ownerPeerId,
              required avatarVersion,
            }) async {
              prefetchCalls++;
              throw Exception('profile download failed');
            },
      );
      listener.start();

      final requests = <ContactRequestModel>[];
      listener.requestStream.listen(requests.add);

      streamController.add(_makeContactRequestMessage());
      await Future.delayed(const Duration(milliseconds: 100));

      expect(prefetchCalls, equals(1));
      expect(requests.length, equals(1));
      expect(requests.first.peerId, equals(_testPeerId));
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
      var prefetchCalls = 0;
      contactRepo.addTestContact(
        ContactModel(
          peerId: _testPeerId,
          publicKey: _testPublicKey,
          rendezvous: '/addr',
          username: 'TestUser',
          signature: 'sig',
          scannedAt: '2024-01-01T00:00:00Z',
          mlKemPublicKey: 'existingKey',
        ),
      );
      listener = ContactRequestListener(
        contactRequestStream: streamController.stream,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        getOwnPeerId: () => _testOwnPeerId,
        downloadProfilePictureFn:
            ({
              required bridge,
              required contactRepo,
              required ownerPeerId,
              required avatarVersion,
            }) async {
              prefetchCalls++;
              return null;
            },
      );
      listener.start();

      final requests = <ContactRequestModel>[];
      listener.requestStream.listen(requests.add);

      streamController.add(_makeContactRequestMessage());
      await Future.delayed(const Duration(milliseconds: 100));

      expect(requests, isEmpty);
      expect(prefetchCalls, equals(0));
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
      streamController.add(
        _makeContactRequestMessage(
          peerId: _testOwnPeerId,
          from: _testOwnPeerId,
        ),
      );
      await Future.delayed(const Duration(milliseconds: 100));

      expect(requests, isEmpty);
    });

    test(
      'swallows exception from handleIncomingMessage without crashing',
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
      },
    );
  });

  // ---------------------------------------------------------------------------
  // contactKeyUpdatedStream
  // ---------------------------------------------------------------------------
  group('contactKeyUpdatedStream', () {
    test(
      'emits updated contact when existing contact has null ML-KEM key',
      () async {
        // Seed a contact WITHOUT ML-KEM key
        contactRepo.addTestContact(
          ContactModel(
            peerId: _testPeerId,
            publicKey: _testPublicKey,
            rendezvous: '/addr',
            username: 'TestUser',
            signature: 'sig',
            scannedAt: '2024-01-01T00:00:00Z',
            mlKemPublicKey: null,
          ),
        );
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
      },
    );

    test(
      'emits when an existing contact key rotates via a newer signed payload',
      () async {
        // P0-B contract: a verified contact_request carrying a DIFFERENT
        // key with a newer signed ts rotates the stored key and broadcasts.
        contactRepo.addTestContact(
          ContactModel(
            peerId: _testPeerId,
            publicKey: _testPublicKey,
            rendezvous: '/addr',
            username: 'TestUser',
            signature: 'sig',
            scannedAt: '2024-01-01T00:00:00Z',
            mlKemPublicKey: 'existingKey',
          ),
        );
        listener.start();

        final updates = <ContactModel>[];
        listener.contactKeyUpdatedStream.listen(updates.add);

        streamController.add(_makeContactRequestMessage(mlkem: 'differentKey'));
        await Future.delayed(const Duration(milliseconds: 100));

        expect(updates, hasLength(1));
        expect(updates.single.mlKemPublicKey, 'differentKey');
      },
    );

    test(
      'does not emit when the key change is a stale replay (anti-rollback)',
      () async {
        contactRepo.addTestContact(
          ContactModel(
            peerId: _testPeerId,
            publicKey: _testPublicKey,
            rendezvous: '/addr',
            username: 'TestUser',
            signature: 'sig',
            scannedAt: '2024-01-01T00:00:00Z',
            mlKemPublicKey: 'existingKey',
            // Last accepted key update is far in the future relative to any
            // payload ts the fixture generates — the change must be ignored.
            mlKemKeyUpdatedTs: '2099-01-01T00:00:00Z',
          ),
        );
        listener.start();

        final updates = <ContactModel>[];
        listener.contactKeyUpdatedStream.listen(updates.add);

        streamController.add(_makeContactRequestMessage(mlkem: 'staleKey'));
        await Future.delayed(const Duration(milliseconds: 100));

        expect(updates, isEmpty);
      },
    );

    test('does not emit when payload has no mlkem field', () async {
      // Seed a contact WITHOUT ML-KEM key
      contactRepo.addTestContact(
        ContactModel(
          peerId: _testPeerId,
          publicKey: _testPublicKey,
          rendezvous: '/addr',
          username: 'TestUser',
          signature: 'sig',
          scannedAt: '2024-01-01T00:00:00Z',
          mlKemPublicKey: null,
        ),
      );
      listener.start();

      final updates = <ContactModel>[];
      listener.contactKeyUpdatedStream.listen(updates.add);

      // No mlkem in payload
      streamController.add(_makeContactRequestMessage());
      await Future.delayed(const Duration(milliseconds: 100));

      expect(updates, isEmpty);
    });

    test('emitted contact preserves all fields', () async {
      contactRepo.addTestContact(
        ContactModel(
          peerId: _testPeerId,
          publicKey: _testPublicKey,
          rendezvous: '/addr',
          username: 'TestUser',
          signature: 'sig',
          scannedAt: '2024-01-01T00:00:00Z',
          mlKemPublicKey: null,
        ),
      );
      listener.start();

      final updates = <ContactModel>[];
      listener.contactKeyUpdatedStream.listen(updates.add);

      streamController.add(_makeContactRequestMessage(mlkem: 'newKey'));
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

  // ---------------------------------------------------------------------------
  // v2 encrypted contact request
  // ---------------------------------------------------------------------------
  group('v2 encrypted', () {
    ChatMessage _makeV2Message({
      String peerId = _testPeerId,
      String publicKey = _testPublicKey,
      String? from,
      String? mlkem,
      String? msgId,
    }) {
      final payload = SplayTreeMap<String, dynamic>.from({
        if (mlkem != null) 'mlkem': mlkem,
        'ns': peerId,
        'pk': publicKey,
        'rv': '/dns4/rendezvous.example.com/tcp/4001/p2p/$peerId',
        'sig': 'fakeSigBase64ForTesting',
        'ts': '2024-06-15T12:00:00Z',
        'un': 'TestUser',
      });

      final id = msgId ?? 'v2-msg-${DateTime.now().microsecondsSinceEpoch}';
      final ts = DateTime.now().toUtc().toIso8601String();

      final envelope = jsonEncode({
        'type': 'contact_request',
        'version': '2',
        'msgId': id,
        'ts': ts,
        'encrypted': {
          'ephemeralPublicKey': 'ephPubBase64',
          'ciphertext': 'ctBase64',
          'nonce': 'nonceBase64',
        },
      });

      // Set up bridge decrypt to return the payload
      bridge.decryptResponse = {'ok': true, 'plaintext': jsonEncode(payload)};

      return ChatMessage(
        from: from ?? peerId,
        to: _testOwnPeerId,
        content: envelope,
        timestamp: DateTime.now().toUtc().toIso8601String(),
        isIncoming: true,
      );
    }

    test('emits ContactRequestModel for valid v2', () async {
      final v2Listener = ContactRequestListener(
        contactRequestStream: streamController.stream,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        getOwnPeerId: () => _testOwnPeerId,
        getOwnPrivateKey: () async => 'ownPrivKeyBase64',
      );
      v2Listener.start();

      final requests = <ContactRequestModel>[];
      v2Listener.requestStream.listen(requests.add);

      streamController.add(_makeV2Message());
      await Future.delayed(const Duration(milliseconds: 100));

      expect(requests.length, equals(1));
      expect(requests.first.peerId, equals(_testPeerId));

      v2Listener.dispose();
    });

    test('does not emit for v2 decryption failure', () async {
      bridge.decryptResponse = {
        'ok': false,
        'errorCode': 'INTERNAL_ERROR',
        'errorMessage': 'decryption failed',
      };

      final v2Listener = ContactRequestListener(
        contactRequestStream: streamController.stream,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        getOwnPeerId: () => _testOwnPeerId,
        getOwnPrivateKey: () async => 'ownPrivKeyBase64',
      );
      v2Listener.start();

      final requests = <ContactRequestModel>[];
      v2Listener.requestStream.listen(requests.add);

      // Need to build the message manually since _makeV2Message sets decryptResponse
      final envelope = jsonEncode({
        'type': 'contact_request',
        'version': '2',
        'msgId': 'fail-msg-1',
        'ts': DateTime.now().toUtc().toIso8601String(),
        'encrypted': {
          'ephemeralPublicKey': 'ephPub',
          'ciphertext': 'ct',
          'nonce': 'nonce',
        },
      });
      streamController.add(
        ChatMessage(
          from: _testPeerId,
          to: _testOwnPeerId,
          content: envelope,
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
        ),
      );
      await Future.delayed(const Duration(milliseconds: 100));

      expect(requests, isEmpty);
      v2Listener.dispose();
    });

    test('v1 still works without getOwnPrivateKey', () async {
      // Default listener (no getOwnPrivateKey) should handle v1 fine
      listener.start();

      final requests = <ContactRequestModel>[];
      listener.requestStream.listen(requests.add);

      streamController.add(_makeContactRequestMessage());
      await Future.delayed(const Duration(milliseconds: 100));

      expect(requests.length, equals(1));
    });

    test(
      'v2 contactKeyUpdated: peerId from decrypted payload, not message.from',
      () async {
        // Seed a contact WITHOUT ML-KEM key
        contactRepo.addTestContact(
          ContactModel(
            peerId: _testPeerId,
            publicKey: _testPublicKey,
            rendezvous: '/addr',
            username: 'TestUser',
            signature: 'sig',
            scannedAt: '2024-01-01T00:00:00Z',
            mlKemPublicKey: null,
          ),
        );

        final v2Listener = ContactRequestListener(
          contactRequestStream: streamController.stream,
          requestRepo: requestRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          getOwnPeerId: () => _testOwnPeerId,
          getOwnPrivateKey: () async => 'ownPrivKeyBase64',
        );
        v2Listener.start();

        final updates = <ContactModel>[];
        v2Listener.contactKeyUpdatedStream.listen(updates.add);

        // message.from is 'unknown' — peerId must come from decrypted payload
        streamController.add(
          _makeV2Message(from: 'unknown', mlkem: 'newMlKemKey'),
        );
        await Future.delayed(const Duration(milliseconds: 200));

        expect(updates.length, equals(1));
        expect(updates.first.peerId, equals(_testPeerId));
        expect(updates.first.mlKemPublicKey, equals('newMlKemKey'));

        v2Listener.dispose();
      },
    );

    test('v2 contactKeyUpdated: works with matching message.from', () async {
      // Seed a contact WITHOUT ML-KEM key
      contactRepo.addTestContact(
        ContactModel(
          peerId: _testPeerId,
          publicKey: _testPublicKey,
          rendezvous: '/addr',
          username: 'TestUser',
          signature: 'sig',
          scannedAt: '2024-01-01T00:00:00Z',
          mlKemPublicKey: null,
        ),
      );

      final v2Listener = ContactRequestListener(
        contactRequestStream: streamController.stream,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        getOwnPeerId: () => _testOwnPeerId,
        getOwnPrivateKey: () async => 'ownPrivKeyBase64',
      );
      v2Listener.start();

      final updates = <ContactModel>[];
      v2Listener.contactKeyUpdatedStream.listen(updates.add);

      // message.from matches peerId — normal v2 case
      streamController.add(_makeV2Message(mlkem: 'newMlKemKey'));
      await Future.delayed(const Duration(milliseconds: 200));

      expect(updates.length, equals(1));
      expect(updates.first.peerId, equals(_testPeerId));
      expect(updates.first.mlKemPublicKey, equals('newMlKemKey'));

      v2Listener.dispose();
    });

    test(
      'v2 new contact request: peerId from decrypted payload with from=unknown',
      () async {
        final v2Listener = ContactRequestListener(
          contactRequestStream: streamController.stream,
          requestRepo: requestRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          getOwnPeerId: () => _testOwnPeerId,
          getOwnPrivateKey: () async => 'ownPrivKeyBase64',
        );
        v2Listener.start();

        final requests = <ContactRequestModel>[];
        v2Listener.requestStream.listen(requests.add);

        // message.from is 'unknown' — peerId extracted from decrypted payload
        streamController.add(_makeV2Message(from: 'unknown'));
        await Future.delayed(const Duration(milliseconds: 200));

        expect(requests.length, equals(1));
        expect(requests.first.peerId, equals(_testPeerId));

        v2Listener.dispose();
      },
    );

    test(
      'silent intro recovery does not emit requestStream, records the v2 msgId, emits intro refresh once, and forwards key updates',
      () async {
        final introRepo = InMemoryIntroductionRepository();
        final messageRepo = InMemoryMessageRepository();
        final replayCache = ReplayCache();
        await introRepo.saveIntroduction(
          _pendingIntroFor(_testOwnPeerId, _testPeerId),
        );
        requestRepo.existingRequest = ContactRequestModel(
          peerId: _testPeerId,
          publicKey: _testPublicKey,
          rendezvous: '/addr',
          username: 'TestUser',
          signature: 'sig',
          receivedAt: '2026-04-03T11:00:00Z',
          status: ContactRequestStatus.pending,
        );
        contactRepo.addTestContact(
          ContactModel(
            peerId: _testPeerId,
            publicKey: _testPublicKey,
            rendezvous: '/addr',
            username: 'TestUser',
            signature: 'sig',
            scannedAt: '2026-04-03T11:00:00Z',
            mlKemPublicKey: null,
          ),
        );

        final recoveredIntros = <IntroductionModel>[];
        final v2Listener = ContactRequestListener(
          contactRequestStream: streamController.stream,
          requestRepo: requestRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          getOwnPeerId: () => _testOwnPeerId,
          getOwnPrivateKey: () async => 'ownPrivKeyBase64',
          replayCache: replayCache,
          attemptSilentIntroRecovery: (request) => recoverIntroContactRequest(
            introRepo: introRepo,
            requestRepo: requestRepo,
            contactRepo: contactRepo,
            ownPeerId: _testOwnPeerId,
            request: request,
            messageRepo: messageRepo,
          ),
          emitRecoveredIntroductionStatus: recoveredIntros.add,
        );
        v2Listener.start();

        final requests = <ContactRequestModel>[];
        final updates = <ContactModel>[];
        v2Listener.requestStream.listen(requests.add);
        v2Listener.contactKeyUpdatedStream.listen(updates.add);

        const msgId = 'intro-recovery-msg';
        streamController.add(
          _makeV2Message(msgId: msgId, mlkem: 'recovered-mlkem-key'),
        );
        await Future.delayed(const Duration(milliseconds: 200));

        expect(requests, isEmpty);
        expect(recoveredIntros, hasLength(1));
        expect(recoveredIntros.single.status, IntroductionOverallStatus.mutualAccepted);
        expect(updates, hasLength(1));
        expect(updates.single.peerId, _testPeerId);
        expect(updates.single.mlKemPublicKey, 'recovered-mlkem-key');
        expect(replayCache.contains(msgId), isTrue);
        expect(requestRepo.existingRequest, isNull);

        v2Listener.dispose();
      },
    );

    test(
      'silent intro recovery stays idempotent for same-envelope replay and fresh resend envelopes',
      () async {
        final introRepo = InMemoryIntroductionRepository();
        final messageRepo = InMemoryMessageRepository();
        final replayCache = ReplayCache();
        await introRepo.saveIntroduction(
          _pendingIntroFor(_testOwnPeerId, _testPeerId),
        );
        requestRepo.existingRequest = ContactRequestModel(
          peerId: _testPeerId,
          publicKey: _testPublicKey,
          rendezvous: '/addr',
          username: 'TestUser',
          signature: 'sig',
          receivedAt: '2026-04-03T11:00:00Z',
          status: ContactRequestStatus.pending,
        );

        final recoveredIntros = <IntroductionModel>[];
        final v2Listener = ContactRequestListener(
          contactRequestStream: streamController.stream,
          requestRepo: requestRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          getOwnPeerId: () => _testOwnPeerId,
          getOwnPrivateKey: () async => 'ownPrivKeyBase64',
          replayCache: replayCache,
          attemptSilentIntroRecovery: (request) => recoverIntroContactRequest(
            introRepo: introRepo,
            requestRepo: requestRepo,
            contactRepo: contactRepo,
            ownPeerId: _testOwnPeerId,
            request: request,
            messageRepo: messageRepo,
          ),
          emitRecoveredIntroductionStatus: recoveredIntros.add,
        );
        v2Listener.start();

        final requests = <ContactRequestModel>[];
        final updates = <ContactModel>[];
        v2Listener.requestStream.listen(requests.add);
        v2Listener.contactKeyUpdatedStream.listen(updates.add);

        streamController.add(_makeV2Message(msgId: 'repair-msg-1'));
        await Future.delayed(const Duration(milliseconds: 200));

        streamController.add(_makeV2Message(msgId: 'repair-msg-1'));
        await Future.delayed(const Duration(milliseconds: 200));

        streamController.add(_makeV2Message(msgId: 'repair-msg-2'));
        await Future.delayed(const Duration(milliseconds: 200));

        expect(requests, isEmpty);
        expect(updates, isEmpty);
        expect(recoveredIntros, hasLength(1));
        expect(await contactRepo.getContactCount(), 1);
        expect(replayCache.contains('repair-msg-1'), isTrue);
        expect(replayCache.contains('repair-msg-2'), isTrue);
        expect(requestRepo.existingRequest, isNull);

        v2Listener.dispose();
      },
    );

    test(
      'suppresses requestStream emission when presentation is delegated',
      () async {
        final suppressedListener = ContactRequestListener(
          contactRequestStream: streamController.stream,
          requestRepo: requestRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          getOwnPeerId: () => _testOwnPeerId,
          shouldSuppressPresentationForPeerId: (peerId) =>
              peerId == _testPeerId,
        );
        suppressedListener.start();

        final requests = <ContactRequestModel>[];
        suppressedListener.requestStream.listen(requests.add);

        streamController.add(_makeContactRequestMessage());
        await Future.delayed(const Duration(milliseconds: 100));

        expect(requests, isEmpty);
        expect(requestRepo.lastAdded?.peerId, _testPeerId);

        suppressedListener.dispose();
      },
    );
  });

  // ---------------------------------------------------------------------------
  // ReplayCache
  // ---------------------------------------------------------------------------
  group('ReplayCache', () {
    test('bounded at maxSize entries', () {
      final cache = ReplayCache(maxSize: 5, ttl: const Duration(hours: 25));

      for (int i = 0; i < 10; i++) {
        cache.add('msg-$i');
      }

      expect(cache.length, equals(5));
      // Oldest entries should be evicted
      expect(cache.contains('msg-0'), isFalse);
      expect(cache.contains('msg-4'), isFalse);
      // Most recent should be kept
      expect(cache.contains('msg-9'), isTrue);
      expect(cache.contains('msg-5'), isTrue);
    });

    test('evicts entries older than TTL', () {
      final cache = ReplayCache(maxSize: 1000, ttl: Duration.zero);

      cache.add('old-msg');
      // TTL is 0, so the entry is immediately stale
      expect(cache.contains('old-msg'), isFalse);
    });

    test('ids returns all cached entries', () {
      final cache = ReplayCache(maxSize: 1000, ttl: const Duration(hours: 25));
      cache.add('a');
      cache.add('b');
      cache.add('c');

      final ids = cache.ids;
      expect(ids, containsAll(['a', 'b', 'c']));
      expect(ids.length, equals(3));
    });
  });

  // -------------------------------------------------------------------------
  // 171: tap-free auto-add + deferred-ack confirm
  // -------------------------------------------------------------------------
  group('171 auto-add + confirm', () {
    ChatMessage makeV2({
      String peerId = _testPeerId,
      String? msgId,
      String? confirmNonce,
    }) {
      final payload = SplayTreeMap<String, dynamic>.from({
        'ns': peerId,
        'pk': _testPublicKey,
        'rv': '/dns4/rendezvous.example.com/tcp/4001/p2p/$peerId',
        'sig': 'fakeSigBase64ForTesting',
        'ts': '2024-06-15T12:00:00Z',
        'un': 'TestUser',
      });
      bridge.decryptResponse = {'ok': true, 'plaintext': jsonEncode(payload)};
      return ChatMessage(
        from: peerId,
        to: _testOwnPeerId,
        content: jsonEncode({
          'type': 'contact_request',
          'version': '2',
          'msgId': msgId ?? 'v2-${DateTime.now().microsecondsSinceEpoch}',
          'ts': DateTime.now().toUtc().toIso8601String(),
          'encrypted': {
            'ephemeralPublicKey': 'e',
            'ciphertext': 'c',
            'nonce': 'n',
          },
        }),
        timestamp: DateTime.now().toUtc().toIso8601String(),
        isIncoming: true,
        confirmNonce: confirmNonce,
      );
    }

    ContactRequestListener makeListener({
      Future<AcceptContactRequestResult> Function(String peerId)? autoAccept,
      ContactAutoAddRateLimiter? limiter,
    }) {
      return ContactRequestListener(
        contactRequestStream: streamController.stream,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        getOwnPeerId: () => _testOwnPeerId,
        getOwnPrivateKey: () async => 'ownPrivKeyBase64',
        autoAcceptAndReciprocate: autoAccept,
        autoAddRateLimiter: limiter,
      );
    }

    // TC-03: live deferred contact_request confirms ok:true after commit.
    test('confirms deferred contact_request with ok:true after commit', () async {
      final l = makeListener(
        autoAccept: (_) async => AcceptContactRequestResult.success,
      );
      addTearDown(l.dispose);

      await l.processIncomingMessage(makeV2(confirmNonce: 'nonce-abc'));

      final confirms = bridge.confirmRequests;
      expect(confirms, hasLength(1));
      expect(confirms.single['payload']['nonce'], equals('nonce-abc'));
      expect(confirms.single['payload']['ok'], isTrue);
    });

    // TC-03: a message with no confirmNonce must NOT trigger a confirm.
    test('does not confirm when confirmNonce is null', () async {
      final l = makeListener(
        autoAccept: (_) async => AcceptContactRequestResult.success,
      );
      addTearDown(l.dispose);

      await l.processIncomingMessage(makeV2(confirmNonce: null));

      expect(bridge.confirmRequests, isEmpty);
    });

    // TC-03: a thrown error during processing confirms ok:false (so the
    // sender's node withholds the ack -> the request inboxes -> retried).
    test('confirms ok:false when processing throws', () async {
      final l = makeListener(
        autoAccept: (_) async => throw Exception('accept boom'),
      );
      addTearDown(l.dispose);

      await expectLater(
        l.processIncomingMessage(makeV2(confirmNonce: 'nonce-fail')),
        throwsA(isA<Exception>()),
      );

      final confirms = bridge.confirmRequests;
      expect(confirms, hasLength(1));
      expect(confirms.single['payload']['nonce'], equals('nonce-fail'));
      expect(confirms.single['payload']['ok'], isFalse);
    });

    // TC-06: contactAutoAdded auto-accepts + reciprocates + confirms in order,
    // emits the notice, and does NOT show a dialog.
    test(
      'contactAutoAdded auto-accepts + confirms in order, notice, no dialog',
      () async {
        final order = <String>[];
        final l = makeListener(
          autoAccept: (peerId) async {
            order.add('accept:$peerId');
            return AcceptContactRequestResult.success;
          },
        );
        addTearDown(l.dispose);
        bridge.onSend = (req) {
          if (req['cmd'] == 'message:confirm') order.add('confirm');
        };
        final dialogs = <ContactRequestModel>[];
        l.requestStream.listen(dialogs.add);

        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        addTearDown(() => debugSetFlowEventSink(null));

        final result = await l.processIncomingMessage(makeV2(confirmNonce: 'n6'));
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(result, equals(HandleMessageResult.contactAutoAdded));
        // (a) accept fires, THEN (b) confirm — in order, exactly once each.
        expect(order, equals(['accept:$_testPeerId', 'confirm']));
        expect(
          events.where((e) => e['event'] == 'CONTACT_AUTO_ADDED').length,
          equals(1),
        );
        // No request-dialog emission.
        expect(dialogs, isEmpty);
      },
    );

    // TC-11: the global flood cap caps auto-adds; the overflow falls back to
    // the manual dialog (not a silent drop).
    test('auto-add rate-limit caps then falls back to dialog', () async {
      final accepts = <String>[];
      final l = makeListener(
        autoAccept: (peerId) async {
          accepts.add(peerId);
          return AcceptContactRequestResult.success;
        },
        limiter: ContactAutoAddRateLimiter(
          maxPerWindow: 2,
          clock: () => DateTime.utc(2026, 1, 1, 12),
        ),
      );
      addTearDown(l.dispose);
      final dialogs = <ContactRequestModel>[];
      l.requestStream.listen(dialogs.add);

      for (var i = 0; i < 3; i++) {
        await l.processIncomingMessage(
          makeV2(peerId: '12D3KooWDistinctPeer${i}xxxxxxxxxx', msgId: 'rl-$i'),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(accepts, hasLength(2));
      expect(dialogs, hasLength(1));
    });

    // TC-12: the same v2 msgId delivered twice auto-accepts EXACTLY once
    // (INV-6) — the contactAutoAdded result must enter the replay cache.
    //
    // Uses a WORKING request repo so the first auto-accept flips the request to
    // `accepted` (mimics acceptAndReciprocate). That makes step-9's
    // pending-request dedup INERT on the 2nd delivery, so the replay cache is
    // the SOLE dedup — exactly what the OR-list entry must provide. (Omitting
    // contactAutoAdded from the replay-cache OR-list re-runs the 2nd delivery.)
    test('same-msgId v2 delivered twice → exactly one auto-accept', () async {
      final reqRepo = InMemoryContactRequestRepository();
      final accepts = <String>[];
      final l = ContactRequestListener(
        contactRequestStream: streamController.stream,
        requestRepo: reqRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        getOwnPeerId: () => _testOwnPeerId,
        getOwnPrivateKey: () async => 'ownPrivKeyBase64',
        autoAcceptAndReciprocate: (peerId) async {
          accepts.add(peerId);
          await reqRepo.updateStatus(peerId, ContactRequestStatus.accepted);
          return AcceptContactRequestResult.success;
        },
      );
      addTearDown(l.dispose);

      await l.processIncomingMessage(makeV2(msgId: 'dup-msg-1'));
      await l.processIncomingMessage(makeV2(msgId: 'dup-msg-1'));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(accepts, hasLength(1));
    });

    // Review fix: if the local accept fails (e.g. a transient DB write error),
    // the request is NOT silently lost (committed-and-deleted with no contact)
    // — it falls back to the manual dialog (it is already durably pending).
    test('auto-add accept failure falls back to dialog (no silent loss)', () async {
      final dialogs = <ContactRequestModel>[];
      final l = makeListener(
        autoAccept: (_) async => AcceptContactRequestResult.addContactError,
      );
      addTearDown(l.dispose);
      l.requestStream.listen(dialogs.add);

      final events = <Map<String, dynamic>>[];
      debugSetFlowEventSink(events.add);
      addTearDown(() => debugSetFlowEventSink(null));

      final result = await l.processIncomingMessage(makeV2());
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Result is still contactAutoAdded (the use-case eligibility), but the
      // listener surfaced it on the dialog rather than losing it.
      expect(result, equals(HandleMessageResult.contactAutoAdded));
      expect(dialogs, hasLength(1));
      expect(
        events
            .where(
              (e) =>
                  e['event'] ==
                  'CONTACT_AUTO_ADD_ACCEPT_FAILED_DIALOG_FALLBACK',
            )
            .length,
        equals(1),
      );
    });
  });
}
