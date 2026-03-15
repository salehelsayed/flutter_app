import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/video_process_result.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/features/posts/application/attach_post_media_use_case.dart';
import 'package:flutter_app/features/posts/application/load_posts_feed_use_case.dart';
import 'package:flutter_app/features/posts/application/post_comment_listener.dart';
import 'package:flutter_app/features/posts/application/post_listener.dart';
import 'package:flutter_app/features/posts/application/post_reaction_listener.dart';
import 'package:flutter_app/features/posts/application/send_post_comment_reaction_use_case.dart';
import 'package:flutter_app/features/posts/application/send_post_comment_use_case.dart';
import 'package:flutter_app/features/posts/application/send_post_reaction_use_case.dart';
import 'package:flutter_app/features/posts/application/send_post_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';
import 'package:image_picker/image_picker.dart';

import '../test/core/secure_storage/fake_secure_key_store.dart';
import '../test/shared/fakes/fake_media_file_manager.dart';
import '../test/shared/fakes/fake_p2p_network.dart';
import '../test/shared/fakes/fake_p2p_service_integration.dart';
import '../test/shared/fakes/in_memory_contact_repository.dart';
import '../test/shared/fakes/in_memory_post_repository.dart';

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
  testWidgets(
    'offline comment replay and duplicate hearts converge through the receiver recipient set',
    (tester) async {
      final network = FakeP2PNetwork();
      final aliceService = FakeP2PService(
        peerId: 'peer-alice',
        network: network,
      );
      final bobService = FakeP2PService(peerId: 'peer-bob', network: network);
      final caraService = FakeP2PService(peerId: 'peer-cara', network: network);

      final aliceContacts = InMemoryContactRepository()
        ..addTestContact(_contact('peer-bob', 'Bob'))
        ..addTestContact(_contact('peer-cara', 'Cara'));
      final bobContacts = InMemoryContactRepository()
        ..addTestContact(_contact('peer-alice', 'Alice'))
        ..addTestContact(_contact('peer-cara', 'Cara'));
      final caraContacts = InMemoryContactRepository()
        ..addTestContact(_contact('peer-alice', 'Alice'))
        ..addTestContact(_contact('peer-bob', 'Bob'));

      final alicePosts = InMemoryPostRepository();
      final bobPosts = InMemoryPostRepository();
      final caraPosts = InMemoryPostRepository();

      final bobRouter = IncomingMessageRouter(p2pService: bobService)..start();
      final caraRouter = IncomingMessageRouter(p2pService: caraService)..start();
      final aliceRouter = IncomingMessageRouter(p2pService: aliceService)
        ..start();
      final bobPostListener = PostListener(
        postCreateStream: bobRouter.postCreateStream,
        postRepo: bobPosts,
        contactRepo: bobContacts,
      )..start();
      final caraPostListener = PostListener(
        postCreateStream: caraRouter.postCreateStream,
        postRepo: caraPosts,
        contactRepo: caraContacts,
      )..start();
      final aliceCommentListener = PostCommentListener(
        postCommentStream: aliceRouter.postCommentStream,
        postRepo: alicePosts,
        contactRepo: aliceContacts,
      )..start();
      final caraCommentListener = PostCommentListener(
        postCommentStream: caraRouter.postCommentStream,
        postRepo: caraPosts,
        contactRepo: caraContacts,
      )..start();
      final aliceReactionListener = PostReactionListener(
        postReactionStream: aliceRouter.postReactionStream,
        postCommentReactionStream: aliceRouter.postCommentReactionStream,
        postRepo: alicePosts,
        contactRepo: aliceContacts,
      )..start();

      addTearDown(() {
        bobPostListener.dispose();
        caraPostListener.dispose();
        aliceCommentListener.dispose();
        caraCommentListener.dispose();
        aliceReactionListener.dispose();
        bobRouter.dispose();
        caraRouter.dispose();
        aliceRouter.dispose();
        alicePosts.dispose();
        bobPosts.dispose();
        caraPosts.dispose();
      });

      final (sendResult, post) = await sendPost(
        p2pService: aliceService,
        postRepo: alicePosts,
        contactRepo: aliceContacts,
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        text: 'Need a ladder',
        audience: PostAudience.allFriends(),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(sendResult, SendPostResult.success);
      expect(post, isNotNull);
      final sentPost = post!;
      expect(await bobPosts.getRecipientDeliveries(sentPost.id), hasLength(2));

      aliceService.setOnline(false);
      final (commentResult, comment) = await sendPostComment(
        p2pService: bobService,
        postRepo: bobPosts,
        contactRepo: bobContacts,
        postId: sentPost.id,
        senderPeerId: 'peer-bob',
        senderUsername: 'Bob',
        body: 'I can lend one.',
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(commentResult, SendPostCommentResult.success);
      expect(comment, isNotNull);
      expect(network.inboxCount('peer-alice'), 1);
      expect(await caraPosts.loadComments(sentPost.id), hasLength(1));

      aliceService.setOnline(true);
      await aliceService.drainOfflineInbox();
      await tester.pump(const Duration(milliseconds: 50));

      expect(await alicePosts.loadComments(sentPost.id), hasLength(1));
      network.duplicateOnDeliver = true;

      final reactionResult = await sendPostReaction(
        p2pService: bobService,
        postRepo: bobPosts,
        contactRepo: bobContacts,
        postId: sentPost.id,
        senderPeerId: 'peer-bob',
        isActive: true,
      );
      final commentReactionResult = await sendPostCommentReaction(
        p2pService: bobService,
        postRepo: bobPosts,
        contactRepo: bobContacts,
        postId: sentPost.id,
        commentId: comment!.id,
        senderPeerId: 'peer-bob',
        isActive: true,
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(reactionResult.$1, SendPostReactionResult.success);
      expect(commentReactionResult.$1, SendPostCommentReactionResult.success);
      expect(await alicePosts.loadPostReactions(sentPost.id), hasLength(1));
      expect(await alicePosts.loadCommentReactions(comment.id), hasLength(1));
    },
  );

  testWidgets('image, video, and voice media posts survive fake reload', (
    tester,
  ) async {
    final network = FakeP2PNetwork();
    final aliceService = FakeP2PService(peerId: 'peer-alice', network: network);
    final contacts = InMemoryContactRepository()
      ..addTestContact(_contact('peer-bob', 'Bob'));
    final posts = InMemoryPostRepository();
    final secureKeyStore = FakeSecureKeyStore();
    final mediaFileManager = FakeMediaFileManager();

    addTearDown(posts.dispose);
    await secureKeyStore.write(
      ImageQualityPreference.storageKey,
      ImageQualityPreference.original.toStorageString(),
    );

    final cases = <({
      String expectedKind,
      PostMediaDraft draft,
      PostMediaAttachmentModel attachment,
    })>[
      (
        expectedKind: 'image',
        draft: const PostMediaDraft(
          localFilePath: '/tmp/image.jpg',
          mime: 'image/jpeg',
          width: 1440,
          height: 1080,
        ),
        attachment: const PostMediaAttachmentModel(
          mediaId: 'media-image',
          postId: '',
          blobId: 'blob-image',
          kind: 'image',
          mime: 'image/jpeg',
          sizeBytes: 248120,
          width: 1440,
          height: 1080,
          localPath: '',
          downloadStatus: 'done',
          createdAt: '2026-03-15T10:20:00.000Z',
        ),
      ),
      (
        expectedKind: 'video',
        draft: const PostMediaDraft(
          localFilePath: '/tmp/video.mp4',
          mime: 'video/mp4',
          width: 1280,
          height: 720,
          durationMs: 125000,
        ),
        attachment: const PostMediaAttachmentModel(
          mediaId: 'media-video',
          postId: '',
          blobId: 'blob-video',
          kind: 'video',
          mime: 'video/mp4',
          sizeBytes: 512000,
          width: 1280,
          height: 720,
          durationMs: 125000,
          localPath: '',
          downloadStatus: 'done',
          createdAt: '2026-03-15T10:21:00.000Z',
        ),
      ),
      (
        expectedKind: 'voice',
        draft: const PostMediaDraft(
          localFilePath: '/tmp/voice.m4a',
          mime: 'audio/mp4',
          durationMs: 5000,
          waveform: [0.1, 0.5, 0.9],
        ),
        attachment: const PostMediaAttachmentModel(
          mediaId: 'media-voice',
          postId: '',
          blobId: 'blob-voice',
          kind: 'voice',
          mime: 'audio/mp4',
          sizeBytes: 48000,
          durationMs: 5000,
          waveform: [0.1, 0.5, 0.9],
          localPath: '',
          downloadStatus: 'done',
          createdAt: '2026-03-15T10:22:00.000Z',
        ),
      ),
    ];

    for (final mediaCase in cases) {
      final (result, post) = await sendPost(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        text: mediaCase.expectedKind == 'voice'
            ? ''
            : '${mediaCase.expectedKind} post',
        audience: PostAudience.allFriends(),
        mediaDrafts: [mediaCase.draft],
        secureKeyStore: secureKeyStore,
        imageProcessor: ImageProcessor(
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
          compressVideo:
              ({required path, required compress, onProgress}) async {
                return VideoProcessResult(
                  path: '${path}_processed',
                  width: mediaCase.draft.width,
                  height: mediaCase.draft.height,
                  durationMs: mediaCase.draft.durationMs,
                );
              },
        ),
        mediaFileManager: mediaFileManager,
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
              return mediaCase.attachment.copyWith(
                postId: postId,
                localPath: 'post_media/$postId/${mediaCase.attachment.blobId}',
                width: width,
                height: height,
                durationMs: durationMs,
                waveform: waveform,
              );
            },
      );
      await tester.pump(const Duration(milliseconds: 20));

      expect(result, SendPostResult.success);
      expect(post, isNotNull);

      final feed = await loadPostsFeed(
        postRepo: posts,
        mediaFileManager: mediaFileManager,
        viewerPeerId: 'peer-alice',
      );
      final restoredPost = feed.firstWhere((feedPost) => feedPost.id == post!.id);
      expect(restoredPost.mediaKind, mediaCase.expectedKind);
      expect(
        restoredPost.media.single.localPath,
        startsWith('/tmp/test_docs/'),
      );

      final payload = jsonDecode(
        network.retrieveInbox('peer-bob').single['message'] as String,
      ) as Map<String, dynamic>;
      final snapshot = payload['payload']['snapshot'] as Map<String, dynamic>;
      expect(snapshot['media_kind'], mediaCase.expectedKind);
      expect(snapshot['media'], hasLength(1));
    }
  });
}
