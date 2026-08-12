import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/lifecycle/handle_app_paused.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

import '../../features/conversation/domain/repositories/fake_media_attachment_repository.dart';
import '../../shared/fakes/in_memory_message_repository.dart';
import '../bridge/fake_bridge.dart';
import '../services/fake_p2p_service.dart';

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

      await expectLater(handleAppPaused(messageRepo: messageRepo), completes);
    });

    test(
      'returns 0 transitioned messages when no sending messages exist',
      () async {
        final messageRepo = InMemoryMessageRepository();

        final result = await handleAppPaused(messageRepo: messageRepo);

        expect(result.transitionedCount, 0);
      },
    );
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

    test(
      'returns correct count for multiple concurrent sending messages',
      () async {
        final messageRepo = InMemoryMessageRepository();
        for (var i = 1; i <= 5; i++) {
          await messageRepo.saveMessage(
            makeSendingMessage(id: 'msg-00$i', contactPeerId: 'peer-$i'),
          );
        }

        final result = await handleAppPaused(messageRepo: messageRepo);

        expect(result.transitionedCount, 5);
      },
    );
  });

  group('handleAppPaused — preserves wireEnvelope', () {
    test('wireEnvelope is preserved after status transition', () async {
      final messageRepo = InMemoryMessageRepository();
      const envelope = '{"type":"chat_message","version":"2","encrypted":{}}';
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
      await messageRepo.saveMessage(makeMessageWithStatus('msg-sent', 'sent'));

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

    test(
      'mixed statuses: only sending outgoing messages are transitioned',
      () async {
        final messageRepo = InMemoryMessageRepository();
        await messageRepo.saveMessage(makeMessageWithStatus('ok-1', 'sent'));
        await messageRepo.saveMessage(
          makeMessageWithStatus('ok-2', 'delivered'),
        );
        await messageRepo.saveMessage(makeMessageWithStatus('ok-3', 'failed'));
        await messageRepo.saveMessage(makeSendingMessage(id: 'bad-1'));
        await messageRepo.saveMessage(makeSendingMessage(id: 'bad-2'));

        final result = await handleAppPaused(messageRepo: messageRepo);

        expect(result.transitionedCount, 2);
        final sentMsg = await messageRepo.getMessagesForContact('peer-a');
        final statuses = sentMsg.map((m) => m.status).toSet();
        expect(statuses, containsAll(['sent', 'delivered', 'failed']));
      },
    );
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

  group('TC-361-03b restricted linked pause', () {
    test(
      'TC-361-03b linked runtime starts only direct blob-free event owners — '
      'the linked pause call shape runs the local-only sweep with the '
      'FDC-06 flush parked and zero network side effects',
      () async {
        final messageRepo = InMemoryMessageRepository();
        await messageRepo.saveMessage(makeSendingMessage(id: 'linked-p-1'));
        final p2pService = FakeP2PService();
        addTearDown(p2pService.dispose);
        final bridge = FakeBridge();

        // The exact argument shape the application root uses for the
        // restricted linked role (_onPaused linked branch).
        final result = await handleAppPaused(
          messageRepo: messageRepo,
          p2pService: p2pService,
          bridge: bridge,
          enablePauseFlush: false,
        );

        expect(result.transitionedCount, 1);
        expect(
          result.flushDepositedCount,
          0,
          reason: 'the pause flush must stay parked for the linked role',
        );
        final messages = await messageRepo.getMessagesForContact('peer-a');
        expect(messages.single.status, 'failed');
        expect(
          p2pService.storeInInboxCallCount,
          0,
          reason: 'no durable-inbox deposit may run on the linked pause',
        );
        expect(p2pService.sendMessageCallCount, 0);
        expect(
          bridge.sendCallCount,
          0,
          reason: 'the linked pause is local-DB-only',
        );
      },
    );

    test(
      'TC-362-04a linked pause keeps every generic media pause owner zero',
      () async {
        final messageRepo = InMemoryMessageRepository();
        await messageRepo.saveMessage(makeSendingMessage(id: 'linked-p-362'));
        final p2pService = FakeP2PService();
        addTearDown(p2pService.dispose);
        final bridge = FakeBridge();
        // A generic (full) pause would consult the media repository for the
        // pending-upload sweep; the restricted linked call shape omits the
        // media/group repositories entirely, so every generic media pause
        // owner must stay at zero while the local sweep still runs.
        final mediaRepo = FakeMediaAttachmentRepository()
          ..seed(<MediaAttachment>[
            MediaAttachment(
              id: 'linked-p-362-att',
              messageId: 'linked-p-362',
              mime: 'image/jpeg',
              size: 2048,
              mediaType: 'image',
              localPath: 'pending_uploads/linked-p-362/linked-p-362-att.jpg',
              downloadStatus: 'upload_pending',
              createdAt: '2026-08-12T09:00:00.000Z',
              ownerLane: MediaOwnerLane.direct,
            ),
          ]);

        // The exact argument shape the application root uses for the
        // restricted linked role (_onPaused linked branch): no
        // mediaAttachmentRepo, no groupMsgRepo, flush parked.
        final result = await handleAppPaused(
          messageRepo: messageRepo,
          p2pService: p2pService,
          bridge: bridge,
          enablePauseFlush: false,
        );

        expect(result.transitionedCount, 1);
        expect(
          result.groupTransitionedCount,
          0,
          reason: 'the group pause owner has no seat in the linked call shape',
        );
        expect(result.flushDepositedCount, 0);
        expect(
          (await messageRepo.getMessagesForContact('peer-a')).single.status,
          'failed',
          reason: 'the local-only sweep itself still runs',
        );
        expect(
          mediaRepo.getAttachmentsForMessageCallCount,
          0,
          reason: 'no media pause owner may consult attachments',
        );
        final untouched = await mediaRepo.getAttachmentsForMessage(
          'linked-p-362',
          owner: MediaOwnerLane.direct,
        );
        expect(
          untouched.single.downloadStatus,
          'upload_pending',
          reason:
              'the pending upload is byte-untouched — the generic '
              'pending-upload sweep never ran on the linked pause',
        );
        expect(p2pService.storeInInboxCallCount, 0);
        expect(p2pService.sendMessageCallCount, 0);
        expect(bridge.sendCallCount, 0);
      },
    );
  });
}
