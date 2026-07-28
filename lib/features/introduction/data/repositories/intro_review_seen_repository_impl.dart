import '../../domain/repositories/intro_review_seen_repository.dart';

class IntroReviewSeenRepositoryImpl implements IntroReviewSeenRepository {
  final Future<Set<String>> Function() dbLoadSeenKeys;
  final Future<void> Function(Set<String> itemKeys, DateTime seenAt)
  dbMarkAllSeen;

  IntroReviewSeenRepositoryImpl({
    required this.dbLoadSeenKeys,
    required this.dbMarkAllSeen,
  });

  @override
  Future<Set<String>> loadSeenKeys() => dbLoadSeenKeys();

  @override
  Future<void> markAllSeen(Set<String> itemKeys) async {
    if (itemKeys.isEmpty) return;
    await dbMarkAllSeen(itemKeys, DateTime.now().toUtc());
  }
}
