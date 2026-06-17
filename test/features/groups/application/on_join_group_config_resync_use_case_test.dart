import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/on_join_group_config_resync_use_case.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';

/// T2 (08-D): direct coverage of the `sendOnJoinGroupConfigRequest` transport
/// fallback — the offline `sendMessage:false → storeInInbox` leg and the
/// node-not-running best-effort no-throw — which was previously only exercised
/// end-to-end.
void main() {
  late FakeBridge bridge;

  setUp(() {
    bridge = FakeBridge();
  });

  Future<SendGroupConfigResyncResult> sendRequest(
    FakeP2PService p2p, {
    String? inviterMlKemPublicKey = 'inviterMlKem64',
  }) {
    return sendOnJoinGroupConfigRequest(
      p2pService: p2p,
      bridge: bridge,
      groupId: 'grp-1',
      requesterPeerId: 'me',
      inviterPeerId: 'inviter',
      inviterMlKemPublicKey: inviterMlKemPublicKey,
    );
  }

  group('sendOnJoinGroupConfigRequest transport fallback', () {
    test('T2: direct send succeeds → success, no inbox fallback', () async {
      final p2p = FakeP2PService(
        initialState: const NodeState(isStarted: true),
        sendMessageResult: true,
      );

      final result = await sendRequest(p2p);

      expect(result, SendGroupConfigResyncResult.success);
      expect(p2p.sendMessageCallCount, 1);
      expect(p2p.storeInInboxCallCount, 0);
    });

    test('T2: direct send fails → inbox fallback used → success', () async {
      final p2p = FakeP2PService(
        initialState: const NodeState(isStarted: true),
        sendMessageResult: false,
        storeInInboxResult: true,
      );

      final result = await sendRequest(p2p);

      expect(result, SendGroupConfigResyncResult.success);
      expect(p2p.sendMessageCallCount, 1);
      expect(p2p.storeInInboxCallCount, 1);
      // The same encrypted envelope was handed to both legs.
      expect(p2p.lastStoreInInboxMessage, p2p.lastSendMessageContent);
    });

    test('T2: both send and inbox fail → sendFailed', () async {
      final p2p = FakeP2PService(
        initialState: const NodeState(isStarted: true),
        sendMessageResult: false,
        storeInInboxResult: false,
      );

      final result = await sendRequest(p2p);

      expect(result, SendGroupConfigResyncResult.sendFailed);
      expect(p2p.sendMessageCallCount, 1);
      expect(p2p.storeInInboxCallCount, 1);
    });

    test(
      'T2: node not running → nodeNotRunning, best-effort no-throw, no transport',
      () async {
        final p2p = FakeP2PService(
          initialState: const NodeState(isStarted: false),
          sendMessageResult: true,
        );

        final result = await sendRequest(p2p);

        expect(result, SendGroupConfigResyncResult.nodeNotRunning);
        expect(p2p.sendMessageCallCount, 0);
        expect(p2p.storeInInboxCallCount, 0);
      },
    );

    test(
      'T2: a missing inviter ML-KEM key short-circuits to encryptionRequired '
      'without attempting transport',
      () async {
        final p2p = FakeP2PService(
          initialState: const NodeState(isStarted: true),
        );

        final result = await sendRequest(p2p, inviterMlKemPublicKey: null);

        expect(result, SendGroupConfigResyncResult.encryptionRequired);
        expect(p2p.sendMessageCallCount, 0);
        expect(p2p.storeInInboxCallCount, 0);
      },
    );
  });
}
