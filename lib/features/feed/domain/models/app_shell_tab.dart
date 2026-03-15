abstract final class AppShellTab {
  static const String feed = 'feed';
  static const String remember = 'remember';
  static const String posts = 'posts';
  static const String orbit = 'orbit';

  static const Set<String> values = <String>{feed, remember, posts, orbit};

  static bool isValid(String value) => values.contains(value);
}
