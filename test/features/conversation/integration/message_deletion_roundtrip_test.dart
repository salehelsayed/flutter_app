import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

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

  group('message deletion roundtrip', () {
    test(
      'online delete-for-everyone hides the sender row and tombstones recipient',
      () async {
        final (sendResult, sentMessage) = await alice.sendMessage(
          bob.peerId,
          'Hello Bob',
        );
        expect(sendResult, SendChatMessageResult.success);
        expect(sentMessage, isNotNull);

        await Future<void>.delayed(const Duration(milliseconds: 100));

        final (deleteResult, deleteMessage) = await alice
            .deleteMessageForEveryone(sentMessage!);
        expect(deleteResult, SendChatMessageResult.success);
        expect(deleteMessage, isNotNull);

        await Future<void>.delayed(const Duration(milliseconds: 150));

        final aliceConversation = await alice.loadConversationWith(bob.peerId);
        final bobConversation = await bob.loadConversationWith(alice.peerId);

        expect(aliceConversation, isEmpty);
        expect(bobConversation, hasLength(1));
        expect(bobConversation.single.id, sentMessage.id);
        expect(bobConversation.single.text, isEmpty);
        expect(bobConversation.single.isDeleted, isTrue);
        expect(bobConversation.single.isHidden, isFalse);
      },
    );

    test(
      'offline inbox ordering leaves the recipient with a tombstoned final row',
      () async {
        bob.setOnline(false);

        final (sendResult, sentMessage) = await alice.sendMessage(
          bob.peerId,
          'Message to retract',
        );
        expect(sendResult, SendChatMessageResult.success);
        expect(sentMessage, isNotNull);

        final (deleteResult, deleteMessage) = await alice
            .deleteMessageForEveryone(sentMessage!);
        expect(deleteResult, SendChatMessageResult.success);
        expect(deleteMessage, isNotNull);

        final aliceConversation = await alice.loadConversationWith(bob.peerId);
        expect(aliceConversation, isEmpty);

        bob.setOnline(true);
        final drained = await bob.drainOfflineInbox();
        expect(drained, 2);

        await Future<void>.delayed(const Duration(milliseconds: 150));

        final bobConversation = await bob.loadConversationWith(alice.peerId);
        expect(bobConversation, hasLength(1));
        expect(bobConversation.single.id, sentMessage.id);
        expect(bobConversation.single.text, isEmpty);
        expect(bobConversation.single.isDeleted, isTrue);
        expect(bobConversation.single.isHidden, isFalse);
      },
    );
  });
}
