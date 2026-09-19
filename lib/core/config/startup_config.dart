/// Feature flags for startup behavior.
class StartupConfig {
  StartupConfig._();

  /// When true, qualified P2P startup yields the current synchronous work.
  /// When false, it starts immediately; neither mode waits for a rendered frame.
  static bool deferredStartupMode = true;
}
