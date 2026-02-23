import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/p2p/application/stop_node_use_case.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import '../../../core/services/fake_p2p_service.dart';

/// FakeP2PService subclass that throws on stopNode().
class _ThrowingStopFakeP2PService extends FakeP2PService {
  _ThrowingStopFakeP2PService({super.initialState});

  @override
  Future<bool> stopNode() async {
    stopNodeCallCount++;
    throw Exception('stop node exploded');
  }
}

void main() {
  group('stopP2PNode', () {
    test('returns notRunning when node is not started', () async {
      final p2pService = FakeP2PService(); // default: NodeState.stopped

      final result = await stopP2PNode(p2pService: p2pService);

      expect(result, StopNodeResult.notRunning);
    });

    test('returns success when stopNode returns true', () async {
      final p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'my-peer'),
        stopNodeResult: true,
      );

      final result = await stopP2PNode(p2pService: p2pService);

      expect(result, StopNodeResult.success);
    });

    test('returns error when stopNode returns false', () async {
      final p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'my-peer'),
        stopNodeResult: false,
      );

      final result = await stopP2PNode(p2pService: p2pService);

      expect(result, StopNodeResult.error);
    });

    test('returns error when stopNode throws', () async {
      final p2pService = _ThrowingStopFakeP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'my-peer'),
      );

      final result = await stopP2PNode(p2pService: p2pService);

      expect(result, StopNodeResult.error);
    });

    test('does not call stopNode when not running', () async {
      final p2pService = FakeP2PService(); // default: NodeState.stopped

      await stopP2PNode(p2pService: p2pService);

      expect(p2pService.stopNodeCallCount, 0);
    });
  });
}
