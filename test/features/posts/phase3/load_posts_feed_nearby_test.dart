import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/posts/application/load_posts_feed_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';

import '../../../shared/fakes/in_memory_post_repository.dart';

void main() {
  late InMemoryPostRepository posts;

  setUp(() {
    posts = InMemoryPostRepository();
  });

  tearDown(() {
    posts.dispose();
  });

  test('builds nearby distance labels from stored nearby distance', () async {
    await posts.savePost(
      PostModel(
        id: 'post-nearby',
        eventId: 'evt-post-nearby',
        senderPeerId: 'peer-bob',
        authorPeerId: 'peer-bob',
        authorUsername: 'Bob',
        text: 'Lost dog near the bridge.',
        audience: PostAudience.peopleNearby(radiusM: 500),
        createdAt: '2026-03-15T10:15:30.000Z',
        visibleAt: '2026-03-15T10:15:30.000Z',
        expiresAt: '2026-03-18T10:15:30.000Z',
        nearbyDistanceM: 474,
      ),
    );

    final feed = await loadPostsFeed(postRepo: posts);

    expect(feed, hasLength(1));
    expect(feed.single.nearbyDistanceLabel, '450m away');
  });
}
