import 'dart:io';

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

  // G-F (Finding 02 Slice 1): the pending-key-repair sweep must run AFTER the
  // Step 3c offline-inbox drain. Step 3c calls the real drainGroupOfflineInbox
  // directly (not an injectable Fn) and is gated on needsGroupRecovery, so the
  // runtime order-recorder above cannot observe it — a source-order lock guards
  // the 3c→8i relationship against a future reorder that would re-create the
  // undecryptable-message bug (sweep running before fresh messages/keys land).
  test(
    'Step 3c drainGroupOfflineInbox precedes the Step 8i pending-key-repair '
    'sweep in source (sweep must be after the drain)',
    () async {
      final source = await File(
        'lib/app/lifecycle/handle_app_resumed.dart',
      ).readAsString();

      final step3cIndex = source.indexOf(
        'Step 3c: drainGroupOfflineInbox() starting...',
      );
      expect(
        step3cIndex,
        isNonNegative,
        reason: 'Step 3c drainGroupOfflineInbox marker must exist in source',
      );

      final step8iIndex = source.indexOf(
        'Step 8i: retryAllPendingGroupKeyRepairs=',
      );
      expect(
        step8iIndex,
        isNonNegative,
        reason:
            'Step 8i pending-key-repair sweep marker must exist in source',
      );

      expect(
        step3cIndex,
        lessThan(step8iIndex),
        reason:
            'Step 3c offline-inbox drain must run before the Step 8i pending-'
            'key-repair sweep so freshly drained group messages/keys are '
            'present when the sweep re-fires persisted repairs',
      );
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
