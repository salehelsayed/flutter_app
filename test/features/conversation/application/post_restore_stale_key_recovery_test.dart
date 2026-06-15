import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/secure_storage/ml_kem_secret_ring.dart';
import 'package:flutter_app/features/contact_request/application/mlkem_reannounce_marker.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/handle_incoming_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/identity/application/restore_identity_use_case.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository_impl.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../shared/fakes/in_memory_message_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

const _senderPeerId = 'sender-peer-stale-key-12345';

class _SeededContactRepository implements ContactRepository {
  final Map<String, ContactModel> _contacts = {};

  void seed(ContactModel contact) => _contacts[contact.peerId] = contact;

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
  Future<List<ContactModel>> getAllContacts() async =>
      _contacts.values.toList();
  @override
  Future<void> deleteContact(String peerId) async {
    _contacts.remove(peerId);
  }

  @override
  Future<int> getContactCount() async => _contacts.length;
  @override
  Future<void> archiveContact(String peerId) async {}
  @override
  Future<void> unarchiveContact(String peerId) async {}
  @override
  Future<List<ContactModel>> getActiveContacts() async =>
      _contacts.values.where((c) => !c.isArchived).toList();
  @override
  Future<List<ContactModel>> getArchivedContacts() async =>
      _contacts.values.where((c) => c.isArchived).toList();
  @override
  Future<void> blockContact(String peerId) async {}
  @override
  Future<void> unblockContact(String peerId) async {}
  @override
  Future<void> dismissIntroBanner(String peerId) async {}
  @override
  Future<void> setIntrosSentAt(String peerId, String timestamp) async {}
}

class _RecordingMessageRepository extends InMemoryMessageRepository {
  final List<ConversationMessage> saved = [];

  @override
  Future<void> saveMessage(ConversationMessage message) async {
    saved.add(message);
    await super.saveMessage(message);
  }
}

/// Decrypt bridge keyed by the secret it is asked to use — simulates real
/// ML-KEM semantics where only the matching secret can open the envelope.
class _KeyedDecryptBridge implements Bridge {
  final String correctSecret;
  final String plaintext;
  int decryptCallCount = 0;
  final List<String> attemptedSecrets = [];

  _KeyedDecryptBridge({required this.correctSecret, required this.plaintext});

  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message) as Map<String, dynamic>;
    if (request['cmd'] == 'message.decrypt') {
      decryptCallCount++;
      final payload = request['payload'] as Map<String, dynamic>;
      final secret = payload['secretKey'] as String;
      attemptedSecrets.add(secret);
      if (secret == correctSecret) {
        return jsonEncode({'ok': true, 'plaintext': plaintext});
      }
      return jsonEncode({
        'ok': false,
        'errorCode': 'DECRYPT_FAILED',
        'errorMessage': 'message authentication failed',
      });
    }
    return jsonEncode({'ok': true});
  }

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
  void Function(ChatMessage)? onMessageReceived;
  @override
  void Function(ConnectionState)? onPeerConnected;
  @override
  void Function(ConnectionState)? onPeerDisconnected;
  @override
  void Function(List<String>, List<String>)? onAddressesUpdated;
  @override
  void Function(Map<String, dynamic>)? onRelayStateChanged;
  @override
  void Function(Map<String, dynamic>)? onGroupMessageReceived;
  @override
  void Function(Map<String, dynamic>)? onGroupReactionReceived;
}

ChatMessage _v2Message() {
  return ChatMessage(
    from: _senderPeerId,
    to: 'own-peer',
    content: jsonEncode({
      'type': 'chat_message',
      'version': '2',
      'senderPeerId': _senderPeerId,
      'encrypted': {
        'kem': 'kem-blob',
        'ciphertext': 'cipher-blob',
        'nonce': 'nonce-blob',
      },
    }),
    timestamp: '2026-06-12T10:00:00.000Z',
    isIncoming: true,
  );
}

String _chatPlaintext() => jsonEncode({
  'id': 'msg-old-key-001',
  'text': 'Sent to the pre-restore key',
  'senderPeerId': _senderPeerId,
  'senderUsername': 'Alice',
  'timestamp': '2026-06-12T10:00:00.000Z',
});

