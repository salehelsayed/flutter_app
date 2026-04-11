import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/message_deletion_payload.dart';
import 'package:flutter_app/features/conversation/domain/models/message_payload.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
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

    test(
      'delete arriving before the original still leaves the recipient on a tombstoned final row',
      () async {
        const messageId = 'msg-delete-before-original';
        final deleteEnvelope = MessageDeletionPayload(
          messageId: messageId,
          senderPeerId: alice.peerId,
          timestamp: '2026-04-01T10:00:00.000Z',
        ).toJson();
        final originalEnvelope = MessagePayload(
          id: messageId,
          text: 'This should never reappear',
          senderPeerId: alice.peerId,
          senderUsername: alice.username,
          timestamp: '2026-04-01T09:59:00.000Z',
        ).toJson();

        bob.p2pService.injectIncomingMessage(
          ChatMessage(
            from: alice.peerId,
            to: bob.peerId,
            content: deleteEnvelope,
            timestamp: '2026-04-01T10:00:00.000Z',
            isIncoming: true,
          ),
        );

        await Future<void>.delayed(const Duration(milliseconds: 50));

        var bobConversation = await bob.loadConversationWith(alice.peerId);
        expect(bobConversation, hasLength(1));
        expect(bobConversation.single.id, messageId);
        expect(bobConversation.single.text, isEmpty);
        expect(bobConversation.single.isDeleted, isTrue);

        bob.p2pService.injectIncomingMessage(
          ChatMessage(
            from: alice.peerId,
            to: bob.peerId,
            content: originalEnvelope,
            timestamp: '2026-04-01T10:00:01.000Z',
            isIncoming: true,
          ),
        );

        await Future<void>.delayed(const Duration(milliseconds: 100));

        bobConversation = await bob.loadConversationWith(alice.peerId);
        expect(bobConversation, hasLength(1));
        expect(bobConversation.single.id, messageId);
        expect(bobConversation.single.text, isEmpty);
        expect(bobConversation.single.isDeleted, isTrue);
        expect(bobConversation.single.isHidden, isFalse);
      },
    );

    test(
      'delete from a now-blocked sender still tombstones the already stored authored row',
      () async {
        final (sendResult, sentMessage) = await alice.sendMessage(
          bob.peerId,
          'Message from soon-blocked Alice',
        );
        expect(sendResult, SendChatMessageResult.success);
        expect(sentMessage, isNotNull);

        await Future<void>.delayed(const Duration(milliseconds: 100));
        await bob.contactRepo.blockContact(alice.peerId);

        final (deleteResult, deleteMessage) = await alice
            .deleteMessageForEveryone(sentMessage!);
        expect(deleteResult, SendChatMessageResult.success);
        expect(deleteMessage, isNotNull);

        await Future<void>.delayed(const Duration(milliseconds: 150));

        final bobConversation = await bob.loadConversationWith(alice.peerId);
        expect(bobConversation, hasLength(1));
        expect(bobConversation.single.id, sentMessage.id);
        expect(bobConversation.single.text, isEmpty);
        expect(bobConversation.single.isDeleted, isTrue);
        expect(bobConversation.single.deletedByPeerId, alice.peerId);
      },
    );

    test(
      'sender restart keeps the pending delete tombstone without resurrecting original content',
      () async {
        final (sendResult, sentMessage) = await alice.sendMessage(
          bob.peerId,
          'Delete survives restart',
        );
        expect(sendResult, SendChatMessageResult.success);
        expect(sentMessage, isNotNull);

        await Future<void>.delayed(const Duration(milliseconds: 100));

        network.deliveryFails = true;
        network.inboxDisabled = true;

        final (deleteResult, failedDelete) = await alice
            .deleteMessageForEveryone(sentMessage!);
        expect(deleteResult, isNot(SendChatMessageResult.success));
        expect(failedDelete, isNotNull);
        expect(failedDelete!.id, sentMessage.id);
        expect(failedDelete.isDeleted, isTrue);
        expect(failedDelete.isHidden, isFalse);

        final beforeRestart = await alice.loadConversationWith(bob.peerId);
        expect(beforeRestart, hasLength(1));
        expect(beforeRestart.single.id, sentMessage.id);
        expect(beforeRestart.single.text, isEmpty);
        expect(beforeRestart.single.isDeleted, isTrue);
        expect(beforeRestart.single.isHidden, isFalse);

        final persistedAliceRepo = alice.messageRepo;
        final persistedAliceContacts = alice.contactRepo;
        alice.dispose();

        alice = TestUser.create(
          peerId: '12D3KooWAlicePeerId00000000001',
          username: 'Alice',
          network: network,
          messageRepo: persistedAliceRepo,
          contactRepo: persistedAliceContacts,
          withMessageDeletion: true,
        );
        alice.start();

        final afterRestart = await alice.loadConversationWith(bob.peerId);
        expect(afterRestart, hasLength(1));
        expect(afterRestart.single.id, sentMessage.id);
        expect(afterRestart.single.text, isEmpty);
        expect(afterRestart.single.isDeleted, isTrue);
        expect(afterRestart.single.isHidden, isFalse);
      },
    );
  });
}
