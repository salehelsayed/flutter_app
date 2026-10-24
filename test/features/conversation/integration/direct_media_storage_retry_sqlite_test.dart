import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/media/direct_media_blob_artifact_store.dart';
import 'package:flutter_app/core/media/direct_media_custody_intent.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/handle_delivery_receipt_use_case.dart';
import 'package:flutter_app/features/conversation/application/handle_incoming_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/prepared_direct_media_blob_custody_coordinator.dart';
import 'package:flutter_app/features/conversation/application/retry_incomplete_uploads_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_delivery_receipt_use_case.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fixtures/media_repository_real_db_fixture.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'DC-007 strict storage failure silently retries the same SQLite generation and settles once',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'direct_storage_retry_',
      );
      addTearDown(() => temp.delete(recursive: true));
      var sender = await MediaRepositoryRealDbFixture.create(
        databasePath: '${temp.path}/sender.sqlite',
      );
      addTearDown(() => sender.dispose());
      var receiver = await MediaRepositoryRealDbFixture.create(
        databasePath: '${temp.path}/receiver.sqlite',
      );
      addTearDown(() => receiver.dispose());
      const senderId = 'storage-retry-sender';
      const receiverId = 'storage-retry-recipient';
      const messageId = 'dc007-storage-retry-message';
      const attachmentId = 'dc007-storage-retry-attachment';
      const relativeSource = 'pending_uploads/$messageId/$attachmentId.jpg';
      final source = File(
        '${FakeMediaFileManager.testRootPath}/$relativeSource',
      );
      await source.parent.create(recursive: true);
      await source.writeAsBytes([1, 2, 3, 4]);
      addTearDown(() => source.parent.delete(recursive: true));
      final manager = FakeMediaFileManager();
      final bridge = PassthroughCryptoBridge();
      final senderContacts = InMemoryContactRepository();
      final receiverContacts = InMemoryContactRepository();
      ContactModel contact(String id) => ContactModel(
        peerId: id,
        publicKey: '$id-public-key',
        rendezvous: 'fixture-relay',
        username: 'Fixture contact',
        signature: 'fixture-signature',
        scannedAt: '2026-10-24T00:00:00.000Z',
        mlKemPublicKey: '$id-mlkem',
      );
      await senderContacts.addContact(contact(receiverId));
      await receiverContacts.addContact(contact(senderId));
      await sender.db.insert('contacts', contact(receiverId).toMap());
      await receiver.db.insert('contacts', contact(senderId).toMap());
      final identity = FakeIdentityRepository()
        ..seed(FakeIdentityRepository.makeIdentity(peerId: senderId));
      // The existing integration transport implements ack-or-expiry custody;
      // a legacy bool-only inbox fake correctly fails strict admission.
      final network = FakeP2PNetwork();
      final p2p = _MediaExpiryNetworkService(
        peerId: senderId,
        network: network,
      );
      addTearDown(p2p.dispose);
      final receiptTransport = FakeP2PService(
        peerId: receiverId,
        network: network,
      )..setOnline(false);
      addTearDown(receiptTransport.dispose);
      final created = DateTime.now().toUtc().toIso8601String();
      final parent = ConversationMessage(
        id: messageId,
        contactPeerId: receiverId,
        senderPeerId: senderId,
        text: 'Fixture media',
        timestamp: created,
        createdAt: created,
        status: 'sending',
        isIncoming: false,
        dedupKey: messageId,
        directMediaCustodyIntentId: computeDirectMediaCustodyIntentId(
          messageId: messageId,
          attachmentIds: [attachmentId],
        ),
      );
      final pending = MediaAttachment(
        id: attachmentId,
        messageId: messageId,
        mime: 'image/jpeg',
        size: 4,
        mediaType: 'image',
        localPath: relativeSource,
        downloadStatus: 'upload_pending',
        createdAt: created,
        ownerLane: MediaOwnerLane.direct,
      );
      var blocked = true;
      var encryptions = 0;
      final uploads = <({String id, String path, String hash, int size})>[];
      PreparedDirectMediaBlobCustodyCoordinator coordinator() =>
          PreparedDirectMediaBlobCustodyCoordinator(
            repository: sender.repo as DirectMediaBlobCustodyRepository,
            artifactStore: DirectMediaBlobArtifactStore(
              documentsDirectoryProvider: () async => temp,
            ),
            // Encryption and transport are existing host seams; artifact
            // ownership, hashes, production staging and SQLite are real.
            prepareArtifact: ({required bridge, required localFilePath}) async {
              encryptions++;
              final bytes = [
                ...await File(localFilePath).readAsBytes(),
                ...List.filled(16, 7),
              ];
              final encrypted = File(
                '${temp.path}/candidate-$encryptions.blob',
              );
              await encrypted.writeAsBytes(bytes);
              return EncryptedMediaArtifact(
                encryptedPath: encrypted.path,
                keyBase64: base64Encode(List.filled(32, 1)),
                nonce: base64Encode(List.filled(12, 2)),
                scheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                contentHash: sha256.convert(bytes).toString(),
                plaintextSize: 4,
              );
            },
            strictUpload:
                ({
                  required bridge,
                  required attachmentId,
                  required recipientPeerId,
                  required ciphertextPath,
                  required contentHash,
                  required ciphertextSize,
                }) async {
                  expect(recipientPeerId, receiverId);
                  expect(
                    sha256
                        .convert(await File(ciphertextPath).readAsBytes())
                        .toString(),
                    contentHash,
                  );
                  uploads.add((
                    id: attachmentId,
                    path: ciphertextPath,
                    hash: contentHash,
                    size: ciphertextSize,
                  ));
                  if (blocked) {
                    return <String, dynamic>{
                      'ok': false,
                      'error': 'MEDIA_CUSTODY_STORAGE_ERROR',
                    };
                  }
                  return <String, dynamic>{
                    'ok': true,
                    'id': attachmentId,
                    'storeStatus': 'stored',
                    'custodyKind': 'direct_media_blob_v1',
                    'custodyContract': 'ack_or_expiry_v1',
                    'contentHash': contentHash,
                    'size': ciphertextSize,
                    'mime': 'application/octet-stream',
                    'expiresAtMs': DateTime.now()
                        .add(const Duration(hours: 1))
                        .millisecondsSinceEpoch,
                    'custodyRelayPeerId': 'fixture-custody-relay',
                  };
                },
          );
      final first = await coordinator().prepareAndUploadFreshMessage(
        bridge: bridge,
        identityPeerId: senderId,
        recipientPeerId: receiverId,
        parent: parent,
        sources: [
          PreparedDirectMediaBlobSource(
            attachment: pending,
            plaintextPath: source.path,
          ),
        ],
        onAuthorityReady: (_) async => true,
      );
      expect(first.state, PreparedDirectMediaBlobUploadState.retained);
      expect(first.hasDurableAuthority, isTrue);
      expect(uploads, hasLength(1));
      expect(encryptions, 1);
      final firstRow =
          (await (sender.repo as DirectMediaBlobCustodyRepository)
                  .loadDirectMediaBlobCustodyForMessage(messageId))
              .single;
      expect(firstRow.state, DirectMediaBlobCustodyState.outgoingPrepared);
      final prepared = (await sender.repo.getAttachmentsForMessage(
        messageId,
        owner: MediaOwnerLane.direct,
      )).single;
      expect(prepared.downloadStatus, 'upload_pending');
      expect(await sender.messageRepo.getMessage(messageId), isNotNull);
      expect(network.deliverCallCount, 0);

      sender = await sender.reopen();
      Future<int> retry() => retryIncompleteUploads(
        mediaAttachmentRepo: sender.repo,
        messageRepo: sender.messageRepo,
        bridge: bridge,
        p2pService: p2p,
        identityRepo: identity,
        contactRepo: senderContacts,
        mediaFileManager: manager,
        directMediaBlobCustodyCoordinator: coordinator(),
      );
      expect(await retry(), 0);
      expect(uploads, hasLength(2));
      expect(network.deliverCallCount, 0);
      expect(
        (await sender.repo.getAttachmentsForMessage(
          messageId,
          owner: MediaOwnerLane.direct,
        )).single.downloadStatus,
        'upload_pending',
      );
      blocked = false;
      expect(await retry(), 1);
      expect(uploads, hasLength(3));
      expect(uploads.every((attempt) => attempt == uploads.first), isTrue);
      expect(
        encryptions,
        1,
        reason: 'recovery reopens owned ciphertext; no new generation',
      );
      var settled = (await sender.messageRepo.getMessage(messageId))!;
      expect(settled.status, 'inboxed');
      final storedBlob =
          (await (sender.repo as DirectMediaBlobCustodyRepository)
                  .loadDirectMediaBlobCustodyForMessage(messageId))
              .single;
      expect(p2p.expiryCeilings, [storedBlob.expiresAtMs]);
      expect(settled.id, messageId);
      expect(settled.dedupKey, messageId);
      final complete = (await sender.repo.getAttachmentsForMessage(
        messageId,
        owner: MediaOwnerLane.direct,
      )).single;
      expect(complete.id, attachmentId);
      expect(complete.downloadStatus, 'done');
      expect(complete.encryptionKeyBase64, prepared.encryptionKeyBase64);
      expect(network.inboxCount(receiverId), 1);
      receiptTransport.setOnline(true);
      final queued = await receiptTransport.retrieveInbox();
      expect(queued, hasLength(1));
      final wire = queued.single['message'] as String;
      expect(wire, settled.wireEnvelope);
      final received = await handleIncomingChatMessage(
        message: ChatMessage(
          from: senderId,
          to: receiverId,
          content: wire,
          timestamp: created,
          isIncoming: true,
          transport: 'inbox',
        ),
        messageRepo: receiver.messageRepo,
        contactRepo: receiverContacts,
        bridge: bridge,
        ownMlKemSecretKey: 'fixture-receiver-secret',
        mediaAttachmentRepo: receiver.repo,
      );
      expect(received.$1, HandleChatMessageResult.chatMessage);
      expect(received.$2, isNotNull);
      expect(received.$2!.dedupKey, messageId);
      expect(await receiver.messageRepo.getMessage(received.$2!.id), isNotNull);
      final receiptFuture = p2p.messageStream
          .firstWhere(
            (message) =>
                (jsonDecode(message.content) as Map)['type'] ==
                'delivery_receipt',
          )
          .timeout(const Duration(seconds: 5));
      expect(
        await sendDeliveryReceipt(
          p2pService: receiptTransport,
          targetPeerId: senderId,
          messageIds: [received.$2!.dedupKey!],
        ),
        isTrue,
      );
      final receipt = await receiptFuture;
      await handleDeliveryReceipt(
        message: receipt,
        messageRepo: sender.messageRepo,
        mediaAttachmentRepo: sender.repo,
      );
      await handleDeliveryReceipt(
        message: receipt,
        messageRepo: sender.messageRepo,
        mediaAttachmentRepo: sender.repo,
      );
      expect(await retry(), 0);
      expect(uploads, hasLength(3));
      sender = await sender.reopen();
      receiver = await receiver.reopen();
      settled = (await sender.messageRepo.getMessage(messageId))!;
      expect(settled.status, 'delivered');
      expect(settled.wireEnvelope, isNull);
      expect(await sender.db.query('messages'), hasLength(1));
      expect(
        await sender.repo.getAttachmentsForMessage(
          messageId,
          owner: MediaOwnerLane.direct,
        ),
        hasLength(1),
      );
      expect(
        (await sender.repo.getAttachmentsForMessage(
          messageId,
          owner: MediaOwnerLane.direct,
        )).single.downloadStatus,
        'done',
      );
      expect(await receiver.db.query('messages'), hasLength(1));
      expect(
        await receiver.repo.getAttachmentsForMessage(
          received.$2!.id,
          owner: MediaOwnerLane.direct,
        ),
        hasLength(1),
      );
    },
  );
}

// A narrow media-only capability over the existing integration network.
// The general fake intentionally has only ordinary ACK-or-expiry storage.
class _MediaExpiryNetworkService extends FakeP2PService
    implements MediaExpiryBoundedInboxStore {
  _MediaExpiryNetworkService({required super.peerId, required super.network});

  final expiryCeilings = <int>[];

  @override
  Future<InboxStoreOutcome> storeInMediaExpiryBoundedInboxDetailed(
    String toPeerId,
    String message, {
    required int custodyExpiresAtOrBeforeMs,
    int? timeoutMs,
  }) async {
    expect(
      custodyExpiresAtOrBeforeMs,
      greaterThan(DateTime.now().millisecondsSinceEpoch),
    );
    expiryCeilings.add(custodyExpiresAtOrBeforeMs);
    final stored = await super.storeInInboxDetailed(
      toPeerId,
      message,
      timeoutMs: timeoutMs,
    );
    if (!stored.accepted) return stored;
    return InboxStoreOutcome(
      status: stored.status,
      storeStatus: stored.storeStatus,
      expiresAtMs: custodyExpiresAtOrBeforeMs,
      custodyContract: ackOrExpiryInboxCustodyContract,
    );
  }
}
