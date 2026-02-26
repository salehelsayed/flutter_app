/// Integration test: Voice message send/receive between two users.
///
/// Verifies that voice messages (audio attachments) propagate correctly
/// through the send/receive pipeline:
///   Alice records voice → sends with audio MediaAttachment → Bob receives & persists
///
/// Uses the same TestUser / FakeP2PNetwork infrastructure as text message tests.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../shared/fakes/test_user.dart';

void main() {
  late FakeP2PNetwork network;
  late TestUser alice;
  late TestUser bob;
  late InMemoryMediaAttachmentRepository aliceMediaRepo;
  late InMemoryMediaAttachmentRepository bobMediaRepo;

  /// Helper to create an audio MediaAttachment (simulating what uploadMedia returns).
  MediaAttachment makeAudioAttachment({
    required String id,
    int durationMs = 3000,
    int size = 48000,
    String mime = 'audio/mp4',
  }) {
    return MediaAttachment(
      id: id,
      messageId: '', // set by sendChatMessage
      mime: mime,
      size: size,
      mediaType: 'audio',
      durationMs: durationMs,
      downloadStatus: 'done',
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

  group('Voice message send/receive', () {
    test('Alice sends voice message — Bob receives with correct audio metadata',
        () async {
      final attachment = makeAudioAttachment(
        id: 'voice-blob-001',
        durationMs: 5200,
        size: 83200,
      );

      final bobReceived = <ConversationMessage>[];
      final sub = bob.chatListener.incomingMessageStream.listen(
        (msg) => bobReceived.add(msg),
      );

      final (result, sentMsg) = await alice.sendMessageWithMedia(
        bob.peerId,
        '', // voice-only, no text
        [attachment],
      );

      expect(result, SendChatMessageResult.success);
      expect(sentMsg, isNotNull);

      // Alice's media repo has the attachment
      expect(aliceMediaRepo.count, 1);

      await Future.delayed(const Duration(milliseconds: 100));

      // Bob received the message
      expect(bobReceived.length, 1);

      // Bob's media repo has the audio attachment with correct metadata
      expect(bobMediaRepo.count, 1);
      final bobAttachments = await bobMediaRepo.getPendingDownloads();
      expect(bobAttachments.length, 1);
      expect(bobAttachments.first.mime, 'audio/mp4');
      expect(bobAttachments.first.mediaType, 'audio');
      expect(bobAttachments.first.durationMs, 5200);
      expect(bobAttachments.first.size, 83200);

      await sub.cancel();
    });

    test('Voice message appears in Alice message list with mediaType audio',
        () async {
      final attachment = makeAudioAttachment(id: 'voice-blob-002');

      final (result, sentMsg) = await alice.sendMessageWithMedia(
        bob.peerId,
        '',
        [attachment],
      );

      expect(result, SendChatMessageResult.success);

      // Load Alice's conversation
      final convo = await alice.loadConversationWith(bob.peerId);
      expect(convo.length, 1);
      expect(convo.first.isIncoming, false);

      // Verify media attachment on the stored message
      final attachments = await aliceMediaRepo.getAttachmentsForMessage(
        convo.first.id,
      );
      expect(attachments.length, 1);
      expect(attachments.first.mediaType, 'audio');
      expect(attachments.first.mime, 'audio/mp4');
    });

    test('Voice message appears in Bob pending downloads', () async {
      final attachment = makeAudioAttachment(
        id: 'voice-blob-003',
        size: 64000,
      );

      await alice.sendMessageWithMedia(bob.peerId, '', [attachment]);
      await Future.delayed(const Duration(milliseconds: 100));

      final pending = await bobMediaRepo.getPendingDownloads();
      expect(pending.length, 1);
      expect(pending.first.downloadStatus, 'pending');
      expect(pending.first.mediaType, 'audio');
    });

    test('Bob media attachment has correct metadata (mime, size, durationMs)',
        () async {
      final attachment = makeAudioAttachment(
        id: 'voice-blob-004',
        durationMs: 12500,
        size: 200000,
        mime: 'audio/mp4',
      );

      await alice.sendMessageWithMedia(bob.peerId, '', [attachment]);
      await Future.delayed(const Duration(milliseconds: 100));

      final bobAttachments = await bobMediaRepo.getPendingDownloads();
      expect(bobAttachments.length, 1);

      final a = bobAttachments.first;
      expect(a.mime, 'audio/mp4');
      expect(a.size, 200000);
      expect(a.durationMs, 12500);
      expect(a.mediaType, 'audio');
      expect(a.localPath, isNull); // not yet downloaded
    });
  });

  group('Voice message with caption', () {
    test('Alice sends voice + text caption — Bob receives both', () async {
      final attachment = makeAudioAttachment(id: 'voice-caption-001');

      final bobReceived = <ConversationMessage>[];
      final sub = bob.chatListener.incomingMessageStream.listen(
        (msg) => bobReceived.add(msg),
      );

      final (result, _) = await alice.sendMessageWithMedia(
        bob.peerId,
        'Listen to this!',
        [attachment],
      );

      expect(result, SendChatMessageResult.success);
      await Future.delayed(const Duration(milliseconds: 100));

      // Bob received the message with text and audio
      expect(bobReceived.length, 1);
      expect(bobReceived.first.text, 'Listen to this!');

      // Audio attachment is present
      final bobAttachments = await bobMediaRepo.getPendingDownloads();
      expect(bobAttachments.length, 1);
      expect(bobAttachments.first.mediaType, 'audio');

      await sub.cancel();
    });

    test('Caption text preserved alongside audio attachment', () async {
      final attachment = makeAudioAttachment(id: 'voice-caption-002');

      await alice.sendMessageWithMedia(
        bob.peerId,
        'Important voice note',
        [attachment],
      );
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify Alice's conversation has text
      final aliceConvo = await alice.loadConversationWith(bob.peerId);
      expect(aliceConvo.length, 1);
      expect(aliceConvo.first.text, 'Important voice note');

      // Verify Bob's conversation has text
      final bobConvo = await bob.loadConversationWith(alice.peerId);
      expect(bobConvo.length, 1);
      expect(bobConvo.first.text, 'Important voice note');
      expect(bobConvo.first.isIncoming, true);

      // Both have the audio attachment
      expect(aliceMediaRepo.count, 1);
      expect(bobMediaRepo.count, 1);
    });
  });

  group('Voice message edge cases', () {
    test('Voice message via inbox fallback — delivered correctly', () async {
      // Create an offline user
      final offlineUser = TestUser.create(
        peerId: '12D3KooWOfflineUser0000000004',
        username: 'Offline',
        network: network,
        mediaAttachmentRepo: InMemoryMediaAttachmentRepository(),
      );
      alice.addContact(offlineUser);
      offlineUser.addContact(alice);
      offlineUser.start();
      offlineUser.setOnline(false);

      final offlineReceived =
          offlineUser.chatListener.incomingMessageStream.first;

      final attachment = makeAudioAttachment(
        id: 'voice-inbox-001',
        durationMs: 4000,
      );

      final (result, msg) = await alice.sendMessageWithMedia(
        offlineUser.peerId,
        '',
        [attachment],
      );

      // Falls back to inbox storage
      expect(result, SendChatMessageResult.success);
      expect(msg, isNotNull);
      expect(msg!.status, 'delivered');

      // Peer comes online and drains inbox
      offlineUser.setOnline(true);
      final drained = await offlineUser.drainOfflineInbox();
      expect(drained, 1);

      final delivered = await offlineReceived.timeout(
        const Duration(seconds: 2),
        onTimeout: () =>
            throw StateError('Offline peer never received voice message'),
      );
      expect(delivered.isIncoming, true);
      expect(delivered.senderPeerId, alice.peerId);

      offlineUser.dispose();
    });

    test('Voice-only message (no text, audio attachment only) round-trips',
        () async {
      final attachment = makeAudioAttachment(id: 'voice-only-001');

      final bobReceived = <ConversationMessage>[];
      final sub = bob.chatListener.incomingMessageStream.listen(
        (msg) => bobReceived.add(msg),
      );

      final (result, msg) = await alice.sendMessageWithMedia(
        bob.peerId,
        '', // no text
        [attachment],
      );

      expect(result, SendChatMessageResult.success);
      expect(msg, isNotNull);
      expect(msg!.text, isEmpty);

      await Future.delayed(const Duration(milliseconds: 100));

      expect(bobReceived.length, 1);
      expect(bobReceived.first.text, isEmpty);

      // Audio attachment propagated
      expect(bobMediaRepo.count, 1);
      final bobAtt = await bobMediaRepo.getPendingDownloads();
      expect(bobAtt.first.mediaType, 'audio');

      await sub.cancel();
    });
  });
}
