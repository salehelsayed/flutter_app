import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/posts/application/pending_post_media_upload_retrier.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_upload_recovery_item.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../shared/fakes/encrypted_media_test_bridge.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';

ContactModel _contact(String peerId, String username, {String? mlKemKey}) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/example.invalid/tcp/443',
    username: username,
    signature: 'sig-$peerId',
    scannedAt: '2026-03-15T10:00:00.000Z',
    mlKemPublicKey: mlKemKey,
  );
}

void main() {
  late InMemoryPostRepository posts;
  late InMemoryContactRepository contacts;
  late FakeSecureKeyStore secureKeyStore;
  late ImageProcessor imageProcessor;
  late Directory tempDir;

  setUp(() async {
    posts = InMemoryPostRepository();
    contacts = InMemoryContactRepository();
    secureKeyStore = FakeSecureKeyStore();
    imageProcessor = ImageProcessor(
      compressFile:
          ({
            required path,
            required quality,
            required keepExif,
            minWidth = 1920,
            minHeight = 1080,
          }) async {
            final processedPath = '${path}_processed';
            final source = File(path);
            if (source.existsSync()) {
              source.copySync(processedPath);
            }
            return XFile(processedPath);
          },
    );
    tempDir = await Directory.systemTemp.createTemp('post-media-restart');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
    posts.dispose();
  });

  test(
    'retryPendingPostMediaUploads hydrates attachments and resumes recipient fanout with nearby context preserved',
    () async {
      final localFile = File('${tempDir.path}/photo.jpg');
      await localFile.writeAsString('phase7');
      final network = FakeP2PNetwork();
      final p2pService = FakeP2PService(peerId: 'peer-self', network: network);
      contacts.addTestContact(_contact('peer-bob', 'Bob'));

      await posts.savePost(
        const PostModel(
          id: 'post-nearby-media',
          eventId: 'evt-nearby-media',
          senderPeerId: 'peer-self',
          authorPeerId: 'peer-self',
          authorUsername: 'Alice',
          text: '',
          audience: PostAudience(
            kind: PostAudienceKind.peopleNearby,
            radiusM: 500,
            scopeLabel: 'Shared nearby',
          ),
          createdAt: '2026-03-16T10:00:00.000Z',
          visibleAt: '2026-03-16T10:00:00.000Z',
          expiresAt: '2026-03-19T10:00:00.000Z',
          isIncoming: false,
          deliveryStatus: 'failed',
          mediaKind: 'image',
        ),
      );
      await posts.saveRecipientDelivery(
        const PostRecipientDelivery(
          postId: 'post-nearby-media',
          recipientPeerId: 'peer-bob',
          deliveryStatus: 'failed',
          lastAttemptAt: '2026-03-16T10:00:01.000Z',
          deliveryPath: 'failed',
          lastError: 'direct_and_inbox_failed',
          createdAt: '2026-03-16T10:00:01.000Z',
          updatedAt: '2026-03-16T10:00:01.000Z',
          nearbyDistanceM: 87,
        ),
      );
      await posts.replacePostMediaUploadRecoveryItems(
        'post-nearby-media',
        <PostMediaUploadRecoveryItem>[
          PostMediaUploadRecoveryItem(
            postId: 'post-nearby-media',
            position: 0,
            localFilePath: localFile.path,
            mime: 'image/jpeg',
            kind: 'image',
            createdAt: '2026-03-16T10:00:00.000Z',
          ),
        ],
      );

      final retried = await retryPendingPostMediaUploads(
        postRepo: posts,
        contactRepo: contacts,
        p2pService: p2pService,
        secureKeyStore: secureKeyStore,
        imageProcessor: imageProcessor,
        uploadPostMediaFn:
            ({
              required postId,
              required localFilePath,
              required mime,
              required allowedPeers,
              mediaFileManager,
              width,
              height,
              durationMs,
              waveform,
            }) async {
              return PostMediaAttachmentModel(
                mediaId: 'media-1',
                postId: postId,
                blobId: 'blob-1',
                kind: 'image',
                mime: mime,
                sizeBytes: 248120,
                width: width,
                height: height,
                localPath: 'post_media/$postId/blob-1.jpg',
                downloadStatus: 'done',
                createdAt: '2026-03-16T10:00:02.000Z',
              );
            },
      );

      expect(retried, 1);
      expect(
        await posts.loadPostMediaUploadRecoveryItems('post-nearby-media'),
        isEmpty,
      );
      expect(
        await posts.loadPostMediaAttachments('post-nearby-media'),
        hasLength(1),
      );
      expect(
        (await posts.getPost('post-nearby-media'))!.deliveryStatus,
        'sent',
      );

      final inboxMessage =
          network.retrieveInbox('peer-bob').single['message'] as String;
      final payload = jsonDecode(inboxMessage) as Map<String, dynamic>;
      final envelopePayload = payload['payload'] as Map<String, dynamic>;
      final snapshot = envelopePayload['snapshot'] as Map<String, dynamic>;
      final nearbyContext =
          envelopePayload['nearby_context'] as Map<String, dynamic>;
      expect(snapshot['media_kind'], 'image');
      expect(snapshot['media'][0]['blob_id'], 'blob-1');
      expect(nearbyContext['distance_m'], 87);

      p2pService.dispose();
    },
  );

  test(
    'retrier replay through the REAL uploadPostMedia re-encrypts from source with a fresh key and blobId; superseded blob orphaned with no delete (KC-P2)',
    () async {
      final sourceBytes = Uint8List.fromList(
        List<int>.generate(320, (index) => (index * 13 + 5) & 0xff),
      );
      final localFile = File('${tempDir.path}/photo.jpg');
      localFile.writeAsBytesSync(sourceBytes, flush: true);

      final network = FakeP2PNetwork();
      final p2pService = FakeP2PService(peerId: 'peer-self', network: network);
      final relayStore = RelayMediaStore();
      final bridge = EncryptedMediaTestBridge(relayStore);
      final mediaFileManager = TempPostMediaFileManager(tempDir.path);
      contacts.addTestContact(
        _contact('peer-bob', 'Bob', mlKemKey: 'mlkem-peer-bob'),
      );

      // A prior (pre-kill) attempt left a blob on the relay and keyless
      // attachment rows, but the recovery items were never cleared.
      relayStore.uploadedBytesByBlobId['blob-superseded'] = sourceBytes;
      await posts.savePost(
        const PostModel(
          id: 'post-replay',
          eventId: 'evt-replay',
          senderPeerId: 'peer-self',
          authorPeerId: 'peer-self',
          authorUsername: 'Alice',
          text: '',
          audience: PostAudience(kind: PostAudienceKind.allFriends),
          createdAt: '2026-03-16T10:00:00.000Z',
          visibleAt: '2026-03-16T10:00:00.000Z',
          expiresAt: '2026-03-19T10:00:00.000Z',
          isIncoming: false,
          deliveryStatus: 'failed',
          mediaKind: 'image',
        ),
      );
      await posts.saveRecipientDelivery(
        const PostRecipientDelivery(
          postId: 'post-replay',
          recipientPeerId: 'peer-bob',
          deliveryStatus: 'failed',
          lastAttemptAt: '2026-03-16T10:00:01.000Z',
          deliveryPath: 'failed',
          createdAt: '2026-03-16T10:00:01.000Z',
          updatedAt: '2026-03-16T10:00:01.000Z',
        ),
      );
      await posts.replacePostMediaUploadRecoveryItems(
        'post-replay',
        <PostMediaUploadRecoveryItem>[
          PostMediaUploadRecoveryItem(
            postId: 'post-replay',
            position: 0,
            localFilePath: localFile.path,
            mime: 'image/jpeg',
            kind: 'image',
            createdAt: '2026-03-16T10:00:00.000Z',
          ),
        ],
      );

      final retried = await retryPendingPostMediaUploads(
        postRepo: posts,
        contactRepo: contacts,
        p2pService: p2pService,
        secureKeyStore: secureKeyStore,
        imageProcessor: imageProcessor,
        mediaFileManager: mediaFileManager,
        bridge: bridge,
      );

      expect(retried, 1);
      expect(
        await posts.loadPostMediaUploadRecoveryItems('post-replay'),
        isEmpty,
      );

      // Fresh blobId+key minted inside the real uploadPostMedia; recovery
      // items are keyless plaintext-source rows by design.
      final attachment =
          (await posts.loadPostMediaAttachments('post-replay')).single;
      expect(attachment.blobId, isNot('blob-superseded'));
      expect(attachment.isEncrypted, isTrue);
      expect(attachment.encryptionKeyBase64, isNotNull);
      expect(attachment.encryptionNonce, isNotNull);
      expect(
        attachment.encryptionScheme,
        kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      );
      expect(attachment.contentHash, isNotNull);

      // Ciphertext on the relay under the opaque transport mime.
      final relayBytes = relayStore.uploadedBytesByBlobId[attachment.blobId]!;
      expect(relayBytes, isNot(orderedEquals(sourceBytes)));
      expect(
        relayStore.mimeByBlobId[attachment.blobId],
        kOpaqueMediaTransportMime,
      );

      // KC-P2 residual: the superseded blob is orphaned, never deleted.
      expect(
        relayStore.uploadedBytesByBlobId.containsKey('blob-superseded'),
        isTrue,
      );
      expect(relayStore.deletedBlobIds, isEmpty);
      expect(bridge.commandLog, isNot(contains('media:delete')));

      // KC-P1: the wire envelope is built only after prep succeeds, from
      // the CURRENT rows — its media_keys reference the fresh blobId.
      final inboxMessage =
          network.retrieveInbox('peer-bob').single['message'] as String;
      final wire = jsonDecode(inboxMessage) as Map<String, dynamic>;
      expect(wire['version'], '2');
      final innerPayload =
          jsonDecode(
                (wire['encrypted'] as Map<String, dynamic>)['ciphertext']
                    as String,
              )
              as Map<String, dynamic>;
      final mediaKeys = innerPayload['media_keys'] as Map<String, dynamic>;
      final entry =
          mediaKeys[attachment.mediaId] as Map<String, dynamic>;
      expect(entry['blob_id'], attachment.blobId);
      expect(entry['key_base64'], attachment.encryptionKeyBase64);

      p2pService.dispose();
    },
  );
}
