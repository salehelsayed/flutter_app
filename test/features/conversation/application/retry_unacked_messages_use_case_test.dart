import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show Database;
import 'package:flutter_app/core/database/helpers/direct_reaction_inbox_custody_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/features/conversation/application/retry_unacked_messages_use_case.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_inbox_custody_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_reaction_inbox_custody_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/outgoing_ordinary_mutation_result.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fixtures/media_repository_real_db_fixture.dart';
import '../domain/repositories/fake_message_repository.dart';

ConversationMessage _makeSentMessage({
  String id = 'msg-sent-001',
  String contactPeerId = 'peer-target',
  String wireEnvelope = '{"type":"chat_message","version":"2","encrypted":{}}',
}) {
  return ConversationMessage(
    id: id,
    contactPeerId: contactPeerId,
    senderPeerId: 'my-peer-id',
    text: 'Hello',
    timestamp: '2026-01-01T00:00:00.000Z',
    status: 'sent',
    isIncoming: false,
    createdAt: '2026-01-01T00:00:00.000Z',
    wireEnvelope: wireEnvelope,
  );
}

ConversationMessage _makeSentDeletedMessage({
  String id = 'msg-delete-sent-001',
  String contactPeerId = 'peer-target',
  String wireEnvelope =
      '{"type":"message_deletion","version":"2","encrypted":{}}',
}) {
  return ConversationMessage(
    id: id,
    contactPeerId: contactPeerId,
    senderPeerId: 'my-peer-id',
    text: '',
    timestamp: '2026-01-01T00:00:00.000Z',
    status: 'sent',
    isIncoming: false,
    createdAt: '2026-01-01T00:00:00.000Z',
    deletedAt: '2026-01-01T00:01:00.000Z',
    deletedByPeerId: 'my-peer-id',
    wireEnvelope: wireEnvelope,
  );
}

class _TokenAfterUnackedListMessageRepository extends FakeMessageRepository {
  _TokenAfterUnackedListMessageRepository(this.intentId);

  final String intentId;
  bool crossedAfterListLoad = false;

  @override
  Future<List<ConversationMessage>> getUnackedOutgoingMessages({
    required Duration olderThan,
  }) async {
    final loaded = await super.getUnackedOutgoingMessages(olderThan: olderThan);
    if (!crossedAfterListLoad && loaded.isNotEmpty) {
      crossedAfterListLoad = true;
      final current = await getMessage(loaded.single.id);
      await saveMessage(
        current!.copyWith(directMediaCustodyIntentId: intentId),
      );
    }
    return loaded;
  }
}

/// 362: stamps the durable fanout no-remint marker onto the row AFTER the
/// unacked batch was loaded, modeling a linked-media generation acquired
/// between list load and egress.
class _MarkerAfterUnackedListMessageRepository extends FakeMessageRepository {
  bool crossedAfterListLoad = false;

  @override
  Future<List<ConversationMessage>> getUnackedOutgoingMessages({
    required Duration olderThan,
  }) async {
    final loaded = await super.getUnackedOutgoingMessages(olderThan: olderThan);
    if (!crossedAfterListLoad && loaded.isNotEmpty) {
      crossedAfterListLoad = true;
      final current = await getMessage(loaded.single.id);
      await saveMessage(
        current!.copyWith(directEventFanoutGenerationId: current.id),
      );
    }
    return loaded;
  }
}

