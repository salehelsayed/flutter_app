import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/features/conversation/application/send_reaction_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_reaction_inbox_custody_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/direct_reaction_custody_p2p_service.dart';
import '../../../shared/fakes/in_memory_direct_reaction_custody_repository.dart';
import '../domain/repositories/fake_reaction_repository.dart';

void main() {
  late DirectReactionCustodyP2PService p2pService;
  late FakeBridge bridge;
  late InMemoryDirectReactionCustodyRepository reactionRepo;

  setUp(() {
    p2pService = DirectReactionCustodyP2PService(
      initialState: const NodeState(isStarted: true, peerId: 'my-peer'),
    );
    bridge = FakeBridge(
      initialResponses: <String, Map<String, dynamic>>{
        'message.encrypt': <String, dynamic>{
          'ok': true,
          'kem': 'test-kem',
          'ciphertext': 'test-cipher',
          'nonce': 'test-nonce',
        },
      },
    );
    reactionRepo = InMemoryDirectReactionCustodyRepository(
      now: () => DateTime.utc(2026, 8, 7, 12),
    );
  });

  Future<(SendReactionResult, MessageReaction?)> invoke({
    InMemoryDirectReactionCustodyRepository? repository,
  }) => sendReaction(
    p2pService: p2pService,
    bridge: bridge,
    reactionRepo: repository ?? reactionRepo,
    targetPeerId: 'peer-1',
    messageId: 'msg-1',
    emoji: '👍',
    senderPeerId: 'my-peer',
    recipientMlKemPublicKey: 'key-1',
  );

  group('sendReaction Plan 343 custody', () {
    test('encryption failure authors no reaction or custody', () async {
      bridge.responses['message.encrypt'] = <String, dynamic>{
        'ok': false,
        'errorCode': 'err',
      };

      final (result, reaction) = await invoke();

      expect(result, SendReactionResult.encryptionFailed);
      expect(reaction, isNull);
      expect(reactionRepo.stageCallCount, 0);
      expect(reactionRepo.custodyRows, isEmpty);
      expect(p2pService.sendMessageCallCount, 0);
      expect(p2pService.storeInInboxCallCount, 0);
    });

    test('bridge throw authors no reaction or custody', () async {
      bridge.throwOnSend = true;

      final (result, reaction) = await invoke();

      expect(result, SendReactionResult.encryptionFailed);
      expect(reaction, isNull);
      expect(reactionRepo.stageCallCount, 0);
      expect(reactionRepo.custodyRows, isEmpty);
    });

    test('node-stopped ADD still commits exact local custody', () async {
      p2pService = DirectReactionCustodyP2PService(
        initialState: const NodeState(isStarted: false),
      );

      final (result, reaction) = await invoke();

      expect(result, SendReactionResult.nodeNotRunning);
      expect(reaction, isNotNull);
      expect(reactionRepo.stageCallCount, 1);
      expect(reactionRepo.saveReactionCallCount, 1);
      expect(reactionRepo.custodyRows, hasLength(1));
      expect(reactionRepo.custodyRows.single.eventId, reaction!.id);
      expect(p2pService.sendMessageCallCount, 0);
      expect(p2pService.storeInInboxCallCount, 0);
    });

    test(
      'TC-343-03a connected ADD stages exact custody before live and live ACK cannot retire it',
      () async {
        p2pService.isConnectedToPeerResult = true;
        p2pService.sendMessageResult = true;
        final storeEntered = Completer<void>();
        final releaseStore = Completer<InboxStoreOutcome>();
        p2pService.onStoreInInboxDetailed =
            (peerId, envelope, {timeoutMs}) async {
              storeEntered.complete();
              return releaseStore.future;
            };

        final send = invoke();
        await storeEntered.future;

        expect(reactionRepo.stageCallCount, 1);
        expect(reactionRepo.custodyRows, hasLength(1));
        expect(p2pService.sendMessageCallCount, 1);
        expect(p2pService.storeInInboxCallCount, 1);
        expect(
          p2pService.lastSendMessageContent,
          p2pService.lastStoreInInboxMessage,
        );
        final staged = reactionRepo.custodyRows.single;

        releaseStore.complete(
          const InboxStoreOutcome(status: InboxStoreStatus.stored),
        );
        final (result, reaction) = await send;

        expect(result, SendReactionResult.success);
        expect(reaction, isNotNull);
        expect(reactionRepo.completionCallCount, 1);
        expect(
          reactionRepo.completionExpected.single.recipientPeerId,
          'peer-1',
        );
        expect(reactionRepo.completionExpected.single.eventId, staged.eventId);
        expect(
          reactionRepo.completionExpected.single.wireEnvelope,
          staged.wireEnvelope,
        );
        expect(reactionRepo.custodyRows, isEmpty);
      },
    );

    final outcomeCases =
        <
          ({
            String name,
            bool live,
            bool throwLive,
            InboxStoreOutcome inbox,
            bool throwInbox,
            SendReactionResult result,
            bool retained,
            String? errorCode,
          })
        >[
          (
            name: 'live accepted and store failed',
            live: true,
            throwLive: false,
            inbox: const InboxStoreOutcome(status: InboxStoreStatus.failed),
            throwInbox: false,
            result: SendReactionResult.success,
            retained: true,
            errorCode: 'store_failed',
          ),
          (
            name: 'live failed and store accepted',
            live: false,
            throwLive: false,
            inbox: const InboxStoreOutcome(status: InboxStoreStatus.stored),
            throwInbox: false,
            result: SendReactionResult.success,
            retained: false,
            errorCode: null,
          ),
          (
            name: 'live failed and duplicate accepted',
            live: false,
            throwLive: false,
            inbox: const InboxStoreOutcome(status: InboxStoreStatus.duplicate),
            throwInbox: false,
            result: SendReactionResult.success,
            retained: false,
            errorCode: null,
          ),
          (
            name: 'both legs rejected',
            live: false,
            throwLive: false,
            inbox: const InboxStoreOutcome(
              status: InboxStoreStatus.rejectedFull,
            ),
            throwInbox: false,
            result: SendReactionResult.sendFailed,
            retained: true,
            errorCode: 'store_rejected_full',
          ),
          (
            name: 'live throw and store failed',
            live: true,
            throwLive: true,
            inbox: const InboxStoreOutcome(status: InboxStoreStatus.failed),
            throwInbox: false,
            result: SendReactionResult.sendFailed,
            retained: true,
            errorCode: 'store_failed',
          ),
          (
            name: 'live throw and store accepted',
            live: true,
            throwLive: true,
            inbox: const InboxStoreOutcome(status: InboxStoreStatus.stored),
            throwInbox: false,
            result: SendReactionResult.success,
            retained: false,
            errorCode: null,
          ),
          (
            name: 'live accepted and store threw',
            live: true,
            throwLive: false,
            inbox: const InboxStoreOutcome(status: InboxStoreStatus.stored),
            throwInbox: true,
            result: SendReactionResult.success,
            retained: true,
            errorCode: 'store_threw',
          ),
        ];

    for (final testCase in outcomeCases) {
      test(
        'TC-343-03b ADD immediate outcome matrix retains committed custody: ${testCase.name}',
        () async {
          p2pService.sendMessageResult = testCase.live;
          p2pService.throwOnLiveSend = testCase.throwLive;
          p2pService.detailedInboxOutcome = testCase.inbox;
          p2pService.throwOnDetailedInboxStore = testCase.throwInbox;

          final (result, reaction) = await invoke();

          expect(result, testCase.result);
          expect(reaction, isNotNull);
          expect(reactionRepo.saveReactionCallCount, 1);
          expect(p2pService.sendMessageCallCount, 1);
          expect(p2pService.storeInInboxCallCount, 1);
          expect(reactionRepo.custodyRows.isNotEmpty, testCase.retained);
          if (testCase.retained) {
            expect(
              reactionRepo.custodyRows.single.lastErrorCode,
              testCase.errorCode,
            );
          }
          final inboxAccepted = !testCase.throwInbox && testCase.inbox.accepted;
          final exactExpected = inboxAccepted
              ? reactionRepo.completionExpected.single
              : reactionRepo.failureExpected.single;
          expect(exactExpected.recipientPeerId, 'peer-1');
          expect(exactExpected.eventId, reaction!.id);
          expect(
            exactExpected.wireEnvelope,
            p2pService.lastStoreInInboxMessage,
          );
        },
      );
    }

    test(
      'TC-343-03b accepted ADD whose local completion throws retains local_completion_failed',
      () async {
        p2pService.sendMessageResult = false;
        reactionRepo.throwOnCompletion = true;

        final (result, reaction) = await invoke();

        expect(result, SendReactionResult.success);
        expect(reaction, isNotNull);
        expect(reactionRepo.custodyRows, hasLength(1));
        expect(
          reactionRepo.custodyRows.single.lastErrorCode,
          'local_completion_failed',
        );
      },
    );

    test(
      'accepted ADD with stale local completion retains exact custody for retry',
      () async {
        p2pService.sendMessageResult = false;
        reactionRepo.forcedCompletionOutcome =
            DirectReactionInboxCustodyCompletionOutcome.stale;

        final (result, reaction) = await invoke();

        expect(result, SendReactionResult.success);
        expect(reaction, isNotNull);
        expect(reactionRepo.completionCallCount, 1);
        expect(reactionRepo.failureRecordCallCount, 1);
        expect(reactionRepo.failureErrorCodes, <String>[
          'local_completion_failed',
        ]);
        expect(reactionRepo.custodyRows, hasLength(1));
        expect(
          reactionRepo.failureExpected.single.wireEnvelope,
          reactionRepo.completionExpected.single.wireEnvelope,
        );
      },
    );

    test('stage refusal is fail-closed before all network work', () async {
      reactionRepo.refuseStage = true;

      final (result, reaction) = await invoke();

      expect(result, SendReactionResult.sendFailed);
      expect(reaction, isNull);
      expect(p2pService.sendMessageCallCount, 0);
      expect(p2pService.storeInInboxCallCount, 0);
      expect(reactionRepo.saveReactionCallCount, 0);
    });

    test(
      'atomic stage exception is contained before all network work',
      () async {
        reactionRepo.throwOnStage = true;

        final (result, reaction) = await invoke();

        expect(result, SendReactionResult.sendFailed);
        expect(reaction, isNull);
        expect(p2pService.sendMessageCallCount, 0);
        expect(p2pService.storeInInboxCallCount, 0);
        expect(reactionRepo.saveReactionCallCount, 0);
      },
    );

    test('missing custody capability is fail-closed', () async {
      final incapable = FakeReactionRepository();

      final (result, reaction) = await sendReaction(
        p2pService: p2pService,
        bridge: bridge,
        reactionRepo: incapable,
        targetPeerId: 'peer-1',
        messageId: 'msg-1',
        emoji: '👍',
        senderPeerId: 'my-peer',
        recipientMlKemPublicKey: 'key-1',
      );

      expect(result, SendReactionResult.sendFailed);
      expect(reaction, isNull);
      expect(p2pService.sendMessageCallCount, 0);
      expect(p2pService.storeInInboxCallCount, 0);
    });

    test('disabled custody capability is fail-closed', () async {
      reactionRepo.custodySupported = false;

      final (result, reaction) = await invoke();

      expect(result, SendReactionResult.sendFailed);
      expect(reaction, isNull);
      expect(reactionRepo.stageCallCount, 0);
      expect(p2pService.sendMessageCallCount, 0);
      expect(p2pService.storeInInboxCallCount, 0);
    });

    test('missing typed inbox capability is fail-closed', () async {
      final incapableTransport = FakeP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'my-peer'),
      );

      final (result, reaction) = await sendReaction(
        p2pService: incapableTransport,
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
      expect(reactionRepo.stageCallCount, 0);
      expect(incapableTransport.sendMessageCallCount, 0);
      expect(incapableTransport.storeInInboxCallCount, 0);
    });

    test(
      'ADD uses one exact encrypted envelope on both transport legs',
      () async {
        p2pService.sendMessageResult = true;
        p2pService.detailedInboxOutcome = const InboxStoreOutcome(
          status: InboxStoreStatus.failed,
        );

        final (result, reaction) = await invoke();

        expect(result, SendReactionResult.success);
        final liveEnvelope = p2pService.lastSendMessageContent!;
        expect(liveEnvelope, p2pService.lastStoreInInboxMessage);
        expect(liveEnvelope, reactionRepo.custodyRows.single.wireEnvelope);
        expect(reactionRepo.failureExpected.single.wireEnvelope, liveEnvelope);
        expect(reactionRepo.failureExpected.single.recipientPeerId, 'peer-1');
        final outer = jsonDecode(liveEnvelope) as Map<String, dynamic>;
        expect(outer['eventId'], reaction!.id);
        expect(outer['action'], 'add');
        expect(outer['targetMessageId'], 'msg-1');
        expect(outer.containsKey('emoji'), isFalse);
        expect(outer.containsKey('senderUsername'), isFalse);
      },
    );

    test('persists non-preset emoji through the atomic stage', () async {
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
      expect(reaction?.emoji, '😀');
      expect(reactionRepo.lastSavedReaction?.emoji, '😀');
    });

    test('reaction custody never enters the failed-message pipeline', () {
      final source = File(
        'lib/features/conversation/application/send_reaction_use_case.dart',
      ).readAsStringSync();
      expect(source, isNot(contains('MessageRepository')));
      expect(source, isNot(contains('saveMessage')));
    });
  });
}
