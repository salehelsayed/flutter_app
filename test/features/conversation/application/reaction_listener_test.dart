import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/reaction_listener.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_payload.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../domain/repositories/fake_message_repository.dart';
import '../domain/repositories/fake_reaction_repository.dart';

const _senderPeerId = '12D3KooWSender';

ChatMessage _makeV2ReactionMessage({
  String action = 'add',
  String senderPeerId = _senderPeerId,
}) {
  return ChatMessage(
    from: senderPeerId,
    to: 'my-peer',
    content: ReactionPayload.buildEncryptedEnvelope(
      senderPeerId: senderPeerId,
      kem: 'k',
      ciphertext: 'c',
      nonce: 'n',
    ),
    timestamp: DateTime.now().toUtc().toIso8601String(),
    isIncoming: true,
  );
}

void main() {
  late StreamController<ChatMessage> reactionStreamController;
  late FakeBridge bridge;
  late FakeContactRepository contactRepo;
  late FakeMessageRepository messageRepo;
  late FakeReactionRepository reactionRepo;
  late ReactionListener listener;

  setUp(() {
    reactionStreamController = StreamController<ChatMessage>.broadcast();
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

    listener = ReactionListener(
      reactionStream: reactionStreamController.stream,
      messageRepo: messageRepo,
      reactionRepo: reactionRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      getOwnMlKemSecretKey: () async => 'own-secret-key',
    );
  });

  tearDown(() {
    listener.dispose();
    reactionStreamController.close();
  });

  group('ReactionListener', () {
    test(
      'processes add reaction and broadcasts to incomingReactionStream',
      () async {
        final received = <MessageReaction>[];
        listener.incomingReactionStream.listen(received.add);
        listener.start();

        reactionStreamController.add(_makeV2ReactionMessage());
        await Future.delayed(const Duration(milliseconds: 100));

        expect(received.length, 1);
        expect(received[0].emoji, '👍');
        expect(received[0].messageId, 'msg-1');
        expect(reactionRepo.saveReactionCallCount, 1);
      },
    );

    test(
      'processes remove reaction and broadcasts a removal change event',
      () async {
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

        final received = <ReactionChange>[];
        listener.incomingReactionChangeStream.listen(received.add);
        listener.start();

        reactionStreamController.add(_makeV2ReactionMessage(action: 'remove'));
        await Future.delayed(const Duration(milliseconds: 100));

        expect(received, hasLength(1));
        expect(received.single.type, ReactionChangeType.removed);
        expect(received.single.messageId, 'msg-1');
        expect(received.single.senderPeerId, _senderPeerId);
        expect(reactionRepo.removeReactionCallCount, 1);
      },
    );

    test('remove action does not emit to incomingReactionStream', () async {
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

      final received = <MessageReaction>[];
      listener.incomingReactionStream.listen(received.add);
      listener.start();

      reactionStreamController.add(_makeV2ReactionMessage(action: 'remove'));
      await Future.delayed(const Duration(milliseconds: 100));

      expect(received, isEmpty);
    });

    test('rejects blocked senders', () async {
      // Block the sender
      await contactRepo.blockContact(_senderPeerId);

      final received = <MessageReaction>[];
      listener.incomingReactionStream.listen(received.add);
      listener.start();

      reactionStreamController.add(_makeV2ReactionMessage());
      await Future.delayed(const Duration(milliseconds: 100));

      expect(received, isEmpty);
      expect(reactionRepo.saveReactionCallCount, 0);
    });

    test('does not broadcast for decryption failure', () async {
      bridge.responses['message.decrypt'] = {'ok': false, 'errorCode': 'err'};

      final received = <MessageReaction>[];
      listener.incomingReactionStream.listen(received.add);
      listener.start();

      reactionStreamController.add(_makeV2ReactionMessage());
      await Future.delayed(const Duration(milliseconds: 100));

      expect(received, isEmpty);
    });

    test('does not broadcast for unknown sender', () async {
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

      final received = <MessageReaction>[];
      listener.incomingReactionStream.listen(received.add);
      listener.start();

      reactionStreamController.add(
        ChatMessage(
          from: 'unknown-peer',
          to: 'my-peer',
          content: ReactionPayload.buildEncryptedEnvelope(
            senderPeerId: 'unknown-peer',
            kem: 'k',
            ciphertext: 'c',
            nonce: 'n',
          ),
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
        ),
      );
      await Future.delayed(const Duration(milliseconds: 100));

      expect(received, isEmpty);
    });

    test('does not broadcast when the target message is missing', () async {
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

      final received = <MessageReaction>[];
      final changes = <ReactionChange>[];
      listener.incomingReactionStream.listen(received.add);
      listener.incomingReactionChangeStream.listen(changes.add);
      listener.start();

      reactionStreamController.add(_makeV2ReactionMessage());
      await Future.delayed(const Duration(milliseconds: 100));

      expect(received, isEmpty);
      expect(changes, isEmpty);
      expect(reactionRepo.saveReactionCallCount, 0);
    });

    test('start is idempotent', () {
      listener.start();
      listener.start(); // no error
    });

    test('stop cancels subscription', () async {
      final received = <MessageReaction>[];
      listener.incomingReactionStream.listen(received.add);
      listener.start();
      listener.stop();

      reactionStreamController.add(_makeV2ReactionMessage());
      await Future.delayed(const Duration(milliseconds: 100));

      expect(received, isEmpty);
    });

    test('dispose closes stream', () {
      listener.start();
      listener.dispose();
      // No error on dispose
    });
  });
}
