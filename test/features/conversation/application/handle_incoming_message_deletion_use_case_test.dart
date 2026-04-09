import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/handle_incoming_message_deletion_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_deletion_payload.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../domain/repositories/fake_media_attachment_repository.dart';
import '../domain/repositories/fake_message_repository.dart';
import '../domain/repositories/fake_reaction_repository.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';

void main() {
  late FakeMessageRepository messageRepo;
  late FakeContactRepository contactRepo;
  late FakeReactionRepository reactionRepo;
  late FakeMediaAttachmentRepository mediaAttachmentRepo;
  late FakeMediaFileManager mediaFileManager;

  ContactModel makeContact(String peerId) {
    return ContactModel(
      peerId: peerId,
      publicKey: 'pk-$peerId',
      rendezvous: '/dns4/relay/tcp/443/p2p/relay',
      username: 'User $peerId',
      signature: 'sig-$peerId',
      scannedAt: '2026-03-31T09:00:00.000Z',
      mlKemPublicKey: 'mlkem-$peerId',
    );
  }

  ConversationMessage makeMessage({
    required String id,
    required String contactPeerId,
    required String senderPeerId,
    String text = 'Hello',
    bool isIncoming = true,
    String status = 'delivered',
  }) {
    return ConversationMessage(
      id: id,
      contactPeerId: contactPeerId,
      senderPeerId: senderPeerId,
      text: text,
      timestamp: '2026-03-31T10:00:00.000Z',
      status: status,
      isIncoming: isIncoming,
      createdAt: '2026-03-31T10:00:01.000Z',
    );
  }

  MediaAttachment makeAttachment({
    required String id,
    required String messageId,
    required String localPath,
    String downloadStatus = 'done',
  }) {
    return MediaAttachment(
      id: id,
      messageId: messageId,
      mime: 'image/jpeg',
      size: 1234,
      mediaType: 'image',
      localPath: localPath,
      downloadStatus: downloadStatus,
      createdAt: '2026-03-31T10:00:02.000Z',
    );
  }

  setUp(() {
    messageRepo = FakeMessageRepository();
    contactRepo = FakeContactRepository();
    reactionRepo = FakeReactionRepository();
    mediaAttachmentRepo = FakeMediaAttachmentRepository();
    mediaFileManager = FakeMediaFileManager();
  });

  group('handleIncomingMessageDeletion', () {
    test(
      'applies an authorized tombstone and cleans up local artifacts',
      () async {
        contactRepo.seed([makeContact('peer-alice')]);

        final original = makeMessage(
          id: 'msg-1',
          contactPeerId: 'peer-alice',
          senderPeerId: 'peer-alice',
        );
        messageRepo.seed([original]);
        await reactionRepo.saveReaction(
          const MessageReaction(
            id: 'reaction-1',
            messageId: 'msg-1',
            emoji: '👍',
            senderPeerId: 'peer-bob',
            timestamp: '2026-03-31T10:01:00.000Z',
            createdAt: '2026-03-31T10:01:00.000Z',
          ),
        );
        mediaAttachmentRepo.seed([
          makeAttachment(
            id: 'att-owned',
            messageId: 'msg-1',
            localPath: 'media/msg-1/photo.jpg',
          ),
          makeAttachment(
            id: 'att-external',
            messageId: 'msg-1',
            localPath: '/tmp/external/photo.jpg',
          ),
        ]);

        final payload = MessageDeletionPayload(
          messageId: 'msg-1',
          senderPeerId: 'peer-alice',
          timestamp: '2026-03-31T10:05:00.000Z',
        );
        final encryptedEnvelope = MessageDeletionPayload.buildEncryptedEnvelope(
          senderPeerId: 'peer-alice',
          kem: 'fake-kem',
          ciphertext: payload.toInnerJson(),
          nonce: 'fake-nonce',
        );

        final (result, tombstone) = await handleIncomingMessageDeletion(
          message: ChatMessage(
            from: 'peer-alice',
            to: 'peer-bob',
            content: encryptedEnvelope,
            timestamp: '2026-03-31T10:05:00.000Z',
            isIncoming: true,
          ),
          messageRepo: messageRepo,
          contactRepo: contactRepo,
          reactionRepo: reactionRepo,
          mediaAttachmentRepo: mediaAttachmentRepo,
          mediaFileManager: mediaFileManager,
          bridge: PassthroughCryptoBridge(),
          ownMlKemSecretKey: 'self-secret',
        );

        expect(result, HandleMessageDeletionResult.success);
        expect(tombstone, isNotNull);
        expect(tombstone!.id, 'msg-1');
        expect(tombstone.text, isEmpty);
        expect(tombstone.isDeleted, isTrue);
        expect(tombstone.isHidden, isFalse);
        expect(tombstone.deletedAt, '2026-03-31T10:05:00.000Z');
        expect(tombstone.deletedByPeerId, 'peer-alice');

        final stored = await messageRepo.getMessage('msg-1');
        expect(stored, isNotNull);
        expect(stored!.isDeleted, isTrue);
        expect(
          await mediaAttachmentRepo.getAttachmentsForMessage('msg-1'),
          isEmpty,
        );
        expect(await reactionRepo.getReactionsForMessage('msg-1'), isEmpty);
        expect(
          mediaFileManager.deletedFilePaths,
          contains(endsWith('test_docs/media/msg-1/photo.jpg')),
        );
        expect(
          mediaFileManager.deletedFilePaths,
          isNot(contains('/tmp/external/photo.jpg')),
        );
      },
    );

    test('rejects spoofed delete requests for another sender', () async {
      contactRepo.seed([makeContact('peer-alice')]);
      messageRepo.seed([
        makeMessage(
          id: 'msg-1',
          contactPeerId: 'peer-alice',
          senderPeerId: 'peer-charlie',
        ),
      ]);

      final payload = MessageDeletionPayload(
        messageId: 'msg-1',
        senderPeerId: 'peer-alice',
        timestamp: '2026-03-31T10:05:00.000Z',
      );

      final (result, tombstone) = await handleIncomingMessageDeletion(
        message: ChatMessage(
          from: 'peer-alice',
          to: 'peer-bob',
          content: payload.toJson(),
          timestamp: '2026-03-31T10:05:00.000Z',
          isIncoming: true,
        ),
        messageRepo: messageRepo,
        contactRepo: contactRepo,
        reactionRepo: reactionRepo,
        mediaAttachmentRepo: mediaAttachmentRepo,
        mediaFileManager: mediaFileManager,
      );

      expect(result, HandleMessageDeletionResult.unauthorized);
      expect(tombstone, isNull);
      final stored = await messageRepo.getMessage('msg-1');
      expect(stored, isNotNull);
      expect(stored!.isDeleted, isFalse);
    });

    test('ignores delete requests for missing messages', () async {
      contactRepo.seed([makeContact('peer-alice')]);

      final payload = MessageDeletionPayload(
        messageId: 'missing-message',
        senderPeerId: 'peer-alice',
        timestamp: '2026-03-31T10:05:00.000Z',
      );

      final (result, tombstone) = await handleIncomingMessageDeletion(
        message: ChatMessage(
          from: 'peer-alice',
          to: 'peer-bob',
          content: payload.toJson(),
          timestamp: '2026-03-31T10:05:00.000Z',
          isIncoming: true,
        ),
        messageRepo: messageRepo,
        contactRepo: contactRepo,
      );

      expect(result, HandleMessageDeletionResult.ignoredMissingMessage);
      expect(tombstone, isNull);
    });
  });
}
