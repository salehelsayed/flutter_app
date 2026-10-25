import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/utils/thought_lifetime.dart';
import 'package:flutter_app/features/posts/application/early_thought_retractions.dart';

void main() {
  final created = DateTime.utc(2026, 10, 25, 9);
  late DateTime now;
  late EarlyThoughtRetractions retractions;

  setUp(() {
    now = created.add(const Duration(minutes: 5));
    retractions = EarlyThoughtRetractions(nowProvider: () => now, capacity: 2);
  });

  test("rejects the author's thought until it would have expired", () {
    retractions.record(
      postId: 'p1',
      retractedBy: 'bob',
      postCreatedAt: created,
    );

    expect(retractions.rejects(postId: 'p1', authorPeerId: 'bob'), isTrue);
    expect(retractions.rejects(postId: 'p1', authorPeerId: 'cat'), isFalse);
    expect(retractions.rejects(postId: 'p2', authorPeerId: 'bob'), isFalse);

    now = ThoughtLifetime.expiresAt(created);
    expect(retractions.rejects(postId: 'p1', authorPeerId: 'bob'), isFalse);
  });

  test('a retraction for a thought already past its lifetime is not kept', () {
    retractions.record(
      postId: 'p1',
      retractedBy: 'bob',
      postCreatedAt: now.subtract(ThoughtLifetime.duration),
    );

    expect(retractions.rejects(postId: 'p1', authorPeerId: 'bob'), isFalse);
  });

  test('keeps the newest retractions once full', () {
    for (final postId in ['p1', 'p2', 'p3']) {
      retractions.record(
        postId: postId,
        retractedBy: 'bob',
        postCreatedAt: created,
      );
    }

    expect(retractions.rejects(postId: 'p1', authorPeerId: 'bob'), isFalse);
    expect(retractions.rejects(postId: 'p2', authorPeerId: 'bob'), isTrue);
    expect(retractions.rejects(postId: 'p3', authorPeerId: 'bob'), isTrue);
  });
}
