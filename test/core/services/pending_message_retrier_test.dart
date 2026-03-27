import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/pending_message_retrier.dart';
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
  });
}
