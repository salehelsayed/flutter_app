import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/remove_reaction_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../domain/repositories/fake_reaction_repository.dart';

/// FDC-18 Prerequisite P0: capture the flow events emitted while [action] runs.
Future<List<Map<String, dynamic>>> _captureFlowEvents(
  Future<void> Function() action,
) async {
  final events = <Map<String, dynamic>>[];
  debugSetFlowEventSink((payload) => events.add(payload));
  try {
    await action();
  } finally {
    debugSetFlowEventSink(null);
  }
  return events;
}

/// Seeds a removable reaction on `msg-1` from `my-peer`.
Future<void> _seedReaction(FakeReactionRepository repo) {
  return repo.saveReaction(
    const MessageReaction(
      id: 'r1',
      messageId: 'msg-1',
      emoji: '👍',
      senderPeerId: 'my-peer',
      timestamp: '2026-02-27T10:00:00.000Z',
      createdAt: '2026-02-27T10:00:01.000Z',
    ),
  );
}

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

    // ---- FDC-18: concurrent durable inbox (twin of the add path) ----

    test(
      'FDC-18-R1 unknown-presence reaction REMOVE whose live send fails takes '
      'concurrent-inbox custody',
      () async {
        await _seedReaction(reactionRepo);
        p2pService.sendMessageResult = false;
        p2pService.storeInInboxResult = true;

        late RemoveReactionResult result;
        final events = await _captureFlowEvents(() async {
          result = await removeReaction(
            p2pService: p2pService,
            bridge: bridge,
            reactionRepo: reactionRepo,
            targetPeerId: 'peer-1',
            messageId: 'msg-1',
            emoji: '👍',
            senderPeerId: 'my-peer',
            recipientMlKemPublicKey: 'key-1',
          );
        });

        expect(result, RemoveReactionResult.success);
        expect(p2pService.storeInInboxCallCount, 1);
        expect(
          events.map((e) => e['event']),
          contains('REACTION_REMOVE_CONCURRENT_INBOX_BEGIN'),
        );
        expect(reactionRepo.removeReactionCallCount, 1);
        expect(await reactionRepo.getReactionsForMessage('msg-1'), isEmpty);
      },
    );

    test(
      'FDC-18-R2 unknown-presence reaction REMOVE whose live send WINS still '
      'deposits one concurrent inbox copy',
      () async {
        await _seedReaction(reactionRepo);
        p2pService.sendMessageResult = true;
        p2pService.sendMessageDelay = const Duration(milliseconds: 150);
        p2pService.storeInInboxResult = true;

        late RemoveReactionResult result;
        final events = await _captureFlowEvents(() async {
          result = await removeReaction(
            p2pService: p2pService,
            bridge: bridge,
            reactionRepo: reactionRepo,
            targetPeerId: 'peer-1',
            messageId: 'msg-1',
            emoji: '👍',
            senderPeerId: 'my-peer',
            recipientMlKemPublicKey: 'key-1',
          );
        });

        expect(result, RemoveReactionResult.success);
        expect(p2pService.sendMessageCallCount, 1);
        expect(p2pService.storeInInboxCallCount, 1);
        expect(reactionRepo.removeReactionCallCount, 1);
        final names = events.map((e) => e['event']).toList();
        expect(names, contains('REACTION_REMOVE_CONCURRENT_INBOX_BEGIN'));
        expect(names, contains('REACTION_REMOVE_SUCCESS'));
      },
    );

    test(
      'FDC-18-R3 connected-peer reaction REMOVE does NOT fire the concurrent '
      'inbox',
      () async {
        await _seedReaction(reactionRepo);
        p2pService.isConnectedToPeerResult = true;
        p2pService.sendMessageResult = true;
        p2pService.storeInInboxResult = true;

        late RemoveReactionResult result;
        final events = await _captureFlowEvents(() async {
          result = await removeReaction(
            p2pService: p2pService,
            bridge: bridge,
            reactionRepo: reactionRepo,
            targetPeerId: 'peer-1',
            messageId: 'msg-1',
            emoji: '👍',
            senderPeerId: 'my-peer',
            recipientMlKemPublicKey: 'key-1',
          );
        });

        expect(result, RemoveReactionResult.success);
        expect(p2pService.storeInInboxCallCount, 0);
        expect(
          events.map((e) => e['event']),
          isNot(contains('REACTION_REMOVE_CONCURRENT_INBOX_BEGIN')),
        );
      },
    );

    test(
      'FDC-18-R4 concurrent-custody REMOVE writes storeInInbox EXACTLY once',
      () async {
        await _seedReaction(reactionRepo);
        p2pService.sendMessageResult = false;
        p2pService.storeInInboxResult = true;

        late RemoveReactionResult result;
        final events = await _captureFlowEvents(() async {
          result = await removeReaction(
            p2pService: p2pService,
            bridge: bridge,
            reactionRepo: reactionRepo,
            targetPeerId: 'peer-1',
            messageId: 'msg-1',
            emoji: '👍',
            senderPeerId: 'my-peer',
            recipientMlKemPublicKey: 'key-1',
          );
        });

        expect(p2pService.storeInInboxCallCount, 1);
        expect(
          events.map((e) => e['event']),
          contains('REACTION_REMOVE_CONCURRENT_INBOX_BEGIN'),
        );
        expect(result, RemoveReactionResult.success);
      },
    );

    test(
      'FDC-18-R5 live send and concurrent inbox both fail returns sendFailed '
      'and does not delete locally',
      () async {
        await _seedReaction(reactionRepo);
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
        expect(reactionRepo.removeReactionCallCount, 0);
        expect(p2pService.storeInInboxCallCount, 1);
        final remaining = await reactionRepo.getReactionsForMessage('msg-1');
        expect(remaining, hasLength(1));
        expect(remaining.single.id, 'r1');
      },
    );

    // FDC-18-P2b source-pin (mirror of the add file's 116-P1.2 pin): now that
    // FDC-18 edits the remove file, lock that it stays off the failed-message
    // retry pipeline — no MessageRepository, no saveMessage.
    test(
      'remove-reaction failure never writes a failed messages row '
      '(retry-pipeline non-involvement)',
      () {
        final source = File(
          'lib/features/conversation/application/remove_reaction_use_case.dart',
        ).readAsStringSync();
        expect(source, isNot(contains('MessageRepository')));
        expect(source, isNot(contains('saveMessage')));
      },
    );
  });
}
