import 'dart:io';

import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/application/block_contact_use_case.dart';
import 'package:flutter_app/features/contacts/application/unblock_contact_use_case.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/reaction_listener.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/fake_app_visibility.dart';
import '../../../shared/fakes/fake_notification_service.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../shared/fakes/test_user.dart';

Future<void> _until(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('The expected ingress/notification boundary was not reached.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

void main() {
  test('DC-016 block suppresses text/media/reactions and alerts, permits '
      'authored stored-message deletion, then admits fresh delivery', () async {
    final network = FakeP2PNetwork();
    final aliceMedia = InMemoryMediaAttachmentRepository();
    final bobMedia = InMemoryMediaAttachmentRepository();
    final alice = TestUser.create(
      peerId: '12D3KooWAliceIngressPrivacy01',
      username: 'Alice',
      network: network,
      mediaAttachmentRepo: aliceMedia,
      withReactions: true,
      withMessageDeletion: true,
    );
    final bob = TestUser.create(
      peerId: '12D3KooWBobIngressPrivacy0002',
      username: 'Bob',
      network: network,
      mediaAttachmentRepo: bobMedia,
      withReactions: true,
      withMessageDeletion: true,
    );
    aliceMedia.enableDirectMediaInboxCustodyForTest(alice.messageRepo);
    alice.addContact(bob);
    bob.addContact(alice);
    final temporary = await Directory.systemTemp.createTemp('dc016-ingress-');
    final gate = RecentRemoteNotificationGate(
      filePath: '${temporary.path}/announcements.json',
    );
    final notifications = FakeNotificationService();
    final events = <String>[];
    var reactionNotificationResolutions = 0;
    // Reuse the real two-peer sender/router/deletion fixture, but compose the
    // recipient chat listener with a real notification sink. The helper's
    // default listeners intentionally do not publish notifications.
    final chat = ChatMessageListener(
      chatMessageStream: bob.router!.chatMessageStream,
      messageRepo: bob.messageRepo,
      contactRepo: bob.contactRepo,
      mediaAttachmentRepo: bobMedia,
      bridge: bob.bridge,
      getOwnMlKemSecretKey: () async => 'fixture-recipient-secret',
      notificationService: notifications,
      appVisibility: FixedAppVisibility(),
      remoteNotificationGate: gate,
      backgroundNotificationDuplicateGuardDelay: Duration.zero,
    );
    final reactions = ReactionListener(
      reactionStream: bob.router!.reactionStream,
      messageRepo: bob.messageRepo,
      reactionRepo: bob.reactionRepo!,
      contactRepo: bob.contactRepo,
      bridge: bob.bridge,
      getOwnMlKemSecretKey: () async => 'fixture-recipient-secret',
      resolveNotificationDependencies: (_) {
        reactionNotificationResolutions++;
        return null;
      },
    );
    final received = <String>[];
    final subscription = chat.incomingMessageStream.listen(
      (message) => received.add(message.id),
    );
    debugSetFlowEventSink((event) => events.add(event['event'] as String));
    alice.start();
    bob.router!.start();
    bob.messageDeletionListener!.start();
    // The notification sink records a show before its dedup marker is written.
    // Retain the real handler futures so teardown can await that final IO.
    final chatIngress = <Future<ChatMessageProcessOutcome>>[];
    final chatInput = bob.router!.chatMessageStream.listen((message) {
      chatIngress.add(chat.processIncomingMessage(message));
    });
    reactions.start();
    try {
      final (initialResult, original) = await alice.sendMessage(
        bob.peerId,
        'Authored before blocking',
      );
      expect(initialResult, SendChatMessageResult.success);
      await _until(() => received.contains(original!.id));
      await _until(() => notifications.shown.length == 1);
      final parentReceived = alice.chatListener.incomingMessageStream.first;
      final (replyResult, parent) = await bob.sendMessage(
        alice.peerId,
        'An existing reaction target',
      );
      expect(replyResult, SendChatMessageResult.success);
      expect(
        (await parentReceived.timeout(const Duration(seconds: 3))).id,
        parent!.id,
      );

      await blockContact(contactRepo: bob.contactRepo, peerId: alice.peerId);
      final rowsBefore = await bob.loadConversationWith(alice.peerId);
      final streamCount = received.length;
      final (_, blockedText) = await alice.sendMessage(bob.peerId, 'Blocked');
      final (mediaResult, blockedMedia) = await alice
          .sendMessageWithMedia(bob.peerId, 'Blocked photo', [
            MediaAttachment(
              id: 'blocked-photo-blob',
              messageId: '',
              mime: 'image/jpeg',
              size: 128,
              mediaType: 'image',
              localPath: '/tmp/fixture-blocked-photo.jpg',
              downloadStatus: 'done',
              createdAt: DateTime.now().toUtc().toIso8601String(),
              contentHash: List.filled(64, 'a').join(),
              encryptionKeyBase64: 'fixture-blob-key',
              encryptionNonce: 'fixture-blob-nonce',
              encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            ),
          ]);
      expect(mediaResult, SendChatMessageResult.success);
      expect(blockedMedia, isNotNull);
      await alice.sendReaction(bob.peerId, parent.id, '👍');
      // Wait for positive rejection witnesses, rather than interpreting an
      // arbitrary quiet sleep as proof the router consumed the blocked inputs.
      await _until(
        () =>
            events
                    .where((event) => event == 'CHAT_LISTENER_BLOCKED_REJECT')
                    .length ==
                2 &&
            events.contains('REACTION_LISTENER_BLOCKED_REJECT'),
      );
      final blockedRows = await bob.loadConversationWith(alice.peerId);
      expect(blockedRows.map((row) => row.id), rowsBefore.map((row) => row.id));
      expect(blockedRows.any((row) => row.id == blockedText!.id), isFalse);
      expect(blockedRows.any((row) => row.id == blockedMedia!.id), isFalse);
      expect(
        bobMedia.count,
        0,
        reason: 'Blocked media must not leave an orphan.',
      );
      expect(
        await bob.reactionRepo!.getReactionsForMessage(parent.id),
        isEmpty,
      );
      expect(received, hasLength(streamCount));
      expect(notifications.shown, hasLength(1));
      expect(notifications.shownGeneric, isEmpty);
      expect(
        reactionNotificationResolutions,
        0,
        reason: 'Blocked reaction must not reach notification admission.',
      );

      final deletion =
          bob.messageDeletionListener!.incomingDeletionStream.first;
      final (deleteResult, _) = await alice.deleteMessageForEveryone(original!);
      expect(deleteResult, SendChatMessageResult.success);
      final tombstone = await deletion.timeout(const Duration(seconds: 3));
      expect(tombstone.id, original.id);
      expect(tombstone.isDeleted, isTrue);
      expect(tombstone.deletedByPeerId, alice.peerId);
      expect(notifications.shown, hasLength(1));

      await unblockContact(contactRepo: bob.contactRepo, peerId: alice.peerId);
      final (freshResult, fresh) = await alice.sendMessage(bob.peerId, 'Fresh');
      expect(freshResult, SendChatMessageResult.success);
      await _until(() => received.contains(fresh!.id));
      await _until(() => notifications.shown.length == 2);
      final reaction = reactions.incomingReactionStream.first;
      await alice.sendReaction(bob.peerId, parent.id, '✅');
      final admitted = await reaction.timeout(const Duration(seconds: 3));
      expect(admitted.messageId, parent.id);
      expect(admitted.emoji, '✅');
      expect(reactionNotificationResolutions, 1);
      final finalRows = await bob.loadConversationWith(alice.peerId);
      expect(
        finalRows.where((row) => row.id == original.id).single.isDeleted,
        isTrue,
      );
      expect(finalRows.where((row) => row.id == fresh!.id), hasLength(1));
      expect(bobMedia.count, 0);
    } finally {
      await chatInput.cancel();
      await Future.wait(chatIngress);
      debugSetFlowEventSink(null);
      await subscription.cancel();
      chat.dispose();
      reactions.dispose();
      alice.dispose();
      bob.dispose();
      await gate.clear();
      await temporary.delete(recursive: true);
    }
  });
}
