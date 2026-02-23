import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/p2p/application/send_message_use_case.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import '../../../core/services/fake_p2p_service.dart';

/// FakeP2PService subclass that throws on sendMessage().
class _ThrowingSendFakeP2PService extends FakeP2PService {
  _ThrowingSendFakeP2PService({super.initialState});

  @override
  Future<bool> sendMessage(String peerId, String message) async {
    sendMessageCallCount++;
    lastSendMessagePeerId = peerId;
    lastSendMessageContent = message;
    throw Exception('send message exploded');
  }
}

void main() {
  const startedState = NodeState(isStarted: true, peerId: 'my-peer');

  group('sendP2PMessage', () {
    test('returns nodeNotRunning when node is stopped', () async {
      final p2pService = FakeP2PService(); // default: NodeState.stopped

      final result = await sendP2PMessage(
        p2pService: p2pService,
        peerId: 'target-peer',
        message: 'Hello',
      );

      expect(result, SendMessageResult.nodeNotRunning);
    });

    test('returns success when sendMessage returns true', () async {
      final p2pService = FakeP2PService(
        initialState: startedState,
        sendMessageResult: true,
      );

      final result = await sendP2PMessage(
        p2pService: p2pService,
        peerId: 'target-peer',
        message: 'Hello',
      );

      expect(result, SendMessageResult.success);
    });

    test('returns error when sendMessage returns false', () async {
      final p2pService = FakeP2PService(
        initialState: startedState,
        sendMessageResult: false,
      );

      final result = await sendP2PMessage(
        p2pService: p2pService,
        peerId: 'target-peer',
        message: 'Hello',
      );

      expect(result, SendMessageResult.error);
    });

    test('returns error when sendMessage throws', () async {
      final p2pService = _ThrowingSendFakeP2PService(
        initialState: startedState,
      );

      final result = await sendP2PMessage(
        p2pService: p2pService,
        peerId: 'target-peer',
        message: 'Hello',
      );

      expect(result, SendMessageResult.error);
    });

    test('passes correct peerId and message to service', () async {
      final p2pService = FakeP2PService(
        initialState: startedState,
        sendMessageResult: true,
      );

      await sendP2PMessage(
        p2pService: p2pService,
        peerId: 'target-peer-xyz',
        message: 'Test message content',
      );

      expect(p2pService.lastSendMessagePeerId, 'target-peer-xyz');
      expect(p2pService.lastSendMessageContent, 'Test message content');
    });

    test('does not call sendMessage when node is stopped', () async {
      final p2pService = FakeP2PService(); // default: NodeState.stopped

      await sendP2PMessage(
        p2pService: p2pService,
        peerId: 'target-peer',
        message: 'Hello',
      );

      expect(p2pService.sendMessageCallCount, 0);
    });
  });
}