void main() {
  group('retryUnackedMessages', () {
    late FakeMessageRepository messageRepo;

    setUp(() {
      messageRepo = FakeMessageRepository();
    });

    test('returns 0 when no unacked messages exist', () async {
      final p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
      );

      final count = await retryUnackedMessages(
        messageRepo: messageRepo,
        p2pService: p2pService,
      );

      expect(count, 0);
    });

    test(
      'TC-361-01b an unacked wrapper without the plural capability refuses a '
      'fanout-marked generation before any legacy network',
      () async {
        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
        );
        final marked = _makeSentMessage(
          id: 'msg-fanout-marked',
        ).copyWith(directEventFanoutGenerationId: 'msg-fanout-marked');
        await messageRepo.saveMessage(marked);

        final count = await retryUnackedMessages(
          messageRepo: messageRepo,
          p2pService: p2pService,
        );

        expect(count, 0);
        expect(
          p2pService.storeInInboxCallCount,
          0,
          reason:
              'a marked generation must never reach the legacy single-'
              'target inbox store',
        );
        final untouched = await messageRepo.getMessage('msg-fanout-marked');
        expect(untouched!.status, 'sent');
        expect(untouched.wireEnvelope, isNotNull);
      },
    );

    test(
      'TC-362-02b unacked resend refuses a marker-bearing media parent',
      () async {
        const attachment = MediaAttachment(
          id: 'att-362-unacked',
          messageId: 'msg-362-media-marked',
          mime: 'image/jpeg',
          size: 2048,
          mediaType: 'image',
          localPath: 'media/peer/att-362-unacked.jpg',
          downloadStatus: 'done',
          createdAt: '2026-01-01T00:00:00.000Z',
        );

        // Leg 1: the LOADED batch row already carries the linked-media
        // fanout marker (v110 token consumed, v108 siblings absent): the
        // singular unacked resend must refuse it before any legacy network.
        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          storeInInboxResult: true,
        );
        final loadedMarked = _makeSentMessage(id: 'msg-362-media-marked')
            .copyWith(
              media: const <MediaAttachment>[attachment],
              directEventFanoutGenerationId: 'msg-362-media-marked',
            );
        messageRepo.seed(<ConversationMessage>[loadedMarked]);

        final count = await retryUnackedMessages(
          messageRepo: messageRepo,
          p2pService: p2pService,
        );
        expect(count, 0);
        expect(
          p2pService.storeInInboxCallCount,
          0,
          reason:
              'a marker-bearing media parent is owned by its exact v108 '
              'siblings (or terminal) — never this singular resend',
        );
        expect(
          messageRepo.saveMessageCallCount,
          0,
          reason: 'no writer touches the marked row',
        );
        final untouched = await messageRepo.getMessage('msg-362-media-marked');
        expect(untouched!.status, 'sent');
        expect(untouched.wireEnvelope, isNotNull);
        expect(untouched.directEventFanoutGenerationId, 'msg-362-media-marked');

        // Leg 2: the marker lands BETWEEN list load and egress. The freshly
        // reloaded parent carries it, so the exact-candidate recheck must
        // refuse the resend even though the loaded snapshot was unmarked.
        final crossingRepo = _MarkerAfterUnackedListMessageRepository();
        final crossedService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          storeInInboxResult: true,
        );
        final unmarked = _makeSentMessage(
          id: 'msg-362-marker-crossed',
        ).copyWith(media: const <MediaAttachment>[attachment]);
        crossingRepo.seed(<ConversationMessage>[unmarked]);

        final crossedCount = await retryUnackedMessages(
          messageRepo: crossingRepo,
          p2pService: crossedService,
        );
        expect(
          crossingRepo.crossedAfterListLoad,
          isTrue,
          reason: 'the marker was stamped after the batch load',
        );
        expect(crossedCount, 0);
        expect(
          crossedService.storeInInboxCallCount,
          0,
          reason:
              'a marker acquired between list load and egress must '
              'equally never enter this singular resend',
        );
        final crossed = await crossingRepo.getMessage('msg-362-marker-crossed');
        expect(crossed!.status, 'sent');
        expect(crossed.wireEnvelope, isNotNull);
        expect(crossed.directEventFanoutGenerationId, 'msg-362-marker-crossed');
      },
    );

    test('TC-186-01 threads olderThan to getUnackedOutgoingMessages '
        '(default 60s; reconnect passes Duration.zero)', () async {
      final p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
      );

      // Default preserves the 60s anti-race window (all existing callers).
      await retryUnackedMessages(
        messageRepo: messageRepo,
        p2pService: p2pService,
      );
      expect(messageRepo.lastUnackedOlderThan, const Duration(seconds: 60));

      // 186: the reconnect pass drops the gate so a freshly-queued offline
      // message is not skipped.
      await retryUnackedMessages(
        messageRepo: messageRepo,
        p2pService: p2pService,
        olderThan: Duration.zero,
      );
      expect(messageRepo.lastUnackedOlderThan, Duration.zero);
    });

    test('marks inboxed via inbox and sets transport to inbox', () async {
      final msg = _makeSentMessage();
      messageRepo.seed([msg]);
      messageRepo.unackedOutgoingOverride = [msg];

      final p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
        storeInInboxResult: true,
      );

      final count = await retryUnackedMessages(
        messageRepo: messageRepo,
        p2pService: p2pService,
      );

      expect(count, 1);
      expect(p2pService.storeInInboxCallCount, 1);

      // Verify saved message has transport='inbox' and status='inboxed'
      final saved = messageRepo.lastSavedMessage;
      expect(saved, isNotNull);
      expect(saved!.status, 'inboxed');
      expect(saved.transport, 'inbox');
    });

    test('retains wireEnvelope after successful inbox store', () async {
      final msg = _makeSentMessage();
      messageRepo.seed([msg]);
      messageRepo.unackedOutgoingOverride = [msg];

      final p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
        storeInInboxResult: true,
      );

      await retryUnackedMessages(
        messageRepo: messageRepo,
        p2pService: p2pService,
      );

      expect(messageRepo.lastSavedMessage!.wireEnvelope, msg.wireEnvelope);
    });

    test(
      'manual recovery settlement removes the row from later unacked replay',
      () async {
        final settled = _makeSentMessage(
          id: 'msg-manual-recovered-001',
        ).copyWith(status: 'delivered', transport: 'inbox', wireEnvelope: null);
        messageRepo.seed([settled]);

        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          storeInInboxResult: true,
        );

        final count = await retryUnackedMessages(
          messageRepo: messageRepo,
          p2pService: p2pService,
        );

        expect(count, 0);
        expect(p2pService.storeInInboxCallCount, 0);
        expect(messageRepo.saveMessageCallCount, 0);
        expect(
          (await messageRepo.getMessage('msg-manual-recovered-001'))?.status,
          'delivered',
        );
      },
    );

    test(
      'keeps inboxed outgoing delete tombstones visible after inbox retry succeeds',
      () async {
        final msg = _makeSentDeletedMessage();
        messageRepo.seed([msg]);
        messageRepo.unackedOutgoingOverride = [msg];

        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          storeInInboxResult: true,
        );

        final count = await retryUnackedMessages(
          messageRepo: messageRepo,
          p2pService: p2pService,
        );

        expect(count, 1);
        final saved = messageRepo.lastSavedMessage;
        expect(saved, isNotNull);
        expect(saved!.status, 'inboxed');
        expect(saved.isDeleted, isTrue);
        expect(saved.isHidden, isFalse);
        expect(saved.hiddenAt, isNull);
      },
    );

    test(
      'unsafe legacy ordinary envelope is quarantined by exact identity without replay',
      () async {
        final exactChat =
            _makeSentMessage(
              id: 'legacy-chat-exact',
              wireEnvelope:
                  '{"type":"chat_message","version":"1","payload":{"text":"legacy chat"}}',
            ).copyWith(
              text: 'edited legacy chat',
              editedAt: '2026-01-01T00:02:00.000Z',
              transport: 'inbox',
              relayExpiresAt: 3360701,
              custodyCheckedAt: '2026-01-01T00:03:00.000Z',
            );
        final exactTombstone =
            _makeSentDeletedMessage(
              id: 'legacy-delete-exact',
              wireEnvelope:
                  '{"type":"message_deletion","version":"1","payload":{"messageId":"legacy-delete-exact"}}',
            ).copyWith(
              transport: 'inbox',
              relayExpiresAt: 3360702,
              custodyCheckedAt: '2026-01-01T00:04:00.000Z',
            );
        final staleCrossedSnapshot =
            _makeSentMessage(
              id: 'legacy-chat-crossed',
              wireEnvelope:
                  '{"type":"chat_message","version":"1","payload":{"text":"stale"}}',
            ).copyWith(
              text: 'stale snapshot',
              editedAt: '2026-01-01T00:05:00.000Z',
              transport: 'inbox',
              relayExpiresAt: 3360703,
              custodyCheckedAt: '2026-01-01T00:06:00.000Z',
            );
        final crossedWinner = staleCrossedSnapshot.copyWith(
          text: 'concurrent winner',
          editedAt: '2026-01-01T00:07:00.000Z',
          wireEnvelope:
              '{"type":"chat_message","version":"1","payload":{"text":"winner"}}',
          transport: 'direct',
          relayExpiresAt: 3360799,
          custodyCheckedAt: '2026-01-01T00:08:00.000Z',
        );
        messageRepo.seed([exactChat, exactTombstone, crossedWinner]);
        messageRepo.unackedOutgoingOverride = [
          exactChat,
          exactTombstone,
          staleCrossedSnapshot,
        ];
        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          storeInInboxResult: true,
        );

        final count = await retryUnackedMessages(
          messageRepo: messageRepo,
          p2pService: p2pService,
        );

        expect(count, 0);
        expect(
          (await messageRepo.getMessage(exactChat.id))!.toMap(),
          exactChat
              .copyWith(
                status: 'failed',
                transport: null,
                relayExpiresAt: null,
                custodyCheckedAt: null,
              )
              .toMap(),
        );
        expect(
          (await messageRepo.getMessage(exactTombstone.id))!.toMap(),
          exactTombstone
              .copyWith(
                status: 'failed',
                transport: null,
                relayExpiresAt: null,
                custodyCheckedAt: null,
              )
              .toMap(),
        );
        expect(
          (await messageRepo.getMessage(crossedWinner.id))!.toMap(),
          crossedWinner.toMap(),
        );
        expect(
          messageRepo.ordinaryMutationCallCount,
          2,
          reason:
              'the crossed winner is rejected by the fresh exact pre-egress recheck before quarantine',
        );
        expect(messageRepo.saveMessageCallCount, 0);
        expect(p2pService.storeInInboxCallCount, 0);
        expect(p2pService.sendMessageCallCount, 0);
        expect(p2pService.sendMessageWithReplyCallCount, 0);
        expect(p2pService.discoverPeerCallCount, 0);
        expect(p2pService.dialPeerCallCount, 0);
        expect(p2pService.sendLocalMediaCallCount, 0);
      },
    );

    test(
      'does not replay persisted v1 chat wireEnvelope when coming online',
      () async {
        final msg = _makeSentMessage(
          wireEnvelope:
              '{"type":"chat_message","version":"1","payload":{"text":"Legacy leak sentinel"}}',
        );
        messageRepo.seed([msg]);
        messageRepo.unackedOutgoingOverride = [msg];

        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          storeInInboxResult: true,
        );

        final count = await retryUnackedMessages(
          messageRepo: messageRepo,
          p2pService: p2pService,
        );

        expect(count, 0);
        expect(p2pService.storeInInboxCallCount, 0);
        final saved = messageRepo.lastSavedMessage;
        expect(saved, isNotNull);
        expect(saved!.status, 'failed');
        expect(saved.wireEnvelope, msg.wireEnvelope);
      },
    );

    // 116 P1 companion PIN (green-on-arrival): the legacy demotion at
    // retry_unacked_messages_use_case.dart (copyWith(status:'failed')) must
    // preserve editedAt so the fallback's row-derived reconstruction has the
    // metadata it needs — this is the deterministic v1-demotion feeder into
    // the edit-retry pipeline.
    test('legacy demotion preserves editedAt on the demoted row', () async {
      final msg = _makeSentMessage(
        wireEnvelope:
            '{"type":"chat_message","version":"1","payload":{"text":"legacy edit"}}',
      ).copyWith(editedAt: '2026-01-01T00:05:00.000Z', transport: 'direct');
      messageRepo.seed([msg]);
      messageRepo.unackedOutgoingOverride = [msg];

      final p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
        storeInInboxResult: true,
      );

      await retryUnackedMessages(
        messageRepo: messageRepo,
        p2pService: p2pService,
      );

      final saved = messageRepo.lastSavedMessage;
      expect(saved!.status, 'failed');
      expect(saved.editedAt, '2026-01-01T00:05:00.000Z');
      expect(saved.transport, isNull);
      expect(saved.wireEnvelope, msg.wireEnvelope);
    });

    test(
      'does not replay persisted v1 deletion wireEnvelope when coming online',
      () async {
        final msg = _makeSentDeletedMessage(
          wireEnvelope:
              '{"type":"message_deletion","version":"1","payload":{"messageId":"msg-delete-sent-001"}}',
        );
        messageRepo.seed([msg]);
        messageRepo.unackedOutgoingOverride = [msg];

        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          storeInInboxResult: true,
        );

        final count = await retryUnackedMessages(
          messageRepo: messageRepo,
          p2pService: p2pService,
        );

        expect(count, 0);
        expect(p2pService.storeInInboxCallCount, 0);
        final saved = messageRepo.lastSavedMessage;
        expect(saved, isNotNull);
        expect(saved!.status, 'failed');
        expect(saved.isDeleted, isTrue);
        expect(saved.isHidden, isFalse);
        expect(saved.wireEnvelope, msg.wireEnvelope);
      },
    );

    test('leaves status as sent when storeInInbox fails', () async {
      final msg = _makeSentMessage();
      messageRepo.seed([msg]);
      messageRepo.unackedOutgoingOverride = [msg];

      final p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
        storeInInboxResult: false,
      );

      final count = await retryUnackedMessages(
        messageRepo: messageRepo,
        p2pService: p2pService,
      );

      expect(count, 0);
      // Message should NOT have been re-saved (storeInInbox returned false)
      expect(messageRepo.saveMessageCallCount, 0);
    });

    test('leaves transport unchanged when storeInInbox fails', () async {
      final msg = _makeSentMessage();
      messageRepo.seed([msg]);
      messageRepo.unackedOutgoingOverride = [msg];

      final p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
        storeInInboxResult: false,
      );

      await retryUnackedMessages(
        messageRepo: messageRepo,
        p2pService: p2pService,
      );

      // Original message should still have null transport (no save occurred)
      final messages = await messageRepo.getMessagesForContact('peer-target');
      expect(messages.first.transport, isNull);
      expect(messages.first.status, 'sent');
    });

    test('returns count of successfully updated messages', () async {
      final msg1 = _makeSentMessage(id: 'msg-1', contactPeerId: 'peer-a');
      final msg2 = _makeSentMessage(id: 'msg-2', contactPeerId: 'peer-b');
      messageRepo.seed([msg1, msg2]);
      messageRepo.unackedOutgoingOverride = [msg1, msg2];

      final p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
        storeInInboxResult: true,
      );

      final count = await retryUnackedMessages(
        messageRepo: messageRepo,
        p2pService: p2pService,
      );

      expect(count, 2);
    });

    test('retryUnackedMessages re-stores when message transport '
        'is already inbox', () async {
      // Simulate the post-crash state: message was successfully stored
      // in inbox but app crashed before DB was updated. On resume,
      // a recovery path re-saved the row with transport='inbox'.
      final msgWithInboxTransport = ConversationMessage(
        id: 'msg-crash-002',
        contactPeerId: 'peer-target',
        senderPeerId: 'my-peer-id',
        text: 'Unacked crash test',
        timestamp: '2026-01-01T00:00:00.000Z',
        status: 'sent',
        isIncoming: false,
        createdAt: '2026-01-01T00:00:00.000Z',
        transport: 'inbox', // already in inbox
        wireEnvelope:
            '{"type":"chat_message","version":"2","encrypted":{"kem":"k","ciphertext":"{}","nonce":"n"}}',
      );
      messageRepo.seed([msgWithInboxTransport]);
      messageRepo.unackedOutgoingOverride = [msgWithInboxTransport];

      final p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
        storeInInboxResult: true,
      );

      final count = await retryUnackedMessages(
        messageRepo: messageRepo,
        p2pService: p2pService,
      );

      // transport='inbox' is not custody proof after crash recovery; re-store.
      expect(p2pService.storeInInboxCallCount, 1);
      expect(count, 1);
      final saved = messageRepo.lastSavedMessage;
      expect(saved, isNotNull);
      expect(saved!.status, 'inboxed');
      expect(saved.wireEnvelope, isNotNull);
    });

    // --- NET-REL-05 R1: concurrent-fallback interaction (regression) ---
    //
    // A low-confidence send whose concurrent durable copy took custody settles
    // as inboxed/inbox/non-null-envelope. The unacked retrier filters on
    // status=='sent' AND a non-empty wireEnvelope, so such a row must never be
    // selected — it cannot be re-stored a second time alongside the concurrent
    // fallback.
    test('concurrently-inboxed message (inboxed/inbox/envelope-retained) is NOT '
        're-stored by the unacked retrier', () async {
      final concurrentlyInboxed = ConversationMessage(
        id: 'msg-concurrent-inbox-unacked-001',
        contactPeerId: 'peer-target',
        senderPeerId: 'my-peer-id',
        text: 'Low-confidence send',
        timestamp: '2026-01-01T00:00:00.000Z',
        status: 'inboxed',
        isIncoming: false,
        createdAt: '2026-01-01T00:00:00.000Z',
        transport: 'inbox',
        wireEnvelope: '{"type":"chat_message","version":"2","encrypted":{}}',
      );
      // Seeded WITHOUT an unackedOutgoingOverride so the real fake query
      // (status=='sent' && wireEnvelope non-empty) decides selection — proving
      // the durable copy is naturally excluded, not forced out by the test.
      messageRepo.seed([concurrentlyInboxed]);

      final p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
        storeInInboxResult: true,
      );

      final count = await retryUnackedMessages(
        messageRepo: messageRepo,
        p2pService: p2pService,
      );

      // NEGATIVE CONTROL: not selected, not re-stored, not re-saved.
      expect(count, 0);
      expect(p2pService.storeInInboxCallCount, 0);
      expect(messageRepo.saveMessageCallCount, 0);
      expect(
        (await messageRepo.getMessage(
          'msg-concurrent-inbox-unacked-001',
        ))?.status,
        'inboxed',
      );
    });

    test('continues on storeInInbox error and tries next message', () async {
      final msg1 = _makeSentMessage(id: 'msg-1', contactPeerId: 'peer-a');
      final msg2 = _makeSentMessage(id: 'msg-2', contactPeerId: 'peer-b');
      messageRepo.seed([msg1, msg2]);
      messageRepo.unackedOutgoingOverride = [msg1, msg2];

      // First call throws, second succeeds
      final p2pService = _ThrowingInboxP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
        throwOnIndices: {0},
      );

      final count = await retryUnackedMessages(
        messageRepo: messageRepo,
        p2pService: p2pService,
      );

      // First failed, second succeeded
      expect(count, 1);
    });

    // ─── 115 Phase 3.1 — retry-unacked truthfulness ──────────────────────
    // 'delivered' may never be minted from a bare storeInInbox==true and
    // NEVER from a blind transport=='inbox' flip with no re-store at all —
    // those were the second and third places false-delivered was born.
    test(
      'TC-345-08 globally v108-owned media bypasses generic unacked store after recipient drift without starving legacy rows',
      () async {
        final ownedMedia =
            _makeSentMessage(
              id: 'msg-v108-media-owned',
              contactPeerId: 'peer-media-drifted',
              wireEnvelope:
                  '{"type":"chat_message","version":"2","encrypted":{"ciphertext":"media"}}',
            ).copyWith(
              media: const <MediaAttachment>[
                MediaAttachment(
                  id: 'att-v108-media-owned',
                  messageId: 'msg-v108-media-owned',
                  mime: 'image/jpeg',
                  size: 7,
                  mediaType: 'image',
                  downloadStatus: 'done',
                  createdAt: '2026-08-07T12:00:00.000Z',
                ),
              ],
            );
        final legacySibling = _makeSentMessage(
          id: 'msg-legacy-sibling',
          contactPeerId: 'peer-legacy',
          wireEnvelope:
              '{"type":"chat_message","version":"2","encrypted":{"ciphertext":"legacy"}}',
        );
        messageRepo.seed(<ConversationMessage>[ownedMedia, legacySibling]);
        messageRepo.unackedOutgoingOverride = <ConversationMessage>[
          ownedMedia,
          legacySibling,
        ];
        messageRepo.seedDirectInboxCustody(
          DirectInboxCustodyOutboxEntry(
            recipientPeerId: 'peer-media-owner',
            messageId: ownedMedia.id,
            incarnationId: '0123456789abcdef0123456789abcdef',
            wireEnvelope: ownedMedia.wireEnvelope!,
            retryCount: 0,
            lastAttemptAt: null,
            lastErrorCode: null,
            createdAt: '2026-08-07T12:00:00.000Z',
            updatedAt: '2026-08-07T12:00:00.000Z',
          ),
        );
        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          storeInInboxResult: true,
        );

        final count = await retryUnackedMessages(
          messageRepo: messageRepo,
          p2pService: p2pService,
          olderThan: Duration.zero,
        );

        expect(count, 1);
        expect(p2pService.storeInInboxCallCount, 1);
        expect(p2pService.lastStoreInInboxPeerId, legacySibling.contactPeerId);
        expect(
          (await messageRepo.getMessage(ownedMedia.id))!.toMap(),
          ownedMedia.toMap(),
          reason: 'the shared v108 drain remains the only settlement owner',
        );
        expect(
          (await messageRepo.getMessage(legacySibling.id))?.status,
          'inboxed',
        );
        expect(messageRepo.directCustodyRows, hasLength(1));
        expect(
          messageRepo.directCustodyRows.values.single,
          isA<DirectInboxCustodyOutboxEntry>()
              .having((entry) => entry.messageId, 'messageId', ownedMedia.id)
              .having(
                (entry) => entry.recipientPeerId,
                'stored recipient owner',
                'peer-media-owner',
              ),
        );
      },
    );

    test(
      'TC-345-08b token-bearing unacked preparation has zero generic egress or settlement',
      () async {
        const messageId = 'msg-v110-unacked-preparation';
        const intent = '0123456789abcdef0123456789abcdef';
        final prepared = _makeSentMessage(
          id: messageId,
          contactPeerId: 'peer-token-preparation',
          wireEnvelope:
              '{"type":"chat_message","version":"2","encrypted":{"ciphertext":"stale"}}',
        ).copyWith(directMediaCustodyIntentId: intent);
        messageRepo.seed(<ConversationMessage>[prepared]);
        messageRepo.unackedOutgoingOverride = <ConversationMessage>[prepared];
        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          storeInInboxResult: true,
        );

        final count = await retryUnackedMessages(
          messageRepo: messageRepo,
          p2pService: p2pService,
          olderThan: Duration.zero,
        );

        expect(count, 0);
        expect(p2pService.storeInInboxCallCount, 0);
        expect(p2pService.sendMessageCallCount, 0);
        expect(p2pService.sendMessageWithReplyCallCount, 0);
        expect(messageRepo.ordinaryMutationCallCount, 0);
        expect(messageRepo.saveMessageCallCount, 0);
        expect(
          (await messageRepo.getMessage(messageId))!.toMap(),
          prepared.toMap(),
        );
      },
    );

    test(
      'TC-345-08c token preparation winning after unacked list load has zero egress',
      () async {
        const messageId = 'msg-v110-unacked-crossing';
        const intent = 'fedcba9876543210fedcba9876543210';
        final crossingRepo = _TokenAfterUnackedListMessageRepository(intent);
        final listed = _makeSentMessage(
          id: messageId,
          contactPeerId: 'peer-token-crossing',
          wireEnvelope:
              '{"type":"chat_message","version":"2","encrypted":{"ciphertext":"listed"}}',
        );
        crossingRepo.seed(<ConversationMessage>[listed]);
        crossingRepo.unackedOutgoingOverride = <ConversationMessage>[listed];
        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          storeInInboxResult: true,
        );

        final count = await retryUnackedMessages(
          messageRepo: crossingRepo,
          p2pService: p2pService,
          olderThan: Duration.zero,
        );

        expect(crossingRepo.crossedAfterListLoad, isTrue);
        expect(count, 0);
        expect(p2pService.storeInInboxCallCount, 0);
        expect(p2pService.sendMessageCallCount, 0);
        expect(p2pService.sendMessageWithReplyCallCount, 0);
        expect(crossingRepo.ordinaryMutationCallCount, 0);
        expect(
          (await crossingRepo.getMessage(
            messageId,
          ))?.directMediaCustodyIntentId,
          intent,
        );
      },
    );

    test('TC-356-03b unacked private deletion with lifecycle-only v109 owner '
        'blocks legacy replay', () async {
      // 357: the owner is a REAL physical v109 row, resolved through the same
      // production helpers main.dart wires.
      final fixture = await MediaRepositoryRealDbFixture.create();
      addTearDown(fixture.dispose);
      const recipient = 'peer-target';

      Future<void> seedPhysicalEvent(String eventId, String envelope) async {
        await fixture.db
            .insert('direct_reaction_inbox_custody_outbox', <String, Object?>{
              'recipient_peer_id': recipient,
              'event_id': eventId,
              'wire_envelope': envelope,
              'retry_count': 0,
              'last_attempt_at': null,
              'last_error_code': null,
              'created_at': '2026-01-01T00:00:00.000Z',
              'updated_at': '2026-01-01T00:00:00.000Z',
            });
      }

      Future<List<Map<String, Object?>>> physicalRows(String eventId) =>
          fixture.db.query(
            'direct_reaction_inbox_custody_outbox',
            where: 'event_id = ?',
            whereArgs: <Object?>[eventId],
          );

      // 1. The private deletion is owned at its FIRST lookup.
      const messageId = 'tc356-03b-private-deletion';
      const eventId = '35600000-0000-4000-8000-000000000301';
      const envelope =
          '{"type":"message_deletion","version":"2","eventId":"$eventId",'
          '"senderPeerId":"my-peer-id",'
          '"encrypted":{"kem":"k","ciphertext":"c","nonce":"n"}}';
      final tombstone = _makeSentDeletedMessage(
        id: messageId,
        contactPeerId: recipient,
        wireEnvelope: envelope,
      ).copyWith(privateMediaPolicy: const PrivateMediaPolicy.protected());
      final backing = FakeMessageRepository();
      backing.seed(<ConversationMessage>[tombstone]);
      backing.unackedOutgoingOverride = <ConversationMessage>[tombstone];
      await seedPhysicalEvent(eventId, envelope);
      final messageRepository = _LifecycleOnlyMutationCustodyRepository(
        backing,
        db: fixture.db,
      );

      final p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
        storeInInboxResult: true,
      );

      expect(
        await retryUnackedMessages(
          messageRepo: messageRepository,
          p2pService: p2pService,
          olderThan: Duration.zero,
        ),
        0,
      );
      expect(
        messageRepository.ownedAtLookups,
        <int>[1],
        reason: 'a physical owner wins at the first generic lifecycle lookup',
      );
      expect(
        p2pService.storeInInboxCallCount,
        0,
        reason: 'the exact v109 owner blocks the generic unacked store',
      );
      expect(p2pService.sendMessageWithReplyCallCount, 0);
      expect(backing.saveMessageCallCount, 0);
      expect(
        await physicalRows(eventId),
        hasLength(1),
        reason: 'the exact event is retained for its own drain',
      );
      expect((await backing.getMessage(messageId))!.toMap(), tombstone.toMap());

      // 2. An ownerless event-bearing private deletion fails closed at that
      //    same first lookup: the legacy store is never reacquired for it.
      const orphanId = 'tc356-03b-ownerless';
      const orphanEvent = '35600000-0000-4000-8000-000000000302';
      const orphanEnvelope =
          '{"type":"message_deletion","version":"2",'
          '"eventId":"$orphanEvent","senderPeerId":"my-peer-id",'
          '"encrypted":{"kem":"k","ciphertext":"c","nonce":"n"}}';
      final orphan = _makeSentDeletedMessage(
        id: orphanId,
        contactPeerId: recipient,
        wireEnvelope: orphanEnvelope,
      ).copyWith(privateMediaPolicy: const PrivateMediaPolicy.viewOnce());
      final orphanBacking = FakeMessageRepository();
      orphanBacking.seed(<ConversationMessage>[orphan]);
      orphanBacking.unackedOutgoingOverride = <ConversationMessage>[orphan];
      final orphanRepository = _LifecycleOnlyMutationCustodyRepository(
        orphanBacking,
        db: fixture.db,
      );
      final orphanP2p = FakeP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
        storeInInboxResult: true,
      );

      expect(
        await retryUnackedMessages(
          messageRepo: orphanRepository,
          p2pService: orphanP2p,
          olderThan: Duration.zero,
        ),
        0,
      );
      expect(
        orphanRepository.lifecycleLookups,
        1,
        reason: 'an ownerless current deletion is terminal at its first look',
      );
      expect(orphanRepository.ownedAtLookups, isEmpty);
      expect(orphanP2p.storeInInboxCallCount, 0);
      expect(orphanBacking.saveMessageCallCount, 0);
      expect(await physicalRows(orphanEvent), isEmpty);

      // 3. The applicable LATER owner check: a compatible current EDIT is
      //    ownerless at list load and acquires its exact physical v109 row
      //    before egress. The pre-egress lookup must find it.
      const editId = 'tc356-03b-edit-pre-egress';
      const editEvent = '35600000-0000-4000-8000-000000000303';
      const editEnvelope =
          '{"type":"chat_message","version":"2","id":"$editId",'
          '"eventId":"$editEvent","senderPeerId":"my-peer-id",'
          '"encrypted":{"kem":"k","ciphertext":"c","nonce":"n"}}';
      final edit = _makeSentMessage(
        id: editId,
        contactPeerId: recipient,
        wireEnvelope: editEnvelope,
      ).copyWith(editedAt: '2026-01-01T00:00:01.000Z');
      final editBacking = FakeMessageRepository();
      editBacking.seed(<ConversationMessage>[edit]);
      editBacking.unackedOutgoingOverride = <ConversationMessage>[edit];
      final editRepository = _LifecycleOnlyMutationCustodyRepository(
        editBacking,
        db: fixture.db,
        onLookup: (index) async {
          if (index == 2) {
            await seedPhysicalEvent(editEvent, editEnvelope);
          }
        },
      );
      final editP2p = FakeP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
        storeInInboxResult: true,
      );

      expect(
        await retryUnackedMessages(
          messageRepo: editRepository,
          p2pService: editP2p,
          olderThan: Duration.zero,
        ),
        0,
      );
      expect(
        editRepository.lifecycleLookups,
        2,
        reason: 'the list-load lookup and then the pre-egress owner barrier',
      );
      expect(
        editRepository.ownedAtLookups,
        <int>[2],
        reason: 'only the pre-egress lookup could see the physical owner',
      );
      expect(
        editP2p.storeInInboxCallCount,
        0,
        reason: 'the pre-egress owner check blocks the legacy relay store',
      );
      expect(editBacking.saveMessageCallCount, 0);
      expect(await physicalRows(editEvent), hasLength(1));
    });

    test(
      'TC-353-03 unacked media caption edit with a v109 owner never re-stores',
      () async {
        const messageId = 'tc353-unacked-media-edit';
        const eventId = '35300000-0000-4000-8000-000000000301';
        const recipient = 'peer-target';
        final envelope =
            '{"type":"chat_message","version":"2","id":"$messageId",'
            '"eventId":"$eventId","senderPeerId":"my-peer-id",'
            '"encrypted":{"kem":"k","ciphertext":"c","nonce":"n"}}';
        final parent =
            _makeSentMessage(
              id: messageId,
              contactPeerId: recipient,
              wireEnvelope: envelope,
            ).copyWith(
              editedAt: '2026-01-01T00:00:01.000Z',
              media: const <MediaAttachment>[
                MediaAttachment(
                  id: '$messageId-a',
                  messageId: messageId,
                  mime: 'image/jpeg',
                  size: 800,
                  mediaType: 'image',
                  downloadStatus: 'done',
                  createdAt: '2026-01-01T00:00:00.000Z',
                ),
              ],
            );
        messageRepo.seed(<ConversationMessage>[parent]);
        messageRepo.unackedOutgoingOverride = <ConversationMessage>[parent];
        messageRepo.directMutationCustodyRows['$recipient\u0000$eventId'] =
            DirectReactionInboxCustodyOutboxEntry(
              recipientPeerId: recipient,
              eventId: eventId,
              wireEnvelope: envelope,
              retryCount: 0,
              lastAttemptAt: null,
              lastErrorCode: null,
              createdAt: '2026-01-01T00:00:00.000Z',
              updatedAt: '2026-01-01T00:00:00.000Z',
            );

        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          storeInInboxResult: true,
        );

        final count = await retryUnackedMessages(
          messageRepo: messageRepo,
          p2pService: p2pService,
          olderThan: Duration.zero,
        );

        expect(count, 0);
        expect(
          p2pService.storeInInboxCallCount,
          0,
          reason: 'the exact v109 owner blocks every legacy store leg',
        );
        expect(p2pService.sendMessageCallCount, 0);
        expect(p2pService.sendMessageWithReplyCallCount, 0);
        expect(
          messageRepo.directMutationCustodyRows,
          hasLength(1),
          reason: 'the exact event stays retained for its own drain',
        );
      },
    );

    group('115 P3 — retry-unacked truthfulness', () {
      test(
        "'sent' row with transport=='inbox' is re-stored to the relay, not blind-flipped to 'delivered'",
        () async {
          final msg = _makeSentMessage(
            id: 'msg-crash-recovered-001',
          ).copyWith(transport: 'inbox');
          messageRepo.seed([msg]);
          messageRepo.unackedOutgoingOverride = [msg];

          final p2pService = FakeP2PService(
            initialState: const NodeState(
              isStarted: true,
              peerId: 'my-peer-id',
            ),
            storeInInboxResult: true,
          );

          await retryUnackedMessages(
            messageRepo: messageRepo,
            p2pService: p2pService,
          );

          expect(
            p2pService.storeInInboxCallCount,
            1,
            reason:
                'a crash-recovered transport-inbox row has NO custody proof '
                '— it must be re-stored, never blind-flipped',
          );
          final saved = messageRepo.lastSavedMessage;
          expect(saved!.status, 'inboxed');
          expect(saved.wireEnvelope, isNotNull);
        },
      );

      test(
        "successful inbox re-store flips 'sent' → 'inboxed' and retains wire_envelope",
        () async {
          final msg = _makeSentMessage(id: 'msg-restore-custody-001');
          messageRepo.seed([msg]);
          messageRepo.unackedOutgoingOverride = [msg];

          final p2pService = FakeP2PService(
            initialState: const NodeState(
              isStarted: true,
              peerId: 'my-peer-id',
            ),
            storeInInboxResult: true,
          );

          final count = await retryUnackedMessages(
            messageRepo: messageRepo,
            p2pService: p2pService,
          );

          expect(count, 1);
          final saved = messageRepo.lastSavedMessage;
          expect(saved!.status, 'inboxed');
          expect(saved.transport, 'inbox');
          expect(
            saved.wireEnvelope,
            isNotNull,
            reason: 'the custody sweep still owns the envelope until receipt',
          );
        },
      );
    });
  });
}

