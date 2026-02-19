import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contact_request/application/handle_incoming_message_use_case.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart';
import 'package:flutter_app/core/bridge/bridge.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeBridge extends Bridge {
  bool verifyResult = true;

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
    final req = jsonDecode(message) as Map<String, dynamic>;
    if (req['cmd'] == 'payload.verify') {
      return jsonEncode({'ok': true, 'valid': verifyResult});
    }
    return jsonEncode({'ok': true});
  }
}

class _FakeContactRequestRepo implements ContactRequestRepository {
  final Map<String, ContactRequestModel> _requests = {};

  @override
  Future<void> addRequest(ContactRequestModel request) async {
    _requests[request.peerId] = request;
  }

  @override
  Future<ContactRequestModel?> getRequest(String peerId) async =>
      _requests[peerId];

  @override
  Future<List<ContactRequestModel>> getPendingRequests() async =>
      _requests.values
          .where((r) => r.status == ContactRequestStatus.pending)
          .toList();

  @override
  Future<void> updateStatus(String peerId, ContactRequestStatus status) async {
    final existing = _requests[peerId];
    if (existing != null) {
      _requests[peerId] = existing.copyWith(status: status);
    }
  }

  @override
  Future<void> deleteRequest(String peerId) async {
    _requests.remove(peerId);
  }

  @override
  Future<bool> requestExists(String peerId) async =>
      _requests.containsKey(peerId);
}

class _FakeContactRepo implements ContactRepository {
  final Set<String> _contacts = {};

  @override
  Future<void> addContact(ContactModel contact) async {
    _contacts.add(contact.peerId);
  }

  @override
  Future<ContactModel?> getContact(String peerId) async => null;

  @override
  Future<List<ContactModel>> getAllContacts() async => [];

  @override
  Future<void> deleteContact(String peerId) async {
    _contacts.remove(peerId);
  }

  @override
  Future<bool> contactExists(String peerId) async =>
      _contacts.contains(peerId);

  @override
  Future<int> getContactCount() async => _contacts.length;

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
}

// ---------------------------------------------------------------------------
// Test data
// ---------------------------------------------------------------------------

const _ownPeerId = '12D3KooWOwnPeerIdForTesting';
const _senderPeerId = '12D3KooWSenderPeerIdForTest';

Map<String, dynamic> _validPayload() => {
      'pk': 'senderPublicKey',
      'ns': _senderPeerId,
      'rv': '/dns4/mknoun.xyz/tcp/4001/wss/p2p/relay',
      'ts': DateTime.now().toUtc().toIso8601String(),
      'sig': 'validSignatureBase64',
      'un': 'Alice',
    };

String _contactRequestMessage(Map<String, dynamic> payload) => jsonEncode({
      'type': 'contact_request',
      'version': '1',
      'payload': payload,
    });

