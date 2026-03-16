import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/pending_post_media_upload_retrier.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_upload_recovery_item.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';

ContactModel _contact(String peerId, String username) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/example.invalid/tcp/443',
    username: username,
    signature: 'sig-$peerId',
    scannedAt: '2026-03-15T10:00:00.000Z',
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
            return XFile('${path}_processed');
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
}