ContactModel _aliceContact() => ContactModel(
  peerId: _senderPeerId,
  publicKey: 'pk-alice',
  rendezvous: '/dns4/relay/tcp/443/p2p/relay',
  username: 'Alice',
  signature: 'sig',
  scannedAt: '2026-01-01T00:00:00.000Z',
);

IdentityModel _identity({required String mlKemSecretKey}) => IdentityModel(
  peerId: 'own-peer',
  publicKey: 'own-pk',
  privateKey: 'own-sk',
  mnemonic12:
      'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
  mlKemPublicKey: 'mlkem-pk-$mlKemSecretKey',
  mlKemSecretKey: mlKemSecretKey,
  createdAt: '2026-01-01T00:00:00.000Z',
  updatedAt: '2026-01-01T00:00:00.000Z',
);

void main() {
  group('B-2 restore records the re-announce marker', () {
    test(
      'restore records re-announce pending marker for all active contacts',
      () async {
        final secureKeyStore = FakeSecureKeyStore();
        final contactRepo = _SeededContactRepository()
          ..seed(_aliceContact())
          ..seed(
            ContactModel(
              peerId: 'blocked-peer-9999999999',
              publicKey: 'pk-b',
              rendezvous: '/dns4/relay/tcp/443/p2p/relay',
              username: 'Blocked',
              signature: 'sig',
              scannedAt: '2026-01-01T00:00:00.000Z',
              isBlocked: true,
            ),
          );

        final result = await restoreIdentityFromMnemonic(
          input:
              'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
          callRestore: (mnemonic) async => {
            'ok': true,
            'identity': {
              'peerId': 'own-peer',
              'publicKey': 'own-pk',
              'privateKey': 'own-sk',
              'mnemonic12': mnemonic,
              'createdAt': '2026-06-12T10:00:00.000Z',
              'updatedAt': '2026-06-12T10:00:00.000Z',
            },
          },
          callMlKemKeygen: () async => {
            'ok': true,
            'publicKey': 'new-mlkem-pk',
            'secretKey': 'new-mlkem-sk',
          },
          repo: FakeIdentityRepository(),
          secureKeyStore: secureKeyStore,
          contactRepo: contactRepo,
        );

        expect(result, RestoreIdentityResult.success);
        final marker = await readMlKemReannounceMarker(secureKeyStore);
        expect(marker, [_senderPeerId]);
      },
    );
  });

  group('B-4 secret-key ring write', () {
    late FakeSecureKeyStore secureKeyStore;
    late IdentityRepositoryImpl repo;

    setUp(() {
      secureKeyStore = FakeSecureKeyStore();
      repo = IdentityRepositoryImpl(
        dbLoadIdentityRow: () async => null,
        dbUpsertIdentityRow: (_) async {},
        secureKeyStore: secureKeyStore,
      );
    });

    test('saveIdentity pushes previous differing ML-KEM secret onto the ring',
        () async {
      await repo.saveIdentity(_identity(mlKemSecretKey: 'secret-A'));
      await repo.saveIdentity(_identity(mlKemSecretKey: 'secret-B'));

      final ring = await loadMlKemSecretKeyRing(secureKeyStore);
      expect(ring, ['secret-A']);
    });

    test('ring is capped at 3, newest first', () async {
      for (final secret in ['s1', 's2', 's3', 's4', 's5']) {
        await repo.saveIdentity(_identity(mlKemSecretKey: secret));
      }

      final ring = await loadMlKemSecretKeyRing(secureKeyStore);
      expect(ring, ['s4', 's3', 's2']);
    });

    test('saveIdentity with identical secret does not grow the ring', () async {
      await repo.saveIdentity(_identity(mlKemSecretKey: 'secret-A'));
      await repo.saveIdentity(_identity(mlKemSecretKey: 'secret-A'));

      final ring = await loadMlKemSecretKeyRing(secureKeyStore);
      expect(ring, isEmpty);
    });
  });

  group('B-5 decrypt fallback through the ring', () {
    test(
      'falls back to ring secret when primary decrypt fails cryptographically',
      () async {
        final bridge = _KeyedDecryptBridge(
          correctSecret: 'old-secret',
          plaintext: _chatPlaintext(),
        );
        final messageRepo = _RecordingMessageRepository();
        final contactRepo = _SeededContactRepository()..seed(_aliceContact());

        final (result, message, _) = await handleIncomingChatMessage(
          message: _v2Message(),
          messageRepo: messageRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownMlKemSecretKey: 'new-secret',
          fallbackMlKemSecretKeys: const ['old-secret'],
        );

        expect(result, HandleChatMessageResult.chatMessage);
        expect(message, isNotNull);
        expect(message!.text, 'Sent to the pre-restore key');
        expect(bridge.decryptCallCount, 2);
        expect(bridge.attemptedSecrets, ['new-secret', 'old-secret']);
        expect(messageRepo.saved, hasLength(1));
      },
    );

    test('does not try ring on transient (BRIDGE_TIMEOUT) failure', () async {
      final bridge = _TimeoutDecryptBridge();
      final messageRepo = _RecordingMessageRepository();
      final contactRepo = _SeededContactRepository()..seed(_aliceContact());

      final (result, message, _) = await handleIncomingChatMessage(
        message: _v2Message(),
        messageRepo: messageRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownMlKemSecretKey: 'new-secret',
        fallbackMlKemSecretKeys: const ['old-secret'],
      );

      expect(result, HandleChatMessageResult.decryptionDeferred);
      expect(message, isNull);
      expect(
        bridge.decryptCallCount,
        1,
        reason: 'transient failure must not burn ring attempts',
      );
    });

    test('listener passes ring to use case', () async {
      final bridge = _KeyedDecryptBridge(
        correctSecret: 'old-secret',
        plaintext: _chatPlaintext(),
      );
      final messageRepo = _RecordingMessageRepository();
      final contactRepo = _SeededContactRepository()..seed(_aliceContact());

      final listener = ChatMessageListener(
        chatMessageStream: const Stream<ChatMessage>.empty(),
        messageRepo: messageRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        getOwnMlKemSecretKey: () async => 'new-secret',
        getOwnMlKemSecretKeyRing: () async => const ['old-secret'],
      );

      final outcome = await listener.processIncomingMessage(_v2Message());

      expect(outcome.state, ChatMessageProcessState.stored);
      expect(bridge.attemptedSecrets, ['new-secret', 'old-secret']);
    });
  });

  group('B-6 end-to-end same-device story', () {
    test(
      'message encrypted to pre-restore key decrypts via ring after silent '
      'recovery',
      () async {
        // 1. Old identity saved with secret-OLD.
        final secureKeyStore = FakeSecureKeyStore();
        final identityRepo = IdentityRepositoryImpl(
          dbLoadIdentityRow: () async => null,
          dbUpsertIdentityRow: (_) async {},
          secureKeyStore: secureKeyStore,
        );
        await repoSave(identityRepo, 'old-mlkem-secret');

        // 2. Silent recovery regenerates the pair — the ring keeps the old
        //    secret that would otherwise be destroyed.
        await repoSave(identityRepo, 'new-mlkem-secret');
        final ring = await loadMlKemSecretKeyRing(secureKeyStore);
        expect(ring, ['old-mlkem-secret']);

        // 3. An in-flight message encrypted to the OLD public key arrives.
        final bridge = _KeyedDecryptBridge(
          correctSecret: 'old-mlkem-secret',
          plaintext: _chatPlaintext(),
        );
        final messageRepo = _RecordingMessageRepository();
        final contactRepo = _SeededContactRepository()..seed(_aliceContact());

        final (result, message, _) = await handleIncomingChatMessage(
          message: _v2Message(),
          messageRepo: messageRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownMlKemSecretKey: 'new-mlkem-secret',
          fallbackMlKemSecretKeys: ring,
        );

        // 4. Stored, not quarantined.
        expect(result, HandleChatMessageResult.chatMessage);
        expect(message!.text, 'Sent to the pre-restore key');
        expect(messageRepo.saved, hasLength(1));
      },
    );
  });
}

Future<void> repoSave(IdentityRepositoryImpl repo, String secret) =>
    repo.saveIdentity(_identity(mlKemSecretKey: secret));

class _TimeoutDecryptBridge extends _KeyedDecryptBridge {
  _TimeoutDecryptBridge() : super(correctSecret: 'never', plaintext: '{}');

  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message) as Map<String, dynamic>;
    if (request['cmd'] == 'message.decrypt') {
      decryptCallCount++;
      return jsonEncode({
        'ok': false,
        'errorCode': 'BRIDGE_TIMEOUT',
        'errorMessage': 'Bridge call timed out after 10s',
      });
    }
    return jsonEncode({'ok': true});
  }
}
