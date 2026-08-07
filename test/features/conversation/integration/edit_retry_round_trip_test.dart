// 116 Phase 1.2 — end-to-end convergence proof for edit retry fidelity.
//
// A failed-then-retried edit must converge sender and receiver text + edited
// badge. Pre-116 the retry pipeline downgraded the edit to a plain send under
// the original id: the receiver deduped it by id (kept the PRE-edit text)
// while the sender settled 'delivered' with editedAt silently nulled —
// permanent, invisible content divergence (doc 116 §1).

import 'package:flutter_app/features/conversation/application/retry_failed_messages_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../features/identity/domain/repositories/fake_identity_repository.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/test_user.dart';

void main() {
  late FakeP2PNetwork network;
  late TestUser alice;
  late TestUser bob;

  setUp(() {
    network = FakeP2PNetwork();

    alice = TestUser.create(
      peerId: '12D3KooWAlicePeerId00000000001',
      username: 'Alice',
      network: network,
    );
    bob = TestUser.create(
      peerId: '12D3KooWBobPeerIdxxx00000000002',
      username: 'Bob',
      network: network,
    );

    alice.addContact(bob);
    bob.addContact(alice);

    alice.start();
    bob.start();
  });

  tearDown(() {
    alice.dispose();
    bob.dispose();
  });

  group('116 P1 — edit retry round trip', () {
    test(
      'sender and receiver text converge after a failed-then-retried edit (divergence repair)',
      () async {
        // 1. Healthy send: bob holds the pre-edit text.
        final bobReceivedOriginal =
            bob.chatListener.incomingMessageStream.first;
        final (sendResult, sentMessage) = await alice.sendMessage(
          bob.peerId,
          'original text',
        );
        expect(sendResult, SendChatMessageResult.success);
        await bobReceivedOriginal.timeout(const Duration(seconds: 2));

        var bobConvo = await bob.loadConversationWith(alice.peerId);
        expect(bobConvo.single.text, 'original text');

        // 2. Transport blackout: the edit fails terminally and persists a
        //    'failed' row carrying editedAt + the v2 EDIT envelope.
        network.deliveryFails = true;
        network.inboxDisabled = true;

        final recipientKey = (await alice.contactRepo.getContact(
          bob.peerId,
        ))!.mlKemPublicKey;
        final (editResult, _) = await editChatMessage(
          p2pService: alice.p2pService,
          messageRepo: alice.messageRepo,
          originalMessage: sentMessage!,
          updatedText: 'edited text',
          senderUsername: alice.username,
          bridge: alice.bridge,
          recipientMlKemPublicKey: recipientKey,
        );
        expect(editResult, isNot(SendChatMessageResult.success));

        final failedRow = await alice.messageRepo.getMessage(sentMessage.id);
        expect(failedRow!.status, 'failed');
        expect(failedRow.editedAt, isNotNull);
        expect(failedRow.wireEnvelope, isNotNull);

        // 3. Heal relay STORE. A current edit event owns one immutable
        //    envelope/eventId, so retry must replay those exact bytes and may
        //    not fall through to a fresh direct re-encryption.
        network.deliveryFails = false;
        network.inboxDisabled = false;

        final identityRepo = FakeIdentityRepository()
          ..seed(
            IdentityModel(
              peerId: alice.peerId,
              publicKey: 'pk-${alice.peerId}',
              privateKey: 'privkey',
              mnemonic12: 'w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12',
              username: alice.username,
              createdAt: '2026-01-01T00:00:00.000Z',
              updatedAt: '2026-01-01T00:00:00.000Z',
            ),
          );

        final bobReceivedEdit = bob.chatListener.incomingMessageStream.first;
        final retried = await retryFailedMessages(
          messageRepo: alice.messageRepo,
          identityRepo: identityRepo,
          contactRepo: alice.contactRepo,
          p2pService: alice.p2pService,
          bridge: alice.bridge,
        );
        expect(retried, 1);
        await bob.p2pService.drainOfflineInbox();
        await bobReceivedEdit.timeout(const Duration(seconds: 2));
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // 4. Convergence: bob displays the EDITED text with editedAt set
        //    (edit applied via the action-aware receive path), and alice's
        //    edited badge survives the retry.
        bobConvo = await bob.loadConversationWith(alice.peerId);
        expect(bobConvo, hasLength(1));
        expect(
          bobConvo.single.text,
          'edited text',
          reason:
              'the retried edit must apply on the receiver, not be deduped '
              'by id as a plain duplicate',
        );
        expect(bobConvo.single.editedAt, isNotNull);

        final aliceRow = await alice.messageRepo.getMessage(sentMessage.id);
        expect(
          aliceRow!.editedAt,
          isNotNull,
          reason: "the sender's edited badge must survive the retry",
        );
      },
    );
  });
}
