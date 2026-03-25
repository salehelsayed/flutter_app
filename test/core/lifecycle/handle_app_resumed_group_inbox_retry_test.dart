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

  test('resume handler Step 8e calls retryFailedGroupInboxStoresFn', () async {
    int callCount = 0;

    await handleAppResumed(
      bridge: bridge,
      p2pService: p2pService,
      retryFailedGroupInboxStoresFn: () async {
        callCount++;
        return 3;
      },
    );

    expect(callCount, 1);
  });

  test('resume handler Step 8e is fault-isolated from Step 8d', () async {
    bool step8dCalled = false;
    bool step8eCalled = false;

    await handleAppResumed(
      bridge: bridge,
      p2pService: p2pService,
      retryUnackedMessagesFn: () async {
        step8dCalled = true;
        throw Exception('Step 8d blew up');
      },
      retryFailedGroupInboxStoresFn: () async {
        step8eCalled = true;
        return 0;
      },
    );

    // Both should be called even though 8d threw
    expect(step8dCalled, isTrue);
    expect(step8eCalled, isTrue);
  });

  test('resume handler continues normally when retryFailedGroupInboxStoresFn is null', () async {
    // Should not throw when the callback is not provided
    final result = await handleAppResumed(
      bridge: bridge,
      p2pService: p2pService,
    );

    expect(result, isTrue);
  });
}
