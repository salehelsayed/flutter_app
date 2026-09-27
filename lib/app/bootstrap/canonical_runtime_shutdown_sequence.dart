import 'dart:async';

/// Time a live call gets to end before the Android canonical runtime stops.
///
/// The native host waits 5 s in total for the Dart shutdown reply
/// (`MainActivity.CANONICAL_RUNTIME_SHUTDOWN_TIMEOUT_MS`). The database close
/// that follows keeps its own 2 s bound, so this budget leaves room for both.
const Duration kCallShutdownBeforeRuntimeReleaseBudget = Duration(seconds: 2);

/// Orders Android canonical-runtime shutdown after call signaling shutdown.
///
/// When MainActivity is destroyed, the native `mknoon/canonical_runtime_shutdown`
/// request and the Dart `detached` lifecycle edge arrive together. Ending a
/// live call sends a terminate to the peer. That send reads the peer endpoint
/// from SQLCipher and leaves through the Go runtime. So the runtime must not
/// quiesce Go or close the database until the call shutdown settles (or its
/// budget runs out).
final class CanonicalRuntimeShutdownSequence {
  CanonicalRuntimeShutdownSequence({
    required Future<bool> Function() shutdownRuntime,
    this.callShutdownBudget = kCallShutdownBeforeRuntimeReleaseBudget,
  }) : _shutdownRuntime = shutdownRuntime;

  final Future<bool> Function() _shutdownRuntime;
  final Duration callShutdownBudget;
  Future<void> Function()? _shutdownCalls;

  /// Binds the call signaling shutdown once the call graph exists. Before
  /// that there is no call to end.
  void bindCallShutdown(Future<void> Function() shutdownCalls) {
    _shutdownCalls = shutdownCalls;
  }

  /// Returns whether the runtime released, exactly as the runtime reports it.
  Future<bool> shutdown() async {
    final shutdownCalls = _shutdownCalls;
    if (shutdownCalls != null) {
      try {
        await Future<void>.sync(shutdownCalls).timeout(callShutdownBudget);
      } catch (_) {
        // A failed or slow call shutdown must not keep the runtime (and the
        // retained engine) alive. The peer then ends the call on media loss.
      }
    }
    return _shutdownRuntime();
  }
}
