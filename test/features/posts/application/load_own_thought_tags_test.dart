import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/posts/application/load_own_thought_tags_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';

import '../../../shared/fakes/in_memory_post_repository.dart';

final _now = DateTime.utc(2026, 11, 4, 12);

PostModel _post(
  String id,
  String text, {
  required Duration age,
  bool incoming = false,
}) {
  final created = _now.subtract(age);
  return PostModel(
    id: id,
    eventId: 'event-$id',
    senderPeerId: incoming ? 'friend' : 'me',
    authorPeerId: incoming ? 'friend' : 'me',
    authorUsername: incoming ? 'Friend' : 'Me',
    text: text,
    audience: PostAudience.allFriends(),
    createdAt: created.toIso8601String(),
    visibleAt: created.toIso8601String(),
    expiresAt: created.add(const Duration(hours: 24)).toIso8601String(),
    isIncoming: incoming,
  );
}

void main() {
  test('every tag you used, newest first, with when you last used it and '
      'how you last wrote it', () async {
    final posts = InMemoryPostRepository();
    addTearDown(posts.dispose);
    await posts.savePost(
      _post('a', 'frost #Walks', age: const Duration(days: 21)),
    );
    await posts.savePost(
      _post('b', 'coffee #coffee #mornings', age: const Duration(days: 9)),
    );
    await posts.savePost(
      _post('c', 'the hill #walks', age: const Duration(days: 2)),
    );
    await posts.savePost(
      _post('d', 'their #secret', age: const Duration(days: 1), incoming: true),
    );
    final live = _post('e', 'reef #sea', age: const Duration(hours: 3));
    await posts.savePost(live);

    final tags = await loadOwnThoughtTags(
      postRepo: posts,
      live: live,
      nowProvider: () => _now,
    );

    expect(
      [for (final tag in tags) tag.key],
      ['sea', 'walks', 'coffee', 'mornings'],
    );
    expect(
      [for (final tag in tags) tag.label],
      ['#sea', '#walks', '#coffee', '#mornings'],
    );
    expect(tags[1].lastUsed, _now.subtract(const Duration(days: 2)));
  });

  test('no tags, nothing to list', () async {
    final posts = InMemoryPostRepository();
    addTearDown(posts.dispose);
    await posts.savePost(
      _post('a', 'no tags here', age: const Duration(days: 2)),
    );
    expect(
      await loadOwnThoughtTags(
        postRepo: posts,
        live: null,
        nowProvider: () => _now,
      ),
      isEmpty,
    );
  });
}
