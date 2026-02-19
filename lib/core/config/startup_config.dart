/// Feature flags for startup behavior.
class StartupConfig {
  StartupConfig._();

  /// When true, P2P startup is deferred until after the first frame.
  /// When false, P2P starts as soon as route navigation completes (legacy behavior).
  static bool deferredStartupMode = true;
}
