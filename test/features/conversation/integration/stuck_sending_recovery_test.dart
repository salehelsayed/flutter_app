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
