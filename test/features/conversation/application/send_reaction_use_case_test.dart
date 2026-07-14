import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/send_reaction_use_case.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../domain/repositories/fake_reaction_repository.dart';

/// FDC-18 Prerequisite P0: capture the flow events emitted while [action] runs.
/// Reactions emit via `emitFlowEvent` -> `debugSetFlowEventSink`; the reaction
/// test files have no shared capture helper, so each adds this local one.
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

    test('ADD envelope carries minimal notification metadata', () async {
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
      final outer =
          jsonDecode(p2pService.lastSendMessageContent!)
              as Map<String, dynamic>;
      expect(outer['eventId'], reaction!.id);
      expect(outer['action'], 'add');
      expect(outer['targetMessageId'], 'msg-1');
      expect(outer.containsKey('emoji'), isFalse);
      expect(outer.containsKey('senderUsername'), isFalse);
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

    // 116 P1.2 PIN (green-on-arrival): reactions never enter the failed-
    // message retry pipeline — sendReaction takes no MessageRepository and a
    // failed reaction writes no messages row, so the edit-retry fidelity
    // contracts (EF-1..EF-4) have no reaction leg. This source pin fails if
    // anyone ever threads a MessageRepository into this use case.
    test(
      'reaction failure never writes a failed messages row (retry-pipeline non-involvement)',
      () {
        final source = File(
          'lib/features/conversation/application/send_reaction_use_case.dart',
        ).readAsStringSync();
        expect(source, isNot(contains('MessageRepository')));
        expect(source, isNot(contains('saveMessage')));
      },
    );

    // ---- FDC-18: concurrent durable inbox (mirror FDC-03 onto sendReaction) ----

    test('FDC-18-01 unknown-presence reaction whose live send fails takes '
        'concurrent-inbox custody', () async {
      // Unknown presence (isConnectedToPeerResult: false by default); the live
      // send fails, the concurrent inbox deposit succeeds.
      p2pService.sendMessageResult = false;
      p2pService.storeInInboxResult = true;

      late SendReactionResult result;
      final events = await _captureFlowEvents(() async {
        final (r, _) = await sendReaction(
          p2pService: p2pService,
          bridge: bridge,
          reactionRepo: reactionRepo,
          targetPeerId: 'peer-1',
          messageId: 'msg-1',
          emoji: '👍',
          senderPeerId: 'my-peer',
          recipientMlKemPublicKey: 'key-1',
        );
        result = r;
      });

      expect(result, SendReactionResult.success);
      expect(p2pService.storeInInboxCallCount, 1);
      expect(
        events.map((e) => e['event']),
        contains('REACTION_SEND_CONCURRENT_INBOX_BEGIN'),
      );
      expect(reactionRepo.saveReactionCallCount, 1);
    });

    test(
      'FDC-18-02 unknown-presence reaction whose live send WINS still deposits '
      'one concurrent inbox copy',
      () async {
        // PROD-CRITICAL keystone: the concurrent arm must fire even on a live
        // win. The 150ms send delay makes the race observable — the deposit has
        // started before the live leg resolves, so a naive serial `if(!sent)`
        // implementation yields storeInInboxCallCount==0 here.
        p2pService.sendMessageResult = true;
        p2pService.sendMessageDelay = const Duration(milliseconds: 150);
        p2pService.storeInInboxResult = true;

        late SendReactionResult result;
        final events = await _captureFlowEvents(() async {
          final (r, _) = await sendReaction(
            p2pService: p2pService,
            bridge: bridge,
            reactionRepo: reactionRepo,
            targetPeerId: 'peer-1',
            messageId: 'msg-1',
            emoji: '👍',
            senderPeerId: 'my-peer',
            recipientMlKemPublicKey: 'key-1',
          );
          result = r;
        });

        expect(result, SendReactionResult.success);
        expect(p2pService.sendMessageCallCount, 1);
        expect(p2pService.storeInInboxCallCount, 1);
        expect(reactionRepo.saveReactionCallCount, 1);
        final names = events.map((e) => e['event']).toList();
        expect(names, contains('REACTION_SEND_CONCURRENT_INBOX_BEGIN'));
        expect(names, contains('REACTION_SEND_SUCCESS'));
      },
    );

    test(
      'FDC-18-03 connected-peer reaction does NOT fire the concurrent inbox',
      () async {
        // Confirmed-path => single-path. A live-connected peer has its own
        // delivery confirmation; no parallel inbox copy. (Mutation-verified
        // guard: HEAD-serial logic already yields 0 on a live win, so the value
        // is M3 — dropping the !isConnectedToPeer guard would deposit here.)
        p2pService.isConnectedToPeerResult = true;
        p2pService.sendMessageResult = true;
        p2pService.storeInInboxResult = true;

        late SendReactionResult result;
        final events = await _captureFlowEvents(() async {
          final (r, _) = await sendReaction(
            p2pService: p2pService,
            bridge: bridge,
            reactionRepo: reactionRepo,
            targetPeerId: 'peer-1',
            messageId: 'msg-1',
            emoji: '👍',
            senderPeerId: 'my-peer',
            recipientMlKemPublicKey: 'key-1',
          );
          result = r;
        });

        expect(result, SendReactionResult.success);
        expect(p2pService.storeInInboxCallCount, 0);
        expect(
          events.map((e) => e['event']),
          isNot(contains('REACTION_SEND_CONCURRENT_INBOX_BEGIN')),
        );
      },
    );

    test(
      'FDC-18-04 concurrent-custody reaction writes storeInInbox EXACTLY once',
      () async {
        // No concurrent + serial double-write: the concurrent deposit is the
        // ONLY store; the live-miss tail awaits it rather than starting a fresh
        // one. (M4 removes the short-circuit -> count 2.)
        p2pService.sendMessageResult = false;
        p2pService.storeInInboxResult = true;

        late SendReactionResult result;
        final events = await _captureFlowEvents(() async {
          final (r, _) = await sendReaction(
            p2pService: p2pService,
            bridge: bridge,
            reactionRepo: reactionRepo,
            targetPeerId: 'peer-1',
            messageId: 'msg-1',
            emoji: '👍',
            senderPeerId: 'my-peer',
            recipientMlKemPublicKey: 'key-1',
          );
          result = r;
        });

        expect(p2pService.storeInInboxCallCount, 1);
        expect(
          events.map((e) => e['event']),
          contains('REACTION_SEND_CONCURRENT_INBOX_BEGIN'),
        );
        expect(result, SendReactionResult.success);
      },
    );

    test(
      'FDC-18-05 live send and concurrent inbox both fail returns sendFailed '
      'and persists nothing',
      () async {
        // Preserved sentinel under the concurrent arm: both legs fail =>
        // sendFailed, no local persist. (M5 returns success on inbox-false.)
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
        expect(reactionRepo.saveReactionCallCount, 0);
        expect(p2pService.storeInInboxCallCount, 1);
        expect(await reactionRepo.getReactionsForMessage('msg-1'), isEmpty);
      },
    );
  });
}
