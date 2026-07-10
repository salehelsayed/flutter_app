import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/share/application/share_batch_delivery_coordinator.dart';
import 'package:flutter_app/features/share/application/share_target_selection.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/media_thumbnail_image.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/fake_audio_recorder_service.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../shared/fakes/in_memory_message_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

class _GatedMediaAttachmentRepository
    extends InMemoryMediaAttachmentRepository {
  final Completer<void> saveStarted = Completer<void>();
  final Completer<void> allowSave = Completer<void>();

  @override
  Future<void> saveAttachment(
    MediaAttachment attachment, {
    required MediaOwnerLane owner,
  }) async {
    if (!saveStarted.isCompleted) {
      saveStarted.complete();
    }
    await allowSave.future;
    await super.saveAttachment(attachment, owner: owner);
  }
}

void main() {
  testWidgets(
    '1:1 external image share into an open conversation renders the thumbnail on the first outgoing frame',
    (tester) async {
      final tempDir = Directory.systemTemp.createTempSync(
        'external-share-first-frame-',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final imageFile = File('${tempDir.path}/shared.png')
        ..writeAsBytesSync(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
          ),
        );

      const ownPeerId = 'own-peer';
      const contactPeerId = 'contact-peer';
      const messageId = 'external-share-message';
      const attachmentId = 'external-share-attachment';
      const timestamp = '2026-07-10T12:00:00.000Z';
      final identity = IdentityModel(
        peerId: ownPeerId,
        publicKey: 'own-public-key',
        privateKey: 'own-private-key',
        mnemonic12:
            'one two three four five six seven eight nine ten eleven twelve',
        username: 'Me',
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      final contact = ContactModel(
        peerId: contactPeerId,
        publicKey: 'contact-public-key',
        mlKemPublicKey: 'contact-mlkem-key',
        rendezvous: '/ip4/127.0.0.1/tcp/4001',
        username: 'Friend',
        signature: 'contact-signature',
        scannedAt: timestamp,
      );
      final identityRepository = FakeIdentityRepository()..seed(identity);
      final contactRepository = InMemoryContactRepository()
        ..addTestContact(contact);
      final messageRepository = InMemoryMessageRepository();
      final mediaAttachmentRepository = _GatedMediaAttachmentRepository();
      final p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: true),
        storeInInboxResult: true,
      );
      final bridge = PassthroughCryptoBridge();
      final chatMessageListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepository,
        contactRepo: contactRepository,
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ConversationWired(
            contact: contact,
            identityRepo: identityRepository,
            messageRepo: messageRepository,
            chatMessageListener: chatMessageListener,
            p2pService: p2pService,
            bridge: bridge,
            mediaAttachmentRepo: mediaAttachmentRepository,
            mediaFileManager: FakeMediaFileManager(),
            audioRecorderService: FakeAudioRecorderService(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final coordinator = DefaultShareBatchDeliveryCoordinator(
        identityRepository: identityRepository,
        contactRepository: contactRepository,
        messageRepository: messageRepository,
        mediaAttachmentRepository: mediaAttachmentRepository,
        groupRepository: null,
        groupMessageRepository: null,
        bridge: bridge,
        p2pService: p2pService,
        mediaFileManager: FakeMediaFileManager(),
        imageProcessor: ImageProcessor(
          compressFile:
              ({
                required path,
                required quality,
                required keepExif,
                minWidth = 1920,
                minHeight = 1080,
              }) async => null,
          compressVideo:
              ({required path, required compress, onProgress}) async => null,
        ),
        processSharedMediaFn: (shareIntent) async => ProcessedShareMediaBatch(
          processedMedia: [
            PendingComposerMedia(
              file: imageFile,
              budgetBytes: imageFile.lengthSync(),
            ),
          ],
        ),
        sendToContactFn:
            ({
              required identity,
              required shareIntent,
              required contact,
              required processedMedia,
              required uploadHooks,
            }) async {
              final attachment = MediaAttachment(
                id: attachmentId,
                messageId: '',
                mime: 'image/png',
                size: processedMedia.single.budgetBytes,
                mediaType: 'image',
                localPath: processedMedia.single.file.path,
                downloadStatus: 'done',
                createdAt: timestamp,
                contentHash:
                    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                encryptionKeyBase64: 'external-share-key',
                encryptionNonce: 'external-share-nonce',
                encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
              );
              final (result, message) = await sendChatMessage(
                p2pService: p2pService,
                messageRepo: messageRepository,
                targetPeerId: contact.peerId,
                text: shareIntent.text ?? '',
                senderPeerId: identity.peerId,
                senderUsername: identity.username,
                messageId: messageId,
                timestamp: timestamp,
                createdAt: timestamp,
                bridge: bridge,
                recipientMlKemPublicKey: contact.mlKemPublicKey,
                mediaAttachments: [attachment],
                mediaAttachmentRepo: mediaAttachmentRepository,
              );
              return ShareBatchTargetResult(
                target: ShareTargetSelection.contact(contact),
                status: result == SendChatMessageResult.success
                    ? ShareBatchTargetStatus.sent
                    : ShareBatchTargetStatus.failed,
                detail: message == null ? 'Share failed.' : 'Sent.',
              );
            },
      );

      final delivery = coordinator.deliver(
        shareIntent: ShareIntent(
          type: ShareIntentType.files,
          filePaths: [imageFile.path],
        ),
        targets: [ShareTargetSelection.contact(contact)],
      );

      for (
        var i = 0;
        i < 20 && !mediaAttachmentRepository.saveStarted.isCompleted;
        i++
      ) {
        await tester.pump();
      }
      expect(mediaAttachmentRepository.saveStarted.isCompleted, isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      final renderedBeforeAttachmentSave = find
          .byType(MediaThumbnailImage)
          .evaluate()
          .isNotEmpty;

      mediaAttachmentRepository.allowSave.complete();
      await delivery;
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        renderedBeforeAttachmentSave,
        isTrue,
        reason:
            'the first message-change frame must render inline normalized media before attachment persistence completes',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
