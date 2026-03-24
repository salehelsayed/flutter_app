import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/application/retry_unacked_messages_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';

import '../domain/repositories/fake_message_repository.dart';
import '../../../core/services/fake_p2p_service.dart';

const _testTs = '2026-01-01T00:00:00.000Z';

void main() {
  late FakeMessageRepository messageRepo;
  late FakeP2PService p2pService;

  setUp(() {
    messageRepo = FakeMessageRepository();
    p2pService = FakeP2PService(storeInInboxResult: true);
  });

  tearDown(() {
    p2pService.dispose();
  });

  group('retryUnackedMessages -- null wireEnvelope guard', () {
    // ------------------------------------------------------------------
    // C.2-TEST-1: null wireEnvelope is skipped, not dereferenced
    // ------------------------------------------------------------------
    test(
      'skips message with null wireEnvelope without crashing',
      () async {
        // Force the unacked query to return a message with null wireEnvelope.
        // In production this should not happen (SQL filters it out), but
        // defensive code must handle it.
        final badMsg = ConversationMessage(
          id: 'msg-null-envelope',
          contactPeerId: 'peer-bob',
          senderPeerId: 'peer-alice',
          text: 'Hello',
          timestamp: _testTs,
          status: 'sent',
          isIncoming: false,
          createdAt: _testTs,
          wireEnvelope: null, // <-- null despite being 'sent'
        );
        messageRepo.unackedOutgoingOverride = [badMsg];

        // Must NOT throw a null dereference error
        final count = await retryUnackedMessages(
          messageRepo: messageRepo,
          p2pService: p2pService,
        );

        // Skipped -- no inbox store attempted
        expect(p2pService.storeInInboxCallCount, 0);
        expect(count, 0);
      },
    );

    // ------------------------------------------------------------------
    // C.2-TEST-2: empty wireEnvelope is also skipped
    // ------------------------------------------------------------------
    test(
      'skips message with empty wireEnvelope string',
      () async {
        final badMsg = ConversationMessage(
          id: 'msg-empty-envelope',
          contactPeerId: 'peer-bob',
          senderPeerId: 'peer-alice',
          text: 'Hello',
          timestamp: _testTs,
          status: 'sent',
          isIncoming: false,
          createdAt: _testTs,
          wireEnvelope: '', // <-- empty string
        );
        messageRepo.unackedOutgoingOverride = [badMsg];

        final count = await retryUnackedMessages(
          messageRepo: messageRepo,
          p2pService: p2pService,
        );

        expect(p2pService.storeInInboxCallCount, 0);
        expect(count, 0);
      },
    );

    // ------------------------------------------------------------------
    // C.2-TEST-3: valid wireEnvelope is still processed normally
    // ------------------------------------------------------------------
    test(
      'processes message with valid wireEnvelope normally',
      () async {
        const envelope = '{"type":"chat_message","version":"1","payload":{}}';
        final goodMsg = ConversationMessage(
          id: 'msg-good-envelope',
          contactPeerId: 'peer-bob',
          senderPeerId: 'peer-alice',
          text: 'Hello',
          timestamp: _testTs,
          status: 'sent',
          isIncoming: false,
          createdAt: _testTs,
          wireEnvelope: envelope,
        );
        messageRepo.unackedOutgoingOverride = [goodMsg];

        final count = await retryUnackedMessages(
          messageRepo: messageRepo,
          p2pService: p2pService,
        );

        expect(p2pService.storeInInboxCallCount, 1);
        expect(p2pService.lastStoreInInboxMessage, envelope);
        expect(count, 1);
      },
    );

    // ------------------------------------------------------------------
    // C.2-TEST-4: mixed batch -- null envelope skipped, valid processed
    // ------------------------------------------------------------------
    test(
      'in a mixed batch, skips null envelopes and processes valid ones',
      () async {
        const envelope = '{"type":"chat_message","version":"1","payload":{}}';
        final nullMsg = ConversationMessage(
          id: 'msg-null',
          contactPeerId: 'peer-bob',
          senderPeerId: 'peer-alice',
          text: 'Bad',
          timestamp: _testTs,
          status: 'sent',
          isIncoming: false,
          createdAt: _testTs,
          wireEnvelope: null,
        );
        final goodMsg = ConversationMessage(
          id: 'msg-good',
          contactPeerId: 'peer-bob',
          senderPeerId: 'peer-alice',
          text: 'Good',
          timestamp: _testTs,
          status: 'sent',
          isIncoming: false,
          createdAt: _testTs,
          wireEnvelope: envelope,
        );
        messageRepo.unackedOutgoingOverride = [nullMsg, goodMsg];

        final count = await retryUnackedMessages(
          messageRepo: messageRepo,
          p2pService: p2pService,
        );

        // Only the good message was stored
        expect(p2pService.storeInInboxCallCount, 1);
        expect(count, 1);

        // The good message was delivered
        final saved = messageRepo.lastSavedMessage;
        expect(saved, isNotNull);
        expect(saved!.id, 'msg-good');
        expect(saved.status, 'delivered');
      },
    );
  });
}
