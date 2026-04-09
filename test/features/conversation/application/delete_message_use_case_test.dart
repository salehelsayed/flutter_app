import 'package:flutter_app/features/conversation/application/delete_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../domain/repositories/fake_media_attachment_repository.dart';
import '../domain/repositories/fake_message_repository.dart';
import '../domain/repositories/fake_reaction_repository.dart';

void main() {
  late FakeMessageRepository messageRepo;
  late FakeReactionRepository reactionRepo;
  late FakeMediaAttachmentRepository mediaAttachmentRepo;
  late FakeMediaFileManager mediaFileManager;

  ConversationMessage makeMessage({
    String id = 'msg-1',
    String contactPeerId = 'peer-bob',
    String senderPeerId = 'peer-alice',
    String text = 'Hello Bob',
    String status = 'delivered',
    bool isIncoming = false,
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
      size: 2048,
      mediaType: 'image',
      localPath: localPath,
      downloadStatus: downloadStatus,
      createdAt: '2026-03-31T10:00:02.000Z',
    );
  }

  setUp(() {
    messageRepo = FakeMessageRepository();
    reactionRepo = FakeReactionRepository();
    mediaAttachmentRepo = FakeMediaAttachmentRepository();
    mediaFileManager = FakeMediaFileManager();
  });

  group('delete_message_use_case', () {
    test(
      'deleteMessageForMe hard-deletes the row after local cleanup',
      () async {
        final message = makeMessage();
        messageRepo.seed([message]);
        mediaAttachmentRepo.seed([
          makeAttachment(
            id: 'att-owned',
            messageId: message.id,
            localPath: 'media/msg-1/photo.jpg',
          ),
          makeAttachment(
            id: 'att-external',
            messageId: message.id,
            localPath: '/tmp/external/photo.jpg',
          ),
        ]);
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

        final count = await deleteMessageForMe(
          message: message,
          messageRepo: messageRepo,
          reactionRepo: reactionRepo,
          mediaAttachmentRepo: mediaAttachmentRepo,
          mediaFileManager: mediaFileManager,
        );

        expect(count, 1);
        expect(await messageRepo.getMessage(message.id), isNull);
        expect(
          await mediaAttachmentRepo.getAttachmentsForMessage(message.id),
          isEmpty,
        );
        expect(await reactionRepo.getReactionsForMessage(message.id), isEmpty);
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

    test(
      'deleteMessageForEveryone keeps a sender-visible failed tombstone on send failure',
      () async {
        final original = makeMessage();
        messageRepo.seed([original]);

        final network = FakeP2PNetwork()..inboxDisabled = true;
        final p2pService = FakeP2PService(
          peerId: 'peer-alice',
          network: network,
        );

        final (result, tombstone) = await deleteMessageForEveryone(
          p2pService: p2pService,
          messageRepo: messageRepo,
          originalMessage: original,
        );

        expect(result, SendChatMessageResult.peerNotFound);
        expect(tombstone, isNotNull);
        expect(tombstone!.id, original.id);
        expect(tombstone.text, isEmpty);
        expect(tombstone.status, 'failed');
        expect(tombstone.isDeleted, isTrue);
        expect(tombstone.isHidden, isFalse);
        expect(tombstone.deletedByPeerId, 'peer-alice');
        expect(tombstone.wireEnvelope, contains('"type":"message_deletion"'));

        final stored = await messageRepo.getMessage(original.id);
        expect(stored, isNotNull);
        expect(stored!.status, 'failed');
        expect(stored.isHidden, isFalse);
        expect(
          await messageRepo.getMessagesForContact(original.contactPeerId),
          hasLength(1),
        );

        p2pService.dispose();
      },
    );
  });
}