ChatMessage _makeChatMessage(String content, {String? from}) => ChatMessage(
      from: from ?? _senderPeerId,
      to: _ownPeerId,
      content: content,
      timestamp: DateTime.now().toIso8601String(),
      isIncoming: true,
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _FakeBridge bridge;
  late _FakeContactRequestRepo requestRepo;
  late _FakeContactRepo contactRepo;

  setUp(() {
    bridge = _FakeBridge();
    requestRepo = _FakeContactRequestRepo();
    contactRepo = _FakeContactRepo();
  });

  test('contactRequest: valid contact request is stored', () async {
    final payload = _validPayload();
    final message = _makeChatMessage(_contactRequestMessage(payload));

    final (result, request) = await handleIncomingMessage(
      message: message,
      bridge: bridge,
      requestRepo: requestRepo,
      contactRepo: contactRepo,
      ownPeerId: _ownPeerId,
    );

    expect(result, equals(HandleMessageResult.contactRequest));
    expect(request, isNotNull);
    expect(request!.peerId, equals(_senderPeerId));
    expect(request.username, equals('Alice'));
  });

  test('regularMessage: non-JSON content', () async {
    final message = _makeChatMessage('Hello, plain text!');

    final (result, request) = await handleIncomingMessage(
      message: message,
      bridge: bridge,
      requestRepo: requestRepo,
      contactRepo: contactRepo,
      ownPeerId: _ownPeerId,
    );

    expect(result, equals(HandleMessageResult.regularMessage));
    expect(request, isNull);
  });

  test('regularMessage: JSON but not contact_request type', () async {
    final message = _makeChatMessage(jsonEncode({
      'type': 'chat_message',
      'payload': {'text': 'hi'},
    }));

    final (result, _) = await handleIncomingMessage(
      message: message,
      bridge: bridge,
      requestRepo: requestRepo,
      contactRepo: contactRepo,
      ownPeerId: _ownPeerId,
    );

    expect(result, equals(HandleMessageResult.regularMessage));
  });

  test('invalidMessage: missing required fields', () async {
    final message = _makeChatMessage(_contactRequestMessage({
      'pk': 'key',
      // missing ns, rv, ts, sig
    }));

    final (result, _) = await handleIncomingMessage(
      message: message,
      bridge: bridge,
      requestRepo: requestRepo,
      contactRepo: contactRepo,
      ownPeerId: _ownPeerId,
    );

    expect(result, equals(HandleMessageResult.invalidMessage));
  });

  test('invalidMessage: invalid signature', () async {
    bridge.verifyResult = false;
    final payload = _validPayload();
    final message = _makeChatMessage(_contactRequestMessage(payload));

    final (result, _) = await handleIncomingMessage(
      message: message,
      bridge: bridge,
      requestRepo: requestRepo,
      contactRepo: contactRepo,
      ownPeerId: _ownPeerId,
    );

    expect(result, equals(HandleMessageResult.invalidMessage));
  });

  test('invalidMessage: sender mismatch (from != ns)', () async {
    final payload = _validPayload();
    final message = _makeChatMessage(
      _contactRequestMessage(payload),
      from: 'differentPeerId12345',
    );

    final (result, _) = await handleIncomingMessage(
      message: message,
      bridge: bridge,
      requestRepo: requestRepo,
      contactRepo: contactRepo,
      ownPeerId: _ownPeerId,
    );

    expect(result, equals(HandleMessageResult.invalidMessage));
  });

  test('invalidMessage: from self', () async {
    final payload = _validPayload();
    // Override ns to be own peer ID
    payload['ns'] = _ownPeerId;
    final message = _makeChatMessage(
      _contactRequestMessage(payload),
      from: _ownPeerId,
    );

    final (result, _) = await handleIncomingMessage(
      message: message,
      bridge: bridge,
      requestRepo: requestRepo,
      contactRepo: contactRepo,
      ownPeerId: _ownPeerId,
    );

    expect(result, equals(HandleMessageResult.invalidMessage));
  });

  test('alreadyContact: sender is already a contact', () async {
    contactRepo._contacts.add(_senderPeerId);
    final payload = _validPayload();
    final message = _makeChatMessage(_contactRequestMessage(payload));

    final (result, _) = await handleIncomingMessage(
      message: message,
      bridge: bridge,
      requestRepo: requestRepo,
      contactRepo: contactRepo,
      ownPeerId: _ownPeerId,
    );

    expect(result, equals(HandleMessageResult.alreadyContact));
  });

  test('duplicateRequest: pending request already exists', () async {
    // Pre-populate a pending request
    await requestRepo.addRequest(ContactRequestModel(
      peerId: _senderPeerId,
      publicKey: 'pk',
      rendezvous: 'rv',
      username: 'Alice',
      signature: 'sig',
      receivedAt: DateTime.now().toIso8601String(),
      status: ContactRequestStatus.pending,
    ));

    final payload = _validPayload();
    final message = _makeChatMessage(_contactRequestMessage(payload));

    final (result, _) = await handleIncomingMessage(
      message: message,
      bridge: bridge,
      requestRepo: requestRepo,
      contactRepo: contactRepo,
      ownPeerId: _ownPeerId,
    );

    expect(result, equals(HandleMessageResult.duplicateRequest));
  });

  test('contactRequest with mlkem key: ML-KEM public key is preserved', () async {
    final payload = _validPayload();
    payload['mlkem'] = 'senderMlKemPublicKey';
    final message = _makeChatMessage(_contactRequestMessage(payload));

    final (result, request) = await handleIncomingMessage(
      message: message,
      bridge: bridge,
      requestRepo: requestRepo,
      contactRepo: contactRepo,
      ownPeerId: _ownPeerId,
    );

    expect(result, equals(HandleMessageResult.contactRequest));
    expect(request!.mlKemPublicKey, equals('senderMlKemPublicKey'));
  });
}
