import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/lifecycle/handle_app_resumed.dart';
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
    'Step 8i pending-key-repair sweep runs AFTER the Step 8h key-distribution '
    'drain (freshly-drained keys must be present first)',
    () async {
      final order = <String>[];

      await handleAppResumed(
        bridge: bridge,
        p2pService: p2pService,
        drainPendingKeyDistributionsFn: () async {
          order.add('8h_drain');
          return 0;
        },
        retryAllPendingGroupKeyRepairsFn: () async {
          order.add('8i_sweep');
          return 0;
        },
      );

      expect(order, ['8h_drain', '8i_sweep']);
    },
  );

  test(
    'Step 8i sweep is fault-isolated: a throw in the prior Step 8h does not '
    'skip the sweep and resume still completes',
    () async {
      var sweepCalled = false;

      final result = await handleAppResumed(
        bridge: bridge,
        p2pService: p2pService,
        drainPendingKeyDistributionsFn: () async {
          throw Exception('Step 8h blew up');
        },
        retryAllPendingGroupKeyRepairsFn: () async {
          sweepCalled = true;
          return 0;
        },
      );

      expect(sweepCalled, isTrue);
      expect(result, isTrue);
    },
  );

  test('a throw inside the Step 8i sweep does not crash resume', () async {
    final result = await handleAppResumed(
      bridge: bridge,
      p2pService: p2pService,
      retryAllPendingGroupKeyRepairsFn: () async {
        throw Exception('Step 8i sweep blew up');
      },
    );

    expect(result, isTrue);
  });

  test(
    'resume completes normally when the sweep fn is null (ungated + optional)',
    () async {
      final result = await handleAppResumed(
        bridge: bridge,
        p2pService: p2pService,
      );

      expect(result, isTrue);
    },
  );
}
