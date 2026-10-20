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

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../shared/fakes/encrypted_media_test_bridge.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';

ContactModel _contact(
  String peerId,
  String username, {
  String? mlKemKey = 'test-mlkem',
}) {
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

  for (final scenario in [
    (swept: false, fails: false),
    (swept: true, fails: false),
    (swept: true, fails: true),
  ]) {
    final sweptDuringUpload = scenario.swept;
    final uploadFails = scenario.fails;
    test(
      'upload finishing after expiry sends nothing (swept=$sweptDuringUpload, failed=$uploadFails)',
      () async {
        var now = DateTime.now().toUtc();
        final createdAt = now.subtract(const Duration(hours: 23));
        final source = File('${tempDir.path}/voice.m4a');
        await source.writeAsString('voice bytes');
        final network = FakeP2PNetwork();
        final service = FakeP2PService(peerId: 'peer-self', network: network);
        addTearDown(service.dispose);
        contacts.addTestContact(_contact('peer-bob', 'Bob'));
        await posts.savePost(
          PostModel(
            id: 'late-upload',
            eventId: 'late-event',
            senderPeerId: 'peer-self',
            authorPeerId: 'peer-self',
            authorUsername: 'Alice',
            text: '',
            audience: PostAudience.allFriends(),
            createdAt: createdAt.toIso8601String(),
            visibleAt: createdAt.toIso8601String(),
            expiresAt: createdAt
                .add(const Duration(hours: 24))
                .toIso8601String(),
            mediaKind: 'voice',
            isIncoming: false,
            deliveryStatus: 'failed',
          ),
        );
        await posts.saveRecipientDelivery(
          PostRecipientDelivery(
            postId: 'late-upload',
            recipientPeerId: 'peer-bob',
            deliveryStatus: 'failed',
            lastAttemptAt: DateTime.now().toUtc().toIso8601String(),
            deliveryPath: 'failed',
            createdAt: createdAt.toIso8601String(),
            updatedAt: createdAt.toIso8601String(),
          ),
        );
        await posts.replacePostMediaUploadRecoveryItems('late-upload', [
          PostMediaUploadRecoveryItem(
            postId: 'late-upload',
            position: 0,
            localFilePath: source.path,
            mime: 'audio/mp4',
            kind: 'voice',
            createdAt: createdAt.toIso8601String(),
          ),
        ]);
        final lateFile = File(
          '${tempDir.path}/post_media/late-upload/late.m4a',
        );
        var uploads = 0;
        final retried = await retryPendingPostMediaUploads(
          postRepo: posts,
          contactRepo: contacts,
          p2pService: service,
          secureKeyStore: secureKeyStore,
          imageProcessor: imageProcessor,
          bridge: FakeBridge(),
          mediaFileManager: TempPostMediaFileManager(tempDir.path),
          nowProvider: () => now,
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
                uploads++;
                now = createdAt.add(const Duration(hours: 24));
                if (sweptDuringUpload) await posts.deletePostCascade(postId);
                if (uploadFails) return null;
                await lateFile.parent.create(recursive: true);
                await lateFile.writeAsString('late upload');
                return PostMediaAttachmentModel(
                  localPath: 'post_media/late-upload/late.m4a',
                  mediaId: 'late-media',
                  postId: postId,
                  blobId: 'late-blob',
                  kind: 'voice',
                  mime: mime,
                  sizeBytes: 11,
                  createdAt: now.toIso8601String(),
                );
              },
        );
        expect(retried, 1);
        expect(uploads, 1);
        expect(await lateFile.exists(), isFalse);
        expect(await lateFile.parent.exists(), isFalse);
        expect(network.inboxCount('peer-bob'), 0);
        expect(
          await posts.loadPostMediaUploadRecoveryItems('late-upload'),
          isEmpty,
        );
        expect(await posts.loadPostMediaAttachments('late-upload'), isEmpty);
        if (sweptDuringUpload) {
          expect(await posts.getPost('late-upload'), isNull);
        }
      },
    );
  }

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
        nowProvider: () => DateTime.parse('2026-03-16T12:00:00Z'),
        secureKeyStore: secureKeyStore,
        imageProcessor: imageProcessor,
        bridge: FakeBridge(),
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
      final envelopePayload =
          jsonDecode(
                (payload['encrypted'] as Map<String, dynamic>)['ciphertext']
                    as String,
              )
              as Map<String, dynamic>;
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
        nowProvider: () => DateTime.parse('2026-03-16T12:00:00Z'),
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
      final attachment = (await posts.loadPostMediaAttachments(
        'post-replay',
      )).single;
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
      final entry = mediaKeys[attachment.mediaId] as Map<String, dynamic>;
      expect(entry['blob_id'], attachment.blobId);
      expect(entry['key_base64'], attachment.encryptionKeyBase64);

      p2pService.dispose();
    },
  );
}
