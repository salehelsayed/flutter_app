import 'dart:io';

import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/handle_incoming_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/retry_failed_messages_use_case.dart';
import 'package:flutter_app/features/conversation/application/retry_incomplete_uploads_use_case.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fixtures/media_repository_real_db_fixture.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

void main() {
  test(
    'queued forward retry preserves operation identity direct owner and local media state',
    () async {
      final tempDir = Directory.systemTemp.createTempSync('forward_retry_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final localFile = File('${tempDir.path}/forward.mp4')
        ..writeAsBytesSync([1, 2, 3, 4]);
      var senderStore = await MediaRepositoryRealDbFixture.create(
        databasePath: '${tempDir.path}/sender.sqlite',
      );
      addTearDown(() => senderStore.dispose());
      var receiverStore = await MediaRepositoryRealDbFixture.create(
        databasePath: '${tempDir.path}/receiver.sqlite',
      );
      addTearDown(() => receiverStore.dispose());

      const operationKey = 'stable-forward-operation';
      const senderPeerId = 'sender-peer';
      const receiverPeerId = 'receiver-peer';
      const messageId = 'fresh-forward-message';
      final originalRow = ConversationMessage(
        id: messageId,
        contactPeerId: receiverPeerId,
        senderPeerId: senderPeerId,
        text: 'caption',
        timestamp: '2026-07-10T10:00:00.000Z',
        status: 'failed',
        isIncoming: false,
        createdAt: '2026-07-10T10:00:00.000Z',
        dedupKey: operationKey,
        isForwarded: true,
      );
      final originalAttachment = MediaAttachment(
        id: 'fresh-forward-attachment',
        messageId: messageId,
        mime: 'video/mp4',
        size: 4,
        mediaType: 'video',
        downloadStatus: 'upload_pending',
        createdAt: '2026-07-10T10:00:00.000Z',
        ownerLane: MediaOwnerLane.direct,
      );

      // Persist the actual rows, then apply viewer-only state through the
      // owner-aware repository boundary. None of this state is constructor
      // reseeding, so the close/reopen below must rehydrate it from SQLite.
      await senderStore.messageRepo.saveMessage(originalRow);
      await senderStore.repo.saveAttachment(
        originalAttachment,
        owner: MediaOwnerLane.direct,
      );
      await senderStore.repo.updateLocalPath(
        originalAttachment.id,
        localFile.path,
      );
      await senderStore.repo.setBookmarked(
        originalAttachment.id,
        bookmarked: true,
      );
      await senderStore.repo.updatePlaybackPosition(originalAttachment.id, 77);
      await senderStore.repo.updateDownloadStatus(
        originalAttachment.id,
        'upload_pending',
      );

      senderStore = await senderStore.reopen();
      final rehydratedBeforeRetry = await senderStore.messageRepo.getMessage(
        messageId,
      );
      expect(rehydratedBeforeRetry!.id, messageId);
      expect(rehydratedBeforeRetry.dedupKey, operationKey);
      expect(rehydratedBeforeRetry.isForwarded, isTrue);
      final rehydratedMediaBeforeRetry = await senderStore.repo
          .getAttachmentsForMessage(messageId, owner: MediaOwnerLane.direct);
      expect(rehydratedMediaBeforeRetry, hasLength(1));
      expect(
        rehydratedMediaBeforeRetry.single.ownerLane,
        MediaOwnerLane.direct,
      );
      expect(rehydratedMediaBeforeRetry.single.isBookmarked, isTrue);
      expect(rehydratedMediaBeforeRetry.single.lastPlaybackPositionMs, 77);
      expect(rehydratedMediaBeforeRetry.single.localPath, localFile.path);
      expect(
        rehydratedMediaBeforeRetry.single.downloadStatus,
        'upload_pending',
      );

      final identities = FakeIdentityRepository()
        ..seed(FakeIdentityRepository.makeIdentity(peerId: senderPeerId));
      final senderContacts = InMemoryContactRepository();
      await senderContacts.addContact(
        const ContactModel(
          peerId: receiverPeerId,
          publicKey: 'receiver-public-key',
          rendezvous: '/dns4/relay/tcp/443',
          username: 'Receiver',
          signature: 'receiver-signature',
          scannedAt: '2026-07-10T09:00:00.000Z',
          mlKemPublicKey: 'receiver-mlkem-public-key',
        ),
      );
      final p2p = FakeP2PService(
        initialState: const NodeState(isStarted: true, peerId: senderPeerId),
      );
      final bridge = PassthroughCryptoBridge();

      final incompleteCount = await retryIncompleteUploads(
        mediaAttachmentRepo: senderStore.repo,
        messageRepo: senderStore.messageRepo,
        bridge: bridge,
        p2pService: p2p,
        identityRepo: identities,
        contactRepo: senderContacts,
        uploadMediaFn:
            ({
              required bridge,
              required localFilePath,
              required mime,
              required recipientPeerId,
              mediaFileManager,
              width,
              height,
              durationMs,
              waveform,
              allowedPeers,
              blobId,
              deleteSourceWhenDone = false,
              preparedArtifact,
            }) async => UploadMediaSucceeded(
              originalAttachment.copyWith(
                id: blobId,
                localPath: localFilePath,
                downloadStatus: 'done',
                encryptionKeyBase64: 'retry-upload-key',
                encryptionNonce: 'retry-upload-nonce',
                encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                contentHash:
                    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
              ),
            ),
      );
      expect(incompleteCount, 1);
      final firstEnvelope =
          p2p.lastSendMessageContent ?? p2p.lastStoreInInboxMessage;
      expect(firstEnvelope, isNotNull);

      final receiverContacts = InMemoryContactRepository();
      await receiverContacts.addContact(
        const ContactModel(
          peerId: senderPeerId,
          publicKey: 'sender-public-key',
          rendezvous: '/dns4/relay/tcp/443',
          username: 'Sender',
          signature: 'sender-signature',
          scannedAt: '2026-07-10T09:00:00.000Z',
          mlKemPublicKey: 'sender-mlkem-public-key',
        ),
      );
      final (firstReceive, firstReceived, _) = await handleIncomingChatMessage(
        message: ChatMessage(
          from: senderPeerId,
          to: receiverPeerId,
          content: firstEnvelope!,
          timestamp: originalRow.timestamp,
          isIncoming: true,
        ),
        messageRepo: receiverStore.messageRepo,
        contactRepo: receiverContacts,
        bridge: bridge,
        ownMlKemSecretKey: 'receiver-mlkem-secret-key',
        mediaAttachmentRepo: receiverStore.repo,
      );
      expect(firstReceive, HandleChatMessageResult.chatMessage);
      expect(firstReceived!.dedupKey, operationKey);
      expect(firstReceived.isForwarded, isTrue);

      // Plan 345 makes generic full-row persistence monotonic after an exact
      // initial envelope has settled. This test deliberately needs a
      // historical failed/no-envelope input, so seed that state through the
      // raw fixture DB only after proving no v110 intent or v108 owner remains.
      // retryFailedMessage must then rebuild from the rehydrated message and
      // media rows rather than replaying a cached wire payload.
      final sentAfterUpload = (await senderStore.messageRepo.getMessage(
        messageId,
      ))!;
      expect(sentAfterUpload.status, 'inboxed');
      expect(sentAfterUpload.transport, 'inbox');
      expect(sentAfterUpload.directMediaCustodyIntentId, isNull);
      final custodyOwners = await senderStore.db.query(
        'direct_inbox_custody_outbox',
        columns: const ['message_id'],
        where: 'message_id = ?',
        whereArgs: const [messageId],
      );
      expect(custodyOwners, isEmpty);
      final projected = await senderStore.db.update(
        'messages',
        const <String, Object?>{
          'status': 'failed',
          'wire_envelope': null,
          'transport': null,
          'relay_expires_at': null,
          'custody_checked_at': null,
        },
        where:
            'id = ? AND status = ? AND transport = ? '
            'AND direct_media_custody_intent_id IS NULL',
        whereArgs: const [messageId, 'inboxed', 'inbox'],
      );
      expect(projected, 1);
      senderStore = await senderStore.reopen();
      final failedAfterReopen = (await senderStore.messageRepo.getMessage(
        messageId,
      ))!;
      expect(failedAfterReopen.status, 'failed');
      expect(failedAfterReopen.wireEnvelope, isNull);
      expect(failedAfterReopen.id, messageId);
      expect(failedAfterReopen.dedupKey, operationKey);
      expect(failedAfterReopen.isForwarded, isTrue);
      final failedMediaAfterReopen = await senderStore.repo
          .getAttachmentsForMessage(messageId, owner: MediaOwnerLane.direct);
      expect(failedMediaAfterReopen, hasLength(1));
      expect(failedMediaAfterReopen.single.id, originalAttachment.id);
      expect(failedMediaAfterReopen.single.messageId, messageId);
      expect(failedMediaAfterReopen.single.ownerLane, MediaOwnerLane.direct);
      expect(failedMediaAfterReopen.single.isBookmarked, isTrue);
      expect(failedMediaAfterReopen.single.lastPlaybackPositionMs, 77);
      expect(failedMediaAfterReopen.single.localPath, localFile.path);
      expect(
        failedMediaAfterReopen.single.encryptionKeyBase64,
        'retry-upload-key',
      );
      expect(
        failedMediaAfterReopen.single.encryptionNonce,
        'retry-upload-nonce',
      );

      final failedCount = await retryFailedMessage(
        messageId: messageId,
        messageRepo: senderStore.messageRepo,
        identityRepo: identities,
        contactRepo: senderContacts,
        p2pService: p2p,
        bridge: bridge,
        mediaAttachmentRepo: senderStore.repo,
      );
      expect(failedCount, 1);
      final rebuiltEnvelope =
          p2p.lastSendMessageContent ?? p2p.lastStoreInInboxMessage;
      expect(rebuiltEnvelope, isNotNull);

      final (redeliveryResult, _, _) = await handleIncomingChatMessage(
        message: ChatMessage(
          from: senderPeerId,
          to: receiverPeerId,
          content: rebuiltEnvelope!,
          timestamp: originalRow.timestamp,
          isIncoming: true,
        ),
        messageRepo: receiverStore.messageRepo,
        contactRepo: receiverContacts,
        bridge: bridge,
        ownMlKemSecretKey: 'receiver-mlkem-secret-key',
        mediaAttachmentRepo: receiverStore.repo,
      );
      expect(redeliveryResult, HandleChatMessageResult.duplicate);

      final retried = await senderStore.messageRepo.getMessage(messageId);
      expect(retried!.id, messageId);
      expect(retried.dedupKey, operationKey);
      expect(retried.isForwarded, isTrue);
      final storedMedia = await senderStore.repo.getAttachmentsForMessage(
        messageId,
        owner: MediaOwnerLane.direct,
      );
      expect(storedMedia, hasLength(1));
      expect(storedMedia.single.id, originalAttachment.id);
      expect(storedMedia.single.messageId, messageId);
      expect(storedMedia.single.ownerLane, MediaOwnerLane.direct);
      expect(storedMedia.single.isBookmarked, isTrue);
      expect(storedMedia.single.lastPlaybackPositionMs, 77);
      expect(storedMedia.single.localPath, localFile.path);
      expect(storedMedia.single.encryptionKeyBase64, 'retry-upload-key');
      expect(storedMedia.single.encryptionNonce, 'retry-upload-nonce');

      final receiverRows = await receiverStore.messageRepo
          .getMessagesForContact(senderPeerId);
      expect(receiverRows, hasLength(1));
      expect(receiverRows.single.id, messageId);
      expect(receiverRows.single.isForwarded, isTrue);
      expect(receiverRows.single.dedupKey, operationKey);
      final receiverMediaRows = await receiverStore.repo
          .getAttachmentsForMessage(messageId, owner: MediaOwnerLane.direct);
      expect(receiverMediaRows, hasLength(1));
      expect(receiverMediaRows.single.id, originalAttachment.id);
      expect(receiverMediaRows.single.messageId, messageId);
      expect(receiverMediaRows.single.ownerLane, MediaOwnerLane.direct);
    },
  );
}
