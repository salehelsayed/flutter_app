import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/diagnostics/active_identity_reporter.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_payload.dart';

import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/features/conversation/application/send_reaction_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_reaction_inbox_custody_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/config/direct_linked_event_fanout_flag.dart';
import 'package:flutter_app/core/database/direct_event_fanout_contract.dart';
import 'package:flutter_app/features/conversation/application/direct_event_fanout_coordinator.dart';
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
    ActiveIdentityReporter? activityReporter,
    ({ActiveIdentityReporter? reporter, ActiveIdentityReporterCapture? capture})? capturedActivity,
  }) => sendReaction(
    p2pService: p2pService,
    bridge: bridge,
    reactionRepo: repository ?? reactionRepo,
    targetPeerId: 'peer-1',
    messageId: 'msg-1',
    emoji: '👍',
    senderPeerId: 'my-peer',
    recipientMlKemPublicKey: 'key-1',
    activityReporter: activityReporter,
    capturedActivity: capturedActivity,
  );

  DirectEventFanoutAuthoring fanoutAuthoring({
    required bool selectorOn,
    required List<String> targets,
    required List<String> events,
    void Function(List<DirectEventFanoutTargetCandidate> candidates)? onStage,
    DirectEventFanoutStageOutcome outcome = DirectEventFanoutStageOutcome.applied,
  }) => DirectEventFanoutAuthoring(
    selector: selectorOn
        ? const DirectLinkedEventFanoutSelector.enabled()
        : const DirectLinkedEventFanoutSelector.disabled(),
    linkedOrigin: false,
    senderTransportPeerId: 'my-peer',
    readSnapshot: (contact) async {
      events.add('resolve');
      return DirectContactFanoutSnapshot(
        contactAccountPeerId: contact,
        contactAccountSigningPublicKey: 'signing-key',
        rosterInitialized: true,
        targets: <DirectContactFanoutTargetFact>[
          for (final peer in targets)
            DirectContactFanoutTargetFact(
              peerId: peer,
              mlKemPublicKey: 'mlkem-$peer',
              isLegacyAccountTarget: false,
              fingerprint: 'f' * 64,
              deviceId: 'device-$peer',
            ),
        ],
      );
    },
    encrypt: ({required recipientMlKemPublicKey, required plaintext}) async {
      events.add('encrypt:$recipientMlKemPublicKey');
      return (kem: 'k', ciphertext: 'ct-$recipientMlKemPublicKey', nonce: 'n');
    },
    loadTextSiblings: (_) async => const [],
    stageTextFanout:
        ({
          String? authoredTextIntentToken,
          required stagedRow,
          required messageId,
          required contactAccountPeerId,
          required senderTransportPeerId,
          required expectedSnapshot,
          required candidates,
        }) async => throw StateError('reactions never stage text'),
    loadEventSiblings: (_) async => const [],
    stageMutationFanout:
        ({
          required expectedRow,
          required stagedRow,
          required kind,
          required eventId,
          required parentMessageId,
          required contactAccountPeerId,
          required senderTransportPeerId,
          required expectedSnapshot,
          required candidates,
        }) async => throw StateError('reactions never stage mutations'),
    stageReactionFanout:
        ({
          required reactionRow,
          required action,
          required parentMessageId,
          required contactAccountPeerId,
          required senderTransportPeerId,
          required expectedSnapshot,
          required candidates,
        }) async {
          events.add('stage:$action');
          onStage?.call(candidates);
          return DbDirectEventFanoutStageResult(
            outcome: outcome,
            rows: <Map<String, Object?>>[
              for (final candidate in candidates)
                <String, Object?>{
                  'recipient_peer_id': candidate.recipientPeerId,
                  'event_id': reactionRow['id'],
                  'wire_envelope': candidate.wireEnvelope,
                  'retry_count': 0,
                  'last_attempt_at': null,
                  'last_error_code': null,
                  'contact_account_peer_id': contactAccountPeerId,
                  'parent_message_id': parentMessageId,
                  'created_at': '2026-08-11T12:00:00.000Z',
                  'updated_at': '2026-08-11T12:00:00.000Z',
                },
            ],
          );
        },
  );

  group('BL29 U2 actual direct ADD admission', () {
    const budget = Duration(seconds: 2);
    late _U2ReactionActivityBridge activityBridge;
    late ActiveIdentityReporter reporter;
    setUp(() async {
      activityBridge = _U2ReactionActivityBridge();
      bridge = activityBridge;
      reporter = ActiveIdentityReporter(statePath: '/unused/u2-add.json');
      reporter.attachBridge(activityBridge);
      reporter.observeIdentity(accountPeerId: 'my-peer',
        rootPrivateKeyBase64: base64Encode(List<int>.filled(64, 17)),
        profileBinding: 'v1:${'a' * 64}');
      await reporter.observeConsent((enabled: true, consentEpoch: 7)).timeout(budget);
    });
    tearDown(() async {
      final block = activityBridge.markBlock;
      if (block != null && !block.isCompleted) block.complete();
      await reporter.dispose().timeout(budget);
    });

    test('B14U2A-001 single applied offline ADD marks after exact custody stage', () async {
      p2pService = DirectReactionCustodyP2PService(initialState: const NodeState(isStarted: false, peerId: 'my-peer'));
      final result = await invoke(activityReporter: reporter).timeout(budget);
      expect(result.$1, SendReactionResult.nodeNotRunning);
      expect(result.$2, isNotNull);
      expect(reactionRepo.stageCallCount, 1);
      expect(reactionRepo.custodyRows.single.eventId, result.$2!.id);
      expect(activityBridge.marks, hasLength(1));
      expect(p2pService.sendMessageCallCount, 0);
    });

    test('B14U2A-002 rejected transport cannot revoke a committed ADD activity', () async {
      p2pService.sendMessageResult = false;
      p2pService.detailedInboxOutcome = const InboxStoreOutcome(status: InboxStoreStatus.failed);
      final result = await invoke(activityReporter: reporter).timeout(budget);
      expect(result.$1, SendReactionResult.sendFailed);
      expect(result.$2, isNotNull);
      expect(reactionRepo.custodyRows, hasLength(1));
      expect(activityBridge.marks, hasLength(1));
    });

    test('B14U2A-003 single idempotent stage retains its owner without new activity', () async {
      p2pService = DirectReactionCustodyP2PService(initialState: const NodeState(isStarted: false, peerId: 'my-peer'));
      final repository = _U2IdempotentReactionRepository();
      final result = await invoke(repository: repository, activityReporter: reporter).timeout(budget);
      expect(result.$2, isNotNull);
      expect(repository.custodyRows, hasLength(1));
      expect(activityBridge.marks, isEmpty);
    });

    for (final (id, failure) in [
      ('B14U2A-004', 'stage'), ('B14U2A-005', 'encryption'),
    ]) {
      test('$id refused $failure never admits or marks ADD', () async {
        if (failure == 'stage') reactionRepo.refuseStage = true;
        if (failure == 'encryption') activityBridge.responses['message.encrypt'] = {'ok': false};
        final result = await invoke(activityReporter: reporter).timeout(budget);
        expect(result.$2, isNull);
        expect(reactionRepo.custodyRows, isEmpty);
        expect(activityBridge.marks, isEmpty);
        expect(p2pService.sendMessageCallCount, 0);
      });
    }

    test('B14U2A-006 present null capture cannot reacquire after enabling', () async {
      await reporter.observeConsent((enabled: false, consentEpoch: 8)).timeout(budget);
      final original = (reporter: reporter, capture: reporter.captureOwner(expectedAccountPeerId: 'my-peer'));
      expect(original.capture, isNull);
      await reporter.observeConsent((enabled: true, consentEpoch: 9)).timeout(budget);
      final result = await invoke(activityReporter: reporter, capturedActivity: original).timeout(budget);
      expect(result.$2, isNotNull);
      expect(activityBridge.marks, isEmpty);
    });

    test('B14U2A-007 profile turnover during encryption fences original ADD capture', () async {
      activityBridge.beforeEncrypt = () async {
        reporter.observeIdentity(accountPeerId: 'my-peer',
          rootPrivateKeyBase64: base64Encode(List<int>.filled(64, 17)),
          profileBinding: 'v1:${'b' * 64}');
        await reporter.observeConsent((enabled: true, consentEpoch: 7)).timeout(budget);
      };
      final result = await invoke(activityReporter: reporter).timeout(budget);
      expect(result.$2, isNotNull);
      expect(activityBridge.marks, isEmpty);
    });

    for (final (id, mode) in [('B14U2A-008', 'throw'), ('B14U2A-009', 'block')]) {
      test('$id optional reporter $mode cannot fail or delay admitted ADD', () async {
        if (mode == 'throw') activityBridge.throwOnMark = true;
        if (mode == 'block') activityBridge.markBlock = Completer<void>();
        p2pService = DirectReactionCustodyP2PService(initialState: const NodeState(isStarted: false, peerId: 'my-peer'));
        final result = await invoke(activityReporter: reporter).timeout(budget);
        expect(result.$1, SendReactionResult.nodeNotRunning);
        expect(reactionRepo.custodyRows, hasLength(1));
        expect(activityBridge.marks, hasLength(1));
        if (mode == 'block') expect(activityBridge.markBlock!.isCompleted, isFalse);
      });
    }

    for (final (id, outcome) in [
      ('B14U2A-010', DirectEventFanoutStageOutcome.applied),
      ('B14U2A-011', DirectEventFanoutStageOutcome.survivorReplay),
      ('B14U2A-012', DirectEventFanoutStageOutcome.terminal),
      ('B14U2A-013', DirectEventFanoutStageOutcome.refused),
    ]) {
      test('$id linked ADD $outcome only fresh applied batch marks once for all targets', () async {
        p2pService = DirectReactionCustodyP2PService(initialState: const NodeState(isStarted: false, peerId: 'my-peer'));
        final events = <String>[];
        final result = await sendReaction(
          p2pService: p2pService, bridge: bridge, reactionRepo: reactionRepo,
          targetPeerId: 'peer-1', messageId: 'msg-1', emoji: '👍',
          senderPeerId: 'my-peer', recipientMlKemPublicKey: 'key-1',
          activityReporter: reporter,
          directEventFanout: fanoutAuthoring(selectorOn: true,
            targets: ['peer-device-a', 'peer-device-b'], events: events, outcome: outcome),
        ).timeout(budget);
        expect(events.where((event) => event == 'stage:add'), hasLength(1));
        expect(reactionRepo.stageCallCount, 0);
        expect(result.$2, outcome == DirectEventFanoutStageOutcome.refused ? isNull : isNotNull);
        expect(activityBridge.marks, outcome == DirectEventFanoutStageOutcome.applied ? hasLength(1) : isEmpty);
      });
    }

    test('B14U2A-015 consent epoch turnover during encryption fences original ADD capture', () async {
      activityBridge.beforeEncrypt = () => reporter.observeConsent((enabled: true, consentEpoch: 8)).timeout(budget);
      final result = await invoke(activityReporter: reporter).timeout(budget);
      expect(result.$2, isNotNull);
      expect(activityBridge.marks, isEmpty);
    });

    for (final (id, initiallyEnabled) in [('B14U2A-016', false), ('B14U2A-017', true)]) {
      test('$id linked ADD stage turnover cannot capture the replacement epoch', () async {
        if (!initiallyEnabled) await reporter.observeConsent((enabled: false, consentEpoch: 8)).timeout(budget);
        Future<void>? replaced;
        final events = <String>[];
        final result = await sendReaction(
          p2pService: p2pService, bridge: bridge, reactionRepo: reactionRepo,
          targetPeerId: 'peer-1', messageId: 'msg-1', emoji: '👍',
          senderPeerId: 'my-peer', recipientMlKemPublicKey: 'key-1', activityReporter: reporter,
          directEventFanout: fanoutAuthoring(selectorOn: true,
            targets: ['peer-device-a', 'peer-device-b'], events: events,
            onStage: (_) { replaced = reporter.observeConsent((enabled: true, consentEpoch: 9)); }),
        ).timeout(budget);
        expect(result.$2, isNotNull);
        expect(replaced, isNotNull);
        await replaced!.timeout(budget);
        expect(events, contains('stage:add'));
        expect(activityBridge.marks, isEmpty);
      });
    }

    test('B14U2A-014 REMOVE adapter never marks even when a capture is supplied', () async {
      final payload = ReactionPayload(id: 'u2-remove', messageId: 'msg-1',
        emoji: '👍', action: ReactionPayload.removeAction, senderPeerId: 'my-peer',
        timestamp: '2026-11-17T00:00:00.000Z');
      final events = <String>[];
      final result = await authorDirectReactionFanout(
        directEventFanout: fanoutAuthoring(selectorOn: true, targets: ['peer-device-a'], events: events),
        p2pService: p2pService, custodyRepo: reactionRepo,
        storeInAckCustodyInboxDetailed: p2pService.storeInAckCustodyInboxDetailed,
        targetPeerId: 'peer-1', messageId: 'msg-1', action: ReactionPayload.removeAction,
        payload: payload, flowPrefix: 'REMOVE_REACTION',
        capturedActivity: (reporter: reporter, capture: reporter.captureOwner(expectedAccountPeerId: 'my-peer')),
      ).timeout(budget);
      expect(result, isNotNull);
      expect(events, contains('stage:remove'));
      expect(activityBridge.marks, isEmpty);
    });
  });

  group('TC-361-02a reaction fanout adapter', () {
    test(
      'TC-361-02a selector OFF refuses a reaction pre-crypto without staging '
      'or network',
      () async {
        final events = <String>[];
        final (result, reaction) = await sendReaction(
          p2pService: p2pService,
          bridge: bridge,
          reactionRepo: reactionRepo,
          targetPeerId: 'peer-1',
          messageId: 'msg-1',
          emoji: '👍',
          senderPeerId: 'my-peer',
          recipientMlKemPublicKey: 'key-1',
          directEventFanout: fanoutAuthoring(
            selectorOn: false,
            targets: const ['peer-device-a'],
            events: events,
          ),
        );
        expect(result, SendReactionResult.sendFailed);
        expect(reaction, isNull);
        expect(events, ['resolve']);
        expect(bridge.sendCallCount, 0);
        expect(reactionRepo.stageCallCount, 0);
        expect(p2pService.sendMessageCallCount, 0);
        expect(p2pService.storeInInboxCallCount, 0);
      },
    );

    test('TC-361-02a ON stages the reaction ADD batch through the shared owner '
        'and delivers each committed row independently', () async {
      final events = <String>[];
      List<DirectEventFanoutTargetCandidate>? stagedCandidates;
      final (result, reaction) = await sendReaction(
        p2pService: p2pService,
        bridge: bridge,
        reactionRepo: reactionRepo,
        targetPeerId: 'peer-1',
        messageId: 'msg-1',
        emoji: '👍',
        senderPeerId: 'my-peer',
        recipientMlKemPublicKey: 'key-1',
        directEventFanout: fanoutAuthoring(
          selectorOn: true,
          targets: const ['peer-device-a', 'peer-device-b'],
          events: events,
          onStage: (candidates) => stagedCandidates = candidates,
        ),
      );
      expect(result, SendReactionResult.success);
      expect(reaction, isNotNull);
      expect(events.where((event) => event.startsWith('encrypt')).length, 2);
      expect(
        events.indexOf('stage:add'),
        greaterThan(events.lastIndexOf('resolve')),
      );
      expect(stagedCandidates, hasLength(2));
      expect(
        stagedCandidates!.map((candidate) => candidate.wireEnvelope).toSet(),
        hasLength(2),
        reason: 'one independent ciphertext per target',
      );
      expect(
        p2pService.storeInInboxCallCount,
        2,
        reason: 'each committed row rides its own protected store',
      );
      expect(
        reactionRepo.stageCallCount,
        0,
        reason: 'the shared fanout owner replaces the single-target stage',
      );
    });
  });

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
      'Plan 344 reaction ADD rejects generic stored without ack-or-expiry proof',
      () async {
        p2pService
          ..sendMessageResult = false
          ..automaticallyProveAckCustody = false
          ..detailedInboxOutcome = const InboxStoreOutcome(
            status: InboxStoreStatus.stored,
          );

        final (result, reaction) = await invoke();

        expect(result, SendReactionResult.sendFailed);
        expect(reaction, isNotNull);
        expect(reactionRepo.custodyRows, hasLength(1));
        expect(p2pService.lastCustodyKind, AckCustodyKind.directReactionV109);
      },
    );

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

