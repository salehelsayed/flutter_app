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

    test('marks delivered via inbox and sets transport to inbox', () async {
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

      // Verify saved message has transport='inbox' and status='delivered'
      final saved = messageRepo.lastSavedMessage;
      expect(saved, isNotNull);
      expect(saved!.status, 'delivered');
      expect(saved.transport, 'inbox');
    });

    test('clears wireEnvelope after successful inbox store', () async {
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

      expect(messageRepo.lastSavedMessage!.wireEnvelope, isNull);
    });

    test(
      'hides delivered outgoing delete tombstones after inbox retry succeeds',
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
        expect(saved!.status, 'delivered');
        expect(saved.isDeleted, isTrue);
        expect(saved.isHidden, isTrue);
        expect(saved.hiddenAt, saved.deletedAt);
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

    test('retryUnackedMessages skips storeInInbox when message transport '
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
            '{"type":"chat","version":"1","payload":{"id":"msg-crash-002"}}',
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

      // storeInInbox should NOT be called — message already has transport='inbox'
      expect(p2pService.storeInInboxCallCount, 0);
      // But the message should still be marked as delivered
      expect(count, 1);
      final saved = messageRepo.lastSavedMessage;
      expect(saved, isNotNull);
      expect(saved!.status, 'delivered');
      expect(saved.wireEnvelope, isNull);
    });

    test('continues on storeInInbox error and tries next message', () async {
      final msg1 = _makeSentMessage(id: 'msg-1', contactPeerId: 'peer-a');
      final msg2 = _makeSentMessage(id: 'msg-2', contactPeerId: 'peer-b');
      messageRepo.seed([msg1, msg2]);
      messageRepo.unackedOutgoingOverride = [msg1, msg2];

      // First call throws, second succeeds
      var callCount = 0;
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
