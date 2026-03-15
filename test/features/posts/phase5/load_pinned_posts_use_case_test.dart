import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/posts/application/dismiss_pin_use_case.dart';
import 'package:flutter_app/features/posts/application/load_pinned_posts_use_case.dart';
import 'package:flutter_app/features/posts/application/load_posts_feed_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_pin_state_model.dart';

import '../../../shared/fakes/in_memory_post_repository.dart';
import 'support/post_pin_fixtures.dart';

void main() {
  late InMemoryPostRepository posts;

  setUp(() {
    posts = InMemoryPostRepository();
  });

  tearDown(() {
    posts.dispose();
  });

  Future<void> seedActivePin({
    required String createdAt,
    String effectiveAt = '2026-03-15T11:20:00.000Z',
  }) async {
    await posts.savePost(
      postPinBasePost(
        createdAt: createdAt,
        keepAvailable: true,
      ),
    );
    await posts.savePostPinState(
      PostPinStateModel(
        postId: 'post-1',
        eventId: 'evt-pin-1',
        pinEventId: 'pin-evt-1',
        senderPeerId: 'peer-bob',
        state: 'active',
        effectiveAt: effectiveAt,
        pinnedAt: effectiveAt,
        createdAt: effectiveAt,
      ),
    );
  }

  test('loads active pins and excludes locally dismissed pins', () async {
    await seedActivePin(createdAt: '2026-03-15T10:15:30.000Z');

    var pinned = await loadPinnedPosts(postRepo: posts);
    expect(pinned.map((post) => post.id), <String>['post-1']);

    await dismissPin(postRepo: posts, postId: 'post-1');

    pinned = await loadPinnedPosts(postRepo: posts);
    expect(pinned, isEmpty);
  });

  test('keeps pinned posts in the normal feed during the first 24 hours', () async {
    await seedActivePin(createdAt: '2026-03-15T10:15:30.000Z');

    final feed = await loadPostsFeed(
      postRepo: posts,
      nowProvider: () => DateTime.parse('2026-03-16T09:00:00.000Z'),
    );
    final pinned = await loadPinnedPosts(postRepo: posts);

    expect(feed.map((post) => post.id), contains('post-1'));
    expect(pinned.map((post) => post.id), <String>['post-1']);
  });

  test('moves old keep-available posts out of the normal feed but keeps them pinned', () async {
    await seedActivePin(createdAt: '2026-03-14T08:15:30.000Z');

    final feed = await loadPostsFeed(
      postRepo: posts,
      nowProvider: () => DateTime.parse('2026-03-15T12:30:00.000Z'),
    );
    final pinned = await loadPinnedPosts(postRepo: posts);

    expect(feed.map((post) => post.id), isNot(contains('post-1')));
    expect(pinned.map((post) => post.id), <String>['post-1']);
  });
}