class _U2IdempotentReactionRepository extends InMemoryDirectReactionCustodyRepository {
  @override
  Future<DirectReactionCustodyStageResult> stageOutgoingDirectReactionInboxCustody({
    required MessageReaction reaction, required String recipientPeerId,
    required String action, required String wireEnvelope,
  }) async {
    final owner = await super.stageOutgoingDirectReactionInboxCustody(
      reaction: reaction, recipientPeerId: recipientPeerId, action: action, wireEnvelope: wireEnvelope);
    return DirectReactionCustodyStageResult(outcome: DirectReactionCustodyStageOutcome.idempotent,
      reaction: owner.reaction, custody: owner.custody);
  }
}

class _U2ReactionActivityBridge extends FakeBridge {
  _U2ReactionActivityBridge() : super(initialResponses: {
    'message.encrypt': {'ok': true, 'kem': 'test-kem', 'ciphertext': 'test-cipher', 'nonce': 'test-nonce'},
  });
  final marks = <Map<String, dynamic>>[];
  Future<void> Function()? beforeEncrypt;
  Completer<void>? markBlock;
  bool throwOnMark = false;
  int revision = 0;
  @override
  bool get isInitialized => true;
  @override
  Future<String> send(String message) async {
    final envelope = jsonDecode(message) as Map<String, dynamic>;
    if (envelope['cmd'] == 'message.encrypt') await beforeEncrypt?.call();
    if (envelope['cmd'] != 'active_identity_reporter_v1') return super.send(message);
    final payload = Map<String, dynamic>.from(envelope['payload'] as Map);
    final op = payload['op'];
    if (op == 'mark') {
      marks.add(payload);
      if (throwOnMark) throw StateError('optional reporter unavailable');
      await markBlock?.future;
    }
    return jsonEncode({'ok': true, 'data': {
      'revision': op == 'configure' ? ++revision : payload['revision'],
      'consentEpoch': payload['consentEpoch'],
      if (op == 'configure') 'configured': payload['enabled'] == true && payload['profileBinding'] != '',
      if (op == 'mark') 'accepted': true,
      if (op == 'flush') 'queued': true,
    }});
  }
}
