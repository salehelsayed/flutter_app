import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/application/remove_reaction_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
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

  group('removeReaction', () {
    test('returns nodeNotRunning when node is stopped', () async {
      p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: false),
      );

      final result = await removeReaction(
        p2pService: p2pService,
        bridge: bridge,
        reactionRepo: reactionRepo,
        targetPeerId: 'peer-1',
        messageId: 'msg-1',
        emoji: '👍',
        senderPeerId: 'my-peer',
        recipientMlKemPublicKey: 'key-1',
      );

      expect(result, RemoveReactionResult.nodeNotRunning);
    });

    test('returns encryptionFailed when encryption fails', () async {
      bridge.responses['message.encrypt'] = {'ok': false, 'errorCode': 'err'};

      final result = await removeReaction(
        p2pService: p2pService,
        bridge: bridge,
        reactionRepo: reactionRepo,
        targetPeerId: 'peer-1',
        messageId: 'msg-1',
        emoji: '👍',
        senderPeerId: 'my-peer',
        recipientMlKemPublicKey: 'key-1',
      );

      expect(result, RemoveReactionResult.encryptionFailed);
    });

    test('returns success — encrypts, sends, deletes locally', () async {
      // Pre-populate with a reaction to remove
      await reactionRepo.saveReaction(
        const MessageReaction(
          id: 'r1',
          messageId: 'msg-1',
          emoji: '👍',
          senderPeerId: 'my-peer',
          timestamp: '2026-02-27T10:00:00.000Z',
          createdAt: '2026-02-27T10:00:01.000Z',
        ),
      );

      final result = await removeReaction(
        p2pService: p2pService,
        bridge: bridge,
        reactionRepo: reactionRepo,
        targetPeerId: 'peer-1',
        messageId: 'msg-1',
        emoji: '👍',
        senderPeerId: 'my-peer',
        recipientMlKemPublicKey: 'key-1',
      );

      expect(result, RemoveReactionResult.success);
      expect(reactionRepo.removeReactionCallCount, 1);

      // Verify local reaction deleted
      final remaining = await reactionRepo.getReactionsForMessage('msg-1');
      expect(remaining, isEmpty);
    });

    test('falls back to inbox when direct send fails', () async {
      p2pService.sendMessageResult = false;

      final result = await removeReaction(
        p2pService: p2pService,
        bridge: bridge,
        reactionRepo: reactionRepo,
        targetPeerId: 'peer-1',
        messageId: 'msg-1',
        emoji: '👍',
        senderPeerId: 'my-peer',
        recipientMlKemPublicKey: 'key-1',
      );

      expect(result, RemoveReactionResult.success);
      expect(p2pService.storeInInboxCallCount, 1);
    });

    test(
      'returns sendFailed and does not delete locally when direct send and inbox store both fail',
      () async {
        await reactionRepo.saveReaction(
          const MessageReaction(
            id: 'r1',
            messageId: 'msg-1',
            emoji: '👍',
            senderPeerId: 'my-peer',
            timestamp: '2026-02-27T10:00:00.000Z',
            createdAt: '2026-02-27T10:00:01.000Z',
          ),
        );
        p2pService.sendMessageResult = false;
        p2pService.storeInInboxResult = false;

        final result = await removeReaction(
          p2pService: p2pService,
          bridge: bridge,
          reactionRepo: reactionRepo,
          targetPeerId: 'peer-1',
          messageId: 'msg-1',
          emoji: '👍',
          senderPeerId: 'my-peer',
          recipientMlKemPublicKey: 'key-1',
        );

        expect(result, RemoveReactionResult.sendFailed);
        expect(p2pService.storeInInboxCallCount, 1);
        expect(reactionRepo.removeReactionCallCount, 0);

        final remaining = await reactionRepo.getReactionsForMessage('msg-1');
        expect(remaining, hasLength(1));
        expect(remaining.single.id, 'r1');
      },
    );
  });
}
