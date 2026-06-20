abstract final class AppShellTab {
  static const String feed = 'feed';
  static const String orbit = 'orbit';

  /// Temporary visuals prototype tab (gated by `kOrbit2PrototypeEnabled`).
  static const String orbit2 = 'orbit2';

  static const Set<String> values = <String>{feed, orbit, orbit2};

  static bool isValid(String value) => values.contains(value);
}
