import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/handle_incoming_reaction_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_payload.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../domain/repositories/fake_reaction_repository.dart';

const _senderPeerId = '12D3KooWSender';
const _ownMlKemSecretKey = 'own-secret-key';

ChatMessage _makeReactionMessage(String content) {
  return ChatMessage(
    from: _senderPeerId,
    to: 'my-peer',
    content: content,
    timestamp: DateTime.now().toUtc().toIso8601String(),
    isIncoming: true,
  );
}

void main() {
  late FakeBridge bridge;
  late FakeContactRepository contactRepo;
  late FakeReactionRepository reactionRepo;

  setUp(() {
    bridge = FakeBridge(initialResponses: {
      'message.decrypt': {
        'ok': true,
        'plaintext': jsonEncode({
          'id': 'r1',
          'messageId': 'msg-1',
          'emoji': '👍',
          'action': 'add',
          'senderPeerId': _senderPeerId,
          'timestamp': '2026-02-27T10:00:00.000Z',
        }),
      },
    });
    contactRepo = FakeContactRepository();
    contactRepo.seed([
      ContactModel(
        peerId: _senderPeerId,
        publicKey: 'pk',
        rendezvous: '/relay',
        username: 'Sender',
        signature: 'sig',
        scannedAt: '2026-01-01T00:00:00.000Z',
      ),
    ]);
    reactionRepo = FakeReactionRepository();
  });

  group('handleIncomingReaction', () {
    test('rejects non-reaction envelope', () async {
      final (result, _) = await handleIncomingReaction(
        message: _makeReactionMessage(jsonEncode({
          'type': 'chat_message',
          'version': '1',
          'payload': {},
        })),
        reactionRepo: reactionRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownMlKemSecretKey: _ownMlKemSecretKey,
      );

      expect(result, HandleReactionResult.notReaction);
    });

    test('rejects v1 reaction (encryption required)', () async {
      final v1 = const ReactionPayload(
        id: 'r1',
        messageId: 'msg-1',
        emoji: '👍',
        action: 'add',
        senderPeerId: _senderPeerId,
        timestamp: '2026-02-27T10:00:00.000Z',
      ).toJson();

      final (result, _) = await handleIncomingReaction(
        message: _makeReactionMessage(v1),
        reactionRepo: reactionRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownMlKemSecretKey: _ownMlKemSecretKey,
      );

      expect(result, HandleReactionResult.notReaction);
    });

    test('returns decryptionFailed when no own key', () async {
      final v2 = ReactionPayload.buildEncryptedEnvelope(
        senderPeerId: _senderPeerId,
        kem: 'k',
        ciphertext: 'c',
        nonce: 'n',
      );

      final (result, _) = await handleIncomingReaction(
        message: _makeReactionMessage(v2),
        reactionRepo: reactionRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownMlKemSecretKey: null,
      );

      expect(result, HandleReactionResult.decryptionFailed);
    });

    test('returns decryptionFailed when decrypt fails', () async {
      bridge.responses['message.decrypt'] = {'ok': false, 'errorCode': 'err'};

      final v2 = ReactionPayload.buildEncryptedEnvelope(
        senderPeerId: _senderPeerId,
        kem: 'k',
        ciphertext: 'c',
        nonce: 'n',
      );

      final (result, _) = await handleIncomingReaction(
        message: _makeReactionMessage(v2),
        reactionRepo: reactionRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownMlKemSecretKey: _ownMlKemSecretKey,
      );

      expect(result, HandleReactionResult.decryptionFailed);
    });

    test('returns unknownSender when sender not in contacts', () async {
      // Use a different sender that's not in contacts
      bridge.responses['message.decrypt'] = {
        'ok': true,
        'plaintext': jsonEncode({
          'id': 'r1',
          'messageId': 'msg-1',
          'emoji': '👍',
          'action': 'add',
          'senderPeerId': 'unknown-peer',
          'timestamp': '2026-02-27T10:00:00.000Z',
        }),
      };

      final v2 = ReactionPayload.buildEncryptedEnvelope(
        senderPeerId: 'unknown-peer',
        kem: 'k',
        ciphertext: 'c',
        nonce: 'n',
      );

      final (result, _) = await handleIncomingReaction(
        message: _makeReactionMessage(v2),
        reactionRepo: reactionRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownMlKemSecretKey: _ownMlKemSecretKey,
      );

      expect(result, HandleReactionResult.unknownSender);
    });

    test('add action — decrypts and persists reaction', () async {
      final v2 = ReactionPayload.buildEncryptedEnvelope(
        senderPeerId: _senderPeerId,
        kem: 'k',
        ciphertext: 'c',
        nonce: 'n',
      );

      final (result, reaction) = await handleIncomingReaction(
        message: _makeReactionMessage(v2),
        reactionRepo: reactionRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownMlKemSecretKey: _ownMlKemSecretKey,
      );

      expect(result, HandleReactionResult.success);
      expect(reaction, isNotNull);
      expect(reaction!.emoji, '👍');
      expect(reaction.messageId, 'msg-1');
      expect(reactionRepo.saveReactionCallCount, 1);
    });

    test('remove action — decrypts and deletes reaction', () async {
      // Pre-populate
      await reactionRepo.saveReaction(const MessageReaction(
        id: 'r1',
        messageId: 'msg-1',
        emoji: '👍',
        senderPeerId: _senderPeerId,
        timestamp: '2026-02-27T10:00:00.000Z',
        createdAt: '2026-02-27T10:00:01.000Z',
      ));

      bridge.responses['message.decrypt'] = {
        'ok': true,
        'plaintext': jsonEncode({
          'id': 'r2',
          'messageId': 'msg-1',
          'emoji': '👍',
          'action': 'remove',
          'senderPeerId': _senderPeerId,
          'timestamp': '2026-02-27T10:01:00.000Z',
        }),
      };

      final v2 = ReactionPayload.buildEncryptedEnvelope(
        senderPeerId: _senderPeerId,
        kem: 'k',
        ciphertext: 'c',
        nonce: 'n',
      );

      final (result, reaction) = await handleIncomingReaction(
        message: _makeReactionMessage(v2),
        reactionRepo: reactionRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownMlKemSecretKey: _ownMlKemSecretKey,
      );

      expect(result, HandleReactionResult.success);
      expect(reaction, isNull); // remove action returns null
      expect(reactionRepo.removeReactionCallCount, 1);

      final remaining = await reactionRepo.getReactionsForMessage('msg-1');
      expect(remaining, isEmpty);
    });
  });
}
