// Integration test: Media attachment send/receive.
//
// Verifies media metadata propagation through the send/receive path,
// persistence in MediaAttachmentRepository, and wire format.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/application/handle_incoming_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../shared/fakes/in_memory_message_repository.dart';
import '../../../shared/fakes/test_user.dart';

void main() {
  late FakeP2PNetwork network;
  late TestUser alice;
  late TestUser bob;
  late InMemoryMediaAttachmentRepository aliceMediaRepo;
  late InMemoryMediaAttachmentRepository bobMediaRepo;

  MediaAttachment makeAttachment({
    required String id,
    String mime = 'image/jpeg',
    int size = 2048,
    String mediaType = 'image',
  }) {
    return MediaAttachment(
      id: id,
      messageId: '', // will be set by send
      mime: mime,
      size: size,
      mediaType: mediaType,
      downloadStatus: 'pending',
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  setUp(() {
    network = FakeP2PNetwork();
    aliceMediaRepo = InMemoryMediaAttachmentRepository();
    bobMediaRepo = InMemoryMediaAttachmentRepository();

    alice = TestUser.create(
      peerId: '12D3KooWAlicePeerId00000000001',
      username: 'Alice',
      network: network,
      mediaAttachmentRepo: aliceMediaRepo,
    );
    bob = TestUser.create(
      peerId: '12D3KooWBobPeerIdxxx00000000002',
      username: 'Bob',
      network: network,
      mediaAttachmentRepo: bobMediaRepo,
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

  group('Media attachment flow', () {
    test(
      '6a. Send message with media — wire envelope includes metadata',
      () async {
        final attachment = makeAttachment(id: 'blob-001');

        final bobReceived = <ConversationMessage>[];
        final sub = bob.chatListener.incomingMessageStream.listen(
          (msg) => bobReceived.add(msg),
        );

        final (result, _) = await alice.sendMessageWithMedia(
          bob.peerId,
          'Check this photo!',
          [attachment],
        );
        expect(result, SendChatMessageResult.success);

        // Verify attachment saved in Alice's repo
        // The attachment is persisted with the message ID assigned by sendChatMessage
        expect(aliceMediaRepo.count, 1);

        // Wait for Bob to receive
        await Future.delayed(const Duration(milliseconds: 100));

        expect(bobReceived.length, 1);

        // Parse Bob's received raw message to check wire format
        // (the ChatMessageListener ingests the raw ChatMessage via
        //  handleIncomingChatMessage which parses the envelope)
        // Verify Bob's media repo has the attachment
        expect(bobMediaRepo.count, 1);
        final bobAttachments = await bobMediaRepo.getPendingDownloads();
        expect(bobAttachments.length, 1);
        expect(bobAttachments.first.mime, 'image/jpeg');
        expect(bobAttachments.first.size, 2048);
        expect(bobAttachments.first.mediaType, 'image');

        await sub.cancel();
      },
    );

    test(
      'successful outgoing media send replaces stale upload_pending placeholder rows',
      () async {
        const messageId = 'msg-stable-flow-001';

        await aliceMediaRepo.saveAttachment(
          MediaAttachment(
            id: 'placeholder-upload-pending',
            messageId: messageId,
            mime: 'image/jpeg',
            size: 0,
            mediaType: 'image',
            localPath: '/tmp/pending.jpg',
            downloadStatus: 'upload_pending',
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );

        final (result, _) = await sendChatMessage(
          p2pService: alice.p2pService,
          messageRepo: alice.messageRepo,
          targetPeerId: bob.peerId,
          text: 'Stable attachment cleanup',
          senderPeerId: alice.peerId,
          senderUsername: alice.username,
          messageId: messageId,
          timestamp: DateTime.now().toUtc().toIso8601String(),
          mediaAttachments: [
            MediaAttachment(
              id: 'uploaded-final-id',
              messageId: '',
              mime: 'image/jpeg',
              size: 2048,
              mediaType: 'image',
              localPath: '/tmp/final.jpg',
              downloadStatus: 'done',
              createdAt: DateTime.now().toUtc().toIso8601String(),
            ),
          ],
          mediaAttachmentRepo: aliceMediaRepo,
        );

        expect(result, SendChatMessageResult.success);
        final attachments = await aliceMediaRepo.getAttachmentsForMessage(
          messageId,
        );
        expect(attachments.length, 1);
        expect(attachments.single.id, 'uploaded-final-id');
        expect(attachments.single.downloadStatus, 'done');
        expect(await aliceMediaRepo.getUploadPendingAttachments(), isEmpty);
      },
    );

    test(
      '6b. Receive message with media — metadata persisted to repo',
      () async {
        // Manually inject a chat_message with media array
        final mediaJson = {
          'id': 'blob-100',
          'mime': 'video/mp4',
          'size': 10240,
          'mediaType': 'video',
          'width': 1920,
          'height': 1080,
          'durationMs': 30000,
        };

        final envelope = jsonEncode({
          'type': 'chat_message',
          'version': '1',
          'payload': {
            'id': 'msg-with-media-001',
            'text': 'Video message',
            'senderPeerId': alice.peerId,
            'senderUsername': 'Alice',
            'timestamp': DateTime.now().toUtc().toIso8601String(),
            'media': [mediaJson],
          },
        });

        // Use handleIncomingChatMessage directly
        final msgRepo = InMemoryMessageRepository();
        final contactRepo = InMemoryContactRepository();
        contactRepo.addTestContact(
          ContactModel(
            peerId: alice.peerId,
            publicKey: 'pk',
            rendezvous: '/rv',
            username: 'Alice',
            signature: 'sig',
            scannedAt: '2026-01-01T00:00:00Z',
          ),
        );
        final mediaRepo = InMemoryMediaAttachmentRepository();

        final (result, msg, _) = await handleIncomingChatMessage(
          message: ChatMessage(
            from: alice.peerId,
            to: 'own',
            content: envelope,
            timestamp: DateTime.now().toUtc().toIso8601String(),
            isIncoming: true,
          ),
          messageRepo: msgRepo,
          contactRepo: contactRepo,
          mediaAttachmentRepo: mediaRepo,
        );

        expect(result, HandleChatMessageResult.chatMessage);
        expect(msg, isNotNull);

        // Verify media persisted
        final attachments = await mediaRepo.getAttachmentsForMessage(
          'msg-with-media-001',
        );
        expect(attachments.length, 1);
        expect(attachments.first.id, 'blob-100');
        expect(attachments.first.mime, 'video/mp4');
        expect(attachments.first.size, 10240);
        expect(attachments.first.mediaType, 'video');
        expect(attachments.first.downloadStatus, 'pending');
      },
    );

    test('6c. Multiple media attachments on single message', () async {
      final attachments = [
        makeAttachment(id: 'blob-img', mime: 'image/png', mediaType: 'image'),
        makeAttachment(
          id: 'blob-vid',
          mime: 'video/mp4',
          size: 5000,
          mediaType: 'video',
        ),
        makeAttachment(
          id: 'blob-aud',
          mime: 'audio/mpeg',
          size: 3000,
          mediaType: 'audio',
        ),
      ];

      final bobReceived = <ConversationMessage>[];
      final sub = bob.chatListener.incomingMessageStream.listen(
        (msg) => bobReceived.add(msg),
      );

      final (result, _) = await alice.sendMessageWithMedia(
        bob.peerId,
        'Multi-media message',
        attachments,
      );
      expect(result, SendChatMessageResult.success);
      await Future.delayed(const Duration(milliseconds: 100));

      // Alice's repo has 3 attachments
      expect(aliceMediaRepo.count, 3);

      // Bob received and persisted 3
      expect(bobMediaRepo.count, 3);
      final bobPending = await bobMediaRepo.getPendingDownloads();
      expect(bobPending.length, 3);

      final mimeTypes = bobPending.map((a) => a.mime).toSet();
      expect(mimeTypes, containsAll(['image/png', 'video/mp4', 'audio/mpeg']));

      await sub.cancel();
    });

    test('6d. Message with empty text but media is valid', () async {
      final attachment = makeAttachment(id: 'blob-002');

      final (result, msg) = await alice.sendMessageWithMedia(
        bob.peerId,
        '', // empty text
        [attachment],
      );

      expect(result, SendChatMessageResult.success);
      expect(msg, isNotNull);
    });

    test('6e. Message with no media and empty text is rejected', () async {
      final (result, msg) = await sendChatMessage(
        p2pService: alice.p2pService,
        messageRepo: alice.messageRepo,
        targetPeerId: bob.peerId,
        text: '',
        senderPeerId: alice.peerId,
        senderUsername: alice.username,
        mediaAttachments: null,
      );

      expect(result, SendChatMessageResult.invalidMessage);
      expect(msg, isNull);
    });

    test('6f. Voice-only message (no text, audio attachment only)', () async {
      final audioAttachment = makeAttachment(
        id: 'blob-audio-001',
        mime: 'audio/mp4',
        size: 48000,
        mediaType: 'audio',
      );

      final bobReceived = <ConversationMessage>[];
      final sub = bob.chatListener.incomingMessageStream.listen(
        (msg) => bobReceived.add(msg),
      );

      final (result, msg) = await alice.sendMessageWithMedia(
        bob.peerId,
        '', // no text — voice only
        [audioAttachment],
      );

      expect(result, SendChatMessageResult.success);
      expect(msg, isNotNull);
      expect(msg!.text, isEmpty);

      await Future.delayed(const Duration(milliseconds: 100));

      expect(bobReceived.length, 1);
      expect(bobMediaRepo.count, 1);

      final pending = await bobMediaRepo.getPendingDownloads();
      expect(pending.first.mime, 'audio/mp4');
      expect(pending.first.mediaType, 'audio');
      expect(pending.first.size, 48000);

      await sub.cancel();
    });

    test('6g. Mixed media — image + audio in single message', () async {
      final attachments = [
        makeAttachment(
          id: 'blob-img-mix',
          mime: 'image/jpeg',
          size: 2048,
          mediaType: 'image',
        ),
        makeAttachment(
          id: 'blob-aud-mix',
          mime: 'audio/mp4',
          size: 48000,
          mediaType: 'audio',
        ),
      ];

      final bobReceived = <ConversationMessage>[];
      final sub = bob.chatListener.incomingMessageStream.listen(
        (msg) => bobReceived.add(msg),
      );

      final (result, _) = await alice.sendMessageWithMedia(
        bob.peerId,
        'Photo with voice note',
        attachments,
      );

      expect(result, SendChatMessageResult.success);
      await Future.delayed(const Duration(milliseconds: 100));

      // Both repos have 2 attachments
      expect(aliceMediaRepo.count, 2);
      expect(bobMediaRepo.count, 2);

      // Bob has both types
      final bobPending = await bobMediaRepo.getPendingDownloads();
      final mimeTypes = bobPending.map((a) => a.mime).toSet();
      expect(mimeTypes, containsAll(['image/jpeg', 'audio/mp4']));

      final mediaTypes = bobPending.map((a) => a.mediaType).toSet();
      expect(mediaTypes, containsAll(['image', 'audio']));

      await sub.cancel();
    });

    test('6h. MediaAttachment.fromJson round-trip', () {
      final original = MediaAttachment(
        id: 'att-001',
        messageId: 'msg-001',
        mime: 'image/jpeg',
        size: 4096,
        mediaType: 'image',
        width: 800,
        height: 600,
        downloadStatus: 'done',
        createdAt: '2026-01-01T00:00:00Z',
      );

      final json = original.toJson();
      final restored = MediaAttachment.fromJson(json);

      expect(restored.id, 'att-001');
      expect(restored.mime, 'image/jpeg');
      expect(restored.size, 4096);
      expect(restored.mediaType, 'image');
      expect(restored.width, 800);
      expect(restored.height, 600);
      // fromJson always sets downloadStatus to 'pending'
      expect(restored.downloadStatus, 'pending');
    });
  });
}
