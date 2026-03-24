import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../services/fake_p2p_service.dart';
import '../bridge/fake_bridge.dart';

void main() {
  group('handleAppResumed — stuck sending recovery', () {
    late FakeBridge bridge;
    late FakeP2PService p2pService;

    setUp(() {
      bridge = FakeBridge();
      p2pService = FakeP2PService(
        initialState: const NodeState(
          isStarted: true,
          peerId: 'my-peer',
          circuitAddresses: ['/p2p-circuit/addr1'],
        ),
      );
    });

    tearDown(() {
      p2pService.dispose();
    });

    test('calls recoverStuckSendingMessages on resume when callback provided',
        () async {
      int recoverCallCount = 0;

      await handleAppResumed(
        bridge: bridge,
        p2pService: p2pService,
        recoverStuckSendingMessagesFn: () async {
          recoverCallCount++;
          return 0;
        },
      );

      expect(recoverCallCount, 1);
    });

    test('does not call recoverStuckSendingMessages when callback is null',
        () async {
      // callback not passed — old callers that haven't been wired yet
      await handleAppResumed(
        bridge: bridge,
        p2pService: p2pService,
      );

      // No crash, and no call on any repo
    });

    test('recovery is called before retryFailedMessages step',
        () async {
      final callOrder = <String>[];

      await handleAppResumed(
        bridge: bridge,
        p2pService: p2pService,
        recoverStuckSendingMessagesFn: () async {
          callOrder.add('recover');
          return 0;
        },
        retryFailedMessagesFn: () async {
          callOrder.add('retryFailed');
          return 0;
        },
      );

      // recoverStuckSendingMessages must appear before retryFailedMessages
      expect(callOrder.contains('recover'), isTrue);
      expect(callOrder.contains('retryFailed'), isTrue);
      expect(callOrder.indexOf('recover'), lessThan(callOrder.indexOf('retryFailed')));
    });

    test('bridge health check error does not prevent recovery from running',
        () async {
      bridge.checkHealthResult = false; // forces reinitialize path
      int recoverCallCount = 0;

      await handleAppResumed(
        bridge: bridge,
        p2pService: p2pService,
        recoverStuckSendingMessagesFn: () async {
          recoverCallCount++;
          return 0;
        },
      );

      expect(recoverCallCount, 1);
    });

    test('recovery error is swallowed and resume completes', () async {
      final result = await handleAppResumed(
        bridge: bridge,
        p2pService: p2pService,
        recoverStuckSendingMessagesFn: () async {
          throw Exception('recovery error');
        },
      );

      // handleAppResumed must not propagate the error
      expect(result, isNotNull);
    });
  });
}
