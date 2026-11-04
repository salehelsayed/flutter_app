import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/attach_post_media_use_case.dart';
import 'package:flutter_app/features/posts/application/pending_post_media_upload_retrier.dart';
import 'package:flutter_app/features/posts/application/post_delivery_runner.dart';
import 'package:flutter_app/features/posts/application/send_post_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
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

ContactModel _contact(String peerId, String username) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/example.invalid/tcp/443',
    username: username,
    signature: 'sig-$peerId',
    scannedAt: '2026-03-15T10:00:00.000Z',
    mlKemPublicKey: 'mlkem-$peerId',
  );
}

void main() {
  late InMemoryContactRepository contacts;
  late InMemoryPostRepository posts;
  late FakeSecureKeyStore secureKeyStore;
  late ImageProcessor imageProcessor;

  setUp(() {
    contacts = InMemoryContactRepository();
    posts = InMemoryPostRepository();
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
    contacts.addTestContact(_contact('peer-bob', 'Bob'));
  });

  tearDown(() {
    posts.dispose();
  });

  test(
    'accepted photo stays readable after its picker source is removed',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('thought-source-');
      addTearDown(() => tempDir.delete(recursive: true));
      final source = File('${tempDir.path}/picker/photo.jpg');
      await source.parent.create();
      const photoBytes = <int>[1, 2, 3, 4];
      await source.writeAsBytes(photoBytes);
      final files = TempPostMediaFileManager('${tempDir.path}/documents');
      final (result, created) = await createLocalPost(
        postRepo: posts,
        contactRepo: contacts,
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        text: 'My photo',
        audience: PostAudience.allFriends(),
        mediaDrafts: [
          PostMediaDraft(localFilePath: source.path, mime: 'image/jpeg'),
        ],
        mediaFileManager: files,
      );
      expect(result, SendPostResult.success);
      final postId = created!.post.id;
      await source.parent.delete(recursive: true);

      final retained = await posts.loadPostMediaUploadRecoveryItems(postId);
      expect(retained, hasLength(1));
      final retainedFile = File(
        await files.resolveStoredPath(retained.single.localFilePath),
      );
      expect(await retainedFile.exists(), isTrue);
      expect(await retainedFile.readAsBytes(), photoBytes);
      expect(await posts.loadPostMediaAttachments(postId), isEmpty);

      final network = FakeP2PNetwork();
      final service = FakeP2PService(peerId: 'peer-alice', network: network);
      addTearDown(service.dispose);
      final replayProcessor = ImageProcessor(
        compressFile:
            ({
              required path,
              required quality,
              required keepExif,
              minWidth = 1920,
              minHeight = 1080,
            }) async {
              final processed = await File(path).copy('${path}_processed');
              return XFile(processed.path);
            },
      );
      List<int>? replayedBytes;
      expect(
        await retryPendingPostMediaUploads(
          postRepo: posts,
          contactRepo: contacts,
          p2pService: service,
          secureKeyStore: secureKeyStore,
          imageProcessor: replayProcessor,
          mediaFileManager: files,
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
                replayedBytes = await File(localFilePath).readAsBytes();
                return null;
              },
        ),
        1,
      );
      expect(replayedBytes, photoBytes);
      expect(await retainedFile.readAsBytes(), photoBytes);
      expect(
        await posts.loadPostMediaUploadRecoveryItems(postId),
        hasLength(1),
      );
      expect(network.storeInInboxCallCount, 0);
    },
  );

  test(
    'live photo retries after one upload failure and publishes the same thought once',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('thought-retry-');
      addTearDown(() => tempDir.delete(recursive: true));
      final source = File('${tempDir.path}/photo.jpg');
      await source.writeAsBytes(<int>[1, 2, 3, 4]);
      final network = FakeP2PNetwork();
      final service = FakeP2PService(peerId: 'peer-alice', network: network);
      addTearDown(service.dispose);
      final bridge = FakeBridge();
      var uploadAttempts = 0;
      Future<PostMediaAttachmentModel?> upload({
        required String postId,
        required String localFilePath,
        required String mime,
        required List<String> allowedPeers,
        MediaFileManager? mediaFileManager,
        int? width,
        int? height,
        int? durationMs,
        List<double>? waveform,
      }) async {
        uploadAttempts++;
        if (uploadAttempts == 1) return null;
        return PostMediaAttachmentModel(
          mediaId: 'recovered-photo',
          postId: postId,
          blobId: 'recovered-blob',
          kind: 'image',
          mime: mime,
          sizeBytes: 4,
          localPath: 'post_media/$postId/recovered-blob.jpg',
          downloadStatus: 'done',
          createdAt: DateTime.now().toUtc().toIso8601String(),
        );
      }

      final (result, pending) = await sendPost(
        p2pService: service,
        postRepo: posts,
        contactRepo: contacts,
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        text: 'Photo with a caption',
        audience: PostAudience.allFriends(),
        mediaDrafts: [
          PostMediaDraft(localFilePath: source.path, mime: 'image/jpeg'),
        ],
        secureKeyStore: secureKeyStore,
        imageProcessor: imageProcessor,
        uploadPostMediaFn: upload,
        bridge: bridge,
      );
      expect(result, SendPostResult.sendFailed);
      final postId = pending!.id;
      expect(pending.mediaKind, 'image');
      expect(pending.deliveryStatus, 'sending');
      expect(await source.exists(), isTrue);
      expect(
        await posts.loadPostMediaUploadRecoveryItems(postId),
        hasLength(1),
      );
      expect(network.storeInInboxCallCount, 0);

      Future<int> retry() => retryPendingPostMediaUploads(
        postRepo: posts,
        contactRepo: contacts,
        p2pService: service,
        secureKeyStore: secureKeyStore,
        imageProcessor: imageProcessor,
        uploadPostMediaFn: upload,
        bridge: bridge,
      );
      expect(await retry(), 1);
      expect(await retry(), 0);
      expect(uploadAttempts, 2);
      expect(network.storeInInboxCallCount, 1);
      final recovered = await posts.getPost(postId);
      expect(recovered!.eventId, pending.eventId);
      expect(recovered.deliveryStatus, 'sent');
      expect(recovered.media.single.blobId, 'recovered-blob');
      expect(await posts.loadPostMediaUploadRecoveryItems(postId), isEmpty);
      final wire =
          network.retrieveInbox('peer-bob').single['message'] as String;
      final outer = jsonDecode(wire) as Map<String, dynamic>;
      expect(outer['event_id'], pending.eventId);
      final inner =
          jsonDecode(
                (outer['encrypted'] as Map<String, dynamic>)['ciphertext']
                    as String,
              )
              as Map<String, dynamic>;
      final snapshot = inner['snapshot'] as Map<String, dynamic>;
      expect(snapshot['post_id'], postId);
      expect(snapshot['text'], 'Photo with a caption');
      expect(snapshot['media_kind'], 'image');
      expect(snapshot['media'], hasLength(1));
      expect(snapshot['media'][0]['blob_id'], 'recovered-blob');
    },
  );

  test(
    'createLocalPost persists a media skeleton before upload metadata exists',
    () async {
      final (result, created) = await createLocalPost(
        postRepo: posts,
        contactRepo: contacts,
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        text: '',
        audience: PostAudience.allFriends(),
        mediaDrafts: const [
          PostMediaDraft(localFilePath: '/tmp/photo.jpg', mime: 'image/jpeg'),
        ],
      );

      expect(result, SendPostResult.success);
      expect(created, isNotNull);
      final createdPost = created!;
      expect(createdPost.mediaDrafts, hasLength(1));
      expect(createdPost.post.mediaKind, 'image');
      expect(createdPost.post.media, isEmpty);
      expect(createdPost.post.deliveryStatus, 'sending');

      final storedPost = await posts.getPost(createdPost.post.id);
      expect(storedPost, isNotNull);
      expect(storedPost!.mediaKind, 'image');
      expect(storedPost.media, isEmpty);
      expect(
        await posts.loadPostMediaAttachments(createdPost.post.id),
        isEmpty,
      );
      final recovery = await posts.loadPostMediaUploadRecoveryItems(
        createdPost.post.id,
      );
      expect(recovery, hasLength(1));
      expect(recovery.single.postId, createdPost.post.id);
      expect(recovery.single.position, 0);
      expect(recovery.single.localFilePath, '/tmp/photo.jpg');
      expect(recovery.single.mime, 'image/jpeg');
      expect(recovery.single.kind, 'image');
    },
  );

  test(
    'prepareCreatedLocalPostMedia retains pending recovery without dropping the local skeleton when upload fails',
    () async {
      final (_, created) = await createLocalPost(
        postRepo: posts,
        contactRepo: contacts,
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        text: '',
        audience: PostAudience.allFriends(),
        mediaDrafts: const [
          PostMediaDraft(localFilePath: '/tmp/photo.jpg', mime: 'image/jpeg'),
        ],
      );

      final createdPost = created!;
      final (result, prepared) = await prepareCreatedLocalPostMedia(
        created: createdPost,
        postRepo: posts,
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
              return null;
            },
      );

      expect(result, SendPostResult.sendFailed);
      expect(prepared, isNotNull);
      final preparedPost = prepared!;
      expect(preparedPost.post.id, createdPost.post.id);
      expect(prepared.post.deliveryStatus, 'sending');
      expect(prepared.post.mediaKind, 'image');
      expect(prepared.post.media, isEmpty);

      final storedPost = await posts.getPost(createdPost.post.id);
      expect(storedPost, isNotNull);
      expect(storedPost!.deliveryStatus, 'sending');
      expect(storedPost.mediaKind, 'image');
      expect(storedPost.media, isEmpty);
      final recovery = await posts.loadPostMediaUploadRecoveryItems(
        createdPost.post.id,
      );
      expect(recovery, hasLength(1));
      expect(recovery.single.localFilePath, '/tmp/photo.jpg');
      expect(recovery.single.position, 0);
    },
  );

  test(
    'prepareCreatedLocalPostMedia clears partially uploaded attachments when a later upload fails',
    () async {
      final (_, created) = await createLocalPost(
        postRepo: posts,
        contactRepo: contacts,
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        text: '',
        audience: PostAudience.allFriends(),
        mediaDrafts: const [
          PostMediaDraft(localFilePath: '/tmp/photo-1.jpg', mime: 'image/jpeg'),
          PostMediaDraft(localFilePath: '/tmp/photo-2.jpg', mime: 'image/jpeg'),
        ],
      );

      var uploadCount = 0;
      final createdPost = created!;
      final (result, prepared) = await prepareCreatedLocalPostMedia(
        created: createdPost,
        postRepo: posts,
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
              uploadCount++;
              if (uploadCount == 2) {
                return null;
              }
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
                createdAt: '2026-03-15T10:20:00.000Z',
              );
            },
      );

      expect(result, SendPostResult.sendFailed);
      expect(prepared, isNotNull);
      expect(prepared!.post.deliveryStatus, 'sending');
      expect(prepared.post.mediaKind, 'image_carousel');
      expect(prepared.post.media, isEmpty);

      final storedPost = await posts.getPost(createdPost.post.id);
      expect(storedPost, isNotNull);
      expect(storedPost!.deliveryStatus, 'sending');
      expect(storedPost.mediaKind, 'image_carousel');
      expect(storedPost.media, isEmpty);
      expect(
        await posts.loadPostMediaAttachments(createdPost.post.id),
        isEmpty,
      );
      final recovery = await posts.loadPostMediaUploadRecoveryItems(
        createdPost.post.id,
      );
      expect(
        recovery.map((item) => item.localFilePath).toList(growable: false),
        <String>['/tmp/photo-1.jpg', '/tmp/photo-2.jpg'],
      );
      expect(
        recovery.map((item) => item.position).toList(growable: false),
        <int>[0, 1],
      );
    },
  );

  test(
    'prepareCreatedLocalPostMedia reloads persisted recovery drafts when CreatedLocalPost has no in-memory mediaDrafts',
    () async {
      final (_, created) = await createLocalPost(
        postRepo: posts,
        contactRepo: contacts,
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        text: '',
        audience: PostAudience.allFriends(),
        mediaDrafts: const [
          PostMediaDraft(localFilePath: '/tmp/photo.jpg', mime: 'image/jpeg'),
        ],
      );

      final restartedCreated = created!.copyWith(
        mediaDrafts: const <PostMediaDraft>[],
      );
      late String uploadedLocalFilePath;
      final (result, prepared) = await prepareCreatedLocalPostMedia(
        created: restartedCreated,
        postRepo: posts,
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
              uploadedLocalFilePath = localFilePath;
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
                createdAt: '2026-03-15T10:20:00.000Z',
              );
            },
      );

      expect(result, SendPostResult.success);
      expect(prepared, isNotNull);
      expect(uploadedLocalFilePath, '/tmp/photo.jpg_processed');
      expect(
        await posts.loadPostMediaUploadRecoveryItems(restartedCreated.post.id),
        isEmpty,
      );
    },
  );

  test(
    'createLocalPost persists upload recovery before a mid-create interruption can orphan the media skeleton',
    () async {
      final interruptedPosts = _ThrowOnRecipientSavePostRepository();

      await expectLater(
        () => createLocalPost(
          postRepo: interruptedPosts,
          contactRepo: contacts,
          senderPeerId: 'peer-alice',
          senderUsername: 'Alice',
          text: '',
          audience: PostAudience.allFriends(),
          mediaDrafts: const [
            PostMediaDraft(localFilePath: '/tmp/photo.jpg', mime: 'image/jpeg'),
          ],
        ),
        throwsA(isA<StateError>()),
      );

      final savedPostId = interruptedPosts.lastSavedPostId;
      expect(savedPostId, isNotNull);
      final savedPost = await interruptedPosts.getPost(savedPostId!);
      expect(savedPost, isNotNull);
      expect(savedPost!.mediaKind, 'image');
      expect(savedPost.media, isEmpty);

      final recovery = await interruptedPosts.loadPostMediaUploadRecoveryItems(
        savedPostId,
      );
      expect(recovery, hasLength(1));
      expect(recovery.single.postId, savedPostId);
      expect(recovery.single.localFilePath, '/tmp/photo.jpg');
      expect(recovery.single.position, 0);
    },
  );

  test(
    'media attachments are prepared before recipient fanout and then delivered with metadata',
    () async {
      final network = FakeP2PNetwork();
      final aliceService = FakeP2PService(
        peerId: 'peer-alice',
        network: network,
      );

      final (_, created) = await createLocalPost(
        postRepo: posts,
        contactRepo: contacts,
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        text: '',
        audience: PostAudience.allFriends(),
        mediaDrafts: const [
          PostMediaDraft(localFilePath: '/tmp/photo.jpg', mime: 'image/jpeg'),
        ],
      );

      expect(network.retrieveInbox('peer-bob'), isEmpty);

      final createdPost = created!;
      final (prepareResult, prepared) = await prepareCreatedLocalPostMedia(
        created: createdPost,
        postRepo: posts,
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
                createdAt: '2026-03-15T10:20:00.000Z',
              );
            },
      );

      expect(prepareResult, SendPostResult.success);
      expect(prepared, isNotNull);
      expect(prepared!.post.media, hasLength(1));
      expect(prepared.post.media.single.blobId, 'blob-1');
      expect(prepared.mediaDrafts, isEmpty);

      final (deliveryResult, deliveredPost) = await PostDeliveryRunner(
        bridge: FakeBridge(),
        p2pService: aliceService,
        postRepo: posts,
      ).execute(prepared);

      expect(deliveryResult, SendPostResult.success);
      expect(deliveredPost.deliveryStatus, 'sent');

      final inboxMessage =
          network.retrieveInbox('peer-bob').single['message'] as String;
      final payload = jsonDecode(inboxMessage) as Map<String, dynamic>;
      final inner =
          jsonDecode(
                (payload['encrypted'] as Map<String, dynamic>)['ciphertext']
                    as String,
              )
              as Map<String, dynamic>;
      final snapshot = inner['snapshot'] as Map<String, dynamic>;
      expect(snapshot['media_kind'], 'image');
      expect(snapshot['media'][0]['blob_id'], 'blob-1');
    },
  );
}

class _ThrowOnRecipientSavePostRepository extends InMemoryPostRepository {
  String? lastSavedPostId;

  @override
  Future<void> savePost(PostModel post) async {
    lastSavedPostId = post.id;
    await super.savePost(post);
  }

  @override
  Future<void> saveRecipientDelivery(PostRecipientDelivery delivery) async {
    throw StateError('simulated recipient persistence interruption');
  }
}
