import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/lifecycle/handle_app_paused.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';

import '../../shared/fakes/in_memory_message_repository.dart';

// Repo that throws on getSendingOutgoingMessages
class _ThrowingMessageRepository extends InMemoryMessageRepository {
  @override
  Future<List<ConversationMessage>> getSendingOutgoingMessages() {
    throw Exception('DB unavailable during pause');
  }
}

// Repo that throws on conditionalTransitionStatus
class _ThrowOnUpdateRepository extends InMemoryMessageRepository {
  int updateCallCount = 0;

  @override
  Future<int> conditionalTransitionStatus(
    String id, {
    required String fromStatus,
    required String toStatus,
  }) async {
    updateCallCount++;
    throw Exception('conditionalTransitionStatus failed');
  }
}

void main() {
  group('handleAppPaused — error resilience', () {
    test(
      'returns safe default when getSendingOutgoingMessages throws',
      () async {
        final result = await handleAppPaused(
          messageRepo: _ThrowingMessageRepository(),
        );

        // Must not throw; returns zeroed result
        expect(result.transitionedCount, 0);
      },
    );

    test(
      'continues processing remaining messages when one conditionalTransitionStatus throws',
      () async {
        final repo = _ThrowOnUpdateRepository();
        await repo.saveMessage(
          ConversationMessage(
            id: 'msg-001',
            contactPeerId: 'peer-a',
            senderPeerId: 'me',
            text: 'hi',
            timestamp: '2026-01-01T00:00:00.000Z',
            status: 'sending',
            isIncoming: false,
            createdAt: '2026-01-01T00:00:00.000Z',
          ),
        );
        await repo.saveMessage(
          ConversationMessage(
            id: 'msg-002',
            contactPeerId: 'peer-b',
            senderPeerId: 'me',
            text: 'hello',
            timestamp: '2026-01-01T01:00:00.000Z',
            status: 'sending',
            isIncoming: false,
            createdAt: '2026-01-01T00:00:00.000Z',
          ),
        );

        // Should not throw even though every conditionalTransitionStatus call fails
        await expectLater(
          handleAppPaused(messageRepo: repo),
          completes,
        );

        // Both messages attempted: updateCallCount >= 2 means we tried both
        // rather than aborting on first failure
        expect(repo.updateCallCount, greaterThanOrEqualTo(2));
      },
    );

    test(
      'does not call conditionalTransitionStatus when no sending messages exist',
      () async {
        final repo = _ThrowOnUpdateRepository();
        // Repo starts empty -- no sending messages

        // Should complete without hitting the throwing method
        await expectLater(
          handleAppPaused(messageRepo: repo),
          completes,
        );

        expect(repo.updateCallCount, 0);
      },
    );
  });

  group('handleAppPaused — timing', () {
    test(
      'completes within reasonable time for local DB only handler',
      () async {
        final messageRepo = InMemoryMessageRepository();
        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'msg-hang',
            contactPeerId: 'peer-a',
            senderPeerId: 'me',
            text: 'hi',
            timestamp: '2026-01-01T00:00:00.000Z',
            status: 'sending',
            isIncoming: false,
            createdAt: '2026-01-01T00:00:00.000Z',
            wireEnvelope: '{"version":"2"}',
          ),
        );

        final start = DateTime.now();

        final result = await handleAppPaused(
          messageRepo: messageRepo,
        );

        final elapsed = DateTime.now().difference(start);
        expect(elapsed.inMilliseconds, lessThan(5000),
            reason: 'Pause handler must not block indefinitely');
        // Message still transitioned to failed (DB write always happens first)
        expect(result.transitionedCount, 1);
      },
    );
  });
}
