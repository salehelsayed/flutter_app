import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/application/retry_unacked_messages_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../../../core/services/fake_p2p_service.dart';
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
      expect(saved.transport, 'direct');
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
