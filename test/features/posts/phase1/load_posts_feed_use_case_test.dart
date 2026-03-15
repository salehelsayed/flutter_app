import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/posts/application/load_posts_feed_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';

import '../../../shared/fakes/in_memory_post_repository.dart';

void main() {
  late InMemoryPostRepository postRepo;

  setUp(() {
    postRepo = InMemoryPostRepository();
  });

  tearDown(() {
    postRepo.dispose();
  });

  test('returns feed ordered by visible_at descending', () async {
    await postRepo.savePost(_post(id: 'post-1', visibleAt: '2026-03-15T09:00:00.000Z'));
    await postRepo.savePost(_post(id: 'post-2', visibleAt: '2026-03-15T11:00:00.000Z'));

    final feed = await loadPostsFeed(postRepo: postRepo);

    expect(feed.map((post) => post.id), orderedEquals(<String>['post-2', 'post-1']));
  });
}

PostModel _post({
  required String id,
  required String visibleAt,
}) {
  return PostModel(
    id: id,
    eventId: 'evt-$id',
    senderPeerId: 'peer-a',
    authorPeerId: 'peer-a',
    authorUsername: 'Alice',
    text: 'hello',
    audience: PostAudience.allFriends(),
    createdAt: visibleAt,
    visibleAt: visibleAt,
    expiresAt: '2026-03-18T10:15:30.000Z',
  );
}
