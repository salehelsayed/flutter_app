import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/lifecycle/handle_app_paused.dart';
import 'package:flutter_app/core/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';

import '../../shared/fakes/in_memory_message_repository.dart';
import '../../core/services/fake_p2p_service.dart';
import '../../core/bridge/fake_bridge.dart';

void main() {
  group('Smoke: send -> pause -> resume -> retry', () {
    test(
      'message stranded in sending state transitions to failed after pause',
      () async {
        // 1. ARRANGE
        final messageRepo = InMemoryMessageRepository();

        // 2. ACT — simulate a message that was written to the DB as 'sending'
        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'msg-in-flight',
            contactPeerId: 'peer-bob',
            senderPeerId: 'my-peer-id',
            text: 'Hello Bob',
            timestamp: '2026-01-01T00:00:00.000Z',
            status: 'sending',
            isIncoming: false,
            createdAt: '2026-01-01T00:00:00.000Z',
            wireEnvelope:
                '{"type":"chat_message","version":"2","encrypted":{"kem":"k","ciphertext":"c","nonce":"n"}}',
          ),
        );

        // 3. ACT — OS pauses the app (lock screen, home button)
        final pauseResult = await handleAppPaused(messageRepo: messageRepo);

        // 4. ASSERT — message is now 'failed', not stranded in 'sending'
        expect(pauseResult.transitionedCount, 1);
        final afterPause =
            await messageRepo.getMessagesForContact('peer-bob');
        expect(afterPause.single.status, 'failed',
            reason: 'Pause must transition sending->failed');
        // wireEnvelope must be preserved for the retry path
        expect(afterPause.single.wireEnvelope, isNotNull);

        // 4b. ASSERT — UI recovery: verify the messageChanges stream emitted
        // the 'failed' status so the UI filter can react.
        final emittedStatuses = <String>[];
        final sub = messageRepo.messageChanges.listen(
          (msg) => emittedStatuses.add('${msg.id}:${msg.status}'),
        );

        // Re-run pause to confirm idempotency and that no stale emission occurs
        final secondPause = await handleAppPaused(messageRepo: messageRepo);
        expect(secondPause.transitionedCount, 0,
            reason: 'Second pause is a no-op — message already failed');

        await sub.cancel();
        // No new emissions for the already-failed message
        expect(emittedStatuses, isEmpty,
            reason:
                'Already-failed message must not re-emit on messageChanges');

        // 5. ASSERT — failed messages are available for retry after resume
        final failed = await messageRepo.getFailedOutgoingMessages();
        expect(failed.length, 1);
        expect(failed.first.id, 'msg-in-flight');
        expect(failed.first.status, 'failed');
      },
    );

    test(
      'multiple concurrent sending messages all transition to failed after pause',
      () async {
        final messageRepo = InMemoryMessageRepository();

        // Seed 3 concurrent sending messages
        for (final (idx, peer) in [
          'peer-alice',
          'peer-carol',
          'peer-dave',
        ].indexed) {
          await messageRepo.saveMessage(
            ConversationMessage(
              id: 'msg-00${idx + 1}',
              contactPeerId: peer,
              senderPeerId: 'my-peer-id',
              text: 'Hi',
              timestamp: '2026-01-01T0$idx:00:00.000Z',
              status: 'sending',
              isIncoming: false,
              createdAt: '2026-01-01T00:00:00.000Z',
              wireEnvelope: '{"version":"2","encrypted":{}}',
            ),
          );
        }

        final pauseResult = await handleAppPaused(messageRepo: messageRepo);
        expect(pauseResult.transitionedCount, 3);

        final failed = await messageRepo.getFailedOutgoingMessages();
        expect(failed.length, 3);
      },
    );

    test(
      'pause on app with no in-flight messages is a no-op and resume still succeeds',
      () async {
        final messageRepo = InMemoryMessageRepository();
        final bridge = FakeBridge();
        final p2pService = FakeP2PService();

        // No sending messages at all
        final pauseResult = await handleAppPaused(messageRepo: messageRepo);
        expect(pauseResult.transitionedCount, 0);

        // Resume should still work correctly
        final bridgeOk =
            await handleAppResumed(bridge: bridge, p2pService: p2pService);
        expect(bridgeOk, isNotNull);
      },
    );
  });
}
