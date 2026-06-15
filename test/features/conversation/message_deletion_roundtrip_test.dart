// Audit gap: message_deletion_roundtrip (124 Phase 8).
//
// End-to-end 1:1 delete-for-everyone roundtrip across the fake transport:
//   alice.deleteMessageForEveryone (DeleteMessageUseCase)
//     -> FakeP2PNetwork (fake send/receive transport)
//       -> bob's MessageDeletionListener -> handleIncomingMessageDeletion
//         -> bob stores/renders a TOMBSTONE in place of the original row.
//
// The contract under test (per delete_message_tombstone_visibility +
// handle_incoming_message_deletion_use_case): the receiver swaps the message
// for a tombstone — the stored/rendered row keeps the original id but has
// EMPTY text and isDeleted == true. The original plaintext must never survive
// on the receiver. A sibling integration suite lives at
// test/features/conversation/integration/message_deletion_roundtrip_test.dart;
// this file pins the single core claim on its own.

import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../shared/fakes/fake_p2p_network.dart';
import '../../shared/fakes/test_user.dart';

const _originalText = 'Top secret plaintext that must be retracted';

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
      withMessageDeletion: true,
    );
    bob = TestUser.create(
      peerId: '12D3KooWBobPeerIdxxx00000000002',
      username: 'Bob',
      network: network,
      withMessageDeletion: true,
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

  test(
    'delete-for-everyone makes the receiver render/store a tombstone, '
    'never the original text',
    () async {
      // Alice sends the original message; Bob receives and stores its text.
      final (sendResult, sentMessage) = await alice.sendMessage(
        bob.peerId,
        _originalText,
      );
      expect(sendResult, SendChatMessageResult.success);
      expect(sentMessage, isNotNull);

      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Precondition: Bob has the real, undeleted message with its plaintext.
      final bobBeforeDelete = await bob.loadConversationWith(alice.peerId);
      expect(bobBeforeDelete, hasLength(1));
      expect(bobBeforeDelete.single.id, sentMessage!.id);
      expect(bobBeforeDelete.single.text, _originalText);
      expect(bobBeforeDelete.single.isDeleted, isFalse);

      // Alice retracts the message for everyone. The deletion envelope rides
      // the fake transport to Bob's MessageDeletionListener.
      final (deleteResult, deletedMessage) = await alice
          .deleteMessageForEveryone(sentMessage);
      expect(deleteResult, SendChatMessageResult.success);
      expect(deletedMessage, isNotNull);

      await Future<void>.delayed(const Duration(milliseconds: 150));

      // The receiver swapped the message for a tombstone: same id, empty text,
      // isDeleted true, attributed to Alice — and it is still visible (not
      // hidden) so the recipient sees a "deleted" placeholder rather than the
      // row silently vanishing.
      final bobAfterDelete = await bob.loadConversationWith(alice.peerId);
      expect(bobAfterDelete, hasLength(1));
      final tombstone = bobAfterDelete.single;
      expect(tombstone.id, sentMessage.id);
      expect(tombstone.text, isEmpty);
      expect(tombstone.isDeleted, isTrue);
      expect(tombstone.isHidden, isFalse);
      expect(tombstone.deletedByPeerId, alice.peerId);

      // The original plaintext must not survive anywhere on the receiver.
      final storedTombstone = await bob.messageRepo.getMessage(sentMessage.id);
      expect(storedTombstone, isNotNull);
      expect(storedTombstone!.text, isEmpty);
      expect(storedTombstone.isDeleted, isTrue);
      expect(
        bobAfterDelete.any((m) => m.text == _originalText),
        isFalse,
        reason: 'original plaintext leaked past delete-for-everyone',
      );

      // Sender side: the sent row is gone from Alice's own view (online
      // delivery hides the outgoing tombstone).
      final aliceAfterDelete = await alice.loadConversationWith(bob.peerId);
      expect(aliceAfterDelete, isEmpty);
    },
  );
}
