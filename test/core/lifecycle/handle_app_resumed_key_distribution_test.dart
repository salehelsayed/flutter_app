import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/app/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../services/fake_p2p_service.dart';
import '../bridge/fake_bridge.dart';

void main() {
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

  test(
    'resume handler Step 8h drains deferred key distributions (Finding 03 Slice 2)',
    () async {
      var callCount = 0;

      await handleAppResumed(
        bridge: bridge,
        p2pService: p2pService,
        drainPendingKeyDistributionsFn: () async {
          callCount++;
          return 2;
        },
      );

      expect(callCount, 1);
    },
  );

  test(
    'resume handler Step 8h is fault-isolated from other resume steps',
    () async {
      var inboxStoresCalled = false;
      var distributionDrainCalled = false;

      await handleAppResumed(
        bridge: bridge,
        p2pService: p2pService,
        retryFailedGroupInboxStoresFn: () async {
          inboxStoresCalled = true;
          return 0;
        },
        drainPendingKeyDistributionsFn: () async {
          distributionDrainCalled = true;
          throw Exception('distribution drain blew up');
        },
      );

      // The prior step ran, and the drain throw did not crash resume.
      expect(inboxStoresCalled, isTrue);
      expect(distributionDrainCalled, isTrue);
    },
  );

  test('resume handler continues when the drain callback is null', () async {
    final result = await handleAppResumed(
      bridge: bridge,
      p2pService: p2pService,
    );
    expect(result, isTrue);
  });
}
