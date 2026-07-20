
import 'package:flutter_app/core/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../bridge/fake_bridge.dart';
import '../services/fake_p2p_service.dart';

/// FDC-04 (TC-04-11 / DESIGN-3 / SRC-1): resume eagerly warms the ONE active
/// conversation peer (PS-4 — never the roster), bounded and UNAWAITED (slotted
/// into FDC-05's parallel re-prime block so it never adds latency to the resume
/// future).
void main() {
  late FakeBridge fakeBridge;
  late FakeP2PService fakeP2PService;

  setUp(() {
    fakeBridge = FakeBridge();
    fakeP2PService = FakeP2PService(
      initialState: const NodeState(
        isStarted: true,
        peerId: 'my-peer',
        circuitAddresses: ['/p2p-circuit/addr1'],
      ),
    );
  });

  tearDown(() => fakeP2PService.dispose());

  group('handleAppResumed — FDC-04 eager warm of the active peer', () {
    // (a) active peer present → warmPeer(peerA) exactly once.
    test('TC-04-11(a): warms the active conversation peer exactly once',
        () async {
      await handleAppResumed(
        bridge: fakeBridge,
        p2pService: fakeP2PService,
        activeConversationPeerId: () => 'peer-A',
      );
      // The warm is fire-and-forget; give it a microtask turn to settle.
      await Future<void>.delayed(Duration.zero);
      expect(fakeP2PService.warmPeerCallCount, 1);
      expect(fakeP2PService.lastWarmPeerId, 'peer-A');
    });

    // (b) active-peer source returns null → no warm (Mutation B: warm
    // unconditionally → this re-reds).
    test('TC-04-11(b): no active peer → no warm', () async {
      await handleAppResumed(
        bridge: fakeBridge,
        p2pService: fakeP2PService,
        activeConversationPeerId: () => null,
      );
      await Future<void>.delayed(Duration.zero);
      expect(fakeP2PService.warmPeerCallCount, 0);
    });

    // A `group:` active key is NOT warmed — warmPeer is 1:1-only (the active
    // tracker can hold a group key; the resume warm must guard against it).
    test('TC-04-11: a group: active key is not warmed (1:1 only)', () async {
      await handleAppResumed(
        bridge: fakeBridge,
        p2pService: fakeP2PService,
        activeConversationPeerId: () => 'group:abc',
      );
      await Future<void>.delayed(Duration.zero);
      expect(fakeP2PService.warmPeerCallCount, 0);
    });

    // No active-peer source supplied at all (the default-null param) → no warm.
    test('TC-04-11: no active-peer source → no warm', () async {
      await handleAppResumed(bridge: fakeBridge, p2pService: fakeP2PService);
      await Future<void>.delayed(Duration.zero);
      expect(fakeP2PService.warmPeerCallCount, 0);
    });
  });
}
