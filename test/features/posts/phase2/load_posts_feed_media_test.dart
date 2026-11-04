import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/posts/application/load_orbit_thoughts_use_case.dart';
import 'package:flutter_app/features/posts/application/load_posts_feed_use_case.dart';
import 'package:flutter_app/features/posts/application/load_own_thought_history_use_case.dart';
import 'package:flutter_app/features/posts/application/post_surface_hydrator.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_upload_recovery_item.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';

import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';

void main() {
  late InMemoryPostRepository posts;
  late FakeMediaFileManager mediaFileManager;

  setUp(() {
    posts = InMemoryPostRepository();
    mediaFileManager = FakeMediaFileManager();
  });

  tearDown(() {
    posts.dispose();
  });

  const localPhotoPath = 'post_media/own-pending/selected.png';

  Future<PostModel> storePendingPhoto(DateTime created) async {
    final post = PostModel(
      id: 'own-pending',
      eventId: 'evt-own-pending',
      senderPeerId: 'author',
      authorPeerId: 'author',
      authorUsername: 'Author',
      text: '',
      audience: PostAudience.allFriends(),
      createdAt: created.toIso8601String(),
      visibleAt: created.toIso8601String(),
      expiresAt: created.add(const Duration(hours: 24)).toIso8601String(),
      mediaKind: 'image',
      isIncoming: false,
      deliveryStatus: 'sending',
    );
    await posts.savePost(post);
    await posts.replacePostMediaUploadRecoveryItems(post.id, [
      PostMediaUploadRecoveryItem(
        postId: post.id,
        position: 0,
        localFilePath: localPhotoPath,
        mime: 'image/png',
        kind: 'image',
        createdAt: post.createdAt,
      ),
    ]);
    return post;
  }

  test(
    'expired own history hydrates local photos without making them live',
    () async {
      final now = DateTime.utc(2026, 11, 4, 12);
      final stored = await storePendingPhoto(
        now.subtract(const Duration(hours: 48)),
      );

      final history = await loadOwnThoughtHistory(
        postRepo: posts,
        historyLimit: 20,
        mediaFileManager: mediaFileManager,
        viewerPeerId: 'author',
        nowProvider: () => now,
      );

      expect(history.single.id, stored.id);
      expect(history.single.media, isEmpty);
      expect(
        history.single.localMediaSources.map((source) => source.localFilePath),
        [localPhotoPath],
      );
      expect(
        await LoadOrbitThoughtsUseCase(
          postRepo: posts,
          contactRepo: InMemoryContactRepository(),
          nowProvider: () => now,
        ).executeOwn(localPeerId: 'author'),
        isNull,
      );
      expect((await posts.getPost(stored.id))!.localMediaSources, isEmpty);
      expect(await posts.loadPostMediaAttachments(stored.id), isEmpty);
      final persisted = history.single.toMap();
      expect(jsonEncode(persisted), isNot(contains(localPhotoPath)));
      expect(PostModel.fromMap(persisted).localMediaSources, isEmpty);
    },
  );

  test('rehydration clears local previews when they no longer apply', () async {
    final stored = await storePendingPhoto(DateTime.utc(2026, 11, 4, 12));
    final projected = (await hydratePostSurfaceItems(
      postRepo: posts,
      posts: [stored],
      viewerPeerId: 'author',
    )).single;

    for (final changed in [
      projected.copyWith(isIncoming: true),
      projected.copyWith(mediaKind: 'none'),
    ]) {
      final refreshed = (await hydratePostSurfaceItems(
        postRepo: posts,
        posts: [changed],
        viewerPeerId: 'author',
      )).single;
      expect(refreshed.localMediaSources, isEmpty);
      expect(refreshed.media, isEmpty);
    }

    await posts.savePostMediaAttachment(
      PostMediaAttachmentModel(
        mediaId: 'completed-photo',
        postId: stored.id,
        blobId: 'uploaded-photo',
        kind: 'image',
        mime: 'image/jpeg',
        sizeBytes: 128,
        localPath: 'post_media/own-pending/completed.jpg',
        createdAt: stored.createdAt,
      ),
    );
    final completed = (await hydratePostSurfaceItems(
      postRepo: posts,
      posts: [projected],
      viewerPeerId: 'author',
    )).single;
    expect(completed.media.single.mediaId, 'completed-photo');
    expect(completed.localMediaSources, isEmpty);
  });

  test(
    'own history is newest first, expired only, and hydrates retained media',
    () async {
      final now = DateTime.utc(2026, 10, 21, 9);
      for (final entry in {
        'own-older': 48,
        'own-newer': 25,
        'own-live': 1,
        'friend-expired': 26,
      }.entries) {
        final created = now.subtract(Duration(hours: entry.value));
        await posts.savePost(
          PostModel(
            id: entry.key,
            eventId: 'evt-${entry.key}',
            senderPeerId: 'author',
            authorPeerId: 'author',
            authorUsername: 'Author',
            text: entry.key,
            audience: PostAudience.allFriends(),
            createdAt: created.toIso8601String(),
            visibleAt: created.toIso8601String(),
            expiresAt: created.add(const Duration(hours: 24)).toIso8601String(),
            isIncoming: entry.key == 'friend-expired',
          ),
        );
      }
      await posts.savePostMediaAttachment(
        PostMediaAttachmentModel(
          mediaId: 'history-photo',
          postId: 'own-newer',
          blobId: 'history-blob',
          kind: 'image',
          mime: 'image/jpeg',
          sizeBytes: 128,
          localPath: 'post_media/own-newer/image.jpg',
          downloadStatus: 'done',
          createdAt: now.subtract(const Duration(hours: 25)).toIso8601String(),
        ),
      );

      final history = await loadOwnThoughtHistory(
        postRepo: posts,
        historyLimit: 20,
        mediaFileManager: mediaFileManager,
        viewerPeerId: 'author',
        nowProvider: () => now,
      );
      final newestOnly = await loadOwnThoughtHistory(
        postRepo: posts,
        historyLimit: 1,
        nowProvider: () => now,
      );

      expect(posts.expiredOwnPageLimits, [20, 1]);
      expect(history.map((post) => post.id), ['own-newer', 'own-older']);
      expect(newestOnly.map((post) => post.id), ['own-newer']);
      expect(history.first.media, hasLength(1));
      expect(history.first.mediaKind, 'image');
      expect(
        history.first.media.single.localPath,
        endsWith('test_docs/post_media/own-newer/image.jpg'),
      );
      expect(history.first.media.single.downloadStatus, 'done');
    },
  );

  test(
    'restores hydrated post media with resolved local paths after reload',
    () async {
      await posts.savePost(
        PostModel(
          id: 'post-1',
          eventId: 'evt-post-1',
          senderPeerId: 'peer-bob',
          authorPeerId: 'peer-bob',
          authorUsername: 'Bob',
          text: 'Photo post',
          audience: PostAudience.allFriends(),
          createdAt: '2026-03-15T10:15:30.000Z',
          visibleAt: '2026-03-15T10:15:30.000Z',
          expiresAt: '2026-03-18T10:15:30.000Z',
          mediaKind: 'image',
        ),
      );
      await posts.savePostMediaAttachment(
        const PostMediaAttachmentModel(
          mediaId: 'media-1',
          postId: 'post-1',
          blobId: 'blob-1',
          kind: 'image',
          mime: 'image/jpeg',
          sizeBytes: 248120,
          width: 1440,
          height: 1080,
          localPath: 'post_media/post-1/blob-1.jpg',
          downloadStatus: 'done',
          createdAt: '2026-03-15T10:20:00.000Z',
        ),
      );

      final feed = await loadPostsFeed(
        postRepo: posts,
        mediaFileManager: mediaFileManager,
      );

      expect(feed, hasLength(1));
      expect(feed.single.media, hasLength(1));
      expect(
        feed.single.media.single.localPath,
        endsWith('test_docs/post_media/post-1/blob-1.jpg'),
      );
    },
  );
}
