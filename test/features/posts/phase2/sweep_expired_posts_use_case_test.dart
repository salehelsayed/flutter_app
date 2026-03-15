import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/posts/application/sweep_expired_posts_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';

import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';

PostModel _post({
  required String id,
  required String expiresAt,
}) {
  return PostModel(
    id: id,
    eventId: 'evt-$id',
    senderPeerId: 'peer-bob',
    authorPeerId: 'peer-bob',
    authorUsername: 'Bob',
    text: 'Need a ladder',
    audience: PostAudience.allFriends(),
    createdAt: '2026-03-15T10:15:30.000Z',
    visibleAt: '2026-03-15T10:15:30.000Z',
    expiresAt: expiresAt,
  );
}

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

  test('sweeps expired posts and removes hydrated attachment state', () async {
    await posts.savePost(
      _post(id: 'post-expired', expiresAt: '2026-03-16T08:00:00.000Z'),
    );
    await posts.savePost(
      _post(id: 'post-fresh', expiresAt: '2026-03-19T08:00:00.000Z'),
    );
    await posts.savePostMediaAttachment(
      const PostMediaAttachmentModel(
        mediaId: 'media-1',
        postId: 'post-expired',
        blobId: 'blob-1',
        kind: 'image',
        mime: 'image/jpeg',
        sizeBytes: 128,
        localPath: 'post_media/post-expired/blob-1',
        downloadStatus: 'done',
        createdAt: '2026-03-15T10:20:00.000Z',
      ),
    );

    final deletedPostIds = await sweepExpiredPosts(
      postRepo: posts,
      mediaFileManager: mediaFileManager,
      nowProvider: () => DateTime.parse('2026-03-16T09:00:00.000Z'),
    );

    expect(deletedPostIds, ['post-expired']);
    expect(await posts.getPost('post-expired'), isNull);
    expect(await posts.loadPostMediaAttachments('post-expired'), isEmpty);
    expect(await posts.getPost('post-fresh'), isNotNull);
    expect(mediaFileManager.deletedPostIds, ['post-expired']);
  });
}
