import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/posts/application/sweep_expired_posts_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';

import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';

// BL-14: a viewer's clock set 25 h ahead must not permanently delete a
// friend's Thought that is still live by real time.
final _created = DateTime.utc(2026, 11, 10, 9);

PostModel _friendThought() => PostModel(
  id: 'friend-live',
  eventId: 'evt-friend-live',
  senderPeerId: 'peer-bob',
  authorPeerId: 'peer-bob',
  authorUsername: 'Bob',
  text: 'Still live by real time',
  audience: PostAudience.allFriends(),
  createdAt: _created.toIso8601String(),
  visibleAt: _created.toIso8601String(),
  expiresAt: _created.add(const Duration(hours: 24)).toIso8601String(),
);

PostMediaAttachmentModel _media() => PostMediaAttachmentModel(
  mediaId: 'media-friend-live',
  postId: 'friend-live',
  blobId: 'blob-friend-live',
  kind: 'image',
  mime: 'image/jpeg',
  sizeBytes: 128,
  localPath: 'post_media/friend-live/image.jpg',
  downloadStatus: 'done',
  createdAt: _created.toIso8601String(),
);

void main() {
  late InMemoryPostRepository posts;
  late FakeMediaFileManager files;

  setUp(() async {
    posts = InMemoryPostRepository();
    files = FakeMediaFileManager();
    await posts.savePost(_friendThought());
    await posts.savePostMediaAttachment(_media());
  });

  tearDown(() => posts.dispose());

  test(
    "a sweep under a clock 25 h ahead keeps a friend's live Thought and media",
    () async {
      final realNow = _created.add(const Duration(hours: 1));
      final wrongNow = realNow.add(const Duration(hours: 25));

      final deleted = await sweepExpiredPosts(
        postRepo: posts,
        mediaFileManager: files,
        nowProvider: () => wrongNow,
      );

      expect(deleted, isEmpty);
      expect(files.deletedPostIds, isEmpty);
      expect((await posts.getPost('friend-live'))?.text, 'Still live by real time');
      expect(await posts.loadPostMediaAttachments('friend-live'), hasLength(1));
    },
  );

  test(
    "a friend's Thought is deleted once its expiry is 48 h in the past",
    () async {
      final expiry = _created.add(const Duration(hours: 24));

      final early = await sweepExpiredPosts(
        postRepo: posts,
        mediaFileManager: files,
        nowProvider: () => expiry.add(
          const Duration(hours: 48) - const Duration(milliseconds: 1),
        ),
      );
      expect(early, isEmpty);

      final late = await sweepExpiredPosts(
        postRepo: posts,
        mediaFileManager: files,
        nowProvider: () => expiry.add(const Duration(hours: 48)),
      );
      expect(late, ['friend-live']);
      expect(await posts.getPost('friend-live'), isNull);
      expect(files.deletedPostIds, ['friend-live']);
    },
  );

  test('a sweep reports each hidden Thought it keeps', () async {
    final kept = <String>[];

    await sweepExpiredPosts(
      postRepo: posts,
      mediaFileManager: files,
      nowProvider: () => _created.add(const Duration(hours: 25)),
      onExpiredKept: kept.add,
    );

    expect(kept, ['friend-live']);
    expect(await posts.getPost('friend-live'), isNotNull);
  });
}
