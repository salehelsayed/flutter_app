import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/handle_incoming_reaction_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_payload.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../domain/repositories/fake_message_repository.dart';
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
  late FakeMessageRepository messageRepo;
  late FakeReactionRepository reactionRepo;

  setUp(() {
    bridge = FakeBridge(
      initialResponses: {
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
      },
    );
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
    messageRepo = FakeMessageRepository()
      ..seed([
        const ConversationMessage(
          id: 'msg-1',
          contactPeerId: _senderPeerId,
          senderPeerId: _senderPeerId,
          text: 'hello',
          timestamp: '2026-02-27T10:00:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-02-27T10:00:00.000Z',
        ),
      ]);
    reactionRepo = FakeReactionRepository();
  });

  group('handleIncomingReaction', () {
    test('rejects non-reaction envelope', () async {
      final (result, _) = await handleIncomingReaction(
        message: _makeReactionMessage(
          jsonEncode({'type': 'chat_message', 'version': '1', 'payload': {}}),
        ),
        messageRepo: messageRepo,
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
        messageRepo: messageRepo,
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
        message: ChatMessage(
          from: 'unknown-peer',
          to: 'my-peer',
          content: v2,
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
        ),
        messageRepo: messageRepo,
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
        message: ChatMessage(
          from: 'unknown-peer',
          to: 'my-peer',
          content: v2,
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
        ),
        messageRepo: messageRepo,
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
        message: ChatMessage(
          from: 'unknown-peer',
          to: 'my-peer',
          content: v2,
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
        ),
        messageRepo: messageRepo,
        reactionRepo: reactionRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownMlKemSecretKey: _ownMlKemSecretKey,
      );

      expect(result, HandleReactionResult.unknownSender);
    });

    test('returns senderMismatch when envelope sender disagrees with payload sender', () async {
      final v2 = ReactionPayload.buildEncryptedEnvelope(
        senderPeerId: _senderPeerId,
        kem: 'k',
        ciphertext: 'c',
        nonce: 'n',
      );

      final (result, change) = await handleIncomingReaction(
        message: ChatMessage(
          from: 'different-envelope-sender',
          to: 'my-peer',
          content: v2,
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
        ),
        messageRepo: messageRepo,
        reactionRepo: reactionRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownMlKemSecretKey: _ownMlKemSecretKey,
      );

      expect(result, HandleReactionResult.senderMismatch);
      expect(change, isNull);
      expect(reactionRepo.saveReactionCallCount, 0);
    });

    test(
      'returns senderMismatch when encrypted envelope sender disagrees with payload sender',
      () async {
        final v2 = ReactionPayload.buildEncryptedEnvelope(
          senderPeerId: 'different-envelope-sender',
          kem: 'k',
          ciphertext: 'c',
          nonce: 'n',
        );

        final (result, change) = await handleIncomingReaction(
          message: _makeReactionMessage(v2),
          messageRepo: messageRepo,
          reactionRepo: reactionRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownMlKemSecretKey: _ownMlKemSecretKey,
        );

        expect(result, HandleReactionResult.senderMismatch);
        expect(change, isNull);
        expect(reactionRepo.saveReactionCallCount, 0);
      },
    );

    test('add action — decrypts and persists reaction', () async {
      final v2 = ReactionPayload.buildEncryptedEnvelope(
        senderPeerId: _senderPeerId,
        kem: 'k',
        ciphertext: 'c',
        nonce: 'n',
      );

      final (result, change) = await handleIncomingReaction(
        message: _makeReactionMessage(v2),
        messageRepo: messageRepo,
        reactionRepo: reactionRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownMlKemSecretKey: _ownMlKemSecretKey,
      );

      expect(result, HandleReactionResult.success);
      expect(change, isNotNull);
      expect(change!.type, ReactionChangeType.upserted);
      expect(change.reaction!.emoji, '👍');
      expect(change.messageId, 'msg-1');
      expect(reactionRepo.saveReactionCallCount, 1);
    });

    test('duplicate add deliveries stay idempotent', () async {
      final v2 = ReactionPayload.buildEncryptedEnvelope(
        senderPeerId: _senderPeerId,
        kem: 'k',
        ciphertext: 'c',
        nonce: 'n',
      );

      final first = await handleIncomingReaction(
        message: _makeReactionMessage(v2),
        messageRepo: messageRepo,
        reactionRepo: reactionRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownMlKemSecretKey: _ownMlKemSecretKey,
      );
      final second = await handleIncomingReaction(
        message: _makeReactionMessage(v2),
        messageRepo: messageRepo,
        reactionRepo: reactionRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownMlKemSecretKey: _ownMlKemSecretKey,
      );

      expect(first.$1, HandleReactionResult.success);
      expect(second.$1, HandleReactionResult.success);
      expect(reactionRepo.saveReactionCallCount, 2);

      final stored = await reactionRepo.getReactionsForMessage('msg-1');
      expect(stored, hasLength(1));
      expect(stored.single.senderPeerId, _senderPeerId);
      expect(stored.single.emoji, '👍');
    });

    test('remove action — decrypts and deletes reaction', () async {
      // Pre-populate
      await reactionRepo.saveReaction(
        const MessageReaction(
          id: 'r1',
          messageId: 'msg-1',
          emoji: '👍',
          senderPeerId: _senderPeerId,
          timestamp: '2026-02-27T10:00:00.000Z',
          createdAt: '2026-02-27T10:00:01.000Z',
        ),
      );

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

      final (result, change) = await handleIncomingReaction(
        message: _makeReactionMessage(v2),
        messageRepo: messageRepo,
        reactionRepo: reactionRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownMlKemSecretKey: _ownMlKemSecretKey,
      );

      expect(result, HandleReactionResult.success);
      expect(change, isNotNull);
      expect(change!.type, ReactionChangeType.removed);
      expect(change.messageId, 'msg-1');
      expect(change.senderPeerId, _senderPeerId);
      expect(change.reaction, isNull);
      expect(reactionRepo.removeReactionCallCount, 1);

      final remaining = await reactionRepo.getReactionsForMessage('msg-1');
      expect(remaining, isEmpty);
    });

    test('duplicate remove deliveries stay idempotent', () async {
      await reactionRepo.saveReaction(
        const MessageReaction(
          id: 'r1',
          messageId: 'msg-1',
          emoji: '👍',
          senderPeerId: _senderPeerId,
          timestamp: '2026-02-27T10:00:00.000Z',
          createdAt: '2026-02-27T10:00:01.000Z',
        ),
      );

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

      final first = await handleIncomingReaction(
        message: _makeReactionMessage(v2),
        messageRepo: messageRepo,
        reactionRepo: reactionRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownMlKemSecretKey: _ownMlKemSecretKey,
      );
      final second = await handleIncomingReaction(
        message: _makeReactionMessage(v2),
        messageRepo: messageRepo,
        reactionRepo: reactionRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownMlKemSecretKey: _ownMlKemSecretKey,
      );

      expect(first.$1, HandleReactionResult.success);
      expect(second.$1, HandleReactionResult.success);
      expect(reactionRepo.removeReactionCallCount, 2);
      expect(await reactionRepo.getReactionsForMessage('msg-1'), isEmpty);
    });

    test('stale remove does not erase a newer stored reaction', () async {
      await reactionRepo.saveReaction(
        const MessageReaction(
          id: 'r-newer',
          messageId: 'msg-1',
          emoji: '❤️',
          senderPeerId: _senderPeerId,
          timestamp: '2026-02-27T10:02:00.000Z',
          createdAt: '2026-02-27T10:02:01.000Z',
        ),
      );

      bridge.responses['message.decrypt'] = {
        'ok': true,
        'plaintext': jsonEncode({
          'id': 'r-older-remove',
          'messageId': 'msg-1',
          'emoji': '❤️',
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

      final (result, change) = await handleIncomingReaction(
        message: _makeReactionMessage(v2),
        messageRepo: messageRepo,
        reactionRepo: reactionRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownMlKemSecretKey: _ownMlKemSecretKey,
      );

      expect(result, HandleReactionResult.success);
      expect(change, isNull);
      expect(reactionRepo.removeReactionCallCount, 0);

      final stored = await reactionRepo.getReactionsForMessage('msg-1');
      expect(stored, hasLength(1));
      expect(stored.single.emoji, '❤️');
      expect(stored.single.timestamp, '2026-02-27T10:02:00.000Z');
    });

    test('stale add does not replace a newer stored reaction', () async {
      await reactionRepo.saveReaction(
        const MessageReaction(
          id: 'r-newer',
          messageId: 'msg-1',
          emoji: '❤️',
          senderPeerId: _senderPeerId,
          timestamp: '2026-02-27T10:02:00.000Z',
          createdAt: '2026-02-27T10:02:01.000Z',
        ),
      );

      bridge.responses['message.decrypt'] = {
        'ok': true,
        'plaintext': jsonEncode({
          'id': 'r-older-add',
          'messageId': 'msg-1',
          'emoji': '👍',
          'action': 'add',
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

      final (result, change) = await handleIncomingReaction(
        message: _makeReactionMessage(v2),
        messageRepo: messageRepo,
        reactionRepo: reactionRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownMlKemSecretKey: _ownMlKemSecretKey,
      );

      expect(result, HandleReactionResult.success);
      expect(change, isNull);
      expect(reactionRepo.saveReactionCallCount, 1);
      expect(reactionRepo.lastSavedReaction?.emoji, '❤️');

      final stored = await reactionRepo.getReactionsForMessage('msg-1');
      expect(stored, hasLength(1));
      expect(stored.single.emoji, '❤️');
      expect(stored.single.timestamp, '2026-02-27T10:02:00.000Z');
    });

    test('ignores add action when the target message is missing', () async {
      bridge.responses['message.decrypt'] = {
        'ok': true,
        'plaintext': jsonEncode({
          'id': 'r1',
          'messageId': 'missing-msg',
          'emoji': '👍',
          'action': 'add',
          'senderPeerId': _senderPeerId,
          'timestamp': '2026-02-27T10:00:00.000Z',
        }),
      };

      final v2 = ReactionPayload.buildEncryptedEnvelope(
        senderPeerId: _senderPeerId,
        kem: 'k',
        ciphertext: 'c',
        nonce: 'n',
      );

      final (result, change) = await handleIncomingReaction(
        message: _makeReactionMessage(v2),
        messageRepo: messageRepo,
        reactionRepo: reactionRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownMlKemSecretKey: _ownMlKemSecretKey,
      );

      expect(result, HandleReactionResult.targetUnavailable);
      expect(change, isNull);
      expect(reactionRepo.saveReactionCallCount, 0);
      expect(await reactionRepo.getReactionsForMessage('missing-msg'), isEmpty);
    });

    test('ignores add action when the target message is deleted', () async {
      messageRepo.seed([
        const ConversationMessage(
          id: 'msg-1',
          contactPeerId: _senderPeerId,
          senderPeerId: _senderPeerId,
          text: 'deleted',
          timestamp: '2026-02-27T10:00:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-02-27T10:00:00.000Z',
          deletedAt: '2026-02-27T10:05:00.000Z',
          deletedByPeerId: _senderPeerId,
        ),
      ]);

      final v2 = ReactionPayload.buildEncryptedEnvelope(
        senderPeerId: _senderPeerId,
        kem: 'k',
        ciphertext: 'c',
        nonce: 'n',
      );

      final (result, change) = await handleIncomingReaction(
        message: _makeReactionMessage(v2),
        messageRepo: messageRepo,
        reactionRepo: reactionRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownMlKemSecretKey: _ownMlKemSecretKey,
      );

      expect(result, HandleReactionResult.targetUnavailable);
      expect(change, isNull);
      expect(reactionRepo.saveReactionCallCount, 0);
      expect(await reactionRepo.getReactionsForMessage('msg-1'), isEmpty);
    });
  });
}
