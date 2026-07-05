abstract class IntroReviewSeenRepository {
  Future<Set<String>> loadSeenKeys();

  Future<void> markAllSeen(Set<String> itemKeys);
}
