import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/features/conversation/application/remove_reaction_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_reaction_inbox_custody_outbox_entry.dart';
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
    // The default fake encryptor echoes plaintext into ciphertext, letting the
    // test compare the inner REMOVE identity with outer metadata and staging.
    bridge = FakeBridge();
    reactionRepo = InMemoryDirectReactionCustodyRepository(
      now: () => DateTime.utc(2026, 8, 7, 12),
    );
  });

  Future<RemoveReactionResult> invoke({
    InMemoryDirectReactionCustodyRepository? repository,
  }) => removeReaction(
    p2pService: p2pService,
    bridge: bridge,
    reactionRepo: repository ?? reactionRepo,
    targetPeerId: 'peer-1',
    messageId: 'msg-1',
    emoji: '👍',
    senderPeerId: 'my-peer',
    recipientMlKemPublicKey: 'key-1',
  );

  group('removeReaction Plan 343 custody', () {
    test('encryption failure authors no tombstone or custody', () async {
      bridge.responses['message.encrypt'] = <String, dynamic>{
        'ok': false,
        'errorCode': 'err',
      };

      final result = await invoke();

      expect(result, RemoveReactionResult.encryptionFailed);
      expect(reactionRepo.stageCallCount, 0);
      expect(reactionRepo.custodyRows, isEmpty);
      expect(p2pService.sendMessageCallCount, 0);
      expect(p2pService.storeInInboxCallCount, 0);
    });

    test('node-stopped REMOVE commits a complete tombstone', () async {
      p2pService = DirectReactionCustodyP2PService(
        initialState: const NodeState(isStarted: false),
      );

      final result = await invoke();

      expect(result, RemoveReactionResult.nodeNotRunning);
      expect(reactionRepo.stageCallCount, 1);
      expect(reactionRepo.custodyRows, hasLength(1));
      final tombstone = await reactionRepo.getReactionForSenderIncludingRemoved(
        messageId: 'msg-1',
        senderPeerId: 'my-peer',
      );
      expect(tombstone, isNotNull);
      expect(tombstone!.isRemoved, isTrue);
      expect(tombstone.id, reactionRepo.custodyRows.single.eventId);
      expect(p2pService.sendMessageCallCount, 0);
      expect(p2pService.storeInInboxCallCount, 0);
    });

    test(
      'TC-343-03c connected REMOVE stages exact custody before live and live ACK cannot retire it',
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

        final remove = invoke();
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
        expect(await remove, RemoveReactionResult.success);
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
        expect(await reactionRepo.getReactionsForMessage('msg-1'), isEmpty);
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
            RemoveReactionResult result,
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
            result: RemoveReactionResult.success,
            retained: true,
            errorCode: 'store_failed',
          ),
          (
            name: 'live failed and store accepted',
            live: false,
            throwLive: false,
            inbox: const InboxStoreOutcome(status: InboxStoreStatus.stored),
            throwInbox: false,
            result: RemoveReactionResult.success,
            retained: false,
            errorCode: null,
          ),
          (
            name: 'live failed and duplicate accepted',
            live: false,
            throwLive: false,
            inbox: const InboxStoreOutcome(status: InboxStoreStatus.duplicate),
            throwInbox: false,
            result: RemoveReactionResult.success,
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
            result: RemoveReactionResult.sendFailed,
            retained: true,
            errorCode: 'store_rejected_full',
          ),
          (
            name: 'live throw and store failed',
            live: true,
            throwLive: true,
            inbox: const InboxStoreOutcome(status: InboxStoreStatus.failed),
            throwInbox: false,
            result: RemoveReactionResult.sendFailed,
            retained: true,
            errorCode: 'store_failed',
          ),
          (
            name: 'live throw and store accepted',
            live: true,
            throwLive: true,
            inbox: const InboxStoreOutcome(status: InboxStoreStatus.stored),
            throwInbox: false,
            result: RemoveReactionResult.success,
            retained: false,
            errorCode: null,
          ),
          (
            name: 'live accepted and store threw',
            live: true,
            throwLive: false,
            inbox: const InboxStoreOutcome(status: InboxStoreStatus.stored),
            throwInbox: true,
            result: RemoveReactionResult.success,
            retained: true,
            errorCode: 'store_threw',
          ),
        ];

    for (final testCase in outcomeCases) {
      test(
        'TC-343-03d REMOVE immediate outcome matrix retains committed custody: ${testCase.name}',
        () async {
          p2pService.sendMessageResult = testCase.live;
          p2pService.throwOnLiveSend = testCase.throwLive;
          p2pService.detailedInboxOutcome = testCase.inbox;
          p2pService.throwOnDetailedInboxStore = testCase.throwInbox;

          final result = await invoke();

          expect(result, testCase.result);
          expect(reactionRepo.stageCallCount, 1);
          expect(p2pService.sendMessageCallCount, 1);
          expect(p2pService.storeInInboxCallCount, 1);
          expect(reactionRepo.custodyRows.isNotEmpty, testCase.retained);
          if (testCase.retained) {
            expect(
              reactionRepo.custodyRows.single.lastErrorCode,
              testCase.errorCode,
            );
          }
          final tombstone = await reactionRepo
              .getReactionForSenderIncludingRemoved(
                messageId: 'msg-1',
                senderPeerId: 'my-peer',
              );
          expect(tombstone?.isRemoved, isTrue);
          final inboxAccepted = !testCase.throwInbox && testCase.inbox.accepted;
          final exactExpected = inboxAccepted
              ? reactionRepo.completionExpected.single
              : reactionRepo.failureExpected.single;
          expect(exactExpected.recipientPeerId, 'peer-1');
          expect(exactExpected.eventId, tombstone!.id);
          expect(
            exactExpected.wireEnvelope,
            p2pService.lastStoreInInboxMessage,
          );
        },
      );
    }

    test(
      'TC-343-03d accepted REMOVE whose local completion throws retains local_completion_failed',
      () async {
        p2pService.sendMessageResult = false;
        reactionRepo.throwOnCompletion = true;

        final result = await invoke();

        expect(result, RemoveReactionResult.success);
        expect(reactionRepo.custodyRows, hasLength(1));
        expect(
          reactionRepo.custodyRows.single.lastErrorCode,
          'local_completion_failed',
        );
      },
    );

    test(
      'accepted REMOVE with stale local completion retains exact custody for retry',
      () async {
        p2pService.sendMessageResult = false;
        reactionRepo.forcedCompletionOutcome =
            DirectReactionInboxCustodyCompletionOutcome.stale;

        expect(await invoke(), RemoveReactionResult.success);

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

    test('REMOVE inner outer stage identities are exact', () async {
      p2pService.sendMessageResult = true;
      p2pService.detailedInboxOutcome = const InboxStoreOutcome(
        status: InboxStoreStatus.failed,
      );

      expect(await invoke(), RemoveReactionResult.success);

      final envelope = p2pService.lastSendMessageContent!;
      expect(envelope, p2pService.lastStoreInInboxMessage);
      expect(envelope, reactionRepo.custodyRows.single.wireEnvelope);
      expect(reactionRepo.failureExpected.single.wireEnvelope, envelope);
      expect(reactionRepo.failureExpected.single.recipientPeerId, 'peer-1');
      final outer = jsonDecode(envelope) as Map<String, dynamic>;
      final encrypted = outer['encrypted'] as Map<String, dynamic>;
      final inner =
          jsonDecode(encrypted['ciphertext'] as String) as Map<String, dynamic>;
      final tombstone = await reactionRepo.getReactionForSenderIncludingRemoved(
        messageId: 'msg-1',
        senderPeerId: 'my-peer',
      );

      expect(outer['eventId'], inner['id']);
      expect(outer['eventId'], tombstone!.id);
      expect(outer['eventId'], reactionRepo.custodyRows.single.eventId);
      expect(outer['action'], 'remove');
      expect(inner['action'], 'remove');
      expect(outer['targetMessageId'], inner['messageId']);
      expect(inner['messageId'], tombstone.messageId);
      expect(inner['senderPeerId'], tombstone.senderPeerId);
      expect(tombstone.removedAt, inner['timestamp']);
    });

    test('stage refusal is fail-closed before all network work', () async {
      reactionRepo.refuseStage = true;

      expect(await invoke(), RemoveReactionResult.sendFailed);

      expect(p2pService.sendMessageCallCount, 0);
      expect(p2pService.storeInInboxCallCount, 0);
      expect(reactionRepo.saveReactionCallCount, 0);
    });

    test(
      'atomic stage exception is contained before all network work',
      () async {
        reactionRepo.throwOnStage = true;

        expect(await invoke(), RemoveReactionResult.sendFailed);

        expect(p2pService.sendMessageCallCount, 0);
        expect(p2pService.storeInInboxCallCount, 0);
        expect(reactionRepo.saveReactionCallCount, 0);
      },
    );

    test('missing custody capability is fail-closed', () async {
      final incapable = FakeReactionRepository();

      final result = await removeReaction(
        p2pService: p2pService,
        bridge: bridge,
        reactionRepo: incapable,
        targetPeerId: 'peer-1',
        messageId: 'msg-1',
        emoji: '👍',
        senderPeerId: 'my-peer',
        recipientMlKemPublicKey: 'key-1',
      );

      expect(result, RemoveReactionResult.sendFailed);
      expect(p2pService.sendMessageCallCount, 0);
      expect(p2pService.storeInInboxCallCount, 0);
    });

    test('disabled custody capability is fail-closed', () async {
      reactionRepo.custodySupported = false;

      expect(await invoke(), RemoveReactionResult.sendFailed);

      expect(reactionRepo.stageCallCount, 0);
      expect(p2pService.sendMessageCallCount, 0);
      expect(p2pService.storeInInboxCallCount, 0);
    });

    test('missing typed inbox capability is fail-closed', () async {
      final incapableTransport = FakeP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'my-peer'),
      );

      final result = await removeReaction(
        p2pService: incapableTransport,
        bridge: bridge,
        reactionRepo: reactionRepo,
        targetPeerId: 'peer-1',
        messageId: 'msg-1',
        emoji: '👍',
        senderPeerId: 'my-peer',
        recipientMlKemPublicKey: 'key-1',
      );

      expect(result, RemoveReactionResult.sendFailed);
      expect(reactionRepo.stageCallCount, 0);
      expect(incapableTransport.sendMessageCallCount, 0);
      expect(incapableTransport.storeInInboxCallCount, 0);
    });

    test('reaction REMOVE never enters the failed-message pipeline', () {
      final source = File(
        'lib/features/conversation/application/remove_reaction_use_case.dart',
      ).readAsStringSync();
      expect(source, isNot(contains('MessageRepository')));
      expect(source, isNot(contains('saveMessage')));
    });
  });
}
