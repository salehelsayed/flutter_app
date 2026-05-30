import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/application/recover_stuck_sending_messages_use_case.dart';
import 'package:flutter_app/features/conversation/application/retry_failed_messages_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart'
    as p2p;
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';

import '../../../core/services/fake_p2p_service.dart';
import '../../../core/bridge/fake_bridge.dart';
import '../domain/repositories/fake_message_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';
import '../../contacts/domain/repositories/fake_contact_repository.dart';

void main() {
  group('Stuck-sending recovery — smoke test', () {
    test(
      'message stuck in sending is recovered and delivered on next resume+online',
      () async {
        // --- Arrange ---
        // Simulate what was persisted when the user sent and backgrounded
        final stuckTs = DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 2))
            .toIso8601String();

        final stuckMessage = ConversationMessage(
          id: 'msg-stuck-smoke',
          contactPeerId: 'peer-bob',
          senderPeerId: 'peer-alice',
          text: 'Hello Bob!',
          timestamp: stuckTs,
          status: 'sending', // <-- stuck here after kill
          isIncoming: false,
          createdAt: stuckTs,
          wireEnvelope: null, // realistic: envelope not yet serialized
        );

        final messageRepo = FakeMessageRepository()..seed([stuckMessage]);
        final identityRepo = FakeIdentityRepository()
          ..seed(
            IdentityModel(
              peerId: 'peer-alice',
              publicKey: 'pk-alice',
              privateKey: 'sk-alice',
              mnemonic12:
                  'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
              createdAt: stuckTs,
              updatedAt: stuckTs,
            ),
          );
        final contactRepo = FakeContactRepository()
          ..seed([
            ContactModel(
              peerId: 'peer-bob',
              publicKey: 'pk-bob',
              rendezvous: '/ip4/127.0.0.1/tcp/4001',
              username: 'Bob',
              signature: 'sig',
              scannedAt: stuckTs,
              mlKemPublicKey: 'mlkem-peer-bob',
            ),
          ]);
        final p2pService = FakeP2PService(
          initialState: const NodeState(
            isStarted: true,
            peerId: 'peer-alice',
            circuitAddresses: ['/p2p-circuit/addr1'],
          ),
          storeInInboxResult: true,
          discoverPeerResult: const DiscoveredPeer(
            id: 'peer-bob',
            addresses: ['/ip4/127.0.0.1/tcp/4001'],
          ),
          dialPeerResult: true,
          sendMessageWithReplyResult: const p2p.SendMessageResult(
            sent: true,
            reply: 'ack',
          ),
        );
        final bridge = FakeBridge(
          initialResponses: {
            'message.encrypt': {
              'ok': true,
              'kem': 'fake-kem',
              'ciphertext': 'fake-ct',
              'nonce': 'fake-nonce',
            },
          },
        );

        // --- Act: simulate app resume recovery sequence ---

        // Step 1: recover stuck messages (transitions sending -> failed IN PLACE)
        final recovered = await recoverStuckSendingMessages(
          messageRepo: messageRepo,
          threshold: const Duration(seconds: 30),
        );
        expect(recovered, 1);

        // Verify same row was transitioned -- NOT manually re-seeded
        final afterRecovery = await messageRepo.getMessagesForContact(
          'peer-bob',
        );
        final recoveredMsg = afterRecovery.firstWhere(
          (m) => m.id == 'msg-stuck-smoke',
        );
        expect(recoveredMsg.status, 'failed');

        // Step 2: retry failed messages (picks up the recovered message)
        final retried = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
        );

        // --- Assert ---
        expect(retried, 1);

        final saved = messageRepo.lastSavedMessage;
        expect(saved, isNotNull);
        expect(saved!.id, 'msg-stuck-smoke'); // same row, not a new message
        // Either delivered (inbox path) or at minimum no longer 'sending'
        expect(saved.status, isNot('sending'));
        expect(saved.status, isNot('failed'));
      },
    );

    test(
      'message younger than threshold remains sending and is not retried',
      () async {
        final recentTs = DateTime.now()
            .toUtc()
            .subtract(const Duration(seconds: 5))
            .toIso8601String();

        final youngMessage = ConversationMessage(
          id: 'msg-young',
          contactPeerId: 'peer-bob',
          senderPeerId: 'peer-alice',
          text: 'Still in flight',
          timestamp: recentTs,
          status: 'sending',
          isIncoming: false,
          createdAt: recentTs,
        );

        final messageRepo = FakeMessageRepository()..seed([youngMessage]);

        final count = await recoverStuckSendingMessages(
          messageRepo: messageRepo,
          threshold: const Duration(seconds: 30),
        );

        expect(count, 0);
        // The seeded message must still be 'sending'
        final messages = await messageRepo.getMessagesForContact('peer-bob');
        expect(messages.first.status, 'sending');
      },
    );

    // --- NET-REL-05 R1: concurrent-fallback interaction (regression) ---
    //
    // The full resume sequence is recoverStuckSending -> retryFailed. A message
    // whose concurrent durable fallback already took custody is settled as
    // delivered/inbox/null-envelope. It must survive BOTH steps untouched: it is
    // neither 'sending' (so recovery skips it) nor 'failed' (so the failed
    // retrier skips it). Meanwhile a genuinely stuck 'sending' row in the same
    // batch must still be reclassified sending>30s -> failed and then retried.
    test(
      'concurrently-inboxed message survives recover+retry untouched while a '
      'stuck sending message is still reclassified and retried',
      () async {
        final stuckTs = DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 2))
            .toIso8601String();

        final stuckMessage = ConversationMessage(
          id: 'msg-stuck-coexist',
          contactPeerId: 'peer-bob',
          senderPeerId: 'peer-alice',
          text: 'Stuck Hello',
          timestamp: stuckTs,
          status: 'sending',
          isIncoming: false,
          createdAt: stuckTs,
          wireEnvelope: null,
        );

        // Already-durable concurrent-fallback row to a different peer.
        final concurrentlyInboxed = ConversationMessage(
          id: 'msg-concurrent-inbox-coexist',
          contactPeerId: 'peer-carol',
          senderPeerId: 'peer-alice',
          text: 'Low-confidence send',
          timestamp: stuckTs,
          status: 'delivered',
          isIncoming: false,
          createdAt: stuckTs,
          transport: 'inbox',
          wireEnvelope: null,
        );

        final messageRepo = FakeMessageRepository()
          ..seed([stuckMessage, concurrentlyInboxed]);
        final identityRepo = FakeIdentityRepository()
          ..seed(
            IdentityModel(
              peerId: 'peer-alice',
              publicKey: 'pk-alice',
              privateKey: 'sk-alice',
              mnemonic12:
                  'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
              createdAt: stuckTs,
              updatedAt: stuckTs,
            ),
          );
        final contactRepo = FakeContactRepository()
          ..seed([
            ContactModel(
              peerId: 'peer-bob',
              publicKey: 'pk-bob',
              rendezvous: '/ip4/127.0.0.1/tcp/4001',
              username: 'Bob',
              signature: 'sig',
              scannedAt: stuckTs,
              mlKemPublicKey: 'mlkem-peer-bob',
            ),
            ContactModel(
              peerId: 'peer-carol',
              publicKey: 'pk-carol',
              rendezvous: '/ip4/127.0.0.1/tcp/4001',
              username: 'Carol',
              signature: 'sig',
              scannedAt: stuckTs,
              mlKemPublicKey: 'mlkem-peer-carol',
            ),
          ]);
        final p2pService = FakeP2PService(
          initialState: const NodeState(
            isStarted: true,
            peerId: 'peer-alice',
            circuitAddresses: ['/p2p-circuit/addr1'],
          ),
          storeInInboxResult: true,
          discoverPeerResult: const DiscoveredPeer(
            id: 'peer-bob',
            addresses: ['/ip4/127.0.0.1/tcp/4001'],
          ),
          dialPeerResult: true,
          sendMessageWithReplyResult: const p2p.SendMessageResult(
            sent: true,
            reply: 'ack',
          ),
        );
        final bridge = FakeBridge(
          initialResponses: {
            'message.encrypt': {
              'ok': true,
              'kem': 'fake-kem',
              'ciphertext': 'fake-ct',
              'nonce': 'fake-nonce',
            },
          },
        );

        // Step 1: recovery only flips the stuck 'sending' row -> 'failed'.
        // The concurrent-inbox row is NOT 'sending', so it is untouched.
        final recovered = await recoverStuckSendingMessages(
          messageRepo: messageRepo,
          threshold: const Duration(seconds: 30),
        );
        expect(recovered, 1);
        expect(
          (await messageRepo.getMessage('msg-stuck-coexist'))?.status,
          'failed',
        );
        // NEGATIVE CONTROL: durable copy untouched by recovery.
        final carolAfterRecovery = await messageRepo.getMessage(
          'msg-concurrent-inbox-coexist',
        );
        expect(carolAfterRecovery?.status, 'delivered');
        expect(carolAfterRecovery?.transport, 'inbox');

        // Step 2: retryFailed picks up ONLY the recovered stuck row, not the
        // already-durable concurrent-inbox row.
        final retried = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
        );

        // Exactly one message retried (the stuck one). The concurrent-inbox copy
        // was NOT double-retried.
        expect(retried, 1);
        expect(messageRepo.getFailedOutgoingCallCount, 1);

        // NEGATIVE CONTROL: durable copy STILL delivered/inbox after the full
        // sequence — never re-sent live, never re-stored.
        final carolFinal = await messageRepo.getMessage(
          'msg-concurrent-inbox-coexist',
        );
        expect(carolFinal?.status, 'delivered');
        expect(carolFinal?.transport, 'inbox');

        // The stuck row is now resolved (delivered/sent), no longer 'sending'.
        final bobFinal = await messageRepo.getMessage('msg-stuck-coexist');
        expect(bobFinal?.status, isNot('sending'));
        expect(bobFinal?.status, isNot('failed'));
      },
    );

    test(
      'recoverStuckSending reclassifies sending>30s to failed and leaves a '
      'concurrently-inboxed row alone',
      () async {
        final stuckTs = DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 2))
            .toIso8601String();

        final messageRepo = FakeMessageRepository()
          ..seed([
            ConversationMessage(
              id: 'msg-stuck-only',
              contactPeerId: 'peer-bob',
              senderPeerId: 'peer-alice',
              text: 'Stuck',
              timestamp: stuckTs,
              status: 'sending',
              isIncoming: false,
              createdAt: stuckTs,
            ),
            ConversationMessage(
              id: 'msg-durable',
              contactPeerId: 'peer-carol',
              senderPeerId: 'peer-alice',
              text: 'Durable',
              timestamp: stuckTs,
              status: 'delivered',
              isIncoming: false,
              createdAt: stuckTs,
              transport: 'inbox',
              wireEnvelope: null,
            ),
          ]);

        final recovered = await recoverStuckSendingMessages(
          messageRepo: messageRepo,
          threshold: const Duration(seconds: 30),
        );

        // Only the stuck 'sending' row is reclassified.
        expect(recovered, 1);
        expect(
          (await messageRepo.getMessage('msg-stuck-only'))?.status,
          'failed',
        );
        // NEGATIVE CONTROL: the durable concurrent-inbox row is not a recovery
        // candidate and is left exactly as-is.
        final durable = await messageRepo.getMessage('msg-durable');
        expect(durable?.status, 'delivered');
        expect(durable?.transport, 'inbox');
        expect(durable?.wireEnvelope, isNull);
      },
    );

    test('no stuck messages — both recovery and retry are no-ops', () async {
      final messageRepo = FakeMessageRepository(); // empty
      final identityRepo = FakeIdentityRepository();
      final p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'peer-alice'),
      );
      final bridge = FakeBridge();
      final contactRepo = FakeContactRepository();

      final recovered = await recoverStuckSendingMessages(
        messageRepo: messageRepo,
      );
      expect(recovered, 0);

      // retryFailedMessages returns 0 — no identity, so early exit
      final retried = await retryFailedMessages(
        messageRepo: messageRepo,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        bridge: bridge,
      );
      expect(retried, 0);
    });
  });
}
