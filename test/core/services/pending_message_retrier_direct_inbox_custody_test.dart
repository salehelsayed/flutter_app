import 'dart:async';

import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/services/pending_message_retrier.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/drain_direct_inbox_custody_outbox_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_inbox_custody_outbox_entry.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../../features/conversation/domain/repositories/fake_message_repository.dart';
import '../../features/identity/domain/repositories/fake_identity_repository.dart';
import '../bridge/fake_bridge.dart';
import 'fake_p2p_service.dart';

void main() {
  const online = NodeState(
    isStarted: true,
    peerId: 'my-peer',
    circuitAddresses: <String>['/relay'],
  );

  tearDown(groupRecoveryGate.resetForTest);

  test(
    'TC-342-06 retrier lifecycle drains direct custody before message rebuild without cross-family starvation',
    () async {
      Future<List<String>> runFullPass({
        required bool startsOnline,
        required bool periodic,
        bool drainThrows = false,
      }) async {
        final calls = <String>[];
        final completed = Completer<void>();
        final p2pService = FakeP2PService(
          initialState: startsOnline ? online : NodeState.stopped,
        );
        final retrier = PendingMessageRetrier(
          p2pService: p2pService,
          messageRepo: FakeMessageRepository(),
          identityRepo: FakeIdentityRepository(),
          contactRepo: FakeContactRepository(),
          bridge: FakeBridge(),
          retryDebounce: periodic ? const Duration(days: 1) : Duration.zero,
          periodicRetryInterval: periodic
              ? const Duration(milliseconds: 1)
              : const Duration(days: 1),
          groupContinuitySweepInterval: const Duration(days: 1),
          recoverStuckSendingMessagesFn: () async {
            calls.add('recover');
            return 0;
          },
          retryIncompleteUploadsFn: () async {
            calls.add('upload');
            return 0;
          },
          retryIncompleteUploadsPeriodicFn: () async {
            calls.add('upload');
            return 0;
          },
          drainDirectInboxCustodyOutboxFn: () async {
            calls.add('directCustody');
            if (drainThrows) throw StateError('forced custody drain failure');
            return 0;
          },
          retryFailedMessagesOverride: () async {
            calls.add('failed');
            return 0;
          },
          retryUnackedMessagesOverride: () async {
            calls.add('unacked');
            if (!completed.isCompleted) completed.complete();
            return 0;
          },
        );

        retrier.start();
        if (!startsOnline) p2pService.emitState(online);
        await completed.future.timeout(const Duration(seconds: 2));
        retrier.dispose();
        p2pService.dispose();
        groupRecoveryGate.resetForTest();
        return calls;
      }

      // Cold start with an already-online node owns the same ordered pass.
      expect(await runFullPass(startsOnline: true, periodic: false), <String>[
        'recover',
        'upload',
        'directCustody',
        'failed',
        'unacked',
      ]);

      // A reconnect drain failure is isolated from both rebuild families.
      expect(
        await runFullPass(
          startsOnline: false,
          periodic: false,
          drainThrows: true,
        ),
        <String>['recover', 'upload', 'directCustody', 'failed', 'unacked'],
      );

      // The existing periodic cadence owns custody without introducing a new
      // timer and preserves the same ordering.
      expect(await runFullPass(startsOnline: true, periodic: true), <String>[
        'recover',
        'upload',
        'directCustody',
        'failed',
        'unacked',
      ]);

      // OS connectivity restoration uses its existing light pass. Custody is
      // first, and its failure cannot suppress the zero-age unacked family.
      final restoredCalls = <String>[];
      final restoredCompleted = Completer<void>();
      final restoredSignal = StreamController<void>.broadcast(sync: true);
      final restoredP2p = FakeP2PService();
      final restoredRetrier = PendingMessageRetrier(
        p2pService: restoredP2p,
        messageRepo: FakeMessageRepository(),
        identityRepo: FakeIdentityRepository(),
        contactRepo: FakeContactRepository(),
        bridge: FakeBridge(),
        networkRestoredSignal: restoredSignal.stream,
        networkRestoredDebounce: Duration.zero,
        drainDirectInboxCustodyOutboxFn: () async {
          restoredCalls.add('directCustody');
          throw StateError('forced restored custody drain failure');
        },
        retryUnackedMessagesOverride: () async {
          restoredCalls.add('unacked');
          restoredCompleted.complete();
          return 0;
        },
      );
      restoredRetrier.start();
      restoredSignal.add(null);
      await restoredCompleted.future.timeout(const Duration(seconds: 2));
      expect(restoredCalls, <String>['directCustody', 'unacked']);
      restoredRetrier.dispose();
      restoredP2p.dispose();
      await restoredSignal.close();

      // The node-online and OS-restored owners may legitimately overlap. The
      // retrier must let the idempotent drain boundary observe both calls and
      // let both existing retry tails continue once they settle.
      final overlapSignal = StreamController<void>.broadcast(sync: true);
      final overlapP2p = FakeP2PService();
      final twoDrainsStarted = Completer<void>();
      final releaseDrains = Completer<void>();
      final bothTailsCompleted = Completer<void>();
      var activeDrains = 0;
      var maxActiveDrains = 0;
      var unackedCalls = 0;
      var failedCalls = 0;
      final overlapRetrier = PendingMessageRetrier(
        p2pService: overlapP2p,
        messageRepo: FakeMessageRepository(),
        identityRepo: FakeIdentityRepository(),
        contactRepo: FakeContactRepository(),
        bridge: FakeBridge(),
        networkRestoredSignal: overlapSignal.stream,
        retryDebounce: Duration.zero,
        networkRestoredDebounce: Duration.zero,
        periodicRetryInterval: const Duration(days: 1),
        groupContinuitySweepInterval: const Duration(days: 1),
        drainDirectInboxCustodyOutboxFn: () async {
          activeDrains++;
          if (activeDrains > maxActiveDrains) {
            maxActiveDrains = activeDrains;
          }
          if (activeDrains == 2 && !twoDrainsStarted.isCompleted) {
            twoDrainsStarted.complete();
          }
          await releaseDrains.future;
          activeDrains--;
          return 0;
        },
        retryFailedMessagesOverride: () async {
          failedCalls++;
          return 0;
        },
        retryUnackedMessagesOverride: () async {
          unackedCalls++;
          if (unackedCalls == 2 && !bothTailsCompleted.isCompleted) {
            bothTailsCompleted.complete();
          }
          return 0;
        },
      );
      overlapRetrier.start();
      overlapSignal.add(null);
      overlapP2p.emitState(online);
      await twoDrainsStarted.future.timeout(const Duration(seconds: 2));
      releaseDrains.complete();
      await bothTailsCompleted.future.timeout(const Duration(seconds: 2));
      expect(maxActiveDrains, 2);
      expect(failedCalls, 1);
      expect(unackedCalls, 2);
      overlapRetrier.dispose();
      overlapP2p.dispose();
      await overlapSignal.close();
    },
  );

  test(
    'TC-342-06 global drain plus bulk failed retry stores a retained custody row once',
    () async {
      final messageRepo = FakeMessageRepository();
      final identityRepo = FakeIdentityRepository()
        ..seed(FakeIdentityRepository.makeIdentity());
      final contactRepo = FakeContactRepository()
        ..seed(const <ContactModel>[
          ContactModel(
            peerId: 'peer-target',
            publicKey: 'contact-public-key',
            rendezvous: '/ip4/127.0.0.1/tcp/4001',
            username: 'Target',
            signature: 'signature',
            scannedAt: '2026-08-06T10:00:00.000Z',
            mlKemPublicKey: 'contact-ml-kem-key',
          ),
        ]);
      const message = ConversationMessage(
        id: 'retained-custody-message',
        contactPeerId: 'peer-target',
        senderPeerId: 'my-peer-id',
        text: 'immutable direct text',
        timestamp: '2026-08-06T10:00:00.000Z',
        status: 'failed',
        isIncoming: false,
        createdAt: '2026-08-06T10:00:00.000Z',
      );
      messageRepo
        ..seed(const <ConversationMessage>[message])
        ..seedDirectInboxCustody(
          const DirectInboxCustodyOutboxEntry(
            recipientPeerId: 'peer-target',
            messageId: 'retained-custody-message',
            incarnationId: '0123456789abcdef0123456789abcdef',
            wireEnvelope: 'exact-retained-envelope',
            retryCount: 0,
            lastAttemptAt: null,
            lastErrorCode: null,
            createdAt: '2026-08-06T10:00:00.000Z',
            updatedAt: '2026-08-06T10:00:00.000Z',
          ),
        );
      final p2pService = FakeP2PService(
        initialState: online,
        storeInInboxResult: false,
      );
      final bridge = FakeBridge();
      final passCompleted = Completer<void>();
      final retrier = PendingMessageRetrier(
        p2pService: p2pService,
        messageRepo: messageRepo,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        retryDebounce: Duration.zero,
        periodicRetryInterval: const Duration(days: 1),
        groupContinuitySweepInterval: const Duration(days: 1),
        drainDirectInboxCustodyOutboxFn: () => drainDirectInboxCustodyOutbox(
          custodyRepository: messageRepo,
          storeInInboxDetailed: (toPeerId, envelope, {int? timeoutMs}) async {
            final stored = await p2pService.storeInInbox(
              toPeerId,
              envelope,
              timeoutMs: timeoutMs,
            );
            return InboxStoreOutcome(
              status: stored
                  ? InboxStoreStatus.stored
                  : InboxStoreStatus.failed,
            );
          },
        ),
        retryUnackedMessagesOverride: () async {
          if (!passCompleted.isCompleted) passCompleted.complete();
          return 0;
        },
      );
      addTearDown(retrier.dispose);
      addTearDown(p2pService.dispose);

      retrier.start();
      await passCompleted.future.timeout(const Duration(seconds: 2));

      expect(p2pService.storeInInboxCallCount, 1);
      expect(
        p2pService.storeInInboxLog.single.message,
        'exact-retained-envelope',
      );
      expect(p2pService.sendMessageCallCount, 0);
      expect(p2pService.sendMessageWithReplyCallCount, 0);
      expect(bridge.sendCallCount, 0);
      final retained = messageRepo.directCustodyRows.values.single;
      expect(retained.retryCount, 1);
      expect(retained.lastErrorCode, DirectInboxCustodyErrorCode.storeFailed);
      expect((await messageRepo.getMessage(message.id))!.status, 'failed');
    },
  );
}
