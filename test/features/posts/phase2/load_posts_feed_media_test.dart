import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/posts/application/load_posts_feed_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';

import '../../../shared/fakes/fake_media_file_manager.dart';
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