class _ThrowingInboxP2PService extends FakeP2PService {
  final Set<int> throwOnIndices;
  int _storeCallIndex = 0;

  _ThrowingInboxP2PService({
    required super.initialState,
    required this.throwOnIndices,
  });

  @override
  Future<bool> storeInInbox(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    storeInInboxCallCount++;
    final idx = _storeCallIndex++;
    if (throwOnIndices.contains(idx)) {
      throw Exception('storeInInbox error at index $idx');
    }
    return true;
  }
}

/// Exposes ONLY the shared v109 lifecycle capability.
///
/// 356: a private deletion event is staged by the private owner, so unacked
/// retry must resolve its exact custody through the generic lifecycle
/// interface, never through the ordinary text-stage capability.
class _LifecycleOnlyMutationCustodyRepository
    implements
        MessageRepository,
        OutgoingTransportMutationRepository,
        DirectMutationInboxCustodyLifecycleRepository {
  _LifecycleOnlyMutationCustodyRepository(
    this.delegate, {
    required this.db,
    this.onLookup,
  });

  final FakeMessageRepository delegate;

  /// The REAL physical v109 outbox, read through the same helpers production
  /// wires into [MessageRepositoryImpl].
  final Database db;

  /// Fires before each lookup with its 1-based index, so a test can move
  /// ownership at an exact production checkpoint without a production hook.
  final Future<void> Function(int lookupIndex)? onLookup;

  int lifecycleLookups = 0;

  /// The lookup indexes that actually resolved an owner.
  final List<int> ownedAtLookups = <int>[];

  @override
  bool get supportsDirectMutationInboxCustodyLifecycle => true;

  @override
  Future<DirectReactionInboxCustodyOutboxEntry?>
  loadDirectTextMutationInboxCustodyForEvent({
    required String recipientPeerId,
    required String eventId,
  }) async {
    lifecycleLookups++;
    await onLookup?.call(lifecycleLookups);
    final row = await dbLoadDirectReactionInboxCustodyOutboxForEvent(
      db,
      recipientPeerId: recipientPeerId,
      eventId: eventId,
    );
    if (row == null) return null;
    ownedAtLookups.add(lifecycleLookups);
    return DirectReactionInboxCustodyOutboxEntry.fromMap(row);
  }

  @override
  Future<bool> recordDirectTextMutationInboxCustodyFailureIfExact({
    required DirectReactionInboxCustodyOutboxEntry expected,
    required String errorCode,
  }) => dbRecordDirectReactionInboxCustodyFailureIfExact(
    db,
    recipientPeerId: expected.recipientPeerId,
    eventId: expected.eventId,
    expectedWireEnvelope: expected.wireEnvelope,
    errorCode: errorCode,
    attemptedAt: DateTime.utc(2026).toIso8601String(),
  );

  @override
  Future<DirectMutationInboxCustodyCompletionOutcome>
  completeAcceptedDirectTextMutationInboxCustodyIfExact({
    required DirectReactionInboxCustodyOutboxEntry expected,
    required int? relayExpiresAt,
  }) => dbCompleteAcceptedDirectMutationInboxCustodyIfExact(
    db,
    recipientPeerId: expected.recipientPeerId,
    eventId: expected.eventId,
    expectedWireEnvelope: expected.wireEnvelope,
    relayExpiresAt: relayExpiresAt,
  );

  @override
  Future<ConversationMessage?> getMessage(String id) => delegate.getMessage(id);

  @override
  Future<List<ConversationMessage>> getUnackedOutgoingMessages({
    required Duration olderThan,
  }) => delegate.getUnackedOutgoingMessages(olderThan: olderThan);

  // The incumbent ordinary settlement surface stays available: only the
  // TEXT-STAGE custody capability is withheld, so a retry that casts through
  // it misses an owner the shared v109 lifecycle would have found.
  @override
  Future<OutgoingOrdinaryMutationResult> stageOutgoingOrdinaryAttempt({
    required ConversationMessage? expected,
    required ConversationMessage staged,
    required OutgoingOrdinaryAttemptKind kind,
  }) => delegate.stageOutgoingOrdinaryAttempt(
    expected: expected,
    staged: staged,
    kind: kind,
  );

  @override
  Future<OutgoingOrdinaryMutationResult> settleOutgoingOrdinaryTransport({
    required String messageId,
    required String expectedContactPeerId,
    required String? expectedEnvelope,
    required String status,
    required String? transport,
    required int? relayExpiresAt,
    required OutgoingOrdinarySettlementMode mode,
  }) => delegate.settleOutgoingOrdinaryTransport(
    messageId: messageId,
    expectedContactPeerId: expectedContactPeerId,
    expectedEnvelope: expectedEnvelope,
    status: status,
    transport: transport,
    relayExpiresAt: relayExpiresAt,
    mode: mode,
  );

  @override
  Future<OutgoingOrdinaryMutationResult> settleOutgoingOrdinaryDeleteTombstone({
    required String messageId,
    required String expectedContactPeerId,
    required String? expectedEnvelope,
    required String status,
    required String? transport,
    required int? relayExpiresAt,
    required OutgoingOrdinarySettlementMode mode,
  }) => delegate.settleOutgoingOrdinaryDeleteTombstone(
    messageId: messageId,
    expectedContactPeerId: expectedContactPeerId,
    expectedEnvelope: expectedEnvelope,
    status: status,
    transport: transport,
    relayExpiresAt: relayExpiresAt,
    mode: mode,
  );

  @override
  Future<OutgoingOrdinaryMutationResult> invalidateOutgoingOrdinaryEnvelope({
    required String messageId,
    required String expectedContactPeerId,
    required String expectedEnvelope,
  }) => delegate.invalidateOutgoingOrdinaryEnvelope(
    messageId: messageId,
    expectedContactPeerId: expectedContactPeerId,
    expectedEnvelope: expectedEnvelope,
  );

  @override
  Future<OutgoingOrdinaryMutationResult>
  quarantineUnsafeLegacyOutgoingEnvelope({
    required String messageId,
    required String expectedContactPeerId,
    required String expectedEnvelope,
    required bool isDeleteTombstone,
  }) => delegate.quarantineUnsafeLegacyOutgoingEnvelope(
    messageId: messageId,
    expectedContactPeerId: expectedContactPeerId,
    expectedEnvelope: expectedEnvelope,
    isDeleteTombstone: isDeleteTombstone,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'lifecycle-only repository received ${invocation.memberName}',
  );
}
