import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/pending_message_retrier.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
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
    // The retrier now opens the process-global group recovery gate during its
    // group recovery pass and 30s continuity sweep; reset it so a test that
    // leaves a pass mid-flight cannot leak gate state into the next test.
    groupRecoveryGate.resetForTest();
  });

  group('PendingMessageRetrier', () {
    // 186 — reconnect self-heal latency tightening (FU-185-A). The first
    // post-online retry (debounced, so flappy transitions still coalesce) drops
    // the 60s unacked age gate so a freshly-queued offline message converges on
    // reconnect instead of after the 5-min periodic; the periodic pass keeps 60s.
    test(
      'TC-186-02 the reconnect (debounced) retry drops the unacked age gate '
      '(olderThan=0); the periodic pass keeps 60s',
      () {
        fakeAsync((async) {
          // No override -> the real retryUnackedMessages hits the fake repo,
          // which records the olderThan it was queried with.
          retrier = PendingMessageRetrier(
            p2pService: p2pService,
            messageRepo: messageRepo,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            bridge: bridge,
          );
          retrier.start(); // default FakeP2PService = stopped (offline)

          // Genuine offline -> online reconnect (relay reserved).
          p2pService.emitState(
            const NodeState(
              isStarted: true,
              peerId: 'my-peer',
              circuitAddresses: ['/addr'],
            ),
          );
          // The reconnect retry fires after the debounce, with the gate dropped.
          async.elapse(PendingMessageRetrier.defaultRetryDebounce);
          async.flushMicrotasks();
          expect(
            messageRepo.lastUnackedOlderThan,
            Duration.zero,
            reason:
                'the reconnect pass must not skip freshly-queued offline rows '
                '(RED on HEAD: hardcoded 60s)',
          );

          // The periodic pass keeps the 60s anti-race window.
          messageRepo.lastUnackedOlderThan = null;
          async.elapse(PendingMessageRetrier.defaultPeriodicRetryInterval);
          async.flushMicrotasks();
          expect(
            messageRepo.lastUnackedOlderThan,
            const Duration(seconds: 60),
            reason: 'the periodic pass keeps the anti-race window',
          );
        });
      },
    );

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

    test('BB-012 retrier-owned immediate recovery drains before ack', () {
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
          'drainGroupOfflineInbox',
          'acknowledgeRecovery',
        ]);
      });
    });

    test('BB-012 retrier-owned retry sweep drains before ack', () {
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
          'drainGroupOfflineInbox',
          'acknowledgeRecovery',
          'retryFailedMessages',
          'retryUnackedMessages',
        ]);
      });
    });

    test(
      'BB-012 retrier-owned recovery does not ack while drain is incomplete',
      () {
        fakeAsync((async) {
          final callOrder = <String>[];
          final drainCompleter = Completer<void>();

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
              return true;
            },
            acknowledgeGroupRecoveryFn: () async {
              callOrder.add('acknowledgeRecovery');
            },
            drainGroupOfflineInboxFn: () {
              callOrder.add('drainGroupOfflineInbox');
              if (p2pService.currentState.needsGroupRecovery != true) {
                return Future<void>.value();
              }
              return drainCompleter.future;
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

          drainCompleter.complete();
          async.flushMicrotasks();

          expect(callOrder, <String>[
            'rejoinGroupTopics',
            'drainGroupOfflineInbox',
            'acknowledgeRecovery',
          ]);
        });
      },
    );

    test('BB-012 retrier-owned recovery does not ack when drain fails', () {
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
            throw StateError('forced drain failure');
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
        expect(callOrder, isNot(contains('acknowledgeRecovery')));
      });
    });

    test(
      'NW-004 reconnect recovery sweep rejoins drains and acks before retries',
      () {
        fakeAsync((async) {
          final callOrder = <String>[];

          p2pService = FakeP2PService(
            initialState: const NodeState(
              isStarted: true,
              peerId: 'my-peer',
              circuitAddresses: ['/p2p-circuit/repaired'],
              needsGroupRecovery: true,
            ),
          );
          retrier = PendingMessageRetrier(
            p2pService: p2pService,
            messageRepo: messageRepo,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            bridge: bridge,
            retryDebounce: Duration.zero,
            rejoinGroupTopicsWithRecoveryAckEligibilityFn: () async {
              callOrder.add('rejoinGroupTopics');
              return true;
            },
            drainGroupOfflineInboxFn: () async {
              callOrder.add('drainGroupOfflineInbox');
            },
            acknowledgeGroupRecoveryFn: () async {
              callOrder.add('acknowledgeRecovery');
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

          async.elapse(Duration.zero);
          async.flushMicrotasks();

          expect(callOrder, <String>[
            'rejoinGroupTopics',
            'drainGroupOfflineInbox',
            'acknowledgeRecovery',
            'retryFailedMessages',
            'retryUnackedMessages',
          ]);
        });
      },
    );

    test(
      'NW-004 reconnect recovery sweep does not acknowledge failed drain',
      () {
        fakeAsync((async) {
          final callOrder = <String>[];

          p2pService = FakeP2PService(
            initialState: const NodeState(
              isStarted: true,
              peerId: 'my-peer',
              circuitAddresses: ['/p2p-circuit/repaired'],
              needsGroupRecovery: true,
            ),
          );
          retrier = PendingMessageRetrier(
            p2pService: p2pService,
            messageRepo: messageRepo,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            bridge: bridge,
            retryDebounce: Duration.zero,
            rejoinGroupTopicsWithRecoveryAckEligibilityFn: () async {
              callOrder.add('rejoinGroupTopics');
              return true;
            },
            drainGroupOfflineInboxFn: () async {
              callOrder.add('drainGroupOfflineInbox');
              throw StateError('NW-004 drain failure');
            },
            acknowledgeGroupRecoveryFn: () async {
              callOrder.add('acknowledgeRecovery');
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

          async.elapse(Duration.zero);
          async.flushMicrotasks();

          expect(callOrder, <String>[
            'rejoinGroupTopics',
            'drainGroupOfflineInbox',
            'retryFailedMessages',
            'retryUnackedMessages',
          ]);
          expect(callOrder, isNot(contains('acknowledgeRecovery')));
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

    test('GFR-002 readiness return runs queued group retry once', () {
      fakeAsync((async) {
        final callOrder = <String>[];

        p2pService = FakeP2PService(
          initialState: const NodeState(
            isStarted: true,
            peerId: 'my-peer',
            circuitAddresses: ['/p2p-circuit/relay-visible'],
            relayState: 'online',
            sendCapabilityReady: false,
            inboxCapabilityReady: false,
          ),
        );
        retrier = PendingMessageRetrier(
          p2pService: p2pService,
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          retryDebounce: Duration.zero,
          rejoinGroupTopicsWithRecoveryAckEligibilityFn: () async {
            callOrder.add('rejoinGroupTopics');
            return true;
          },
          drainGroupOfflineInboxFn: () async {
            callOrder.add('drainGroupOfflineInbox');
          },
          acknowledgeGroupRecoveryFn: () async {
            callOrder.add('acknowledgeRecovery');
          },
          recoverStuckSendingGroupMessagesFn: () async {
            callOrder.add('recoverStuckSendingGroupMessages');
            return 0;
          },
          retryIncompleteGroupUploadsFn: () async {
            callOrder.add('retryIncompleteGroupUploads');
            return 0;
          },
          retryFailedGroupMessagesFn: () async {
            callOrder.add('retryFailedGroupMessages');
            return 1;
          },
          retryFailedMessagesOverride: () async {
            callOrder.add('retryFailedMessages');
            return 0;
          },
          retryUnackedMessagesOverride: () async {
            callOrder.add('retryUnackedMessages');
            return 0;
          },
          retryFailedGroupInboxStoresFn: () async {
            callOrder.add('retryFailedGroupInboxStores');
            return 0;
          },
        );
        retrier.start();

        async.elapse(Duration.zero);
        async.flushMicrotasks();

        expect(callOrder, <String>[
          'retryFailedMessages',
          'retryUnackedMessages',
        ]);
        callOrder.clear();

        p2pService.emitState(
          const NodeState(
            isStarted: true,
            peerId: 'my-peer',
            circuitAddresses: ['/p2p-circuit/relay-visible'],
            relayState: 'online',
            sendCapabilityReady: true,
            inboxCapabilityReady: true,
          ),
        );

        async.elapse(Duration.zero);
        async.flushMicrotasks();

        // The publish-free group inbox-store confirm (retryFailedGroupInboxStores,
        // which promotes a reconcilable pending row to sent without re-sending)
        // MUST run BEFORE the re-publish retrier (retryFailedGroupMessages). Both
        // touch 'pending' rows; confirm-first prevents re-publishing — and thus
        // risking a duplicate delivery of — a pending row that custody already
        // resolved (GAP 3a).
        expect(callOrder, <String>[
          'rejoinGroupTopics',
          'drainGroupOfflineInbox',
          'acknowledgeRecovery',
          'recoverStuckSendingGroupMessages',
          'retryIncompleteGroupUploads',
          'retryFailedGroupInboxStores',
          'retryFailedGroupMessages',
          'retryFailedMessages',
          'retryUnackedMessages',
        ]);
      });
    });

    test('GFR-002 readiness flapping coalesces queued group retry', () {
      fakeAsync((async) {
        final retryGate = Completer<void>();
        var retryFailedGroupMessagesCalls = 0;

        retrier = PendingMessageRetrier(
          p2pService: p2pService,
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          retryDebounce: Duration.zero,
          retryFailedGroupMessagesFn: () {
            retryFailedGroupMessagesCalls++;
            return retryGate.future.then((_) => 1);
          },
          retryFailedMessagesOverride: () async => 0,
          retryUnackedMessagesOverride: () async => 0,
        );
        retrier.start();

        p2pService.emitState(
          const NodeState(
            isStarted: true,
            peerId: 'my-peer',
            circuitAddresses: ['/p2p-circuit/relay-visible'],
            relayState: 'online',
            sendCapabilityReady: true,
            inboxCapabilityReady: true,
          ),
        );
        async.elapse(Duration.zero);
        async.flushMicrotasks();

        expect(retryFailedGroupMessagesCalls, 1);

        p2pService.emitState(
          const NodeState(
            isStarted: true,
            peerId: 'my-peer',
            circuitAddresses: ['/p2p-circuit/relay-visible'],
            relayState: 'online',
            sendCapabilityReady: false,
            inboxCapabilityReady: false,
          ),
        );
        p2pService.emitState(
          const NodeState(
            isStarted: true,
            peerId: 'my-peer',
            circuitAddresses: ['/p2p-circuit/relay-visible'],
            relayState: 'online',
            sendCapabilityReady: true,
            inboxCapabilityReady: true,
          ),
        );
        async.elapse(Duration.zero);
        async.flushMicrotasks();

        expect(retryFailedGroupMessagesCalls, 1);

        retryGate.complete();
        async.flushMicrotasks();

        expect(retryFailedGroupMessagesCalls, 1);
      });
    });

    test(
      'GFR-002 app resume external recovery suppresses relay-ready auto recovery',
      () {
        fakeAsync((async) {
          var rejoinCalled = false;
          var drainCalled = false;
          var retryFailedGroupMessagesCalled = false;

          retrier = PendingMessageRetrier(
            p2pService: p2pService,
            messageRepo: messageRepo,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            bridge: bridge,
            retryDebounce: Duration.zero,
            rejoinGroupTopicsFn: () async {
              rejoinCalled = true;
            },
            drainGroupOfflineInboxFn: () async {
              drainCalled = true;
            },
            retryFailedGroupMessagesFn: () async {
              retryFailedGroupMessagesCalled = true;
              return 0;
            },
            retryFailedMessagesOverride: () async => 0,
            retryUnackedMessagesOverride: () async => 0,
            isExternalRecoveryInProgressFn: () => true,
          );
          retrier.start();

          p2pService.emitState(
            const NodeState(
              isStarted: true,
              peerId: 'my-peer',
              circuitAddresses: ['/p2p-circuit/relay-visible'],
              relayState: 'online',
              sendCapabilityReady: true,
              inboxCapabilityReady: true,
            ),
          );
          async.elapse(Duration.zero);
          async.flushMicrotasks();

          expect(rejoinCalled, isFalse);
          expect(drainCalled, isFalse);
          expect(retryFailedGroupMessagesCalled, isFalse);
        });
      },
    );

    test(
      'GFR-002 enableResumeGroupRecovery false disables auto group retry',
      () {
        fakeAsync((async) {
          var rejoinCalled = false;
          var drainCalled = false;
          var retryFailedGroupMessagesCalled = false;
          var retryFailedMessagesCalled = false;

          retrier = PendingMessageRetrier(
            p2pService: p2pService,
            messageRepo: messageRepo,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            bridge: bridge,
            retryDebounce: Duration.zero,
            rejoinGroupTopicsFn: () async {
              rejoinCalled = true;
            },
            drainGroupOfflineInboxFn: () async {
              drainCalled = true;
            },
            retryFailedGroupMessagesFn: () async {
              retryFailedGroupMessagesCalled = true;
              return 0;
            },
            retryFailedMessagesOverride: () async {
              retryFailedMessagesCalled = true;
              return 0;
            },
            retryUnackedMessagesOverride: () async => 0,
          );
          retrier.start();

          p2pService.emitState(
            const NodeState(
              isStarted: true,
              peerId: 'my-peer',
              circuitAddresses: ['/p2p-circuit/relay-visible'],
              relayState: 'online',
              featureFlags: {'enableResumeGroupRecovery': false},
              sendCapabilityReady: true,
              inboxCapabilityReady: true,
            ),
          );
          async.elapse(Duration.zero);
          async.flushMicrotasks();

          expect(rejoinCalled, isFalse);
          expect(drainCalled, isFalse);
          expect(retryFailedGroupMessagesCalled, isFalse);
          expect(retryFailedMessagesCalled, isTrue);
        });
      },
    );

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

  group('PendingMessageRetrier group recovery gate (P1.3)', () {
    const onlineState = NodeState(
      isStarted: true,
      peerId: 'my-peer',
      circuitAddresses: ['/addr'],
    );

    setUp(() => groupRecoveryGate.resetForTest());
    tearDown(() => groupRecoveryGate.resetForTest());

    test('group recovery + outbound repair steps run while the gate is held; '
        '1:1 steps run after the gate releases', () {
      fakeAsync((async) {
        final gateDuring = <String, bool>{};

        p2pService = FakeP2PService(initialState: onlineState);
        retrier = PendingMessageRetrier(
          p2pService: p2pService,
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          rejoinGroupTopicsFn: () async {
            gateDuring['rejoin'] = isGroupRecoveryInProgress();
          },
          drainGroupOfflineInboxFn: () async {
            gateDuring['drain'] = isGroupRecoveryInProgress();
          },
          recoverStuckSendingGroupMessagesFn: () async {
            gateDuring['recoverStuckGroup'] = isGroupRecoveryInProgress();
            return 0;
          },
          retryIncompleteGroupUploadsFn: () async {
            gateDuring['uploadsGroup'] = isGroupRecoveryInProgress();
            return 0;
          },
          retryFailedGroupInboxStoresFn: () async {
            gateDuring['inboxStores'] = isGroupRecoveryInProgress();
            return 0;
          },
          retryFailedGroupMessagesFn: () async {
            gateDuring['failedMessagesGroup'] = isGroupRecoveryInProgress();
            return 0;
          },
          // A 1:1 step — must observe the gate released (scoped to group).
          retryFailedMessagesOverride: () async {
            gateDuring['failedMessages1to1'] = isGroupRecoveryInProgress();
            return 0;
          },
          retryUnackedMessagesOverride: () async => 0,
        );
        retrier.start();
        async.elapse(PendingMessageRetrier.defaultRetryDebounce);
        async.flushMicrotasks();

        // Every group step saw the gate held.
        expect(gateDuring['rejoin'], isTrue);
        expect(gateDuring['drain'], isTrue);
        expect(gateDuring['recoverStuckGroup'], isTrue);
        expect(gateDuring['uploadsGroup'], isTrue);
        expect(gateDuring['inboxStores'], isTrue);
        expect(gateDuring['failedMessagesGroup'], isTrue);
        // The 1:1 step ran with the gate already released.
        expect(gateDuring['failedMessages1to1'], isFalse);
        // Gate fully released after the pass.
        expect(isGroupRecoveryInProgress(), isFalse);
      });
    });

    test('group pass preserves the 12-step order including GAP-3a '
        '(inbox-store custody-confirm before re-publish)', () {
      fakeAsync((async) {
        final order = <String>[];

        p2pService = FakeP2PService(initialState: onlineState);
        retrier = PendingMessageRetrier(
          p2pService: p2pService,
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          rejoinGroupTopicsWithRecoveryAckEligibilityFn: () async {
            order.add('rejoin');
            return true;
          },
          acknowledgeGroupRecoveryFn: () async => order.add('ack'),
          drainGroupOfflineInboxFn: () async => order.add('drain'),
          recoverStuckSendingGroupMessagesFn: () async {
            order.add('recoverStuckGroup');
            return 0;
          },
          retryIncompleteGroupUploadsFn: () async {
            order.add('uploadsGroup');
            return 0;
          },
          retryFailedGroupInboxStoresFn: () async {
            order.add('inboxStores');
            return 0;
          },
          retryFailedGroupMessagesFn: () async {
            order.add('failedMessagesGroup');
            return 0;
          },
          recoverStuckSendingMessagesFn: () async {
            order.add('recoverStuck1to1');
            return 0;
          },
          retryIncompleteUploadsFn: () async {
            order.add('uploads1to1');
            return 0;
          },
          retryFailedMessagesOverride: () async {
            order.add('failedMessages1to1');
            return 0;
          },
          retryUnackedMessagesOverride: () async {
            order.add('unacked1to1');
            return 0;
          },
          retryPendingIntroductionDeliveriesFn: () async {
            order.add('intro');
            return 0;
          },
        );
        retrier.start();
        async.elapse(PendingMessageRetrier.defaultRetryDebounce);
        async.flushMicrotasks();

        expect(order, <String>[
          'rejoin',
          'drain',
          'ack',
          'recoverStuckGroup',
          'uploadsGroup',
          'inboxStores',
          'failedMessagesGroup',
          'recoverStuck1to1',
          'uploads1to1',
          'failedMessages1to1',
          'unacked1to1',
          'intro',
        ]);
        // GAP-3a invariant: custody-confirm strictly precedes re-publish.
        expect(
          order.indexOf('inboxStores'),
          lessThan(order.indexOf('failedMessagesGroup')),
        );
      });
    });

    test('retrier skips its pass while an external pass holds the recovery gate '
        '(the main.dart provider OR-in path, _isResuming false)', () {
      fakeAsync((async) {
        var rejoinCalled = false;
        var failed1to1Called = false;
        final hold = Completer<void>();

        // Simulate the startup/resume recovery pass holding the gate.
        unawaited(runWithGroupRecoveryGate(() => hold.future));
        expect(isGroupRecoveryInProgress(), isTrue);

        p2pService = FakeP2PService(initialState: onlineState);
        retrier = PendingMessageRetrier(
          p2pService: p2pService,
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          rejoinGroupTopicsFn: () async {
            rejoinCalled = true;
          },
          drainGroupOfflineInboxFn: () async {},
          retryFailedMessagesOverride: () async {
            failed1to1Called = true;
            return 0;
          },
          // Mirrors main.dart: _isResuming(false) || isGroupRecoveryInProgress().
          isExternalRecoveryInProgressFn: () =>
              false || isGroupRecoveryInProgress(),
        );
        retrier.start();
        async.elapse(PendingMessageRetrier.defaultRetryDebounce);
        async.flushMicrotasks();

        // Whole pass skipped — neither group nor 1:1 steps ran.
        expect(rejoinCalled, isFalse);
        expect(failed1to1Called, isFalse);

        hold.complete();
        async.flushMicrotasks();
      });
    });

    test(
      'continuity sweep skips (does not queue) and emits GATE_ACTIVE while an '
      'external pass holds the recovery gate (P1.3b OrSkip path)',
      () {
        fakeAsync((async) {
          final events = <String>[];
          debugSetFlowEventSink((p) => events.add(p['event'] as String));
          addTearDown(() => debugSetFlowEventSink(null));

          var rejoinCalled = false;
          var drainCalled = false;
          final hold = Completer<void>();

          // An external recovery pass (startup/resume) holds the gate.
          unawaited(runWithGroupRecoveryGate(() => hold.future));
          expect(isGroupRecoveryInProgress(), isTrue);

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
              rejoinCalled = true;
            },
            drainGroupOfflineInboxFn: () async {
              drainCalled = true;
            },
            // Entry guard must NOT short-circuit — we want to reach the
            // gate-level OrSkip path, not the _isExternalRecoveryInProgressFn
            // early return.
            isExternalRecoveryInProgressFn: () => false,
          );
          retrier.start();

          // needsGroupRecovery false->true while online triggers the immediate
          // continuity sweep (no timer elapse needed).
          p2pService.emitState(
            const NodeState(
              isStarted: true,
              peerId: 'my-peer',
              circuitAddresses: ['/addr'],
              needsGroupRecovery: true,
            ),
          );
          async.flushMicrotasks();

          // Skipped at the gate (OrSkip returned null), not run.
          expect(rejoinCalled, isFalse);
          expect(drainCalled, isFalse);
          expect(
            events,
            contains('PENDING_RETRIER_GROUP_SWEEP_SKIPPED_GATE_ACTIVE'),
          );
          // It was the gate-level skip, not the entry-guard skip.
          expect(
            events,
            isNot(
              contains('PENDING_RETRIER_GROUP_SWEEP_SKIPPED_EXTERNAL_RECOVERY'),
            ),
          );

          // Releasing the external pass must NOT retroactively run the skipped
          // sweep — proves OrSkip (skip) instead of runWithGroupRecoveryGate
          // (queue), which would dequeue and run the steps here.
          hold.complete();
          async.flushMicrotasks();
          expect(rejoinCalled, isFalse);
          expect(drainCalled, isFalse);
        });
      },
    );
  });
}
