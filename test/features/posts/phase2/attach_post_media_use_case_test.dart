import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/video_process_result.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/features/posts/application/attach_post_media_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';

void main() {
  late InMemoryPostRepository posts;
  late FakeSecureKeyStore secureKeyStore;
  late FakeMediaFileManager mediaFileManager;

  setUp(() {
    posts = InMemoryPostRepository();
    secureKeyStore = FakeSecureKeyStore();
    mediaFileManager = FakeMediaFileManager();
  });

  tearDown(() {
    posts.dispose();
  });

  test(
    'builds allowedPeers from the persisted recipient set and image quality preference',
    () async {
      await secureKeyStore.write(
        ImageQualityPreference.storageKey,
        ImageQualityPreference.original.toStorageString(),
      );
      await posts.savePost(_post('post-1'));
      await posts.saveRecipientDelivery(_delivery('post-1', 'peer-bob'));
      await posts.saveRecipientDelivery(_delivery('post-1', 'peer-cara'));

      final compressedQualities = <int>[];
      final uploadCalls = <Map<String, Object?>>[];

      final imageProcessor = ImageProcessor(
        compressFile:
            ({
              required path,
              required quality,
              required keepExif,
              minWidth = 1920,
              minHeight = 1080,
            }) async {
              compressedQualities.add(quality);
              return XFile('${path}_processed');
            },
      );

      final (result, attachments) = await attachPostMedia(
        postId: 'post-1',
        postRepo: posts,
        secureKeyStore: secureKeyStore,
        imageProcessor: imageProcessor,
        mediaFileManager: mediaFileManager,
        drafts: const [
          PostMediaDraft(
            localFilePath: '/tmp/original.jpg',
            mime: 'image/jpeg',
            width: 1440,
            height: 1080,
          ),
        ],
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
              uploadCalls.add({
                'postId': postId,
                'localFilePath': localFilePath,
                'mime': mime,
                'allowedPeers': allowedPeers,
                'width': width,
                'height': height,
              });
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

      expect(result, AttachPostMediaResult.success);
      expect(compressedQualities, [100]);
      expect(attachments, hasLength(1));
      expect(
        uploadCalls.single['localFilePath'],
        '/tmp/original.jpg_processed',
      );
      expect(
        uploadCalls.single['allowedPeers'],
        containsAll(<String>['peer-alice', 'peer-bob', 'peer-cara']),
      );
      expect(await posts.loadPostMediaAttachments('post-1'), hasLength(1));
    },
  );

  test('uses the stored video quality preference for video drafts', () async {
    await secureKeyStore.write(
      ImageQualityPreference.videoStorageKey,
      ImageQualityPreference.compressed.toStorageString(),
    );
    await posts.savePost(_post('post-1'));
    await posts.saveRecipientDelivery(_delivery('post-1', 'peer-bob'));

    final videoCompressFlags = <bool>[];
    final imageProcessor = ImageProcessor(
      compressVideo: ({required path, required compress, onProgress}) async {
        videoCompressFlags.add(compress);
        return const VideoProcessResult(
          path: '/tmp/video_processed.mp4',
          width: 1280,
          height: 720,
          durationMs: 12_000,
        );
      },
    );

    final (result, attachments) = await attachPostMedia(
      postId: 'post-1',
      postRepo: posts,
      secureKeyStore: secureKeyStore,
      imageProcessor: imageProcessor,
      mediaFileManager: mediaFileManager,
      drafts: const [
        PostMediaDraft(
          localFilePath: '/tmp/input.mov',
          mime: 'video/quicktime',
        ),
      ],
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
              mediaId: 'media-video-1',
              postId: postId,
              blobId: 'blob-video-1',
              kind: 'video',
              mime: mime,
              sizeBytes: 999,
              width: width,
              height: height,
              durationMs: durationMs,
              localPath: 'post_media/$postId/blob-video-1.mov',
              downloadStatus: 'done',
              createdAt: '2026-03-15T10:20:00.000Z',
            );
          },
    );

    expect(result, AttachPostMediaResult.success);
    expect(videoCompressFlags, [isTrue]);
    expect(attachments.single.durationMs, 12_000);
  });

  test('preserves the selected order for multi-image posts', () async {
    await posts.savePost(_post('post-ordered'));
    await posts.saveRecipientDelivery(_delivery('post-ordered', 'peer-bob'));

    final imageProcessor = ImageProcessor(
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

    final (result, attachments) = await attachPostMedia(
      postId: 'post-ordered',
      postRepo: posts,
      secureKeyStore: secureKeyStore,
      imageProcessor: imageProcessor,
      drafts: const [
        PostMediaDraft(localFilePath: '/tmp/one.jpg', mime: 'image/jpeg'),
        PostMediaDraft(localFilePath: '/tmp/two.jpg', mime: 'image/jpeg'),
      ],
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
            final index = localFilePath.contains('one') ? 0 : 1;
            return PostMediaAttachmentModel(
              mediaId: 'media-$index',
              postId: postId,
              blobId: 'blob-$index',
              kind: 'image',
              mime: mime,
              sizeBytes: 100 + index,
              localPath: 'post_media/$postId/blob-$index.jpg',
              downloadStatus: 'done',
              createdAt: '2026-03-15T10:20:0${1 - index}.000Z',
            );
          },
    );

    expect(result, AttachPostMediaResult.success);
    expect(
      attachments.map((attachment) => attachment.blobId).toList(),
      <String>['blob-0', 'blob-1'],
    );
    expect(attachments.map((attachment) => attachment.position).toList(), <int>[
      0,
      1,
    ]);

    final stored = await posts.loadPostMediaAttachments('post-ordered');
    expect(stored.map((attachment) => attachment.blobId).toList(), <String>[
      'blob-0',
      'blob-1',
    ]);
  });
}

PostModel _post(String postId) {
  return PostModel(
    id: postId,
    eventId: 'evt-$postId',
    senderPeerId: 'peer-alice',
    authorPeerId: 'peer-alice',
    authorUsername: 'Alice',
    text: 'Need a ladder',
    audience: PostAudience.allFriends(),
    createdAt: '2026-03-15T10:15:30.000Z',
    visibleAt: '2026-03-15T10:15:30.000Z',
    expiresAt: '2026-03-18T10:15:30.000Z',
    isIncoming: false,
  );
}

PostRecipientDelivery _delivery(String postId, String recipientPeerId) {
  return PostRecipientDelivery(
    postId: postId,
    recipientPeerId: recipientPeerId,
    deliveryStatus: 'pending',
    lastAttemptAt: '2026-03-15T10:15:31.000Z',
    deliveryPath: 'pending',
    createdAt: '2026-03-15T10:15:31.000Z',
    updatedAt: '2026-03-15T10:15:31.000Z',
  );
}
