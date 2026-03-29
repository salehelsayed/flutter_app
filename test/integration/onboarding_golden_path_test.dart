import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contact_request/application/accept_and_reciprocate_use_case.dart';
import 'package:flutter_app/features/contact_request/application/accept_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/application/handle_incoming_message_use_case.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/identity/application/generate_identity_use_case.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

import '../core/bridge/fake_bridge.dart';
import '../features/identity/domain/repositories/fake_identity_repository.dart';
import '../shared/fakes/fake_p2p_network.dart';
import '../shared/fakes/in_memory_contact_request_repository.dart';
import '../shared/fakes/test_user.dart';

const _alicePeerId = '12D3KooWAliceGoldenPath000000000001';
const _bobPeerId = '12D3KooWBobGoldenPath00000000000002';

const _mnemonic12 =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

String _buildContactRequestEnvelope({
  required String peerId,
  required String publicKey,
  required String username,
  required String mlKemPublicKey,
}) {
  final payload = SplayTreeMap<String, dynamic>.from({
    'mlkem': mlKemPublicKey,
    'ns': peerId,
    'pk': publicKey,
    'rv': '/dns4/relay/tcp/443/p2p/relay',
    'ts': DateTime.now().toUtc().toIso8601String(),
    'un': username,
  });

  return jsonEncode({
    'type': 'contact_request',
    'version': '1',
    'payload': {...payload, 'sig': 'sig-$peerId'},
  });
}

ChatMessage _buildContactRequestMessage() {
  return ChatMessage(
    from: _bobPeerId,
    to: _alicePeerId,
    content: _buildContactRequestEnvelope(
      peerId: _bobPeerId,
      publicKey: 'pk-$_bobPeerId',
      username: 'Bob',
      mlKemPublicKey: 'mlkem-$_bobPeerId',
    ),
    timestamp: DateTime.now().toUtc().toIso8601String(),
    isIncoming: true,
  );
}

Future<void> _waitFor(
  FutureOr<bool> Function() condition, {
  String description = 'condition',
  Duration timeout = const Duration(seconds: 1),
  Duration poll = const Duration(milliseconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) {
      return;
    }
    await Future<void>.delayed(poll);
  }
  fail('Timed out waiting for $description');
}

void main() {
  test(
    'fresh identity creation, accepted contact request, and first message succeed in one flow',
    () async {
      final network = FakeP2PNetwork();
      final bridge = PassthroughCryptoBridge()
        ..responses['payload.verify'] = {'ok': true, 'valid': true}
        ..responses['payload.sign'] = {'ok': true, 'signature': 'test-sig'}
        ..responses['contactrequest.encrypt'] = {
          'ok': true,
          'ephemeralPublicKey': 'ephPub',
          'ciphertext': 'ct',
          'nonce': 'nonce',
        };
      final identityRepo = FakeIdentityRepository();
      final requestRepo = InMemoryContactRequestRepository();

      final generateResult = await generateNewIdentity(
        callGenerate: () async => {
          'ok': true,
          'identity': {
            'peerId': _alicePeerId,
            'publicKey': 'pk-$_alicePeerId',
            'privateKey': 'sk-$_alicePeerId',
            'mnemonic12': _mnemonic12,
            'username': 'Alice',
            'createdAt': '2026-03-26T08:00:00Z',
            'updatedAt': '2026-03-26T08:00:00Z',
          },
        },
        callMlKemKeygen: () async => {
          'ok': true,
          'publicKey': 'mlkem-$_alicePeerId',
          'secretKey': 'mlkem-sk-$_alicePeerId',
        },
        repo: identityRepo,
      );

      expect(generateResult, GenerateIdentityResult.success);
      expect(identityRepo.saveIdentityCallCount, 1);

      final aliceIdentity = await identityRepo.loadIdentity();
      expect(aliceIdentity, isNotNull);
      expect(aliceIdentity!.peerId, _alicePeerId);
      expect(aliceIdentity.mlKemPublicKey, 'mlkem-$_alicePeerId');

      final alice = TestUser.create(
        peerId: aliceIdentity.peerId,
        username: 'Alice',
        network: network,
        bridge: bridge,
      );
      final bob = TestUser.create(
        peerId: _bobPeerId,
        username: 'Bob',
        network: network,
      );
      bob.addContact(alice);

      final (incomingResult, request, _) = await handleIncomingMessage(
        message: _buildContactRequestMessage(),
        bridge: bridge,
        requestRepo: requestRepo,
        contactRepo: alice.contactRepo,
        ownPeerId: alice.peerId,
      );

      expect(incomingResult, HandleMessageResult.contactRequest);
      expect(request, isNotNull);
      expect(request!.status, ContactRequestStatus.pending);
      expect(request.peerId, _bobPeerId);

      final acceptResult = await acceptAndReciprocateContactRequest(
        requestRepo: requestRepo,
        contactRepo: alice.contactRepo,
        peerId: _bobPeerId,
        p2pService: alice.p2pService,
        identityRepo: identityRepo,
        bridge: bridge,
        downloadProfilePictureFn:
            ({
              required bridge,
              required contactRepo,
              required ownerPeerId,
              required avatarVersion,
            }) async {
              return contactRepo.getContact(ownerPeerId);
            },
      );

      expect(acceptResult, AcceptContactRequestResult.success);
      await _waitFor(
        () async => bridge.commandLog.contains('contactrequest.encrypt'),
        description: 'reciprocal contact request encryption',
      );

      final acceptedContact = await alice.contactRepo.getContact(_bobPeerId);
      expect(acceptedContact, isNotNull);
      expect(acceptedContact!.username, 'Bob');
      expect(acceptedContact.mlKemPublicKey, 'mlkem-$_bobPeerId');

      bob.start();

      final (sendResult, sentMessage) = await alice.sendMessage(
        _bobPeerId,
        'Hello Bob',
      );

      expect(sendResult, SendChatMessageResult.success);
      expect(sentMessage, isNotNull);
      expect(sentMessage!.status, 'delivered');
      expect(sentMessage.transport, anyOf('direct', 'relay', 'local'));

      await _waitFor(
        () async =>
            (await bob.messageRepo.getMessageCountForContact(_alicePeerId)) ==
            1,
        description: 'Bob to persist the first message',
      );

      final aliceConversation = await alice.loadConversationWith(_bobPeerId);
      final bobConversation = await bob.loadConversationWith(_alicePeerId);

      expect(aliceConversation, hasLength(1));
      expect(aliceConversation.single.text, 'Hello Bob');
      expect(aliceConversation.single.isIncoming, isFalse);

      expect(bobConversation, hasLength(1));
      expect(bobConversation.single.text, 'Hello Bob');
      expect(bobConversation.single.isIncoming, isTrue);
      expect(bobConversation.single.contactPeerId, _alicePeerId);

      expect(
        bridge.commandLog,
        containsAll([
          'payload.verify',
          'contactrequest.encrypt',
          'message.encrypt',
        ]),
      );
    },
  );
}
