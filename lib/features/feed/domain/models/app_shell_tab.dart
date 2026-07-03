abstract final class AppShellTab {
  static const String feed = 'feed';
  static const String orbit = 'orbit';

  /// Temporary "One Circle" visuals prototype tab (gated by
  /// `kOrbit3PrototypeEnabled`).
  static const String orbit3 = 'orbit3';

  static const Set<String> values = <String>{feed, orbit, orbit3};

  static bool isValid(String value) => values.contains(value);
}
