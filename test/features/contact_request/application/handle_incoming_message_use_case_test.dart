import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contact_request/application/handle_incoming_message_use_case.dart';
import 'package:flutter_app/features/contact_request/application/recover_intro_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/push/domain/received_wake_token_store.dart';
import 'package:flutter_app/core/bridge/bridge.dart';

/// Minimal in-memory [ReceivedWakeTokenStore] for the A03/A04 receive tests.
class _FakeReceivedWakeTokenStore implements ReceivedWakeTokenStore {
  final Map<String, Map<String, String>> tokens = {};

  @override
  Future<Map<String, String>?> readTokenFor(String peerId) async =>
      tokens[peerId] == null ? null : Map<String, String>.from(tokens[peerId]!);

  @override
  Future<void> writeTokenFor(String peerId, String token, String ts) async =>
      tokens[peerId] = {'tok': token, 'ts': ts};

  @override
  Future<void> removeTokenFor(String peerId) async => tokens.remove(peerId);

  @override
  Future<void> clear() async => tokens.clear();
}

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeBridge extends Bridge {
  bool verifyResult = true;
  Map<String, dynamic> decryptResponse = {
    'ok': true,
    'plaintext': '', // will be set per test
  };
  bool decryptCalled = false;
  bool verifyCalled = false;

  /// The exact reconstructed `data` string the use-case asked us to verify —
  /// lets A02 assert the reconstruction allowlist included (or omitted) `wt`.
  String? lastVerifyData;

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
      verifyCalled = true;
      lastVerifyData = (req['payload'] as Map<String, dynamic>)['data'] as String?;
      return jsonEncode({'ok': true, 'valid': verifyResult});
    }
    if (req['cmd'] == 'contactrequest.decrypt') {
      decryptCalled = true;
      return jsonEncode(decryptResponse);
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
  Future<List<ContactRequestModel>> getPendingRequests() async => _requests
      .values
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
  final Map<String, ContactModel> _contacts = {};

  @override
  Future<void> addContact(ContactModel contact) async {
    _contacts[contact.peerId] = contact;
  }

  @override
  Future<ContactModel?> getContact(String peerId) async => _contacts[peerId];

  @override
  Future<List<ContactModel>> getAllContacts() async =>
      _contacts.values.toList();

  @override
  Future<void> deleteContact(String peerId) async {
    _contacts.remove(peerId);
  }

  @override
  Future<bool> contactExists(String peerId) async =>
      _contacts.containsKey(peerId);

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

  @override
  Future<void> dismissIntroBanner(String peerId) async {}

  @override
  Future<void> setIntrosSentAt(String peerId, String timestamp) async {}
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

String _contactRequestMessage(Map<String, dynamic> payload) =>
    jsonEncode({'type': 'contact_request', 'version': '1', 'payload': payload});

ChatMessage _makeChatMessage(String content, {String? from}) => ChatMessage(
  from: from ?? _senderPeerId,
  to: _ownPeerId,
  content: content,
  timestamp: DateTime.now().toIso8601String(),
  isIncoming: true,
);

IntroductionModel _introModel() => IntroductionModel(
  id: 'intro-recovery-1',
  introducerId: '12D3KooWIntroducerPeerId',
  recipientId: _ownPeerId,
  introducedId: _senderPeerId,
  recipientStatus: IntroductionStatus.accepted,
  introducedStatus: IntroductionStatus.pending,
  status: IntroductionOverallStatus.pending,
  createdAt: DateTime.now().toUtc().toIso8601String(),
  introducerUsername: 'Noor',
  recipientUsername: 'Own User',
  introducedUsername: 'Alice',
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

    final (result, request, _) = await handleIncomingMessage(
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

  test(
    'contactRequest: preserves mixed-script username from payload',
    () async {
      final payload = _validPayload();
      payload['un'] = ' \u200f\u0644\u064a\u0644\u0649 Alpha\u200f ';
      final message = _makeChatMessage(_contactRequestMessage(payload));

      final (result, request, _) = await handleIncomingMessage(
        message: message,
        bridge: bridge,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        ownPeerId: _ownPeerId,
      );

      expect(result, equals(HandleMessageResult.contactRequest));
      expect(request, isNotNull);
      expect(
        request!.username,
        equals(' \u200f\u0644\u064a\u0644\u0649 Alpha\u200f '),
      );
    },
  );

  test('regularMessage: non-JSON content', () async {
    final message = _makeChatMessage('Hello, plain text!');

    final (result, request, _) = await handleIncomingMessage(
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
    final message = _makeChatMessage(
      jsonEncode({
        'type': 'chat_message',
        'payload': {'text': 'hi'},
      }),
    );

    final (result, _, _) = await handleIncomingMessage(
      message: message,
      bridge: bridge,
      requestRepo: requestRepo,
      contactRepo: contactRepo,
      ownPeerId: _ownPeerId,
    );

    expect(result, equals(HandleMessageResult.regularMessage));
  });

  test('invalidMessage: missing required fields', () async {
    final message = _makeChatMessage(
      _contactRequestMessage({
        'pk': 'key',
        // missing ns, rv, ts, sig
      }),
    );

    final (result, _, _) = await handleIncomingMessage(
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

    final (result, _, _) = await handleIncomingMessage(
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

    final (result, _, _) = await handleIncomingMessage(
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

    final (result, _, _) = await handleIncomingMessage(
      message: message,
      bridge: bridge,
      requestRepo: requestRepo,
      contactRepo: contactRepo,
      ownPeerId: _ownPeerId,
    );

    expect(result, equals(HandleMessageResult.invalidMessage));
  });

  test('alreadyContact: sender is already a contact', () async {
    contactRepo._contacts[_senderPeerId] = ContactModel(
      peerId: _senderPeerId,
      publicKey: 'senderPublicKey',
      rendezvous: '/dns4/mknoun.xyz/tcp/4001/wss/p2p/relay',
      username: 'Alice',
      signature: 'sig',
      scannedAt: DateTime.now().toIso8601String(),
      mlKemPublicKey: 'existingKey',
    );
    final payload = _validPayload();
    final message = _makeChatMessage(_contactRequestMessage(payload));

    final (result, _, _) = await handleIncomingMessage(
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
    await requestRepo.addRequest(
      ContactRequestModel(
        peerId: _senderPeerId,
        publicKey: 'pk',
        rendezvous: 'rv',
        username: 'Alice',
        signature: 'sig',
        receivedAt: DateTime.now().toIso8601String(),
        status: ContactRequestStatus.pending,
      ),
    );

    final payload = _validPayload();
    final message = _makeChatMessage(_contactRequestMessage(payload));

    final (result, _, _) = await handleIncomingMessage(
      message: message,
      bridge: bridge,
      requestRepo: requestRepo,
      contactRepo: contactRepo,
      ownPeerId: _ownPeerId,
    );

    expect(result, equals(HandleMessageResult.duplicateRequest));
  });

  test(
    'silentIntroRecovered: recovery callback runs before alreadyContact short-circuit',
    () async {
      contactRepo._contacts[_senderPeerId] = ContactModel(
        peerId: _senderPeerId,
        publicKey: 'senderPublicKey',
        rendezvous: '/dns4/mknoun.xyz/tcp/4001/wss/p2p/relay',
        username: 'Alice',
        signature: 'sig',
        scannedAt: DateTime.now().toIso8601String(),
        mlKemPublicKey: 'existingKey',
      );

      VerifiedContactRequestEnvelope? capturedRequest;
      final message = _makeChatMessage(_contactRequestMessage(_validPayload()));

      final (result, request, peerId) = await handleIncomingMessage(
        message: message,
        bridge: bridge,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        ownPeerId: _ownPeerId,
        attemptSilentIntroRecovery: (verifiedRequest) async {
          capturedRequest = verifiedRequest;
          return IntroContactRequestRecoveryResult.recovered(
            introduction: _introModel(),
            contact: await contactRepo.getContact(_senderPeerId),
          );
        },
      );

      expect(result, HandleMessageResult.silentIntroRecovered);
      expect(request, isNull);
      expect(peerId, isNull);
      expect(capturedRequest?.peerId, _senderPeerId);
    },
  );

  test(
    'silentIntroRecovered: recovery callback runs before duplicateRequest short-circuit',
    () async {
      await requestRepo.addRequest(
        ContactRequestModel(
          peerId: _senderPeerId,
          publicKey: 'pk',
          rendezvous: 'rv',
          username: 'Alice',
          signature: 'sig',
          receivedAt: DateTime.now().toIso8601String(),
          status: ContactRequestStatus.pending,
        ),
      );

      var recoveryCalls = 0;
      final message = _makeChatMessage(_contactRequestMessage(_validPayload()));

      final (result, request, peerId) = await handleIncomingMessage(
        message: message,
        bridge: bridge,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        ownPeerId: _ownPeerId,
        attemptSilentIntroRecovery: (_) async {
          recoveryCalls++;
          return IntroContactRequestRecoveryResult.recovered(
            introduction: _introModel(),
          );
        },
      );

      expect(result, HandleMessageResult.silentIntroRecovered);
      expect(request, isNull);
      expect(peerId, isNull);
      expect(recoveryCalls, 1);
    },
  );

  test(
    'continueAsContactRequest fallback bypasses a stale pending request row',
    () async {
      await requestRepo.addRequest(
        ContactRequestModel(
          peerId: _senderPeerId,
          publicKey: 'pk',
          rendezvous: 'rv',
          username: 'Alice',
          signature: 'sig',
          receivedAt: DateTime.now().toIso8601String(),
          status: ContactRequestStatus.pending,
        ),
      );
      final message = _makeChatMessage(_contactRequestMessage(_validPayload()));

      final (result, request, peerId) = await handleIncomingMessage(
        message: message,
        bridge: bridge,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        ownPeerId: _ownPeerId,
        attemptSilentIntroRecovery: (_) async {
          await requestRepo.deleteRequest(_senderPeerId);
          return const IntroContactRequestRecoveryResult.continueAsContactRequest();
        },
      );

      expect(result, HandleMessageResult.contactRequest);
      expect(request, isNotNull);
      expect(peerId, isNull);
      expect(await requestRepo.getRequest(_senderPeerId), isNotNull);
    },
  );

  test(
    'noMatch guard falls back to the normal contact request path',
    () async {
      final message = _makeChatMessage(_contactRequestMessage(_validPayload()));

      final (result, request, peerId) = await handleIncomingMessage(
        message: message,
        bridge: bridge,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        ownPeerId: _ownPeerId,
        attemptSilentIntroRecovery: (_) async =>
            const IntroContactRequestRecoveryResult.noMatch(),
      );

      expect(result, HandleMessageResult.contactRequest);
      expect(request, isNotNull);
      expect(peerId, isNull);
    },
  );

  test(
    'unknown sender still allows verified silent recovery on the old no-intent path',
    () async {
      VerifiedContactRequestEnvelope? capturedRequest;
      final message = _makeChatMessage(
        _contactRequestMessage(_validPayload()),
        from: 'unknown',
      );

      final (result, request, peerId) = await handleIncomingMessage(
        message: message,
        bridge: bridge,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        ownPeerId: _ownPeerId,
        attemptSilentIntroRecovery: (verifiedRequest) async {
          capturedRequest = verifiedRequest;
          return IntroContactRequestRecoveryResult.recovered(
            introduction: _introModel(),
          );
        },
      );

      expect(result, HandleMessageResult.silentIntroRecovered);
      expect(request, isNull);
      expect(peerId, isNull);
      expect(capturedRequest?.peerId, _senderPeerId);
      expect(capturedRequest?.publicKey, 'senderPublicKey');
    },
  );

  test(
    'contactRequest with mlkem key: ML-KEM public key is preserved',
    () async {
      final payload = _validPayload();
      payload['mlkem'] = 'senderMlKemPublicKey';
      final message = _makeChatMessage(_contactRequestMessage(payload));

      final (result, request, _) = await handleIncomingMessage(
        message: message,
        bridge: bridge,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        ownPeerId: _ownPeerId,
      );

      expect(result, equals(HandleMessageResult.contactRequest));
      expect(request!.mlKemPublicKey, equals('senderMlKemPublicKey'));
    },
  );

  test('contactKeyUpdated: contact has no key but payload has one', () async {
    contactRepo._contacts[_senderPeerId] = ContactModel(
      peerId: _senderPeerId,
      publicKey: 'senderPublicKey',
      rendezvous: '/dns4/mknoun.xyz/tcp/4001/wss/p2p/relay',
      username: 'Alice',
      signature: 'sig',
      scannedAt: DateTime.now().toIso8601String(),
      mlKemPublicKey: null,
    );

    final payload = _validPayload();
    payload['mlkem'] = 'senderMlKemPub';
    final message = _makeChatMessage(_contactRequestMessage(payload));

    final (result, request, _) = await handleIncomingMessage(
      message: message,
      bridge: bridge,
      requestRepo: requestRepo,
      contactRepo: contactRepo,
      ownPeerId: _ownPeerId,
    );

    expect(result, equals(HandleMessageResult.contactKeyUpdated));
    expect(request, isNull);

    // Verify the contact was updated with the ML-KEM key
    final updated = await contactRepo.getContact(_senderPeerId);
    expect(updated!.mlKemPublicKey, equals('senderMlKemPub'));
  });

  test(
    'updates existing contact ML-KEM key when signed payload carries a '
    'different key',
    () async {
      // P0-B: a restored peer re-announces a NEW key via the signed
      // contact_request envelope; the receiver must rotate, not ignore.
      contactRepo._contacts[_senderPeerId] = ContactModel(
        peerId: _senderPeerId,
        publicKey: 'senderPublicKey',
        rendezvous: '/dns4/mknoun.xyz/tcp/4001/wss/p2p/relay',
        username: 'Alice',
        signature: 'sig',
        scannedAt: '2026-01-01T00:00:00.000Z',
        mlKemPublicKey: 'existingKey',
      );

      final payload = _validPayload();
      payload['mlkem'] = 'rotatedKey';
      final message = _makeChatMessage(_contactRequestMessage(payload));

      final (result, request, peerId) = await handleIncomingMessage(
        message: message,
        bridge: bridge,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        ownPeerId: _ownPeerId,
      );

      expect(result, equals(HandleMessageResult.contactKeyUpdated));
      expect(request, isNull);
      expect(peerId, equals(_senderPeerId));

      final updated = await contactRepo.getContact(_senderPeerId);
      expect(updated!.mlKemPublicKey, equals('rotatedKey'));
      expect(updated.mlKemKeyUpdatedTs, equals(payload['ts']));
    },
  );

  test(
    'ignores key change when payload ts is not newer than last key update',
    () async {
      // Anti-rollback: a replayed OLD signed contact_request must not roll
      // the contact back to a stale key.
      contactRepo._contacts[_senderPeerId] = ContactModel(
        peerId: _senderPeerId,
        publicKey: 'senderPublicKey',
        rendezvous: '/dns4/mknoun.xyz/tcp/4001/wss/p2p/relay',
        username: 'Alice',
        signature: 'sig',
        scannedAt: '2026-01-01T00:00:00.000Z',
        mlKemPublicKey: 'currentKey',
        mlKemKeyUpdatedTs: '2026-06-01T00:00:00.000Z',
      );

      final payload = _validPayload();
      payload['mlkem'] = 'staleReplayedKey';
      payload['ts'] = '2026-05-01T00:00:00.000Z';
      final message = _makeChatMessage(_contactRequestMessage(payload));

      final (result, _, _) = await handleIncomingMessage(
        message: message,
        bridge: bridge,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        ownPeerId: _ownPeerId,
      );

      expect(result, equals(HandleMessageResult.alreadyContact));
      final contact = await contactRepo.getContact(_senderPeerId);
      expect(contact!.mlKemPublicKey, equals('currentKey'));
      expect(contact.mlKemKeyUpdatedTs, equals('2026-06-01T00:00:00.000Z'));
    },
  );

  test('keeps existing key when payload key is identical', () async {
    contactRepo._contacts[_senderPeerId] = ContactModel(
      peerId: _senderPeerId,
      publicKey: 'senderPublicKey',
      rendezvous: '/dns4/mknoun.xyz/tcp/4001/wss/p2p/relay',
      username: 'Alice',
      signature: 'sig',
      scannedAt: '2026-01-01T00:00:00.000Z',
      mlKemPublicKey: 'existingKey',
      mlKemKeyUpdatedTs: '2026-02-01T00:00:00.000Z',
    );

    final payload = _validPayload();
    payload['mlkem'] = 'existingKey';
    final message = _makeChatMessage(_contactRequestMessage(payload));

    final (result, _, _) = await handleIncomingMessage(
      message: message,
      bridge: bridge,
      requestRepo: requestRepo,
      contactRepo: contactRepo,
      ownPeerId: _ownPeerId,
    );

    expect(result, equals(HandleMessageResult.alreadyContact));
    final contact = await contactRepo.getContact(_senderPeerId);
    expect(contact!.mlKemPublicKey, equals('existingKey'));
    expect(contact.mlKemKeyUpdatedTs, equals('2026-02-01T00:00:00.000Z'));
  });

  test('alreadyContact: payload has no mlkem field, no update', () async {
    contactRepo._contacts[_senderPeerId] = ContactModel(
      peerId: _senderPeerId,
      publicKey: 'senderPublicKey',
      rendezvous: '/dns4/mknoun.xyz/tcp/4001/wss/p2p/relay',
      username: 'Alice',
      signature: 'sig',
      scannedAt: DateTime.now().toIso8601String(),
      mlKemPublicKey: null,
    );

    final payload = _validPayload();
    // No 'mlkem' key in payload
    final message = _makeChatMessage(_contactRequestMessage(payload));

    final (result, _, _) = await handleIncomingMessage(
      message: message,
      bridge: bridge,
      requestRepo: requestRepo,
      contactRepo: contactRepo,
      ownPeerId: _ownPeerId,
    );

    expect(result, equals(HandleMessageResult.alreadyContact));

    // Key still null
    final contact = await contactRepo.getContact(_senderPeerId);
    expect(contact!.mlKemPublicKey, isNull);
  });

  test('contactKeyUpdated: returned ContactRequestModel is null', () async {
    contactRepo._contacts[_senderPeerId] = ContactModel(
      peerId: _senderPeerId,
      publicKey: 'senderPublicKey',
      rendezvous: '/dns4/mknoun.xyz/tcp/4001/wss/p2p/relay',
      username: 'Alice',
      signature: 'sig',
      scannedAt: DateTime.now().toIso8601String(),
      mlKemPublicKey: null,
    );

    final payload = _validPayload();
    payload['mlkem'] = 'senderMlKemPub';
    final message = _makeChatMessage(_contactRequestMessage(payload));

    final (result, request, _) = await handleIncomingMessage(
      message: message,
      bridge: bridge,
      requestRepo: requestRepo,
      contactRepo: contactRepo,
      ownPeerId: _ownPeerId,
    );

    expect(result, equals(HandleMessageResult.contactKeyUpdated));
    expect(request, isNull);
  });

  test('contactKeyUpdated: returns peerId from decrypted payload', () async {
    contactRepo._contacts[_senderPeerId] = ContactModel(
      peerId: _senderPeerId,
      publicKey: 'senderPublicKey',
      rendezvous: '/dns4/mknoun.xyz/tcp/4001/wss/p2p/relay',
      username: 'Alice',
      signature: 'sig',
      scannedAt: DateTime.now().toIso8601String(),
      mlKemPublicKey: null,
    );

    final payload = _validPayload();
    payload['mlkem'] = 'senderMlKemPub';
    final message = _makeChatMessage(_contactRequestMessage(payload));

    final (result, _, keyUpdatePeerId) = await handleIncomingMessage(
      message: message,
      bridge: bridge,
      requestRepo: requestRepo,
      contactRepo: contactRepo,
      ownPeerId: _ownPeerId,
    );

    expect(result, equals(HandleMessageResult.contactKeyUpdated));
    expect(keyUpdatePeerId, equals(_senderPeerId));
  });

  // --- v2 encrypted contact request tests ---

  group('v2 encrypted', () {
    /// Builds a v2 encrypted envelope with the payload as "ciphertext".
    /// The fake bridge will return the payload JSON as plaintext on decrypt.
    String v2Message(
      Map<String, dynamic> payload, {
      String? msgId,
      String? ts,
    }) {
      final id = msgId ?? 'test-msg-${DateTime.now().microsecondsSinceEpoch}';
      final timestamp = ts ?? DateTime.now().toUtc().toIso8601String();
      return jsonEncode({
        'type': 'contact_request',
        'version': '2',
        'msgId': id,
        'ts': timestamp,
        'encrypted': {
          'ephemeralPublicKey': 'ephPubBase64',
          'ciphertext': 'ctBase64',
          'nonce': 'nonceBase64',
        },
      });
    }

    test('v2 message is decrypted and stored', () async {
      final payload = _validPayload();
      bridge.decryptResponse = {'ok': true, 'plaintext': jsonEncode(payload)};

      final message = _makeChatMessage(v2Message(payload));
      final (result, request, _) = await handleIncomingMessage(
        message: message,
        bridge: bridge,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        ownPeerId: _ownPeerId,
        ownPrivateKey: 'ownPrivKeyBase64',
      );

      // 171: a NEW v2 (recipient-bound) request is now auto-add-eligible
      // (contactAutoAdded), not the manual-dialog contactRequest. It is still
      // decrypted + stored pending (asserted below).
      expect(result, equals(HandleMessageResult.contactAutoAdded));
      expect(request, isNotNull);
      expect(request!.peerId, equals(_senderPeerId));
    });

    test('v2 decrypted payload is signature-verified', () async {
      final payload = _validPayload();
      bridge.decryptResponse = {'ok': true, 'plaintext': jsonEncode(payload)};

      final message = _makeChatMessage(v2Message(payload));
      await handleIncomingMessage(
        message: message,
        bridge: bridge,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        ownPeerId: _ownPeerId,
        ownPrivateKey: 'ownPrivKeyBase64',
      );

      expect(bridge.decryptCalled, isTrue);
      expect(bridge.verifyCalled, isTrue);
    });

    test('v2 decryption failure → invalidMessage', () async {
      bridge.decryptResponse = {
        'ok': false,
        'errorCode': 'INTERNAL_ERROR',
        'errorMessage': 'decryption failed',
      };

      final message = _makeChatMessage(v2Message(_validPayload()));
      final (result, _, _) = await handleIncomingMessage(
        message: message,
        bridge: bridge,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        ownPeerId: _ownPeerId,
        ownPrivateKey: 'ownPrivKeyBase64',
      );

      expect(result, equals(HandleMessageResult.invalidMessage));
    });

    test('v2 invalid signature after decrypt → invalidMessage', () async {
      final payload = _validPayload();
      bridge.decryptResponse = {'ok': true, 'plaintext': jsonEncode(payload)};
      bridge.verifyResult = false;

      final message = _makeChatMessage(v2Message(payload));
      final (result, _, _) = await handleIncomingMessage(
        message: message,
        bridge: bridge,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        ownPeerId: _ownPeerId,
        ownPrivateKey: 'ownPrivKeyBase64',
      );

      expect(result, equals(HandleMessageResult.invalidMessage));
    });

    test('v2 missing ownPrivateKey → invalidMessage', () async {
      bridge.decryptResponse = {
        'ok': true,
        'plaintext': jsonEncode(_validPayload()),
      };

      final message = _makeChatMessage(v2Message(_validPayload()));
      final (result, _, _) = await handleIncomingMessage(
        message: message,
        bridge: bridge,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        ownPeerId: _ownPeerId,
        ownPrivateKey: null,
      );

      expect(result, equals(HandleMessageResult.invalidMessage));
    });

    test('v2 missing encrypted block → invalidMessage', () async {
      final message = _makeChatMessage(
        jsonEncode({
          'type': 'contact_request',
          'version': '2',
          'msgId': 'test-msg-1',
          'ts': DateTime.now().toUtc().toIso8601String(),
          // no 'encrypted' key
        }),
      );
      final (result, _, _) = await handleIncomingMessage(
        message: message,
        bridge: bridge,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        ownPeerId: _ownPeerId,
        ownPrivateKey: 'ownPrivKeyBase64',
      );

      expect(result, equals(HandleMessageResult.invalidMessage));
    });

    test('v2 incomplete encrypted block → invalidMessage', () async {
      final message = _makeChatMessage(
        jsonEncode({
          'type': 'contact_request',
          'version': '2',
          'msgId': 'test-msg-1',
          'ts': DateTime.now().toUtc().toIso8601String(),
          'encrypted': {
            'ephemeralPublicKey': 'ephPub',
            // missing ciphertext and nonce
          },
        }),
      );
      final (result, _, _) = await handleIncomingMessage(
        message: message,
        bridge: bridge,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        ownPeerId: _ownPeerId,
        ownPrivateKey: 'ownPrivKeyBase64',
      );

      expect(result, equals(HandleMessageResult.invalidMessage));
    });

    test('v2 duplicate msgId → invalidMessage', () async {
      final payload = _validPayload();
      bridge.decryptResponse = {'ok': true, 'plaintext': jsonEncode(payload)};

      const dupeId = 'duplicate-msg-id';
      final seenIds = <String>{dupeId};

      final message = _makeChatMessage(v2Message(payload, msgId: dupeId));
      final (result, _, _) = await handleIncomingMessage(
        message: message,
        bridge: bridge,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        ownPeerId: _ownPeerId,
        ownPrivateKey: 'ownPrivKeyBase64',
        seenMessageIds: seenIds,
      );

      expect(result, equals(HandleMessageResult.invalidMessage));
    });

    test('v2 ts older than 24h → invalidMessage', () async {
      final payload = _validPayload();
      bridge.decryptResponse = {'ok': true, 'plaintext': jsonEncode(payload)};

      final oldTs = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 25))
          .toIso8601String();
      final message = _makeChatMessage(v2Message(payload, ts: oldTs));
      final (result, _, _) = await handleIncomingMessage(
        message: message,
        bridge: bridge,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        ownPeerId: _ownPeerId,
        ownPrivateKey: 'ownPrivKeyBase64',
      );

      expect(result, equals(HandleMessageResult.invalidMessage));
    });

    test('v2 ts >5min in future → invalidMessage', () async {
      final payload = _validPayload();
      bridge.decryptResponse = {'ok': true, 'plaintext': jsonEncode(payload)};

      final futureTs = DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 10))
          .toIso8601String();
      final message = _makeChatMessage(v2Message(payload, ts: futureTs));
      final (result, _, _) = await handleIncomingMessage(
        message: message,
        bridge: bridge,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        ownPeerId: _ownPeerId,
        ownPrivateKey: 'ownPrivKeyBase64',
      );

      expect(result, equals(HandleMessageResult.invalidMessage));
    });

    test('v1 still works without ownPrivateKey', () async {
      final payload = _validPayload();
      final message = _makeChatMessage(_contactRequestMessage(payload));

      final (result, request, _) = await handleIncomingMessage(
        message: message,
        bridge: bridge,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        ownPeerId: _ownPeerId,
        // no ownPrivateKey
      );

      expect(result, equals(HandleMessageResult.contactRequest));
      expect(request, isNotNull);
    });

    test(
      'v1 with ownPrivateKey uses plaintext path (decrypt NOT called)',
      () async {
        final payload = _validPayload();
        final message = _makeChatMessage(_contactRequestMessage(payload));

        final (result, _, _) = await handleIncomingMessage(
          message: message,
          bridge: bridge,
          requestRepo: requestRepo,
          contactRepo: contactRepo,
          ownPeerId: _ownPeerId,
          ownPrivateKey: 'somePrivKey',
        );

        expect(result, equals(HandleMessageResult.contactRequest));
        expect(bridge.decryptCalled, isFalse);
      },
    );

    test(
      'v2 malformed decrypt: missing plaintext in ok:true → invalidMessage',
      () async {
        bridge.decryptResponse = {'ok': true};
        // No 'plaintext' key at all

        final message = _makeChatMessage(v2Message(_validPayload()));
        final (result, _, _) = await handleIncomingMessage(
          message: message,
          bridge: bridge,
          requestRepo: requestRepo,
          contactRepo: contactRepo,
          ownPeerId: _ownPeerId,
          ownPrivateKey: 'ownPrivKeyBase64',
        );

        expect(result, equals(HandleMessageResult.invalidMessage));
      },
    );

    test(
      'v2 malformed decrypt: non-string plaintext → invalidMessage',
      () async {
        bridge.decryptResponse = {'ok': true, 'plaintext': 12345};

        final message = _makeChatMessage(v2Message(_validPayload()));
        final (result, _, _) = await handleIncomingMessage(
          message: message,
          bridge: bridge,
          requestRepo: requestRepo,
          contactRepo: contactRepo,
          ownPeerId: _ownPeerId,
          ownPrivateKey: 'ownPrivKeyBase64',
        );

        expect(result, equals(HandleMessageResult.invalidMessage));
      },
    );

    test('v2 malformed decrypt: empty plaintext → invalidMessage', () async {
      bridge.decryptResponse = {'ok': true, 'plaintext': ''};

      final message = _makeChatMessage(v2Message(_validPayload()));
      final (result, _, _) = await handleIncomingMessage(
        message: message,
        bridge: bridge,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        ownPeerId: _ownPeerId,
        ownPrivateKey: 'ownPrivKeyBase64',
      );

      expect(result, equals(HandleMessageResult.invalidMessage));
    });
  });

  // -------------------------------------------------------------------------
  // 171: one-scan mutual auto-add (v2 recipient-bound requests add tap-free)
  // -------------------------------------------------------------------------
  group('171 one-scan auto-add', () {
    String v2Msg(Map<String, dynamic> payload, {String? msgId, String? ts}) {
      final id = msgId ?? 'auto-msg-${DateTime.now().microsecondsSinceEpoch}';
      final timestamp = ts ?? DateTime.now().toUtc().toIso8601String();
      return jsonEncode({
        'type': 'contact_request',
        'version': '2',
        'msgId': id,
        'ts': timestamp,
        'encrypted': {
          'ephemeralPublicKey': 'ephPubBase64',
          'ciphertext': 'ctBase64',
          'nonce': 'nonceBase64',
        },
      });
    }

    // TC-05: a NEW v2 verified request returns contactAutoAdded (Expected-RED
    // on HEAD — HEAD returns contactRequest) and stores the request pending.
    test('v2 new request returns contactAutoAdded', () async {
      final payload = _validPayload();
      bridge.decryptResponse = {'ok': true, 'plaintext': jsonEncode(payload)};

      final (result, request, _) = await handleIncomingMessage(
        message: _makeChatMessage(v2Msg(payload)),
        bridge: bridge,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        ownPeerId: _ownPeerId,
        ownPrivateKey: 'ownPrivKeyBase64',
      );

      expect(result, equals(HandleMessageResult.contactAutoAdded));
      // Request stored pending (audit) so the listener can accept+reciprocate.
      final stored = await requestRepo.getRequest(_senderPeerId);
      expect(stored, isNotNull);
      expect(stored!.status, equals(ContactRequestStatus.pending));
      expect(request, isNotNull);
    });

    // TC-07: a NEW v1 plaintext request stays on the manual dialog path (no
    // recipient binding → never auto-add). Mutation-first guard lock: PASSES
    // on HEAD; the mutation "drop the version=='2' gate" makes v1 auto-add and
    // reds this. v2-only is the INV-2 security gate.
    test('v1 plaintext new request stays on dialog (not auto-added)', () async {
      final (result, _, _) = await handleIncomingMessage(
        message: _makeChatMessage(_contactRequestMessage(_validPayload())),
        bridge: bridge,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        ownPeerId: _ownPeerId,
      );

      expect(result, equals(HandleMessageResult.contactRequest));
      expect(result, isNot(equals(HandleMessageResult.contactAutoAdded)));
    });

    // TC-09: a previously-declined peer is NOT resurrected by auto-add.
    // Mutation-first guard lock: PASSES on pristine HEAD (a declined peer falls
    // to contactRequest/dialog); the mutation "auto-add WITHOUT the
    // status==declined guard" lets it through and reds this.
    test('declined request is NOT resurrected by auto-add', () async {
      final declined = ContactRequestModel.fromP2PPayload(
        _validPayload(),
      ).copyWith(status: ContactRequestStatus.declined);
      await requestRepo.addRequest(declined);

      final payload = _validPayload();
      bridge.decryptResponse = {'ok': true, 'plaintext': jsonEncode(payload)};

      final (result, _, _) = await handleIncomingMessage(
        message: _makeChatMessage(v2Msg(payload)),
        bridge: bridge,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        ownPeerId: _ownPeerId,
        ownPrivateKey: 'ownPrivKeyBase64',
      );

      expect(result, isNot(equals(HandleMessageResult.contactAutoAdded)));
      expect(result, equals(HandleMessageResult.contactRequest));
      // No contact row created for a declined peer.
      expect(await contactRepo.contactExists(_senderPeerId), isFalse);
    });

    // TC-10: a blocked existing contact is short-circuited by step-8
    // (alreadyContact), never auto-added. Mutation-first: the COMPOUND mutation
    // "move auto-add ahead of step-8 AND remove the in-branch isBlocked guard"
    // reds this. Step-8 is the primary catch; the guard is defense-in-depth.
    test('blocked peer is NOT auto-added', () async {
      await contactRepo.addContact(
        ContactModel(
          peerId: _senderPeerId,
          publicKey: 'senderPublicKey',
          rendezvous: '/dns4/mknoun.xyz/tcp/4001/wss/p2p/relay',
          username: 'Alice',
          signature: 'sig',
          scannedAt: DateTime.now().toUtc().toIso8601String(),
          isBlocked: true,
        ),
      );

      final payload = _validPayload();
      bridge.decryptResponse = {'ok': true, 'plaintext': jsonEncode(payload)};

      final (result, _, _) = await handleIncomingMessage(
        message: _makeChatMessage(v2Msg(payload)),
        bridge: bridge,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        ownPeerId: _ownPeerId,
        ownPrivateKey: 'ownPrivKeyBase64',
      );

      expect(result, equals(HandleMessageResult.alreadyContact));
      expect(result, isNot(equals(HandleMessageResult.contactAutoAdded)));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 217 / CV-14 wake-token receive leg (A02 reconstruction, A03 store, A04
  // anti-rollback). INV-1 (no-break): a signed `wt` must never invalidate a
  // no-`wt` or old-peer request. INV-4 directionality is proven on device (A13a).
  // ─────────────────────────────────────────────────────────────────────────
  group('217 CV-14 wake-token receive', () {
    test('reconstruction includes wt', () async {
      // A request whose Ed25519 signature COVERED `wt`. The receiver must add
      // `wt` back to the reconstructed data or the signature check fails and the
      // request is dropped. (The fake verify captures the exact reconstructed
      // string; verifyResult stays true so the discriminator is the data.)
      final payload = _validPayload();
      payload['wt'] = 'wake-tok-for-me';
      final message = _makeChatMessage(_contactRequestMessage(payload));

      final (result, _, _) = await handleIncomingMessage(
        message: message,
        bridge: bridge,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        ownPeerId: _ownPeerId,
      );

      expect(bridge.lastVerifyData, contains('"wt":"wake-tok-for-me"'));
      // A wt-carrying request still verifies and proceeds (not dropped).
      expect(result, isNot(equals(HandleMessageResult.invalidMessage)));
    });

    test('a no-wt legacy request still verifies (PROD-CRITICAL preservation)',
        () async {
      final payload = _validPayload(); // no wt
      final message = _makeChatMessage(_contactRequestMessage(payload));

      final (result, _, _) = await handleIncomingMessage(
        message: message,
        bridge: bridge,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        ownPeerId: _ownPeerId,
      );

      // Conditional inclusion preserves the old shape: no `wt` in the data,
      // and the request still verifies (contact-add / key-rotation unbroken).
      expect(bridge.lastVerifyData, isNot(contains('wt')));
      expect(result, isNot(equals(HandleMessageResult.invalidMessage)));
    });

    test('stores wt for new, already-contact, AND silent-intro-recovered peers',
        () async {
      // (a) New-contact verified request → stored.
      final storeNew = _FakeReceivedWakeTokenStore();
      final pNew = _validPayload()..['wt'] = 'wt-new';
      await handleIncomingMessage(
        message: _makeChatMessage(_contactRequestMessage(pNew)),
        bridge: bridge,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        ownPeerId: _ownPeerId,
        receivedWakeTokenStore: storeNew,
      );
      expect((await storeNew.readTokenFor(_senderPeerId))?['tok'], 'wt-new');

      // (b) Already-contact (key-rotation branch) → still stored.
      contactRepo._contacts[_senderPeerId] = ContactModel(
        peerId: _senderPeerId,
        publicKey: 'senderPublicKey',
        rendezvous: '/dns4/mknoun.xyz/tcp/4001/wss/p2p/relay',
        username: 'Alice',
        signature: 'sig',
        scannedAt: '2024-01-01T00:00:00.000Z',
        mlKemPublicKey: 'oldKey',
      );
      final storeContact = _FakeReceivedWakeTokenStore();
      final pRot = _validPayload()
        ..['wt'] = 'wt-rot'
        ..['mlkem'] = 'newKey';
      await handleIncomingMessage(
        message: _makeChatMessage(_contactRequestMessage(pRot)),
        bridge: bridge,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        ownPeerId: _ownPeerId,
        receivedWakeTokenStore: storeContact,
      );
      expect((await storeContact.readTokenFor(_senderPeerId))?['tok'], 'wt-rot');

      // (c) Silent-intro-recovered → the function returns at the recovery block
      // BEFORE the contact checks; the wt must already have been stored.
      final storeIntro = _FakeReceivedWakeTokenStore();
      final pIntro = _validPayload()..['wt'] = 'wt-intro';
      final (result, _, _) = await handleIncomingMessage(
        message: _makeChatMessage(_contactRequestMessage(pIntro)),
        bridge: bridge,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        ownPeerId: _ownPeerId,
        receivedWakeTokenStore: storeIntro,
        attemptSilentIntroRecovery: (_) async =>
            IntroContactRequestRecoveryResult.recovered(
              introduction: _introModel(),
            ),
      );
      expect(result, HandleMessageResult.silentIntroRecovered);
      expect((await storeIntro.readTokenFor(_senderPeerId))?['tok'], 'wt-intro');
    });

    test('anti-rollback: an older-ts wt does not overwrite a newer stored token',
        () async {
      final store = _FakeReceivedWakeTokenStore();
      // Stored: {tok-current, ts=T2}.
      await store.writeTokenFor(
        _senderPeerId,
        'tok-current',
        '2026-07-06T12:00:00.000Z',
      );

      // Inbound ts=T1 < T2 → unchanged.
      final pOld = _validPayload()
        ..['wt'] = 'tok-old'
        ..['ts'] = '2026-07-06T10:00:00.000Z';
      await handleIncomingMessage(
        message: _makeChatMessage(_contactRequestMessage(pOld)),
        bridge: bridge,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        ownPeerId: _ownPeerId,
        receivedWakeTokenStore: store,
      );
      expect((await store.readTokenFor(_senderPeerId))?['tok'], 'tok-current');

      // Inbound ts=T3 > T2 → overwrites.
      final pNew = _validPayload()
        ..['wt'] = 'tok-new'
        ..['ts'] = '2026-07-06T14:00:00.000Z';
      await handleIncomingMessage(
        message: _makeChatMessage(_contactRequestMessage(pNew)),
        bridge: bridge,
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        ownPeerId: _ownPeerId,
        receivedWakeTokenStore: store,
      );
      expect((await store.readTokenFor(_senderPeerId))?['tok'], 'tok-new');
    });
  });
}
