/// Integration test: Offline inbox round-trip.
///
/// Comprehensive coverage of the offline inbox fallback mechanism:
/// messages stored in inbox when peer is offline, delivered when they come online.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';

import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/test_user.dart';

void main() {
  late FakeP2PNetwork network;
  late TestUser alice;
  late TestUser bob;
  late TestUser charlie;

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
    charlie = TestUser.create(
      peerId: '12D3KooWCharliePeer00000000003',
      username: 'Charlie',
      network: network,
    );

    // Wire contacts
    alice.addContact(bob);
    alice.addContact(charlie);
    bob.addContact(alice);
    bob.addContact(charlie);
    charlie.addContact(alice);
    charlie.addContact(bob);

    alice.start();
    bob.start();
    charlie.start();
  });

  tearDown(() {
    alice.dispose();
    bob.dispose();
    charlie.dispose();
  });

  group('Offline inbox round-trip', () {
    test('3a. Multiple messages stored offline inbox, all delivered in order',
        () async {
      charlie.setOnline(false);

      final received = <ConversationMessage>[];
      final sub = charlie.chatListener.incomingMessageStream.listen(
        (msg) => received.add(msg),
      );

      // Alice sends 3 messages to offline Charlie
      for (final text in ['msg-1', 'msg-2', 'msg-3']) {
        final (r, _) = await alice.sendMessage(charlie.peerId, text);
        expect(r, SendChatMessageResult.success);
      }

      // Charlie comes online and drains
      charlie.setOnline(true);
      final drained = await charlie.drainOfflineInbox();
      expect(drained, 3);

      await Future.delayed(const Duration(milliseconds: 100));

      // All 3 received in order
      expect(received.length, 3);
      expect(received[0].text, 'msg-1');
      expect(received[1].text, 'msg-2');
      expect(received[2].text, 'msg-3');
      for (final msg in received) {
        expect(msg.senderPeerId, alice.peerId);
        expect(msg.isIncoming, true);
      }

      await sub.cancel();
    });

    test('3b. Multiple senders to same offline peer', () async {
      charlie.setOnline(false);

      final received = <ConversationMessage>[];
      final sub = charlie.chatListener.incomingMessageStream.listen(
        (msg) => received.add(msg),
      );

      // Alice sends 2
      await alice.sendMessage(charlie.peerId, 'from-alice-1');
      await alice.sendMessage(charlie.peerId, 'from-alice-2');
      // Bob sends 1
      await bob.sendMessage(charlie.peerId, 'from-bob-1');

      charlie.setOnline(true);
      await charlie.drainOfflineInbox();
      await Future.delayed(const Duration(milliseconds: 100));

      expect(received.length, 3);

      final aliceMessages =
          received.where((m) => m.senderPeerId == alice.peerId).toList();
      final bobMessages =
          received.where((m) => m.senderPeerId == bob.peerId).toList();

      expect(aliceMessages.length, 2);
      expect(bobMessages.length, 1);
      expect(bobMessages.first.text, 'from-bob-1');

      await sub.cancel();
    });

    test('3c. No messages in inbox returns empty drain', () async {
      final drained = await alice.drainOfflineInbox();
      expect(drained, 0);
    });

    test('3d. Full round-trip: offline -> drain -> reply', () async {
      alice.setOnline(false);

      final aliceReceived = <ConversationMessage>[];
      final aliceSub = alice.chatListener.incomingMessageStream.listen(
        (msg) => aliceReceived.add(msg),
      );

      // Bob sends to offline Alice
      final (r1, _) = await bob.sendMessage(alice.peerId, 'Hey Alice!');
      expect(r1, SendChatMessageResult.success);

      // Alice comes online and drains
      alice.setOnline(true);
      await alice.drainOfflineInbox();
      await Future.delayed(const Duration(milliseconds: 100));

      expect(aliceReceived.length, 1);
      expect(aliceReceived.first.text, 'Hey Alice!');

      // Alice replies
      final bobReceived = <ConversationMessage>[];
      final bobSub = bob.chatListener.incomingMessageStream.listen(
        (msg) => bobReceived.add(msg),
      );

      final (r2, _) = await alice.sendMessage(bob.peerId, 'Hey Bob!');
      expect(r2, SendChatMessageResult.success);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(bobReceived.length, 1);
      expect(bobReceived.first.text, 'Hey Bob!');

      // Both conversations have 2 messages in correct order
      final aliceConvo = await alice.messageRepo.getMessagesForContact(bob.peerId);
      expect(aliceConvo.length, 2);
      expect(aliceConvo[0].text, 'Hey Alice!');
      expect(aliceConvo[0].isIncoming, true);
      expect(aliceConvo[1].text, 'Hey Bob!');
      expect(aliceConvo[1].isIncoming, false);

      final bobConvo = await bob.messageRepo.getMessagesForContact(alice.peerId);
      expect(bobConvo.length, 2);
      expect(bobConvo[0].text, 'Hey Alice!');
      expect(bobConvo[0].isIncoming, false);
      expect(bobConvo[1].text, 'Hey Bob!');
      expect(bobConvo[1].isIncoming, true);

      await aliceSub.cancel();
      await bobSub.cancel();
    });

    test('3e. Multiple offline peers each get only their own messages',
        () async {
      // Dave sends to both Alice and Bob (both offline)
      final dave = TestUser.create(
        peerId: '12D3KooWDavePeerIdxx00000000004',
        username: 'Dave',
        network: network,
      );
      dave.addContact(alice);
      dave.addContact(bob);
      alice.addContact(dave);
      bob.addContact(dave);
      dave.start();

      alice.setOnline(false);
      bob.setOnline(false);

      await dave.sendMessage(alice.peerId, 'for-alice');
      await dave.sendMessage(bob.peerId, 'for-bob');

      // Alice drains
      final aliceReceived = <ConversationMessage>[];
      final aliceSub = alice.chatListener.incomingMessageStream.listen(
        (msg) => aliceReceived.add(msg),
      );
      alice.setOnline(true);
      await alice.drainOfflineInbox();
      await Future.delayed(const Duration(milliseconds: 100));

      // Bob drains
      final bobReceived = <ConversationMessage>[];
      final bobSub = bob.chatListener.incomingMessageStream.listen(
        (msg) => bobReceived.add(msg),
      );
      bob.setOnline(true);
      await bob.drainOfflineInbox();
      await Future.delayed(const Duration(milliseconds: 100));

      // Alice only got her message
      expect(aliceReceived.length, 1);
      expect(aliceReceived.first.text, 'for-alice');

      // Bob only got his message
      expect(bobReceived.length, 1);
      expect(bobReceived.first.text, 'for-bob');

      await aliceSub.cancel();
      await bobSub.cancel();
      dave.dispose();
    });

    test('3f. Contact request delivered via offline inbox', () async {
      bob.setOnline(false);

      // Alice stores a raw contact_request envelope in Bob's inbox
      final contactRequestJson = '{"type":"contact_request","version":"1",'
          '"payload":{"pk":"pk-alice","ns":"${alice.peerId}",'
          '"rv":"/rv/1","ts":"2026-01-01T00:00:00Z",'
          '"sig":"sig-alice","un":"Alice"}}';

      await alice.p2pService.storeInInbox(bob.peerId, contactRequestJson);

      // Bob comes online and drains
      bob.setOnline(true);
      final drained = await bob.drainOfflineInbox();
      expect(drained, 1);

      // The raw ChatMessage should arrive on Bob's messageStream
      // (the existing ChatMessageListener won't parse it as chat_message,
      //  but the raw stream should have received it)
      // Verify via messageRepo: no chat message stored (it's a contact_request)
      await Future.delayed(const Duration(milliseconds: 100));
      expect(bob.messageRepo.count, 0);
    });

    test(
        '3g. Sender status is delivered immediately on inbox store and stays delivered after receipt',
        () async {
      bob.setOnline(false);

      final (result, sent) = await alice.sendMessage(bob.peerId, 'offline ping');
      expect(result, SendChatMessageResult.success);
      expect(sent, isNotNull);
      expect(sent!.status, 'delivered');

      var aliceConvo = await alice.messageRepo.getMessagesForContact(bob.peerId);
      expect(aliceConvo, hasLength(1));
      expect(aliceConvo.first.status, 'delivered');

      bob.setOnline(true);
      final drained = await bob.drainOfflineInbox();
      expect(drained, 1);

      await Future.delayed(const Duration(milliseconds: 150));

      aliceConvo = await alice.messageRepo.getMessagesForContact(bob.peerId);
      expect(aliceConvo, hasLength(1));
      expect(aliceConvo.first.id, sent.id);
      expect(aliceConvo.first.status, 'delivered');
    });
  });
}
