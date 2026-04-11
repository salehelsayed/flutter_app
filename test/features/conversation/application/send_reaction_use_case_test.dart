import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/application/send_reaction_use_case.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../domain/repositories/fake_reaction_repository.dart';

void main() {
  late FakeP2PService p2pService;
  late FakeBridge bridge;
  late FakeReactionRepository reactionRepo;

  setUp(() {
    p2pService = FakeP2PService(
      initialState: const NodeState(isStarted: true, peerId: 'my-peer'),
    );
    bridge = FakeBridge(
      initialResponses: {
        'message.encrypt': {
          'ok': true,
          'kem': 'test-kem',
          'ciphertext': 'test-cipher',
          'nonce': 'test-nonce',
        },
      },
    );
    reactionRepo = FakeReactionRepository();
  });

  group('sendReaction', () {
    test('returns nodeNotRunning when node is stopped', () async {
      p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: false),
      );

      final (result, reaction) = await sendReaction(
        p2pService: p2pService,
        bridge: bridge,
        reactionRepo: reactionRepo,
        targetPeerId: 'peer-1',
        messageId: 'msg-1',
        emoji: '👍',
        senderPeerId: 'my-peer',
        recipientMlKemPublicKey: 'key-1',
      );

      expect(result, SendReactionResult.nodeNotRunning);
      expect(reaction, isNull);
    });

    test('returns encryptionFailed when encryption fails', () async {
      bridge.responses['message.encrypt'] = {'ok': false, 'errorCode': 'err'};

      final (result, reaction) = await sendReaction(
        p2pService: p2pService,
        bridge: bridge,
        reactionRepo: reactionRepo,
        targetPeerId: 'peer-1',
        messageId: 'msg-1',
        emoji: '👍',
        senderPeerId: 'my-peer',
        recipientMlKemPublicKey: 'key-1',
      );

      expect(result, SendReactionResult.encryptionFailed);
      expect(reaction, isNull);
    });

    test('returns encryptionFailed when bridge throws', () async {
      bridge.throwOnSend = true;

      final (result, reaction) = await sendReaction(
        p2pService: p2pService,
        bridge: bridge,
        reactionRepo: reactionRepo,
        targetPeerId: 'peer-1',
        messageId: 'msg-1',
        emoji: '👍',
        senderPeerId: 'my-peer',
        recipientMlKemPublicKey: 'key-1',
      );

      expect(result, SendReactionResult.encryptionFailed);
      expect(reaction, isNull);
    });

    test('returns success — encrypts, sends, persists locally', () async {
      final (result, reaction) = await sendReaction(
        p2pService: p2pService,
        bridge: bridge,
        reactionRepo: reactionRepo,
        targetPeerId: 'peer-1',
        messageId: 'msg-1',
        emoji: '👍',
        senderPeerId: 'my-peer',
        recipientMlKemPublicKey: 'key-1',
      );

      expect(result, SendReactionResult.success);
      expect(reaction, isNotNull);
      expect(reaction!.emoji, '👍');
      expect(reaction.messageId, 'msg-1');
      expect(reaction.senderPeerId, 'my-peer');

      // Verify persisted
      expect(reactionRepo.saveReactionCallCount, 1);
      expect(reactionRepo.lastSavedReaction!.emoji, '👍');

      // Verify sent
      expect(p2pService.sendMessageCallCount, 1);
    });

    test('falls back to inbox when direct send fails', () async {
      p2pService.sendMessageResult = false;

      final (result, _) = await sendReaction(
        p2pService: p2pService,
        bridge: bridge,
        reactionRepo: reactionRepo,
        targetPeerId: 'peer-1',
        messageId: 'msg-1',
        emoji: '👍',
        senderPeerId: 'my-peer',
        recipientMlKemPublicKey: 'key-1',
      );

      expect(result, SendReactionResult.success);
      expect(p2pService.storeInInboxCallCount, 1);
    });

    test('persists non-preset emoji payloads from the picker path', () async {
      final (result, reaction) = await sendReaction(
        p2pService: p2pService,
        bridge: bridge,
        reactionRepo: reactionRepo,
        targetPeerId: 'peer-1',
        messageId: 'msg-1',
        emoji: '😀',
        senderPeerId: 'my-peer',
        recipientMlKemPublicKey: 'key-1',
      );

      expect(result, SendReactionResult.success);
      expect(reaction, isNotNull);
      expect(reaction!.emoji, '😀');
      expect(reactionRepo.saveReactionCallCount, 1);
      expect(reactionRepo.lastSavedReaction!.emoji, '😀');
      expect(p2pService.sendMessageCallCount, 1);
    });

    test(
      'returns sendFailed and does not persist when direct send and inbox store both fail',
      () async {
        p2pService.sendMessageResult = false;
        p2pService.storeInInboxResult = false;

        final (result, reaction) = await sendReaction(
          p2pService: p2pService,
          bridge: bridge,
          reactionRepo: reactionRepo,
          targetPeerId: 'peer-1',
          messageId: 'msg-1',
          emoji: '👍',
          senderPeerId: 'my-peer',
          recipientMlKemPublicKey: 'key-1',
        );

        expect(result, SendReactionResult.sendFailed);
        expect(reaction, isNull);
        expect(p2pService.storeInInboxCallCount, 1);
        expect(reactionRepo.saveReactionCallCount, 0);
        expect(await reactionRepo.getReactionsForMessage('msg-1'), isEmpty);
      },
    );
  });
}
