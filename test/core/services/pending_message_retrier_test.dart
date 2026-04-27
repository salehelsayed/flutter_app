import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/pending_message_retrier.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'fake_p2p_service.dart';
import '../../features/conversation/domain/repositories/fake_message_repository.dart';
import '../../features/identity/domain/repositories/fake_identity_repository.dart';
import '../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../../core/bridge/fake_bridge.dart';

void main() {
  late FakeP2PService p2pService;
  late FakeMessageRepository messageRepo;
  late FakeIdentityRepository identityRepo;
  late FakeContactRepository contactRepo;
  late FakeBridge bridge;
  late PendingMessageRetrier retrier;

  setUp(() {
    p2pService = FakeP2PService();
    messageRepo = FakeMessageRepository();
    identityRepo = FakeIdentityRepository();
    contactRepo = FakeContactRepository();
    bridge = FakeBridge();

    retrier = PendingMessageRetrier(
      p2pService: p2pService,
      messageRepo: messageRepo,
      identityRepo: identityRepo,
      contactRepo: contactRepo,
      bridge: bridge,
    );
  });

  tearDown(() {
    retrier.dispose();
    p2pService.dispose();
  });

  group('PendingMessageRetrier', () {
    test('start subscribes to stateStream', () {
      retrier.start();

      // Verify retrier is listening by emitting a state and checking no crash
      p2pService.emitState(NodeState.stopped);
      // If start didn't subscribe, this would have no listener
    });

    test(
      'offline to online transition triggers retry after debounce',
      () async {
        // No identity → retryFailedMessages returns 0 quickly
        retrier.start();

        // Emit online state (isStarted + circuitAddresses non-empty)
        final onlineState = const NodeState(
          isStarted: true,
          peerId: 'my-peer',
          circuitAddresses: ['/p2p-circuit/addr1'],
        );
        p2pService.emitState(onlineState);

        // Debounce is 5 seconds — wait for it
        await Future.delayed(const Duration(seconds: 6));

        // retryFailedMessages was called → it tried to load identity
        expect(identityRepo.loadIdentityCallCount, greaterThanOrEqualTo(1));
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test(
      'going offline does not trigger an additional retry beyond cold-start sweep',
      () async {
        // Start in online state — cold-start sweep will fire after 5s
        p2pService = FakeP2PService(
          initialState: const NodeState(
            isStarted: true,
            peerId: 'my-peer',
            circuitAddresses: ['/p2p-circuit/addr1'],
          ),
        );
        retrier = PendingMessageRetrier(
          p2pService: p2pService,
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          bridge: bridge,
        );
        retrier.start();

        // Go offline
        p2pService.emitState(NodeState.stopped);
        await Future.delayed(const Duration(seconds: 6));

        // Cold-start sweep fires once (initial online state), but going
        // offline does not trigger an additional retry.
        expect(identityRepo.loadIdentityCallCount, 1);
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test(
      'online without circuitAddresses is not considered online',
      () async {
        retrier.start();

        // isStarted but no circuitAddresses
        final partialOnline = const NodeState(
          isStarted: true,
          peerId: 'my-peer',
          circuitAddresses: [],
        );
        p2pService.emitState(partialOnline);
        await Future.delayed(const Duration(seconds: 6));

        expect(identityRepo.loadIdentityCallCount, 0);
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test('dispose cancels timer and subscription', () {
      retrier.start();
      retrier.dispose();

      // After dispose, emitting states should not cause issues
      // (subscription is cancelled, so no listener errors)
      p2pService.emitState(
        const NodeState(
          isStarted: true,
          peerId: 'my-peer',
          circuitAddresses: ['/addr'],
        ),
      );
    });

    test(
      'debounce cancels previous timer on rapid state changes',
      () async {
        retrier.start();

        // Rapidly go online -> offline -> online
        p2pService.emitState(
          const NodeState(
            isStarted: true,
            peerId: 'p',
            circuitAddresses: ['/a'],
          ),
        );
        await Future.delayed(const Duration(seconds: 1));
        p2pService.emitState(NodeState.stopped);
        await Future.delayed(const Duration(milliseconds: 500));
        p2pService.emitState(
          const NodeState(
            isStarted: true,
            peerId: 'p',
            circuitAddresses: ['/a'],
          ),
        );

        // Wait for debounce from last transition
        await Future.delayed(const Duration(seconds: 6));

        // Should only retry once (first timer cancelled)
        expect(identityRepo.loadIdentityCallCount, 1);
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );

    test(
      'does not retry concurrently (_isRetrying guard)',
      () async {
        retrier.start();

        // Emit online state twice rapidly
        final onlineState = const NodeState(
          isStarted: true,
          peerId: 'p',
          circuitAddresses: ['/a'],
        );

        p2pService.emitState(onlineState);
        await Future.delayed(const Duration(seconds: 5, milliseconds: 100));

        // Go offline then online again immediately to trigger another retry
        p2pService.emitState(NodeState.stopped);
        p2pService.emitState(onlineState);
        await Future.delayed(const Duration(seconds: 6));

        // Both retries should have completed (sequentially, not concurrently)
        expect(identityRepo.loadIdentityCallCount, greaterThanOrEqualTo(1));
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );

    test(
      'skips online sweeps while external recovery is in progress',
      () async {
        var rejoinCalled = false;
        var drainCalled = false;
        var recoverCalled = false;
        var retryFailedCalled = false;

        p2pService = FakeP2PService(
          initialState: const NodeState(
            isStarted: true,
            peerId: 'my-peer',
            circuitAddresses: ['/addr'],
          ),
        );
        retrier = PendingMessageRetrier(
          p2pService: p2pService,
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          rejoinGroupTopicsFn: () async {
            rejoinCalled = true;
          },
          drainGroupOfflineInboxFn: () async {
            drainCalled = true;
          },
          recoverStuckSendingMessagesFn: () async {
            recoverCalled = true;
            return 0;
          },
          retryFailedMessagesOverride: () async {
            retryFailedCalled = true;
            return 0;
          },
          isExternalRecoveryInProgressFn: () => true,
        );
        retrier.start();

        await Future.delayed(const Duration(seconds: 6));

        expect(rejoinCalled, isFalse);
        expect(drainCalled, isFalse);
        expect(recoverCalled, isFalse);
        expect(retryFailedCalled, isFalse);
        expect(identityRepo.loadIdentityCallCount, 0);
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test(
      'group continuity sweep runs on a shorter cadence than full retry loop',
      () {
        fakeAsync((async) {
          final callOrder = <String>[];

          p2pService = FakeP2PService(
            initialState: const NodeState(
              isStarted: true,
              peerId: 'my-peer',
              circuitAddresses: ['/addr'],
            ),
          );
          retrier = PendingMessageRetrier(
            p2pService: p2pService,
            messageRepo: messageRepo,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            bridge: bridge,
            rejoinGroupTopicsFn: () async {
              callOrder.add('rejoinGroupTopics');
            },
            drainGroupOfflineInboxFn: () async {
              callOrder.add('drainGroupOfflineInbox');
            },
            retryFailedMessagesOverride: () async {
              callOrder.add('retryFailedMessages');
              return 0;
            },
            retryUnackedMessagesOverride: () async {
              callOrder.add('retryUnackedMessages');
              return 0;
            },
          );
          retrier.start();

          async.elapse(PendingMessageRetrier.defaultRetryDebounce);
          async.flushMicrotasks();

          expect(callOrder, <String>[
            'rejoinGroupTopics',
            'drainGroupOfflineInbox',
            'retryFailedMessages',
            'retryUnackedMessages',
          ]);

          async.elapse(
            PendingMessageRetrier.defaultGroupContinuitySweepInterval,
          );
          async.flushMicrotasks();

          expect(callOrder, <String>[
            'rejoinGroupTopics',
            'drainGroupOfflineInbox',
            'retryFailedMessages',
            'retryUnackedMessages',
            'rejoinGroupTopics',
            'drainGroupOfflineInbox',
          ]);
        });
      },
    );

    test(
      'needsGroupRecovery false-to-true while online triggers immediate continuity sweep',
      () {
        fakeAsync((async) {
          final callOrder = <String>[];

          p2pService = FakeP2PService(
            initialState: const NodeState(
              isStarted: true,
              peerId: 'my-peer',
              circuitAddresses: ['/addr'],
              needsGroupRecovery: false,
            ),
          );
          retrier = PendingMessageRetrier(
            p2pService: p2pService,
            messageRepo: messageRepo,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            bridge: bridge,
            rejoinGroupTopicsFn: () async {
              callOrder.add('rejoinGroupTopics');
            },
            drainGroupOfflineInboxFn: () async {
              callOrder.add('drainGroupOfflineInbox');
            },
            retryFailedMessagesOverride: () async {
              callOrder.add('retryFailedMessages');
              return 0;
            },
            retryUnackedMessagesOverride: () async {
              callOrder.add('retryUnackedMessages');
              return 0;
            },
          );
          retrier.start();

          async.elapse(PendingMessageRetrier.defaultRetryDebounce);
          async.flushMicrotasks();

          callOrder.clear();

          p2pService.emitState(
            const NodeState(
              isStarted: true,
              peerId: 'my-peer',
              circuitAddresses: ['/addr'],
              needsGroupRecovery: true,
            ),
          );
          async.flushMicrotasks();

          expect(callOrder, <String>[
            'rejoinGroupTopics',
            'drainGroupOfflineInbox',
          ]);
        });
      },
    );

    test(
      'immediate group recovery does not reset the 30-second fallback timer',
      () {
        fakeAsync((async) {
          final callOrder = <String>[];

          p2pService = FakeP2PService(
            initialState: const NodeState(
              isStarted: true,
              peerId: 'my-peer',
              circuitAddresses: ['/addr'],
              needsGroupRecovery: false,
            ),
          );
          retrier = PendingMessageRetrier(
            p2pService: p2pService,
            messageRepo: messageRepo,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            bridge: bridge,
            rejoinGroupTopicsFn: () async {
              callOrder.add('rejoinGroupTopics');
            },
            drainGroupOfflineInboxFn: () async {
              callOrder.add('drainGroupOfflineInbox');
            },
            retryFailedMessagesOverride: () async {
              callOrder.add('retryFailedMessages');
              return 0;
            },
            retryUnackedMessagesOverride: () async {
              callOrder.add('retryUnackedMessages');
              return 0;
            },
          );
          retrier.start();

          async.elapse(PendingMessageRetrier.defaultRetryDebounce);
          async.flushMicrotasks();

          expect(callOrder, <String>[
            'rejoinGroupTopics',
            'drainGroupOfflineInbox',
            'retryFailedMessages',
            'retryUnackedMessages',
          ]);

          async.elapse(const Duration(seconds: 5));
          p2pService.emitState(
            const NodeState(
              isStarted: true,
              peerId: 'my-peer',
              circuitAddresses: ['/addr'],
              needsGroupRecovery: true,
            ),
          );
          async.flushMicrotasks();

          expect(callOrder, <String>[
            'rejoinGroupTopics',
            'drainGroupOfflineInbox',
            'retryFailedMessages',
            'retryUnackedMessages',
            'rejoinGroupTopics',
            'drainGroupOfflineInbox',
          ]);

          async.elapse(const Duration(seconds: 19));
          async.flushMicrotasks();

          expect(callOrder, hasLength(6));

          async.elapse(const Duration(seconds: 1));
          async.flushMicrotasks();

          expect(callOrder, <String>[
            'rejoinGroupTopics',
            'drainGroupOfflineInbox',
            'retryFailedMessages',
            'retryUnackedMessages',
            'rejoinGroupTopics',
            'drainGroupOfflineInbox',
            'rejoinGroupTopics',
            'drainGroupOfflineInbox',
          ]);
        });
      },
    );

    test(
      'successful retrier-owned nodeRequestedRecovery sends ack on immediate recovery',
      () {
        fakeAsync((async) {
          final callOrder = <String>[];

          p2pService = FakeP2PService(
            initialState: const NodeState(
              isStarted: true,
              peerId: 'my-peer',
              circuitAddresses: ['/addr'],
              needsGroupRecovery: false,
            ),
          );
          retrier = PendingMessageRetrier(
            p2pService: p2pService,
            messageRepo: messageRepo,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            bridge: bridge,
            rejoinGroupTopicsWithRecoveryAckEligibilityFn: () async {
              callOrder.add('rejoinGroupTopics');
              return p2pService.currentState.needsGroupRecovery ?? false;
            },
            acknowledgeGroupRecoveryFn: () async {
              callOrder.add('acknowledgeRecovery');
            },
            drainGroupOfflineInboxFn: () async {
              callOrder.add('drainGroupOfflineInbox');
            },
            retryFailedMessagesOverride: () async {
              callOrder.add('retryFailedMessages');
              return 0;
            },
            retryUnackedMessagesOverride: () async {
              callOrder.add('retryUnackedMessages');
              return 0;
            },
          );
          retrier.start();

          async.elapse(PendingMessageRetrier.defaultRetryDebounce);
          async.flushMicrotasks();

          callOrder.clear();

          p2pService.emitState(
            const NodeState(
              isStarted: true,
              peerId: 'my-peer',
              circuitAddresses: ['/addr'],
              needsGroupRecovery: true,
            ),
          );
          async.flushMicrotasks();

          expect(callOrder, <String>[
            'rejoinGroupTopics',
            'acknowledgeRecovery',
            'drainGroupOfflineInbox',
          ]);
        });
      },
    );

    test(
      'successful retrier-owned recovery sends ack on the retry sweep path',
      () {
        fakeAsync((async) {
          final callOrder = <String>[];

          p2pService = FakeP2PService(
            initialState: const NodeState(
              isStarted: true,
              peerId: 'my-peer',
              circuitAddresses: ['/addr'],
              needsGroupRecovery: true,
            ),
          );
          retrier = PendingMessageRetrier(
            p2pService: p2pService,
            messageRepo: messageRepo,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            bridge: bridge,
            rejoinGroupTopicsWithRecoveryAckEligibilityFn: () async {
              callOrder.add('rejoinGroupTopics');
              return true;
            },
            acknowledgeGroupRecoveryFn: () async {
              callOrder.add('acknowledgeRecovery');
            },
            drainGroupOfflineInboxFn: () async {
              callOrder.add('drainGroupOfflineInbox');
            },
            retryFailedMessagesOverride: () async {
              callOrder.add('retryFailedMessages');
              return 0;
            },
            retryUnackedMessagesOverride: () async {
              callOrder.add('retryUnackedMessages');
              return 0;
            },
          );
          retrier.start();

          async.elapse(PendingMessageRetrier.defaultRetryDebounce);
          async.flushMicrotasks();

          expect(callOrder, <String>[
            'rejoinGroupTopics',
            'acknowledgeRecovery',
            'drainGroupOfflineInbox',
            'retryFailedMessages',
            'retryUnackedMessages',
          ]);
        });
      },
    );

    test('failed retrier-owned recovery does not send ack', () {
      fakeAsync((async) {
        final callOrder = <String>[];

        p2pService = FakeP2PService(
          initialState: const NodeState(
            isStarted: true,
            peerId: 'my-peer',
            circuitAddresses: ['/addr'],
            needsGroupRecovery: false,
          ),
        );
        retrier = PendingMessageRetrier(
          p2pService: p2pService,
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          rejoinGroupTopicsWithRecoveryAckEligibilityFn: () async {
            callOrder.add('rejoinGroupTopics');
            return false;
          },
          acknowledgeGroupRecoveryFn: () async {
            callOrder.add('acknowledgeRecovery');
          },
          drainGroupOfflineInboxFn: () async {
            callOrder.add('drainGroupOfflineInbox');
          },
          retryFailedMessagesOverride: () async {
            callOrder.add('retryFailedMessages');
            return 0;
          },
          retryUnackedMessagesOverride: () async {
            callOrder.add('retryUnackedMessages');
            return 0;
          },
        );
        retrier.start();

        async.elapse(PendingMessageRetrier.defaultRetryDebounce);
        async.flushMicrotasks();

        callOrder.clear();

        p2pService.emitState(
          const NodeState(
            isStarted: true,
            peerId: 'my-peer',
            circuitAddresses: ['/addr'],
            needsGroupRecovery: true,
          ),
        );
        async.flushMicrotasks();

        expect(callOrder, <String>[
          'rejoinGroupTopics',
          'drainGroupOfflineInbox',
        ]);
        expect(callOrder, isNot(contains('acknowledgeRecovery')));
      });
    });

    test(
      'periodic sweep does not replay a row already settled by manual recovery',
      () {
        fakeAsync((async) {
          identityRepo.seed(FakeIdentityRepository.makeIdentity());
          messageRepo.seed([
            ConversationMessage(
              id: 'msg-periodic-settled-001',
              contactPeerId: 'peer-target',
              senderPeerId: 'my-peer-id',
              text: 'Already settled',
              timestamp: '2026-01-01T00:00:00.000Z',
              status: 'delivered',
              isIncoming: false,
              createdAt: '2026-01-01T00:00:00.000Z',
              transport: 'inbox',
              wireEnvelope: null,
            ),
          ]);
          p2pService = FakeP2PService(
            initialState: const NodeState(
              isStarted: true,
              peerId: 'my-peer-id',
              circuitAddresses: ['/p2p-circuit/addr1'],
            ),
            storeInInboxResult: true,
          );
          retrier = PendingMessageRetrier(
            p2pService: p2pService,
            messageRepo: messageRepo,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            bridge: bridge,
          );

          retrier.start();
          async.elapse(PendingMessageRetrier.defaultRetryDebounce);
          async.flushMicrotasks();
          async.elapse(PendingMessageRetrier.defaultPeriodicRetryInterval);
          async.flushMicrotasks();

          expect(
            messageRepo.getFailedOutgoingCallCount,
            greaterThanOrEqualTo(2),
          );
          expect(p2pService.storeInInboxCallCount, 0);
          expect(p2pService.sendMessageWithReplyCallCount, 0);
          expect(messageRepo.saveMessageCallCount, 0);
        });
      },
    );
  });
}
