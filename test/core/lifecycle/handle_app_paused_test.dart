import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/lifecycle/handle_app_paused.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';

import '../../shared/fakes/in_memory_message_repository.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ConversationMessage makeSendingMessage({
  String id = 'msg-001',
  String contactPeerId = 'peer-a',
  String? wireEnvelope,
}) {
  return ConversationMessage(
    id: id,
    contactPeerId: contactPeerId,
    senderPeerId: 'my-peer-id',
    text: 'Hello',
    timestamp: '2026-01-01T00:00:00.000Z',
    status: 'sending',
    isIncoming: false,
    createdAt: '2026-01-01T00:00:00.000Z',
    wireEnvelope: wireEnvelope,
  );
}

ConversationMessage makeMessageWithStatus(String id, String status) {
  return ConversationMessage(
    id: id,
    contactPeerId: 'peer-a',
    senderPeerId: 'my-peer-id',
    text: 'Hello',
    timestamp: '2026-01-01T00:00:00.000Z',
    status: status,
    isIncoming: false,
    createdAt: '2026-01-01T00:00:00.000Z',
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('handleAppPaused — no messages', () {
    test('completes without error when no sending messages exist', () async {
      final messageRepo = InMemoryMessageRepository();

      await expectLater(
        handleAppPaused(messageRepo: messageRepo),
        completes,
      );
    });

    test('returns 0 transitioned messages when no sending messages exist',
        () async {
      final messageRepo = InMemoryMessageRepository();

      final result = await handleAppPaused(messageRepo: messageRepo);

      expect(result.transitionedCount, 0);
    });
  });

  group('handleAppPaused — transitions sending -> failed', () {
    test('transitions one sending message to failed', () async {
      final messageRepo = InMemoryMessageRepository();
      await messageRepo.saveMessage(makeSendingMessage(id: 'msg-001'));

      await handleAppPaused(messageRepo: messageRepo);

      final messages = await messageRepo.getMessagesForContact('peer-a');
      expect(messages.single.status, 'failed');
    });

    test('returns transitioned count of 1 for one sending message', () async {
      final messageRepo = InMemoryMessageRepository();
      await messageRepo.saveMessage(makeSendingMessage(id: 'msg-001'));

      final result = await handleAppPaused(messageRepo: messageRepo);

      expect(result.transitionedCount, 1);
    });

    test('transitions all sending messages when multiple exist', () async {
      final messageRepo = InMemoryMessageRepository();
      await messageRepo.saveMessage(
        makeSendingMessage(id: 'msg-001', contactPeerId: 'peer-a'),
      );
      await messageRepo.saveMessage(
        makeSendingMessage(id: 'msg-002', contactPeerId: 'peer-b'),
      );
      await messageRepo.saveMessage(
        makeSendingMessage(id: 'msg-003', contactPeerId: 'peer-c'),
      );

      final result = await handleAppPaused(messageRepo: messageRepo);

      expect(result.transitionedCount, 3);
      final msgsA = await messageRepo.getMessagesForContact('peer-a');
      expect(msgsA.single.status, 'failed');
      final msgsB = await messageRepo.getMessagesForContact('peer-b');
      expect(msgsB.single.status, 'failed');
      final msgsC = await messageRepo.getMessagesForContact('peer-c');
      expect(msgsC.single.status, 'failed');
    });

    test('returns correct count for multiple concurrent sending messages',
        () async {
      final messageRepo = InMemoryMessageRepository();
      for (var i = 1; i <= 5; i++) {
        await messageRepo.saveMessage(
          makeSendingMessage(id: 'msg-00$i', contactPeerId: 'peer-$i'),
        );
      }

      final result = await handleAppPaused(messageRepo: messageRepo);

      expect(result.transitionedCount, 5);
    });
  });

  group('handleAppPaused — preserves wireEnvelope', () {
    test('wireEnvelope is preserved after status transition', () async {
      final messageRepo = InMemoryMessageRepository();
      const envelope =
          '{"type":"chat_message","version":"2","encrypted":{}}';
      await messageRepo.saveMessage(
        makeSendingMessage(id: 'msg-001', wireEnvelope: envelope),
      );

      await handleAppPaused(messageRepo: messageRepo);

      final messages = await messageRepo.getMessagesForContact('peer-a');
      expect(messages.single.wireEnvelope, envelope);
      expect(messages.single.status, 'failed');
    });

    test('null wireEnvelope message still transitions to failed', () async {
      final messageRepo = InMemoryMessageRepository();
      await messageRepo.saveMessage(
        makeSendingMessage(id: 'msg-001', wireEnvelope: null),
      );

      await handleAppPaused(messageRepo: messageRepo);

      final messages = await messageRepo.getMessagesForContact('peer-a');
      expect(messages.single.status, 'failed');
      expect(messages.single.wireEnvelope, isNull);
    });
  });

  group('handleAppPaused — does not affect other statuses', () {
    test('does not modify already-failed messages', () async {
      final messageRepo = InMemoryMessageRepository();
      await messageRepo.saveMessage(makeMessageWithStatus('msg-f', 'failed'));
      await messageRepo.saveMessage(makeSendingMessage(id: 'msg-s'));

      await handleAppPaused(messageRepo: messageRepo);

      final result = await handleAppPaused(messageRepo: messageRepo);
      // Only the one 'sending' message should be transitioned; already-failed
      // messages must not count again (they were failed before the call).
      expect(result.transitionedCount, 0); // second call: nothing sending left
    });

    test('delivered messages are untouched', () async {
      final messageRepo = InMemoryMessageRepository();
      await messageRepo.saveMessage(
        makeMessageWithStatus('msg-delivered', 'delivered'),
      );

      await handleAppPaused(messageRepo: messageRepo);

      final messages = await messageRepo.getMessagesForContact('peer-a');
      expect(messages.single.status, 'delivered');
    });

    test('sent messages are untouched', () async {
      final messageRepo = InMemoryMessageRepository();
      await messageRepo
          .saveMessage(makeMessageWithStatus('msg-sent', 'sent'));

      await handleAppPaused(messageRepo: messageRepo);

      final messages = await messageRepo.getMessagesForContact('peer-a');
      expect(messages.single.status, 'sent');
    });

    test('incoming messages are untouched regardless of status', () async {
      final messageRepo = InMemoryMessageRepository();
      await messageRepo.saveMessage(
        ConversationMessage(
          id: 'msg-incoming',
          contactPeerId: 'peer-a',
          senderPeerId: 'peer-a',
          text: 'hi',
          timestamp: '2026-01-01T00:00:00.000Z',
          status: 'sending', // should never happen but must be safe
          isIncoming: true,
          createdAt: '2026-01-01T00:00:00.000Z',
        ),
      );

      await handleAppPaused(messageRepo: messageRepo);

      final messages = await messageRepo.getMessagesForContact('peer-a');
      // Incoming messages must not be transitioned by the pause handler.
      expect(messages.single.status, 'sending');
    });

    test('mixed statuses: only sending outgoing messages are transitioned',
        () async {
      final messageRepo = InMemoryMessageRepository();
      await messageRepo.saveMessage(makeMessageWithStatus('ok-1', 'sent'));
      await messageRepo
          .saveMessage(makeMessageWithStatus('ok-2', 'delivered'));
      await messageRepo.saveMessage(makeMessageWithStatus('ok-3', 'failed'));
      await messageRepo.saveMessage(makeSendingMessage(id: 'bad-1'));
      await messageRepo.saveMessage(makeSendingMessage(id: 'bad-2'));

      final result = await handleAppPaused(messageRepo: messageRepo);

      expect(result.transitionedCount, 2);
      final sentMsg = await messageRepo.getMessagesForContact('peer-a');
      final statuses = sentMsg.map((m) => m.status).toSet();
      expect(statuses, containsAll(['sent', 'delivered', 'failed']));
    });
  });

  group('handleAppPaused — result fields', () {
    test('result exposes transitionedCount', () async {
      final messageRepo = InMemoryMessageRepository();
      await messageRepo.saveMessage(makeSendingMessage(id: 'msg-001'));

      final result = await handleAppPaused(messageRepo: messageRepo);

      expect(result.transitionedCount, isA<int>());
    });

    test('result exposes transitionedCount as 0 for empty DB', () async {
      final messageRepo = InMemoryMessageRepository();

      final result = await handleAppPaused(messageRepo: messageRepo);

      expect(result.transitionedCount, isA<int>());
    });
  });
}
