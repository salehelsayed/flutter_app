abstract final class AppShellTab {
  static const String feed = 'feed';
  static const String orbit = 'orbit';

  static const Set<String> values = <String>{feed, orbit};

  static bool isValid(String value) => values.contains(value);
}
